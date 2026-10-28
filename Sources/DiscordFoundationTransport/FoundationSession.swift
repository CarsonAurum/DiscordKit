// File: Sources/DiscordFoundationTransport/FoundationSession.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(Darwin)
import DiscordTransport
import Foundation

/// Owns a Foundation session and fail-fast admission with no queued callers.
actor FoundationSession {
    nonisolated let session: URLSession
    private let delegate: FoundationSessionDelegate
    private let maximumOperations: Int
    private var resources: [UUID: @Sendable () async -> Void] = [:]
    private var closed = false
    private var closeTask: Task<Void, Never>?

    /// Creates an ephemeral session with no shared cookie, credential or cache store.
    /// - Parameter configuration: Validated admission and network timeout limits.
    init(configuration: FoundationTransportConfiguration) {
        maximumOperations = configuration.maximumConcurrentOperations
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.httpMaximumConnectionsPerHost = configuration.maximumConcurrentOperations
        settings.timeoutIntervalForRequest = configuration.networkTimeout
        settings.timeoutIntervalForResource = configuration.networkTimeout
        let delegate = FoundationSessionDelegate()
        self.delegate = delegate
        session = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
    }

    /// Reserves one bounded resource before a caller starts allocating or uploading.
    /// - Parameter cleanup: Cleanup available even before a platform task exists.
    /// - Returns: Opaque admission identifier to register and release exactly once.
    /// - Throws: Closure or immediate admission rejection; no waiter is retained.
    func reserve(cleanup: @escaping @Sendable () async -> Void) throws -> UUID {
        guard !closed else { throw TransportFailure.closed }
        guard resources.count < maximumOperations else { throw FoundationTransportFailure.admissionRejected }
        let identifier = UUID()
        resources[identifier] = cleanup
        return identifier
    }

    /// Replaces cleanup after acquiring a task or transferring response ownership.
    /// - Parameters:
    ///   - identifier: Admission identifier previously reserved by this owner.
    ///   - cleanup: Idempotent asynchronous cleanup of the current operation resource.
    /// - Throws: `TransportFailure.closed` if shutdown won the registration race.
    func register(_ identifier: UUID, cleanup: @escaping @Sendable () async -> Void) throws {
        guard !closed, resources[identifier] != nil else { throw TransportFailure.closed }
        resources[identifier] = cleanup
    }

    /// Releases admission after the resource has completed its cleanup.
    /// - Parameter identifier: Admission identifier; repeated release has no effect.
    func release(_ identifier: UUID) { resources.removeValue(forKey: identifier) }

    /// Closes the current operation resource after a failure before ownership transfer.
    /// - Parameter identifier: Reservation to remove; repeated abandonment is harmless.
    func abandon(_ identifier: UUID) async {
        let cleanup = resources.removeValue(forKey: identifier)
        await cleanup?()
    }

    /// Cancels native I/O, closes every owned resource and awaits session invalidation.
    /// Concurrent callers await the same task; no newly admitted work can interleave.
    func close() async {
        if let closeTask { await closeTask.value; return }
        closed = true
        let cleanups = Array(resources.values)
        resources.removeAll()
        let session = self.session
        let gate = delegate.invalidation
        let task = Task {
            session.invalidateAndCancel()
            await withTaskGroup(of: Void.self) { group in
                for cleanup in cleanups { group.addTask { await cleanup() } }
                await group.waitForAll()
            }
            await gate.wait()
        }
        closeTask = task
        await task.value
    }
}

/// One-shot invalidation completion shared by the delegate and shutdown callers.
actor FoundationInvalidation {
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until URLSession reports all invalidation callbacks are finished.
    func wait() async {
        if finished { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Completes every shutdown waiter once and discards all continuation storage.
    func finish() {
        finished = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// Rejects redirects and credential challenges without retaining sensitive metadata.
final class FoundationSessionDelegate: NSObject, URLSessionTaskDelegate {
    let invalidation = FoundationInvalidation()

    /// Rejects automatic redirects so credentials cannot cross an unreviewed origin.
    /// - Parameters:
    ///   - session: Owning session; no shared stores are consulted.
    ///   - task: Redirecting task, whose original response remains visible to callers.
    ///   - response: Redirect metadata, never copied into diagnostics.
    ///   - request: Proposed destination, deliberately rejected.
    ///   - completionHandler: Resumed exactly once with no follow-up request.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Uses system TLS trust evaluation and rejects interactive credential retries.
    /// - Parameters:
    ///   - session: Ephemeral owning session.
    ///   - task: Challenged task; it is never replayed using credential storage.
    ///   - challenge: Trust or HTTP authentication challenge.
    ///   - completionHandler: Completes once with default server trust evaluation,
    ///     or cancellation for every other authentication method.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Signals final cleanup without exporting Foundation's possibly sensitive error.
    /// - Parameters:
    ///   - session: Session that has completed invalidation.
    ///   - error: Optional native error; deliberately discarded.
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        Task { await invalidation.finish() }
    }
}
#endif
