import DiscordLogging
import DiscordTransport
import Foundation

/// Bounded authentication adapter for an injected listener; construction starts no tasks or sockets.
/// Accepted exchanges remain caller-owned. Share an instance to share its fail-fast admission budget.
public actor DiscordSignedIngress {
    private let verifier: SignedRequestVerifier
    private let maximumConcurrentRequests: Int
    private let maximumBodyBytes: Int
    private let maximumHeaderBytes: Int
    private var active = 0

    /// Configures count and byte bounds before accepting external work.
    /// - Parameters:
    ///   - verifier: Shared per-application signature/replay authority.
    ///   - maximumConcurrentRequests: Positive concurrent body/handler bound; no waiting queue, default 32.
    ///   - maximumBodyBytes: Positive per-request body cap; aggregate buffering is bounded by
    ///     this value times the concurrent count, default 1 MiB. The verifier independently checks its cap.
    ///   - maximumHeaderBytes: Positive total UTF-8 field-name/value byte cap, default 16 KiB.
    /// - Throws: `SignedIngressFailure.invalidConfiguration` for nonpositive limits.
    public init(verifier: SignedRequestVerifier, maximumConcurrentRequests: Int = 32,
                maximumBodyBytes: Int = 1_048_576, maximumHeaderBytes: Int = 16_384) throws {
        guard maximumConcurrentRequests > 0, maximumBodyBytes > 0, maximumHeaderBytes > 0
        else { throw SignedIngressFailure.invalidConfiguration }
        self.verifier = verifier; self.maximumConcurrentRequests = maximumConcurrentRequests
        self.maximumBodyBytes = maximumBodyBytes; self.maximumHeaderBytes = maximumHeaderBytes
    }

    /// Authenticates and dispatches one request, always consuming or closing its body.
    ///
    /// Request limits run before authentication; application JSON decoding happens only in
    /// `handler`. Authentication failures return 401, overload returns retryable 503,
    /// body/header overflow returns 413/431, non-POST returns 405 and handler failure returns
    /// 500. Authentication failure classification ends before the handler starts: a handler throwing
    /// SignedIngressFailure is still an application failure. No error embeds submitted data. The injected
    /// context bounds reading and handler work; both must cooperate with cancellation. Handler-produced
    /// response bodies remain owned here until successful transfer, including deadline/cancellation races.
    /// This adapter never retries side effects.
    /// - Parameters:
    ///   - request: Single-use request whose body ownership transfers even on rejection.
    ///   - context: Monotonic clock and optional deadline, normally no more than three seconds.
    ///   - handler: Receives authenticated raw bytes; returns an owned response body.
    /// - Returns: A protocol response; caller owns its body until sent or explicitly closed.
    /// - Throws: Cancellation or context expiry, after closing the request body and any response body
    ///   produced before successful transfer. Cleanup is awaited even when a handler finishes after cancellation.
    public func process<C: Clock>(request: HTTPRequest, context: TransportContext<C>,
        handler: @escaping @Sendable (VerifiedDiscordRequest) async throws -> HTTPResponse) async throws -> HTTPResponse
        where C.Duration == Duration {
        DiscordLog.makeLogger("interactions.ingress").debug("Signed request processing started", metadata: ["dk.event": "interactions.ingress.started"])
        do { try context.check() } catch {
            await request.body?.close()
            DiscordLog.makeLogger("interactions.ingress").trace("Request body closed before admission", metadata: ["dk.event": "interactions.ingress.closed_before_admission"])
            throw error
        }
        guard active < maximumConcurrentRequests else {
            DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress capacity exhausted", metadata: ["dk.event": "interactions.ingress.overloaded", "dk.active": .stringConvertible(active)])
            await request.body?.close()
            return HTTPResponse(status: 503, headers: [HTTPHeader(name: "Retry-After", value: "1")])
        }
        active += 1
        DiscordLog.makeLogger("interactions.ingress").trace("Signed ingress admitted", metadata: ["dk.event": "interactions.ingress.admitted", "dk.active": .stringConvertible(active)])
        defer {
            active -= 1
            DiscordLog.makeLogger("interactions.ingress").trace("Signed ingress admission released", metadata: ["dk.event": "interactions.ingress.released", "dk.active": .stringConvertible(active)])
        }
        guard request.method == "POST" else {
            DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress rejected request method", metadata: ["dk.event": "interactions.ingress.method_rejected", "dk.status": "405"])
            await request.body?.close(); return HTTPResponse(status: 405)
        }
        var headerBytes = 0
        for header in request.headers {
            guard header.name.utf8.count <= maximumHeaderBytes - headerBytes else {
                DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress header bound exceeded", metadata: ["dk.event": "interactions.ingress.headers_rejected", "dk.status": "431"])
                await request.body?.close(); return HTTPResponse(status: 431)
            }
            headerBytes += header.name.utf8.count
            guard header.value.utf8.count <= maximumHeaderBytes - headerBytes else {
                DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress header bound exceeded", metadata: ["dk.event": "interactions.ingress.headers_rejected", "dk.status": "431"])
                await request.body?.close(); return HTTPResponse(status: 431)
            }
            headerBytes += header.value.utf8.count
        }
        DiscordLog.makeLogger("interactions.ingress").trace("Request header bounds validated", metadata: ["dk.event": "interactions.ingress.headers_validated", "dk.bytes": .stringConvertible(headerBytes)])
        let responseLease = ResponseLease()
        var pendingResponse: HTTPResponse?
        var authenticated = false
        do {
            let maximumBodyBytes = self.maximumBodyBytes
            DiscordLog.makeLogger("interactions.ingress").trace("Reading bounded request body", metadata: ["dk.event": "interactions.ingress.body_reading"])
            let bytes = try await context.run {
                var bytes = Data()
                if let body = request.body {
                    for try await chunk in body {
                        guard chunk.count <= maximumBodyBytes - bytes.count else {
                            throw SignedIngressFailure.bodyTooLarge
                        }
                        bytes.append(chunk)
                    }
                    await body.close()
                }
                return bytes
            }
            DiscordLog.makeLogger("interactions.ingress").trace("Request body read and closed", metadata: ["dk.event": "interactions.ingress.body_read", "dk.bytes": .stringConvertible(bytes.count)])
            DiscordLog.makeLogger("interactions.ingress").trace("Verifying request signature and replay admission", metadata: ["dk.event": "interactions.ingress.verifying"])
            let verified = try await verifier.verify(headers: request.headers, body: bytes)
            try context.check()
            authenticated = true
            DiscordLog.makeLogger("interactions.ingress").trace("Signed request authenticated", metadata: ["dk.event": "interactions.ingress.authenticated"])
            DiscordLog.makeLogger("interactions.ingress").trace("Invoking authenticated request handler", metadata: ["dk.event": "interactions.ingress.handler_started"])
            try await context.run {
                let response = try await handler(verified)
                await responseLease.store(response)
            }
            pendingResponse = await responseLease.take()
            try context.check()
            guard let response = pendingResponse else { throw TransportFailure.closed }
            pendingResponse = nil
            DiscordLog.makeLogger("interactions.ingress").debug("Signed request processing completed", metadata: ["dk.event": "interactions.ingress.completed", "dk.status": .stringConvertible(response.status)])
            return response
        } catch {
            DiscordLog.makeLogger("interactions.ingress").trace("Closing failed request and retained response bodies", metadata: ["dk.event": "interactions.ingress.cleanup_started"])
            await request.body?.close()
            await pendingResponse?.body?.close()
            await responseLease.take()?.body?.close()
            DiscordLog.makeLogger("interactions.ingress").trace("Failed request bodies closed", metadata: ["dk.event": "interactions.ingress.cleanup_completed"])
            try context.check()
            if !authenticated, let failure = error as? SignedIngressFailure {
                DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress rejected unverified request", metadata: ["dk.event": "interactions.ingress.rejected"])
                switch failure {
                case .bodyTooLarge: return HTTPResponse(status: 413)
                case .replayCapacity: return HTTPResponse(status: 503)
                case .invalidConfiguration: return HTTPResponse(status: 500)
                case .malformedHeaders, .invalidSignature, .staleTimestamp, .replay: return HTTPResponse(status: 401)
                }
            }
            if error is CancellationError {
                DiscordLog.makeLogger("interactions.ingress").debug("Signed ingress cancelled", metadata: ["dk.event": "interactions.ingress.cancelled"])
                throw error
            }
            DiscordLog.makeLogger("interactions.ingress").error("Signed ingress handler failed", metadata: ["dk.event": "interactions.ingress.failed", "dk.status": "500"])
            return HTTPResponse(status: 500)
        }
    }

    /// Owns an accepted exchange through authentication and exactly one response attempt.
    /// - Parameters:
    ///   - exchange: Caller-transferred request and response slot from any HTTPIngress adapter.
    ///   - context: Clock/deadline shared by body, dispatch and response transmission.
    ///   - handler: Authenticated application work; must honor cancellation and own durable admission.
    /// - Throws: Cancellation, deadline or responder transport failure; failure closes the response slot.
    public func handle<C: Clock>(_ exchange: HTTPExchange, context: TransportContext<C>,
        handler: @escaping @Sendable (VerifiedDiscordRequest) async throws -> HTTPResponse) async throws
        where C.Duration == Duration {
        do {
            let response = try await process(request: exchange.request, context: context, handler: handler)
            DiscordLog.makeLogger("interactions.ingress").trace("Sending exchange response", metadata: ["dk.event": "interactions.ingress.response_sending", "dk.status": .stringConvertible(response.status)])
            try await exchange.responder.respond(response, context: context)
            DiscordLog.makeLogger("interactions.ingress").trace("Exchange response sent", metadata: ["dk.event": "interactions.ingress.response_sent"])
        } catch {
            await exchange.responder.close()
            DiscordLog.makeLogger("interactions.ingress").trace("Failed exchange response slot closed", metadata: ["dk.event": "interactions.ingress.exchange_closed"])
            throw error
        }
    }

    /// Reports currently admitted request/handler operations, with no identity labels.
    /// - Returns: A count between zero and the configured concurrent bound.
    public func activeRequestCount() -> Int { active }

    /// Retains a handler-produced response across the structured deadline race. TransportContext.run
    /// joins both children before returning/throwing, so failure cleanup cannot race a later store.
    private actor ResponseLease {
        private var response: HTTPResponse?

        /// Stores the sole handler result before the deadline-raced operation returns Void.
        /// - Parameter response: Newly produced response whose optional body ownership transfers here.
        /// This actor-local operation does not suspend. Exactly one handler invocation stores one result;
        /// retaining the body here prevents TransportContext from discarding its cleanup obligation.
        func store(_ response: HTTPResponse) { self.response = response }

        /// Transfers the retained response into the process caller's pending or cleanup ownership.
        /// - Returns: The sole stored response, or nil before storage or after a previous take.
        /// The caller rechecks cancellation/deadline after this actor hop and closes the pending body
        /// on failure. The actor clears its reference synchronously, so ownership transfers once.
        func take() -> HTTPResponse? {
            defer { response = nil }
            return response
        }
    }
}
