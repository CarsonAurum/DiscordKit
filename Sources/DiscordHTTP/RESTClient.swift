// File: Sources/DiscordHTTP/RESTClient.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordTransport
import Foundation

/// An injected REST execution pipeline; construction starts no tasks or network work.
///
/// Clients sharing a credential must share their opaque identity and rate authority.
/// Use a new read scope/coalescer/cache after credential or scope changes, or explicitly
/// invalidate before reuse. Transport, coordinator and reuse components are injected,
/// separately owned resources: this client never closes shared dependencies implicitly.
public final class RESTClient<C: Clock>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable where C.Duration == Duration {
    private let credential: Credential
    public let identity: RateLimitIdentity
    private let transport: any HTTPTransport
    private let coordinator: RateLimitCoordinator<C>
    private let clock: C
    private let cache: ReadCache<C>?
    private let coalescer: RequestCoalescer?
    private let retryPolicy: RetryPolicy
    private let maximumResponseBytes: Int
    private let maximumExchangeDuration: Duration
    private let userAgent: String
    private let egress: UUID?

    /// Conceals credentials and injected owners from ordinary diagnostic formatting.
    public var description: String { "RESTClient(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from walking transport scripts, secrets or caches.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Binds one authentication scope to its shared admission and optional read reuse owners.
    /// - Parameters:
    ///   - credential: Accepted bot/bearer header credential or webhook/interaction path credential.
    ///     Path-token endpoints require an exact match; tokens never become Authorization headers.
    ///     Use a separate client and stable identity for each token, shared across its workers.
    ///   - identity: Stable opaque credential/rate scope, shared across clients and workers.
    ///   - transport: Single-send adapter; must not follow redirects or automatically retry.
    ///   - coordinator: Shared fail-closed authority using the same clock domain.
    ///   - clock: Monotonic clock shared with admission and cache.
    ///   - cache: Optional bounded opt-in successful-byte cache; nil disables retention.
    ///   - coalescer: Optional bounded eligible-read single-flight owner.
    ///   - retryPolicy: Finite replay/backoff budget, default three attempts.
    ///   - maximumResponseBytes: Positive total response/error byte bound, default 8 MiB.
    ///   - maximumExchangeDuration: Positive shared-flight lifetime, default 30 seconds.
    ///     One subscriber's deadline cannot shorten another subscriber's exchange.
    ///   - egress: Shared opaque outbound-IP identity for aggregate invalid-response protection
    ///     and header-free IP-global admission. Required for globally limited webhook-token operations;
    ///     every client sharing the outbound IP must supply the same value, independently of token identity.
    ///   - userAgent: DiscordBot library identification; validated before transmission.
    /// - Precondition: Response byte and exchange-duration limits are positive.
    public init(credential: Credential, identity: RateLimitIdentity, transport: any HTTPTransport,
                coordinator: RateLimitCoordinator<C>, clock: C, cache: ReadCache<C>? = nil,
                coalescer: RequestCoalescer? = nil, retryPolicy: RetryPolicy = .init(),
                maximumResponseBytes: Int = 8 * 1_024 * 1_024,
                maximumExchangeDuration: Duration = .seconds(30),
                egress: UUID? = nil, userAgent: String = "DiscordBot (https://github.com/CarsonAurum/DiscordKit, 0.19.0)") {
        precondition(maximumResponseBytes > 0 && maximumExchangeDuration > .zero)
        self.credential = credential; self.identity = identity; self.transport = transport
        self.coordinator = coordinator; self.clock = clock; self.cache = cache; self.coalescer = coalescer
        self.retryPolicy = retryPolicy; self.maximumResponseBytes = maximumResponseBytes
        self.maximumExchangeDuration = maximumExchangeDuration; self.userAgent = userAgent; self.egress = egress
    }

    /// Executes a typed or raw descriptor through authentication, admission and bounded decoding.
    /// Trace diagnostics correlate validation, reuse, attempts, rate admission, request/body
    /// ownership and decoding without exposing routes, credentials or content.
    /// - Parameters:
    ///   - endpoint: Explicit success, retry, representation and optional read-reuse policy.
    ///   - deadline: Optional inclusive deadline in this client's clock domain.
    /// - Returns: Decoded result; empty/204 semantics follow the descriptor's decoder.
    /// - Throws: Safe API/validation/admission/transport failures, cancellation, deadline expiry,
    ///   or indeterminate mutation outcome when an unsafe send may already have succeeded.
    ///   Decoder errors are replaced with a safe invalid-response category.
    public func execute<Response: Sendable>(_ endpoint: Endpoint<Response>, deadline: C.Instant? = nil) async throws -> Response {
        return try await DiscordLog.withOperation("http.execution", event: "http.operation") {
            DiscordLog.makeLogger("http.execution").debug("REST execution started", metadata: ["dk.event": "http.execute.started"])
            let context = TransportContext(clock: clock, deadline: deadline)
            try context.check()
            try endpoint.validateCredential(credential)
            if case .webhook = endpoint.pathCredential, endpoint.usesGlobalLimit, egress == nil {
                throw DiscordError.validation(.missingValue)
            }
            DiscordLog.makeLogger("http.execution").trace("REST descriptor and credentials validated", metadata: ["dk.event": "http.execute.validated", "dk.safe_retry": .stringConvertible(endpoint.retrySafety == .safe), "dk.read_reuse": .stringConvertible(endpoint.readPolicy != nil)])
            let evidence = HTTPSubmissionEvidence()
            do {
                let result = try await context.run {
                    let key = self.readKey(endpoint)
                    if endpoint.readPolicy?.timeToLive != nil, let data = await self.cache?.value(for: key) {
                        try context.check()
                        DiscordLog.makeLogger("http.cache").trace("REST read cache hit", metadata: ["dk.event": "http.cache.hit"])
                        return try self.decode(endpoint, data: data)
                    }
                    DiscordLog.makeLogger("http.cache").trace("REST read reuse lookup completed without a cached response", metadata: ["dk.event": "http.cache.miss", "dk.enabled": .stringConvertible(endpoint.readPolicy?.timeToLive != nil && self.cache != nil)])
                    let operation: @Sendable () async throws -> Data = {
                        let generation = await self.cache?.generation()
                        let maximumDeadline = self.clock.now.advanced(by: self.maximumExchangeDuration)
                        let shared = endpoint.readPolicy?.coalescing == true && self.coalescer != nil
                        let sharedDeadline = shared ? maximumDeadline : min(deadline ?? maximumDeadline, maximumDeadline)
                        let started = self.clock.now
                        let reply = try await self.perform(endpoint, deadline: sharedDeadline, evidence: evidence)
                        let data = reply.data
                        // Validate before retention so malformed successes never become cached data.
                        _ = try self.decode(endpoint, data: data)
                        if let requested = endpoint.readPolicy?.timeToLive, let generation,
                           let ttl = self.cacheLifetime(requested: requested, headers: reply.headers + endpoint.headers,
                                                        elapsed: started.duration(to: self.clock.now)) {
                            await self.cache?.insert(data, for: key, timeToLive: ttl,
                                                     tags: endpoint.readPolicy?.tags ?? [], generation: generation)
                        }
                        return data
                    }
                    let data: Data
                    if endpoint.readPolicy?.coalescing == true, let coalescer = self.coalescer {
                        DiscordLog.makeLogger("http.coalescing").trace("REST read entering shared flight admission", metadata: ["dk.event": "http.coalescing.admission"])
                        data = try await coalescer.run(key: key, operation: operation)
                    } else { data = try await operation() }
                    try context.check()
                    return try self.decode(endpoint, data: data)
                }
                try context.check()
                DiscordLog.makeLogger("http.execution").info("REST execution completed", metadata: ["dk.event": "http.execute.completed"])
                return result
            } catch {
                if error is CancellationError {
                    DiscordLog.makeLogger("http.execution").debug("REST execution cancelled", metadata: ["dk.event": "http.execute.cancelled"])
                } else {
                    DiscordLog.makeLogger("http.execution").debug("REST execution failed", metadata: ["dk.event": "http.execute.failed"])
                }
                if endpoint.retrySafety == .unsafe, await evidence.wasSubmitted(),
                   error is CancellationError || (error as? TransportFailure) == .deadlineExceeded {
                    throw self.submissionFailure(error, safety: .unsafe)
                }
                throw error
            }
        }
    }

    /// Invalidates observed permission, visibility or credential-scope changes and awaits old reads.
    /// - Parameter tags: Matching cache tags, or empty to remove all snapshots for this scope.
    /// TTL alone cannot detect unobserved external changes. Existing coalesced readers cancel.
    public func invalidate(tags: Set<String> = []) async {
        DiscordLog.makeLogger("http.cache").debug("REST read scope invalidation started", metadata: ["dk.event": "http.cache.invalidation.started", "dk.tags": .stringConvertible(tags.count)])
        await cache?.invalidate(identity: identity, tags: tags)
        await coalescer?.invalidate(identity: identity)
        DiscordLog.makeLogger("http.cache").trace("REST read scope invalidation completed", metadata: ["dk.event": "http.cache.invalidation.completed"])
    }

    /// Performs finite attempts while holding mutation order through each admitted exchange.
    /// - Parameters:
    ///   - endpoint: Validated operation descriptor.
    ///   - deadline: Bounded exchange deadline, separate from individual shared subscribers.
    ///   - evidence: Operation-local conservative submission evidence for deadline races.
    /// - Returns: Successful bounded response metadata/bytes after invalidating declared local-write tags.
    /// - Throws: Safe failure categories; 429 replays only explicit server rejection, while
    ///   ambiguous transport and 5xx retries require demonstrably safe operation semantics.
    private func perform<Response: Sendable>(_ endpoint: Endpoint<Response>, deadline: C.Instant, evidence: HTTPSubmissionEvidence) async throws -> WireReply {
        let context = TransportContext(clock: clock, deadline: deadline)
        let operation: @Sendable () async throws -> WireReply = { try await context.run {
            var attempt = 0
            while true {
                try context.check()
                attempt += 1
                DiscordLog.makeLogger("http.execution").trace("REST attempt started", metadata: ["dk.event": "http.attempt.started", "dk.attempt": .stringConvertible(attempt), "dk.maximum_attempts": .stringConvertible(self.retryPolicy.maximumAttempts)])
                let reply: WireReply
                do { reply = try await self.send(endpoint, context: context, evidence: evidence) }
                catch let error as DiscordError {
                    if case .transport = error, endpoint.retrySafety == .safe,
                       let delay = self.retryPolicy.delay(after: attempt) {
                        DiscordLog.makeLogger("http.retry").notice("Retrying safe REST transport failure", metadata: ["dk.event": "http.retry.transport", "dk.attempt": .stringConvertible(attempt)])
                        try await self.clock.sleep(for: delay)
                        continue
                    }
                    throw error
                }
                DiscordLog.makeLogger("http.execution").trace("REST attempt response classified", metadata: ["dk.event": "http.attempt.classified", "dk.attempt": .stringConvertible(attempt), "dk.status": .stringConvertible(reply.status), "dk.accepted": .stringConvertible(endpoint.successStatuses.contains(reply.status))])
                if endpoint.successStatuses.contains(reply.status) {
                    if !endpoint.invalidates.isEmpty { await self.invalidate(tags: endpoint.invalidates) }
                    return reply
                }
                let error = APIResponseError(status: reply.status, headers: reply.headers, body: reply.data)
                if reply.status == 429, self.retryPolicy.delay(after: attempt) != nil {
                    DiscordLog.makeLogger("http.retry").notice("Retrying REST server rejection", metadata: ["dk.event": "http.retry.rate_limit", "dk.attempt": .stringConvertible(attempt)])
                    // A complete 429 establishes rejection; queued retry cancellation
                    // must not be misreported as an indeterminate mutation.
                    continue
                }
                if (500...599).contains(reply.status), endpoint.retrySafety == .safe,
                   let delay = self.retryPolicy.delay(after: attempt) {
                    DiscordLog.makeLogger("http.retry").warning("Retrying safe REST server failure", metadata: ["dk.event": "http.retry.server", "dk.attempt": .stringConvertible(attempt), "dk.status": .stringConvertible(reply.status)])
                    try await self.clock.sleep(for: delay)
                    continue
                }
                if (500...599).contains(reply.status), endpoint.retrySafety == .unsafe {
                    throw DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission)
                }
                throw error
            }
        } }
        if endpoint.retrySafety == .unsafe {
            return try await coordinator.withOrdering(request: rateRequest(endpoint), deadline: deadline, operation: operation)
        }
        return try await operation()
    }

    /// Owns one admission token and both body lifetimes; no hidden transport retries occur.
    /// - Parameters:
    ///   - endpoint: Operation providing a fresh replayable body for this attempt.
    ///   - context: Clock/deadline/cancellation context used for admission and transport.
    ///   - evidence: Records possible submission before awaiting the injected adapter.
    /// - Returns: Complete bounded response metadata/bytes after authority observation.
    /// - Throws: Safe transport/authority failures or conservative unsafe-send uncertainty.
    private func send<Response: Sendable>(_ endpoint: Endpoint<Response>, context: TransportContext<C>, evidence: HTTPSubmissionEvidence) async throws -> WireReply {
        try context.check()
        DiscordLog.makeLogger("http.execution").trace("REST attempt requesting rate admission", metadata: ["dk.event": "http.request.admission"])
        let reservation = try await coordinator.acquire(rateRequest(endpoint), deadline: context.deadline)
        let request: HTTPRequest
        do {
            request = try endpoint.makeRequest(credential: credential, userAgent: userAgent)
            DiscordLog.makeLogger("http.execution").trace("REST request encoded", metadata: ["dk.event": "http.request.encoded", "dk.has_body": .stringConvertible(request.body != nil)])
        }
        catch {
            do { try await coordinator.release(reservation, outcome: .notSent) }
            catch { await recordOwnerFailure(error) }
            throw error
        }
        do { try context.check() }
        catch {
            await request.body?.close()
            do { try await coordinator.release(reservation, outcome: .notSent) }
            catch { await recordOwnerFailure(error) }
            throw error
        }
        let response: HTTPResponse
        do {
            await evidence.markSubmitted()
            try context.check()
            DiscordLog.makeLogger("http.execution").trace("REST request submitted to transport", metadata: ["dk.event": "http.request.submitted"])
            response = try await transport.execute(request, context: context)
        }
        catch {
            await request.body?.close()
            do { try await coordinator.release(reservation, outcome: .uncertain) }
            catch { await recordOwnerFailure(error) }
            await recordOwnerFailure(error)
            throw submissionFailure(error, safety: endpoint.retrySafety)
        }
        await request.body?.close()
        DiscordLog.makeLogger("http.execution").trace("REST response received", metadata: ["dk.event": "http.response.received", "dk.status": .stringConvertible(response.status)])
        let data: Data
        do {
            DiscordLog.makeLogger("http.execution").trace("REST response body collection started", metadata: ["dk.event": "http.response.body.started", "dk.maximum_bytes": .stringConvertible(maximumResponseBytes)])
            data = try await ResponseBody.collect(response.body, maximumBytes: maximumResponseBytes)
            DiscordLog.makeLogger("http.execution").trace("REST response body collection completed", metadata: ["dk.event": "http.response.body.completed", "dk.bytes": .stringConvertible(data.count)])
        }
        catch {
            do { try await coordinator.complete(reservation, status: response.status, headers: response.headers) }
            catch { await recordOwnerFailure(error) }
            await recordOwnerFailure(error)
            throw submissionFailure(error, safety: endpoint.retrySafety)
        }
        var retryAfter: Duration?
        var global = false
        if response.status == 429,
           case .object(let object) = try? JSONValue.parse(data) {
            if case .number(let number) = object["retry_after"], let seconds = Double(number.rawValue),
               seconds.isFinite, seconds >= 0, seconds <= 86_400 { retryAfter = .seconds(seconds) }
            if case .bool(let value) = object["global"] { global = value }
        }
        do {
            try await coordinator.complete(reservation, status: response.status, headers: response.headers,
                                           retryAfter: retryAfter, global: global)
        } catch {
            await recordOwnerFailure(error)
            if endpoint.retrySafety == .unsafe { throw submissionFailure(error, safety: .unsafe) }
            throw error
        }
        DiscordLog.makeLogger("http.execution").trace("REST attempt admission released after response observation", metadata: ["dk.event": "http.request.completed", "dk.status": .stringConvertible(response.status)])
        if response.status == 429 { await evidence.markRejected() }
        return WireReply(status: response.status, headers: response.headers, data: data)
    }

    /// Records closed owner evidence before normalization can erase the source failure.
    /// - Parameter error: Original adapter/body/admission failure; only reviewed safe typed cases are inspected.
    /// This observation does not change public thrown errors, request replay or cleanup behavior.
    private func recordOwnerFailure(_ error: any Error) async {
        let failure: InvocationOwnerFailure
        if let error = error as? RateLimitFailure {
            switch error {
            case .closed: failure = .rateLimitClosed
            case .invalidRequest: failure = .rateLimitInvalidRequest
            case .unknownReservation: failure = .rateLimitUnknownReservation
            case .coordinatorUnavailable: failure = .rateLimitCoordinatorUnavailable
            default: return
            }
        } else if let error = error as? TransportFailure {
            switch error {
            case .closed: failure = .transportClosed
            case .concurrentRead: failure = .transportConcurrentRead
            case .invalidLimit: failure = .transportInvalidLimit
            case .scriptExhausted: failure = .transportScriptExhausted
            default: return
            }
        } else { return }
        await InvocationOwnerFailureScope.record(failure)
    }

    /// Replaces untrusted adapter error descriptions with bounded public categories.
    /// - Parameters:
    ///   - error: Adapter, body or cancellation failure after possible submission.
    ///   - safety: Explicit endpoint replay contract.
    /// - Returns: Safe cancellation/transport or indeterminate-mutation error.
    private func submissionFailure(_ error: any Error, safety: RetrySafety) -> any Error {
        let cancelled = error is CancellationError || Task.isCancelled
        let expired = (error as? TransportFailure) == .deadlineExceeded
        if safety == .unsafe {
            return DiscordError.unknownMutationOutcome(cancelled ? .cancelledAfterSubmission :
                (expired ? .deadlineAfterSubmission : .connectionLostAfterSubmission))
        }
        if cancelled { return CancellationError() }
        if expired { return TransportFailure.deadlineExceeded }
        if let error = error as? DiscordError { return error }
        return DiscordError.transport(.connectionFailed)
    }

    /// Builds the common rate/order partition, including declared global exemptions and egress.
    /// - Parameter endpoint: Operation carrying normalized route and major-resource identity.
    /// - Returns: Nonsecret bounded admission metadata with retained request byte accounting.
    private func rateRequest<Response: Sendable>(_ endpoint: Endpoint<Response>) -> RateLimitRequest {
        RateLimitRequest(identity: identity, route: endpoint.method + " " + endpoint.route,
            majorResource: endpoint.majorParameter ?? "", egress: egress,
            usesGlobalLimit: endpoint.usesGlobalLimit,
            usesEgressGlobalLimit: endpoint.authentication == .none && endpoint.usesGlobalLimit && egress != nil,
            queuedBytes: (endpoint.body?.accountedBytes ?? 0) + endpoint.accountedMetadataBytes)
    }

    /// Separates wire representations and client/endpoint acceptance and freshness contracts.
    /// Length prefixes retain exact tag boundaries, and sorted tags make set order irrelevant.
    /// - Parameter endpoint: Immutable descriptor carrying optional read policy.
    /// - Returns: Scoped representation including user-agent, byte/lifetime/retry bounds, exact TTL,
    ///   sorted tags and coalescing eligibility. Different client limits cannot be bypassed by reuse;
    ///   the representation is empty when read reuse is disabled, avoiding unnecessary body encoding.
    private func readKey<Response: Sendable>(_ endpoint: Endpoint<Response>) -> HTTPReadKey {
        guard endpoint.readPolicy != nil else { return HTTPReadKey(identity: identity, representation: "") }
        let ttl = endpoint.readPolicy?.timeToLive.map { duration in
            "\(duration.components.seconds):\(duration.components.attoseconds)"
        } ?? "none"
        let tags = (endpoint.readPolicy?.tags ?? []).sorted()
        let durations = [maximumExchangeDuration, retryPolicy.initialBackoff, retryPolicy.maximumBackoff].map {
            "\($0.components.seconds):\($0.components.attoseconds)"
        }
        let policy = ["client-policy", userAgent, String(maximumResponseBytes),
                      String(retryPolicy.maximumAttempts)] + durations +
                     ["read-policy", ttl, String(endpoint.readPolicy?.coalescing ?? false), String(tags.count)] + tags
        let suffix = policy.map { "\($0.utf8.count):\($0)" }.joined()
        return HTTPReadKey(identity: identity, representation: endpoint.cacheIdentity + suffix)
    }

    /// Applies conservative private-response freshness before cache insertion.
    /// Requests opt in separately; no-store/no-cache and Vary:* always refuse reuse.
    /// max-age and Expires/Date can shorten the requested TTL, while Age and elapsed
    /// exchange time reduce remaining freshness. Malformed explicit cache directives
    /// refuse insertion. This cache performs no conditional revalidation.
    /// - Parameters:
    ///   - requested: Positive endpoint freshness bound.
    ///   - headers: Successful response metadata, matched case-insensitively.
    ///   - elapsed: Nonnegative complete exchange time in the injected clock domain.
    /// - Returns: Positive remaining TTL, or nil when retention is forbidden/stale.
    private func cacheLifetime(requested: Duration, headers: [HTTPHeader], elapsed: Duration) -> Duration? {
        let directives = headers.filter { $0.name.lowercased() == "cache-control" }
            .flatMap { $0.value.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let names = directives.map {
            ($0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        }
        guard !names.contains("no-store"), !names.contains("no-cache"),
              !headers.filter({ $0.name.lowercased() == "vary" }).flatMap({ $0.value.split(separator: ",") })
                .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "*" }) else { return nil }
        var lifetime = requested
        var hasMaximumAge = false
        for (index, directive) in directives.enumerated() where names[index] == "max-age" {
            let fields = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            let raw = fields[1].trimmingCharacters(in: .whitespaces)
            let number = raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2
                ? String(raw.dropFirst().dropLast()) : raw
            guard let seconds = UInt64(number), seconds <= 2_592_000 else { return nil }
            lifetime = min(lifetime, .seconds(Int64(seconds)))
            hasMaximumAge = true
        }
        if !hasMaximumAge, let expires = headers.first(where: { $0.name.lowercased() == "expires" })?.value {
            guard let date = headers.first(where: { $0.name.lowercased() == "date" })?.value else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            guard let expiryDate = formatter.date(from: expires), let serverDate = formatter.date(from: date) else { return nil }
            let seconds = expiryDate.timeIntervalSince(serverDate)
            guard seconds.isFinite, seconds > 0, seconds <= 2_592_000 else { return nil }
            lifetime = min(lifetime, .seconds(seconds))
        }
        for age in headers.filter({ $0.name.lowercased() == "age" }) {
            guard let seconds = UInt64(age.value), seconds <= 2_592_000 else { return nil }
            lifetime = max(.zero, lifetime - .seconds(Int64(seconds)))
        }
        lifetime = max(.zero, lifetime - max(.zero, elapsed))
        return lifetime > .zero ? lifetime : nil
    }

    /// Normalizes decoder errors so server text, request paths and credentials cannot leak.
    /// - Parameters:
    ///   - endpoint: Synchronous deterministic descriptor decoder.
    ///   - data: Complete response bytes within the configured bound.
    /// - Returns: Typed successful value.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for every decoding failure.
    private func decode<Response: Sendable>(_ endpoint: Endpoint<Response>, data: Data) throws -> Response {
        DiscordLog.makeLogger("http.codec").trace("REST response decoding started", metadata: ["dk.event": "http.decode.started", "dk.bytes": .stringConvertible(data.count)])
        do {
            let value = try endpoint.decode(data)
            DiscordLog.makeLogger("http.codec").trace("REST response decoding completed", metadata: ["dk.event": "http.decode.completed"])
            return value
        } catch {
            DiscordLog.makeLogger("http.codec").debug("REST response decoding rejected", metadata: ["dk.event": "http.decode.rejected"])
            throw DiscordError.transport(.invalidResponse)
        }
    }
}

/// Attempt-local bounded wire result, never exposed through default diagnostics.
private struct WireReply: Sendable {
    let status: Int
    let headers: [HTTPHeader]
    let data: Data
}

/// Retains only whether a send may have started, allowing deadline races to preserve uncertainty.
private actor HTTPSubmissionEvidence {
    private var submitted = false
    /// Records conservative possible submission immediately before awaiting the adapter.
    func markSubmitted() { submitted = true }
    /// Clears possible submission after an explicit complete 429 rejection.
    func markRejected() { submitted = false }
    /// Returns whether an attempt may have reached the network without known rejection.
    /// - Returns: True after submission until a complete known rejection is recorded.
    func wasSubmitted() -> Bool { submitted }
}
