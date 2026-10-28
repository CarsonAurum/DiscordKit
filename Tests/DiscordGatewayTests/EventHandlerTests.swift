// File: Tests/DiscordGatewayTests/EventHandlerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordGateway

/// Supervised callback scheduling and aggregate admission with deterministic, cancellation-aware gates.
@Suite("Gateway event handlers", .timeLimit(.minutes(1)))
struct EventHandlerTests {
    /// Every invalid callback/retention bound fails before construction creates any runtime work.
    @Test func configurationValidation() throws {
        for value in [0, -1] {
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHandlerConfiguration(maximumConcurrentHandlers: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHandlerConfiguration(maximumRetainedEvents: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayEventHandlerConfiguration(maximumRetainedBytes: value)
            }
            #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
                try GatewayHandlerAuthority(maximumActiveHandlers: value)
            }
        }
        #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) {
            try GatewayHandlerAuthority(maximumActiveHandlers: 1, maximumWaitingHandlers: -1)
        }
        let configuration = try GatewayEventHandlerConfiguration()
        #expect(configuration.maximumConcurrentHandlers == 4)
        #expect(configuration.maximumRetainedEvents == 128)
        #expect(configuration.maximumRetainedBytes == 4_194_304)
    }

    /// One blocked shard cannot prevent a second shard from running, and a shard's callbacks never overlap.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func shardOrderingAndConcurrentProgress() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumConcurrentHandlers: 2))
        let blocked = TestBarrier()
        let started = TestBarrier()
        let otherShard = TestBarrier()
        let final = TestBarrier()
        let observations = HandlerObservations()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { event in
                await observations.begin(event)
                if event.shard.index == 0, event.sequence == 1 {
                    started.open()
                    try await blocked.wait()
                }
                if event.shard.index == 1 { otherShard.open() }
                await observations.end(event)
                if event.shard.index == 0, event.sequence == 2 { final.open() }
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await started.wait()
        await hub.publish(try makeDeliveryEvent(2))
        await hub.publish(try makeDeliveryEvent(3, shard: 1))
        try await otherShard.wait()
        let before = await observations.snapshot()
        #expect(before.begun == ["0:1", "1:3"])
        #expect(before.maximumActive == 2)
        #expect(!before.sameShardOverlap)
        blocked.open()
        try await final.wait()
        await hub.finish()
        try await task.value
        let after = await observations.snapshot()
        #expect(after.ended.filter { $0.hasPrefix("0:") } == ["0:1", "0:2"])
        #expect(!after.sameShardOverlap)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Explicitly unordered same-shard callbacks overlap while the unchanged task cap queues excess work.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unorderedSameShardCallbacksRespectTaskCapacity() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumConcurrentHandlers: 2),
            serializesPerShard: false)
        let first = TestBarrier(), second = TestBarrier(), blocked = TestBarrier(), final = TestBarrier()
        let observations = HandlerObservations()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { event in
                await observations.begin(event)
                if event.sequence == 1 { first.open(); try await blocked.wait() }
                if event.sequence == 2 { second.open(); try await blocked.wait() }
                if event.sequence == 3 { #expect(blocked.waitingCount == 0); final.open() }
                await observations.end(event)
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await first.wait()
        await hub.publish(try makeDeliveryEvent(2))
        try await second.wait()
        await hub.publish(try makeDeliveryEvent(3))
        let overlap = await observations.snapshot()
        #expect(overlap.maximumActive == 2 && overlap.sameShardOverlap)
        blocked.open()
        try await final.wait()
        await hub.finish()
        try await task.value
        let complete = await observations.snapshot()
        #expect(complete.begun.count == 3 && complete.ended.count == 3)
        #expect(complete.maximumActive == 2)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A failing same-shard callback cancels and joins its overlapping sibling and releases shared admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unorderedSameShardFailureJoinsSiblingAndAuthority() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 2)
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumConcurrentHandlers: 2),
            authority: authority, serializesPerShard: false)
        let blocked = TestBarrier(), started = TestBarrier()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { event in
                if event.sequence == 1 { started.open(); try await blocked.wait() }
                else { throw HandlerTestFailure.callback }
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await started.wait()
        await hub.publish(try makeDeliveryEvent(2))
        await #expect(throws: HandlerTestFailure.callback) { try await task.value }
        #expect(blocked.waitingCount == 0)
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Reentrant publishing from a callback is safe and remains sequential for that shard.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test func reentrantHandlerAndMainActorCaller() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init())
        let done = TestBarrier()
        let observations = HandlerObservations()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { event in
                await observations.begin(event)
                if event.sequence == 1 { await hub.publish(try makeDeliveryEvent(2)) }
                await observations.end(event)
                if event.sequence == 2 { done.open() }
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await done.wait()
        await hub.finish()
        try await task.value
        #expect(await observations.snapshot().ended == ["0:1", "0:2"])
        #expect(await observations.snapshot().maximumActive == 1)
    }

    /// Original callback errors remain observable and sibling suspension/owned subscriptions are cleaned up.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func handlerFailureCancelsSiblingsAndSubscription() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumConcurrentHandlers: 2))
        let blocked = TestBarrier()
        let waiting = TestBarrier()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { event in
                if event.shard.index == 0 {
                    waiting.open()
                    try await blocked.wait()
                } else {
                    try await waiting.wait()
                    throw HandlerTestFailure.callback
                }
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        await hub.publish(try makeDeliveryEvent(1, shard: 1))
        await #expect(throws: HandlerTestFailure.callback) { try await task.value }
        #expect(blocked.waitingCount == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Cancelled execution stops callback work, releases its aggregate permit, and removes buffered events.
    /// - Parameter serializesPerShard: Exercises both legacy ordered and explicit independent scheduling.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func cancellationDuringCallbackAndBeforeRun(serializesPerShard: Bool) async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1)
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(), authority: authority,
            serializesPerShard: serializesPerShard)
        let blocked = TestBarrier()
        let started = TestBarrier()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { _ in
                started.open()
                try await blocked.wait()
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await started.wait()
        await hub.publish(try makeDeliveryEvent(2))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await hub.snapshot().subscriptions == 0)
        let next = try await hub.subscribe()
        let premature = Task {
            while !Task.isCancelled { await Task.yield() }
            try await dispatcher.run(subscription: next) { _ in Issue.record("Precancelled handler executed") }
        }
        premature.cancel()
        await #expect(throws: CancellationError.self) { try await premature.value }
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Shared FIFO admission bounds callbacks across clients, and cancelling its waiter removes admission state.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func sharedAuthorityAdmissionAndQueuedCancellation() async throws {
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1, maximumWaitingHandlers: 1)
        let a = GatewayEventHub(configuration: try .init())
        let b = GatewayEventHub(configuration: try .init())
        let first = try await a.subscribe()
        let second = try await b.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(), authority: authority)
        let started = TestBarrier()
        let blocked = TestBarrier()
        let taskA = Task {
            try await dispatcher.run(subscription: first) { _ in
                started.open()
                try await blocked.wait()
            }
        }
        await a.publish(try makeDeliveryEvent(1))
        try await started.wait()
        let taskB = Task {
            try await dispatcher.run(subscription: second) { _ in Issue.record("Cancelled queued callback executed") }
        }
        await b.publish(try makeDeliveryEvent(1))
        while await authority.snapshot().waitingHandlers != 1 { await Task.yield() }
        #expect(await authority.snapshot().activeHandlers == 1)
        taskB.cancel()
        await #expect(throws: CancellationError.self) { try await taskB.value }
        #expect(await authority.snapshot().waitingHandlers == 0)
        taskA.cancel()
        await #expect(throws: CancellationError.self) { try await taskA.value }
        #expect(await authority.snapshot().activeHandlers == 0)
    }

    /// Exhausted aggregate wait capacity surfaces an error; releasing a permit wakes the oldest remaining waiter.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func sharedAuthorityCapacityAndPermitTransfer() async throws {
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1, maximumWaitingHandlers: 1)
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(), authority: authority)
        let hubs = try (0..<3).map { _ in GatewayEventHub(configuration: try .init()) }
        var subscriptions: [GatewayEventSubscription] = []
        for hub in hubs { subscriptions.append(try await hub.subscribe()) }
        let blocked = TestBarrier()
        let started = TestBarrier()
        let transferred = TestBarrier()
        let first = subscriptions[0]
        let second = subscriptions[1]
        let third = subscriptions[2]
        let a = Task {
            try await dispatcher.run(subscription: first) { _ in started.open(); try await blocked.wait() }
        }
        await hubs[0].publish(try makeDeliveryEvent(1))
        try await started.wait()
        let b = Task {
            try await dispatcher.run(subscription: second) { _ in transferred.open() }
        }
        await hubs[1].publish(try makeDeliveryEvent(1))
        while await authority.snapshot().waitingHandlers != 1 { await Task.yield() }
        let c = Task { try await dispatcher.run(subscription: third) { _ in Issue.record("Excess callback executed") } }
        await hubs[2].publish(try makeDeliveryEvent(1))
        await #expect(throws: GatewayEventDeliveryFailure.handlerCapacityExceeded) { try await c.value }
        blocked.open()
        try await transferred.wait()
        await hubs[0].finish()
        await hubs[1].finish()
        try await a.value
        try await b.value
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
    }

    /// Two independently admitted waiters receive the sole shared permit in FIFO order across dispatchers.
    /// Explicit callback gates establish both queued admissions before releasing the first permit and keep
    /// the second callback active while the third remains queued; no timing assumptions or sleeps are needed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func sharedAuthorityPreservesFIFOAcrossTwoWaiters() async throws {
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1, maximumWaitingHandlers: 2)
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(), authority: authority)
        let hubs = try (0..<3).map { _ in GatewayEventHub(configuration: try .init()) }
        var subscriptions: [GatewayEventSubscription] = []
        for hub in hubs { subscriptions.append(try await hub.subscribe()) }
        let first = subscriptions[0], second = subscriptions[1], third = subscriptions[2]
        let firstStarted = TestBarrier(), secondStarted = TestBarrier(), thirdFinished = TestBarrier()
        let firstBlocked = TestBarrier(), secondBlocked = TestBarrier()
        let observations = HandlerObservations()
        let a = Task {
            try await dispatcher.run(subscription: first) { event in
                await observations.begin(event)
                firstStarted.open()
                try await firstBlocked.wait()
                await observations.end(event)
            }
        }
        await hubs[0].publish(try makeDeliveryEvent(1))
        try await firstStarted.wait()
        let b = Task {
            try await dispatcher.run(subscription: second) { event in
                await observations.begin(event)
                secondStarted.open()
                try await secondBlocked.wait()
                await observations.end(event)
            }
        }
        await hubs[1].publish(try makeDeliveryEvent(2))
        while await authority.snapshot().waitingHandlers != 1 { await Task.yield() }
        let c = Task {
            try await dispatcher.run(subscription: third) { event in
                await observations.begin(event)
                await observations.end(event)
                thirdFinished.open()
            }
        }
        await hubs[2].publish(try makeDeliveryEvent(3))
        while await authority.snapshot().waitingHandlers != 2 { await Task.yield() }
        #expect(await observations.snapshot().begun == ["0:1"])
        firstBlocked.open()
        try await secondStarted.wait()
        #expect(await observations.snapshot().begun == ["0:1", "0:2"])
        #expect(await authority.snapshot().activeHandlers == 1)
        #expect(await authority.snapshot().waitingHandlers == 1)
        secondBlocked.open()
        try await thirdFinished.wait()
        for hub in hubs { await hub.finish() }
        try await a.value
        try await b.value
        try await c.value
        let final = await observations.snapshot()
        #expect(final.begun == ["0:1", "0:2", "0:3"])
        #expect(final.ended == final.begun)
        #expect(final.maximumActive == 1)
        #expect(!final.sameShardOverlap)
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
        for hub in hubs { #expect(await hub.snapshot().subscriptions == 0) }
    }

    /// An event exceeding the retained byte budget fails without invoking user code or retaining its queue.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func oversizedHandlerEvent() async throws {
        let event = try makeDeliveryEvent(1)
        let hub = GatewayEventHub(configuration: try .init())
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumRetainedBytes: event.retainedByteCount - 1))
        await hub.publish(event)
        await #expect(throws: GatewayEventDeliveryFailure.handlerCapacityExceeded) {
            try await dispatcher.run(subscription: subscription) { _ in Issue.record("Oversized handler executed") }
        }
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A single retained event pauses input; overload stays in the independent bounded subscription and is explicit.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func retainedCountBackpressureAndSubscriptionOverflow() async throws {
        let hub = GatewayEventHub(configuration: try .init(maximumEventsPerSubscription: 1))
        let subscription = try await hub.subscribe()
        let dispatcher = GatewayEventHandlerDispatcher(configuration: try .init(maximumRetainedEvents: 1))
        let started = TestBarrier()
        let blocked = TestBarrier()
        let task = Task {
            try await dispatcher.run(subscription: subscription) { _ in
                started.open()
                try await blocked.wait()
            }
        }
        await hub.publish(try makeDeliveryEvent(1))
        try await started.wait()
        await hub.publish(try makeDeliveryEvent(2))
        #expect(await hub.snapshot().bufferedEvents == 1)
        #expect(await hub.publish(try makeDeliveryEvent(3)).terminated == 1)
        blocked.open()
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await task.value }
        #expect(await hub.snapshot().subscriptions == 0)
    }
}

/// Distinguishable application failure proves dispatch does not discard or replace callback errors.
private enum HandlerTestFailure: Error, Equatable { case callback }

/// Actor-owned callback observations avoid data races in deterministic ordering/concurrency assertions.
private actor HandlerObservations {
    private var begun: [String] = []
    private var ended: [String] = []
    private var active: Set<ShardIdentity> = []
    private var activeCount = 0
    private var maximumActive = 0
    private var sameShardOverlap = false

    /// Records callback entry and detects overlap within the same identity/topology/shard partition.
    /// - Parameter event: Received event whose shard and sequence identify test order.
    func begin(_ event: GatewayEvent) {
        if !active.insert(event.shard).inserted { sameShardOverlap = true }
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
        begun.append("\(event.shard.index):\(event.sequence ?? -1)")
    }

    /// Records completion and releases the observation's active partition.
    /// - Parameter event: Previously entered callback event.
    func end(_ event: GatewayEvent) {
        ended.append("\(event.shard.index):\(event.sequence ?? -1)")
        active.remove(event.shard)
        activeCount -= 1
    }

    /// Copies bounded test observations for assertions without exposing mutable actor state.
    /// - Returns: Entry/completion sequences, observed parallelism, and same-shard overlap flag.
    func snapshot() -> (begun: [String], ended: [String], maximumActive: Int, sameShardOverlap: Bool) {
        (begun, ended, maximumActive, sameShardOverlap)
    }
}
