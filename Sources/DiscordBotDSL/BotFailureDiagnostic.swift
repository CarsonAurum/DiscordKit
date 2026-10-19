import DiscordClient
import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordInteractions
import DiscordLogging
import DiscordTransport

/// Operation boundary captured before supervised failures are aggregated.
/// Stages describe the observed boundary, never an inference from HTTP status or arbitrary error text.
public enum BotFailureStage: String, Sendable, CaseIterable {
    case setup, client, events, interactions, acknowledgement, continuation, handler, cleanup
}

/// Closed diagnostic categories. Numeric API status/code and fatal close code are separate evidence;
/// no category establishes that a mutation can be safely retried.
public enum BotFailureCategory: String, Sendable, CaseIterable {
    case unclassified
    case cancelled
    case api
    case validationEmptyCredential = "validation.empty_credential"
    case validationInvalidCredential = "validation.invalid_credential"
    case validationInvalidValue = "validation.invalid_value"
    case validationMissingValue = "validation.missing_value"
    case validationLimitExceeded = "validation.limit_exceeded"
    case transportConnectionFailed = "transport.connection_failed"
    case transportDisconnected = "transport.disconnected"
    case transportDeadlineExceeded = "transport.deadline_exceeded"
    case transportInvalidResponse = "transport.invalid_response"
    case transportLimitExceeded = "transport.limit_exceeded"
    case mutationCancelledAfterSubmission = "mutation.cancelled_after_submission"
    case mutationConnectionLostAfterSubmission = "mutation.connection_lost_after_submission"
    case mutationDeadlineAfterSubmission = "mutation.deadline_after_submission"
    case mutationServerErrorAfterSubmission = "mutation.server_error_after_submission"
    case capabilityUnsupportedPlatform = "capability.unsupported_platform"
    case capabilityRestrictedByHost = "capability.restricted_by_host"
    case capabilityPermissionDenied = "capability.permission_denied"
    case capabilityMissingConfiguration = "capability.missing_configuration"
    case capabilityNotImplemented = "capability.not_implemented"
    case capabilityNotQualified = "capability.not_qualified"
    case capabilityMissingUpstreamContract = "capability.missing_upstream_contract"
    case interactionLifecycleInvalidConfiguration = "interaction_lifecycle.invalid_configuration"
    case interactionLifecycleContextMismatch = "interaction_lifecycle.context_mismatch"
    case interactionLifecycleUnsupportedInteraction = "interaction_lifecycle.unsupported_interaction"
    case interactionLifecycleInitialResponseInFlight = "interaction_lifecycle.initial_response_in_flight"
    case interactionLifecycleAlreadyAcknowledged = "interaction_lifecycle.already_acknowledged"
    case interactionLifecycleNotAcknowledged = "interaction_lifecycle.not_acknowledged"
    case interactionLifecycleIndeterminateAcknowledgement = "interaction_lifecycle.indeterminate_acknowledgement"
    case interactionLifecycleDeadlineExceeded = "interaction_lifecycle.deadline_exceeded"
    case interactionLifecycleTokenExpired = "interaction_lifecycle.token_expired"
    case interactionLifecycleAcknowledgementCapacityExceeded = "interaction_lifecycle.acknowledgement_capacity_exceeded"
    case interactionLifecycleOriginalResponseUnavailable = "interaction_lifecycle.original_response_unavailable"
    case interactionLifecycleDeferredResponseRequired = "interaction_lifecycle.deferred_response_required"
    case interactionLifecycleCompleteDeferredResponseFirst = "interaction_lifecycle.complete_deferred_response_first"
    case interactionLifecycleContinuationInFlight = "interaction_lifecycle.continuation_in_flight"
    case interactionLifecycleHandlerAlreadyRunning = "interaction_lifecycle.handler_already_running"
    case interactionDeliveryNotSubmitted = "interaction_delivery.not_submitted"
    case interactionDeliveryIndeterminate = "interaction_delivery.indeterminate"
    case gatewayInteractionAlreadyPrepared = "gateway_interaction.already_prepared"
    case gatewayInteractionNotPrepared = "gateway_interaction.not_prepared"
    case gatewayInteractionAlreadyRun = "gateway_interaction.already_run"
    case gatewayInteractionUntrustedEvent = "gateway_interaction.untrusted_event"
    case gatewayInteractionWrongApplication = "gateway_interaction.wrong_application"
    case gatewayInteractionUnmatchedCommand = "gateway_interaction.unmatched_command"
    case gatewayInvalidConfiguration = "gateway.invalid_configuration"
    case gatewayInvalidPayload = "gateway.invalid_payload"
    case gatewayUnsupportedEncoding = "gateway.unsupported_encoding"
    case gatewayInvalidTransition = "gateway.invalid_transition"
    case gatewayAlreadyRunning = "gateway.already_running"
    case gatewayStaleGeneration = "gateway.stale_generation"
    case gatewayDisconnected = "gateway.disconnected"
    case gatewayReconnectRequested = "gateway.reconnect_requested"
    case gatewayMissedHeartbeatACK = "gateway.missed_heartbeat_ack"
    case gatewayFatalClose = "gateway.fatal_close"
    case gatewayRetryLimitExceeded = "gateway.retry_limit_exceeded"
    case gatewayEventCapacityExceeded = "gateway.event_capacity_exceeded"
    case gatewayStartupRefreshRequired = "gateway.startup_refresh_required"
    case gatewayCoordinatorUnavailable = "gateway.coordinator_unavailable"
    case gatewayCommandCapacityExceeded = "gateway.command_capacity_exceeded"
    case gatewayCommandRateLimited = "gateway.command_rate_limited"
    case gatewayRequestConflict = "gateway.request_conflict"
    case gatewayNotReady = "gateway.not_ready"
    case gatewayMissingIntent = "gateway.missing_intent"
    case eventDeliveryInvalidConfiguration = "event_delivery.invalid_configuration"
    case eventDeliverySubscriptionCapacityExceeded = "event_delivery.subscription_capacity_exceeded"
    case eventDeliveryResynchronizationRequired = "event_delivery.resynchronization_required"
    case eventDeliveryConcurrentIteration = "event_delivery.concurrent_iteration"
    case eventDeliveryHandlerCapacityExceeded = "event_delivery.handler_capacity_exceeded"
    case eventDeliveryFinished = "event_delivery.finished"
    case clientInvalidConfiguration = "client.invalid_configuration"
    case clientAlreadyRunning = "client.already_running"
    case clientStopped = "client.stopped"
    case clientCapacityExceeded = "client.capacity_exceeded"
    case clientNotReady = "client.not_ready"
    case rateLimitQueueFull = "rate_limit.queue_full"
    case rateLimitMetadataFull = "rate_limit.metadata_full"
    case rateLimitDeadlineExceeded = "rate_limit.deadline_exceeded"
    case rateLimitClosed = "rate_limit.closed"
    case rateLimitInvalidRequest = "rate_limit.invalid_request"
    case rateLimitReservationExpired = "rate_limit.reservation_expired"
    case rateLimitUnknownReservation = "rate_limit.unknown_reservation"
    case rateLimitCoordinatorUnavailable = "rate_limit.coordinator_unavailable"
    case shardOwnershipInvalidAssignment = "shard_ownership.invalid_assignment"
    case shardOwnershipInvalidLimit = "shard_ownership.invalid_limit"
    case shardOwnershipAlreadyOwned = "shard_ownership.already_owned"
    case shardOwnershipCapacityExceeded = "shard_ownership.capacity_exceeded"
    case shardOwnershipStaleLease = "shard_ownership.stale_lease"
    case shardOwnershipCoordinatorUnavailable = "shard_ownership.coordinator_unavailable"
    case shardOwnershipGenerationExhausted = "shard_ownership.generation_exhausted"
    case botRuntimeAlreadyRunning = "bot_runtime.already_running"
    case botRuntimeStopped = "bot_runtime.stopped"
}

/// An immutable safe projection containing no original error, interaction, token, request or payload.
/// Unknown injected failures map to `unclassified`; classification never interpolates or reflects errors.
public struct BotFailureDiagnostic: Sendable, Equatable {
    public let stage: BotFailureStage
    public let category: BotFailureCategory
    public let httpStatus: Int?
    public let apiCode: Int?
    public let gatewayCloseCode: Int?

    /// Classifies one failure using only explicit known-error switches and numeric fields.
    /// - Parameters:
    ///   - error: Transient source of typed evidence; it is never retained by the diagnostic.
    ///   - stage: Boundary that observed the failure, used when no original stage was captured.
    /// An aggregate passed here maps to `unclassified`; use `classify(_:stage:)` for its finite entries.
    public init(classifying error: any Error, stage: BotFailureStage) {
        if let observed = error as? BotFailureObservationError {
            self = observed.diagnostic
            return
        }
        if let cleanup = error as? RuntimeCleanupFailure {
            self = Self(classifying: cleanup.original, stage: .cleanup)
            return
        }
        self.stage = stage
        var status: Int?, code: Int?, close: Int?
        let category: BotFailureCategory
        switch error {
        case is CancellationError: category = .cancelled
        case let failure as APIResponseError:
            category = .api; status = failure.status; code = failure.code
        case let failure as DiscordError:
            switch failure {
            case let .api(value, valueCode): category = .api; status = value; code = valueCode
            case .cancelled: category = .cancelled
            case .validation(let reason):
                switch reason {
                case .emptyCredential: category = .validationEmptyCredential
                case .invalidCredential: category = .validationInvalidCredential
                case .invalidValue: category = .validationInvalidValue
                case .missingValue: category = .validationMissingValue
                case .limitExceeded: category = .validationLimitExceeded
                }
            case .transport(let reason):
                switch reason {
                case .connectionFailed: category = .transportConnectionFailed
                case .disconnected: category = .transportDisconnected
                case .deadlineExceeded: category = .transportDeadlineExceeded
                case .invalidResponse: category = .transportInvalidResponse
                case .limitExceeded: category = .transportLimitExceeded
                }
            case .unknownMutationOutcome(let reason):
                switch reason {
                case .cancelledAfterSubmission: category = .mutationCancelledAfterSubmission
                case .connectionLostAfterSubmission: category = .mutationConnectionLostAfterSubmission
                case .deadlineAfterSubmission: category = .mutationDeadlineAfterSubmission
                case .serverErrorAfterSubmission: category = .mutationServerErrorAfterSubmission
                }
            case .capabilityUnavailable(let reason):
                switch reason {
                case .unsupportedPlatform: category = .capabilityUnsupportedPlatform
                case .restrictedByHost: category = .capabilityRestrictedByHost
                case .permissionDenied: category = .capabilityPermissionDenied
                case .missingConfiguration: category = .capabilityMissingConfiguration
                case .notImplemented: category = .capabilityNotImplemented
                case .notQualified: category = .capabilityNotQualified
                case .missingUpstreamContract: category = .capabilityMissingUpstreamContract
                }
            }
        case let failure as InteractionLifecycleError:
            switch failure {
            case .invalidConfiguration: category = .interactionLifecycleInvalidConfiguration
            case .contextMismatch: category = .interactionLifecycleContextMismatch
            case .unsupportedInteraction: category = .interactionLifecycleUnsupportedInteraction
            case .initialResponseInFlight: category = .interactionLifecycleInitialResponseInFlight
            case .alreadyAcknowledged: category = .interactionLifecycleAlreadyAcknowledged
            case .notAcknowledged: category = .interactionLifecycleNotAcknowledged
            case .indeterminateAcknowledgement: category = .interactionLifecycleIndeterminateAcknowledgement
            case .deadlineExceeded: category = .interactionLifecycleDeadlineExceeded
            case .tokenExpired: category = .interactionLifecycleTokenExpired
            case .acknowledgementCapacityExceeded: category = .interactionLifecycleAcknowledgementCapacityExceeded
            case .originalResponseUnavailable: category = .interactionLifecycleOriginalResponseUnavailable
            case .deferredResponseRequired: category = .interactionLifecycleDeferredResponseRequired
            case .completeDeferredResponseFirst: category = .interactionLifecycleCompleteDeferredResponseFirst
            case .continuationInFlight: category = .interactionLifecycleContinuationInFlight
            case .handlerAlreadyRunning: category = .interactionLifecycleHandlerAlreadyRunning
            }
        case let failure as InteractionDeliveryError:
            switch failure {
            case .notSubmitted: category = .interactionDeliveryNotSubmitted
            case .indeterminate: category = .interactionDeliveryIndeterminate
            }
        case let failure as GatewayInteractionFailure:
            switch failure {
            case .alreadyPrepared: category = .gatewayInteractionAlreadyPrepared
            case .notPrepared: category = .gatewayInteractionNotPrepared
            case .alreadyRun: category = .gatewayInteractionAlreadyRun
            case .untrustedEvent: category = .gatewayInteractionUntrustedEvent
            case .wrongApplication: category = .gatewayInteractionWrongApplication
            case .unmatchedCommand: category = .gatewayInteractionUnmatchedCommand
            }
        case let failure as GatewayFailure:
            switch failure {
            case .invalidConfiguration: category = .gatewayInvalidConfiguration
            case .invalidPayload: category = .gatewayInvalidPayload
            case .unsupportedEncoding: category = .gatewayUnsupportedEncoding
            case .invalidTransition: category = .gatewayInvalidTransition
            case .alreadyRunning: category = .gatewayAlreadyRunning
            case .staleGeneration: category = .gatewayStaleGeneration
            case .disconnected: category = .gatewayDisconnected
            case .reconnectRequested: category = .gatewayReconnectRequested
            case .missedHeartbeatACK: category = .gatewayMissedHeartbeatACK
            case .fatalClose(let value): category = .gatewayFatalClose; close = value
            case .retryLimitExceeded: category = .gatewayRetryLimitExceeded
            case .eventCapacityExceeded: category = .gatewayEventCapacityExceeded
            case .startupRefreshRequired: category = .gatewayStartupRefreshRequired
            case .coordinatorUnavailable: category = .gatewayCoordinatorUnavailable
            case .commandCapacityExceeded: category = .gatewayCommandCapacityExceeded
            case .commandRateLimited: category = .gatewayCommandRateLimited
            case .requestConflict: category = .gatewayRequestConflict
            case .notReady: category = .gatewayNotReady
            case .missingIntent: category = .gatewayMissingIntent
            }
        case let failure as GatewayEventDeliveryFailure:
            switch failure {
            case .invalidConfiguration: category = .eventDeliveryInvalidConfiguration
            case .subscriptionCapacityExceeded: category = .eventDeliverySubscriptionCapacityExceeded
            case .resynchronizationRequired: category = .eventDeliveryResynchronizationRequired
            case .concurrentIteration: category = .eventDeliveryConcurrentIteration
            case .handlerCapacityExceeded: category = .eventDeliveryHandlerCapacityExceeded
            case .finished: category = .eventDeliveryFinished
            }
        case let failure as ClientFailure:
            switch failure {
            case .invalidConfiguration: category = .clientInvalidConfiguration
            case .alreadyRunning: category = .clientAlreadyRunning
            case .stopped: category = .clientStopped
            case .capacityExceeded: category = .clientCapacityExceeded
            case .notReady: category = .clientNotReady
            }
        case let failure as RateLimitFailure:
            switch failure {
            case .queueFull: category = .rateLimitQueueFull
            case .metadataFull: category = .rateLimitMetadataFull
            case .deadlineExceeded: category = .rateLimitDeadlineExceeded
            case .closed: category = .rateLimitClosed
            case .invalidRequest: category = .rateLimitInvalidRequest
            case .reservationExpired: category = .rateLimitReservationExpired
            case .unknownReservation: category = .rateLimitUnknownReservation
            case .coordinatorUnavailable: category = .rateLimitCoordinatorUnavailable
            }
        case let failure as ShardOwnershipFailure:
            switch failure {
            case .invalidAssignment: category = .shardOwnershipInvalidAssignment
            case .invalidLimit: category = .shardOwnershipInvalidLimit
            case .alreadyOwned: category = .shardOwnershipAlreadyOwned
            case .capacityExceeded: category = .shardOwnershipCapacityExceeded
            case .staleLease: category = .shardOwnershipStaleLease
            case .coordinatorUnavailable: category = .shardOwnershipCoordinatorUnavailable
            case .generationExhausted: category = .shardOwnershipGenerationExhausted
            }
        case let failure as BotRuntimeFailure:
            switch failure {
            case .alreadyRunning: category = .botRuntimeAlreadyRunning
            case .stopped: category = .botRuntimeStopped
            }
        default: category = .unclassified
        }
        self.category = category
        httpStatus = status
        apiCode = code
        gatewayCloseCode = close
    }

    /// Classifies a runtime aggregate entry by entry, with a hard maximum of three diagnostics.
    /// - Parameters:
    ///   - error: One failure or a bounded `BotRuntimeFailures` value. Nested aggregates are unclassified.
    ///   - stage: Original caller-known boundary for entries without a captured operation stage.
    /// - Returns: One diagnostic, or primary and at most two additional entries in observation order.
    /// No recursion, reflection, arbitrary descriptions, identifiers or error retention are performed.
    public static func classify(_ error: any Error, stage: BotFailureStage) -> [Self] {
        guard let failures = error as? BotRuntimeFailures else { return [Self(classifying: error, stage: stage)] }
        return ([failures.primary] + failures.additional.prefix(2)).enumerated().map { index, original in
            if index < failures.diagnostics.count { return failures.diagnostics[index] }
            return Self(classifying: original, stage: stage)
        }
    }

    /// Builds fixed safe log metadata; neither error text nor interaction-indexed fields are accepted.
    /// - Returns: Closed stage/category plus optional numeric API/close evidence.
    internal var logMetadata: Logger.Metadata {
        var metadata: Logger.Metadata = ["dk.stage": .string(stage.rawValue), "dk.failure": .string(category.rawValue)]
        if let httpStatus { metadata["dk.http_status"] = .stringConvertible(httpStatus) }
        if let apiCode { metadata["dk.api_code"] = .stringConvertible(apiCode) }
        if let gatewayCloseCode { metadata["dk.gateway_close_code"] = .stringConvertible(gatewayCloseCode) }
        return metadata
    }
}

/// Synchronous nonthrowing observation of one immutable diagnostic, with no library queue or tasks.
/// Observers must be concurrency-safe, finite and fast, and must not call blocking runtime joins.
/// Application-owned retention must be bounded. No original failure or interaction is supplied.
public typealias BotFailureObserver = @Sendable (BotFailureDiagnostic) -> Void

/// Carries exact safe operation provenance internally while preserving the original public thrown error.
/// This value never reaches an observer, diagnostic or ordinary reflection/log interpolation.
internal struct BotFailureObservationError: Error, Sendable, CustomStringConvertible, CustomReflectable {
    internal let original: any Error
    internal let diagnostic: BotFailureDiagnostic

    /// Binds original handling evidence to an already sanitized immutable diagnostic.
    /// - Parameters:
    ///   - original: Original failure rethrown after supervised ownership has joined.
    ///   - diagnostic: Fixed-stage/category projection created at the operation boundary.
    internal init(original: any Error, diagnostic: BotFailureDiagnostic) {
        self.original = original
        self.diagnostic = diagnostic
    }

    /// Conceals the arbitrary original error from routine diagnostic formatting.
    internal var description: String { "BotFailureObservationError(redacted)" }
    /// Prevents ordinary reflection from traversing the original arbitrary error.
    internal var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
