// File: Sources/DiscordInteractions/InteractionResponder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Public response ownership state. In-flight acknowledgement reserves the single initial slot before
/// any actor suspension; indeterminate submission never becomes an invented rejection or automatic retry.
public enum InteractionResponseState: Sendable, Equatable {
    case pending
    case acknowledging
    case acknowledged(InteractionCallbackType)
    case indeterminate
    case expired
}

/// Explicit early-defer semantics. Message mode fixes ephemeral visibility at acknowledgement time;
/// update mode acknowledges a component's existing message without displaying a loading response.
public struct InteractionAutoDeferPolicy: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case message(ephemeral: Bool)
        case update
    }
    public let delay: Duration
    public let mode: Mode

    /// Validates an early acknowledgement time; actual trigger compatibility is checked before handler execution.
    /// - Parameters:
    ///   - delay: Positive receipt-relative delay strictly below three seconds, default two seconds.
    ///   - mode: Explicit public/ephemeral message visibility or existing-message update semantics.
    /// - Throws: `InteractionLifecycleError.invalidConfiguration` for zero, negative or late delays.
    public init(delay: Duration = .seconds(2), mode: Mode) throws {
        guard delay > .zero, delay < .seconds(3) else { throw InteractionLifecycleError.invalidConfiguration }
        self.delay = delay; self.mode = mode
    }
}

/// Per-interaction actor owning Discord's single acknowledgement and fifteen-minute continuation lifetime.
/// Receipt time is captured explicitly, construction performs no I/O, and handler/cache work never runs on
/// a Gateway control executor. No method extends token life or reconciles an ambiguous submission silently.
public actor InteractionResponder: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private nonisolated let interaction: Interaction
    public nonisolated let deliveryMode: InteractionDeliveryMode
    private let clock: InteractionClock
    private let sink: InteractionResponseSink
    private let admission: InteractionAcknowledgementAdmission
    private let receivedAt: Duration
    private let acknowledgementDeadline: Duration
    private let tokenDeadline: Duration
    private var state: InteractionResponseState = .pending
    private var continuationInFlight = false
    private var originalDeleted = false
    private var deferredCompleted = false
    private var handlerRunning = false

    /// Conceals raw interaction fields, continuation tokens and injected response mechanics from diagnostics.
    public nonisolated var description: String { "InteractionResponder(redacted)" }
    /// Uses the same safe marker during debugger formatting without actor suspension.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflective traversal into stored interaction content or callback captures.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Creates an idle actor without tasks, timers, admission reservations or network requests.
    /// - Parameters:
    ///   - interaction: Authenticated HTTP input or trusted Gateway snapshot, including its exact path credential.
    ///   - deliveryMode: Selected receipt mode; `.gateway` still requires an HTTP initial-response sink.
    ///   - clock: Shared monotonic receipt/response clock, with a single stable origin.
    ///   - sink: Injected callback and continuation mechanics; caller owns shared transport cleanup.
    ///   - admission: Shared bounded initial-only authority, independently owned from ordinary REST admission.
    ///   - receivedAt: Receipt offset in `clock`'s domain; nil captures now. Pass actual receipt time after slow ingress.
    ///     Future values are rejected on first operation rather than granting a later deadline.
    public init(interaction: Interaction, deliveryMode: InteractionDeliveryMode, clock: InteractionClock,
        sink: InteractionResponseSink, admission: InteractionAcknowledgementAdmission, receivedAt: Duration? = nil) {
        self.interaction = interaction; self.deliveryMode = deliveryMode; self.clock = clock
        self.sink = sink; self.admission = admission
        let receipt = receivedAt ?? clock.now
        self.receivedAt = receipt; acknowledgementDeadline = receipt + .seconds(3)
        tokenDeadline = receipt + .seconds(900)
    }

    /// Checks that a normalized context cannot accidentally use another interaction's continuation authority.
    /// - Parameters:
    ///   - candidate: Snapshot requiring exact ID, application ID and secret equality.
    ///   - deliveryMode: Configured application delivery channel.
    /// - Returns: Whether both values refer to this exact response owner, without I/O or actor suspension.
    nonisolated func matches(_ candidate: Interaction, deliveryMode: InteractionDeliveryMode) -> Bool {
        candidate.id == interaction.id && candidate.applicationID == interaction.applicationID &&
            candidate.token.withUnsafeValue { left in interaction.token.withUnsafeValue { left == $0 } } &&
            deliveryMode == self.deliveryMode
    }

    /// Reports current acknowledgement ownership, applying local receipt/token expiry without network requests.
    /// - Returns: Pending, reserved, confirmed, uncertain or expired state; uncertainty is retained after expiry.
    public func snapshot() -> InteractionResponseState {
        updateExpiry()
        return state
    }

    /// Sends one validated initial callback through independently bounded acknowledgement admission.
    /// - Parameter response: Any current typed callback; trigger compatibility and payload validation precede I/O.
    /// - Throws: Validation, unsupported future kind, duplicate/in-flight acknowledgement, overload, cancellation,
    ///   deadline or sink failure. Unknown failures after invoking the sink leave `.indeterminate` permanently;
    ///   explicit not-submitted evidence and complete non-5xx API rejection release the initial slot for retry.
    ///   Discord error 10062 closes the expired token; 40060 retains unknown remote acknowledgement ownership.
    ///   At the exact three-second boundary a pending callback fails locally and its token is treated as expired.
    public func respond(_ response: InteractionResponse) async throws {
        DiscordLog.makeLogger("interactions.response").debug("Initial response processing started", metadata: ["dk.event": "interactions.response.started", "dk.callback_type": .stringConvertible(response.type.rawValue)])
        do {
            try Task.checkCancellation()
            try validateReceipt()
            updateExpiry()
            switch state {
            case .pending: break
            case .acknowledging: throw InteractionLifecycleError.initialResponseInFlight
            case .acknowledged: throw InteractionLifecycleError.alreadyAcknowledged
            case .indeterminate: throw InteractionLifecycleError.indeterminateAcknowledgement
            case .expired: throw InteractionLifecycleError.deadlineExceeded
            }
            guard let kind = interaction.type.knownValue else { throw InteractionLifecycleError.unsupportedInteraction }
            if response.type == .deferredUpdateMessage || response.type == .updateMessage {
                guard case .value = interaction.message else { throw InteractionLifecycleError.originalResponseUnavailable }
            }
            let bytes = try response.jsonValue(interactionType: kind).serialized().count
            DiscordLog.makeLogger("interactions.response").trace("Initial response validated and encoded", metadata: ["dk.event": "interactions.response.validated", "dk.bytes": .stringConvertible(bytes)])
            state = .acknowledging
            DiscordLog.makeLogger("interactions.response").trace("Initial interaction response reserved", metadata: ["dk.event": "interactions.response.reserved"])
            let reservation: UUID
            do {
                reservation = try await admission.acquire(encodedBytes: bytes)
                DiscordLog.makeLogger("interactions.response").trace("Acknowledgement admission acquired", metadata: ["dk.event": "interactions.response.admission_acquired"])
            } catch {
                // A failed acquisition never enters the delivery sink.
                state = .pending; updateExpiry()
                DiscordLog.makeLogger("interactions.response").debug("Acknowledgement admission rejected before delivery", metadata: ["dk.event": "interactions.response.admission_rejected"])
                throw error
            }
            do {
                try Task.checkCancellation()
                guard clock.now < acknowledgementDeadline else { throw InteractionLifecycleError.deadlineExceeded }
            } catch {
                state = .pending; updateExpiry(); await admission.release(reservation)
                DiscordLog.makeLogger("interactions.response").trace("Acknowledgement admission released before delivery", metadata: ["dk.event": "interactions.response.released_before_delivery"])
                throw error
            }
            do {
                let timeout = acknowledgementDeadline - clock.now
                DiscordLog.makeLogger("interactions.response").trace("Invoking initial response delivery sink", metadata: ["dk.event": "interactions.response.delivering"])
                try await clock.run(until: acknowledgementDeadline) {
                    try await InteractionFailureScope.withResponseStage(.acknowledgement) {
                        try await self.sink.initial(response, timeout)
                    }
                }
                state = .acknowledged(response.type)
                DiscordLog.makeLogger("interactions.response").debug("Initial interaction response acknowledged", metadata: ["dk.event": "interactions.response.acknowledged", "dk.callback_type": .stringConvertible(response.type.rawValue)])
                await admission.release(reservation)
                DiscordLog.makeLogger("interactions.response").trace("Acknowledgement admission released", metadata: ["dk.event": "interactions.response.admission_released"])
                await InteractionFailureScope.clear()
            } catch {
                state = stateAfterInitialFailure(error)
                DiscordLog.makeLogger("interactions.response").debug("Initial interaction response failed", metadata: ["dk.event": "interactions.response.failed"])
                if state == .indeterminate {
                    DiscordLog.makeLogger("interactions.response").warning("Initial response delivery outcome is uncertain", metadata: ["dk.event": "interactions.response.indeterminate"])
                }
                updateExpiry()
                await admission.release(reservation)
                DiscordLog.makeLogger("interactions.response").trace("Failed acknowledgement admission released", metadata: ["dk.event": "interactions.response.admission_released"])
                throw error
            }
        } catch {
            DiscordLog.makeLogger("interactions.response").debug("Initial response processing stopped", metadata: ["dk.event": "interactions.response.stopped"])
            await InteractionFailureScope.record(error, at: .acknowledgement)
            throw error
        }
    }

    /// Sends an immediate initial message. After manual/automatic defer, complete it with `editOriginal(_:)`.
    /// - Parameter message: Validated JSON-only callback message with explicit mentions/visibility as desired.
    /// - Throws: The same validation, admission, lifecycle and transport failures as `respond(_:)`.
    public func reply(_ message: InteractionMessageCreate) async throws { try await respond(.message(message)) }

    /// Acknowledges a command/component/modal with a loading response whose visibility cannot later change.
    /// - Parameter ephemeral: True limits the original response to its invoker; default false is public.
    /// - Throws: Incompatible PING/autocomplete/unknown kinds or the failures documented by `respond(_:)`.
    public func deferResponse(ephemeral: Bool = false) async throws { try await respond(.deferredMessage(ephemeral: ephemeral)) }

    /// Acknowledges a component or message-associated modal without a visible loading response.
    /// - Throws: Missing source message, incompatible kind or the failures documented by `respond(_:)`.
    public func deferUpdate() async throws { try await respond(.deferredUpdate) }

    /// Edits an existing original response or completes an explicitly acknowledged defer.
    /// - Parameter request: Validated edit; `deferredResponse=true` is legal only after deferred-message acknowledgement.
    /// - Returns: Discord's updated message; a snapshot never extends the token's fifteen-minute deadline.
    /// - Throws: Unacknowledged/uncertain/expired state, unavailable original, concurrent continuation, validation,
    ///   cancellation or REST failure. Cancellation/deadline after adapter entry remains an explicit unknown mutation
    ///   outcome. Ambiguous edits propagate without changing the confirmed initial state or completing a defer locally.
    public func editOriginal(_ request: InteractionMessageEdit) async throws -> Message {
        DiscordLog.makeLogger("interactions.response").debug("Original response edit started", metadata: ["dk.event": "interactions.response.edit_started"])
        do {
            let kind = try reserveContinuation(requireOriginal: true)
            defer {
                continuationInFlight = false
                DiscordLog.makeLogger("interactions.response").trace("Response edit continuation released", metadata: ["dk.event": "interactions.response.continuation_released"])
            }
            if request.deferredResponse, kind != .deferredChannelMessageWithSource {
                throw InteractionLifecycleError.deferredResponseRequired
            }
            _ = try request.jsonValue()
            DiscordLog.makeLogger("interactions.response").trace("Original response edit validated", metadata: ["dk.event": "interactions.response.edit_validated"])
            let timeout = tokenDeadline - clock.now
            let result = try await performContinuation { try await self.sink.edit(request, timeout) }
            deferredCompleted = true
            DiscordLog.makeLogger("interactions.response").debug("Original response edit completed", metadata: ["dk.event": "interactions.response.edit_completed"])
            await InteractionFailureScope.clear()
            return result
        } catch {
            await InteractionFailureScope.record(error, at: .continuation)
            throw error
        }
    }

    /// Creates a new follow-up only after the deferred original has been explicitly completed.
    /// - Parameter request: Validated JSON-only follow-up; Discord checks user-install quota and permissions.
    /// - Returns: Newly created message. No deprecated implicit edit-original fallback is invoked.
    /// - Throws: Lifecycle/expiry/overlap errors, incomplete deferred original, validation or REST failure.
    ///   Cancellation, deadline or transport loss after adapter entry remains an explicit unknown mutation outcome.
    public func followup(_ request: InteractionMessageCreate) async throws -> Message {
        DiscordLog.makeLogger("interactions.response").debug("Follow-up response started", metadata: ["dk.event": "interactions.response.followup_started"])
        do {
            let kind = try reserveContinuation(requireOriginal: false)
            defer {
                continuationInFlight = false
                DiscordLog.makeLogger("interactions.response").trace("Follow-up continuation released", metadata: ["dk.event": "interactions.response.continuation_released"])
            }
            guard kind != .deferredChannelMessageWithSource || deferredCompleted || originalDeleted else {
                throw InteractionLifecycleError.completeDeferredResponseFirst
            }
            _ = try request.jsonValue()
            DiscordLog.makeLogger("interactions.response").trace("Follow-up response validated", metadata: ["dk.event": "interactions.response.followup_validated"])
            let timeout = tokenDeadline - clock.now
            let result = try await performContinuation { try await self.sink.followup(request, timeout) }
            await InteractionFailureScope.clear()
            DiscordLog.makeLogger("interactions.response").debug("Follow-up response completed", metadata: ["dk.event": "interactions.response.followup_completed"])
            return result
        } catch {
            await InteractionFailureScope.record(error, at: .continuation)
            throw error
        }
    }

    /// Deletes the original response once; confirmed deletion prevents later local original edits/deletes.
    /// - Throws: Lifecycle/expiry/overlap errors, absent original, cancellation or REST failure. An ambiguous
    ///   deletion is surfaced as explicit mutation uncertainty and does not invent local confirmed deletion.
    public func deleteOriginal() async throws {
        DiscordLog.makeLogger("interactions.response").debug("Original response deletion started", metadata: ["dk.event": "interactions.response.delete_started"])
        do {
            _ = try reserveContinuation(requireOriginal: true)
            defer {
                continuationInFlight = false
                DiscordLog.makeLogger("interactions.response").trace("Original deletion continuation released", metadata: ["dk.event": "interactions.response.continuation_released"])
            }
            let timeout = tokenDeadline - clock.now
            try await performContinuation { try await self.sink.delete(timeout) }
            originalDeleted = true
            DiscordLog.makeLogger("interactions.response").debug("Original response deletion completed", metadata: ["dk.event": "interactions.response.delete_completed"])
            await InteractionFailureScope.clear()
        } catch {
            await InteractionFailureScope.record(error, at: .continuation)
            throw error
        }
    }

    /// Runs a handler with an explicitly owned early-defer timer and awaits cancellation cleanup on every exit.
    /// - Parameters:
    ///   - policy: Receipt-relative delay and explicit visibility/update semantics; incompatible kinds fail before handler work.
    ///   - operation: Handler that uses `editOriginal(_:)` after deferral. Its errors propagate unchanged; automatic defer
    ///     does not invent success or swallow failures. Both handler and injected sinks must honor cancellation.
    /// - Returns: Handler result, after cancelling and joining the timer. Successful defer does not end handler execution.
    /// - Throws: Invalid/incompatible policy, handler error, defer failure or cancellation. A concurrent manual response
    ///   wins its reserved slot; the timer then performs no second initial callback.
    public func runWithAutoDefer<Value: Sendable>(policy: InteractionAutoDeferPolicy,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let response: InteractionResponse = switch policy.mode {
        case .message(let ephemeral): .deferredMessage(ephemeral: ephemeral)
        case .update: .deferredUpdate
        }
        do {
            try Task.checkCancellation()
            try validateReceipt()
            updateExpiry()
            if state == .expired { throw InteractionLifecycleError.tokenExpired }
            if state == .indeterminate { throw InteractionLifecycleError.indeterminateAcknowledgement }
            guard !handlerRunning else { throw InteractionLifecycleError.handlerAlreadyRunning }
            guard let kind = interaction.type.knownValue else { throw InteractionLifecycleError.unsupportedInteraction }
            _ = try response.jsonValue(interactionType: kind)
            if policy.mode == .update, case .absent = interaction.message {
                throw InteractionLifecycleError.originalResponseUnavailable
            }
        } catch {
            await InteractionFailureScope.record(error, at: .acknowledgement)
            throw error
        }
        handlerRunning = true
        DiscordLog.makeLogger("interactions.response").trace("Automatic deferral timer and handler started", metadata: ["dk.event": "interactions.response.auto_defer_started"])
        defer {
            handlerRunning = false
            DiscordLog.makeLogger("interactions.response").trace("Automatic deferral children joined", metadata: ["dk.event": "interactions.response.auto_defer_joined"])
        }
        return try await withThrowingTaskGroup(of: AutoDeferResult<Value>.self) { group in
            group.addTask { .handled(try await operation()) }
            group.addTask {
                try await self.clock.sleep(until: self.receivedAt + policy.delay)
                try Task.checkCancellation()
                try await self.autoDefer(response)
                return .deferred
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if case .handled(let value) = result { return value }
            }
            throw CancellationError()
        }
    }

    /// Gives the timer a best-effort initial slot without racing an already reserved/manual acknowledgement.
    /// - Parameter response: Callback already validated against the interaction type.
    /// - Throws: Only active pending-response delivery/admission failures; a manual winner is left untouched.
    private func autoDefer(_ response: InteractionResponse) async throws {
        guard state == .pending else {
            DiscordLog.makeLogger("interactions.response").trace("Automatic deferral skipped after manual response reservation", metadata: ["dk.event": "interactions.response.auto_defer_skipped"])
            return
        }
        DiscordLog.makeLogger("interactions.response").trace("Automatic deferral timer claimed pending response", metadata: ["dk.event": "interactions.response.auto_defer_triggered"])
        try await respond(response)
    }

    /// Rejects impossible future receipt offsets rather than extending protocol deadlines.
    /// - Throws: Invalid configuration when receipt is after the injected monotonic current time.
    private func validateReceipt() throws {
        guard receivedAt <= clock.now else { throw InteractionLifecycleError.invalidConfiguration }
    }

    /// Applies local protocol expiry without erasing submission uncertainty or an active initial reservation.
    private func updateExpiry() {
        if state == .pending, clock.now >= acknowledgementDeadline {
            state = .expired
            DiscordLog.makeLogger("interactions.response").debug("Initial acknowledgement deadline expired", metadata: ["dk.event": "interactions.response.acknowledgement_expired"])
        }
        if case .acknowledged = state, clock.now >= tokenDeadline {
            state = .expired
            DiscordLog.makeLogger("interactions.response").debug("Response continuation token expired", metadata: ["dk.event": "interactions.response.token_expired"])
        }
    }

    /// Checks token/original ownership and reserves mutation ordering before the next actor suspension.
    /// - Parameter requireOriginal: True rejects callbacks without an original message or confirmed deletion.
    /// - Returns: Confirmed original callback kind used to enforce deferred completion behavior.
    /// - Throws: Cancellation or safe lifecycle errors, without invoking a sink or changing remote state.
    private func reserveContinuation(requireOriginal: Bool) throws -> InteractionCallbackType {
        try Task.checkCancellation(); try validateReceipt(); updateExpiry()
        guard clock.now < tokenDeadline else { throw InteractionLifecycleError.tokenExpired }
        let kind: InteractionCallbackType
        switch state {
        case .acknowledged(let acknowledged): kind = acknowledged
        case .indeterminate: throw InteractionLifecycleError.indeterminateAcknowledgement
        case .acknowledging: throw InteractionLifecycleError.initialResponseInFlight
        case .expired: throw InteractionLifecycleError.tokenExpired
        case .pending: throw InteractionLifecycleError.notAcknowledged
        }
        let messageKinds: Set<InteractionCallbackType> = [.channelMessageWithSource, .deferredChannelMessageWithSource,
            .deferredUpdateMessage, .updateMessage]
        if requireOriginal {
            guard messageKinds.contains(kind), !originalDeleted else { throw InteractionLifecycleError.originalResponseUnavailable }
        } else if kind == .pong || kind == .applicationCommandAutocompleteResult {
            throw InteractionLifecycleError.originalResponseUnavailable
        }
        guard !continuationInFlight else { throw InteractionLifecycleError.continuationInFlight }
        continuationInFlight = true
        DiscordLog.makeLogger("interactions.response").trace("Response continuation reserved", metadata: ["dk.event": "interactions.response.continuation_reserved", "dk.requires_original": .stringConvertible(requireOriginal)])
        return kind
    }

    /// Executes one reserved continuation with conservative mutation evidence around the outer deadline race.
    /// - Parameter operation: Cancellation-cooperative mutation adapter; definite rejections must carry typed evidence.
    /// - Returns: Confirmed adapter result before token expiry.
    /// - Throws: Existing typed API/validation/capability/mutation-evidence failures unchanged. Outer cancellation,
    ///   deadline, arbitrary adapter failures and unsafe 5xx replies become explicit unknown-mutation-outcome errors;
    ///   no retry is attempted and the caller must reconcile before repeating a potentially applied operation.
    private func performContinuation<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        do {
            DiscordLog.makeLogger("interactions.response").trace("Invoking response continuation sink", metadata: ["dk.event": "interactions.response.continuation_delivering"])
            return try await clock.run(until: tokenDeadline) {
                try await InteractionFailureScope.withResponseStage(.continuation, operation: operation)
            }
        }
        catch {
            DiscordLog.makeLogger("interactions.response").debug("Response continuation delivery failed", metadata: ["dk.event": "interactions.response.continuation_failed"])
            await InteractionFailureScope.recordOwnerFailure(error, at: .continuation)
            if let typed = error as? DiscordError {
                switch typed {
                case .cancelled: throw DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)
                case .transport(.deadlineExceeded): throw DiscordError.unknownMutationOutcome(.deadlineAfterSubmission)
                case .transport: throw DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)
                case .api(let status, _) where (500...599).contains(status):
                    throw DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission)
                default: throw typed
                }
            }
            if let evidence = error as? InteractionDeliveryError { throw evidence }
            if let api = error as? APIResponseError {
                if (500...599).contains(api.status) {
                    throw DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission)
                }
                throw api
            }
            if error is CancellationError { throw DiscordError.unknownMutationOutcome(.cancelledAfterSubmission) }
            if (error as? InteractionLifecycleError) == .deadlineExceeded {
                throw DiscordError.unknownMutationOutcome(.deadlineAfterSubmission)
            }
            throw DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)
        }
    }

    /// Classifies positive rejection evidence while retaining known remote acknowledgement/expiry signals.
    /// - Parameter error: Adapter error; arbitrary error text is never logged or retained.
    /// - Returns: Pending only for explicit no-send/rejection evidence; known expired tokens become expired,
    ///   already acknowledged remote state becomes indeterminate, and ambiguous failures remain indeterminate.
    private func stateAfterInitialFailure(_ error: any Error) -> InteractionResponseState {
        if (error as? InteractionDeliveryError) == .notSubmitted { return .pending }
        if let api = error as? APIResponseError {
            if api.code == 10062 { return .expired }
            if api.code == 40060 { return .indeterminate }
            if (400...499).contains(api.status) { return .pending }
        }
        if case .validation = error as? DiscordError { return .pending }
        return .indeterminate
    }
}

/// Task-group events keep a completed timer distinct from the handler's generic result.
private enum AutoDeferResult<Value: Sendable>: Sendable {
    case handled(Value)
    case deferred
}
