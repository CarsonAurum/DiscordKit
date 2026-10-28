// File: Sources/DiscordVoice/VoiceManager.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// A supervised session whose complete lifetime belongs to a voice manager.
/// Implementations start no work until `run()` and must make `stop()` unblock it.
public protocol VoiceManagedSession: Sendable {
    /// Runs the session until cancellation, explicit stop, or a terminal failure.
    /// - Throws: Sanitized implementation-specific connection or media failures.
    ///   Only one invocation may be active; returning means owned children have exited.
    func run() async throws

    /// Stops network/media work idempotently and waits for resource cleanup.
    /// Cancellation of the caller must not prevent cleanup or leave `run()` suspended.
    func stop() async
}

/// One explicit main-Gateway opcode-4 request, without a dependency on its client owner.
/// The injected sender applies shared Gateway rate admission and never retries an
/// ambiguous write. Permissions and `GUILD_VOICE_STATES` intent remain caller responsibilities.
public struct VoiceManagerCommand: Sendable, Equatable {
    public let guildID: GuildID
    public let channelID: ChannelID?
    public let selfMute: Bool
    public let selfDeaf: Bool

    /// Describes a join, move, or leave without sending it.
    /// - Parameters:
    ///   - guildID: Guild whose account voice state changes.
    ///   - channelID: Requested channel; nil leaves the guild's voice channel.
    ///   - selfMute: Explicit outbound mute state, default false.
    ///   - selfDeaf: Explicit inbound deafen state, default false.
    public init(guildID: GuildID, channelID: ChannelID?, selfMute: Bool = false, selfDeaf: Bool = false) {
        self.guildID = guildID; self.channelID = channelID
        self.selfMute = selfMute; self.selfDeaf = selfDeaf
    }
}

/// Sanitized manager admission/lifetime failures; no credentials or endpoints are retained.
public enum VoiceManagerFailure: Error, Sendable, Equatable {
    case invalidConfiguration, capacityExceeded, operationInProgress, staleGeneration
    case superseded, disconnected, closed
}

/// Bounded diagnostics for all guild sessions owned by one account.
public struct VoiceManagerSnapshot: Sendable, Equatable {
    public let retainedGuildCount: Int
    public let runningSessionCount: Int
    public let pendingJoinCount: Int
    public let closingGuildCount: Int
    /// Retained teardown/factory tasks, conservatively including each current task's chain.
    public let retainedOperationCount: Int
    public let completedSessionCount: UInt64
    public let failedSessionCount: UInt64
    public let isStopped: Bool
}

/// Owns a bounded set of per-guild sessions and two-event main-Gateway rendezvous.
///
/// Construction starts no I/O or tasks. `join` sends one explicit request, waits for
/// both events in either order under an injected-clock deadline, then starts one owned
/// session task. A move replaces credentials even when Discord repeats the endpoint.
/// Route events with the fence captured from `generation(guildID:)`; Discord supplies
/// no nonce, so an owner-unknown delayed event cannot be distinguished from a fresh one.
/// Normally serialize main-Gateway event routing. Concurrent automatic replacements retain
/// at most four teardown/factory tasks per guild; further overlap closes that guild's slot.
/// User callbacks must cooperate with cancellation and must never log credentials.
public actor VoiceManager<C: Clock> where C.Duration == Duration {
    /// Shared main-Gateway command authority supplied by the application.
    public typealias SendCommand = @Sendable (VoiceManagerCommand) async throws -> Void
    /// Creates an inert session with fresh DAVE, transport, and resource ownership.
    public typealias MakeSession = @Sendable (VoiceConnectionCredentials) async throws -> any VoiceManagedSession

    /// Gives each owned task a reference identity independent of its routing/credential fences.
    private final class Operation: Sendable {
        let task: Task<(any VoiceManagedSession)?, any Error>
        let depth: Int

        /// Retains one replacement or teardown task so reentrant completion clears only itself.
        /// - Parameters:
        ///   - task: Already created task whose entire lifetime belongs to one guild.
        ///   - depth: One plus the preceding retained operation's depth, bounded through four.
        init(_ task: Task<(any VoiceManagedSession)?, any Error>, depth: Int) {
            self.task = task; self.depth = depth
        }
    }

    private struct Entry {
        let generation: UInt64
        var rendezvous: VoiceJoinRendezvous
        var credentials: VoiceConnectionCredentials?
        var waiter: CheckedContinuation<VoiceConnectionCredentials, any Error>?
        var session: (any VoiceManagedSession)?
        var task: Task<Void, Never>?
        var operation: Operation?
        var closeTask: Task<Void, any Error>?
        var joining = true
        var installing = false
        var closing = false
    }
    private let userID: UserID
    private let clock: C
    private let maximumGuilds: Int
    private let maximumCredentialFieldBytes: Int
    private let maximumOperationDepth = 4
    private let sendCommand: SendCommand
    private let makeSession: MakeSession
    private var entries: [GuildID: Entry] = [:]
    private var nextGeneration: UInt64 = 0
    private var completedSessions: UInt64 = 0
    private var failedSessions: UInt64 = 0
    private var stopped = false
    private var shutdownTask: Task<Void, Never>?

    /// Creates an inert account-scoped manager with finite aggregate guild retention.
    /// - Parameters:
    ///   - userID: Authenticated joining account, matched against every self-state event.
    ///   - clock: Monotonic clock defining complete join deadlines.
    ///   - maximumGuilds: Maximum pending, running, or closing guild slots, 1...65,536.
    ///   - maximumCredentialFieldBytes: Per-token/session/endpoint UTF-8 bound, 1...65,536.
    ///   - sendCommand: Cancellation-cooperative, once-only main-Gateway opcode-4 sender.
    ///   - makeSession: Cancellation-cooperative factory; must return a new inert owner
    ///     for every credential replacement and must not reuse encryption counters.
    /// - Throws: `invalidConfiguration` for an invalid capacity; no callback is invoked.
    public init(userID: UserID, clock: C, maximumGuilds: Int = 256,
                maximumCredentialFieldBytes: Int = 4_096,
                sendCommand: @escaping SendCommand, makeSession: @escaping MakeSession) throws {
        guard (1...65_536).contains(maximumGuilds), (1...65_536).contains(maximumCredentialFieldBytes) else {
            throw VoiceManagerFailure.invalidConfiguration
        }
        self.userID = userID; self.clock = clock; self.maximumGuilds = maximumGuilds
        self.maximumCredentialFieldBytes = maximumCredentialFieldBytes
        self.sendCommand = sendCommand; self.makeSession = makeSession
    }

    /// Sends one join/move request and starts a session after both matching events arrive.
    /// - Parameters:
    ///   - guildID: Target guild; existing completed sessions are stopped before replacement.
    ///   - channelID: Target channel, including the same channel for an explicit fresh join.
    ///   - selfMute: Explicit initial mute state, default false.
    ///   - selfDeaf: Explicit initial deafen state, default false.
    ///   - timeout: Positive total send/rendezvous/factory deadline through one day, default 15s.
    /// - Returns: The session now owned by this manager; callers may use its richer concrete API
    ///   but must not invoke `run()` themselves. Return does not promise network/DAVE readiness.
    /// - Throws: Cancellation, deadline, capacity, stopped/overlap errors, or injected callback
    ///   errors. Failed joins close created resources and make one best-effort leave request.
    ///   Concurrent joins for one pending/closing guild are rejected without sending a request.
    public func join(guildID: GuildID, channelID: ChannelID, selfMute: Bool = false,
                     selfDeaf: Bool = false, timeout: Duration = .seconds(15)) async throws -> any VoiceManagedSession {
        try Task.checkCancellation()
        guard !stopped else { throw VoiceManagerFailure.closed }
        guard timeout > .zero, timeout <= .seconds(86_400) else { throw VoiceManagerFailure.invalidConfiguration }
        if let entry = entries[guildID], entry.joining || entry.closing || entry.installing || entry.operation != nil {
            throw VoiceManagerFailure.operationInProgress
        }
        guard entries[guildID] != nil || entries.count < maximumGuilds else { throw VoiceManagerFailure.capacityExceeded }
        let logger = DiscordLog.makeLogger("voice.manager")
        logger.trace("Voice join admitted", metadata: ["dk.event": "voice.manager.join.started",
            "dk.retained_guilds": .stringConvertible(entries.count)])
        let generation = try reserveGeneration()
        let old = entries[guildID]
        let rendezvous = try VoiceJoinRendezvous(guildID: guildID, userID: userID, channelID: channelID,
            maximumCredentialFieldBytes: maximumCredentialFieldBytes)
        entries[guildID] = Entry(generation: generation, rendezvous: rendezvous)
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: timeout))
        let operation = Operation(Task<(any VoiceManagedSession)?, any Error> { [self] in
            logger.trace("Voice prior session cleanup starting", metadata: ["dk.event": "voice.manager.join.previous_cleanup"])
            await terminate(old)
            try Task.checkCancellation()
            return try await context.run { [self] in
                try await sendJoin(guildID: guildID, channelID: channelID, selfMute: selfMute,
                    selfDeaf: selfDeaf, generation: generation)
                logger.trace("Voice credential rendezvous waiting", metadata: ["dk.event": "voice.manager.join.credentials.waiting"])
                let credentials = try await waitForCredentials(guildID: guildID, generation: generation)
                logger.trace("Voice credential rendezvous completed", metadata: ["dk.event": "voice.manager.join.credentials.completed"])
                return try await install(credentials, guildID: guildID, generation: generation)
            }
        }, depth: 1)
        entries[guildID]?.operation = operation
        do {
            guard let session = try await waitForOperation(operation) else { throw VoiceManagerFailure.superseded }
            try Task.checkCancellation()
            guard entries[guildID]?.generation == generation, entries[guildID]?.closing == false, !stopped else {
                throw VoiceManagerFailure.superseded
            }
            entries[guildID]?.joining = false; entries[guildID]?.operation = nil
            logger.info("Voice join session installed", metadata: ["dk.event": "voice.manager.join.completed"])
            return session
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Voice join cancelled", metadata: ["dk.event": "voice.manager.join.cancelled"])
            } else {
                logger.debug("Voice join failed", metadata: ["dk.event": "voice.manager.join.failed"])
            }
            let externallyClosed = entries[guildID]?.generation != generation || entries[guildID]?.closing == true
            await discard(guildID: guildID, generation: generation, sendLeave: true)
            if stopped { throw VoiceManagerFailure.closed }
            if externallyClosed, !Task.isCancelled { throw VoiceManagerFailure.disconnected }
            throw error
        }
    }

    /// Replaces one guild's session using the same bounded fresh-credential join path.
    /// - Parameters:
    ///   - guildID: Guild whose previous completed session should be stopped.
    ///   - channelID: New channel; repeated endpoints still require two new event halves.
    ///   - selfMute: Explicit replacement mute state, default false.
    ///   - selfDeaf: Explicit replacement deafen state, default false.
    ///   - timeout: Positive total deadline through one day, default 15s.
    /// - Returns: Newly owned session; readiness remains the session's responsibility.
    /// - Throws: The same validation, cancellation, deadline, and callback errors as `join`.
    public func move(guildID: GuildID, channelID: ChannelID, selfMute: Bool = false,
                     selfDeaf: Bool = false, timeout: Duration = .seconds(15)) async throws -> any VoiceManagedSession {
        try await join(guildID: guildID, channelID: channelID, selfMute: selfMute, selfDeaf: selfDeaf, timeout: timeout)
    }

    /// Returns the current event-routing fence without revealing credentials.
    /// - Parameter guildID: Guild whose pending/running join receives main-Gateway events.
    /// - Returns: Local generation, or nil when no slot is retained. Capture this before routing;
    ///   never substitute a previously cached fence after an explicit join/move/leave.
    public func generation(guildID: GuildID) -> UInt64? { entries[guildID]?.generation }

    /// Routes one typed main-Gateway self-state event to its current bounded rendezvous.
    /// - Parameters:
    ///   - state: Immutable VOICE_STATE_UPDATE; unguilded and unrelated members are ignored.
    ///   - generation: Owner-captured local event fence, checked before inspecting credentials.
    /// - Throws: Stale-generation, rendezvous validation, or replacement-factory failures.
    ///   Self leave/unsolicited move stops the old session. Changed session IDs stop old
    ///   ownership immediately and require a fresh server half before replacement.
    ///   Serialize normal routing; a fifth retained teardown/factory task for this guild
    ///   fails closed with `capacityExceeded` after joining cleanup and issuing one leave.
    public func route(state: VoiceState, generation: UInt64) async throws {
        guard case .value(let guildID) = state.guildID, state.userID == userID else { return }
        try validate(guildID: guildID, generation: generation)
        let oldCredentials = entries[guildID]?.credentials
        let credentials = try entries[guildID]!.rendezvous.receive(state: state, generation: 0)
        if entries[guildID]!.rendezvous.isInvalidated {
            await discard(guildID: guildID, generation: generation, sendLeave: false)
            return
        }
        if let oldCredentials, oldCredentials.sessionID != state.sessionID {
            try await suspend(guildID: guildID, generation: generation)
        }
        if let credentials { try await admit(credentials, guildID: guildID, generation: generation) }
    }

    /// Routes one typed main-Gateway server event, invalidating obsolete active credentials.
    /// - Parameters:
    ///   - server: VOICE_SERVER_UPDATE from the authenticated main-Gateway dispatcher.
    ///   - generation: Owner-captured event fence; unrelated absent guild slots are rejected.
    /// - Throws: Stale-generation, malformed credentials, or replacement-factory failures.
    ///   A null endpoint suspends the old session and requires both fresh event halves;
    ///   changed tokens/endpoints never keep an old session alive while waiting.
    ///   Serialize normal routing; a fifth retained teardown/factory task for this guild
    ///   fails closed with `capacityExceeded` after joining cleanup and issuing one leave.
    public func route(server: GatewayVoiceServerUpdate, generation: UInt64) async throws {
        let guildID = server.guildID
        try validate(guildID: guildID, generation: generation)
        let oldCredentials = entries[guildID]?.credentials
        let credentials = try entries[guildID]!.rendezvous.receive(server: server, generation: 0)
        if let oldCredentials, server.endpoint != .value(oldCredentials.endpoint) || server.token != oldCredentials.token {
            try await suspend(guildID: guildID, generation: generation)
        }
        if let credentials { try await admit(credentials, guildID: guildID, generation: generation) }
    }

    /// Stops a guild's pending/running session and sends one explicit main-Gateway leave.
    /// - Parameter guildID: Guild to leave; absent slots are an idempotent no-op.
    /// - Throws: Only the injected leave-command error, after local cleanup has completed.
    ///   Joining/closing admission stays fenced until this command finishes. Pending joins
    ///   fail with `disconnected`; cancellation cannot skip local session cleanup. Concurrent
    ///   callers await the same physical cleanup and once-only sender result.
    public func leave(guildID: GuildID) async throws {
        guard let entry = entries[guildID],
              let task = beginClose(guildID: guildID, generation: entry.generation,
                  sendLeave: true, waiterFailure: .disconnected) else { return }
        try await task.value
        DiscordLog.makeLogger("voice.manager").info("Voice leave completed", metadata: ["dk.event": "voice.manager.leave.completed"])
    }

    /// Permanently stops all sessions, beginning one best-effort leave for each open guild.
    /// This method is idempotent, rejects new joins before suspension, waits for all owned
    /// run tasks, and suppresses leave errors after local cleanup. An already-closing guild
    /// shares its existing cleanup/sender task without issuing another leave request.
    public func stop() async {
        if let shutdownTask { await shutdownTask.value; return }
        guard !stopped else { return }
        DiscordLog.makeLogger("voice.manager").info("Voice manager stopping", metadata: ["dk.event": "voice.manager.stopping",
            "dk.retained_guilds": .stringConvertible(entries.count)])
        stopped = true
        let retained = entries
        var tasks: [Task<Void, any Error>] = []
        for (guildID, entry) in retained {
            if let task = beginClose(guildID: guildID, generation: entry.generation,
                                    sendLeave: true, waiterFailure: .closed) { tasks.append(task) }
        }
        let closes = tasks
        let task = Task { [self] in await finishStop(closes) }
        shutdownTask = task
        await task.value
        shutdownTask = nil
    }

    /// Completes one shared global-stop task so overlapping callers await the same cleanup.
    /// - Parameter tasks: Fixed bounded per-guild close tasks reserved before global suspension.
    ///   All waiters have been resolved and all entries marked closing before this task starts.
    private func finishStop(_ tasks: [Task<Void, any Error>]) async {
        for task in tasks { _ = await task.result }
        DiscordLog.makeLogger("voice.manager").trace("Voice manager child cleanup joined", metadata: ["dk.event": "voice.manager.cleanup.joined",
            "dk.children": .stringConvertible(tasks.count)])
    }

    /// Returns finite aggregate diagnostics without traversing sessions or credentials.
    /// - Returns: Current retained/running/pending counts and saturating lifetime counters.
    public func snapshot() -> VoiceManagerSnapshot {
        VoiceManagerSnapshot(retainedGuildCount: entries.count,
            runningSessionCount: entries.values.filter { $0.session != nil && !$0.closing }.count,
            pendingJoinCount: entries.values.filter { $0.joining && !$0.closing }.count,
            closingGuildCount: entries.values.filter(\.closing).count,
            retainedOperationCount: entries.values.reduce(0) { $0 + ($1.operation?.depth ?? 0) },
            completedSessionCount: completedSessions, failedSessionCount: failedSessions, isStopped: stopped)
    }

    /// Allocates a globally unique local fence without retaining historical guild metadata.
    /// - Returns: A strictly positive generation shared by join and connection allocation.
    /// - Throws: `invalidConfiguration` at UInt64 exhaustion, without wrapping identities.
    private func reserveGeneration() throws -> UInt64 {
        guard nextGeneration < UInt64.max else { throw VoiceManagerFailure.invalidConfiguration }
        nextGeneration += 1
        return nextGeneration
    }

    /// Checks live slot identity before any route/install mutation or callback.
    /// - Parameters:
    ///   - guildID: Scoped retained guild.
    ///   - generation: Expected routing generation.
    /// - Throws: `closed` after global stop, `staleGeneration` for absent/replaced/closing slots.
    private func validate(guildID: GuildID, generation: UInt64) throws {
        guard !stopped else { throw VoiceManagerFailure.closed }
        guard let entry = entries[guildID], entry.generation == generation, !entry.closing else {
            throw VoiceManagerFailure.staleGeneration
        }
    }

    /// Performs the single admitted main-Gateway join request after checking its fence.
    /// - Parameters:
    ///   - guildID: Retained guild.
    ///   - channelID: Explicit target channel.
    ///   - selfMute: Requested mute state.
    ///   - selfDeaf: Requested deafen state.
    ///   - generation: Current pending join generation.
    /// - Throws: Cancellation, stale generation, or the sender's once-only write error.
    private func sendJoin(guildID: GuildID, channelID: ChannelID, selfMute: Bool, selfDeaf: Bool,
                          generation: UInt64) async throws {
        try Task.checkCancellation(); try validate(guildID: guildID, generation: generation)
        try await sendCommand(VoiceManagerCommand(guildID: guildID, channelID: channelID,
            selfMute: selfMute, selfDeaf: selfDeaf))
    }

    /// Suspends one joining caller until the bounded pair is complete or it is cancelled.
    /// - Parameters:
    ///   - guildID: Current pending guild.
    ///   - generation: Expected routing generation.
    /// - Returns: Credentials retained from early routing or delivered by the next matching half.
    /// - Throws: Cancellation, stale generation, or explicit leave/stop errors. Exactly one
    ///   continuation is retained; cancellation resumes it so structured deadlines can finish.
    private func waitForCredentials(guildID: GuildID, generation: UInt64) async throws -> VoiceConnectionCredentials {
        try Task.checkCancellation(); try validate(guildID: guildID, generation: generation)
        if let credentials = entries[guildID]?.credentials { return credentials }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                entries[guildID]?.waiter = continuation
            }
        } onCancel: {
            Task { await self.cancelWait(guildID: guildID, generation: generation) }
        }
    }

    /// Resolves cancellation only for the waiter belonging to the captured join.
    /// - Parameters:
    ///   - guildID: Cancelled pending guild.
    ///   - generation: Captured routing fence, preventing cancellation of a replacement.
    private func cancelWait(guildID: GuildID, generation: UInt64) {
        guard entries[guildID]?.generation == generation else { return }
        let waiter = entries[guildID]?.waiter; entries[guildID]?.waiter = nil
        waiter?.resume(throwing: CancellationError())
    }

    /// Awaits one retained replacement operation while forwarding the owning caller's cancellation.
    /// - Parameter operation: Unique bounded guild task; nil success represents completed teardown.
    /// - Returns: Newly installed session, or nil for teardown-only work.
    /// - Throws: Cancellation or the task's original sanitized factory/protocol failure.
    ///   Cancellation still awaits the task's cleanup before this helper returns.
    private func waitForOperation(_ operation: Operation) async throws
        -> (any VoiceManagedSession)? {
        try await withTaskCancellationHandler {
            try await operation.task.value
        } onCancel: {
            operation.task.cancel()
        }
    }

    /// Publishes a complete pair to a join waiter or replaces an established session.
    /// - Parameters:
    ///   - credentials: Complete rendezvous pair; receives a unique connection identity.
    ///   - guildID: Current retained guild.
    ///   - generation: Event-routing fence, independent of connection-key generations.
    /// - Throws: Cancellation, stale fence, generation exhaustion, or replacement-factory errors.
    ///   Active replacements retain their factory task before suspension and await any prior
    ///   teardown. Superseded operations cannot discard a newer credential pair in the same guild.
    private func admit(_ credentials: VoiceConnectionCredentials, guildID: GuildID, generation: UInt64) async throws {
        try validate(guildID: guildID, generation: generation)
        let connectionGeneration = try reserveGeneration()
        let current = VoiceConnectionCredentials(guildID: credentials.guildID, userID: credentials.userID,
            channelID: credentials.channelID, sessionID: credentials.sessionID, token: credentials.token,
            endpoint: credentials.endpoint, generation: connectionGeneration)
        entries[guildID]?.credentials = current
        let waiter = entries[guildID]?.waiter; entries[guildID]?.waiter = nil
        if let waiter { waiter.resume(returning: current) }
        else if entries[guildID]?.joining == false {
            let previous = entries[guildID]?.operation
            guard (previous?.depth ?? 0) < maximumOperationDepth else {
                await discard(guildID: guildID, generation: generation, sendLeave: true)
                throw VoiceManagerFailure.capacityExceeded
            }
            let operation = Operation(Task<(any VoiceManagedSession)?, any Error> { [self] in
                if let previous { _ = try await waitForOperation(previous) }
                try Task.checkCancellation()
                return try await install(current, guildID: guildID, generation: generation)
            }, depth: (previous?.depth ?? 0) + 1)
            entries[guildID]?.operation = operation
            do {
                _ = try await waitForOperation(operation)
                try Task.checkCancellation(); try validate(guildID: guildID, generation: generation)
                guard entries[guildID]?.credentials == current,
                      entries[guildID]?.operation === operation else { throw VoiceManagerFailure.superseded }
                entries[guildID]?.operation = nil
            }
            catch {
                if entries[guildID]?.generation == generation, entries[guildID]?.credentials == current {
                    await discard(guildID: guildID, generation: generation, sendLeave: true)
                }
                throw error
            }
        }
    }

    /// Creates and starts one inert session after validating the exact current pair.
    /// - Parameters:
    ///   - credentials: Unique connection-generation pair to install.
    ///   - guildID: Retained guild.
    ///   - generation: Current routing fence.
    /// - Returns: Session with one manager-owned run task.
    /// - Throws: Cancellation, overlap, stale generation, or factory errors. A factory
    ///   result superseded while awaiting is stopped before this method throws.
    private func install(_ credentials: VoiceConnectionCredentials, guildID: GuildID,
                         generation: UInt64) async throws -> any VoiceManagedSession {
        try Task.checkCancellation(); try validate(guildID: guildID, generation: generation)
        guard entries[guildID]?.installing == false else { throw VoiceManagerFailure.operationInProgress }
        entries[guildID]?.installing = true
        let session: any VoiceManagedSession
        do { session = try await makeSession(credentials) }
        catch { if entries[guildID]?.generation == generation { entries[guildID]?.installing = false }; throw error }
        guard !Task.isCancelled, !stopped, entries[guildID]?.generation == generation,
              entries[guildID]?.credentials == credentials, entries[guildID]?.closing == false else {
            await session.stop()
            if entries[guildID]?.generation == generation { entries[guildID]?.installing = false }
            if Task.isCancelled { throw CancellationError() }
            throw VoiceManagerFailure.superseded
        }
        entries[guildID]?.installing = false
        entries[guildID]?.session = session
        entries[guildID]?.task = Task { [self] in
            var failed = false
            do { try await session.run() } catch is CancellationError {} catch { failed = true }
            await session.stop()
            sessionFinished(guildID: guildID, generation: generation,
                connectionGeneration: credentials.generation, failed: failed)
        }
        return session
    }

    /// Retires only the completed task's exact credential generation and finite counters.
    /// - Parameters:
    ///   - guildID: Owning guild.
    ///   - generation: Routing generation captured when the task started.
    ///   - connectionGeneration: Unique credential identity, fencing server replacement.
    ///   - failed: Whether run threw a terminal error other than cooperative cancellation.
    private func sessionFinished(guildID: GuildID, generation: UInt64, connectionGeneration: UInt64, failed: Bool) {
        if completedSessions < UInt64.max { completedSessions += 1 }
        if failed, failedSessions < UInt64.max { failedSessions += 1 }
        guard entries[guildID]?.generation == generation,
              entries[guildID]?.credentials?.generation == connectionGeneration,
              entries[guildID]?.closing == false else { return }
        DiscordLog.makeLogger("voice.manager").debug("Managed voice session finished", metadata: ["dk.event": "voice.manager.session.finished",
            "dk.failed": .stringConvertible(failed)])
        entries[guildID]?.session = nil; entries[guildID]?.task = nil
    }

    /// Stops old media immediately while retaining rendezvous halves for a fresh pair.
    /// - Parameters:
    ///   - guildID: Guild whose session/server half changed.
    ///   - generation: Current event-routing fence.
    /// Old resources move into one retained teardown task before suspension, so stop/leave
    /// and a newly completed credential pair must await their full physical cleanup.
    /// - Throws: `capacityExceeded` after fail-closed cleanup if another task would exceed
    ///   the four-operation per-guild bound; no fifth owned operation is created.
    private func suspend(guildID: GuildID, generation: UInt64) async throws {
        guard let entry = entries[guildID], entry.generation == generation else { return }
        guard (entry.operation?.depth ?? 0) < maximumOperationDepth else {
            await discard(guildID: guildID, generation: generation, sendLeave: true)
            throw VoiceManagerFailure.capacityExceeded
        }
        entries[guildID]?.credentials = nil; entries[guildID]?.session = nil; entries[guildID]?.task = nil
        let operation = Operation(Task<(any VoiceManagedSession)?, any Error> { [self] in
            await terminate(entry)
            return nil
        }, depth: (entry.operation?.depth ?? 0) + 1)
        entries[guildID]?.operation = operation
        _ = await operation.task.result
        if entries[guildID]?.generation == generation, entries[guildID]?.credentials == nil,
           entries[guildID]?.closing == false, entries[guildID]?.operation === operation {
            entries[guildID]?.operation = nil
        }
    }

    /// Releases a slot after failure/leave, retaining its closing fence until cleanup ends.
    /// - Parameters:
    ///   - guildID: Guild being discarded.
    ///   - generation: Fence preventing a failed old join from discarding a new one.
    ///   - sendLeave: Whether to make one cancellation-independent best-effort Gateway leave.
    private func discard(guildID: GuildID, generation: UInt64, sendLeave: Bool) async {
        guard let task = beginClose(guildID: guildID, generation: generation,
                                    sendLeave: sendLeave, waiterFailure: .disconnected) else { return }
        _ = await task.result
    }

    /// Reserves or shares one guild's complete cleanup and optional once-only leave request.
    /// - Parameters:
    ///   - guildID: Retained guild whose resources and sender lifetime must finish together.
    ///   - generation: Current routing fence; absent or replaced slots are ignored.
    ///   - sendLeave: Whether a newly reserved task sends a leave after local cleanup. Existing
    ///     close tasks keep their original policy, including server-directed departures.
    ///   - waiterFailure: Error resolving a pending join when this caller first reserves close.
    /// - Returns: Shared cancellation-independent throwing cleanup task, or nil for a stale slot.
    /// The pre-close snapshot excludes the newly created task, preventing a self-joining cycle.
    private func beginClose(guildID: GuildID, generation: UInt64, sendLeave: Bool,
                            waiterFailure: VoiceManagerFailure) -> Task<Void, any Error>? {
        guard let entry = entries[guildID], entry.generation == generation else { return nil }
        if let task = entry.closeTask { return task }
        entries[guildID]?.closing = true; entries[guildID]?.waiter = nil
        entry.waiter?.resume(throwing: waiterFailure)
        let task = Task<Void, any Error> { [self] in
            try await finishClose(entry, guildID: guildID, sendLeave: sendLeave)
        }
        entries[guildID]?.closeTask = task
        return task
    }

    /// Finishes one reserved guild cleanup and removes its fence after its sender completes.
    /// - Parameters:
    ///   - entry: Pre-close snapshot containing runtime/replacement work, never this close task.
    ///   - guildID: Guild receiving the optional once-only Gateway leave.
    ///   - sendLeave: Whether to invoke the injected sender after all local ownership exits.
    /// - Throws: Injected leave-command error after local cleanup; the slot is removed on failure
    ///   as well as success. Leave callers observe the error; stop/discard suppress that result.
    private func finishClose(_ entry: Entry, guildID: GuildID, sendLeave: Bool) async throws {
        await terminate(entry)
        do {
            if sendLeave { try await sendCommand(VoiceManagerCommand(guildID: guildID, channelID: nil)) }
        } catch {
            if entries[guildID]?.generation == entry.generation { entries.removeValue(forKey: guildID) }
            throw error
        }
        if entries[guildID]?.generation == entry.generation { entries.removeValue(forKey: guildID) }
    }

    /// Cancels and awaits one detached slot's complete runtime ownership without Gateway I/O.
    /// - Parameter entry: Previous slot snapshot, or nil for an initially empty guild.
    ///   Pending continuations are resolved by the caller before invoking this helper.
    private func terminate(_ entry: Entry?) async {
        guard let entry else { return }
        entry.operation?.task.cancel(); entry.task?.cancel()
        await entry.session?.stop()
        await entry.task?.value
        _ = await entry.operation?.task.result
    }
}
