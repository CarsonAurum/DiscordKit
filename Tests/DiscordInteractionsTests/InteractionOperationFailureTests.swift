// File: Tests/DiscordInteractionsTests/InteractionOperationFailureTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordInteractions

/// Verifies opt-in operation provenance without changing response ownership or exposing arbitrary errors.
@Suite(.timeLimit(.minutes(1))) struct InteractionOperationFailureTests {
    /// A sink error retains exact identity without instrumentation; scoped formatting conceals all its content.
    /// - Throws: Unexpected fixture parsing or responder behavior fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func scopePreservesOriginalAndRedactsWrapper() async throws {
        let sentinel = OperationSentinel()
        let plain = try Self.fixture(initialError: sentinel)
        do {
            try await plain.responder.deferResponse()
            Issue.record("Expected initial failure")
        } catch { #expect((error as? OperationSentinel) === sentinel) }
        let unknownScoped = try Self.fixture(initialError: sentinel)
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    try await unknownScoped.responder.deferResponse()
                    Issue.record("Expected original scoped injected error")
                } catch {
                    #expect((error as? OperationSentinel) === sentinel)
                    let failure = try #require(await InteractionFailureScope.annotate(error, at: .handler) as? InteractionOperationFailure)
                    #expect(failure.stage == .handler)
                    #expect(!String(reflecting: failure).contains("SENTINEL-SECRET"))
                }
            }
        }
        let scoped = try Self.fixture(initialError: InteractionDeliveryError.notSubmitted)
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    try await scoped.responder.deferResponse()
                    Issue.record("Expected scoped initial failure")
                } catch {
                    let failure = try #require(await InteractionFailureScope.annotate(error, at: .handler) as? InteractionOperationFailure)
                    #expect(failure.stage == .acknowledgement)
                    #expect(error as? InteractionDeliveryError == .notSubmitted)
                    #expect(failure.underlying as? InteractionDeliveryError == .notSubmitted)
                    #expect(String(describing: failure) == "InteractionOperationFailure(redacted)")
                    #expect(!String(reflecting: failure).contains("SENTINEL-SECRET"))
                }
            }
        }
        #expect(await plain.admission.snapshot().activeCount == 0)
        #expect(await scoped.admission.snapshot().activeCount == 0)
        #expect(await scoped.responder.snapshot() == .pending)
        #expect(scoped.clock.pendingSleepCount == 0)
    }

    /// Initial validation and expiry retain acknowledgement provenance before a callback can be submitted.
    /// - Parameter expired: True expires the receipt; false exercises incompatible response validation.
    /// - Throws: Unexpected fixture or operation provenance fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func initialPreflight(expired: Bool) async throws {
        let fixture = try Self.fixture()
        if expired { try fixture.clock.advance(by: .seconds(3)) }
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    try await fixture.responder.respond(expired ? .deferredMessage(ephemeral: false) : .pong)
                    Issue.record("Expected initial preflight failure")
                } catch {
                    let failure = try #require(await InteractionFailureScope.annotate(error, at: .handler) as? InteractionOperationFailure)
                    #expect(failure.stage == .acknowledgement)
                    if expired { #expect(failure.underlying as? InteractionLifecycleError == .deadlineExceeded) }
                    else { #expect(failure.underlying as? DiscordError == .validation(.invalidValue)) }
                }
            }
        }
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Continuation preflight and adapter uncertainty are attributed before the enclosing handler boundary.
    /// - Parameter operation: Zero edits without acknowledgement, one follows up after token expiry,
    ///   and two deletes after acknowledgement with an arbitrary adapter failure.
    /// - Throws: Unexpected fixture or operation provenance fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<3) func continuationBoundary(operation: Int) async throws {
        let fixture = try Self.fixture()
        if operation > 0 { try await fixture.responder.deferResponse() }
        if operation == 1 { try fixture.clock.advance(by: .seconds(900)) }
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    switch operation {
                    case 0: _ = try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("safe")))
                    case 1: _ = try await fixture.responder.followup(InteractionMessageCreate(content: .value("safe")))
                    default: try await fixture.responder.deleteOriginal()
                    }
                    Issue.record("Expected continuation failure")
                } catch {
                    let failure = try #require(await InteractionFailureScope.annotate(error, at: .handler) as? InteractionOperationFailure)
                    #expect(failure.stage == .continuation)
                    switch operation {
                    case 0: #expect(failure.underlying as? InteractionLifecycleError == .notAcknowledged)
                    case 1: #expect(failure.underlying as? InteractionLifecycleError == .tokenExpired)
                    default:
                        #expect(failure.underlying as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
                    }
                }
            }
        }
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Annotation preserves cancellation and never replaces an earlier responder boundary with a handler label.
    @Test func cancellationAndFirstBoundary() async {
        await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            #expect(await InteractionFailureScope.annotate(CancellationError(), at: .handler) is CancellationError)
            #expect(await InteractionFailureScope.annotate(DiscordError.cancelled, at: .preparation) as? DiscordError == .cancelled)
            let first = InteractionOperationFailure(stage: .continuation, underlying: OperationSentinel())
            let second = await InteractionFailureScope.annotate(first, at: .handler) as? InteractionOperationFailure
            #expect(second?.stage == .continuation)
        }
    }

    /// Closed continuation owner failures remain terminal evidence while public uncertainty errors stay unchanged.
    /// - Parameter index: Four rate-authority and four transport owner/configuration categories.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<8) func ownerEvidenceSurvivesTranslation(index: Int) async throws {
        let original: any Error
        let expected: InteractionOwnerFailure
        switch index {
        case 0: original = RateLimitFailure.closed; expected = .rateLimit(.closed)
        case 1: original = RateLimitFailure.invalidRequest; expected = .rateLimit(.invalidRequest)
        case 2: original = RateLimitFailure.unknownReservation; expected = .rateLimit(.unknownReservation)
        case 3: original = RateLimitFailure.coordinatorUnavailable; expected = .rateLimit(.coordinatorUnavailable)
        case 4: original = TransportFailure.closed; expected = .transport(.closed)
        case 5: original = TransportFailure.concurrentRead; expected = .transport(.concurrentRead)
        case 6: original = TransportFailure.invalidLimit; expected = .transport(.invalidLimit)
        default: original = TransportFailure.scriptExhausted; expected = .transport(.scriptExhausted)
        }
        let fixture = try Self.fixture(continuationError: original)
        try await fixture.responder.deferResponse()
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    try await fixture.responder.deleteOriginal()
                    Issue.record("Expected translated continuation failure")
                } catch {
                    #expect(error as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
                    let annotated = try #require(await InteractionFailureScope.annotate(error, at: .handler)
                        as? InteractionOperationFailure)
                    #expect(annotated.stage == .continuation)
                    #expect(annotated.ownerFailure == expected)
                    #expect(annotated.underlying as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
                    await InteractionFailureScope.clear()
                    let replaced = try #require(await InteractionFailureScope.annotate(OperationSentinel(), at: .handler)
                        as? InteractionOperationFailure)
                    #expect(replaced.ownerFailure == expected)
                    let nested = InteractionOperationFailure(stage: .handler, underlying: OperationSentinel())
                    let nestedOuter = try #require(await InteractionFailureScope.annotate(nested, at: .handler)
                        as? InteractionOperationFailure)
                    #expect(nestedOuter.ownerFailure == expected)
                }
            }
        }
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Lower-layer owner observations retain the exact response stage even after HTTP normalizes the thrown error.
    /// - Parameter continuation: False fails the initial sink; true acknowledges then fails the original-delete sink.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func lowerLayerOwnerObservation(continuation: Bool) async throws {
        let clock = ManualClock(), admission = try InteractionAcknowledgementAdmission()
        let mapped = DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)
        let sink = InteractionResponseSink(initial: { _, _ in
            if !continuation {
                await InvocationOwnerFailureScope.record(.transportClosed)
                throw mapped
            }
        }, deleteOriginal: { _ in
            await InvocationOwnerFailureScope.record(.transportClosed)
            throw mapped
        })
        let responder = InteractionResponder(interaction: try InteractionLifecycleTests.interaction(), deliveryMode: .gateway,
            clock: InteractionClock(clock), sink: sink, admission: admission)
        if continuation { try await responder.deferResponse() }
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            try await InteractionFailureScope.withOperationCapture {
                do {
                    if continuation { try await responder.deleteOriginal() }
                    else { try await responder.deferResponse() }
                    Issue.record("Expected normalized owner failure")
                } catch {
                    #expect(error as? DiscordError == mapped)
                    let annotated = try #require(await InteractionFailureScope.annotate(error, at: .handler)
                        as? InteractionOperationFailure)
                    #expect(annotated.ownerFailure == .transport(.closed))
                    #expect(annotated.stage == (continuation ? .continuation : .acknowledgement))
                }
            }
        }
        #expect(await admission.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Creates one response owner over virtual time with optional initial failure and rejecting continuation sinks.
    /// - Parameters:
    ///   - initialError: Nil confirms the initial callback; otherwise throws the exact supplied object.
    ///   - continuationError: Injected continuation failure, default an arbitrary unsafe sentinel.
    /// - Returns: Isolated clock, bounded acknowledgement authority and inert responder.
    /// - Throws: Fixture parsing or admission configuration failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func fixture(initialError: (any Error)? = nil, continuationError: any Error = OperationSentinel()) throws ->
        (clock: ManualClock, admission: InteractionAcknowledgementAdmission, responder: InteractionResponder) {
        let clock = ManualClock(), admission = try InteractionAcknowledgementAdmission()
        let interaction = try InteractionLifecycleTests.interaction()
        let sink = InteractionResponseSink(initial: { _, _ in if let initialError { throw initialError } },
            editOriginal: { _, _ in throw continuationError }, followup: { _, _ in throw continuationError },
            deleteOriginal: { _ in throw continuationError })
        return (clock, admission, InteractionResponder(interaction: interaction, deliveryMode: .gateway,
            clock: InteractionClock(clock), sink: sink, admission: admission))
    }
}

/// Immutable synthetic error whose unsafe text proves wrapper formatting never traverses the underlying object.
private final class OperationSentinel: Error, Sendable, CustomStringConvertible {
    /// Returns deliberately unsafe test content that must remain absent from public diagnostics.
    var description: String { "SENTINEL-SECRET" }
}
