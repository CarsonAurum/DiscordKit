// File: Sources/DiscordInteractions/InteractionOperationFailure.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordTransport

/// Package-only operation provenance captured at its original invocation boundary.
package enum InteractionOperationStage: Sendable, Equatable {
    case preparation
    case handler
    case acknowledgement
    case continuation
}

/// Closed owner evidence preserved before continuation uncertainty mapping obscures its source.
package enum InteractionOwnerFailure: Sendable, Equatable {
    case rateLimit(RateLimitFailure)
    case transport(TransportFailure)

    /// Selects only terminal owner/configuration failures, without inspecting arbitrary error content.
    /// - Parameter error: Original continuation failure before its public mutation-uncertainty translation.
    init?(_ error: any Error) {
        if let error = error as? RateLimitFailure {
            switch error {
            case .closed, .invalidRequest, .unknownReservation, .coordinatorUnavailable: self = .rateLimit(error)
            default: return nil
            }
        } else if let error = error as? TransportFailure {
            switch error {
            case .closed, .concurrentRead, .invalidLimit, .scriptExhausted: self = .transport(error)
            default: return nil
            }
        } else { return nil }
    }

    /// Converts closed cross-layer owner evidence without importing any runtime owner into Transport.
    /// - Parameter failure: Safe category captured before HTTP public-error normalization.
    init(_ failure: InvocationOwnerFailure) {
        switch failure {
        case .rateLimitClosed: self = .rateLimit(.closed)
        case .rateLimitInvalidRequest: self = .rateLimit(.invalidRequest)
        case .rateLimitUnknownReservation: self = .rateLimit(.unknownReservation)
        case .rateLimitCoordinatorUnavailable: self = .rateLimit(.coordinatorUnavailable)
        case .transportClosed: self = .transport(.closed)
        case .transportConcurrentRead: self = .transport(.concurrentRead)
        case .transportInvalidLimit: self = .transport(.invalidLimit)
        case .transportScriptExhausted: self = .transport(.scriptExhausted)
        }
    }
}

/// Carries the escaping error only between owned package layers, with redacted diagnostic formatting.
/// Public observers must receive a separately classified value and never this underlying error.
package struct InteractionOperationFailure: Error, Sendable, CustomStringConvertible, CustomReflectable {
    package let stage: InteractionOperationStage
    package let underlying: any Error
    package let ownerFailure: InteractionOwnerFailure?

    /// Retains one escaping error without evaluating its description or reflective contents.
    /// - Parameters:
    ///   - stage: Outer boundary or a matching safe observation from a response operation.
    ///   - underlying: Escaping error for existing caller error semantics.
    ///   - ownerFailure: Optional closed terminal owner evidence captured before public error translation.
    package init(stage: InteractionOperationStage, underlying: any Error, ownerFailure: InteractionOwnerFailure? = nil) {
        self.stage = stage
        self.underlying = underlying
        self.ownerFailure = ownerFailure
    }

    /// Conceals arbitrary error content during ordinary formatting.
    package var description: String { "InteractionOperationFailure(redacted)" }

    /// Prevents reflective traversal into an injected error or captured sensitive values.
    package var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Opt-in caller-task instrumentation; ordinary HTTP and direct router calls retain their original errors.
package enum InteractionFailureScope {
    @TaskLocal package static var captureOperationFailures = false
    @TaskLocal private static var recorder: InteractionOperationRecorder?
    @TaskLocal private static var responseStage: InteractionOperationStage = .handler
    @TaskLocal private static var suppressWrapping = false

    /// Isolates one bounded provenance recorder to the current invocation and its structured child tasks.
    /// - Parameter operation: Admitted route execution; construction of the recorder starts no tasks or I/O.
    /// - Returns: The operation's result, retaining its exact normal return semantics.
    /// - Throws: Only the operation's original error or its explicit outer-boundary annotation.
    package static func withOperationCapture<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value) async rethrows -> Value {
        guard captureOperationFailures else { return try await operation() }
        if recorder != nil {
            // Nested public routing remains application work; only the outer host boundary annotates.
            return try await $suppressWrapping.withValue(true, operation: operation)
        }
        let capture = InteractionOperationRecorder()
        return try await $recorder.withValue(capture) {
            try await InvocationOwnerFailureScope.$observer.withValue({ failure in
                await capture.recordOwnerFailure(InteractionOwnerFailure(failure), at: responseStage)
            }, operation: operation)
        }
    }

    /// Identifies the current response operation while its existing sink and structured children execute.
    /// - Parameters:
    ///   - stage: Acknowledgement or continuation source for safe lower-layer owner observations.
    ///   - operation: Existing response work; this adds no retry, task, queue or response behavior.
    /// - Returns: Original operation result.
    /// - Throws: The original operation error unchanged.
    package static func withResponseStage<Value: Sendable>(_ stage: InteractionOperationStage,
        operation: @Sendable () async throws -> Value) async rethrows -> Value {
        try await $responseStage.withValue(stage, operation: operation)
    }

    /// Records safe response provenance without changing the error visible to application catch clauses.
    /// - Parameters:
    ///   - error: Original operation error; only closed typed categories or numeric API evidence are inspected.
    ///   - stage: Response boundary that observed the error before rethrowing it unchanged.
    package static func record(_ error: any Error, at stage: InteractionOperationStage) async {
        await recorder?.record(error, at: stage)
    }

    /// Preserves terminal continuation-owner evidence before its public mutation-uncertainty translation.
    /// - Parameters:
    ///   - error: Original adapter failure; only reviewed closed owner categories are retained.
    ///   - stage: Original operation boundary before public error translation.
    package static func recordOwnerFailure(_ error: any Error, at stage: InteractionOperationStage) async {
        guard let ownerFailure = InteractionOwnerFailure(error) else { return }
        await recorder?.recordOwnerFailure(ownerFailure, at: stage)
    }

    /// Removes earlier failure observations after an explicitly completed response operation.
    /// A later same-category handler failure cannot inherit a response failure that preceded this success.
    package static func clear() async { await recorder?.clear() }

    /// Adds provenance only after application execution has escaped the router boundary.
    /// - Parameters:
    ///   - error: Final escaping failure; arbitrary descriptions and dynamic type names are never inspected.
    ///   - stage: Preparation or handler fallback when no matching closed response fingerprint was observed.
    /// - Returns: Original error outside the scope, for cancellation or for an already annotated error;
    ///   otherwise one package-only wrapper. Unknown or different-fingerprint errors retain the outer
    ///   boundary. A matching fingerprint correlates a safe operation observation; it cannot establish
    ///   causal identity if application code catches and replaces an error with the same safe category.
    ///   This performs no recovery, retry or response work.
    package static func annotate(_ error: any Error, at stage: InteractionOperationStage) async -> any Error {
        guard captureOperationFailures, !suppressWrapping,
              !(error is CancellationError),
              (error as? DiscordError) != .cancelled else { return error }
        let ownerObservation = await recorder?.ownerObservation()
        if let existing = error as? InteractionOperationFailure {
            guard let ownerObservation else { return existing }
            return InteractionOperationFailure(stage: ownerObservation.stage, underlying: existing.underlying,
                ownerFailure: ownerObservation.failure)
        }
        let recordedStage = await recorder?.matchingStage(for: error)
        return InteractionOperationFailure(stage: ownerObservation?.stage ?? recordedStage ?? stage,
            underlying: error, ownerFailure: ownerObservation?.failure)
    }
}

/// One invocation's last response failure, retaining no original error, interaction or token-indexed state.
private actor InteractionOperationRecorder {
    private var last: (stage: InteractionOperationStage, fingerprint: InteractionOperationFingerprint)?
    private var owner: (failure: InteractionOwnerFailure, stage: InteractionOperationStage)?

    /// Creates empty bounded provenance without scheduling work.
    init() {}

    /// Stores one closed fingerprint; arbitrary injected errors clear rather than retain response provenance.
    /// - Parameters:
    ///   - error: Failure whose original value remains owned by the throwing caller.
    ///   - stage: Operation boundary to associate with a closed safe fingerprint.
    func record(_ error: any Error, at stage: InteractionOperationStage) {
        last = InteractionOperationFingerprint(error).map { (stage, $0) }
    }

    /// Retains the first closed terminal owner failure for this invocation, independent of later mapping.
    /// - Parameters:
    ///   - failure: Closed owner evidence, before uncertainty translation or application catches.
    ///   - stage: Exact source operation observed by the caller task.
    func recordOwnerFailure(_ failure: InteractionOwnerFailure, at stage: InteractionOperationStage) {
        if owner == nil { owner = (failure, stage) }
    }

    /// Reads the first safe terminal observation without returning an arbitrary error or invocation content.
    /// - Returns: One closed owner category and its source stage, or nil when no owner failure was observed.
    func ownerObservation() -> (failure: InteractionOwnerFailure, stage: InteractionOperationStage)? { owner }

    /// Clears the ordinary observation after success; terminal owner evidence remains sticky until invocation exit.
    func clear() { last = nil }

    /// Uses response provenance only when the final escaping failure has the same closed safe fingerprint.
    /// - Parameter error: Final router failure after all application catch clauses and mapping have completed.
    /// - Returns: Stage of a matching safe observation, or nil for unknown, different or unrecorded
    ///   fingerprints. Equal fingerprints do not distinguish an original error from an application
    ///   replacement carrying the same closed category and numeric evidence.
    func matchingStage(for error: any Error) -> InteractionOperationStage? {
        guard let last, let fingerprint = InteractionOperationFingerprint(error), last.fingerprint == fingerprint else { return nil }
        return last.stage
    }
}

/// Closed safe matching evidence; numeric API status/code never imply mutation retry safety.
private enum InteractionOperationFingerprint: Sendable, Equatable {
    case discord(DiscordError)
    case lifecycle(InteractionLifecycleError)
    case delivery(InteractionDeliveryError)
    case api(status: Int, code: Int?)
    case rateLimit(RateLimitFailure)
    case transport(TransportFailure)

    /// Projects only reviewed safe typed evidence without retaining headers, bodies or arbitrary error values.
    /// - Parameter error: Response or final router error; unknown injected values yield no fingerprint.
    init?(_ error: any Error) {
        if let error = error as? DiscordError { self = .discord(error) }
        else if let error = error as? InteractionLifecycleError { self = .lifecycle(error) }
        else if let error = error as? InteractionDeliveryError { self = .delivery(error) }
        else if let error = error as? APIResponseError { self = .api(status: error.status, code: error.code) }
        else if let error = error as? RateLimitFailure { self = .rateLimit(error) }
        else if let error = error as? TransportFailure { self = .transport(error) }
        else { return nil }
    }
}
