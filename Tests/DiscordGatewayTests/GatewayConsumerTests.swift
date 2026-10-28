// File: Tests/DiscordGatewayTests/GatewayConsumerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordGateway

/// Public replay-envelope validation and owned asynchronous raw-consumer regression contracts.
@Suite("Gateway consumer ingress", .timeLimit(.minutes(1)))
struct GatewayConsumerTests {
    /// Accounted bytes equal complete UTF-8 JSON envelopes; local socket generations add no wire bytes.
    @Test func publicEventEnvelopeAndGeneration() throws {
        let shard = try ShardIdentity(botID: UserID(rawValue: UInt64.max), topologyGeneration: .max,
            index: 0, count: 1)
        let payload: JSONValue = .object(["future": .string("雪"), "id": .string("18446744073709551615")])
        let event = try GatewayEvent(shard: shard, name: "FUTURE", sequence: .max,
            data: payload, socketGeneration: .max)
        let expected = try JSONValue.object(["op": .number(JSONNumber(rawValue: "0")),
            "t": .string("FUTURE"), "s": .number(JSONNumber(rawValue: String(Int64.max))), "d": payload]).serialized()
        #expect(event.retainedByteCount == expected.count)
        #expect(event.socketGeneration == UInt64.max && event.sequence == Int64.max)
        #expect(event.shard == shard && event.data == payload)
        #expect(event.description == "GatewayEvent(redacted)")
        #expect(event.customMirror.children.count == 1)
        let offline = try GatewayEvent(shard: shard, name: "FUTURE", sequence: .max, data: payload)
        #expect(offline.socketGeneration == 0 && offline.retainedByteCount == event.retainedByteCount)
        let futureOpcode = try GatewayEvent(shard: shard, opcode: Int.max, name: nil, sequence: nil, data: .null)
        #expect(futureOpcode.opcode == Int.max && futureOpcode.name == nil && futureOpcode.sequence == nil)
        #expect(try futureOpcode.decodeDispatch() == nil)
    }

    /// Dispatches require names/sequences; every opcode rejects negative sequences and negative opcodes.
    @Test func publicEventInvalidShape() throws {
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        let invalid: [(Int, String?, Int64?)] = [
            (-1, "FUTURE", 1), (0, nil, 1), (0, "", 1), (0, "FUTURE", nil),
            (0, "FUTURE", -1), (1, nil, -1)
        ]
        for (opcode, name, sequence) in invalid {
            #expect(throws: GatewayFailure.invalidPayload) {
                try GatewayEvent(shard: shard, opcode: opcode, name: name, sequence: sequence, data: .null)
            }
        }
        let boundary = try GatewayEvent(shard: shard, name: "FUTURE", sequence: 0, data: .null)
        #expect(boundary.sequence == 0)
    }

    /// Full-envelope limits enforce byte, depth, node, and configuration failures before admission.
    @Test func publicEventSerializationLimits() throws {
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        let event = try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .null)
        #expect(try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .null,
            limits: JSONLimits(maximumBytes: event.retainedByteCount)).retainedByteCount == event.retainedByteCount)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .null,
                limits: JSONLimits(maximumBytes: event.retainedByteCount - 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .array([.null]),
                limits: JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .null,
                limits: JSONLimits(maximumNodes: 1))
        }
        #expect(throws: JSONValueError.invalidLimits) {
            try GatewayEvent(shard: shard, name: "FUTURE", sequence: 1, data: .null,
                limits: JSONLimits(maximumBytes: 0))
        }
    }

    /// A pending async read wakes on READY, then pulls bounded ordered batches with real socket provenance.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nextEventsWakeBatchAndStop() async throws {
        let identified = TestBarrier(), readyGate = TestBarrier(), ingested = TestBarrier(), idle = TestBarrier()
        let socket = GatewayTestSocket(steps: [
            { .text(consumerHello) },
            { try await identified.wait(); try await readyGate.wait(); return .text(consumerReady) },
            { .text(#"{"op":0,"s":2,"t":"FUTURE","d":{"value":1}}"#) },
            { .text(#"{"op":0,"s":3,"t":"FUTURE","d":{"value":2}}"#) },
            { ingested.open(); try await idle.wait(); return nil }
        ], onSend: { if $0.opcode == 2 { identified.open() } })
        let fixture = try makeRuntime(sockets: [socket])
        let first = Task { try await fixture.shard.nextEvents(maximum: 1) }
        let run = Task { try await fixture.shard.run() }
        try await identified.wait()
        readyGate.open()
        let ready = try #require(try await first.value)
        #expect(ready.count == 1 && ready[0].name == "READY")
        #expect(ready[0].socketGeneration == 1)
        try await ingested.wait()
        let next = try #require(try await fixture.shard.nextEvents(maximum: 1))
        #expect(next.map(\.sequence) == [2])
        let remainder = try #require(try await fixture.shard.nextEvents(maximum: Int.max))
        #expect(remainder.map(\.sequence) == [3])
        #expect(remainder.allSatisfy { $0.socketGeneration == 1 })
        #expect(await fixture.shard.snapshot().bufferedBytes == 0)
        await fixture.shard.stop()
        try await run.value
        #expect(try await fixture.shard.nextEvents() == nil)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Concurrent raw reads cannot accumulate waiters: one fails and stopping resolves the sole admitted reader.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nextEventsRejectsConcurrentConsumers() async throws {
        let fixture = try makeRuntime(sockets: [])
        await withTaskGroup(of: ConsumerReadResult.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return try await fixture.shard.nextEvents() == nil ? .finished : .events }
                    catch let error as GatewayFailure { return .gateway(error) }
                    catch { return .unexpected }
                }
            }
            #expect(await group.next() == .gateway(.alreadyRunning))
            await fixture.shard.stop()
            #expect(await group.next() == .finished)
        }
        #expect(await fixture.transport.connectionCount == 0)
        #expect(try await fixture.shard.nextEvents() == nil)
    }

    /// Invalid maxima fail immediately; cancellation releases the sole consumer reservation on every path.
    /// - Parameter beforeCall: Cancels before entry instead of while waiting for an event.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func nextEventsCancellationAndValidation(_ beforeCall: Bool) async throws {
        let fixture = try makeRuntime(sockets: [])
        for maximum in [0, -1] {
            await #expect(throws: GatewayFailure.invalidConfiguration) { try await fixture.shard.nextEvents(maximum: maximum) }
        }
        if beforeCall {
            let task = Task {
                while !Task.isCancelled { await Task.yield() }
                return try await fixture.shard.nextEvents()
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await withTaskGroup(of: ConsumerReadResult.self) { group in
                for _ in 0..<2 {
                    group.addTask {
                        do { return try await fixture.shard.nextEvents() == nil ? .finished : .events }
                        catch is CancellationError { return .cancelled }
                        catch let error as GatewayFailure { return .gateway(error) }
                        catch { return .unexpected }
                    }
                }
                // The overlapping-reader rejection proves its sibling already owns the suspended read.
                #expect(await group.next() == .gateway(.alreadyRunning))
                group.cancelAll()
                #expect(await group.next() == .cancelled)
            }
        }
        await fixture.shard.stop()
        #expect(try await fixture.shard.nextEvents() == nil)
        #expect(await fixture.shard.snapshot().bufferedEvents == 0)
    }

    /// Multi-shard cancellation drains every child result, retaining a later ownership-release outage.
    /// The first shard completes cancelled cleanup while the second release is explicitly held;
    /// an implicit task-group join would discard the second shard's eventual noncancellation error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func botCancellationPreservesLateSiblingReleaseFailure() async throws {
        let clock = ManualClock()
        let leases = try ConsumerReleaseLeases(clock: clock)
        let discovery = try makeDiscovery()
        let startup = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1),
            limit: discovery.sessionStartLimit, clock: clock)
        var shards: [GatewayShard<ManualClock, ConsumerReleaseLeases>] = []
        var sockets: [GatewayTestSocket] = []
        var receiving: [TestBarrier] = []
        for index in 0..<2 {
            let identified = TestBarrier(), ready = TestBarrier(), idle = TestBarrier()
            let socket = GatewayTestSocket(steps: [
                { .text(consumerHello) },
                { try await identified.wait(); return .text(consumerReady) },
                { ready.open(); try await idle.wait(); return nil }
            ], onSend: { if $0.opcode == 2 { identified.open() } })
            let shard = GatewayShard(identity: try ShardIdentity(botID: UserID(rawValue: 1),
                topologyGeneration: 0, index: index, count: 2), token: try BotToken("consumer-sentinel"),
                intents: 1, discovery: discovery, transport: GatewayTestTransport(sockets: [socket]),
                clock: clock, leases: leases, startup: startup, configuration: try .init(), random: { 1 })
            shards.append(shard)
            sockets.append(socket)
            receiving.append(ready)
        }
        let bot = try GatewayBot(shards: shards)
        let run = Task { try await bot.run() }
        for gate in receiving { try await gate.wait() }
        run.cancel()
        try await leases.firstReleased.wait()
        try await leases.lateReleaseEntered.wait()
        while await shards[0].snapshot().phase != .stopped { await Task.yield() }
        for _ in 0..<32 { await Task.yield() }
        await leases.allowLateRelease()
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await run.value }
        #expect(await leases.retainedCount() == 1)
        for socket in sockets { #expect(await socket.closed) }
        for shard in shards {
            #expect(await shard.snapshot().phase == .stopped)
            #expect(await shard.snapshot().bufferedBytes == 0)
        }
        #expect(clock.pendingSleepCount == 0)
    }
}

/// Closed read outcomes allow a task group to observe rejection without cancelling its admitted sibling.
private enum ConsumerReadResult: Sendable, Equatable {
    case finished, events, cancelled, gateway(GatewayFailure), unexpected
}

/// Credential-free Gateway Hello for regression sockets.
private let consumerHello = #"{"op":10,"d":{"heartbeat_interval":10000}}"#
/// READY only contains the protocol fields required by the session runtime.
private let consumerReady = #"{"op":0,"s":1,"t":"READY","d":{"session_id":"consumer","resume_gateway_url":"wss://gateway.discord.gg"}}"#

/// Shares real fenced ownership but delays shard one's failed release beyond shard zero's completed cleanup.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor ConsumerReleaseLeases: ShardLeaseStore {
    typealias LeaseClock = ManualClock
    nonisolated let firstReleased = TestBarrier()
    nonisolated let lateReleaseEntered = TestBarrier()
    private let base: InProcessShardLeaseStore<ManualClock>
    private var releaseAllowed = false
    private var lateWaiter: CheckedContinuation<Void, Never>?

    /// Creates a two-session real ownership ledger without launching tasks.
    /// - Parameter clock: Monotonic clock shared by both shards.
    /// - Throws: Base capacity validation failures, impossible for the fixed positive capacity.
    init(clock: ManualClock) throws { base = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2) }

    /// Acquires real atomic ownership without changing the fixture's late-release behavior.
    /// - Parameters:
    ///   - shard: One of the two test topology assignments.
    ///   - owner: Fresh nonsecret worker identifier.
    ///   - lifetime: Positive clock-domain lease duration.
    /// - Returns: The current fenced ticket.
    /// - Throws: Base cancellation, conflict, or capacity errors.
    func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.acquire(shard, owner: owner, lifetime: lifetime)
    }

    /// Validates the unchanged real ownership ledger.
    /// - Parameter lease: Current ticket to check.
    /// - Throws: Cancellation or stale/expired authority.
    func validate(_ lease: ShardLease<ManualClock>) async throws { try await base.validate(lease) }

    /// Renews the current ticket through real generation/expiry fencing.
    /// - Parameters:
    ///   - lease: Unexpired ticket being replaced.
    ///   - lifetime: Positive replacement duration.
    /// - Returns: The newly fenced ticket.
    /// - Throws: Base cancellation, duration, or stale ownership errors.
    func renew(_ lease: ShardLease<ManualClock>, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.renew(lease, lifetime: lifetime)
    }

    /// Releases shard zero immediately and parks shard one's mandatory cleanup before a closed outage.
    /// - Parameter lease: Latest ticket. Parking intentionally ignores caller cancellation during cleanup.
    /// - Throws: `coordinatorUnavailable` only for shard one, retaining its record until expiry.
    func release(_ lease: ShardLease<ManualClock>) async throws {
        if lease.shard.index == 0 {
            await base.release(lease)
            firstReleased.open()
            return
        }
        lateReleaseEntered.open()
        if !releaseAllowed { await withCheckedContinuation { lateWaiter = $0 } }
        throw ShardOwnershipFailure.coordinatorUnavailable
    }

    /// Resolves the sole late-release hold exactly once, allowing its configured failure to propagate.
    func allowLateRelease() {
        releaseAllowed = true
        lateWaiter?.resume()
        lateWaiter = nil
    }

    /// Reads retained authority after both child lifetimes finish.
    /// - Returns: One retained ticket after the intentional shard-one release outage.
    func retainedCount() async -> Int { await base.retainedLeaseCount() }
}
