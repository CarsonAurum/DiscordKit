// File: Tests/DiscordVoiceTests/VoiceManagerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Synchronization
import Testing
@testable import DiscordVoice

/// Observes cancellation of independent stop waiters without relying on executor polling.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class VoiceStopCancellationObserver: Sendable {
    let second = TestBarrier()
    private let count = Mutex(0)

    /// Records one cancelled stop waiter and opens the gate when a second owner cancels.
    /// The runtime's cancellation accounts for the first waiter; cancelling the retained
    /// manager teardown must reach the other waiter before physical cleanup is released.
    func record() {
        let reachedSecond = count.withLock { value in value += 1; return value == 2 }
        if reachedSecond { second.open() }
    }
}

/// Deterministic owned session used to verify manager lifetimes without opening sockets.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor ManagedVoiceTestSession: VoiceManagedSession {
    nonisolated let started = TestBarrier()
    nonisolated let stopEntered = TestBarrier()
    nonisolated let stopCancellation = VoiceStopCancellationObserver()
    private let finished = TestBarrier()
    private var stops = 0
    private let failRun: Bool
    private let stopGate: TestBarrier?
    private var cleanupCompleted = false
    private var cleanupTask: Task<Void, Never>?

    /// Creates an inert fake whose optional terminal failure is observed through diagnostics.
    /// - Parameters:
    ///   - failRun: Whether `run` throws after announcing its start.
    ///   - stopGate: Optional cancellation-independent physical-cleanup suspension.
    init(failRun: Bool = false, stopGate: TestBarrier? = nil) { self.failRun = failRun; self.stopGate = stopGate }

    /// Announces admission and waits for explicit stop or cancellation without wall time.
    /// - Throws: The configured terminal failure or cooperative cancellation.
    func run() async throws {
        started.open()
        if failRun { throw VoiceManagerFailure.disconnected }
        try await finished.wait()
    }

    /// Shares one cancellation-independent cleanup task across all idempotent stop callers.
    /// Every caller waits for physical cleanup, including callers whose task is cancelled.
    func stop() async {
        let task: Task<Void, Never>
        if let cleanupTask { task = cleanupTask }
        else {
            stops += 1; finished.open(); stopEntered.open()
            let gate = stopGate
            task = Task { if let gate { try? await gate.wait() } }
            cleanupTask = task
        }
        let cancellation = stopCancellation
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            cancellation.record()
        }
        cleanupCompleted = true
    }

    /// Reports physical cleanup count, rather than the number of idempotent stop invocations.
    /// - Returns: Zero before cleanup and one after cleanup.
    func stopCount() -> Int { stops }

    /// Reports whether the admitted physical cleanup passed its optional gate.
    /// - Returns: False while teardown is suspended, true once cleanup has completed.
    func didCompleteCleanup() -> Bool { cleanupCompleted }
}

/// Records commands and created owners with finite test-only event gates.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor VoiceManagerHarness {
    private var commands: [VoiceManagerCommand] = []
    private var credentials: [VoiceConnectionCredentials] = []
    private var sessions: [ManagedVoiceTestSession] = []
    private var commandWaiters: [Int: TestBarrier] = [:]
    private var creationWaiters: [Int: TestBarrier] = [:]
    private let failCommand: Bool
    private let failFactory: Bool
    private let failRun: Bool
    private let factoryGate: TestBarrier?
    private let factoryGateAfter: Int
    private let factoryHoldsThroughCancellation: Bool
    private let stopGate: TestBarrier?
    private let leaveGate: TestBarrier?
    private let failLeave: Bool

    /// Configures independent sender/factory/runtime failures without network access.
    /// - Parameters:
    ///   - failCommand: Reject non-leave commands after recording them.
    ///   - failFactory: Reject creation before returning an owner.
    ///   - failRun: Return an owner that fails its runtime.
    ///   - factoryGate: Optional gate delaying factory completion; cancellation is deliberately
    ///     ignored there to verify that the manager closes a late returned owner.
    ///   - factoryGateAfter: Number of initial creations allowed through without waiting,
    ///     default zero; one permits a first session before suspending its replacement.
    ///   - factoryHoldsThroughCancellation: Whether a separate unstructured task owns the
    ///     factory gate, so cancellation cannot finish creation until the test opens it.
    ///   - stopGate: Optional gate keeping physical cleanup suspended during replacement races.
    ///   - leaveGate: Optional gate holding the once-only Gateway leave sender after admission.
    ///   - failLeave: Whether the admitted leave fails after its optional gate is released.
    init(failCommand: Bool = false, failFactory: Bool = false, failRun: Bool = false,
         factoryGate: TestBarrier? = nil, factoryGateAfter: Int = 0, stopGate: TestBarrier? = nil,
         leaveGate: TestBarrier? = nil, failLeave: Bool = false, factoryHoldsThroughCancellation: Bool = false) {
        self.failCommand = failCommand; self.failFactory = failFactory
        self.failRun = failRun; self.factoryGate = factoryGate; self.stopGate = stopGate
        self.factoryGateAfter = factoryGateAfter
        self.leaveGate = leaveGate; self.failLeave = failLeave
        self.factoryHoldsThroughCancellation = factoryHoldsThroughCancellation
    }

    /// Records one exact request and wakes any test waiting for this command count.
    /// - Parameter command: Once-only request supplied by the manager.
    /// - Throws: Configured sender failure, or cancellation of the optional leave gate.
    func send(_ command: VoiceManagerCommand) async throws {
        commands.append(command); commandWaiters.removeValue(forKey: commands.count)?.open()
        if failCommand, command.channelID != nil { throw VoiceManagerFailure.disconnected }
        if command.channelID == nil {
            if let leaveGate { try await leaveGate.wait() }
            if failLeave { throw VoiceManagerFailure.invalidConfiguration }
        }
    }

    /// Creates and records a fresh inert fake, optionally delaying or failing its return.
    /// - Parameter credentials: Complete pair whose generation and replacement are asserted.
    /// - Returns: A unique session owner for this exact credential generation.
    /// - Throws: Configured factory failure; never records a real credential or opens I/O.
    func make(_ credentials: VoiceConnectionCredentials) async throws -> any VoiceManagedSession {
        if failFactory { throw VoiceManagerFailure.disconnected }
        let session = ManagedVoiceTestSession(failRun: failRun, stopGate: stopGate)
        self.credentials.append(credentials); sessions.append(session)
        creationWaiters.removeValue(forKey: sessions.count)?.open()
        if let factoryGate, sessions.count > factoryGateAfter {
            if factoryHoldsThroughCancellation { await Task { try? await factoryGate.wait() }.value }
            else { try? await factoryGate.wait() }
        }
        return session
    }

    /// Waits for an exact command count without polling or sleeping.
    /// - Parameter count: Positive expected count in this finite fixture.
    /// - Throws: Cancellation of the testing task.
    func waitForCommand(_ count: Int) async throws {
        if commands.count >= count { return }
        let gate = commandWaiters[count] ?? TestBarrier()
        commandWaiters[count] = gate
        try await gate.wait()
    }

    /// Waits for an exact factory admission count without requiring factory completion.
    /// - Parameter count: Positive expected session count in this finite fixture.
    /// - Throws: Cancellation of the testing task.
    func waitForCreation(_ count: Int) async throws {
        if sessions.count >= count { return }
        let gate = creationWaiters[count] ?? TestBarrier()
        creationWaiters[count] = gate
        try await gate.wait()
    }

    /// Returns immutable synthetic command and credential projections for assertions.
    /// - Returns: Requests and credential pairs in their admission order.
    func recorded() -> ([VoiceManagerCommand], [VoiceConnectionCredentials]) { (commands, credentials) }

    /// Retrieves one known created fake without widening the production manager API.
    /// - Parameter index: Zero-based index below the asserted creation count.
    /// - Returns: The owned fake session actor.
    func session(_ index: Int) -> ManagedVoiceTestSession { sessions[index] }
}

/// Exercises bounded guild admission, exact event fences, replacement and complete cleanup.
@Suite("Supervised voice manager")
struct VoiceManagerTests {
    /// Builds one realistic self voice-state model with explicit nullable channel semantics.
    /// - Parameters:
    ///   - guild: Scoped guild, default one.
    ///   - channel: Requested channel, default three; nil represents leaving.
    ///   - session: Synthetic voice session identifier.
    ///   - user: Sender account, default the manager's account two.
    /// - Returns: Typed immutable VOICE_STATE_UPDATE projection.
    /// - Throws: Fixture JSON/model validation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func state(guild: UInt64 = 1, channel: UInt64? = 3, session: String = "session",
                       user: UInt64 = 2) throws -> VoiceState {
        try VoiceState(data: JSONValue.object(["guild_id": .string(String(guild)), "user_id": .string(String(user)),
            "channel_id": channel.map { .string(String($0)) } ?? .null, "session_id": .string(session),
            "deaf": .bool(false), "mute": .bool(false), "self_deaf": .bool(false), "self_mute": .bool(false),
            "self_video": .bool(false), "suppress": .bool(false), "request_to_speak_timestamp": .null]).serialized())
    }

    /// Builds a synthetic server event, including null endpoints for replacement tests.
    /// - Parameters:
    ///   - guild: Scoped guild, default one.
    ///   - token: Synthetic ephemeral voice token.
    ///   - endpoint: Scheme-free server name; nil clears both rendezvous halves.
    /// - Returns: Typed immutable VOICE_SERVER_UPDATE projection.
    /// - Throws: Fixture JSON/model validation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func server(guild: UInt64 = 1, token: String = "token", endpoint: String? = "voice.discord.media") throws
        -> GatewayVoiceServerUpdate {
        try GatewayVoiceServerUpdate(data: JSONValue.object(["guild_id": .string(String(guild)),
            "token": .string(token), "endpoint": endpoint.map(JSONValue.string) ?? .null]).serialized())
    }

    /// Composes one inert manager over the deterministic test clock and injectable fake owners.
    /// - Parameters:
    ///   - harness: Callback recorder/failure policy.
    ///   - clock: Independent monotonic test clock.
    ///   - maximumGuilds: Aggregate guild retention budget, default two.
    /// - Returns: Manager for authenticated account two, with no started tasks or callbacks.
    /// - Throws: Manager policy validation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func manager(_ harness: VoiceManagerHarness, clock: ManualClock = ManualClock(), maximumGuilds: Int = 2) throws
        -> VoiceManager<ManualClock> {
        try VoiceManager(userID: UserID(rawValue: 2), clock: clock, maximumGuilds: maximumGuilds,
            sendCommand: { try await harness.send($0) }, makeSession: { try await harness.make($0) })
    }

    /// Completes a known pending join in either event order and returns its routing fence.
    /// - Parameters:
    ///   - manager: Owner whose matching command has already been observed.
    ///   - guild: Guild receiving the pair, default one.
    ///   - channel: Requested channel, default three.
    ///   - serverFirst: Whether to deliver server credentials before self state.
    /// - Returns: Captured current local event-routing generation.
    /// - Throws: Missing fence, model validation, or event admission errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func complete(_ manager: VoiceManager<ManualClock>, guild: UInt64 = 1, channel: UInt64 = 3,
                          serverFirst: Bool = false) async throws -> UInt64 {
        let generation = try #require(await manager.generation(guildID: GuildID(rawValue: guild)))
        if serverFirst {
            try await manager.route(server: server(guild: guild), generation: generation)
            try await manager.route(state: state(guild: guild, channel: channel), generation: generation)
        } else {
            try await manager.route(state: state(guild: guild, channel: channel), generation: generation)
            try await manager.route(server: server(guild: guild), generation: generation)
        }
        return generation
    }

    /// Waits for an exact retained-operation count while independent route callers suspend.
    /// - Parameters:
    ///   - manager: Single-guild owner whose numeric resource diagnostics are observed.
    ///   - count: Expected depth in the bounded operation chain.
    /// - Throws: Cancellation of the testing task; no wall-clock deadline or sleep is used.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func waitForOperations(_ manager: VoiceManager<ManualClock>, count: Int) async throws {
        while await manager.snapshot().retainedOperationCount != count {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    /// Enters a concurrent leave while holding the manager's actor isolation.
    /// - Parameters:
    ///   - owner: Manager whose already-closing slot must share its current cleanup task.
    ///   - entered: Opens before the direct isolated call; a later actor operation can run
    ///     only after this call reaches its cleanup suspension, avoiding scheduling races.
    /// - Throws: The exact shared leave-sender error after physical cleanup completes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func concurrentLeave(_ owner: isolated VoiceManager<ManualClock>, entered: TestBarrier) async throws {
        entered.open()
        try await owner.leave(guildID: GuildID(rawValue: 1))
    }

    /// Construction remains inert and invalid aggregate/credential policies reject immediately.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inertConstructionAndValidation() async throws {
        let harness = VoiceManagerHarness(), clock = ManualClock()
        for capacity in [0, 65_537] {
            #expect(throws: VoiceManagerFailure.invalidConfiguration) {
                try manager(harness, clock: clock, maximumGuilds: capacity)
            }
            #expect(throws: VoiceManagerFailure.invalidConfiguration) {
                try VoiceManager(userID: UserID(rawValue: 2), clock: clock, maximumCredentialFieldBytes: capacity,
                    sendCommand: { try await harness.send($0) }, makeSession: { try await harness.make($0) })
            }
        }
        let owner = try manager(harness, clock: clock)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.recorded().0.isEmpty)
        for timeout in [Duration.zero, .seconds(-1), .seconds(86_401)] {
            await #expect(throws: VoiceManagerFailure.invalidConfiguration) {
                try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3), timeout: timeout)
            }
        }
        await owner.stop(); await owner.stop()
        #expect(await owner.snapshot().isStopped)
        await #expect(throws: VoiceManagerFailure.closed) {
            try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3))
        }
    }

    /// Both event orders create exactly one owned session; duplicate/member events add no work.
    /// - Parameter serverFirst: Whether server information arrives first.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func joinOrdersAndDuplicateSuppression(serverFirst: Bool) async throws {
        let harness = VoiceManagerHarness(), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3), selfMute: true) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner, serverFirst: serverFirst)
        _ = try await join.value
        let session = await harness.session(0)
        try await session.started.wait()
        try await owner.route(state: state(channel: nil, user: 99), generation: generation)
        try await owner.route(state: state(), generation: generation)
        try await owner.route(server: server(), generation: generation)
        let recorded = await harness.recorded()
        #expect(recorded.0 == [VoiceManagerCommand(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3), selfMute: true)])
        #expect(recorded.1.count == 1 && recorded.1[0].generation != generation)
        #expect(await owner.snapshot().runningSessionCount == 1)
        try await owner.leave(guildID: GuildID(rawValue: 1))
        try await owner.leave(guildID: GuildID(rawValue: 1))
        #expect(await session.stopCount() == 1)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await owner.snapshot().completedSessionCount == 1)
        #expect(await harness.recorded().0.count == 2)
    }

    /// Pending guild slots enforce aggregate/overlap limits and cancellation fully releases them.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pendingCapacityAndCancellation() async throws {
        let harness = VoiceManagerHarness(), clock = ManualClock(), owner = try manager(harness, clock: clock, maximumGuilds: 1)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        await #expect(throws: VoiceManagerFailure.operationInProgress) {
            try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 4))
        }
        await #expect(throws: VoiceManagerFailure.capacityExceeded) {
            try await owner.join(guildID: GuildID(rawValue: 2), channelID: ChannelID(rawValue: 3))
        }
        #expect(await owner.snapshot().pendingJoinCount == 1)
        join.cancel()
        await #expect(throws: CancellationError.self) { try await join.value }
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(await harness.recorded().0.last?.channelID == nil)
        await owner.stop()
    }

    /// A missing event expires under the injected clock and no continuation/timer survives.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rendezvousDeadline() async throws {
        let scheduled = TestBarrier(), harness = VoiceManagerHarness()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() }), owner = try manager(harness, clock: clock)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3), timeout: .seconds(2)) }
        try await harness.waitForCommand(1); try await scheduled.wait()
        let generation = try #require(await owner.generation(guildID: GuildID(rawValue: 1)))
        try await owner.route(server: server(), generation: generation)
        try clock.advance(by: .seconds(2))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await join.value }
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(await harness.recorded().1.isEmpty)
        await owner.stop()
    }

    /// Explicit moves stop old owners and reject old fences even when the endpoint repeats.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func moveReplacesCredentialsAndFencesOldEvents() async throws {
        let harness = VoiceManagerHarness(), owner = try manager(harness)
        let first = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let oldGeneration = try await complete(owner)
        _ = try await first.value
        let old = await harness.session(0)
        try await old.started.wait()
        let moved = Task { try await owner.move(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 4), selfDeaf: true) }
        try await harness.waitForCommand(2)
        #expect(await old.stopCount() == 1)
        await #expect(throws: VoiceManagerFailure.staleGeneration) {
            try await owner.route(server: server(), generation: oldGeneration)
        }
        let generation = try #require(await owner.generation(guildID: GuildID(rawValue: 1)))
        try await owner.route(server: server(token: "new-token"), generation: generation)
        try await owner.route(state: state(channel: 4, session: "new-session"), generation: generation)
        _ = try await moved.value
        let pairs = await harness.recorded().1
        #expect(pairs.count == 2 && pairs[0].endpoint == pairs[1].endpoint)
        #expect(pairs[0].identity != pairs[1].identity && pairs[1].token == "new-token")
        #expect(await harness.recorded().0.last?.selfDeaf == true)
        await owner.stop()
        #expect(await owner.snapshot().completedSessionCount == 2)
    }

    /// Token/null-endpoint replacement suspends old media and requires the fresh event pair.
    /// - Parameter nullFirst: Whether temporary endpoint unavailability precedes the new pair.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func automaticServerReplacement(nullFirst: Bool) async throws {
        let harness = VoiceManagerHarness(), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        let old = await harness.session(0)
        if nullFirst { try await owner.route(server: server(endpoint: nil), generation: generation) }
        try await owner.route(server: server(token: "replacement"), generation: generation)
        #expect(await old.stopCount() == 1)
        #expect(await owner.snapshot().runningSessionCount == 0)
        try await owner.route(state: state(session: "replacement-session"), generation: generation)
        let pairs = await harness.recorded().1
        #expect(pairs.count == 2 && pairs[1].generation > pairs[0].generation)
        #expect(pairs[1].token == "replacement" && pairs[1].sessionID == "replacement-session")
        #expect(await harness.recorded().0.count == 1)
        await owner.stop()
    }

    /// Authenticated self leave or unsolicited channel movement closes runtime ownership.
    /// - Parameter channel: Nil for leave, or another channel for an unsolicited move.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Optional<UInt64>.none, 4])
    func serverDirectedLeaveAndMove(channel: UInt64?) async throws {
        let harness = VoiceManagerHarness(), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        try await owner.route(state: state(channel: channel), generation: generation)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.session(0).stopCount() == 1)
        #expect(await harness.recorded().0.count == 1)
        await owner.stop()
    }

    /// Sender/factory failures clean local state and send exactly one best-effort leave.
    /// - Parameter failSender: Whether failure occurs before waiting for events or at creation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func injectedAdmissionFailures(failSender: Bool) async throws {
        let harness = VoiceManagerHarness(failCommand: failSender, failFactory: !failSender, failLeave: true)
        let owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        if !failSender { _ = try await complete(owner) }
        await #expect(throws: VoiceManagerFailure.disconnected) { try await join.value }
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.recorded().0.count == 2)
        await owner.stop()
    }

    /// Cancelling during factory suspension closes its late returned owner and releases the slot.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringFactory() async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(factoryGate: gate), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        try await harness.waitForCreation(1)
        join.cancel()
        await #expect(throws: CancellationError.self) { try await join.value }
        #expect(await harness.session(0).stopCount() == 1)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        await owner.stop()
    }

    /// Runtime failure is counted after owned cleanup and cannot silently restart a session.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func terminalRuntimeFailureDiagnostics() async throws {
        let harness = VoiceManagerHarness(failRun: true), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        _ = try await join.value
        let session = await harness.session(0)
        try await session.started.wait()
        await owner.stop()
        let snapshot = await owner.snapshot()
        #expect(snapshot.completedSessionCount == 1 && snapshot.failedSessionCount == 1)
        #expect(await session.stopCount() == 1)
        #expect(await harness.recorded().1.count == 1)
    }

    /// Stop/leave await a pending factory and close its late owner before returning.
    /// - Parameter globalStop: Whether cleanup ends the whole manager or only the pending guild.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cleanupAwaitsPendingFactory(globalStop: Bool) async throws {
        let gate = TestBarrier()
        let harness = VoiceManagerHarness(factoryGate: gate, factoryHoldsThroughCancellation: true)
        let owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        try await harness.waitForCreation(1)
        let cleanup = Task {
            if globalStop { await owner.stop() }
            else { try await owner.leave(guildID: GuildID(rawValue: 1)) }
            #expect(await harness.session(0).didCompleteCleanup())
        }
        while await owner.snapshot().closingGuildCount != 1 { try Task.checkCancellation(); await Task.yield() }
        #expect(await harness.session(0).stopCount() == 0)
        #expect(await owner.snapshot().retainedGuildCount == 1)
        gate.open()
        try await cleanup.value
        #expect(await harness.session(0).stopCount() == 1)
        if globalStop {
            await #expect(throws: VoiceManagerFailure.closed) { try await join.value }
        } else {
            await #expect(throws: VoiceManagerFailure.disconnected) { try await join.value }
        }
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.recorded().0.count == 2)
        await owner.stop()
    }

    /// Stop/leave cancel a route-driven factory and await cleanup of its late returned owner.
    /// - Parameter globalStop: Whether cleanup closes the whole manager or only this guild.
    /// The initial active session admits normally; only its automatic credential replacement
    /// suspends in the factory, so this exercises ownership independent of explicit joins.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cleanupAwaitsAutomaticReplacementFactory(globalStop: Bool) async throws {
        let gate = TestBarrier()
        let harness = VoiceManagerHarness(factoryGate: gate, factoryGateAfter: 1, factoryHoldsThroughCancellation: true)
        let owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        let original = await harness.session(0)
        try await original.started.wait()
        try await owner.route(server: server(token: "replacement"), generation: generation)
        let replacement = Task {
            try await owner.route(state: state(session: "replacement-session"), generation: generation)
        }
        try await harness.waitForCreation(2)
        let lateOwner = await harness.session(1)
        let cleanup = Task {
            if globalStop { await owner.stop() }
            else { try await owner.leave(guildID: GuildID(rawValue: 1)) }
            #expect(await lateOwner.didCompleteCleanup())
        }
        while await owner.snapshot().closingGuildCount != 1 { try Task.checkCancellation(); await Task.yield() }
        #expect(await lateOwner.stopCount() == 0)
        #expect(await owner.snapshot().retainedGuildCount == 1)
        gate.open()
        try await cleanup.value
        #expect(await original.stopCount() == 1)
        #expect(await lateOwner.stopCount() == 1)
        #expect(await lateOwner.didCompleteCleanup())
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.recorded().0.count == 2)
        await #expect(throws: (any Error).self) { try await replacement.value }
        #expect(await harness.recorded().1.count == 2)
        await owner.stop()
    }

    /// Stop/leave retain a route-driven old-session teardown until physical cleanup finishes.
    /// - Parameter globalStop: Whether cleanup closes the whole manager or only this guild.
    /// A cancellation gate proves manager cleanup reached the retained teardown while its
    /// physical stop remained blocked; no wall-clock sleep or executor polling is required.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cleanupAwaitsAutomaticReplacementTeardown(globalStop: Bool) async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(stopGate: gate), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        let original = await harness.session(0)
        try await original.started.wait()
        let replacement = Task { try await owner.route(server: server(token: "replacement"), generation: generation) }
        try await original.stopEntered.wait()
        let cleanup = Task {
            if globalStop { await owner.stop() }
            else { try await owner.leave(guildID: GuildID(rawValue: 1)) }
        }
        try await original.stopCancellation.second.wait()
        #expect(await original.didCompleteCleanup() == false)
        gate.open()
        try await cleanup.value
        try await replacement.value
        #expect(await original.didCompleteCleanup())
        #expect(await original.stopCount() == 1)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.recorded().0.count == 2)
        #expect(await harness.recorded().1.count == 1)
        await owner.stop()
    }

    /// A second automatic replacement supersedes a pending factory without discarding its guild.
    /// The cancelled factory deliberately returns a late inert owner; it must be closed and
    /// release installation admission before the newest credential pair starts its own owner.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func automaticReplacementSupersedesPendingFactory() async throws {
        let gate = TestBarrier()
        let harness = VoiceManagerHarness(factoryGate: gate, factoryGateAfter: 1)
        let owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        try await owner.route(server: server(token: "replacement-one"), generation: generation)
        let superseded = Task {
            try await owner.route(state: state(session: "replacement-session-one"), generation: generation)
        }
        try await harness.waitForCreation(2)
        try await owner.route(server: server(token: "replacement-two"), generation: generation)
        await #expect(throws: CancellationError.self) { try await superseded.value }
        #expect(await harness.session(1).stopCount() == 1)
        #expect(await owner.snapshot().retainedGuildCount == 1)
        #expect(await owner.snapshot().runningSessionCount == 0)
        #expect(await harness.recorded().0.count == 1)
        gate.open()
        try await owner.route(state: state(session: "replacement-session-two"), generation: generation)
        let newest = await harness.session(2)
        try await newest.started.wait()
        let pairs = await harness.recorded().1
        #expect(pairs.count == 3)
        #expect(pairs[2].sessionID == "replacement-session-two" && pairs[2].token == "replacement-two")
        #expect(pairs[2].generation > pairs[1].generation)
        #expect(await owner.snapshot().runningSessionCount == 1)
        await owner.stop()
        #expect(await newest.stopCount() == 1)
    }

    /// A fifth overlapping replacement task fails closed while four owned tasks remain bounded.
    /// A held physical cleanup gate keeps earlier operations alive, and resource diagnostics
    /// synchronize each admission without wall time. Releasing cleanup joins every route,
    /// emits one leave, and admits no replacement factory or leaked ownership.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(.timeLimit(.minutes(1))) func automaticReplacementOperationBound() async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(stopGate: gate), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        let generation = try await complete(owner)
        _ = try await join.value
        let original = await harness.session(0)
        try await original.started.wait()
        let firstServer = Task { try await owner.route(server: server(token: "replacement-one"), generation: generation) }
        try await original.stopEntered.wait()
        let firstState = Task {
            try await owner.route(state: state(session: "replacement-session-one"), generation: generation)
        }
        try await waitForOperations(owner, count: 2)
        let secondServer = Task { try await owner.route(server: server(token: "replacement-two"), generation: generation) }
        try await waitForOperations(owner, count: 3)
        let secondState = Task {
            try await owner.route(state: state(session: "replacement-session-two"), generation: generation)
        }
        try await waitForOperations(owner, count: 4)
        let overflow = Task { try await owner.route(server: server(token: "replacement-three"), generation: generation) }
        while await owner.snapshot().closingGuildCount != 1 {
            try Task.checkCancellation()
            await Task.yield()
        }
        #expect(await owner.snapshot().retainedOperationCount == 4)
        #expect(await original.didCompleteCleanup() == false)
        gate.open()
        await #expect(throws: VoiceManagerFailure.capacityExceeded) { try await overflow.value }
        try await firstServer.value
        try await secondServer.value
        await #expect(throws: CancellationError.self) { try await firstState.value }
        await #expect(throws: CancellationError.self) { try await secondState.value }
        let snapshot = await owner.snapshot()
        #expect(snapshot.retainedGuildCount == 0 && snapshot.retainedOperationCount == 0)
        #expect(await original.didCompleteCleanup())
        #expect(await harness.recorded().0.count == 2)
        #expect(await harness.recorded().1.count == 1)
        await owner.stop()
    }

    /// Concurrent leaves and global stop share one close while physical teardown is blocked.
    /// A direct isolated second leave reaches the manager before stop can mark it stopped.
    /// Cancelling that waiter cannot release it early or cancel the shared physical cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentLeavesAndStopShareBlockedTeardown() async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(stopGate: gate), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        _ = try await join.value
        let original = await harness.session(0)
        try await original.started.wait()
        let first = Task {
            try await owner.leave(guildID: GuildID(rawValue: 1))
            #expect(await original.didCompleteCleanup())
        }
        try await original.stopEntered.wait()
        let entered = TestBarrier()
        let second = Task {
            try await concurrentLeave(owner, entered: entered)
            #expect(await original.didCompleteCleanup())
        }
        try await entered.wait()
        let stop = Task { await owner.stop() }
        while await owner.snapshot().isStopped == false { try Task.checkCancellation(); await Task.yield() }
        second.cancel()
        #expect(await original.didCompleteCleanup() == false)
        #expect(await harness.recorded().0.count == 1)
        gate.open()
        try await first.value
        try await second.value
        await stop.value
        #expect(await original.stopCount() == 1)
        #expect(await harness.recorded().0.count == 2)
        #expect(await owner.snapshot().retainedGuildCount == 0)
    }

    /// Concurrent leaves share a held sender's exact result while stop suppresses its error.
    /// - Parameter rejectLeave: Whether the once-only leave fails after its sender gate opens.
    /// The actor-isolated second caller is admitted before stop begins, so both leave tasks
    /// must observe the same sender result and stop must await it without a duplicate write.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func concurrentLeavesAndStopShareBlockedSender(rejectLeave: Bool) async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(leaveGate: gate, failLeave: rejectLeave)
        let owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        _ = try await join.value
        let first = Task { try await owner.leave(guildID: GuildID(rawValue: 1)) }
        try await harness.waitForCommand(2)
        let entered = TestBarrier()
        let second = Task { try await concurrentLeave(owner, entered: entered) }
        try await entered.wait()
        let stop = Task { await owner.stop() }
        while await owner.snapshot().isStopped == false { try Task.checkCancellation(); await Task.yield() }
        #expect(await owner.snapshot().closingGuildCount == 1)
        #expect(await harness.recorded().0.count == 2)
        gate.open()
        if rejectLeave {
            await #expect(throws: VoiceManagerFailure.invalidConfiguration) { try await first.value }
            await #expect(throws: VoiceManagerFailure.invalidConfiguration) { try await second.value }
        } else {
            try await first.value; try await second.value
        }
        await stop.value
        #expect(await harness.recorded().0.count == 2)
        #expect(await owner.snapshot().retainedGuildCount == 0)
        #expect(await harness.session(0).didCompleteCleanup())
    }

    /// Global stop retains a replacement's old teardown and prevents any later join request.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func stopDuringReplacementTeardown() async throws {
        let gate = TestBarrier(), harness = VoiceManagerHarness(stopGate: gate), owner = try manager(harness)
        let join = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        try await harness.waitForCommand(1)
        _ = try await complete(owner)
        _ = try await join.value
        let original = await harness.session(0)
        try await original.started.wait()
        let move = Task { try await owner.move(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 4)) }
        try await original.stopEntered.wait()
        #expect(await original.didCompleteCleanup() == false)
        let stop = Task { await owner.stop() }
        for _ in 0..<10_000 {
            if await owner.snapshot().isStopped { break }
            await Task.yield()
        }
        #expect(await owner.snapshot().isStopped)
        gate.open()
        await stop.value
        await #expect(throws: VoiceManagerFailure.closed) { try await move.value }
        #expect(await original.didCompleteCleanup())
        #expect(await harness.recorded().0.count == 2)
        #expect(await harness.recorded().1.count == 1)
        #expect(await owner.snapshot().retainedGuildCount == 0)
    }

    /// Global stop fails all pending joins and prevents cross-guild retention or restart.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func stopCancelsPendingJoinsAcrossGuilds() async throws {
        let harness = VoiceManagerHarness(), clock = ManualClock(), owner = try manager(harness, clock: clock)
        let first = Task { try await owner.join(guildID: GuildID(rawValue: 1), channelID: ChannelID(rawValue: 3)) }
        let second = Task { try await owner.join(guildID: GuildID(rawValue: 4), channelID: ChannelID(rawValue: 5)) }
        try await harness.waitForCommand(2)
        await owner.stop()
        await #expect(throws: VoiceManagerFailure.closed) { try await first.value }
        await #expect(throws: VoiceManagerFailure.closed) { try await second.value }
        let snapshot = await owner.snapshot()
        #expect(snapshot.isStopped && snapshot.retainedGuildCount == 0 && snapshot.runningSessionCount == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(await harness.recorded().0.count == 4)
    }
}
