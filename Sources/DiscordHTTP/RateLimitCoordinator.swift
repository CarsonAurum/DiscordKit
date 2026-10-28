// File: Sources/DiscordHTTP/RateLimitCoordinator.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordTransport
import Foundation

/// Cancellable bounded FIFO admission above a shared injectable rate authority.
///
/// The oldest locally eligible partition head receives the next available slot.
/// A blocked partition sleeps independently, so unrelated identities/resources can
/// proceed. Each waiter owns at most one cancellable clock sleeper; there is no
/// autonomous scheduler task. FIFO covers one coordinator's identity/route/major
/// resource/class, including holding that partition until completion. Share the
/// coordinator when mutation ordering must span clients; a distributed store alone
/// coordinates rate admission, not cross-process application mutation ordering.
/// An uncertain authority failure permanently closes local admission and emits one
/// critical event. Replace the coordinator after restoring authority; it never resets
/// the safety latch or silently grants local fallback admission.
public actor RateLimitCoordinator<C: Clock> where C.Duration == Duration {
    private struct QueuePartition: Hashable {
        let identity: RateLimitIdentity
        let route: String
        let majorResource: String
        let schedulingClass: SchedulingClass

        /// Derives a FIFO ownership key containing no credential or raw URL.
        /// - Parameter request: Request's explicitly supplied rate scopes.
        init(_ request: RateLimitRequest) {
            identity = request.identity; route = request.route
            majorResource = request.majorResource; schedulingClass = request.schedulingClass
        }
    }
    private struct Waiter {
        let request: RateLimitRequest
        let deadline: C.Instant
        var blockedUntil: C.Instant
        var sleeper: Task<Void, Error>?
    }
    private let clock: C
    private let store: any RateLimitStore<C.Instant>
    private let policy: SchedulingPolicy
    private var queue: [UUID] = []
    private var waiters: [UUID: Waiter] = [:]
    private var queuedBytes = 0
    private var orderingQueue: [UUID] = []
    private var orderingWaiters: [UUID: Waiter] = [:]
    private var orderedOperations: [UUID: RateLimitRequest] = [:]
    private var active: [UUID: RateLimitReservation<C.Instant>] = [:]
    private var admitting: Set<QueuePartition> = []
    private var closed = false
    private var unavailable = false

    /// Creates a scheduler without spawning background work.
    /// - Parameters:
    ///   - clock: Monotonic clock used for queue/deadline/fairness decisions.
    ///   - store: Shared in-process or external authority; nil creates an owned local store.
    ///   - policy: Finite queue, byte, concurrency and age budgets. If supplying a
    ///     store, configure its aggregate limits independently for all clients sharing it.
    public init(clock: C, store: (any RateLimitStore<C.Instant>)? = nil, policy: SchedulingPolicy = .init()) {
        self.clock = clock
        self.policy = policy
        self.store = store ?? InProcessRateLimitStore<C.Instant>(policy: policy)
    }

    /// Waits for ordered admission while respecting every applicable finite budget.
    /// Cancellation removes the waiter and its sleeper without advancing virtual time.
    /// - Parameters:
    ///   - request: Nonnegative request-byte estimate and opaque authority scopes.
    ///   - deadline: Inclusive clock-local deadline; nil still applies maximumQueueAge.
    /// - Returns: Single-use token whose owner must call complete or release exactly once.
    /// - Throws: Cancellation, closed/unavailable authority, overload, deadline or store failure.
    public func acquire(_ request: RateLimitRequest, deadline: C.Instant? = nil) async throws -> RateLimitReservation<C.Instant> {
        try Task.checkCancellation()
        try ensureOpen()
        guard request.queuedBytes >= 0 else { throw RateLimitFailure.invalidRequest }
        let now = clock.now
        let effectiveDeadline = min(deadline ?? now.advanced(by: policy.maximumQueueAge),
                                    now.advanced(by: policy.maximumQueueAge))
        guard effectiveDeadline > now else { throw RateLimitFailure.deadlineExceeded }
        try validateQueueCapacity(request)
        let id = UUID()
        queue.append(id)
        waiters[id] = Waiter(request: request, deadline: effectiveDeadline, blockedUntil: now)
        queuedBytes += request.queuedBytes
        DiscordLog.makeLogger("http.ratelimit").trace("REST admission queued", metadata: ["dk.event": "http.admission.queued", "dk.queued": .stringConvertible(queue.count)])
        defer { removeWaiter(id) }
        return try await withTaskCancellationHandler {
            while true {
                try Task.checkCancellation()
                try ensureOpen()
                guard var waiter = waiters[id] else { throw CancellationError() }
                let current = clock.now
                guard current < waiter.deadline else { throw RateLimitFailure.deadlineExceeded }
                if eligibleHead(at: current) == id {
                    let partition = QueuePartition(request)
                    admitting.insert(partition)
                    let result: RateLimitAdmission<C.Instant>
                    DiscordLog.makeLogger("http.ratelimit").trace("REST shared authority reservation started", metadata: ["dk.event": "http.admission.reserve", "dk.active": .stringConvertible(active.count)])
                    do { result = try await store.reserve(request, now: current) }
                    catch {
                        admitting.remove(partition)
                        if let failure = error as? RateLimitFailure {
                            if failure == .coordinatorUnavailable || failure == .unknownReservation || failure == .reservationExpired {
                                failClosed()
                            }
                        } else if !(error is CancellationError) { failClosed() }
                        throw authorityFailure(error)
                    }
                    admitting.remove(partition)
                    switch result {
                    case .admitted(let reservation):
                        if closed || unavailable || Task.isCancelled || clock.now >= waiter.deadline {
                            do { try await store.release(reservation, outcome: .notSent, now: clock.now) }
                            catch { failClosed(); throw authorityFailure(error) }
                            try Task.checkCancellation()
                            try ensureOpen()
                            throw RateLimitFailure.deadlineExceeded
                        }
                        active[reservation.id] = reservation
                        DiscordLog.makeLogger("http.ratelimit").trace("REST admission granted", metadata: ["dk.event": "http.admission.granted"])
                        return reservation
                    case .retry(let instant):
                        DiscordLog.makeLogger("http.ratelimit").trace("REST shared authority deferred admission", metadata: ["dk.event": "http.admission.deferred"])
                        waiter.blockedUntil = max(instant, current.advanced(by: policy.fairnessInterval))
                        waiters[id]?.blockedUntil = waiter.blockedUntil
                    }
                }
                let wake = min(waiter.deadline, max(current.advanced(by: policy.fairnessInterval), waiter.blockedUntil))
                let clock = self.clock
                DiscordLog.makeLogger("http.ratelimit").trace("REST admission waiting for eligibility", metadata: ["dk.event": "http.admission.wait", "dk.queued": .stringConvertible(waiters.count), "dk.active": .stringConvertible(active.count)])
                let sleeper = Task { try await clock.sleep(until: wake, tolerance: nil) }
                waiters[id]?.sleeper = sleeper
                do { try await sleeper.value }
                catch {
                    sleeper.cancel()
                    try ensureOpen()
                    try Task.checkCancellation()
                    throw error
                }
                waiters[id]?.sleeper = nil
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Holds local mutation ordering across a complete operation, including every
    /// rejected-attempt retry and backoff. This lease consumes no Discord quota.
    /// Whole-operation and rate waiters share finite count/byte queue caps, and
    /// held operations have separate finite total/per-identity concurrency limits.
    ///
    /// Callers must consistently use this helper for operations whose ordering must
    /// be preserved and share this coordinator across clients. The operation must
    /// cooperate with cancellation and must not recursively acquire the same key.
    /// External rate stores do not supply cross-process mutation ordering.
    /// - Parameters:
    ///   - request: Identity/route/major-resource/class ordering partition and byte estimate.
    ///   - deadline: Inclusive acquisition deadline; nil still bounds queue age.
    ///   - operation: Structured caller-owned operation, invoked exactly once after
    ///     obtaining FIFO ownership. Its suspension points retain that ownership.
    /// - Returns: The operation result, after releasing local ordering ownership.
    /// - Throws: Queue/deadline/authority/cancellation failures or the operation's error.
    public func withOrdering<Value: Sendable>(request: RateLimitRequest, deadline: C.Instant? = nil,
                                              operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        try ensureOpen()
        guard request.queuedBytes >= 0 else { throw RateLimitFailure.invalidRequest }
        let now = clock.now
        let effectiveDeadline = min(deadline ?? now.advanced(by: policy.maximumQueueAge),
                                    now.advanced(by: policy.maximumQueueAge))
        guard effectiveDeadline > now else { throw RateLimitFailure.deadlineExceeded }
        try validateQueueCapacity(request)
        let id = UUID()
        DiscordLog.makeLogger("http.ordering").trace("REST ordered operation queued", metadata: ["dk.event": "http.ordering.queued", "dk.queued": .stringConvertible(orderingWaiters.count + 1)])
        orderingQueue.append(id)
        orderingWaiters[id] = Waiter(request: request, deadline: effectiveDeadline, blockedUntil: now)
        queuedBytes += request.queuedBytes
        defer {
            removeOrderingWaiter(id)
            orderedOperations.removeValue(forKey: id)
            DiscordLog.makeLogger("http.ordering").trace("REST ordered operation released", metadata: ["dk.event": "http.ordering.released", "dk.active": .stringConvertible(orderedOperations.count)])
        }
        return try await withTaskCancellationHandler {
            while true {
                try Task.checkCancellation()
                try ensureOpen()
                guard let waiter = orderingWaiters[id] else { throw CancellationError() }
                guard clock.now < waiter.deadline else { throw RateLimitFailure.deadlineExceeded }
                if eligibleOrderingHead(at: clock.now) == id {
                    removeOrderingWaiter(id)
                    orderedOperations[id] = request
                    DiscordLog.makeLogger("http.ordering").trace("REST ordered operation admitted", metadata: ["dk.event": "http.ordering.admitted", "dk.active": .stringConvertible(orderedOperations.count)])
                    return try await operation()
                }
                let clock = self.clock
                let wake = min(waiter.deadline, clock.now.advanced(by: policy.fairnessInterval))
                let sleeper = Task { try await clock.sleep(until: wake, tolerance: nil) }
                orderingWaiters[id]?.sleeper = sleeper
                do { try await sleeper.value }
                catch {
                    sleeper.cancel()
                    try ensureOpen()
                    try Task.checkCancellation()
                    throw error
                }
                orderingWaiters[id]?.sleeper = nil
            }
        } onCancel: {
            Task { await self.removeOrderingWaiter(id) }
        }
    }

    /// Learns response rate metadata before releasing the local FIFO partition.
    /// - Parameters:
    ///   - reservation: Token acquired from this coordinator.
    ///   - status: HTTP response status.
    ///   - headers: Bounded response metadata from the transport.
    ///   - retryAfter: Optional decoded 429 body delay; headers also participate.
    ///   - global: Decoded 429 body flag, false when absent.
    /// - Throws: Ownership, metadata or external authority failure; authority errors
    ///   stop new local admissions until the consumer replaces the coordinator.
    public func complete(_ reservation: RateLimitReservation<C.Instant>, status: Int, headers: [HTTPHeader],
                         retryAfter: Duration? = nil, global: Bool = false) async throws {
        guard active[reservation.id] != nil else { throw RateLimitFailure.unknownReservation }
        defer { active.removeValue(forKey: reservation.id) }
        do {
            try await store.complete(reservation, status: status, headers: headers,
                                     retryAfter: retryAfter, global: global, now: clock.now)
            DiscordLog.makeLogger("http.ratelimit").trace("REST response rate observation completed", metadata: ["dk.event": "http.admission.completed", "dk.status": .stringConvertible(status), "dk.global": .stringConvertible(global), "dk.retry_after_present": .stringConvertible(retryAfter != nil)])
        } catch { failClosed(); throw authorityFailure(error) }
    }

    /// Clears owned concurrency after a failed/canceled send while retaining rate debits.
    /// - Parameters:
    ///   - reservation: Token acquired from this coordinator.
    ///   - outcome: Explicit uncertainty; neither value refunds server quota.
    /// - Throws: Unknown/expired ownership or authority failure; failure stops new admissions.
    public func release(_ reservation: RateLimitReservation<C.Instant>, outcome: RateLimitReleaseOutcome) async throws {
        guard active[reservation.id] != nil else { throw RateLimitFailure.unknownReservation }
        defer { active.removeValue(forKey: reservation.id) }
        do {
            try await store.release(reservation, outcome: outcome, now: clock.now)
            DiscordLog.makeLogger("http.ratelimit").trace("REST admission released without response", metadata: ["dk.event": "http.admission.released", "dk.uncertain": .stringConvertible(outcome == .uncertain)])
        }
        catch { failClosed(); throw authorityFailure(error) }
    }

    /// Stops new admission and wakes every queued task immediately without sending.
    /// Already acquired tokens retain caller ownership and must still be completed
    /// or released. This operation is idempotent and does not close an injected store.
    public func close() {
        DiscordLog.makeLogger("http.ratelimit").info("REST admission closed", metadata: ["dk.event": "http.admission.closed"])
        closed = true
        for waiter in waiters.values { waiter.sleeper?.cancel() }
        for waiter in orderingWaiters.values { waiter.sleeper?.cancel() }
    }

    /// Captures queue bytes/count and authority-wide active/metadata ownership.
    /// - Returns: Aggregate counters with no unbounded diagnostic label cardinality.
    public func snapshot() async -> SchedulingSnapshot {
        let authority = await store.snapshot()
        return SchedulingSnapshot(queuedCount: waiters.count + orderingWaiters.count, queuedBytes: queuedBytes,
                                  activeCount: authority.activeCount, metadataCount: authority.metadataCount,
                                  orderedOperationsCount: orderedOperations.count)
    }

    /// Replaces untrusted external authority errors with a closed diagnostic category.
    /// - Parameter error: Injected storage failure, potentially containing credentials in its description.
    /// - Returns: A known safe rate failure, standard cancellation, or coordinatorUnavailable.
    private func authorityFailure(_ error: any Error) -> any Error {
        if let failure = error as? RateLimitFailure { return failure }
        if error is CancellationError { return CancellationError() }
        return RateLimitFailure.coordinatorUnavailable
    }

    /// Rejects new work after shutdown or uncertain authority failure.
    /// - Throws: Closed or coordinatorUnavailable; these never permit local fallback.
    private func ensureOpen() throws {
        if closed { throw RateLimitFailure.closed }
        if unavailable { throw RateLimitFailure.coordinatorUnavailable }
    }

    /// Finds the oldest eligible FIFO partition head, bypassing blocked partitions.
    /// Control and ordinary classes have equal scheduling weight, so neither can
    /// permanently starve the other; a class does not bypass total resource caps.
    /// - Parameter now: Instant used to exclude future-blocked and expired requests.
    /// - Returns: Oldest eligible waiter ID, or nil if all partitions are blocked/full.
    private func eligibleHead(at now: C.Instant) -> UUID? {
        guard active.count + admitting.count < policy.maximumConcurrentRequests else { return nil }
        var seen: Set<QueuePartition> = []
        let activePartitions = Set(active.values.map { QueuePartition($0.request) }).union(admitting)
        for id in queue {
            guard let waiter = waiters[id] else { continue }
            let partition = QueuePartition(waiter.request)
            guard seen.insert(partition).inserted else { continue }
            guard waiter.deadline > now, waiter.blockedUntil <= now, !activePartitions.contains(partition) else { continue }
            let identityActive = active.values.filter { $0.request.identity == waiter.request.identity }.count
                + admitting.filter { $0.identity == waiter.request.identity }.count
            if identityActive < policy.maximumConcurrentRequestsPerIdentity { return id }
        }
        return nil
    }

    /// Checks aggregate/per-identity capacity across both ordering and rate queues.
    /// - Parameter request: Candidate's nonnegative byte estimate and opaque identity.
    /// - Throws: queueFull before changing accounting when any finite cap is exceeded.
    private func validateQueueCapacity(_ request: RateLimitRequest) throws {
        let all = Array(waiters.values) + Array(orderingWaiters.values)
        let sameIdentity = all.filter { $0.request.identity == request.identity }
        let identityBytes = sameIdentity.reduce(0) { $0 + $1.request.queuedBytes }
        guard all.count < policy.maximumQueuedRequests,
              sameIdentity.count < policy.maximumQueuedRequestsPerIdentity,
              request.queuedBytes <= policy.maximumQueuedBytes - queuedBytes,
              request.queuedBytes <= policy.maximumQueuedBytesPerIdentity - identityBytes else {
            DiscordLog.makeLogger("http.ratelimit").debug("REST admission queue exhausted", metadata: ["dk.event": "http.admission.overloaded", "dk.queued": .stringConvertible(all.count)])
            throw RateLimitFailure.queueFull
        }
    }

    /// Selects FIFO heads for whole-operation locks while bypassing unrelated locks.
    /// - Parameter now: Current clock-local instant, excluding expired queue entries.
    /// - Returns: Oldest unlocked, within-budget ordering waiter, or nil.
    private func eligibleOrderingHead(at now: C.Instant) -> UUID? {
        guard orderedOperations.count < policy.maximumConcurrentRequests else { return nil }
        let held = Set(orderedOperations.values.map(QueuePartition.init))
        var seen: Set<QueuePartition> = []
        for id in orderingQueue {
            guard let waiter = orderingWaiters[id] else { continue }
            let key = QueuePartition(waiter.request)
            guard seen.insert(key).inserted, !held.contains(key), waiter.deadline > now else { continue }
            if orderedOperations.values.filter({ $0.identity == waiter.request.identity }).count
                < policy.maximumConcurrentRequestsPerIdentity { return id }
        }
        return nil
    }

    /// Clears pending ordering accounting and its sleeper exactly once.
    /// - Parameter id: Pending ordering registration; active operation leases are unaffected.
    private func removeOrderingWaiter(_ id: UUID) {
        guard let waiter = orderingWaiters.removeValue(forKey: id) else { return }
        queuedBytes -= waiter.request.queuedBytes
        orderingQueue.removeAll { $0 == id }
        waiter.sleeper?.cancel()
    }

    /// Removes queue accounting exactly once and cancels any owned clock task.
    /// - Parameter id: Waiter identifier, possibly already removed after cancellation.
    private func removeWaiter(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        queuedBytes -= waiter.request.queuedBytes
        queue.removeAll { $0 == id }
        waiter.sleeper?.cancel()
        DiscordLog.makeLogger("http.ratelimit").trace("REST admission waiter removed", metadata: ["dk.event": "http.admission.waiter.removed", "dk.queued": .stringConvertible(waiters.count), "dk.bytes": .stringConvertible(queuedBytes)])
    }

    /// Runs prompt cancellation cleanup from the cancellation handler's small task.
    /// - Parameter id: Canceled queue registration.
    private func cancelWaiter(_ id: UUID) { removeWaiter(id) }

    /// Permanently latches authority failure and wakes queued tasks without granting admission.
    /// The one critical transition requires application intervention and coordinator replacement.
    private func failClosed() {
        if !unavailable {
            DiscordLog.makeLogger("http.ratelimit").critical("REST authority permanently unavailable; replace coordinator", metadata: ["dk.event": "http.admission.unavailable"])
        }
        unavailable = true
        for waiter in waiters.values { waiter.sleeper?.cancel() }
        for waiter in orderingWaiters.values { waiter.sleeper?.cancel() }
    }
}
