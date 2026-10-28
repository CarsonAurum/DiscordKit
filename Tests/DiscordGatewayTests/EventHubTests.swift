// File: Tests/DiscordGatewayTests/EventHubTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordGateway

/// Independent broadcast, queue accounting, shutdown, and cancellation without live Discord I/O.
@Suite("Gateway event hub", .timeLimit(.minutes(1)))
struct EventHubTests {
    /// Rejects every nonpositive bound and accepts extreme positive arithmetic-safe bounds.
    @Test func configurationValidation() throws {
        for value in [0, -1, Int.min] {
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHubConfiguration(maximumSubscriptions: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHubConfiguration(maximumBufferedEvents: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHubConfiguration(maximumBufferedBytes: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHubConfiguration(maximumEventsPerSubscription: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHubConfiguration(maximumBytesPerSubscription: value)
            }
        }
        let extreme = try GatewayEventHubConfiguration(maximumSubscriptions: Int.max,
            maximumBufferedEvents: Int.max, maximumBufferedBytes: Int.max,
            maximumEventsPerSubscription: Int.max, maximumBytesPerSubscription: Int.max)
        #expect(extreme.maximumBufferedBytes == Int.max)
    }

    /// Confirms two subscribers each receive full ordered copies and delivery releases retained accounting.
    @Test func independentOrderedBroadcast() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let first = try await hub.subscribe()
        let second = try await hub.subscribe()
        let events = try (0..<3).map { try makeDeliveryEvent(Int64($0)) }
        for event in events {
            let result = await hub.publish(event)
            #expect(result.delivered == 2 && result.dropped == 0 && result.terminated == 0)
        }
        #expect(await hub.snapshot().bufferedEvents == 6)
        #expect(await hub.snapshot().bufferedBytes == 2 * events.reduce(0) { $0 + $1.retainedByteCount })
        var a = first.makeAsyncIterator()
        var b = second.makeAsyncIterator()
        for sequence in 0..<3 {
            #expect(try await a.next()?.sequence == Int64(sequence))
            #expect(try await b.next()?.sequence == Int64(sequence))
        }
        #expect(await hub.snapshot().bufferedBytes == 0)
        await first.cancel()
        await second.cancel()
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A slow queue fails with explicit resynchronization while another queue keeps receiving ordered events.
    @Test func overflowIsolationAndMetadataRelease() async throws {
        let hub = GatewayEventHub(configuration: try .init(maximumEventsPerSubscription: 1))
        let slow = try await hub.subscribe()
        let fast = try await hub.subscribe()
        var iterator = fast.makeAsyncIterator()
        await hub.publish(try makeDeliveryEvent(1))
        #expect(try await iterator.next()?.sequence == 1)
        let result = await hub.publish(try makeDeliveryEvent(2))
        #expect(result.delivered == 1 && result.terminated == 1)
        #expect(try await iterator.next()?.sequence == 2)
        var stopped = slow.makeAsyncIterator()
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await stopped.next() }
        #expect(try await stopped.next() == nil)
        #expect(await hub.snapshot().subscriptions == 1)
        await fast.cancel()
        #expect(await hub.snapshot().bufferedEvents == 0)
    }

    /// Exact byte boundaries admit one envelope, then fail closed and discard already queued copies.
    @Test func byteLimitsAndTerminalMetadataBound() async throws {
        let event = try makeDeliveryEvent(1)
        let hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 1,
            maximumBytesPerSubscription: event.retainedByteCount))
        let subscription = try await hub.subscribe()
        #expect(await hub.publish(event).delivered == 1)
        #expect(await hub.publish(event).terminated == 1)
        #expect(await hub.snapshot().bufferedBytes == 0)
        await #expect(throws: GatewayEventDeliveryFailure.subscriptionCapacityExceeded) { try await hub.subscribe() }
        var iterator = subscription.makeAsyncIterator()
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await iterator.next() }
        let replacement = try await hub.subscribe()
        await replacement.cancel()
        await #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
            try await hub.subscribe(maximumEvents: 0)
        }
        await #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
            try await hub.subscribe(maximumBytes: -1)
        }
    }

    /// Explicit lossy modes retain the oldest or newest bounded window without affecting another subscriber.
    /// - Parameter policy: Lossy overflow mode whose retained window is asserted after three publications.
    @Test(arguments: [GatewayEventOverflowPolicy.dropNewest, .dropOldest])
    func explicitLossyPolicies(_ policy: GatewayEventOverflowPolicy) async throws {
        let hub = GatewayEventHub(configuration: try .init(maximumEventsPerSubscription: 2))
        let subscription = try await hub.subscribe(policy: policy)
        for sequence in 1...3 { await hub.publish(try makeDeliveryEvent(Int64(sequence))) }
        #expect(await hub.snapshot().bufferedEvents == 2)
        var iterator = subscription.makeAsyncIterator()
        let first = try await iterator.next()?.sequence
        let second = try await iterator.next()?.sequence
        #expect([first, second] == (policy == .dropNewest ? [1, 2] : [2, 3]))
        await subscription.cancel()
    }

    /// Shared capacity spans hubs without broadcasting one identity's events into another identity's queue.
    @Test func aggregateBudgetsAndHubIsolation() async throws {
        let configuration = try GatewayEventHubConfiguration(maximumSubscriptions: 2,
            maximumBufferedEvents: 1, maximumBufferedBytes: Int.max)
        let authority = GatewayEventHubAuthority(configuration: configuration)
        let a = GatewayEventHub(configuration: configuration, authority: authority)
        let b = GatewayEventHub(configuration: configuration, authority: authority)
        let first = try await a.subscribe()
        let second = try await b.subscribe()
        await #expect(throws: GatewayEventDeliveryFailure.subscriptionCapacityExceeded) { try await b.subscribe() }
        await a.publish(try makeDeliveryEvent(1))
        #expect(await a.snapshot().bufferedEvents == 1)
        #expect(await b.snapshot().bufferedEvents == 0)
        #expect(await b.publish(try makeDeliveryEvent(2)).terminated == 1)
        #expect(await authority.snapshot().bufferedEvents == 1)
        var iterator = first.makeAsyncIterator()
        #expect(try await iterator.next()?.sequence == 1)
        var failed = second.makeAsyncIterator()
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await failed.next() }
        await a.finish()
        #expect(await authority.snapshot().subscriptions == 0)
    }

    /// Local hub aggregate bytes count subscriber copies even when the shared process has spare capacity.
    @Test func localAggregateBytesAndLossySharedCapacity() async throws {
        let event = try makeDeliveryEvent(1)
        let shared = GatewayEventHubAuthority(configuration: try .init())
        let configuration = try GatewayEventHubConfiguration(maximumBufferedBytes: event.retainedByteCount)
        let hub = GatewayEventHub(configuration: configuration, authority: shared)
        let first = try await hub.subscribe(policy: .dropOldest)
        let second = try await hub.subscribe(policy: .dropNewest)
        let result = await hub.publish(event)
        #expect(result.delivered == 1 && result.dropped == 1)
        #expect(await hub.snapshot().bufferedBytes == event.retainedByteCount)
        #expect(await hub.publish(try makeDeliveryEvent(2)).delivered == 1)
        var iterator = first.makeAsyncIterator()
        #expect(try await iterator.next()?.sequence == 2)
        await first.cancel()
        await second.cancel()
    }

    /// An oversized lossy publication preserves existing valid queued data instead of emptying the window.
    /// - Parameter policy: Lossy overflow mode, both of which must preserve the already queued small event.
    @Test(arguments: [GatewayEventOverflowPolicy.dropNewest, .dropOldest])
    func oversizedLossyEvent(_ policy: GatewayEventOverflowPolicy) async throws {
        let small = try makeDeliveryEvent(1)
        let large = try makeDeliveryEvent(2, payload: .string(String(repeating: "x", count: 1_024)))
        let hub = GatewayEventHub(configuration: try .init(maximumBytesPerSubscription: small.retainedByteCount))
        let subscription = try await hub.subscribe(policy: policy)
        await hub.publish(small)
        #expect(await hub.publish(large).dropped == 1)
        #expect(await hub.snapshot().bufferedBytes == small.retainedByteCount)
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next()?.sequence == 1)
        await subscription.cancel()
    }

    /// Shared limits stay finite across many independent hubs, and releasing queues permits later admission.
    @Test func manyClientAggregateMetadataAndBytes() async throws {
        let event = try makeDeliveryEvent(1)
        let authority = GatewayEventHubAuthority(configuration: try .init(maximumSubscriptions: 8,
            maximumBufferedEvents: 8, maximumBufferedBytes: event.retainedByteCount * 4))
        var hubs: [GatewayEventHub] = []
        var subscriptions: [GatewayEventSubscription] = []
        for _ in 0..<8 {
            let hub = GatewayEventHub(configuration: try .init(), authority: authority)
            hubs.append(hub)
            subscriptions.append(try await hub.subscribe(policy: .dropNewest))
        }
        for hub in hubs { await hub.publish(event) }
        let usage = await authority.snapshot()
        #expect(usage.subscriptions == 8 && usage.bufferedEvents == 4)
        #expect(usage.bufferedBytes == event.retainedByteCount * 4)
        let extra = GatewayEventHub(configuration: try .init(), authority: authority)
        await #expect(throws: GatewayEventDeliveryFailure.subscriptionCapacityExceeded) { try await extra.subscribe() }
        for subscription in subscriptions { await subscription.cancel() }
        let replacement = try await extra.subscribe()
        #expect(await extra.publish(event).delivered == 1)
        await replacement.cancel()
        #expect(await authority.snapshot().bufferedBytes == 0)
    }

    /// Cancelling one parked iterator releases only its queue and terminal finish prevents new admission.
    @Test func parkedCancellationAndFinish() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let cancelled = try await hub.subscribe()
        let healthy = try await hub.subscribe()
        let waiting = Task {
            var iterator = cancelled.makeAsyncIterator()
            return try await iterator.next()
        }
        while await hub.snapshot().waitingConsumers != 1 { await Task.yield() }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(await hub.snapshot().subscriptions == 1)
        await hub.publish(try makeDeliveryEvent(5))
        var iterator = healthy.makeAsyncIterator()
        #expect(try await iterator.next()?.sequence == 5)
        await hub.finish()
        await hub.finish()
        #expect(try await iterator.next() == nil)
        await #expect(throws: GatewayEventDeliveryFailure.finished) { try await hub.subscribe() }
        #expect(await hub.publish(try makeDeliveryEvent(6)).delivered == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Concurrent iteration is observable; direct delivery wakes only the original parked consumer.
    @Test func overlappingIterationAndDirectDelivery() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let waiting = Task {
            var iterator = subscription.makeAsyncIterator()
            return try await iterator.next()
        }
        while await hub.snapshot().waitingConsumers != 1 { await Task.yield() }
        var duplicate = subscription.makeAsyncIterator()
        await #expect(throws: GatewayEventDeliveryFailure.concurrentIteration) { try await duplicate.next() }
        #expect(await hub.publish(try makeDeliveryEvent(8)).delivered == 1)
        #expect(try await waiting.value?.sequence == 8)
        #expect(await hub.snapshot().bufferedBytes == 0)
        await subscription.cancel()
    }

    /// Finishing resolves parked consumers normally, and repeated explicit cancellation is harmless.
    @Test func finishWakesParkedConsumer() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let task = Task {
            var iterator = subscription.makeAsyncIterator()
            return try await iterator.next()
        }
        while await hub.snapshot().waitingConsumers != 1 { await Task.yield() }
        await hub.finish()
        #expect(try await task.value == nil)
        await subscription.cancel()
        await subscription.cancel()
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Hub/subscription hops remain usable from an explicitly isolated UI consumer without deadlock.
    @MainActor @Test func mainActorConsumerAndPreCancellation() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        await hub.publish(try makeDeliveryEvent(9))
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next()?.sequence == 9)
        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            var iterator = subscription.makeAsyncIterator()
            return try await iterator.next()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Concurrent finish/admission never leaves a subscription behind after all operations settle.
    @Test func subscribeShutdownRace() async throws {
        let hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 256))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask { _ = try? await hub.subscribe() }
                group.addTask { await hub.finish() }
            }
        }
        #expect(await hub.snapshot().subscriptions == 0)
    }
}

/// Constructs deterministic bounded future dispatches for hub and handler tests.
/// - Parameters:
///   - sequence: Nonnegative per-shard sequence used for order assertions.
///   - shard: Zero-based shard index, default zero in a two-shard topology.
///   - payload: Lossless arbitrary test payload, default null.
/// - Returns: A validated event with accurately accounted serialized envelope bytes.
/// - Throws: Invalid shard/sequence or bounded JSON serialization failures.
func makeDeliveryEvent(_ sequence: Int64, shard: Int = 0, payload: JSONValue = .null) throws -> GatewayEvent {
    try GatewayEvent(shard: ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0,
        index: shard, count: 2), name: "FUTURE_EVENT", sequence: sequence, data: payload)
}
