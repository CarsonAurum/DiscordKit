// File: Tests/DiscordBotDSLTests/DiagnosticTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordClient
import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordHTTP
import DiscordInteractions
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordBotDSL

/// Stores a finite safe observer projection without retaining errors or interaction identities.
final class DiagnosticCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BotFailureDiagnostic] = []

    /// Returns the bounded captured observations under the same lock used by concurrent children.
    var diagnostics: [BotFailureDiagnostic] { lock.withLock { values } }

    /// Records at most three immutable safe values; no asynchronous tasks or per-token keys are used.
    /// - Parameter diagnostic: Sanitized observer value received directly from the runtime.
    func record(_ diagnostic: BotFailureDiagnostic) {
        lock.withLock { if values.count < 3 { values.append(diagnostic) } }
    }
}

/// An arbitrary injected error deliberately retaining every forbidden diagnostic surface.
private struct SecretDiagnosticFailure: Error, Sendable, CustomStringConvertible {
    let token = "sentinel-interaction-token"
    let url = "https://sentinel.example/private-route?token=sentinel-url-secret"
    let headers = ["Authorization": "sentinel-header-secret"]
    let payload = "sentinel-message-content-and-options"
    /// Simulates unsafe dependency descriptions that classification must never inspect.
    var description: String { "sentinel-arbitrary-error-description" }
}

/// A raw callback receives synthetic public events solely to exercise supervised event-stage failures.
private struct DiagnosticEventHandler: GatewayEventHandler {
    let callback: @Sendable () async throws -> Void
    let handlerID = "diagnostic-handler"
    let selector = GatewayEventSelector<GatewayEvent>.raw
    let requiredIntents: GatewayIntents = []

    /// Runs one explicit synthetic callback without decoding or retaining event contents.
    /// - Parameters:
    ///   - event: Finite event accepted by the raw selector; not treated as interaction provenance.
    ///   - context: Existing event boundary metadata; never treated as authentication.
    /// - Throws: The test-selected callback error, without retry or error translation.
    func handle(_ event: GatewayEvent, context: GatewayEventContext) async throws { try await callback() }
}

/// Safe classification and supervised-boundary attribution use offline finite peers only.
@Suite("Safe bot failure diagnostics", .timeLimit(.minutes(1)))
struct DiagnosticTests {
    /// Known categories retain only fixed names and optional numeric evidence, including unknown API codes.
    @Test func knownFamiliesAndNumericEvidence() {
        let cases: [(any Error, BotFailureCategory)] = [
            (CancellationError(), .cancelled),
            (DiscordError.cancelled, .cancelled),
            (DiscordError.validation(.emptyCredential), .validationEmptyCredential),
            (DiscordError.validation(.invalidCredential), .validationInvalidCredential),
            (DiscordError.validation(.invalidValue), .validationInvalidValue),
            (DiscordError.validation(.missingValue), .validationMissingValue),
            (DiscordError.validation(.limitExceeded), .validationLimitExceeded),
            (DiscordError.transport(.connectionFailed), .transportConnectionFailed),
            (DiscordError.transport(.disconnected), .transportDisconnected),
            (DiscordError.transport(.deadlineExceeded), .transportDeadlineExceeded),
            (DiscordError.transport(.invalidResponse), .transportInvalidResponse),
            (DiscordError.transport(.limitExceeded), .transportLimitExceeded),
            (DiscordError.unknownMutationOutcome(.cancelledAfterSubmission), .mutationCancelledAfterSubmission),
            (DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission), .mutationConnectionLostAfterSubmission),
            (DiscordError.unknownMutationOutcome(.deadlineAfterSubmission), .mutationDeadlineAfterSubmission),
            (DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission), .mutationServerErrorAfterSubmission),
            (DiscordError.capabilityUnavailable(.unsupportedPlatform), .capabilityUnsupportedPlatform),
            (DiscordError.capabilityUnavailable(.restrictedByHost), .capabilityRestrictedByHost),
            (DiscordError.capabilityUnavailable(.permissionDenied), .capabilityPermissionDenied),
            (DiscordError.capabilityUnavailable(.missingConfiguration), .capabilityMissingConfiguration),
            (DiscordError.capabilityUnavailable(.notImplemented), .capabilityNotImplemented),
            (DiscordError.capabilityUnavailable(.notQualified), .capabilityNotQualified),
            (DiscordError.capabilityUnavailable(.missingUpstreamContract), .capabilityMissingUpstreamContract),
            (InteractionLifecycleError.invalidConfiguration, .interactionLifecycleInvalidConfiguration),
            (InteractionLifecycleError.contextMismatch, .interactionLifecycleContextMismatch),
            (InteractionLifecycleError.unsupportedInteraction, .interactionLifecycleUnsupportedInteraction),
            (InteractionLifecycleError.initialResponseInFlight, .interactionLifecycleInitialResponseInFlight),
            (InteractionLifecycleError.alreadyAcknowledged, .interactionLifecycleAlreadyAcknowledged),
            (InteractionLifecycleError.notAcknowledged, .interactionLifecycleNotAcknowledged),
            (InteractionLifecycleError.indeterminateAcknowledgement, .interactionLifecycleIndeterminateAcknowledgement),
            (InteractionLifecycleError.deadlineExceeded, .interactionLifecycleDeadlineExceeded),
            (InteractionLifecycleError.tokenExpired, .interactionLifecycleTokenExpired),
            (InteractionLifecycleError.acknowledgementCapacityExceeded, .interactionLifecycleAcknowledgementCapacityExceeded),
            (InteractionLifecycleError.originalResponseUnavailable, .interactionLifecycleOriginalResponseUnavailable),
            (InteractionLifecycleError.deferredResponseRequired, .interactionLifecycleDeferredResponseRequired),
            (InteractionLifecycleError.completeDeferredResponseFirst, .interactionLifecycleCompleteDeferredResponseFirst),
            (InteractionLifecycleError.continuationInFlight, .interactionLifecycleContinuationInFlight),
            (InteractionLifecycleError.handlerAlreadyRunning, .interactionLifecycleHandlerAlreadyRunning),
            (InteractionDeliveryError.notSubmitted, .interactionDeliveryNotSubmitted),
            (InteractionDeliveryError.indeterminate, .interactionDeliveryIndeterminate),
            (GatewayInteractionFailure.alreadyPrepared, .gatewayInteractionAlreadyPrepared),
            (GatewayInteractionFailure.notPrepared, .gatewayInteractionNotPrepared),
            (GatewayInteractionFailure.alreadyRun, .gatewayInteractionAlreadyRun),
            (GatewayInteractionFailure.untrustedEvent, .gatewayInteractionUntrustedEvent),
            (GatewayInteractionFailure.wrongApplication, .gatewayInteractionWrongApplication),
            (GatewayInteractionFailure.unmatchedCommand, .gatewayInteractionUnmatchedCommand),
            (GatewayFailure.invalidConfiguration, .gatewayInvalidConfiguration),
            (GatewayFailure.invalidPayload, .gatewayInvalidPayload),
            (GatewayFailure.unsupportedEncoding, .gatewayUnsupportedEncoding),
            (GatewayFailure.invalidTransition, .gatewayInvalidTransition),
            (GatewayFailure.alreadyRunning, .gatewayAlreadyRunning),
            (GatewayFailure.staleGeneration, .gatewayStaleGeneration),
            (GatewayFailure.disconnected, .gatewayDisconnected),
            (GatewayFailure.reconnectRequested, .gatewayReconnectRequested),
            (GatewayFailure.missedHeartbeatACK, .gatewayMissedHeartbeatACK),
            (GatewayFailure.retryLimitExceeded, .gatewayRetryLimitExceeded),
            (GatewayFailure.eventCapacityExceeded, .gatewayEventCapacityExceeded),
            (GatewayFailure.startupRefreshRequired, .gatewayStartupRefreshRequired),
            (GatewayFailure.coordinatorUnavailable, .gatewayCoordinatorUnavailable),
            (GatewayFailure.commandCapacityExceeded, .gatewayCommandCapacityExceeded),
            (GatewayFailure.commandRateLimited(retryAfter: .seconds(12)), .gatewayCommandRateLimited),
            (GatewayFailure.requestConflict, .gatewayRequestConflict),
            (GatewayFailure.notReady, .gatewayNotReady),
            (GatewayFailure.missingIntent, .gatewayMissingIntent),
            (GatewayEventDeliveryFailure.invalidConfiguration, .eventDeliveryInvalidConfiguration),
            (GatewayEventDeliveryFailure.subscriptionCapacityExceeded, .eventDeliverySubscriptionCapacityExceeded),
            (GatewayEventDeliveryFailure.resynchronizationRequired, .eventDeliveryResynchronizationRequired),
            (GatewayEventDeliveryFailure.concurrentIteration, .eventDeliveryConcurrentIteration),
            (GatewayEventDeliveryFailure.handlerCapacityExceeded, .eventDeliveryHandlerCapacityExceeded),
            (GatewayEventDeliveryFailure.finished, .eventDeliveryFinished),
            (ClientFailure.invalidConfiguration, .clientInvalidConfiguration),
            (ClientFailure.alreadyRunning, .clientAlreadyRunning),
            (ClientFailure.stopped, .clientStopped),
            (ClientFailure.capacityExceeded, .clientCapacityExceeded),
            (ClientFailure.notReady, .clientNotReady),
            (RateLimitFailure.queueFull, .rateLimitQueueFull),
            (RateLimitFailure.metadataFull, .rateLimitMetadataFull),
            (RateLimitFailure.deadlineExceeded, .rateLimitDeadlineExceeded),
            (RateLimitFailure.closed, .rateLimitClosed),
            (RateLimitFailure.invalidRequest, .rateLimitInvalidRequest),
            (RateLimitFailure.reservationExpired, .rateLimitReservationExpired),
            (RateLimitFailure.unknownReservation, .rateLimitUnknownReservation),
            (RateLimitFailure.coordinatorUnavailable, .rateLimitCoordinatorUnavailable),
            (BotRuntimeFailure.alreadyRunning, .botRuntimeAlreadyRunning),
            (BotRuntimeFailure.stopped, .botRuntimeStopped),
            (ShardOwnershipFailure.invalidAssignment, .shardOwnershipInvalidAssignment),
            (ShardOwnershipFailure.invalidLimit, .shardOwnershipInvalidLimit),
            (ShardOwnershipFailure.alreadyOwned, .shardOwnershipAlreadyOwned),
            (ShardOwnershipFailure.capacityExceeded, .shardOwnershipCapacityExceeded),
            (ShardOwnershipFailure.staleLease, .shardOwnershipStaleLease),
            (ShardOwnershipFailure.coordinatorUnavailable, .shardOwnershipCoordinatorUnavailable),
            (ShardOwnershipFailure.generationExhausted, .shardOwnershipGenerationExhausted)
        ]
        let numericOrUnknown = [BotFailureCategory.unclassified, .api, .gatewayFatalClose]
        #expect(Set(cases.map { $0.1.rawValue }) == Set(BotFailureCategory.allCases.map(\.rawValue))
            .subtracting(numericOrUnknown.map(\.rawValue)))
        for (error, category) in cases {
            let value = BotFailureDiagnostic(classifying: error, stage: .handler)
            #expect(value.stage == .handler)
            #expect(value.category == category)
            #expect(value.httpStatus == nil && value.apiCode == nil && value.gatewayCloseCode == nil)
        }
        let api = BotFailureDiagnostic(classifying: DiscordError.api(status: 403, code: 987654321), stage: .acknowledgement)
        #expect(api.category == .api)
        #expect(api.httpStatus == 403)
        #expect(api.apiCode == 987654321)
        let noCode = BotFailureDiagnostic(classifying: DiscordError.api(status: 404, code: nil), stage: .acknowledgement)
        #expect(noCode.category == .api && noCode.httpStatus == 404 && noCode.apiCode == nil)
        #expect(api.logMetadata["dk.http_status"]?.description == "403")
        #expect(api.logMetadata["dk.api_code"]?.description == "987654321")
        let responseError = APIResponseError(status: 400,
            headers: [.init(name: "Authorization", value: "sentinel-header-secret")],
            body: Data(#"{"code":50035,"message":"sentinel-message","errors":{"sentinel-options":"secret"}}"#.utf8))
        let response = BotFailureDiagnostic(classifying: responseError, stage: .continuation)
        #expect(response.category == .api && response.httpStatus == 400 && response.apiCode == 50035)
        #expect(!String(reflecting: response).contains("sentinel"))
        let fatal = BotFailureDiagnostic(classifying: GatewayFailure.fatalClose(4014), stage: .client)
        #expect(fatal.category == .gatewayFatalClose)
        #expect(fatal.gatewayCloseCode == 4014)
        #expect(fatal.logMetadata["dk.gateway_close_code"]?.description == "4014")
        #expect(Set(BotFailureStage.allCases.map(\.rawValue)) ==
            ["setup", "client", "events", "interactions", "acknowledgement", "continuation", "handler", "cleanup"])
    }

    /// Nested aggregates are never recursively reflected; only primary and two additional entries are projected.
    @Test func boundedAggregateAndSecretRedaction() {
        let secret = SecretDiagnosticFailure()
        let nested = BotRuntimeFailures(primary: secret, additional: [secret, secret])
        let aggregate = BotRuntimeFailures(primary: DiscordError.api(status: 500, code: 10062),
            additional: [DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission), nested, secret, secret])
        let diagnostics = BotFailureDiagnostic.classify(aggregate, stage: .continuation)
        #expect(diagnostics.count == 3)
        #expect(diagnostics.map(\.category) == [.api, .mutationServerErrorAfterSubmission, .unclassified])
        #expect(diagnostics.allSatisfy { $0.stage == .continuation })
        #expect(BotFailureDiagnostic(classifying: secret, stage: .handler).category == .unclassified)
        let foreign = NSError(domain: "sentinel-domain-secret", code: 429,
            userInfo: [NSLocalizedDescriptionKey: "sentinel-user-info-secret", "token": secret.token])
        #expect(BotFailureDiagnostic(classifying: foreign, stage: .handler).category == .unclassified)
        let output = String(reflecting: diagnostics) + String(describing: diagnostics.map(\.logMetadata))
        #expect(!output.contains("sentinel"))
        #expect(output.contains("10062"))
        #expect(output.contains("mutation.server_error_after_submission"))
    }

    /// Internally captured operation provenance overrides the broad child stage without exposing its original error.
    @Test func capturedStageAndAggregateProvenance() {
        let diagnostic = BotFailureDiagnostic(classifying: DiscordError.api(status: 400, code: 50035), stage: .acknowledgement)
        let wrapper = BotFailureObservationError(original: SecretDiagnosticFailure(), diagnostic: diagnostic)
        #expect(BotFailureDiagnostic(classifying: wrapper, stage: .interactions) == diagnostic)
        let aggregate = BotRuntimeFailures(primary: wrapper.original, additional: [SecretDiagnosticFailure()],
            diagnostics: [diagnostic, .init(classifying: SecretDiagnosticFailure(), stage: .cleanup)])
        let values = BotFailureDiagnostic.classify(aggregate, stage: .client)
        #expect(values.map(\.stage) == [.acknowledgement, .cleanup])
        #expect(!String(reflecting: wrapper).contains("sentinel"))
        #expect(!String(describing: wrapper).contains("sentinel"))
    }

    /// Setup is observed where subscription fails, before any discovery or client resources are acquired.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func setupObservationIsSafeAndInertUntilRun() async throws {
        let fixture = try DiagnosticRuntimeFixture(steps: [])
        await fixture.hub.finish()
        let capture = DiagnosticCapture(), recorder = LogRecorder()
        let runtime = try fixture.runtime(observer: capture.record)
        #expect(capture.diagnostics.isEmpty)
        #expect(await fixture.http.executionCount == 0)
        await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            await #expect(throws: GatewayEventDeliveryFailure.finished) { try await runtime.run() }
        }
        #expect(capture.diagnostics.map(\.stage) == [.setup])
        #expect(capture.diagnostics.map(\.category) == [.eventDeliveryFinished])
        #expect(await fixture.http.executionCount == 0)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(recorder.entries.contains { $0.metadata["dk.stage"]?.description == "setup" })
    }

    /// Discovery errors report client provenance, while arbitrary event errors report events and remain original throws.
    /// - Parameter eventFailure: Whether the callback rather than discovery supplies the selected failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func childBoundariesAndOriginalFailures(_ eventFailure: Bool) async throws {
        let entered = TestBarrier(), blocked = TestBarrier()
        let fixture = try DiagnosticRuntimeFixture(steps: [{ _ in
            if eventFailure { entered.open(); try await blocked.wait(); throw CancellationError() }
            return HTTPResponse(status: 403)
        }])
        let capture = DiagnosticCapture(), recorder = LogRecorder()
        let runtime = try fixture.runtime(observer: capture.record, callback: { throw SecretDiagnosticFailure() })
        await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let run = Task { try await runtime.run() }
            if eventFailure {
                try? await entered.wait()
                do { _ = await fixture.hub.publish(try fixture.event()) }
                catch { Issue.record("Synthetic event publication failed") }
            }
            do { try await run.value; Issue.record("Expected supervised child failure") }
            catch {
                if eventFailure { #expect(error is SecretDiagnosticFailure) }
                else { #expect((error as? APIResponseError)?.status == 403) }
            }
        }
        #expect(capture.diagnostics.count == 1)
        #expect(capture.diagnostics.first?.stage == (eventFailure ? .events : .client))
        #expect(capture.diagnostics.first?.category == (eventFailure ? .unclassified : .api))
        let output = recorder.entries.map { $0.message + String(describing: $0.metadata) }.joined()
        #expect(!output.contains("sentinel"))
        #expect(!String(reflecting: capture.diagnostics).contains("sentinel"))
        #expect(await fixture.hub.snapshot().subscriptions == 0)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await runtime.phase == .failed)
    }
}

/// Minimal inert client dependencies for setup/client/event diagnostics; no socket connects or live calls occur.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct DiagnosticRuntimeFixture {
    let clock = ManualClock()
    let hub: GatewayEventHub
    let http: ScriptedHTTPTransport
    let budget: ClientResourceBudget
    let client: DiscordClient<ManualClock, InProcessShardLeaseStore<ManualClock>>

    /// Stores finite discovery scripts and an idle client without invoking injected work.
    /// - Parameter steps: Finite local discovery operations; no successful connection is required.
    /// - Throws: Invalid test or production resource bounds.
    init(steps: [ScriptedHTTPTransport.Step]) throws {
        http = try ScriptedHTTPTransport(steps: steps)
        hub = GatewayEventHub(configuration: try .init())
        budget = try ClientResourceBudget()
        let rest = RESTClient(credential: .bot(try BotToken("sentinel-bot-credential")), identity: RateLimitIdentity(),
            transport: http, coordinator: RateLimitCoordinator(clock: clock), clock: clock,
            retryPolicy: .init(maximumAttempts: 1))
        client = DiscordClient(token: try BotToken("sentinel-bot-credential"), configuration: try .init(intents: []),
            services: .init(rest: rest), transport: ScriptedWebSocketTransport(connection: try ScriptedWebSocketConnection(incoming: [])),
            clock: clock, leases: try InProcessShardLeaseStore(clock: clock, maximumLeases: 1),
            authority: try ClientAuthority(botID: .init(rawValue: 42), clock: clock, budget: budget), events: hub)
    }

    /// Compiles one raw event and binds its finite safe observer without invoking either callback.
    /// - Parameters:
    ///   - observer: Synchronous safe diagnostic recorder.
    ///   - callback: Test callback supplying the selected original event error; default empty.
    /// - Returns: Single-use inert supervised lifetime.
    /// - Throws: Invalid catalog, intents or dispatcher configuration.
    func runtime(observer: @escaping BotFailureObserver,
        callback: @escaping @Sendable () async throws -> Void = {}) throws -> BotRuntime {
        let events = try EventCompilation.compile(Module(id: "diagnostics") { DiagnosticEventHandler(callback: callback) }, intents: [])
        return try BotRuntime(client: client, events: events, handlerConfiguration: .init(), failureObserver: observer)
    }

    /// Creates one bounded public synthetic dispatch for the independent event pipeline only.
    /// - Returns: Credential-free event accepted by the raw test selector.
    /// - Throws: Invalid finite JSON, shard or envelope limits.
    func event() throws -> GatewayEvent {
        try GatewayEvent(shard: .init(botID: .init(rawValue: 42), topologyGeneration: 0, index: 0, count: 1),
            opcode: 0, name: "DIAGNOSTIC_SYNTHETIC", sequence: 1, data: .null, socketGeneration: 1)
    }
}
