import Crypto
import DiscordLogging
import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// Durable admission outcome. Both cases certify that work and its duplicate marker are already
/// committed together in consumer-owned storage; this is not a report of handler execution finishing.
public enum WebhookEventAdmission: Sendable, Equatable {
    case accepted
    case alreadyAccepted
}

/// Bounded, independent webhook-event admission. Construction starts no tasks, listeners or network I/O.
/// Pass only verifier-produced requests and configure its replay policy to allow identical signed retries.
///
/// The durable hook must atomically persist recoverable work and an idempotency marker before returning
/// either success case. Only then is HTTP 204 returned. Throws, cancellation, overload and an in-flight
/// duplicate return HTTP 503 so Discord can retry. There is no internal retry or handler work queue.
/// Discord expects 204 within three seconds and retries with exponential backoff for up to ten minutes;
/// consumers must bound durable-store latency and arrange recovery/retention appropriate to that window.
///
/// SHA-256 of exact original body bytes is a stable delivery key, not a Discord event ID. Semantically
/// identical reserialized bodies can have different keys. Local retained keys only accelerate duplicates;
/// after eviction or process restart the durable hook remains the authority. This API promises neither
/// exactly-once effects nor event order. Share durable admission across workers for one application.
public actor WebhookEventProcessor {
    /// Consumer-owned atomic durable admission, invoked with envelope, original signed body and opaque key.
    public typealias DurableAdmission = @Sendable (WebhookEventEnvelope, Data, String) async throws -> WebhookEventAdmission

    private let applicationID: ApplicationID
    private let maximumConcurrentAdmissions: Int
    private let maximumRememberedDeliveries: Int
    private let limits: JSONLimits
    private let admit: DurableAdmission
    private var pending = Set<String>()
    private var accepted = Set<String>()
    private var acceptanceOrder: [String] = []

    /// Creates an application-scoped, queue-free event processor with explicit finite resource limits.
    /// - Parameters:
    ///   - applicationID: Only envelopes addressed to this application can be admitted or PING-acknowledged.
    ///   - maximumConcurrentAdmissions: Positive maximum suspended durable calls; default 32. Excess gets 503.
    ///   - maximumRememberedDeliveries: Nonnegative bounded FIFO of successful delivery digests; default 1,024.
    ///     Zero disables the optimization and delegates every completed retry to durable storage.
    ///   - limits: Complete authenticated JSON bounds; default 1 MiB, depth 64 and 100,000 nodes.
    ///   - admit: Cancellation-cooperative, latency-bounded durable transaction. Return success only after
    ///     durable work/duplicate ownership is established. Throw on unavailable/uncertain admission so
    ///     Discord may retry; on retry the transaction must resolve any prior ambiguous commit safely.
    /// - Throws: Sanitized invalid-value errors for nonsensical concurrency, retention or parser bounds.
    /// Initializing acquires no resources; the consumer owns and closes its durable store separately.
    public init(applicationID: ApplicationID, maximumConcurrentAdmissions: Int = 32,
                maximumRememberedDeliveries: Int = 1_024, limits: JSONLimits = .default,
                admit: @escaping DurableAdmission) throws {
        guard maximumConcurrentAdmissions > 0, maximumRememberedDeliveries >= 0,
              limits.maximumBytes > 0, (1...128).contains(limits.maximumDepth), limits.maximumNodes > 0
        else { throw DiscordError.validation(.invalidValue) }
        self.applicationID = applicationID
        self.maximumConcurrentAdmissions = maximumConcurrentAdmissions
        self.maximumRememberedDeliveries = maximumRememberedDeliveries
        self.limits = limits
        self.admit = admit
    }

    /// Admits one authenticated body and returns the corresponding empty HTTP response.
    /// - Parameter request: Exact body produced by SignedRequestVerifier, with identical retries permitted.
    /// - Returns: Empty 204 for valid PING or durably accepted/known duplicate events; 400 for malformed,
    ///   unsupported-version/kind or wrong-application envelopes; 503 for overload, cancellation, duplicate
    ///   still being admitted or durable errors. All statuses include a valid application/json content type.
    ///
    /// JSON parsing and digesting are synchronous and bounded. The sole suspension is consumer durable
    /// admission, with the pending reservation held across actor reentrancy and released on every exit.
    /// Cancellation before admission prevents work; cancellation after a successful commit returns 503,
    /// preserving the successful duplicate marker for a later retry. Errors never enter diagnostics.
    public func process(_ request: VerifiedDiscordRequest) async -> HTTPResponse {
        DiscordLog.makeLogger("interactions.webhooks").debug("Verified webhook event processing started", metadata: ["dk.event": "interactions.webhook.started"])
        guard !Task.isCancelled else { return response(503) }
        let envelope: WebhookEventEnvelope
        do { envelope = try WebhookEventEnvelope(data: request.rawBody, limits: limits) }
        catch {
            DiscordLog.makeLogger("interactions.webhooks").debug("Webhook event envelope decoding rejected", metadata: ["dk.event": "interactions.webhook.decode_rejected"])
            return response(400)
        }
        DiscordLog.makeLogger("interactions.webhooks").trace("Webhook event envelope decoded", metadata: ["dk.event": "interactions.webhook.decoded"])
        guard envelope.applicationID == applicationID, envelope.version == 1 else { return response(400) }
        if envelope.type.knownValue == .ping { return response(204) }
        guard envelope.type.knownValue == .event else { return response(400) }
        let key = SHA256.hash(data: request.rawBody).map { String(format: "%02x", $0) }.joined()
        if accepted.contains(key) {
            DiscordLog.makeLogger("interactions.webhooks").trace("Previously accepted webhook delivery reused", metadata: ["dk.event": "interactions.webhook.duplicate_accepted"])
            return response(204)
        }
        guard pending.count < maximumConcurrentAdmissions, !pending.contains(key) else {
            DiscordLog.makeLogger("interactions.webhooks").debug("Webhook durable admission is temporarily unavailable", metadata: ["dk.event": "interactions.webhook.admission_unavailable", "dk.active": .stringConvertible(pending.count)])
            return response(503)
        }
        pending.insert(key)
        DiscordLog.makeLogger("interactions.webhooks").trace("Webhook durable admission reserved", metadata: ["dk.event": "interactions.webhook.admitted", "dk.active": .stringConvertible(pending.count)])
        defer {
            pending.remove(key)
            DiscordLog.makeLogger("interactions.webhooks").trace("Webhook durable admission released", metadata: ["dk.event": "interactions.webhook.released", "dk.active": .stringConvertible(pending.count)])
        }
        do {
            DiscordLog.makeLogger("interactions.webhooks").trace("Invoking consumer durable webhook transaction", metadata: ["dk.event": "interactions.webhook.persisting"])
            _ = try await admit(envelope, request.rawBody, key)
            DiscordLog.makeLogger("interactions.webhooks").debug("Durable webhook admission confirmed", metadata: ["dk.event": "interactions.webhook.persisted"])
            remember(key)
            return response(Task.isCancelled ? 503 : 204)
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            DiscordLog.makeLogger("interactions.webhooks").log(level: cancelled ? .debug : .warning, "Durable webhook admission failed; delivery remains retryable", metadata: ["dk.event": "interactions.webhook.persistence_failed", "dk.cancelled": .stringConvertible(cancelled)])
            return response(503)
        }
    }

    /// Adds a successful fixed-size digest and evicts the oldest retained digest when at capacity.
    /// - Parameter key: SHA-256 digest belonging to a successfully committed durable admission.
    /// Zero retention performs no allocation. Eviction affects performance only; durable idempotency
    /// remains required. Work is bounded by configured retention and actor-isolated without suspension.
    private func remember(_ key: String) {
        guard maximumRememberedDeliveries > 0 else { return }
        if accepted.count == maximumRememberedDeliveries {
            accepted.remove(acceptanceOrder.removeFirst())
            DiscordLog.makeLogger("interactions.webhooks").trace("Old webhook duplicate hint evicted", metadata: ["dk.event": "interactions.webhook.hint_evicted"])
        }
        accepted.insert(key)
        acceptanceOrder.append(key)
    }

    /// Constructs an empty response with the content type required by Discord's PING validation.
    /// - Parameter status: HTTP status selected by admission policy; only 204, 400 and 503 are used.
    /// - Returns: A body-free response with no owned streams or cleanup obligations.
    private func response(_ status: Int) -> HTTPResponse {
        DiscordLog.makeLogger("interactions.webhooks").trace("Webhook event HTTP outcome prepared", metadata: ["dk.event": "interactions.webhook.response_prepared", "dk.status": .stringConvertible(status)])
        return HTTPResponse(status: status, headers: [HTTPHeader(name: "Content-Type", value: "application/json")])
    }
}
