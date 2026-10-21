import DiscordLogging
import Foundation

/// Closed subscription/admission failures that never contain event payloads or credentials.
public enum GatewayEventDeliveryFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case subscriptionCapacityExceeded
    case resynchronizationRequired
    case concurrentIteration
    case handlerCapacityExceeded
    case finished
}

/// Explicit choices for a slow subscriber; the default reports lost continuity.
public enum GatewayEventOverflowPolicy: Sendable {
    case resynchronize
    case dropNewest
    case dropOldest
}

/// Validated queue and metadata limits for a hub or its shared process authority.
public struct GatewayEventHubConfiguration: Sendable {
    public let maximumSubscriptions: Int
    public let maximumBufferedEvents: Int
    public let maximumBufferedBytes: Int
    public let maximumEventsPerSubscription: Int
    public let maximumBytesPerSubscription: Int

    /// Validates limits without launching tasks or retaining events.
    /// - Parameters:
    ///   - maximumSubscriptions: Positive subscription metadata cap, including unobserved terminal failures; default 64.
    ///   - maximumBufferedEvents: Positive sum of queued event copies across subscribers; default 4,096.
    ///   - maximumBufferedBytes: Positive sum of retained envelope bytes across subscribers; default 16 MiB.
    ///   - maximumEventsPerSubscription: Positive default individual queue count; default 128.
    ///   - maximumBytesPerSubscription: Positive default individual queue byte limit; default 1 MiB.
    /// - Throws: `GatewayEventDeliveryFailure.invalidConfiguration` for nonpositive limits.
    public init(maximumSubscriptions: Int = 64, maximumBufferedEvents: Int = 4_096,
                maximumBufferedBytes: Int = 16_777_216, maximumEventsPerSubscription: Int = 128,
                maximumBytesPerSubscription: Int = 1_048_576) throws {
        guard maximumSubscriptions > 0, maximumBufferedEvents > 0, maximumBufferedBytes > 0,
              maximumEventsPerSubscription > 0, maximumBytesPerSubscription > 0 else {
            throw GatewayEventDeliveryFailure.invalidConfiguration
        }
        self.maximumSubscriptions = maximumSubscriptions
        self.maximumBufferedEvents = maximumBufferedEvents
        self.maximumBufferedBytes = maximumBufferedBytes
        self.maximumEventsPerSubscription = maximumEventsPerSubscription
        self.maximumBytesPerSubscription = maximumBytesPerSubscription
    }
}

/// Bounded nonsecret queue accounting; event copies are counted once per subscriber.
public struct GatewayEventHubSnapshot: Sendable {
    public let subscriptions: Int
    public let bufferedEvents: Int
    public let bufferedBytes: Int
    public let waitingConsumers: Int
}

/// One publication's admission outcome, with no consumer callbacks executed by publication.
public struct GatewayEventPublication: Sendable {
    public let delivered: Int
    public let dropped: Int
    public let terminated: Int
}

/// Independent single-consumer broadcast queue with explicit cancellation ownership.
///
/// Create a separate subscription for each consumer. Multiple iterators share this one queue;
/// overlapping `next` calls fail rather than creating an unbounded waiter list. Call `cancel`
/// when abandoning a subscription without a suspended iteration. An unobserved overflow retains
/// one bounded metadata slot until iteration observes the failure, explicit cancellation, or hub finish.
public struct GatewayEventSubscription: AsyncSequence, Sendable {
    public typealias Element = GatewayEvent
    fileprivate let authority: GatewayEventHubAuthority
    fileprivate let id: UUID

    /// An iterator into exactly one independently bounded subscription.
    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        fileprivate let subscription: GatewayEventSubscription

        /// Waits for one event, preserving publication order within this subscription.
        /// - Returns: The oldest queued event, or nil after explicit cancellation or hub finish.
        /// - Throws: Cancellation, an overflow's `resynchronizationRequired`, or `concurrentIteration`.
        ///   Cancelling a suspended call releases the entire subscription and all retained events.
        public mutating func next() async throws -> GatewayEvent? {
            let authority = subscription.authority
            let id = subscription.id
            do {
                let event = try await withTaskCancellationHandler {
                    try await authority.next(id)
                } onCancel: {
                    // The cancellation callback cannot await. This short actor hop owns no user work;
                    // the suspended next resumes only after the authority has released its resources.
                    Task { await authority.cancel(id, cancelled: true) }
                }
                try Task.checkCancellation()
                return event
            } catch {
                if Task.isCancelled { await authority.cancel(id, cancelled: true) }
                throw error
            }
        }
    }

    /// Creates an iterator without allocating another queue or starting a task.
    /// - Returns: An iterator sharing this subscription's single-consumer state.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(subscription: self) }

    /// Discards queued events and wakes a suspended consumer with normal end-of-sequence.
    /// Repeated calls are harmless and do not affect any other subscription.
    public func cancel() async { await authority.cancel(id, cancelled: false) }
}

/// Process-local aggregate authority shareable by hubs for independent bot identities.
///
/// All accounting and queue mutations are atomic actor operations with no suspension, user
/// callbacks, payload decoding, or network work. First-created subscribers have admission priority
/// for shared capacity; lossy eviction can discard only the affected subscriber's own events.
/// This is an in-process budget, not a distributed broadcast or persistence contract.
public actor GatewayEventHubAuthority {
    private struct Subscriber {
        let hub: UUID
        let ordinal: UInt64
        let configuration: GatewayEventHubConfiguration
        let maximumEvents: Int
        let maximumBytes: Int
        let policy: GatewayEventOverflowPolicy
        var events: [GatewayEvent] = []
        var bytes = 0
        var waiter: CheckedContinuation<GatewayEvent?, any Error>?
        var failed = false
    }

    private let configuration: GatewayEventHubConfiguration
    private var subscribers: [UUID: Subscriber] = [:]
    private var nextOrdinal: UInt64 = 0
    private var bufferedEvents = 0
    private var bufferedBytes = 0

    /// Stores validated aggregate limits; no background task or external resources are created.
    /// - Parameter configuration: Process-wide subscriptions/count/bytes limits. Per-subscription defaults
    ///   are selected by each hub's configuration, not this authority's defaults.
    public init(configuration: GatewayEventHubConfiguration) { self.configuration = configuration }

    /// Reports aggregate metadata and queue usage across every hub sharing this authority.
    /// - Returns: An atomic bounded snapshot, excluding events already handed to consumer code.
    public func snapshot() -> GatewayEventHubSnapshot { snapshot(hub: nil) }

    /// Registers one independent queue after checking hub and shared metadata budgets.
    /// - Parameters:
    ///   - hub: Opaque hub identity, never a credential or user diagnostic label.
    ///   - configuration: Validated hub aggregate and default individual bounds.
    ///   - policy: Explicit action when queue or shared byte/count capacity is exhausted.
    ///   - maximumEvents: Positive individual event count override, or nil for the hub default.
    ///   - maximumBytes: Positive individual retained byte override, or nil for the hub default.
    /// - Returns: A new subscription that receives only subsequent publications to this hub.
    /// - Throws: `CancellationError` when the caller is already cancelled, invalid overrides,
    ///   or exhausted local/shared subscription metadata capacity.
    fileprivate func subscribe(hub: UUID, configuration: GatewayEventHubConfiguration,
                               policy: GatewayEventOverflowPolicy, maximumEvents: Int?, maximumBytes: Int?) throws -> GatewayEventSubscription {
        try Task.checkCancellation()
        let events = maximumEvents ?? configuration.maximumEventsPerSubscription
        let bytes = maximumBytes ?? configuration.maximumBytesPerSubscription
        guard events > 0, bytes > 0 else { throw GatewayEventDeliveryFailure.invalidConfiguration }
        guard subscribers.count < self.configuration.maximumSubscriptions,
              subscribers.values.lazy.filter({ $0.hub == hub }).count < configuration.maximumSubscriptions,
              nextOrdinal < UInt64.max else { throw GatewayEventDeliveryFailure.subscriptionCapacityExceeded }
        let id = UUID()
        subscribers[id] = Subscriber(hub: hub, ordinal: nextOrdinal, configuration: configuration,
            maximumEvents: events, maximumBytes: bytes, policy: policy)
        nextOrdinal += 1
        DiscordLog.makeLogger("gateway.events").debug("Gateway subscription created", metadata: ["dk.event": "gateway.subscription.created", "dk.subscriptions": .stringConvertible(subscribers.count)])
        return GatewayEventSubscription(authority: self, id: id)
    }

    /// Publishes atomically to a bounded set of independent queues, without awaiting consumers.
    /// - Parameters:
    ///   - event: Already bounded raw envelope whose byte count is trusted from Gateway ingestion.
    ///   - hub: Opaque source hub; subscribers of other hubs never receive this event.
    /// - Returns: Counts of admitted, dropped, and newly failed subscribers.
    fileprivate func publish(_ event: GatewayEvent, hub: UUID) -> GatewayEventPublication {
        var delivered = 0
        var dropped = 0
        var terminated = 0
        let ids = subscribers.filter { $0.value.hub == hub && !$0.value.failed }
            .sorted { $0.value.ordinal < $1.value.ordinal }.map(\.key)
        for id in ids {
            guard var subscriber = subscribers[id] else { continue }
            if let waiter = subscriber.waiter {
                subscriber.waiter = nil
                subscribers[id] = subscriber
                waiter.resume(returning: event)
                delivered += 1
                continue
            }
            if subscriber.policy == .dropOldest,
               event.retainedByteCount <= subscriber.maximumBytes,
               event.retainedByteCount <= subscriber.configuration.maximumBufferedBytes,
               event.retainedByteCount <= configuration.maximumBufferedBytes {
                while !fits(event, subscriber: subscriber), !subscriber.events.isEmpty {
                    let removed = subscriber.events.removeFirst()
                    subscriber.bytes -= removed.retainedByteCount
                    bufferedEvents -= 1
                    bufferedBytes -= removed.retainedByteCount
                    subscribers[id] = subscriber
                }
            }
            if fits(event, subscriber: subscriber) {
                subscriber.events.append(event)
                subscriber.bytes += event.retainedByteCount
                bufferedEvents += 1
                bufferedBytes += event.retainedByteCount
                subscribers[id] = subscriber
                delivered += 1
            } else if subscriber.policy == .resynchronize {
                bufferedEvents -= subscriber.events.count
                bufferedBytes -= subscriber.bytes
                subscriber.events.removeAll(keepingCapacity: false)
                subscriber.bytes = 0
                subscriber.failed = true
                subscribers[id] = subscriber
                terminated += 1
            } else { dropped += 1 }
        }
        if terminated > 0 || dropped > 0 {
            DiscordLog.makeLogger("gateway.events").warning("Gateway subscriber capacity exhausted", metadata: ["dk.event": "gateway.subscription.overflow", "dk.dropped": .stringConvertible(dropped), "dk.terminated": .stringConvertible(terminated)])
        }
        DiscordLog.makeLogger("gateway.events").trace("Gateway event publication completed", metadata: ["dk.event": "gateway.publication.completed", "dk.delivered": .stringConvertible(delivered), "dk.dropped": .stringConvertible(dropped), "dk.terminated": .stringConvertible(terminated), "dk.queued": .stringConvertible(bufferedEvents), "dk.bytes": .stringConvertible(bufferedBytes)])
        return GatewayEventPublication(delivered: delivered, dropped: dropped, terminated: terminated)
    }

    /// Determines admission using subtraction to avoid overflow even for extreme configured limits.
    /// - Parameters:
    ///   - event: Candidate event, counted once for this queue.
    ///   - subscriber: Current local queue state, already reflected in shared accounting.
    /// - Returns: Whether all subscriber, hub, and shared event/byte bounds permit one more copy.
    private func fits(_ event: GatewayEvent, subscriber: Subscriber) -> Bool {
        let hub = snapshot(hub: subscriber.hub)
        return subscriber.events.count < subscriber.maximumEvents
            && event.retainedByteCount <= subscriber.maximumBytes - subscriber.bytes
            && hub.bufferedEvents < subscriber.configuration.maximumBufferedEvents
            && event.retainedByteCount <= subscriber.configuration.maximumBufferedBytes - hub.bufferedBytes
            && bufferedEvents < configuration.maximumBufferedEvents
            && event.retainedByteCount <= configuration.maximumBufferedBytes - bufferedBytes
    }

    /// Reads or parks exactly one consumer continuation and releases accounting before delivery.
    /// - Parameter id: Subscription admission identity, never reused after cancellation.
    /// - Returns: Oldest admitted event, or nil for an unknown/finished subscription.
    /// - Throws: Cancellation, a terminal resynchronization error, or overlapping consumer iteration.
    fileprivate func next(_ id: UUID) async throws -> GatewayEvent? {
        if Task.isCancelled {
            cancel(id, cancelled: true)
            throw CancellationError()
        }
        guard var subscriber = subscribers[id] else { return nil }
        if subscriber.failed {
            subscribers.removeValue(forKey: id)
            throw GatewayEventDeliveryFailure.resynchronizationRequired
        }
        guard subscriber.waiter == nil else { throw GatewayEventDeliveryFailure.concurrentIteration }
        if !subscriber.events.isEmpty {
            let event = subscriber.events.removeFirst()
            subscriber.bytes -= event.retainedByteCount
            bufferedEvents -= 1
            bufferedBytes -= event.retainedByteCount
            subscribers[id] = subscriber
            DiscordLog.makeLogger("gateway.events").trace("Gateway subscription dequeued an event", metadata: ["dk.event": "gateway.subscription.dequeued", "dk.queued": .stringConvertible(bufferedEvents), "dk.bytes": .stringConvertible(bufferedBytes)])
            return event
        }
        DiscordLog.makeLogger("gateway.events").trace("Gateway subscription waiting for publication", metadata: ["dk.event": "gateway.subscription.wait"])
        return try await withCheckedThrowingContinuation { continuation in
            subscriber.waiter = continuation
            subscribers[id] = subscriber
        }
    }

    /// Removes one queue and resolves its continuation exactly once, including cancellation races.
    /// - Parameters:
    ///   - id: Subscription to release; unknown IDs are harmless.
    ///   - cancelled: Whether a suspended consumer receives cancellation rather than normal completion.
    fileprivate func cancel(_ id: UUID, cancelled: Bool) {
        guard let subscriber = subscribers.removeValue(forKey: id) else { return }
        bufferedEvents -= subscriber.events.count
        bufferedBytes -= subscriber.bytes
        DiscordLog.makeLogger("gateway.events").trace("Gateway subscription released", metadata: ["dk.event": "gateway.subscription.released", "dk.cancelled": .stringConvertible(cancelled), "dk.subscriptions": .stringConvertible(subscribers.count), "dk.queued": .stringConvertible(bufferedEvents), "dk.bytes": .stringConvertible(bufferedBytes)])
        if cancelled { subscriber.waiter?.resume(throwing: CancellationError()) }
        else { subscriber.waiter?.resume(returning: nil) }
    }

    /// Discards every queue owned by one hub, leaving unrelated identities operational.
    /// - Parameter hub: Opaque hub whose subscribers should receive normal completion.
    fileprivate func finish(hub: UUID) {
        let ids = subscribers.filter { $0.value.hub == hub }.map(\.key)
        for id in ids { cancel(id, cancelled: false) }
    }

    /// Computes bounded metadata/queue usage for a hub or the full authority.
    /// - Parameter hub: Nil selects all hubs; otherwise only matching subscriptions count.
    /// - Returns: Atomic usage, including terminal failure metadata until observed or cancelled.
    fileprivate func snapshot(hub: UUID?) -> GatewayEventHubSnapshot {
        let selected = subscribers.values.filter { hub == nil || $0.hub == hub }
        return GatewayEventHubSnapshot(subscriptions: selected.count,
            bufferedEvents: selected.reduce(0) { $0 + $1.events.count },
            bufferedBytes: selected.reduce(0) { $0 + $1.bytes },
            waitingConsumers: selected.lazy.filter { $0.waiter != nil }.count)
    }
}

/// A broadcast endpoint with separately bounded queues, optionally sharing aggregate budgets.
///
/// Publication order is preserved per subscription and therefore per sequentially published shard.
/// Concurrent publishers have actor admission order, not an invented cross-shard order. Delivery
/// is neither durable nor exactly once. No constructor launches tasks or performs network I/O.
public actor GatewayEventHub {
    private let id = UUID()
    private let configuration: GatewayEventHubConfiguration
    private let authority: GatewayEventHubAuthority
    private var finished = false
    private var inFlightSubscriptions = 0
    private var admissionsDrained: CheckedContinuation<Void, Never>?
    private var finishTask: Task<Void, Never>?

    /// Creates an idle hub with explicit local bounds and an optional shared process authority.
    /// - Parameters:
    ///   - configuration: Validated local metadata/count/byte limits and subscriber defaults.
    ///   - authority: Shared aggregate budget; nil creates a private authority with the same limits.
    public init(configuration: GatewayEventHubConfiguration, authority: GatewayEventHubAuthority? = nil) {
        self.configuration = configuration
        self.authority = authority ?? GatewayEventHubAuthority(configuration: configuration)
    }

    /// Registers a new consumer before publication; existing queued events are not replayed.
    /// - Parameters:
    ///   - policy: Default `.resynchronize` ends only this subscription when admission fails.
    ///   - maximumEvents: Positive individual queue count override; nil uses configuration.
    ///   - maximumBytes: Positive individual byte override; nil uses configuration.
    /// - Returns: An independently owned sequence that must be consumed or explicitly cancelled.
    /// - Throws: Invalid overrides, cancellation, exhausted local/shared metadata admission,
    ///   or `finished` after permanent hub shutdown, including subscription/shutdown races.
    public func subscribe(policy: GatewayEventOverflowPolicy = .resynchronize,
                          maximumEvents: Int? = nil, maximumBytes: Int? = nil) async throws -> GatewayEventSubscription {
        try Task.checkCancellation()
        guard !finished else { throw GatewayEventDeliveryFailure.finished }
        inFlightSubscriptions += 1
        defer { completeSubscriptionAdmission() }
        let subscription = try await authority.subscribe(hub: id, configuration: configuration, policy: policy,
            maximumEvents: maximumEvents, maximumBytes: maximumBytes)
        if finished || Task.isCancelled {
            await subscription.cancel()
            if Task.isCancelled { throw CancellationError() }
            throw GatewayEventDeliveryFailure.finished
        }
        return subscription
    }

    /// Offers one event to all current subscribers without running or awaiting user callbacks.
    /// - Parameter event: Already bounded raw Gateway observation, including future/unknown events.
    /// - Returns: Explicit subscriber delivery/drop/failure counts. A slow queue never blocks publication.
    @discardableResult public func publish(_ event: GatewayEvent) async -> GatewayEventPublication {
        guard !finished else { return GatewayEventPublication(delivered: 0, dropped: 0, terminated: 0) }
        return await authority.publish(event, hub: id)
    }

    /// Permanently closes admission, completes current subscriptions, and discards queues.
    /// Preexisting subscription admissions are cancelled and awaited before cleanup returns.
    /// Repeated calls await the same owned cleanup task and are harmless. Construct another hub for another run.
    public func finish() async {
        finished = true
        if let finishTask { await finishTask.value; return }
        // Explicit shutdown owns this one task and every caller awaits it. Keeping a single
        // completion task avoids accumulating a continuation per concurrent finish caller.
        let task = Task { await completeFinish() }
        finishTask = task
        await task.value
    }

    /// Reports this hub's atomic metadata/queue usage without exposing identity or event payloads.
    /// - Returns: Usage for only this hub, excluding consumer-owned events after delivery.
    public func snapshot() async -> GatewayEventHubSnapshot { await authority.snapshot(hub: id) }

    /// Releases one pending admission and wakes the single owned cleanup operation after the last settles.
    /// This executes without suspension so shutdown never observes a partially completed admission.
    private func completeSubscriptionAdmission() {
        inFlightSubscriptions -= 1
        if inFlightSubscriptions == 0 {
            admissionsDrained?.resume()
            admissionsDrained = nil
        }
    }

    /// Completes queues before and after awaiting all admissions that raced permanent shutdown.
    /// This operation belongs to `finishTask`; it performs no user work and cannot be cancelled midway.
    private func completeFinish() async {
        await authority.finish(hub: id)
        if inFlightSubscriptions > 0 {
            await withCheckedContinuation { admissionsDrained = $0 }
        }
        await authority.finish(hub: id)
    }
}
