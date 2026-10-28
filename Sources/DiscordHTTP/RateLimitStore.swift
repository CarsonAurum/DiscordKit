// File: Sources/DiscordHTTP/RateLimitStore.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTransport
import Foundation

/// An opaque credential/authorization partition. Reuse this value across clients
/// using the same credential; create a new value on credential or scope rotation.
/// Resource and egress restrictions remain separately scoped across that rotation.
public struct RateLimitIdentity: Sendable, Hashable {
    public let value: UUID

    /// Creates a non-secret partition identifier without retaining a credential.
    /// - Parameter value: Stable externally coordinated identifier, or a fresh UUID.
    public init(_ value: UUID = UUID()) { self.value = value }
}

/// Admission context containing no authorization header or raw credential.
public struct RateLimitRequest: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let identity: RateLimitIdentity
    public let route: String
    public let majorResource: String
    public let egress: UUID?
    public let usesGlobalLimit: Bool
    /// Uses the outbound-IP global budget for requests without Authorization instead of a credential budget.
    /// A nonnil egress is required; `usesGlobalLimit == false` bypasses both global budgets.
    public let usesEgressGlobalLimit: Bool
    public let queuedBytes: Int
    public let schedulingClass: SchedulingClass

    /// Conceals raw route/resource text, including tokens supplied through raw descriptors.
    public var description: String { "RateLimitRequest(redacted)" }
    /// Uses the same redacted marker in debug output.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostics from exposing route or resource components.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Defines rate and queue scopes for one attempt, including retries.
    /// - Parameters:
    ///   - identity: Shared opaque credential/authorization identity.
    ///   - route: Canonical method/route template; never include webhook tokens or query secrets.
    ///   - majorResource: Stable non-secret major resource identifier; empty for no major resource.
    ///   - egress: Shared outbound-IP partition, or nil when the caller cannot identify it.
    ///     Fleet clients sharing an egress must supply the same value to coordinate invalid responses
    ///     and the unauthenticated IP-global window when `usesEgressGlobalLimit` is true.
    ///   - usesGlobalLimit: False for documented globally exempt interaction operations only.
    ///   - usesEgressGlobalLimit: True for unauthenticated webhook-token operations sharing an outbound-IP
    ///     global limit; defaults to false. Requires a nonnil egress and replaces credential-global admission.
    ///     The `usesGlobalLimit == false` interaction exemption skips both global budgets entirely.
    ///   - queuedBytes: Nonnegative retained request byte estimate, default zero.
    ///   - schedulingClass: FIFO scheduling class, ordinary by default.
    public init(identity: RateLimitIdentity, route: String, majorResource: String = "",
                egress: UUID? = nil, usesGlobalLimit: Bool = true, usesEgressGlobalLimit: Bool = false, queuedBytes: Int = 0,
                schedulingClass: SchedulingClass = .ordinary) {
        self.identity = identity
        self.route = route
        self.majorResource = majorResource
        self.egress = egress
        self.usesGlobalLimit = usesGlobalLimit
        self.usesEgressGlobalLimit = usesEgressGlobalLimit
        self.queuedBytes = queuedBytes
        self.schedulingClass = schedulingClass
    }
}

/// A single-use, expiring admission token. Start sending promptly and never start
/// a new send at or after expiry. Expiry cannot recall a network write already sent.
public struct RateLimitReservation<Instant: InstantProtocol>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable where Instant.Duration == Duration {
    public let id: UUID
    public let request: RateLimitRequest
    public let expiresAt: Instant

    /// Conceals ownership tokens and potentially sensitive raw request scopes.
    public var description: String { "RateLimitReservation(redacted)" }
    /// Uses the same marker in debug output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding ownership or raw route metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Creates an adapter-issued reservation. External stores must ensure unique IDs.
    /// - Parameters:
    ///   - id: Unique, unguessable ownership token.
    ///   - request: Exact admitted scope; must not be changed after admission.
    ///   - expiresAt: Clock-local inclusive expiration; caller and store share a time domain.
    public init(id: UUID, request: RateLimitRequest, expiresAt: Instant) {
        self.id = id; self.request = request; self.expiresAt = expiresAt
    }
}

/// Atomic reservation result. A retry result never grants permission to send.
public enum RateLimitAdmission<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration {
    case admitted(RateLimitReservation<Instant>)
    case retry(at: Instant)
}

/// Completion uncertainty. Neither outcome refunds rate quota: a reservation may
/// already have influenced overlapping requests, even if its own send was canceled.
public enum RateLimitReleaseOutcome: Sendable {
    case notSent
    case uncertain
}

/// Injectable atomic authority shared by every worker using a credential.
///
/// Implementations must atomically debit applicable budgets before granting a
/// token, bound ownership and metadata, reject stale completion and fail closed
/// during outages. Composite implementations may conservatively consume quota on
/// refused admission, but must never over-admit. Cancellation/release does not
/// refund possible sends. External stores must use a common monotonic time domain
/// or translate instants at their boundary; raw process-local instants are not a
/// cross-host clock protocol. Durable adapters require the same contract tests.
public protocol RateLimitStore<Instant>: Sendable {
    associatedtype Instant: InstantProtocol where Instant.Duration == Duration

    /// Attempts one atomic admission without waiting for a budget reset.
    /// - Parameters:
    ///   - request: Non-secret scopes and nonnegative resource accounting.
    ///   - now: Current instant in the authority's shared time domain.
    /// - Returns: Expiring permission or the earliest useful retry instant.
    /// - Throws: Validation, capacity, cancellation or coordinator availability failures.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant>

    /// Incorporates a response before releasing ownership; fractional relative delays
    /// take precedence over wall-clock reset timestamps, avoiding clock skew.
    /// - Parameters:
    ///   - reservation: Unexpired token issued by this store.
    ///   - status: HTTP response status.
    ///   - headers: Ordered wire headers, matched case-insensitively.
    ///   - retryAfter: Decoded 429 body delay, if valid; combined conservatively with headers.
    ///   - global: Decoded 429 body global flag; false when absent.
    ///   - now: Response observation instant.
    /// - Throws: Stale/unknown token, metadata capacity, or authority failure. Never bypass on failure.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                  retryAfter: Duration?, global: Bool, now: Instant) async throws

    /// Releases in-flight ownership without refunding consumed quota.
    /// - Parameters:
    ///   - reservation: Token issued by this store; repeated releases are rejected.
    ///   - outcome: Whether no send occurred or the outcome is uncertain.
    ///   - now: Current instant, used for ownership expiry.
    /// - Throws: Unknown/expired token or authority failure.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws

    /// Captures aggregate counts without exposing credential/resource labels.
    /// - Returns: Active reservations and retained rate metadata; queue counters are zero.
    func snapshot() async -> SchedulingSnapshot
}

/// Bounded in-process authority with up to eight fixed rate-state partitions. Credential
/// route/global and outbound-IP global state select their own bounded partition; only finite
/// aggregate ownership accounting uses a common small gate. Share this instance across local
/// clients using the same credentials or outbound IP, including independently rotated tokens.
///
/// Bucket aliases are retained rather than unsafely forgetting a learned grouping.
/// Each partition has a fixed share of the aggregate metadata cap; a skewed
/// workload can exhaust that share before the aggregate count reaches its cap.
/// Metadata exhaustion rejects discovery until safely expired provisional/scope
/// state can be removed. This favors safety over unrestricted route cardinality.
public final class InProcessRateLimitStore<Instant: InstantProtocol>: RateLimitStore where Instant.Duration == Duration {
    private let policy: SchedulingPolicy
    private let partitions: [RateLimitPartition<Instant>]
    private let ownership: RateLimitOwnership<Instant>

    /// Creates fixed bounded partitions and no background tasks or network resources.
    /// - Parameter policy: Aggregate budgets, conservative discovery windows and lease duration.
    public init(policy: SchedulingPolicy = .init()) {
        self.policy = policy
        let count = min(8, max(1, policy.maximumMetadata / 8))
        self.partitions = (0..<count).map { index in
            RateLimitPartition(policy: policy,
                               capacity: policy.maximumMetadata / count + (index < policy.maximumMetadata % count ? 1 : 0))
        }
        self.ownership = RateLimitOwnership(policy: policy)
    }

    /// Atomically reserves bounded ownership and all applicable rate scopes.
    /// Staged scope refusal conservatively retains any already consumed quota.
    /// - Parameters:
    ///   - request: Request scopes; bytes/route length and required egress-global identity are validated.
    ///     Egress-global requests debit the shared IP window before their credential-scoped route;
    ///     route refusal/cancellation clears concurrency while conservatively retaining any earlier debit.
    ///   - now: Monotonic current instant.
    /// - Returns: A single-use token or finite retry instant.
    /// - Throws: Cancellation, invalid request or metadata exhaustion; never fails open.
    public func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        try Task.checkCancellation()
        guard request.queuedBytes >= 0, !request.route.isEmpty, request.route.utf8.count <= 1_024,
              request.majorResource.utf8.count <= 256,
              !request.usesEgressGlobalLimit || request.egress != nil else { throw RateLimitFailure.invalidRequest }
        guard let token = try await ownership.reserve(request, now: now) else {
            return .retry(at: now.advanced(by: policy.fairnessInterval))
        }
        var egressReserved = false
        var routeReserved = false
        do {
            if !request.majorResource.isEmpty,
               let wait = await partition(for: request.majorResource).scopeDelay(.shared(request.majorResource), now: now) {
                _ = try await ownership.remove(token, now: now)
                return .retry(at: wait)
            }
            if let egress = request.egress,
               let wait = await partition(for: egress).scopeDelay(.egress(egress), now: now) {
                _ = try await ownership.remove(token, now: now)
                return .retry(at: wait)
            }
            if request.usesGlobalLimit, request.usesEgressGlobalLimit, let egress = request.egress {
                if let wait = try await partition(for: egress).reserveEgressGlobal(egress, now: now) {
                    _ = try await ownership.remove(token, now: now)
                    return .retry(at: wait)
                }
                egressReserved = true
            }
            if let wait = try await partition(for: request.identity).reserve(request, now: now) {
                if egressReserved, let egress = request.egress {
                    await partition(for: egress).releaseEgressGlobal(egress)
                    egressReserved = false
                }
                _ = try await ownership.remove(token, now: now)
                return .retry(at: wait)
            }
            routeReserved = true
            // Cancellation after debit consumes quota; release removes only ownership.
            try Task.checkCancellation()
            return .admitted(token)
        } catch {
            if routeReserved { await partition(for: request.identity).release(request) }
            if egressReserved, let egress = request.egress { await partition(for: egress).releaseEgressGlobal(egress) }
            _ = try? await ownership.remove(token, now: now)
            throw error
        }
    }

    /// Learns headers, preserves outstanding debits and updates resource/IP-global/invalid-response protection.
    /// - Parameters:
    ///   - reservation: Owned token, consumed even if later metadata learning fails.
    ///   - status: HTTP status; 401/403/nonshared 429 count toward egress protection.
    ///   - headers: Wire rate metadata, parsed case-insensitively.
    ///   - retryAfter: Optional decoded relative 429 delay, nonnegative and finite.
    ///   - global: Optional decoded global 429 flag. Credential requests update their credential budget;
    ///     egress-global requests update the shared outbound-IP budget and globally exempt requests update neither.
    ///   - now: Observation instant in this store's clock domain.
    /// - Throws: Ownership/expiry or metadata errors; original debits are never refunded.
    public func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                         retryAfter: Duration? = nil, global: Bool = false, now: Instant) async throws {
        let owned: RateLimitReservation<Instant>
        do { owned = try await ownership.remove(reservation, now: now) }
        catch RateLimitFailure.reservationExpired {
            await releaseConcurrency(reservation.request)
            throw RateLimitFailure.reservationExpired
        }
        let observation = RateLimitObservation(status: status, headers: headers, retryAfter: retryAfter, global: global)
        do {
            try await partition(for: owned.request.identity).complete(owned.request, observation: observation, now: now)
        } catch {
            // Route completion always releases its own concurrency, including metadata-learning failures.
            if owned.request.usesGlobalLimit, owned.request.usesEgressGlobalLimit, let egress = owned.request.egress {
                await partition(for: egress).releaseEgressGlobal(egress)
            }
            await ownership.failClosed()
            throw error
        }
        do {
            if owned.request.usesGlobalLimit, owned.request.usesEgressGlobalLimit, let egress = owned.request.egress {
                try await partition(for: egress).completeEgressGlobal(egress, observation: observation, now: now)
            }
            if observation.shared, status == 429, !owned.request.majorResource.isEmpty {
                try await partition(for: owned.request.majorResource).block(.shared(owned.request.majorResource),
                    delay: observation.retryAfter ?? policy.provisionalWindow, now: now)
            }
            if let egress = owned.request.egress, status == 401 || status == 403 || (status == 429 && !observation.shared) {
                try await partition(for: egress).recordInvalid(egress, now: now)
            }
        } catch {
            await ownership.failClosed()
            throw error
        }
    }

    /// Releases concurrency without refunding route, credential, IP-global or uncertainty budgets.
    /// - Parameters:
    ///   - reservation: Owned single-use token.
    ///   - outcome: Cancellation certainty; both cases retain the conservative debit.
    ///   - now: Current monotonic instant.
    /// - Throws: Unknown/expired ownership; an expired release still clears its retained concurrency.
    public func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        let owned: RateLimitReservation<Instant>
        do { owned = try await ownership.remove(reservation, now: now) }
        catch RateLimitFailure.reservationExpired {
            await releaseConcurrency(reservation.request)
            throw RateLimitFailure.reservationExpired
        }
        await releaseConcurrency(owned.request)
    }

    /// Captures finite ownership and metadata counts across the fixed partition set.
    /// - Returns: Store counts; queue ownership belongs to the coordinator.
    public func snapshot() async -> SchedulingSnapshot {
        var metadata = 0
        for partition in partitions { metadata += await partition.metadataCount() }
        return SchedulingSnapshot(queuedCount: 0, queuedBytes: 0,
                                  activeCount: await ownership.count(), metadataCount: metadata)
    }

    /// Selects a stable process-local partition without retaining extra directory entries.
    /// - Parameter key: Non-secret identity, resource or egress key.
    /// - Returns: One of the fixed bounded rate-state actors.
    private func partition<Key: Hashable>(for key: Key) -> RateLimitPartition<Instant> {
        partitions[Int(UInt(bitPattern: key.hashValue) % UInt(partitions.count))]
    }

    /// Clears all concurrency retained by a successfully admitted request, including inclusive lease expiry.
    /// - Parameter request: Exact originally owned request; only ownership-verified callers invoke this helper.
    /// No rate debit is refunded. The two fixed actors may suspend independently without granting new quota.
    private func releaseConcurrency(_ request: RateLimitRequest) async {
        await partition(for: request.identity).release(request)
        if request.usesGlobalLimit, request.usesEgressGlobalLimit, let egress = request.egress {
            await partition(for: egress).releaseEgressGlobal(egress)
        }
    }
}

/// Minimal aggregate in-flight gate; substantive rate state lives in partition actors.
private actor RateLimitOwnership<Instant: InstantProtocol> where Instant.Duration == Duration {
    let policy: SchedulingPolicy
    var active: [UUID: RateLimitReservation<Instant>] = [:]
    var perIdentity: [RateLimitIdentity: Int] = [:]
    var unavailable = false

    /// Stores finite limits without creating per-identity state before admission.
    /// - Parameter policy: Aggregate and per-identity active limits.
    init(policy: SchedulingPolicy) { self.policy = policy }

    /// Allocates a token only when both active limits permit it.
    /// - Parameters:
    ///   - request: Admitted identity and request scopes.
    ///   - now: Instant used to assign the inclusive expiration.
    /// - Returns: Token, or nil for transient saturation.
    /// - Throws: coordinatorUnavailable when response metadata could not be retained.
    func reserve(_ request: RateLimitRequest, now: Instant) throws -> RateLimitReservation<Instant>? {
        guard !unavailable else { throw RateLimitFailure.coordinatorUnavailable }
        guard active.count < policy.maximumConcurrentRequests,
              perIdentity[request.identity, default: 0] < policy.maximumConcurrentRequestsPerIdentity else { return nil }
        let token = RateLimitReservation(id: UUID(), request: request, expiresAt: now.advanced(by: policy.reservationLifetime))
        active[token.id] = token
        perIdentity[request.identity, default: 0] += 1
        return token
    }

    /// Consumes exact ownership once, including on expired completion.
    /// Expiry does not automatically free slots: callers must release uncertain sends,
    /// and an external crashed-worker adapter must fence sends before lease reclamation.
    /// - Parameters:
    ///   - reservation: Original token, whose scope must match retained ownership.
    ///   - now: Current instant; late completion is rejected without learning stale headers.
    /// - Returns: Original retained token.
    /// - Throws: Unknown/mismatched token or inclusive expiry.
    func remove(_ reservation: RateLimitReservation<Instant>, now: Instant) throws -> RateLimitReservation<Instant> {
        guard let token = active[reservation.id], token.request == reservation.request,
              token.expiresAt == reservation.expiresAt else { throw RateLimitFailure.unknownReservation }
        active.removeValue(forKey: token.id)
        let remaining = perIdentity[token.request.identity, default: 1] - 1
        if remaining == 0 { perIdentity.removeValue(forKey: token.request.identity) }
        else { perIdentity[token.request.identity] = remaining }
        guard now < token.expiresAt else { throw RateLimitFailure.reservationExpired }
        return token
    }

    /// Stops future shared admission after response learning could not retain a restriction.
    func failClosed() { unavailable = true }

    /// Returns currently retained tokens, excluding completed/released requests.
    /// - Returns: Nonnegative active ownership count.
    func count() -> Int { active.count }
}

/// A bounded key; secrets are excluded by the public admission contract.
private enum RateLimitKey: Hashable, Sendable {
    case route(RateLimitIdentity, String, String)
    case bucket(RateLimitIdentity, String, String)
    case global(RateLimitIdentity)
    case shared(String)
    case egress(UUID)
    case egressGlobal(UUID)
}

/// Parsed relative server metadata. Malformed values are ignored conservatively.
private struct RateLimitObservation: Sendable {
    let status: Int
    let bucket: String?
    let limit: Int?
    let remaining: Int?
    let resetAfter: Duration?
    let retryAfter: Duration?
    let global: Bool
    let shared: Bool

    /// Parses known headers without depending on header casing or wall-clock epochs.
    /// - Parameters:
    ///   - status: HTTP status for 429 treatment.
    ///   - headers: Ordered headers; first matching header wins.
    ///   - retryAfter: Decoded body delay; negative values are ignored.
    ///   - global: Decoded global flag, combined with known header flags.
    init(status: Int, headers: [HTTPHeader], retryAfter: Duration?, global: Bool) {
        self.status = status
        let bucket = headers.first { $0.name.lowercased() == "x-ratelimit-bucket" }?.value
        self.bucket = bucket.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }
        self.limit = Self.integer("x-ratelimit-limit", headers: headers).flatMap { $0 > 0 ? $0 : nil }
        self.remaining = Self.integer("x-ratelimit-remaining", headers: headers)
        self.resetAfter = Self.delay("x-ratelimit-reset-after", headers: headers)
        let headerDelay = Self.delay("retry-after", headers: headers)
        let bodyDelay = retryAfter.flatMap { $0 >= .zero && $0 <= .seconds(2_592_000) ? $0 : nil }
        self.retryAfter = [headerDelay, bodyDelay].compactMap { $0 }.max()
        let scope = headers.first { $0.name.lowercased() == "x-ratelimit-scope" }?.value.lowercased()
        self.global = global || scope == "global" || headers.contains {
            $0.name.lowercased() == "x-ratelimit-global" && $0.value.lowercased() == "true"
        }
        self.shared = scope == "shared"
    }

    /// Reads a nonnegative bounded integer, excluding overflow and malformed values.
    /// - Parameters:
    ///   - name: Lowercase header name.
    ///   - headers: Wire metadata.
    /// - Returns: A count no larger than one billion, or nil for invalid/missing input.
    private static func integer(_ name: String, headers: [HTTPHeader]) -> Int? {
        guard let value = headers.first(where: { $0.name.lowercased() == name })?.value,
              let result = Int(value), result >= 0, result <= 1_000_000_000 else { return nil }
        return result
    }

    /// Reads a fractional relative delay while bounding Duration conversion.
    /// - Parameters:
    ///   - name: Lowercase header name.
    ///   - headers: Wire metadata.
    /// - Returns: Delay from zero through 30 days, or nil for missing/nonfinite values.
    private static func delay(_ name: String, headers: [HTTPHeader]) -> Duration? {
        guard let value = headers.first(where: { $0.name.lowercased() == name })?.value,
              let seconds = Double(value), seconds.isFinite, seconds >= 0, seconds <= 2_592_000 else { return nil }
        return .seconds(seconds)
    }
}

/// One fixed actor-owned identity/resource partition. Metadata is never unbounded.
private actor RateLimitPartition<Instant: InstantProtocol> where Instant.Duration == Duration {
    private struct Budget: Sendable {
        var limit: Int
        var remaining: Int
        var reset: Instant
        var window: Duration
        var inFlight: Int = 0
        var learned: Bool = false
        var invalid: Int = 0
    }
    private let policy: SchedulingPolicy
    private let capacity: Int
    private var budgets: [RateLimitKey: Budget] = [:]
    private var aliases: [RateLimitKey: RateLimitKey] = [:]

    /// Creates a fixed share of the total metadata cap.
    /// - Parameters:
    ///   - policy: Provisional/global/egress rules.
    ///   - capacity: Positive metadata slots assigned to this partition.
    init(policy: SchedulingPolicy, capacity: Int) { self.policy = policy; self.capacity = capacity }

    /// Debits a route and applicable credential-global window without suspension.
    /// - Parameters:
    ///   - request: Opaque identity/major-resource scopes.
    ///   - now: Admission time.
    /// - Returns: Required retry instant, or nil when both debits succeeded.
    /// - Throws: Metadata exhaustion; existing depleted state remains retained.
    func reserve(_ request: RateLimitRequest, now: Instant) throws -> Instant? {
        let route = RateLimitKey.route(request.identity, request.route, request.majorResource)
        let key = aliases[route] ?? route
        let global = RateLimitKey.global(request.identity)
        let credentialGlobal = request.usesGlobalLimit && !request.usesEgressGlobalLimit
        let required = [key] + (credentialGlobal ? [global] : [])
        try makeRoom(for: required.filter { budgets[$0] == nil }.count, now: now, preserving: Set(required))
        if budgets[key] == nil {
            budgets[key] = Budget(limit: 1, remaining: 1, reset: now.advanced(by: policy.provisionalWindow),
                                  window: policy.provisionalWindow)
        }
        if credentialGlobal, budgets[global] == nil {
            budgets[global] = Budget(limit: policy.initialGlobalRequestsPerSecond,
                remaining: policy.initialGlobalRequestsPerSecond, reset: now.advanced(by: .seconds(1)), window: .seconds(1))
        }
        var wait: Instant?
        for budgetKey in required {
            refresh(budgetKey, now: now)
            if let budget = budgets[budgetKey], budget.remaining <= 0 {
                wait = max(wait ?? budget.reset, budget.reset)
            }
        }
        if let wait { return max(wait, now.advanced(by: policy.fairnessInterval)) }
        for budgetKey in required {
            budgets[budgetKey]?.remaining -= 1
            budgets[budgetKey]?.inFlight += 1
        }
        return nil
    }

    /// Reserves the unauthenticated outbound-IP startup window before an independently partitioned route.
    /// - Parameters:
    ///   - egress: Shared non-secret IP identity, independent of rotating webhook-token credentials.
    ///   - now: Common monotonic admission instant.
    /// - Returns: Required retry instant or nil after debiting one allowance and retaining one concurrency slot.
    /// - Throws: Bounded metadata exhaustion before permission is issued; callers never bypass this failure.
    /// The fixed one-second startup allowance uses the existing global-rate policy. Later route refusal
    /// clears concurrency but cannot refund this debit, preserving conservative composite admission.
    func reserveEgressGlobal(_ egress: UUID, now: Instant) throws -> Instant? {
        let key = RateLimitKey.egressGlobal(egress)
        try makeRoom(for: budgets[key] == nil ? 1 : 0, now: now, preserving: [key])
        if budgets[key] == nil {
            budgets[key] = Budget(limit: policy.initialGlobalRequestsPerSecond,
                remaining: policy.initialGlobalRequestsPerSecond, reset: now.advanced(by: .seconds(1)), window: .seconds(1))
        }
        refresh(key, now: now)
        if let budget = budgets[key], budget.remaining <= 0 {
            return max(budget.reset, now.advanced(by: policy.fairnessInterval))
        }
        budgets[key]?.remaining -= 1
        budgets[key]?.inFlight += 1
        return nil
    }

    /// Learns a global 429 for the exact outbound IP and always releases its retained concurrency.
    /// - Parameters:
    ///   - egress: Originally reserved IP-global identity; no credential identity participates in this key.
    ///   - observation: Complete parsed response metadata; only global 429 observations extend this scope.
    ///   - now: Response observation instant in the shared monotonic domain.
    /// - Throws: Metadata exhaustion while learning the restriction; the owning store then fails closed.
    /// Completion never refunds startup debits or changes limits from route-specific response headers.
    func completeEgressGlobal(_ egress: UUID, observation: RateLimitObservation, now: Instant) throws {
        defer { releaseEgressGlobal(egress) }
        if observation.status == 429, observation.global {
            try block(.egressGlobal(egress), delay: observation.retryAfter ?? policy.provisionalWindow, now: now)
        }
    }

    /// Releases exactly one owned IP-global concurrency slot without refunding its consumed request allowance.
    /// - Parameter egress: Original admitted IP identity; ownership validation prevents repeated invocation.
    /// Missing state is tolerated defensively; live owned budgets are never reclaimed by metadata eviction.
    func releaseEgressGlobal(_ egress: UUID) {
        let key = RateLimitKey.egressGlobal(egress)
        if var budget = budgets[key] {
            budget.inFlight = max(0, budget.inFlight - 1)
            budgets[key] = budget
        }
    }

    /// Merges provisional routes into learned bucket identities while retaining
    /// major resources and subtracting other in-flight observations conservatively.
    /// - Parameters:
    ///   - request: Original admitted request.
    ///   - observation: Parsed server metadata.
    ///   - now: Response observation time.
    /// - Throws: Safe metadata discovery refusal; ownership debits are still released.
    func complete(_ request: RateLimitRequest, observation: RateLimitObservation, now: Instant) throws {
        defer { release(request) }
        let route = RateLimitKey.route(request.identity, request.route, request.majorResource)
        var key = aliases[route] ?? route
        if let hash = observation.bucket {
            let learnedKey = RateLimitKey.bucket(request.identity, hash, request.majorResource)
            if key != learnedKey {
                // Replacing a provisional budget needs one extra alias slot. Never drop an exhausted budget.
                let added = (budgets[learnedKey] == nil ? 1 : 0) + (aliases[route] == nil ? 1 : 0)
                try makeRoom(for: max(0, added - (budgets[key] == nil ? 0 : 1)), now: now)
                if let previous = budgets.removeValue(forKey: key) {
                    if var merged = budgets[learnedKey] {
                        merged.remaining = min(merged.remaining, previous.remaining)
                        merged.reset = max(merged.reset, previous.reset)
                        merged.inFlight += previous.inFlight
                        budgets[learnedKey] = merged
                    } else { budgets[learnedKey] = previous }
                    // Existing aliases can still point at an older learned bucket after a hash change.
                    for alias in aliases.keys where aliases[alias] == key { aliases[alias] = learnedKey }
                }
                aliases[route] = learnedKey
                key = learnedKey
            }
        }
        if var budget = budgets[key] {
            let previouslyLearned = budget.learned
            if let limit = observation.limit { budget.limit = limit }
            if let reset = observation.resetAfter {
                budget.window = max(reset, policy.fairnessInterval)
                budget.reset = budget.learned ? max(budget.reset, now.advanced(by: reset)) : now.advanced(by: reset)
            }
            if let remaining = observation.remaining {
                let candidate = max(0, remaining - max(0, budget.inFlight - 1))
                budget.remaining = budget.learned ? min(budget.remaining, candidate) : candidate
                budget.learned = true
            }
            if observation.status == 429 {
                budget.remaining = 0
                let retry = now.advanced(by: observation.retryAfter ?? policy.provisionalWindow)
                budget.reset = previouslyLearned ? max(budget.reset, retry) : retry
            }
            budgets[key] = budget
        }
        if request.usesGlobalLimit, !request.usesEgressGlobalLimit, observation.status == 429, observation.global {
            try block(.global(request.identity), delay: observation.retryAfter ?? policy.provisionalWindow, now: now)
        }
    }

    /// Frees route/global concurrency without refunding uncertainty or rate debits.
    /// - Parameter request: Original reservation request; repeated release is prevented by ownership.
    func release(_ request: RateLimitRequest) {
        let route = RateLimitKey.route(request.identity, request.route, request.majorResource)
        let key = aliases[route] ?? route
        if var budget = budgets[key] {
            budget.inFlight = max(0, budget.inFlight - 1)
            budgets[key] = budget
        }
        let global = RateLimitKey.global(request.identity)
        if request.usesGlobalLimit, !request.usesEgressGlobalLimit, var budget = budgets[global] {
            budget.inFlight = max(0, budget.inFlight - 1)
            budgets[global] = budget
        }
    }

    /// Reads a shared-resource/egress block without allocating metadata on every request.
    /// - Parameters:
    ///   - key: Applicable non-credential scope.
    ///   - now: Current instant.
    /// - Returns: Block expiry, or nil when eligible.
    func scopeDelay(_ key: RateLimitKey, now: Instant) -> Instant? {
        guard let budget = budgets[key], budget.reset > now, budget.remaining == 0 else { return nil }
        return budget.reset
    }

    /// Conservatively extends a resource/global block, retaining the latest deadline.
    /// - Parameters:
    ///   - key: Scope receiving the block.
    ///   - delay: Nonnegative relative wait.
    ///   - now: Response observation instant.
    /// - Throws: Metadata exhaustion without evicting live/exhausted state.
    func block(_ key: RateLimitKey, delay: Duration, now: Instant) throws {
        if budgets[key] == nil { try makeRoom(for: 1, now: now) }
        var budget = budgets[key] ?? Budget(limit: 1, remaining: 0, reset: now, window: policy.provisionalWindow)
        budget.remaining = 0
        budget.reset = max(budget.reset, now.advanced(by: delay))
        budgets[key] = budget
    }

    /// Counts invalid responses since the last full quiet interval and trips early.
    /// Extending the quiet interval conservatively covers rolling server windows
    /// with constant metadata; low continuous invalid traffic may trip earlier.
    /// - Parameters:
    ///   - egress: Opaque outbound-IP identity shared across credentials.
    ///   - now: Response observation time.
    /// - Throws: Metadata exhaustion; callers must stop admitting through a failed authority.
    func recordInvalid(_ egress: UUID, now: Instant) throws {
        let key = RateLimitKey.egress(egress)
        if budgets[key] == nil { try makeRoom(for: 1, now: now) }
        var budget = budgets[key] ?? Budget(limit: 1, remaining: 1, reset: now, window: policy.invalidRequestWindow)
        if budget.reset <= now {
            budget.invalid = 0; budget.remaining = 1
            budget.reset = now.advanced(by: policy.invalidRequestWindow)
        }
        // Reset only after a full quiet interval. This conservatively covers every
        // rolling server window without retaining one timestamp per response.
        budget.reset = max(budget.reset, now.advanced(by: policy.invalidRequestWindow))
        if budget.invalid < policy.invalidRequestThreshold { budget.invalid += 1 }
        if budget.invalid >= policy.invalidRequestThreshold { budget.remaining = 0 }
        budgets[key] = budget
    }

    /// Returns all retained rate records and aliases within this fixed partition.
    /// - Returns: A nonnegative count no greater than the assigned capacity.
    func metadataCount() -> Int { budgets.count + aliases.count }

    /// Rolls elapsed windows forward while reserving room for outstanding sends.
    /// - Parameters:
    ///   - key: Existing rate budget key.
    ///   - now: Current monotonic instant.
    private func refresh(_ key: RateLimitKey, now: Instant) {
        guard var budget = budgets[key], budget.reset <= now else { return }
        budget.remaining = max(0, budget.limit - budget.inFlight)
        budget.reset = now.advanced(by: budget.window)
        budgets[key] = budget
    }

    /// Removes only expired unlearned records with no owners or aliases.
    /// Learned grouping is deliberately retained; refusal is safer than quota reset.
    /// - Parameters:
    ///   - additional: Number of new metadata slots required.
    ///   - now: Time used to prove window expiration.
    ///   - preserving: Existing keys needed by the pending atomic allocation; never reclaim these.
    /// - Throws: `metadataFull` if safe reclamation cannot make enough room.
    private func makeRoom(for additional: Int, now: Instant, preserving: Set<RateLimitKey> = []) throws {
        guard metadataCount() + additional > capacity else { return }
        let referenced = Set(aliases.values)
        let expired = budgets.filter { key, budget in
            budget.reset <= now && budget.inFlight == 0 && !budget.learned
                && !referenced.contains(key) && !preserving.contains(key)
        }.map(\.key)
        for key in expired {
            budgets.removeValue(forKey: key)
            if metadataCount() + additional <= capacity { return }
        }
        guard metadataCount() + additional <= capacity else { throw RateLimitFailure.metadataFull }
    }
}
