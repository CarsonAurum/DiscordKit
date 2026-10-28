// File: Sources/DiscordFoundationTransport/FoundationHTTPTransport.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(Darwin)
import DiscordLogging
import DiscordTransport
import Foundation

/// Send-once Apple HTTP adapter backed by an explicitly owned ephemeral URLSession.
///
/// No redirects, automatic application retries, credential persistence, cookies or
/// caching are enabled. Uploads are bounded collections; response bytes are pulled
/// on demand in bounded chunks. Foundation may internally buffer network data and
/// combines duplicate response headers, so this adapter cannot promise raw header
/// fidelity or an exact Foundation/socket memory ceiling. Use the NIO adapter when
/// those properties are required. Call `close()` when this adapter's owner ends.
public struct FoundationHTTPTransport: HTTPTransport, TransportResource {
    private let owner: FoundationSession
    public let configuration: FoundationTransportConfiguration

    /// Creates a session without making requests or sharing persisted credentials.
    /// - Parameter configuration: Validated per-operation and aggregate bounds.
    public init(configuration: FoundationTransportConfiguration) {
        self.configuration = configuration
        owner = FoundationSession(configuration: configuration)
    }

    /// Sends one request and transfers a single-consumer response body to its caller.
    ///
    /// Admission includes upload collection and the entire transferred body lifetime.
    /// The original context deadline also applies to later body reads. Abandoning a
    /// response requires explicit body closure. Redirect statuses are returned as-is.
    /// Foundation normalizes response header order, casing and repeated field values.
    /// HEAD and 304 Content-Length values describe the selected representation, so
    /// they do not trigger the advertised body-length check. Every consumed byte
    /// remains subject to the configured response limit, regardless of metadata.
    /// - Parameters:
    ///   - request: HTTP(S) request with valid token syntax and unique header names.
    ///     This execution closes its body on every success and failure path.
    ///   - context: Injected clock, cancellation and inclusive optional deadline.
    /// - Returns: HTTP status and normalized metadata with an owned bounded pull body.
    /// - Throws: Cancellation, deadline, syntax, admission, body limit, closure or a
    ///   redacted numeric native failure. Mutations are never replayed by this adapter.
    public func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
    where C.Duration == Duration {
        DiscordLog.makeLogger("foundation.http").trace("Starting Foundation HTTP exchange", metadata: ["dk.event": "foundation.http.execute"])
        var identifier: UUID?
        do {
            try context.check()
            let platform = try foundationRequest(request, webSocket: false)
            let reserved = try await owner.reserve { await request.body?.close() }
            identifier = reserved
            DiscordLog.makeLogger("foundation.admission").trace("Foundation operation slot reserved", metadata: ["dk.event": "foundation.admission.reserved"])
            let owner = self.owner
            let configuration = self.configuration
            let result = try await context.run {
                var upload = Data()
                if let source = request.body {
                    do {
                        for try await chunk in source {
                            try Task.checkCancellation()
                            guard chunk.count <= configuration.maximumRequestBodyBytes - upload.count else {
                                throw FoundationTransportFailure.bodyLimitExceeded(limit: configuration.maximumRequestBodyBytes)
                            }
                            upload.append(chunk)
                        }
                        await source.close()
                    } catch {
                        await source.close()
                        throw error
                    }
                }
                var outgoing = platform
                if request.body != nil { outgoing.httpBody = upload }
                DiscordLog.makeLogger("foundation.http.upload").trace("Foundation HTTP upload collection completed", metadata: ["dk.event": "foundation.http.upload.completed", "dk.bytes": .stringConvertible(upload.count)])
                DiscordLog.makeLogger("foundation.http").trace("Foundation HTTP request submitted", metadata: ["dk.event": "foundation.http.submitted"])
                let (bytes, metadata) = try await owner.session.bytes(for: outgoing)
                guard let response = metadata as? HTTPURLResponse else {
                    bytes.task.cancel()
                    await foundationDiscardBytes(bytes.makeAsyncIterator())
                    throw FoundationTransportFailure.invalidResponse
                }
                if request.method != "HEAD", response.statusCode != 304,
                   response.expectedContentLength > Int64(configuration.maximumResponseBodyBytes) {
                    bytes.task.cancel()
                    await foundationDiscardBytes(bytes.makeAsyncIterator())
                    throw FoundationTransportFailure.bodyLimitExceeded(limit: configuration.maximumResponseBodyBytes)
                }
                let source = FoundationHTTPBody(bytes: bytes, owner: owner, identifier: reserved,
                                                configuration: configuration, context: context)
                do { try await owner.register(reserved) { await source.close() } }
                catch { await source.close(); throw error }
                let body = try BodyStream(maximumChunkBytes: configuration.responseChunkBytes,
                                          next: { try await source.next() }, close: { await source.close() })
                let headers = response.allHeaderFields.map { HTTPHeader(name: String(describing: $0.key),
                                                                        value: String(describing: $0.value)) }
                DiscordLog.makeLogger("foundation.http.body").trace("Foundation HTTP response body ownership transferred", metadata: ["dk.event": "foundation.http.body.transferred", "dk.status": .stringConvertible(response.statusCode)])
                return HTTPResponse(status: response.statusCode, headers: headers, body: body)
            }
            DiscordLog.makeLogger("foundation.http").debug("Foundation HTTP response received", metadata: ["dk.event": "foundation.http.response", "http.status": "\(result.status)"])
            return result
        } catch {
            await request.body?.close()
            if let identifier { await owner.abandon(identifier) }
            DiscordLog.makeLogger("foundation.http").debug("Foundation HTTP exchange ended without a response", metadata: ["dk.event": "foundation.http.failed"])
            throw foundationFailure(error)
        }
    }

    /// Cancels every outstanding exchange/body and waits for session invalidation.
    /// Closure is idempotent; subsequent executions fail with `TransportFailure.closed`.
    public func close() async {
        await owner.close()
        DiscordLog.makeLogger("foundation.http").info("Foundation HTTP transport closed", metadata: ["dk.event": "foundation.http.closed"])
    }
}

/// Preserves iterator state across pulls while leaving concurrency rejection to BodyStream.
private actor FoundationHTTPBody<C: Clock> where C.Duration == Duration {
    private var iterator: URLSession.AsyncBytes.Iterator?
    private let task: URLSessionDataTask
    private let owner: FoundationSession
    private let identifier: UUID
    private let configuration: FoundationTransportConfiguration
    private let context: TransportContext<C>
    private var count = 0
    private var closed = false
    private var closeTask: Task<Void, Never>?

    /// Stores transferred byte ownership without reading or allocating a body buffer.
    /// - Parameters:
    ///   - bytes: Native single-pass response sequence and its cancellable task.
    ///   - owner: Session admission owner, retained until EOF or explicit close.
    ///   - identifier: Admission token released during terminal cleanup.
    ///   - configuration: Validated chunk and total consumed-byte limits.
    ///   - context: Original injected operation clock/deadline, retained for body reads.
    init(bytes: URLSession.AsyncBytes, owner: FoundationSession, identifier: UUID,
         configuration: FoundationTransportConfiguration, context: TransportContext<C>) {
        iterator = bytes.makeAsyncIterator()
        task = bytes.task
        self.owner = owner
        self.identifier = identifier
        self.configuration = configuration
        self.context = context
    }

    /// Pulls up to one configured chunk and enforces the remaining lifetime byte budget.
    /// - Returns: A bounded chunk, or `nil` at EOF/closure; no next chunk is prefetched.
    /// - Throws: Cancellation, original deadline, total limit or redacted native failure.
    func next() async throws -> Data? {
        guard !closed else { return nil }
        let task = self.task
        do {
            return try await context.run {
                try await withTaskCancellationHandler {
                    try await self.read()
                } onCancel: { task.cancel() }
            }
        } catch {
            await close()
            throw foundationFailure(error)
        }
    }

    /// Reads a single chunk using a local iterator copy across native suspension points.
    /// - Returns: Bytes in wire order or `nil` on terminal EOF.
    /// - Throws: Native I/O, cancellation, or the configured total-byte ceiling.
    private func read() async throws -> Data? {
        guard var cursor = iterator else { return nil }
        iterator = nil
        defer { if !closed { iterator = cursor } }
        var result = Data()
        while result.count < configuration.responseChunkBytes {
            try Task.checkCancellation()
            guard let byte = try await cursor.next() else {
                await close()
                return result.isEmpty ? nil : result
            }
            guard !closed else { return nil }
            guard count < configuration.maximumResponseBodyBytes else {
                throw FoundationTransportFailure.bodyLimitExceeded(limit: configuration.maximumResponseBodyBytes)
            }
            count += 1
            result.append(byte)
        }
        return result
    }

    /// Cancels pending native reads and releases admission once before returning.
    func close() async {
        if let closeTask { await closeTask.value; return }
        closed = true
        DiscordLog.makeLogger("foundation.http.body").trace("Foundation HTTP body cleanup started", metadata: ["dk.event": "foundation.http.body.cleanup", "dk.bytes": .stringConvertible(count)])
        task.cancel()
        let discarded = iterator
        iterator = nil
        let owner = self.owner
        let identifier = self.identifier
        let cleanup = Task {
            if let discarded { await foundationDiscardBytes(discarded) }
            await owner.release(identifier)
            DiscordLog.makeLogger("foundation.admission").trace("Foundation HTTP body operation slot released", metadata: ["dk.event": "foundation.admission.released"])
        }
        closeTask = cleanup
        await cleanup.value
    }
}

/// Releases the native async consumer after abandoning buffered response bytes.
///
/// Cancelling only URLSessionDataTask can leave its session invalidation callback
/// pending while an unconsumed AsyncBytes iterator still owns a suspended producer.
/// An owned task drives the iterator to its already-cancelled producer's terminal
/// result. The consumer task remains uncancelled so it can discard buffered bytes;
/// cancelling that task first can skip the native consumer's terminal acknowledgement.
/// No response bytes escape to the caller and the network task is already cancelled.
/// - Parameter iterator: Exclusively owned native cursor, never an active concurrent read.
func foundationDiscardBytes(_ iterator: URLSession.AsyncBytes.Iterator) async {
    let cleanup = Task {
        var cursor = iterator
        do { while try await cursor.next() != nil {} } catch {}
    }
    await cleanup.value
}
#endif
