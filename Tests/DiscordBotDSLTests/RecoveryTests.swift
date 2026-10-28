// File: Tests/DiscordBotDSLTests/RecoveryTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordClient
import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordHTTP
import DiscordInteractions
import DiscordLogging
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordBotDSL
@testable import DiscordGateway

/// Each case selects one distinct invocation boundary while preserving the same real supervised host.
private enum RecoveryMode: String, CaseIterable, Sendable {
    case handler, acknowledgedHandler, deferredHandler, initialRejected, initialIndeterminate
    case continuationAPI, continuationDecoding, continuationIndeterminate
    case acknowledgementDeadline, tokenExpired, staleCommand

    /// Expected operation boundary supplied before the original error reaches runtime supervision.
    var stage: BotFailureStage {
        switch self {
        case .handler, .acknowledgedHandler, .deferredHandler: .handler
        case .initialRejected, .initialIndeterminate, .acknowledgementDeadline: .acknowledgement
        case .continuationAPI, .continuationDecoding, .continuationIndeterminate, .tokenExpired: .continuation
        case .staleCommand: .interactions
        }
    }

    /// Fixed diagnostic evidence expected from this synthetic operation, without arbitrary dependency text.
    var category: BotFailureCategory {
        switch self {
        case .handler, .acknowledgedHandler, .deferredHandler: .unclassified
        case .initialRejected, .continuationAPI: .api
        case .initialIndeterminate, .continuationIndeterminate, .continuationDecoding: .mutationConnectionLostAfterSubmission
        case .acknowledgementDeadline: .interactionLifecycleDeadlineExceeded
        case .tokenExpired: .interactionLifecycleTokenExpired
        case .staleCommand: .gatewayInteractionUnmatchedCommand
        }
    }

    /// Initial HTTP requests expected before the succeeding command gets its own initial response.
    var failedInitialCount: Int {
        switch self {
        case .handler, .acknowledgementDeadline, .staleCommand: 0
        default: 1
        }
    }

    /// Continuation requests expected from the failing invocation; no automatic fallback is allowed.
    var failedContinuationCount: Int {
        switch self {
        case .continuationAPI, .continuationDecoding, .continuationIndeterminate: 1
        default: 0
        }
    }

    /// Responder ownership after failure; an unmatched command never executes an application handler.
    var responseState: InteractionResponseState? {
        switch self {
        case .handler, .initialRejected: .pending
        case .acknowledgedHandler: .acknowledged(.channelMessageWithSource)
        case .initialIndeterminate: .indeterminate
        case .acknowledgementDeadline, .tokenExpired: .expired
        case .staleCommand: nil
        default: .acknowledged(.deferredChannelMessageWithSource)
        }
    }
}

/// Arbitrary injected diagnostic content must never become a library diagnostic or log field.
private struct RecoverySecretError: Error, Sendable, CustomStringConvertible {
    let description = "RECOVERY_ARBITRARY_SECRET https://invalid.example/RECOVERY_URL_SECRET"
}

/// Small synchronized evidence storage separates safe observer values from application response ownership.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class RecoveryEvidence: @unchecked Sendable {
    let observed = TestBarrier(), succeeded = TestBarrier(), eventDelivered = TestBarrier()
    let entered = TestBarrier(), blocked = TestBarrier()
    private let lock = NSLock()
    private var diagnostics: [BotFailureDiagnostic] = []
    private var failureRuns = 0
    private var successRuns = 0
    private var responseState: InteractionResponseState?

    /// Retains at most four immutable diagnostics; the callback receives no interaction or original error.
    /// - Parameter diagnostic: Already sanitized closed library evidence.
    func observe(_ diagnostic: BotFailureDiagnostic) {
        lock.withLock { if diagnostics.count < 4 { diagnostics.append(diagnostic) } }
        observed.open()
    }

    /// Records exactly one execution of the explicitly failing handler.
    func failedHandlerEntered() { lock.withLock { failureRuns += 1 }; entered.open() }

    /// Captures only public response state after a failure; it does not retain an interaction or responder.
    /// - Parameter state: Fixed acknowledgement ownership enum.
    func capture(_ state: InteractionResponseState) { lock.withLock { responseState = state } }

    /// Records a successful next invocation before opening the cooperative assertion gate.
    func successfulHandlerFinished() { lock.withLock { successRuns += 1 }; succeeded.open() }

    /// Returns finite typed observations without rendering unknown errors.
    /// - Returns: Diagnostic values, execution counts and acknowledgement state.
    func snapshot() -> (diagnostics: [BotFailureDiagnostic], failures: Int, successes: Int,
                        state: InteractionResponseState?) {
        lock.withLock { (diagnostics, failureRuns, successRuns, responseState) }
    }
}

/// Uses a real client's private receipt boundary and one open synthetic socket, without live Discord.
@Suite("Recoverable Gateway invocations", .timeLimit(.minutes(1)))
struct RecoveryTests {
    /// Every selected failure is observed once, then the same runtime serves another command and event.
    /// HTTP submission counts prove uncertain mutations, rejected callbacks and failed response decoding
    /// are not replayed. Pending, deferred, indeterminate and expired ownership remain with the responder.
    /// - Parameter mode: Independently exercised handler, callback, continuation or stale-command failure.
    /// - Throws: Unexpected fixture, protocol, response or joined-shutdown failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: RecoveryMode.allCases)
    private func sameRuntimeSurvivesSingleInvocation(_ mode: RecoveryMode) async throws {
        let recorder = LogRecorder(maximumEntries: 2_048)
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let fixture = try RecoveryFixture(mode: mode)
            let runtime = try fixture.runtime()
            #expect(await fixture.botHTTP.executionCount == 0)
            #expect(await fixture.initialHTTP.executionCount == 0)
            #expect(await fixture.transport.connections == 0)
            #expect(fixture.evidence.snapshot().diagnostics.isEmpty)
            let owner = Task { try await runtime.run() }
            fixture.socket.release(0)
            try await fixture.evidence.observed.wait()
            let failed = fixture.evidence.snapshot()
            #expect(failed.diagnostics.count == 1)
            #expect(failed.diagnostics.first?.stage == mode.stage)
            #expect(failed.diagnostics.first?.category == mode.category)
            #expect(failed.failures == (mode == .staleCommand ? 0 : 1))
            #expect(failed.state == mode.responseState)
            #expect(await fixture.initialHTTP.executionCount == mode.failedInitialCount)
            #expect(await fixture.continuationHTTP.executionCount == mode.failedContinuationCount)
            #expect(await fixture.admission.snapshot().activeCount == 0)
            #expect(await runtime.phase == .running)
            #expect(await fixture.client.snapshot().ready)

            fixture.socket.release(1)
            try await fixture.evidence.succeeded.wait()
            fixture.socket.release(2)
            try await fixture.evidence.eventDelivered.wait()
            #expect(fixture.evidence.snapshot().successes == 1)
            #expect(fixture.evidence.snapshot().diagnostics.count == 1)
            #expect(await fixture.transport.connections == 1)
            #expect(await fixture.botHTTP.executionCount == 1)
            #expect(await fixture.initialHTTP.executionCount == mode.failedInitialCount + 1)
            #expect(await fixture.continuationHTTP.executionCount == mode.failedContinuationCount)
            #expect(await runtime.phase == .running)
            #expect(await fixture.client.snapshot().ready)
            if mode == .initialRejected || mode == .continuationAPI {
                #expect(failed.diagnostics.first?.httpStatus == 400)
                #expect(failed.diagnostics.first?.apiCode == 50035)
            }

            try await runtime.shutdown()
            try await owner.value
            try await runtime.shutdown()
            await fixture.expectEmpty()
            #expect(await fixture.socket.closes == 1)
        }
        let rendered = recorder.entries.map { "\($0.message) \($0.metadata)" }.joined(separator: "\n")
        for sentinel in ["RECOVERY_ARBITRARY_SECRET", "RECOVERY_URL_SECRET", "RECOVERY_TOKEN_SECRET",
                         "RECOVERY_BODY_SECRET", "RECOVERY_HEADER_SECRET", "RECOVERY_PAYLOAD_SECRET",
                         "RECOVERY_BOT_SECRET"] {
            #expect(!rendered.contains(sentinel))
        }
        #expect(recorder.entries.count < 2_048)
    }

    /// Recovery does not alter malformed-input, identity, provenance, preparation or queue continuity gates.
    /// - Parameter mode: One independently exercised terminal admission failure.
    /// - Throws: Unexpected fixture/setup errors or a missing terminal error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["application", "malformed", "malformedRoute", "untrusted", "preparation", "overflow", "cancellation",
                      "discordCancellation", "closedRateOwner", "lostRateAuthority", "invalidRateOwner",
                      "gatewayOwner", "eventContinuity", "clientOwner", "responseOwner", "shardAuthority",
                      "transportOwner", "invalidTransportOwner", "concurrentTransportOwner", "exhaustedTransportOwner"])
    func recoveryKeepsSecurityAndOwnerFailuresTerminal(_ mode: String) async throws {
        let fixture = try RecoveryFixture(mode: .handler, terminalMode: mode)
        try await fixture.adapter.prepare(client: fixture.client)
        if mode == "untrusted" {
            let original = try fixture.event()
            let replay = try GatewayEvent(shard: original.shard, name: original.name, sequence: 1, data: original.data)
            await #expect(throws: GatewayInteractionFailure.untrustedEvent) { try await fixture.adapter.receive(replay) }
            await fixture.adapter.cancel()
        } else if mode == "overflow" {
            for _ in 0..<4 { try await fixture.adapter.receive(fixture.event()) }
            await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) {
                try await fixture.adapter.receive(fixture.event())
            }
            await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) {
                try await fixture.adapter.run()
            }
        } else {
            try await fixture.adapter.receive(fixture.event(application: mode == "application" ? "8" : "9",
                malformed: mode == "malformed", malformedRoute: mode == "malformedRoute"))
            await #expect(throws: (any Error).self) { try await fixture.adapter.run() }
        }
        await fixture.adapter.cancel()
        await fixture.client.shutdown()
        #expect(fixture.evidence.snapshot().successes == 0)
        #expect(await fixture.initialHTTP.executionCount == 0)
        await fixture.expectEmpty()
    }

    /// A command already queued behind a suspended failing handler executes once after recovery,
    /// preserving complete-shard serialization and the original client connection.
    /// - Throws: Unexpected fixture, cooperative gate, command or joined cleanup failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nextQueuedInvocationExecutesAfterFailure() async throws {
        let fixture = try RecoveryFixture(mode: .handler, terminalMode: "queuedFailure")
        let runtime = try fixture.runtime(), owner = Task { try await runtime.run() }
        fixture.socket.release(0)
        try await fixture.evidence.entered.wait()
        fixture.socket.release(1)
        try await fixture.socket.secondQueued.wait()
        #expect(fixture.evidence.snapshot().successes == 0)
        #expect(await fixture.adapter.snapshot().activeHandlers == 1)
        fixture.evidence.blocked.open()
        try await fixture.evidence.observed.wait()
        try await fixture.evidence.succeeded.wait()
        fixture.socket.release(2)
        try await fixture.evidence.eventDelivered.wait()
        #expect(fixture.evidence.snapshot().failures == 1)
        #expect(fixture.evidence.snapshot().successes == 1)
        #expect(await fixture.transport.connections == 1)
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.continuationHTTP.executionCount == 0)
        #expect(await runtime.phase == .running)
        try await runtime.shutdown()
        try await owner.value
        await fixture.expectEmpty()
    }

    /// An active interaction remains owned until its cooperative cancellation finishes; both explicit
    /// stop and cancellation of the run owner join client, command, queue and subscription cleanup.
    /// - Parameter cancelOwner: Selects owner cancellation instead of the runtime's explicit shutdown API.
    /// - Throws: Unexpected fixture or cancellation/shutdown result.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func activeInvocationShutdownJoinsAllOwners(_ cancelOwner: Bool) async throws {
        let fixture = try RecoveryFixture(mode: .handler, terminalMode: "blocked")
        let runtime = try fixture.runtime(), owner = Task { try await runtime.run() }
        fixture.socket.release(0)
        try await fixture.evidence.entered.wait()
        #expect(await fixture.adapter.snapshot().activeHandlers == 1)
        if cancelOwner {
            owner.cancel()
            await #expect(throws: CancellationError.self) { try await owner.value }
            await #expect(throws: CancellationError.self) { try await runtime.shutdown() }
            await #expect(throws: CancellationError.self) { try await runtime.shutdown() }
        } else {
            try await runtime.shutdown()
            try await owner.value
            try await runtime.shutdown()
        }
        #expect(fixture.evidence.blocked.waitingCount == 0)
        #expect(fixture.evidence.snapshot().successes == 0)
        #expect(await fixture.initialHTTP.executionCount == 0)
        #expect(await fixture.socket.closes == 1)
        await fixture.expectEmpty()
    }

    /// A permanently closed shared response authority remains terminal at its original boundary,
    /// including when continuation mutation ownership conservatively transforms the public error.
    /// - Parameter continuation: Selects the ordinary continuation coordinator instead of initial admission.
    /// - Throws: Unexpected fixture, response ownership, stage classification or terminal error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func closedResponseAuthorityStaysTerminal(_ continuation: Bool) async throws {
        let fixture = try RecoveryFixture(mode: .continuationIndeterminate)
        if continuation { await fixture.continuationRates.close() }
        else { await fixture.initialRates.close() }
        try await fixture.adapter.prepare(client: fixture.client)
        try await fixture.adapter.receive(fixture.event())
        if continuation {
            await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
                try await fixture.adapter.run()
            }
        } else {
            await #expect(throws: RateLimitFailure.closed) { try await fixture.adapter.run() }
        }
        let observed = fixture.evidence.snapshot()
        #expect(observed.diagnostics.count == 1)
        #expect(observed.diagnostics.first?.category == .rateLimitClosed)
        #expect(observed.diagnostics.first?.stage == (continuation ? .continuation : .acknowledgement))
        #expect(observed.failures == 1)
        #expect(observed.successes == 0)
        #expect(await fixture.initialHTTP.executionCount == (continuation ? 1 : 0))
        #expect(await fixture.continuationHTTP.executionCount == 0)
        await fixture.client.shutdown()
        await fixture.expectEmpty()
    }

    /// A closed injected HTTP transport is observed before public mutation normalization, remains
    /// terminal, and never causes a second callback, continuation request or command execution.
    /// - Parameter continuation: Selects a failing continuation after confirmed deferral instead of initial delivery.
    /// - Throws: Unexpected fixture, diagnostic stage, original public uncertainty or joined cleanup result.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func closedResponseTransportStaysTerminal(_ continuation: Bool) async throws {
        let fixture = try RecoveryFixture(mode: .continuationIndeterminate,
            terminalMode: continuation ? "closedContinuationTransport" : "closedInitialTransport")
        try await fixture.adapter.prepare(client: fixture.client)
        try await fixture.adapter.receive(fixture.event())
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await fixture.adapter.run()
        }
        let observed = fixture.evidence.snapshot()
        #expect(observed.diagnostics.count == 1)
        #expect(observed.diagnostics.first?.category == .unclassified)
        #expect(observed.diagnostics.first?.stage == (continuation ? .continuation : .acknowledgement))
        #expect(observed.failures == 1)
        #expect(observed.successes == 0)
        #expect(observed.state == (continuation ? .acknowledged(.deferredChannelMessageWithSource) : .indeterminate))
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.continuationHTTP.executionCount == (continuation ? 1 : 0))
        await fixture.client.shutdown()
        await fixture.expectEmpty()
    }

    /// A secondary authority outage during failed-send or failed-body cleanup terminates the one
    /// connected runtime while preserving primary mutation uncertainty and its exact response stage.
    /// - Parameter index: Zero/one fail initial send/body; two/three fail continuation send/body.
    /// - Throws: Unexpected fixture, original public error, observer evidence or joined ownership result.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4)
    func secondaryResponseAuthorityFailureStaysTerminal(_ index: Int) async throws {
        let continuation = index >= 2, bodyFailure = index % 2 == 1
        let store = RecoverySecondaryFailureStore(failComplete: bodyFailure)
        let fixture = try RecoveryFixture(mode: continuation ? .continuationIndeterminate : .initialIndeterminate,
            terminalMode: bodyFailure ? (continuation ? "secondaryContinuationBody" : "secondaryInitialBody") : nil,
            secondaryStore: store, secondaryContinuation: continuation)
        let runtime = try fixture.runtime(), owner = Task { try await runtime.run() }
        fixture.socket.release(0)
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await owner.value
        }
        let observed = fixture.evidence.snapshot()
        #expect(observed.diagnostics.count == 1)
        #expect(observed.diagnostics.first?.category == .rateLimitCoordinatorUnavailable)
        #expect(observed.diagnostics.first?.stage == (continuation ? .continuation : .acknowledgement))
        #expect(observed.failures == 1)
        #expect(observed.successes == 0)
        #expect(observed.state == (continuation ? .acknowledged(.deferredChannelMessageWithSource) : .indeterminate))
        #expect(await runtime.phase == .failed)
        #expect(await fixture.transport.connections == 1)
        #expect(await fixture.socket.closes == 1)
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.continuationHTTP.executionCount == (continuation ? 1 : 0))
        #expect(await store.completions == (bodyFailure ? 1 : 0))
        #expect(await store.releases == (bodyFailure ? 0 : 1))
        let responseOwnership = await fixture.responseBodies.snapshot()
        #expect(responseOwnership.acquired == (bodyFailure ? 1 : 0))
        #expect(responseOwnership.live == 0)
        let authority = await store.snapshot()
        #expect(authority.activeCount == 0)
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await runtime.shutdown()
        }
        await fixture.expectEmpty()
    }
}

/// Finite real transport/service composition whose longer client leases isolate the fifteen-minute token gate.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct RecoveryFixture {
    let clock = ManualClock()
    let evidence = RecoveryEvidence()
    let responseBodies = ResourceCounter()
    let socket: RecoverySocket
    let transport: RecoveryTransport
    let botHTTP: ScriptedHTTPTransport
    let initialHTTP: ScriptedHTTPTransport
    let continuationHTTP: ScriptedHTTPTransport
    let initialRates: RateLimitCoordinator<ManualClock>
    let continuationRates: RateLimitCoordinator<ManualClock>
    let hub: GatewayEventHub
    let admission: InteractionAcknowledgementAdmission
    let handlerAuthority: GatewayHandlerAuthority
    let budget: ClientResourceBudget
    let leases: InProcessShardLeaseStore<ManualClock>
    let client: DiscordClient<ManualClock, InProcessShardLeaseStore<ManualClock>>
    let adapter: GatewayInteractionAdapter<ManualClock>

    /// Creates only inert bounded owners; the explicit runtime starts discovery and command execution.
    /// - Parameters:
    ///   - mode: Invocation failure to inject into the first command.
    ///   - terminalMode: Optional security/owner gate, used only by direct admission regression tests.
    ///   - secondaryStore: Optional authority that rejects release/completion after primary failure.
    ///   - secondaryContinuation: Whether the failing authority belongs to continuations, default initial.
    /// - Throws: Invalid fixture or production finite configuration.
    init(mode: RecoveryMode, terminalMode: String? = nil, secondaryStore: RecoverySecondaryFailureStore? = nil,
         secondaryContinuation: Bool = false) throws {
        let clock = self.clock, evidence = self.evidence, responseBodies = self.responseBodies
        socket = RecoverySocket(firstName: mode == .staleCommand ? "stale" : "failure")
        transport = RecoveryTransport(socket: socket)
        botHTTP = try ScriptedHTTPTransport(steps: [{ _ in
            try Self.response(#"{"url":"wss://gateway.discord.gg/?RECOVERY_URL_SECRET","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#)
        }])
        var initialSteps: [ScriptedHTTPTransport.Step] = []
        if mode.failedInitialCount > 0 {
            initialSteps.append { _ in
                if terminalMode == "closedInitialTransport" { throw TransportFailure.closed }
                if terminalMode == "secondaryInitialBody" {
                    let lease = await responseBodies.acquire()
                    return HTTPResponse(status: 204, body: try BodyStream(maximumChunkBytes: 64,
                        next: { throw DiscordError.transport(.disconnected) }, close: { await lease.release() }))
                }
                if mode == .initialIndeterminate { throw DiscordError.transport(.disconnected) }
                if mode == .initialRejected {
                    return try Self.response(#"{"code":50035,"message":"RECOVERY_BODY_SECRET"}"#, status: 400)
                }
                return try Self.response("", status: 204)
            }
        }
        initialSteps.append { _ in try Self.response("", status: 204) }
        initialHTTP = try ScriptedHTTPTransport(steps: initialSteps)
        continuationHTTP = try ScriptedHTTPTransport(steps: mode.failedContinuationCount == 0 ? [] : [{ _ in
            if terminalMode == "closedContinuationTransport" { throw TransportFailure.closed }
            if terminalMode == "secondaryContinuationBody" {
                let lease = await responseBodies.acquire()
                return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 64,
                    next: { throw DiscordError.transport(.disconnected) }, close: { await lease.release() }))
            }
            if mode == .continuationIndeterminate { throw DiscordError.transport(.disconnected) }
            if mode == .continuationAPI {
                return try Self.response(#"{"code":50035,"message":"RECOVERY_BODY_SECRET"}"#, status: 400)
            }
            return try Self.response(#"{"RECOVERY_BODY_SECRET":true}"#)
        }])
        hub = GatewayEventHub(configuration: try .init())
        admission = try InteractionAcknowledgementAdmission()
        handlerAuthority = try GatewayHandlerAuthority(maximumActiveHandlers: 2, maximumWaitingHandlers: 2)
        budget = try ClientResourceBudget()
        leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 1)
        let bot = RESTClient(credential: .bot(try BotToken("RECOVERY_BOT_SECRET")), identity: RateLimitIdentity(),
            transport: botHTTP, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let failedIdentity = RateLimitIdentity(), successIdentity = RateLimitIdentity()
        let responseIdentity: @Sendable (Interaction) -> RateLimitIdentity = {
            $0.id.rawValue == 3 ? successIdentity : failedIdentity
        }
        let initialHTTP = self.initialHTTP, continuationHTTP = self.continuationHTTP
        initialRates = RateLimitCoordinator(clock: clock, store: secondaryContinuation ? nil : secondaryStore)
        continuationRates = RateLimitCoordinator(clock: clock, store: secondaryContinuation ? secondaryStore : nil)
        let initialRates = self.initialRates, continuationRates = self.continuationRates
        let services = BotServiceAdapter(services: ServiceContext(rest: bot), clock: clock,
            initialClient: { interaction in
                RESTClient(credential: .interaction(interaction.token), identity: responseIdentity(interaction), transport: initialHTTP,
                    coordinator: initialRates, clock: clock, retryPolicy: .init(maximumAttempts: 1))
            }, continuationServices: { interaction in
                ServiceContext(rest: RESTClient(credential: .interaction(interaction.token), identity: responseIdentity(interaction),
                    transport: continuationHTTP, coordinator: continuationRates, clock: clock,
                    retryPolicy: .init(maximumAttempts: 1)))
            })
        client = DiscordClient(token: try BotToken("RECOVERY_BOT_SECRET"),
            configuration: try ClientConfiguration(intents: [],
                shard: .init(maximumReconnectAttempts: 0, leaseLifetime: .seconds(3_600))),
            services: ServiceContext(rest: bot), transport: transport, clock: clock, leases: leases,
            authority: try ClientAuthority(botID: .init(rawValue: 42), clock: clock, budget: budget), events: hub)
        let failed = try CommandRoute(key: .command(name: "failure"), prepare: { context in
            if terminalMode == "preparation" { throw DiscordError.validation(.invalidValue) }
            return {
                evidence.failedHandlerEntered()
                do {
                    if terminalMode == "cancellation" { throw CancellationError() }
                    if terminalMode == "discordCancellation" { throw DiscordError.cancelled }
                    if terminalMode == "closedRateOwner" { throw RateLimitFailure.closed }
                    if terminalMode == "lostRateAuthority" { throw RateLimitFailure.coordinatorUnavailable }
                    if terminalMode == "invalidRateOwner" { throw RateLimitFailure.unknownReservation }
                    if terminalMode == "gatewayOwner" { throw GatewayFailure.staleGeneration }
                    if terminalMode == "eventContinuity" { throw GatewayEventDeliveryFailure.resynchronizationRequired }
                    if terminalMode == "clientOwner" { throw ClientFailure.alreadyRunning }
                    if terminalMode == "responseOwner" { throw InteractionLifecycleError.contextMismatch }
                    if terminalMode == "shardAuthority" { throw ShardOwnershipFailure.coordinatorUnavailable }
                    if terminalMode == "transportOwner" { throw TransportFailure.closed }
                    if terminalMode == "invalidTransportOwner" { throw TransportFailure.invalidLimit }
                    if terminalMode == "concurrentTransportOwner" { throw TransportFailure.concurrentRead }
                    if terminalMode == "exhaustedTransportOwner" { throw TransportFailure.scriptExhausted }
                    if terminalMode == "blocked" || terminalMode == "queuedFailure" { try await evidence.blocked.wait() }
                    switch mode {
                    case .handler, .staleCommand: throw RecoverySecretError()
                    case .acknowledgedHandler:
                        try await context.responder.reply(InteractionMessageCreate(content: .value("completed")))
                        throw RecoverySecretError()
                    case .deferredHandler:
                        try await context.responder.deferResponse()
                        throw RecoverySecretError()
                    case .initialRejected, .initialIndeterminate:
                        try await context.responder.reply(InteractionMessageCreate(content: .value("RECOVERY_PAYLOAD_SECRET")))
                    case .continuationAPI, .continuationDecoding, .continuationIndeterminate:
                        try await context.responder.deferResponse()
                        _ = try await context.responder.editOriginal(InteractionMessageEdit(content: .value("RECOVERY_PAYLOAD_SECRET")))
                    case .acknowledgementDeadline:
                        try clock.advance(by: .seconds(3))
                        try await context.responder.reply(InteractionMessageCreate(content: .value("late")))
                    case .tokenExpired:
                        try await context.responder.deferResponse()
                        try clock.advance(by: .seconds(900))
                        _ = try await context.responder.editOriginal(InteractionMessageEdit(content: .value("expired")))
                    }
                } catch {
                    evidence.capture(await context.responder.snapshot())
                    throw error
                }
            }
        })
        let success = try CommandRoute(key: .command(name: "success"), handler: { context in
            try await context.responder.reply(InteractionMessageCreate(content: .value("ok")))
            evidence.successfulHandlerFinished()
        })
        let commands = try CommandCompilation.compile(ExistingCommandFamily(id: "recovery", definitions: [
            .slash(name: "failure", description: "Finite failing command"),
            .slash(name: "success", description: "Finite succeeding command")
        ], routes: [failed, success]))
        adapter = try GatewayInteractionAdapter(applicationID: .init(rawValue: 9), commands: commands,
            services: services, clock: clock, admission: admission, authority: handlerAuthority,
            maximumPendingInteractions: 4, maximumConcurrentHandlers: 1,
            failurePolicy: .continueInvocations, failureObserver: { evidence.observe($0) })
    }

    /// Compiles one independent event pipeline and installs the explicitly configured interaction owner.
    /// - Returns: Inert supervised host with shared bounded handler/client authorities.
    /// - Throws: Unexpected event compilation or host configuration errors.
    func runtime() throws -> BotRuntime {
        let events = try EventCompilation.compile(Module(id: "recovery") {
            RecoveryEventHandler(evidence: evidence)
        }, intents: [])
        return try BotRuntime(client: client, events: events, handlerConfiguration: .init(),
            handlerAuthority: handlerAuthority, interactions: adapter)
    }

    /// Builds internal socket-equivalent input solely to isolate terminal admission gates.
    /// - Parameters:
    ///   - application: Exact application identity, default nine.
    ///   - malformed: Whether to omit all mandatory fields, default false.
    ///   - malformedRoute: Whether to duplicate one option name, default false.
    /// - Returns: Timestamped private-ingestion fixture unavailable to public hosts.
    /// - Throws: Invalid fixture envelope/shard bounds.
    func event(application: String = "9", malformed: Bool = false, malformedRoute: Bool = false) throws -> GatewayEvent {
        var json = malformed ? "{}" : Self.interaction(name: "failure", id: "1", application: application)
        if malformedRoute {
            json = json.replacingOccurrences(of: "\"options\":[",
                with: "\"options\":[{\"type\":3,\"name\":\"text\",\"value\":\"duplicate\"},")
        }
        let envelope = try GatewayEnvelope(.text("{\"op\":0,\"s\":1,\"t\":\"INTERACTION_CREATE\",\"d\":\(json)}"),
            maximumBytes: 1_048_576)
        return GatewayEvent(shard: try .init(botID: .init(rawValue: 42), topologyGeneration: 0, index: 0, count: 1),
            envelope: envelope, receiptAge: { .zero })
    }

    /// Checks every observable local owner only after joined shutdown has returned.
    func expectEmpty() async {
        let events = await hub.snapshot(), handlers = await handlerAuthority.snapshot()
        let resources = await budget.snapshot(), interactions = await adapter.snapshot()
        #expect(events.subscriptions == 0)
        #expect(events.bufferedEvents == 0)
        #expect(events.bufferedBytes == 0)
        #expect(events.waitingConsumers == 0)
        #expect(handlers.activeHandlers == 0)
        #expect(handlers.waitingHandlers == 0)
        #expect(resources.clients == 0)
        #expect(resources.shards == 0)
        #expect(resources.rawEvents == 0)
        #expect(resources.rawBytes == 0)
        #expect(interactions.activeHandlers == 0)
        #expect(interactions.bufferedEvents == 0)
        #expect(interactions.bufferedBytes == 0)
        #expect(interactions.subscriptions == 0)
        #expect(await admission.snapshot().activeCount == 0)
        #expect(await leases.retainedLeaseCount() == 0)
        #expect(await responseBodies.snapshot().live == 0)
        for rates in [initialRates, continuationRates] {
            let state = await rates.snapshot()
            #expect(state.activeCount == 0)
            #expect(state.queuedCount == 0)
            #expect(state.queuedBytes == 0)
            #expect(state.orderedOperationsCount == 0)
        }
        #expect(clock.pendingSleepCount == 0)
    }

    /// Creates a complete bounded command interaction with a synthetic sentinel token and option.
    /// - Parameters:
    ///   - name: Explicit command wire name.
    ///   - id: Distinct interaction snowflake text.
    ///   - application: Expected application snowflake text, default nine.
    /// - Returns: Credential-free JSON fixture except for deliberate synthetic redaction sentinels.
    static func interaction(name: String, id: String, application: String = "9") -> String {
        "{\"id\":\"\(id)\",\"application_id\":\"\(application)\",\"type\":2,\"token\":\"RECOVERY_TOKEN_SECRET_\(id)\",\"version\":1," +
        "\"data\":{\"id\":\"3\",\"name\":\"\(name)\",\"type\":1,\"options\":[{\"type\":3,\"name\":\"text\",\"value\":\"RECOVERY_PAYLOAD_SECRET\"}]}," +
        "\"app_permissions\":\"0\",\"entitlements\":[],\"authorizing_integration_owners\":{},\"attachment_size_limit\":1048576}"
    }

    /// Returns one single-use bounded JSON body, with sentinel headers that must never be logged.
    /// - Parameters:
    ///   - json: Complete small response fixture.
    ///   - status: HTTP status, default success.
    /// - Returns: Owned response body and explicit nonblocking rate metadata.
    /// - Throws: Invalid request body bounds.
    static func response(_ json: String, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [.init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"), .init(name: "X-RateLimit-Reset-After", value: "1"),
            .init(name: "X-Fixture", value: "RECOVERY_HEADER_SECRET")],
            body: try RequestBody(bytes: Data(json.utf8), contentType: "application/json").makeStream())
    }
}

/// A finite real authority whose cleanup succeeds remotely before a simulated lost authority reply.
/// The coordinator must fail closed while preserving primary transport/body uncertainty.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RecoverySecondaryFailureStore: RateLimitStore {
    typealias Instant = ManualClock.Instant
    private let base = InProcessRateLimitStore<Instant>()
    private let failComplete: Bool
    private(set) var completions = 0
    private(set) var releases = 0

    /// Selects the secondary operation that reports an unavailable shared authority.
    /// - Parameter failComplete: True rejects body-failure completion; false rejects failed-send release.
    init(failComplete: Bool) { self.failComplete = failComplete }

    /// Admits through the production bounded ledger without changing credentials or quota accounting.
    /// - Parameters:
    ///   - request: Existing opaque rate scopes.
    ///   - now: Original shared monotonic instant.
    /// - Returns: Production reservation or bounded retry time.
    /// - Throws: Original production admission errors.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        try await base.reserve(request, now: now)
    }

    /// Releases production ownership, then simulates a failed authority observation after body failure.
    /// - Parameters:
    ///   - reservation: Original owned production ticket.
    ///   - status: Received HTTP status.
    ///   - headers: Bounded received metadata.
    ///   - retryAfter: Existing optional retry observation.
    ///   - global: Existing global-limit flag.
    ///   - now: Original shared monotonic instant.
    /// - Throws: Original ledger errors or fixed coordinator unavailability after production cleanup.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                  retryAfter: Duration?, global: Bool, now: Instant) async throws {
        completions += 1
        try await base.complete(reservation, status: status, headers: headers, retryAfter: retryAfter, global: global, now: now)
        if failComplete { throw RateLimitFailure.coordinatorUnavailable }
    }

    /// Releases production ownership, then simulates an unavailable reply after a failed send.
    /// - Parameters:
    ///   - reservation: Original owned production ticket.
    ///   - outcome: Existing uncertain-send evidence.
    ///   - now: Original shared monotonic instant.
    /// - Throws: Original ledger errors or fixed coordinator unavailability after production cleanup.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        releases += 1
        try await base.release(reservation, outcome: outcome, now: now)
        if !failComplete { throw RateLimitFailure.coordinatorUnavailable }
    }

    /// Reads bounded aggregate ownership without retaining request, token or interaction labels.
    /// - Returns: Production ledger counters after remote cleanup.
    func snapshot() async -> SchedulingSnapshot { await base.snapshot() }
}

/// Counts actual upgrade attempts while returning the same explicitly owned synthetic socket.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RecoveryTransport: WebSocketTransport {
    private let socket: RecoverySocket
    private(set) var connections = 0
    /// Stores one inert test connection without starting work.
    /// - Parameter socket: Finite protocol peer returned on explicit upgrade.
    init(socket: RecoverySocket) { self.socket = socket }
    /// Validates the production context and counts each attempted connection without retaining requests.
    /// - Parameters:
    ///   - request: Existing upgrade request, intentionally not retained.
    ///   - context: Existing cancellation/deadline authority.
    /// - Returns: The one owned protocol peer.
    /// - Throws: Existing cancellation/deadline errors.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        try context.check(); connections += 1; return socket
    }
}

/// Handshakes once and releases three finite input frames only through explicit test barriers.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RecoverySocket: WebSocketConnection {
    private let identified = TestBarrier(), idle = TestBarrier()
    nonisolated let secondQueued = TestBarrier()
    private nonisolated let gates = [TestBarrier(), TestBarrier(), TestBarrier()]
    private let firstName: String
    private var nextIndex = 0
    private var closed = false
    private(set) var closes = 0
    /// Stores a finite first command selection without executing I/O.
    /// - Parameter firstName: Exact name, including the stale registration branch.
    init(firstName: String) { self.firstName = firstName }
    /// Releases one bounded predeclared frame, without enqueuing unbounded work.
    /// - Parameter index: Fixture frame slot in zero through two.
    nonisolated func release(_ index: Int) { gates[index].open() }
    /// Opens READY only after production Identify, discarding all outgoing credential bytes.
    /// - Parameters:
    ///   - message: Existing bounded production write.
    ///   - context: Existing deadline/cancellation authority.
    /// - Throws: Invalid fixture JSON or context errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        if case .text(let text) = message, case .object(let object) = try JSONValue.parse(text),
           case .number(let opcode) = object["op"], opcode.rawValue == "2" { identified.open() }
    }
    /// Supplies real socket input for production receipt stamping, followed by a cooperative idle read.
    /// - Parameter context: Production receive cancellation/deadline authority.
    /// - Returns: Next complete bounded frame, or EOF after owner close.
    /// - Throws: Context errors or cancellation while awaiting explicit fixture input.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        if closed { return nil }
        let index = nextIndex; nextIndex += 1
        switch index {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":3600000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"offline","resume_gateway_url":"wss://gateway.discord.gg"}}"#)
        case 2, 3:
            try await gates[index - 2].wait()
            let json = RecoveryFixture.interaction(name: index == 2 ? firstName : "success", id: String(index))
            return .text("{\"op\":0,\"s\":\(index),\"t\":\"INTERACTION_CREATE\",\"d\":\(json)}")
        case 4:
            secondQueued.open()
            try await gates[2].wait()
            return .text(#"{"op":0,"s":4,"t":"RECOVERY_EVENT","d":{"value":"RECOVERY_PAYLOAD_SECRET"}}"#)
        default: try await idle.wait(); return nil
        }
    }
    /// Idempotently closes the one owned connection and releases every fixture wait.
    func close() {
        guard !closed else { return }
        closed = true; closes += 1; identified.open(); idle.open()
        for gate in gates { gate.open() }
    }
}

/// Independent event handling proves an invocation failure does not cancel the runtime's sibling pipeline.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct RecoveryEventHandler: GatewayEventHandler {
    let handlerID = "recovery.events"
    let selector = GatewayEventSelector<GatewayEvent>.raw
    let evidence: RecoveryEvidence
    /// Observes only a fixed fixture event name, without retaining event data or credentials.
    /// - Parameters:
    ///   - event: Original bounded raw event.
    ///   - context: Existing dispatch context, intentionally unused.
    func handle(_ event: GatewayEvent, context: GatewayEventContext) async throws {
        if event.name == "RECOVERY_EVENT" { evidence.eventDelivered.open() }
    }
}
