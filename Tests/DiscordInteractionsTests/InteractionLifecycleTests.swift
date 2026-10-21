import DiscordCore
import DiscordHTTP
import DiscordLogging
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordInteractions

/// Exercises one response owner using virtual monotonic time and injected cancellation-aware callbacks.
/// No Discord credentials, live network requests, wall-clock sleeps or Gateway runtime are involved.
@Suite(.timeLimit(.minutes(1))) struct InteractionLifecycleTests {
    /// A complete response lifecycle distinguishes encoding, admission, delivery, continuation and cleanup without content.
    /// - Throws: Unexpected offline fixture or response operation failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func detailedResponseLoggingTimeline() async throws {
        let logs = LogRecorder()
        let fixture = try DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) { try LifecycleFixture() }
        #expect(logs.entries.isEmpty)
        try await DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) {
            try await fixture.responder.deferResponse(ephemeral: true)
            _ = try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("private_edit"), deferredResponse: true))
            _ = try await fixture.responder.followup(InteractionMessageCreate(content: .value("private_followup")))
            try await fixture.responder.deleteOriginal()
        }
        let responseEvents = logs.entries.filter { $0.label == "discordkit.interactions.response" }
            .compactMap { $0.metadata["dk.event"]?.description }
        #expect(Array(responseEvents.prefix(7)) == ["interactions.response.started", "interactions.response.validated",
            "interactions.response.reserved", "interactions.response.admission_acquired",
            "interactions.response.delivering", "interactions.response.acknowledged", "interactions.response.admission_released"])
        for operation in ["edit", "followup", "delete"] {
            #expect(responseEvents.contains("interactions.response.\(operation)_started"))
            #expect(responseEvents.contains("interactions.response.\(operation)_completed"))
        }
        #expect(responseEvents.filter { $0 == "interactions.response.continuation_reserved" }.count == 3)
        #expect(responseEvents.filter { $0 == "interactions.response.continuation_released" }.count == 3)
        #expect(logs.entries.contains { $0.level == .trace && $0.metadata["dk.event"] == "interactions.admission.released" && $0.metadata["dk.active"]?.description == "0" && $0.metadata["dk.bytes"]?.description == "0" })
        let rendered = String(describing: logs.entries.map { ($0.message, $0.metadata) })
        for privateValue in ["private_edit", "private_followup", "test-token", "18446744073709551615"] {
            #expect(!rendered.contains(privateValue))
        }
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Definite non-submission remains retryable while ambiguous initial delivery produces a warning and never retries.
    /// - Parameter uncertain: Whether the sink throws an unclassified confidential failure.
    /// - Throws: Unexpected response fixture or admission setup failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func initialFailureLogging(uncertain: Bool) async throws {
        let logs = LogRecorder()
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in
            if uncertain { throw TestSupportFailure.scripted("private_delivery_error") }
            throw InteractionDeliveryError.notSubmitted
        }))
        await DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) {
            await #expect(throws: (any Error).self) { try await fixture.responder.deferResponse() }
        }
        #expect(await fixture.responder.snapshot() == (uncertain ? .indeterminate : .pending))
        #expect(logs.entries.contains { $0.level == .warning && $0.metadata["dk.event"] == "interactions.response.indeterminate" } == uncertain)
        #expect(logs.entries.last?.metadata["dk.event"] == "interactions.response.stopped")
        #expect(logs.entries.contains { $0.metadata["dk.event"] == "interactions.response.admission_released" })
        #expect(!String(describing: logs.entries.map { ($0.message, $0.metadata) }).contains("private_delivery_error"))
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Invalid capacities/delays fail before tasks; a clock retains its original domain through advancement.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func configurationAndClock() async throws {
        for capacity in [0, -1, Int.min] {
            #expect(throws: InteractionLifecycleError.invalidConfiguration) {
                try InteractionAcknowledgementAdmission(maximumConcurrent: capacity)
            }
            #expect(throws: InteractionLifecycleError.invalidConfiguration) {
                try InteractionAcknowledgementAdmission(maximumBytes: capacity)
            }
        }
        for delay: Duration in [.zero, .seconds(-1), .seconds(3), .seconds(900)] {
            #expect(throws: InteractionLifecycleError.invalidConfiguration) {
                try InteractionAutoDeferPolicy(delay: delay, mode: .message(ephemeral: false))
            }
        }
        let clock = ManualClock(), erased = InteractionClock(ManualClock())
        #expect(erased.now == .zero)
        let source = InteractionClock(clock)
        try clock.advance(by: .milliseconds(123))
        #expect(source.now == .milliseconds(123))
        try await source.sleep(until: .zero)
        #expect(clock.pendingSleepCount == 0)
        #expect(try InteractionAutoDeferPolicy(mode: .update).delay == .seconds(2))
    }

    /// Continuous-clock erasure accepts elapsed deadlines and cooperates with cancellation of long token waits.
    /// This checks owned task cleanup without waiting for real wall time or claiming allocator/RSS behavior.
    @Test func continuousClockCancellation() async throws {
        let clock = InteractionClock(ContinuousClock())
        try await clock.sleep(until: .zero)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(until: .seconds(900))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Admission bounds both count and bytes, handles huge requests without overflow and releases idempotently.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func admissionBounds() async throws {
        let admission = try InteractionAcknowledgementAdmission(maximumConcurrent: 1, maximumBytes: 10)
        await #expect(throws: InteractionLifecycleError.invalidConfiguration) { try await admission.acquire(encodedBytes: 0) }
        await #expect(throws: InteractionLifecycleError.acknowledgementCapacityExceeded) {
            try await admission.acquire(encodedBytes: Int.max)
        }
        let reservation = try await admission.acquire(encodedBytes: 10)
        #expect(await admission.snapshot().activeCount == 1)
        #expect(await admission.snapshot().encodedBytes == 10)
        await #expect(throws: InteractionLifecycleError.acknowledgementCapacityExceeded) {
            try await admission.acquire(encodedBytes: 1)
        }
        await admission.release(reservation); await admission.release(reservation)
        #expect(await admission.snapshot().activeCount == 0)
        #expect(await admission.snapshot().encodedBytes == 0)
        let again = try await admission.acquire(encodedBytes: 1)
        await admission.release(again)
    }

    /// Context identity, application, delivery channel and path secret must all match the response owner.
    /// - Parameter mode: Both independently adopted receipt modes normalize to the same handler API.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [InteractionDeliveryMode.http, .gateway]) func normalization(mode: InteractionDeliveryMode) async throws {
        let fixture = try LifecycleFixture(mode: mode)
        let context = try InteractionContext(interaction: fixture.interaction, deliveryMode: mode, responder: fixture.responder)
        #expect(context.interaction.id.rawValue == UInt64.max)
        #expect(context.deliveryMode == mode)
        #expect(String(reflecting: context).contains("redacted"))
        #expect(!String(reflecting: context).contains("test-token"))
        #expect(String(reflecting: fixture.responder).contains("redacted"))
        #expect(!String(reflecting: fixture.responder).contains("test-token"))
        for different in [try Self.interaction(id: "1"), try Self.interaction(applicationID: "2"),
                          try Self.interaction(token: "other-token")] {
            #expect(throws: InteractionLifecycleError.contextMismatch) {
                try InteractionContext(interaction: different, deliveryMode: mode, responder: fixture.responder)
            }
        }
        #expect(throws: InteractionLifecycleError.contextMismatch) {
            try InteractionContext(interaction: fixture.interaction,
                deliveryMode: mode == .http ? .gateway : .http, responder: fixture.responder)
        }
        #expect(await fixture.recorder.callbacks.isEmpty)
        try await context.responder.reply(InteractionMessageCreate(content: .value("hello")))
        #expect(await fixture.responder.snapshot() == .acknowledged(.channelMessageWithSource))
        #expect(await fixture.recorder.callbacks == [.channelMessageWithSource])
        await #expect(throws: InteractionLifecycleError.alreadyAcknowledged) { try await fixture.responder.deferResponse() }
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Every available callback category reaches its exact wire kind and preserves explicit defer visibility.
    /// - Parameter index: PONG, message/defer/update/autocomplete/modal/Activity callback alternatives.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9) func callbackVariants(index: Int) async throws {
        let response: InteractionResponse
        let kind: Int
        switch index {
        case 0: kind = 1; response = .pong
        case 1: kind = 2; response = .message(try InteractionMessageCreate(content: .value("message")))
        case 2: kind = 2; response = .deferredMessage(ephemeral: true)
        case 3: kind = 3; response = .deferredUpdate
        case 4: kind = 3; response = .update(try InteractionMessageEdit(content: .value("updated")))
        case 5: kind = 4; response = .autocomplete([])
        case 6:
            kind = 2
            let component = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":4,"custom_id":"input","style":1,"label":"Input"}]}"#.utf8))
            response = .modal(try InteractionModal(customID: "modal", title: "Title", components: [component]))
        case 7: kind = 2; response = .launchActivity
        default: kind = 5; response = .deferredMessage(ephemeral: false)
        }
        let fixture = try LifecycleFixture(kind: kind, includeMessage: kind == 3)
        try await fixture.responder.respond(response)
        #expect(await fixture.responder.snapshot() == .acknowledged(response.type))
        #expect(await fixture.recorder.callbacks == [response.type])
        if index == 2 { #expect(await fixture.recorder.ephemeral == [true]) }
        #expect(await fixture.recorder.timeouts.allSatisfy { $0 > .zero && $0 <= .seconds(3) })
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Unsupported/incompatible responses and missing message context fail before admission or delivery.
    /// - Parameter kind: PING, autocomplete, modal, ordinary command and future interaction kinds.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [1, 2, 3, 4, 5, 99]) func invalidInitialCallbacks(kind: Int) async throws {
        let fixture = try LifecycleFixture(kind: kind)
        if kind == 99 {
            await #expect(throws: InteractionLifecycleError.unsupportedInteraction) { try await fixture.responder.respond(.pong) }
        } else if kind == 1 || kind == 4 {
            await #expect(throws: DiscordError.validation(.invalidValue)) { try await fixture.responder.deferResponse() }
        } else {
            await #expect(throws: InteractionLifecycleError.originalResponseUnavailable) { try await fixture.responder.deferUpdate() }
        }
        #expect(await fixture.recorder.callbacks.isEmpty)
        #expect(await fixture.responder.snapshot() == .pending)
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Reserved acknowledgement survives actor reentrancy; concurrent replies and defers issue one delivery only.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentInitialResponse() async throws {
        let entered = TestBarrier(), release = TestBarrier(), recorder = LifecycleRecorder()
        let sink = InteractionResponseSink(initial: { response, timeout in
            await recorder.initial(response, timeout: timeout); entered.open(); try await release.wait()
        })
        let fixture = try LifecycleFixture(sink: sink)
        let first = Task { try await fixture.responder.deferResponse(ephemeral: true) }
        try await entered.wait()
        #expect(await fixture.responder.snapshot() == .acknowledging)
        #expect(await fixture.admission.snapshot().activeCount == 1)
        await #expect(throws: InteractionLifecycleError.initialResponseInFlight) {
            try await fixture.responder.reply(InteractionMessageCreate(content: .value("race")))
        }
        await #expect(throws: InteractionLifecycleError.initialResponseInFlight) {
            try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("early")))
        }
        release.open(); try await first.value
        #expect(await recorder.callbacks == [.deferredChannelMessageWithSource])
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Saturation is fail-fast and preserves a pending response so it may retry after another owner releases capacity.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func overloadReleasesInitialSlot() async throws {
        let admission = try InteractionAcknowledgementAdmission(maximumConcurrent: 1)
        let reserved = try await admission.acquire(encodedBytes: 1)
        let fixture = try LifecycleFixture(admission: admission)
        await #expect(throws: InteractionLifecycleError.acknowledgementCapacityExceeded) {
            try await fixture.responder.deferResponse()
        }
        #expect(await fixture.responder.snapshot() == .pending)
        await admission.release(reserved)
        try await fixture.responder.deferResponse()
        #expect(await fixture.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        #expect(await admission.snapshot().activeCount == 0)
    }

    /// Exact receipt deadlines are exclusive; passing a real earlier receipt never extends the acknowledgement window.
    /// - Parameter milliseconds: Just before and at/after the three-second deadline.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [2_999, 3_000, 3_001, 900_000]) func initialDeadlines(milliseconds: Int) async throws {
        let fixture = try LifecycleFixture()
        try fixture.clock.advance(by: .milliseconds(milliseconds))
        if milliseconds < 3_000 {
            try await fixture.responder.deferResponse()
            #expect(await fixture.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        } else {
            await #expect(throws: InteractionLifecycleError.deadlineExceeded) { try await fixture.responder.deferResponse() }
            #expect(await fixture.responder.snapshot() == .expired)
            #expect(await fixture.recorder.callbacks.isEmpty)
        }
    }

    /// Future receipt offsets are rejected and a previously elapsed receipt expires despite fresh actor construction.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func receiptValidation() async throws {
        let clock = ManualClock(), source = InteractionClock(clock), interaction = try Self.interaction()
        let sink = InteractionResponseSink(initial: { _, _ in })
        let future = InteractionResponder(interaction: interaction, deliveryMode: .http, clock: source, sink: sink,
            admission: try InteractionAcknowledgementAdmission(), receivedAt: .seconds(1))
        await #expect(throws: InteractionLifecycleError.invalidConfiguration) { try await future.deferResponse() }
        try clock.advance(by: .seconds(4))
        let past = InteractionResponder(interaction: interaction, deliveryMode: .http, clock: source, sink: sink,
            admission: try InteractionAcknowledgementAdmission(), receivedAt: .zero)
        await #expect(throws: InteractionLifecycleError.deadlineExceeded) { try await past.deferResponse() }
    }

    /// Only explicit no-send or complete API rejection evidence reopens the acknowledgement slot.
    /// - Parameter variant: Explicit no-send, 400 API rejection, local validation, or ambiguous failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<6) func initialFailureEvidence(variant: Int) async throws {
        let failure: any Error
        switch variant {
        case 0: failure = InteractionDeliveryError.notSubmitted
        case 1: failure = APIResponseError(status: 400, headers: [], body: Data())
        case 2: failure = DiscordError.validation(.invalidValue)
        case 3: failure = InteractionDeliveryError.indeterminate
        case 4: failure = APIResponseError(status: 503, headers: [], body: Data())
        default: failure = DiscordError.transport(.disconnected)
        }
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in throw failure }))
        await #expect(throws: (any Error).self) { try await fixture.responder.deferResponse() }
        #expect(await fixture.responder.snapshot() == (variant < 3 ? .pending : .indeterminate))
        #expect(await fixture.admission.snapshot().activeCount == 0)
        if variant >= 3 {
            await #expect(throws: InteractionLifecycleError.indeterminateAcknowledgement) { try await fixture.responder.deferResponse() }
            await #expect(throws: InteractionLifecycleError.indeterminateAcknowledgement) {
                try await fixture.responder.followup(InteractionMessageCreate(content: .value("unsafe")))
            }
            try fixture.clock.advance(by: .seconds(900))
            #expect(await fixture.responder.snapshot() == .indeterminate)
        }
    }

    /// Discord's expired/already-acknowledged error codes never reopen the local initial response slot.
    /// - Parameter code: Unknown interaction or acknowledgement previously accepted by another worker.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [10062, 40060]) func serverLifecycleEvidence(code: Int) async throws {
        let failure = APIResponseError(status: 400, headers: [], body: Data("{\"code\":\(code)}".utf8))
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in throw failure }))
        await #expect(throws: (any Error).self) { try await fixture.responder.deferResponse() }
        #expect(await fixture.responder.snapshot() == (code == 10062 ? .expired : .indeterminate))
        await #expect(throws: code == 10062 ? InteractionLifecycleError.deadlineExceeded : .indeterminateAcknowledgement) {
            try await fixture.responder.deferResponse()
        }
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Cancellation before entry causes no I/O; cancellation after adapter entry retains uncertainty and frees resources.
    /// - Parameter afterEntry: Whether cancellation races an already invoked callback adapter.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func cancellation(afterEntry: Bool) async throws {
        let entered = TestBarrier(), blocked = TestBarrier()
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in
            entered.open(); try await blocked.wait()
        }))
        let start = TestBarrier()
        let task = Task {
            if !afterEntry { try await start.wait() }
            try await fixture.responder.deferResponse()
        }
        if afterEntry { try await entered.wait() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fixture.responder.snapshot() == (afterEntry ? .indeterminate : .pending))
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
        #expect(blocked.waitingCount == 0)
    }

    /// Virtual timeout interrupts a cooperative submitted callback and preserves its indeterminate outcome.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func submittedDeadline() async throws {
        let scheduled = TestBarrier(), entered = TestBarrier(), blocked = TestBarrier()
        let clock = ManualClock(onSleepScheduled: scheduled.open)
        let fixture = try LifecycleFixture(clock: clock, sink: InteractionResponseSink(initial: { _, _ in
            entered.open(); try await blocked.wait()
        }))
        let task = Task { try await fixture.responder.deferResponse() }
        try await entered.wait(); try await scheduled.wait()
        try clock.advance(by: .seconds(3))
        await #expect(throws: InteractionLifecycleError.deadlineExceeded) { try await task.value }
        #expect(await fixture.responder.snapshot() == .indeterminate)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(blocked.waitingCount == 0)
    }

    /// Deferred originals complete through explicit PATCH, then support follow-ups/deletion until exact token expiry.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func continuationsAndExpiry() async throws {
        let fixture = try LifecycleFixture()
        let edit = try InteractionMessageEdit(content: .value("done"), deferredResponse: true)
        let message = try InteractionMessageCreate(content: .value("followup"))
        await #expect(throws: InteractionLifecycleError.notAcknowledged) { try await fixture.responder.editOriginal(edit) }
        try await fixture.responder.deferResponse(ephemeral: true)
        await #expect(throws: InteractionLifecycleError.completeDeferredResponseFirst) { try await fixture.responder.followup(message) }
        #expect(try await fixture.responder.editOriginal(edit).id.rawValue == UInt64.max)
        #expect(try await fixture.responder.followup(message).content == "response")
        try fixture.clock.advance(by: .milliseconds(899_999))
        _ = try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("last moment")))
        try await fixture.responder.deleteOriginal()
        await #expect(throws: InteractionLifecycleError.originalResponseUnavailable) { try await fixture.responder.editOriginal(edit) }
        await #expect(throws: InteractionLifecycleError.originalResponseUnavailable) { try await fixture.responder.deleteOriginal() }
        _ = try await fixture.responder.followup(message)
        try fixture.clock.advance(by: .milliseconds(1))
        #expect(await fixture.responder.snapshot() == .expired)
        await #expect(throws: InteractionLifecycleError.tokenExpired) { try await fixture.responder.followup(message) }
        #expect(await fixture.recorder.edits == 2)
        #expect(await fixture.recorder.followups == 2)
        #expect(await fixture.recorder.deletions == 1)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Original-only operations reject callbacks without message resources and false deferred-poll evidence.
    /// - Parameter pong: PONG has no original; immediate message does not establish a deferred original.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func continuationCompatibility(pong: Bool) async throws {
        let fixture = try LifecycleFixture(kind: pong ? 1 : 2)
        if pong { try await fixture.responder.respond(.pong) }
        else { try await fixture.responder.reply(InteractionMessageCreate(content: .value("immediate"))) }
        await #expect(throws: pong ? InteractionLifecycleError.originalResponseUnavailable : .deferredResponseRequired) {
            try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("edit"), deferredResponse: true))
        }
        if pong {
            await #expect(throws: InteractionLifecycleError.originalResponseUnavailable) { try await fixture.responder.deleteOriginal() }
        }
    }

    /// An Activity callback has no original message to edit/delete but may send a normal token-scoped follow-up.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func activityFollowupWithoutOriginal() async throws {
        let fixture = try LifecycleFixture()
        try await fixture.responder.respond(.launchActivity)
        await #expect(throws: InteractionLifecycleError.originalResponseUnavailable) { try await fixture.responder.deleteOriginal() }
        let message = try await fixture.responder.followup(InteractionMessageCreate(content: .value("activity followup")))
        #expect(message.id.rawValue == UInt64.max)
        #expect(await fixture.recorder.followups == 1)
    }

    /// Concurrent continuations fail promptly, and failed edits release local ordering without claiming completion.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func continuationOrderingAndFailure() async throws {
        let entered = TestBarrier(), blocked = TestBarrier()
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in },
            editOriginal: { _, _ in entered.open(); try await blocked.wait(); throw InteractionDeliveryError.indeterminate }))
        try await fixture.responder.deferResponse()
        let task = Task { try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("edit"))) }
        try await entered.wait()
        await #expect(throws: InteractionLifecycleError.continuationInFlight) { try await fixture.responder.deleteOriginal() }
        task.cancel()
        await #expect(throws: DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)) { try await task.value }
        #expect(await fixture.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        await #expect(throws: InteractionLifecycleError.completeDeferredResponseFirst) {
            try await fixture.responder.followup(InteractionMessageCreate(content: .value("after failure")))
        }
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Missing continuation adapters fail explicitly while leaving initial acknowledgement valid and ordering reusable.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func missingContinuationConfiguration() async throws {
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in }))
        try await fixture.responder.reply(InteractionMessageCreate(content: .value("hello")))
        await #expect(throws: DiscordError.capabilityUnavailable(.missingConfiguration)) {
            try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("edit")))
        }
        await #expect(throws: DiscordError.capabilityUnavailable(.missingConfiguration)) {
            try await fixture.responder.followup(InteractionMessageCreate(content: .value("followup")))
        }
        await #expect(throws: DiscordError.capabilityUnavailable(.missingConfiguration)) { try await fixture.responder.deleteOriginal() }
        #expect(await fixture.responder.snapshot() == .acknowledged(.channelMessageWithSource))
    }

    /// Every continuation retains definite rejection/no-send evidence and conservatively classifies ambiguous failures.
    /// - Parameters:
    ///   - operation: Original edit, follow-up creation or original deletion.
    ///   - variant: Local validation, explicit submission evidence, transport/handler failure, server error or API rejection.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<3, 0..<8) func continuationFailureEvidence(operation: Int, variant: Int) async throws {
        let failure: any Error
        switch variant {
        case 0: failure = DiscordError.validation(.invalidValue)
        case 1: failure = InteractionDeliveryError.notSubmitted
        case 2: failure = InteractionDeliveryError.indeterminate
        case 3: failure = DiscordError.transport(.disconnected)
        case 4: failure = LifecycleTestError.handler
        case 5: failure = APIResponseError(status: 503, headers: [], body: Data())
        case 6: failure = APIResponseError(status: 403, headers: [], body: Data())
        default: failure = DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission)
        }
        let fixture = try LifecycleFixture(sink: InteractionResponseSink(initial: { _, _ in },
            editOriginal: { _, _ in throw failure }, followup: { _, _ in throw failure },
            deleteOriginal: { _ in throw failure }))
        try await fixture.responder.reply(InteractionMessageCreate(content: .value("initial")))
        do {
            switch operation {
            case 0: _ = try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("edit")))
            case 1: _ = try await fixture.responder.followup(InteractionMessageCreate(content: .value("followup")))
            default: try await fixture.responder.deleteOriginal()
            }
            Issue.record("Expected injected continuation failure")
        } catch {
            switch variant {
            case 0: #expect(error as? DiscordError == .validation(.invalidValue))
            case 1: #expect(error as? InteractionDeliveryError == .notSubmitted)
            case 2: #expect(error as? InteractionDeliveryError == .indeterminate)
            case 3, 4: #expect(error as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
            case 5, 7: #expect(error as? DiscordError == .unknownMutationOutcome(.serverErrorAfterSubmission))
            default: #expect((error as? APIResponseError)?.status == 403)
            }
        }
        #expect(await fixture.responder.snapshot() == .acknowledged(.channelMessageWithSource))
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// A slow handler receives one early defer with explicit visibility, then completes without retaining timers.
    /// - Parameter update: Tests visible message defer and component-only silent update defer.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func automaticDefer(update: Bool) async throws {
        let scheduled = TestBarrier(), deferred = TestBarrier(), finish = TestBarrier(), recorder = LifecycleRecorder()
        let clock = ManualClock(onSleepScheduled: scheduled.open)
        let fixture = try LifecycleFixture(kind: update ? 3 : 2, includeMessage: update, clock: clock,
            sink: InteractionResponseSink(initial: { response, timeout in
                await recorder.initial(response, timeout: timeout); deferred.open()
            }))
        let policy = try InteractionAutoDeferPolicy(mode: update ? .update : .message(ephemeral: true))
        let task = Task { try await fixture.responder.runWithAutoDefer(policy: policy) {
            try await finish.wait(); return 42
        } }
        try await scheduled.wait(); try clock.advance(by: .seconds(2)); try await deferred.wait()
        for _ in 0..<10_000 {
            if await fixture.responder.snapshot() != .acknowledging { break }
            await Task.yield()
        }
        finish.open(); #expect(try await task.value == 42)
        #expect(await recorder.callbacks == [update ? .deferredUpdateMessage : .deferredChannelMessageWithSource])
        if !update { #expect(await recorder.ephemeral == [true]) }
        #expect(clock.pendingSleepCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// Fast completion/error and manual response races all cancel the early-defer timer with no duplicate delivery.
    /// - Parameter outcome: Handler returns, throws, manually acknowledges, or is cancelled while blocked.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4) func autoDeferHandlerExits(outcome: Int) async throws {
        let scheduled = TestBarrier(), entered = TestBarrier(), blocked = TestBarrier()
        let clock = ManualClock(onSleepScheduled: scheduled.open)
        let fixture = try LifecycleFixture(clock: clock)
        let policy = try InteractionAutoDeferPolicy(mode: .message(ephemeral: false))
        let task = Task { try await fixture.responder.runWithAutoDefer(policy: policy) {
            entered.open()
            if outcome == 1 { throw LifecycleTestError.handler }
            if outcome == 2 { try await fixture.responder.reply(InteractionMessageCreate(content: .value("manual"))) }
            if outcome == 3 { try await blocked.wait() }
            return 7
        } }
        try await entered.wait()
        if outcome == 3 { try await scheduled.wait(); task.cancel() }
        if outcome == 1 { await #expect(throws: LifecycleTestError.handler) { try await task.value } }
        else if outcome == 3 { await #expect(throws: CancellationError.self) { try await task.value } }
        else { #expect(try await task.value == 7) }
        #expect(await fixture.recorder.callbacks.count == (outcome == 2 ? 1 : 0))
        #expect(clock.pendingSleepCount == 0)
        #expect(blocked.waitingCount == 0)
    }

    /// Handler failure/cancellation after a confirmed automatic defer preserves acknowledgement and cleans all timer children.
    /// - Parameter cancel: True cancels the owner; false throws the handler's original error after acknowledgement.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func handlerFailureAfterDefer(cancel: Bool) async throws {
        let scheduled = TestBarrier(), accepted = TestBarrier(), finish = TestBarrier(), recorder = LifecycleRecorder()
        let clock = ManualClock(onSleepScheduled: scheduled.open)
        let fixture = try LifecycleFixture(clock: clock, sink: InteractionResponseSink(initial: { response, timeout in
            await recorder.initial(response, timeout: timeout); accepted.open()
        }))
        let policy = try InteractionAutoDeferPolicy(mode: .message(ephemeral: true))
        let task = Task { try await fixture.responder.runWithAutoDefer(policy: policy) {
            try await finish.wait()
            if !cancel { throw LifecycleTestError.handler }
            return 0
        } }
        try await scheduled.wait(); try clock.advance(by: .seconds(2)); try await accepted.wait()
        for _ in 0..<10_000 {
            if await fixture.responder.snapshot() != .acknowledging { break }
            await Task.yield()
        }
        if cancel { task.cancel() } else { finish.open() }
        if cancel { await #expect(throws: CancellationError.self) { try await task.value } }
        else { await #expect(throws: LifecycleTestError.handler) { try await task.value } }
        #expect(await fixture.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        #expect(await recorder.callbacks == [.deferredChannelMessageWithSource])
        #expect(clock.pendingSleepCount == 0)
        #expect(finish.waitingCount == 0)
    }

    /// Expiry during a continuation cancels its cooperative adapter and subsequent calls fail before another submission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func tokenExpiresDuringContinuation() async throws {
        let scheduled = TestBarrier(), entered = TestBarrier(), blocked = TestBarrier()
        let clock = ManualClock(onSleepScheduled: scheduled.open)
        let fixture = try LifecycleFixture(clock: clock, sink: InteractionResponseSink(initial: { _, _ in },
            editOriginal: { _, _ in entered.open(); try await blocked.wait(); throw LifecycleTestError.handler }))
        try await fixture.responder.deferResponse()
        try clock.advance(by: .seconds(899))
        let task = Task { try await fixture.responder.editOriginal(InteractionMessageEdit(content: .value("slow"))) }
        try await entered.wait()
        for _ in 0..<10_000 {
            if clock.pendingSleepCount > 0 { break }
            await Task.yield()
        }
        try clock.advance(by: .seconds(1))
        await #expect(throws: DiscordError.unknownMutationOutcome(.deadlineAfterSubmission)) { try await task.value }
        #expect(await fixture.responder.snapshot() == .expired)
        await #expect(throws: InteractionLifecycleError.tokenExpired) { try await fixture.responder.deleteOriginal() }
        #expect(clock.pendingSleepCount == 0)
        #expect(blocked.waitingCount == 0)
    }

    /// Autocomplete/PING/future kinds are never auto-deferred, and missing source-message update policy fails early.
    /// - Parameter kind: Incompatible kinds and a component without the original message snapshot.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [1, 3, 4, 99]) func invalidAutoDefer(kind: Int) async throws {
        let fixture = try LifecycleFixture(kind: kind)
        let policy = try InteractionAutoDeferPolicy(mode: kind == 3 ? .update : .message(ephemeral: false))
        await #expect(throws: (any Error).self) {
            try await fixture.responder.runWithAutoDefer(policy: policy) {
                Issue.record("Incompatible policy must not invoke handler")
            }
        }
        #expect(await fixture.recorder.callbacks.isEmpty)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// One response owner runs at most one auto-defer handler/timer pair, and cancellation releases that bound.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func autoDeferOwnerBound() async throws {
        let fixture = try LifecycleFixture(), entered = TestBarrier(), blocked = TestBarrier()
        let policy = try InteractionAutoDeferPolicy(mode: .message(ephemeral: false))
        let owner = Task { try await fixture.responder.runWithAutoDefer(policy: policy) {
            entered.open(); try await blocked.wait()
        } }
        try await entered.wait()
        await #expect(throws: InteractionLifecycleError.handlerAlreadyRunning) {
            try await fixture.responder.runWithAutoDefer(policy: policy) { Issue.record("Second handler must not run") }
        }
        owner.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        #expect(try await fixture.responder.runWithAutoDefer(policy: policy) { 9 } == 9)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Builds bounded realistic interaction input with exact snowflakes and required non-PING context metadata.
    /// - Parameters:
    ///   - kind: Current or future integral interaction kind, default command.
    ///   - includeMessage: Whether input carries the source message required by update acknowledgements.
    ///   - id: Decimal interaction identifier, default maximum UInt64.
    ///   - applicationID: Decimal owning application identifier.
    ///   - token: Synthetic continuation secret used only for ownership matching.
    /// - Returns: Presence-aware parsed snapshot retaining exact IDs.
    /// - Throws: Fixture JSON/model validation failures.
    static func interaction(kind: Int = 2, includeMessage: Bool = false,
        id: String = "18446744073709551615", applicationID: String = "9", token: String = "test-token") throws -> Interaction {
        let data: String = switch kind {
        case 2, 4: #"{"id":"3","name":"command","type":1}"#
        case 3: #"{"custom_id":"button","component_type":2}"#
        case 5: #"{"custom_id":"modal","components":[]}"#
        default: "{}"
        }
        let message = includeMessage ? ",\"message\":" + messageJSON : ""
        return try Interaction(data: Data("{\"id\":\"\(id)\",\"application_id\":\"\(applicationID)\",\"type\":\(kind),\"token\":\"\(token)\",\"version\":1,\"data\":\(data),\"app_permissions\":\"0\",\"entitlements\":[],\"authorizing_integration_owners\":{},\"attachment_size_limit\":1048576\(message)}".utf8))
    }

    static let messageJSON = #"{"id":"18446744073709551615","channel_id":"4","author":{"id":"5","username":"user","discriminator":"0","avatar":null},"content":"response","timestamp":"2026-10-16T12:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":20}"#
}

/// Closed synthetic handler failure used to check exact propagation through structured auto-defer ownership.
private enum LifecycleTestError: Error { case handler }

/// Per-test sink recorder; actors make counters independent of scheduling or parallel suite execution.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor LifecycleRecorder {
    var callbacks: [InteractionCallbackType] = []
    var timeouts: [Duration] = []
    var ephemeral: [Bool] = []
    var edits = 0
    var followups = 0
    var deletions = 0

    /// Records an accepted synthetic initial callback without external side effects.
    /// - Parameters:
    ///   - response: Exact callback whose type and ephemeral defer flag are asserted by callers.
    ///   - timeout: Remaining monotonic deadline budget passed to the adapter.
    func initial(_ response: InteractionResponse, timeout: Duration) {
        callbacks.append(response.type); timeouts.append(timeout)
        if case .deferredMessage(let visibility) = response { ephemeral.append(visibility) }
    }

    /// Counts an original edit and returns a realistic complete message fixture.
    /// - Returns: The same parsed immutable message snapshot on each invocation.
    /// - Throws: Fixture model validation failure.
    func edit() throws -> Message { edits += 1; return try Message(data: Data(InteractionLifecycleTests.messageJSON.utf8)) }

    /// Counts one follow-up and returns its complete message fixture.
    /// - Returns: A realistic message containing maximum-width identifier.
    /// - Throws: Fixture model validation failure.
    func followup() throws -> Message { followups += 1; return try Message(data: Data(InteractionLifecycleTests.messageJSON.utf8)) }

    /// Counts one confirmed original deletion without retaining message content.
    func delete() { deletions += 1 }
}

/// Bundles isolated virtual time, response state, admission and recorded adapter behavior for one test.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct LifecycleFixture {
    let clock: ManualClock
    let interaction: Interaction
    let admission: InteractionAcknowledgementAdmission
    let responder: InteractionResponder
    let recorder: LifecycleRecorder

    /// Creates independent fixture owners without tasks or real network activity.
    /// - Parameters:
    ///   - mode: Configured delivery channel, default HTTP.
    ///   - kind: Interaction discriminator, default application command.
    ///   - includeMessage: Whether source-message context exists for update callbacks.
    ///   - clock: Optional shared clock for explicit scheduling gates.
    ///   - sink: Optional injected failure/suspension adapter; nil records all successful operations.
    ///   - admission: Optional shared aggregate authority for overload scenarios.
    /// - Throws: Fixture parsing or admission configuration errors.
    init(mode: InteractionDeliveryMode = .http, kind: Int = 2, includeMessage: Bool = false,
        clock: ManualClock? = nil, sink: InteractionResponseSink? = nil,
        admission: InteractionAcknowledgementAdmission? = nil) throws {
        let time = clock ?? ManualClock(), recorder = LifecycleRecorder()
        let input = try InteractionLifecycleTests.interaction(kind: kind, includeMessage: includeMessage)
        let authority = try admission ?? InteractionAcknowledgementAdmission()
        self.clock = time; self.interaction = input; self.admission = authority; self.recorder = recorder
        responder = InteractionResponder(interaction: input, deliveryMode: mode, clock: InteractionClock(time),
            sink: sink ?? InteractionResponseSink(initial: { await recorder.initial($0, timeout: $1) },
                editOriginal: { _, _ in try await recorder.edit() }, followup: { _, _ in try await recorder.followup() },
                deleteOriginal: { _ in await recorder.delete() }), admission: authority)
    }
}
