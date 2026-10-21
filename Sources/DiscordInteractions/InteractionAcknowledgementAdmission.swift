import DiscordLogging
import Foundation

/// Safe lifecycle failures without callback content, continuation tokens or arbitrary transport diagnostics.
public enum InteractionLifecycleError: Error, Sendable, Equatable {
    case invalidConfiguration
    case contextMismatch
    case unsupportedInteraction
    case initialResponseInFlight
    case alreadyAcknowledged
    case notAcknowledged
    case indeterminateAcknowledgement
    case deadlineExceeded
    case tokenExpired
    case acknowledgementCapacityExceeded
    case originalResponseUnavailable
    case deferredResponseRequired
    case completeDeferredResponseFirst
    case continuationInFlight
    case handlerAlreadyRunning
}

/// Explicit initial-response submission evidence supplied by an injected delivery adapter.
/// All other adapter failures conservatively leave acknowledgement indeterminate.
public enum InteractionDeliveryError: Error, Sendable, Equatable {
    /// No initial callback bytes could have reached Discord; a later attempt may reserve the initial slot again.
    case notSubmitted
    /// Callback submission may have succeeded; automatic retry and continuation are prohibited.
    case indeterminate
}

/// Independent bounded, fail-fast initial-acknowledgement admission.
/// Share an application-scoped and/or aggregate instance across response actors. It retains no waiting queue,
/// credentials or per-interaction history, and ordinary REST work never acquires these reservations.
public actor InteractionAcknowledgementAdmission {
    private let maximumConcurrent: Int
    private let maximumBytes: Int
    private var reservations: [UUID: Int] = [:]
    private var bytes = 0

    /// Configures finite response count and exact encoded-JSON byte ceilings without allocating tasks.
    /// - Parameters:
    ///   - maximumConcurrent: Positive simultaneous initial callbacks, default 256.
    ///   - maximumBytes: Positive total encoded callback bytes in flight, default 8 MiB.
    /// - Throws: `InteractionLifecycleError.invalidConfiguration` for nonpositive bounds.
    public init(maximumConcurrent: Int = 256, maximumBytes: Int = 8 * 1_024 * 1_024) throws {
        guard maximumConcurrent > 0, maximumBytes > 0 else { throw InteractionLifecycleError.invalidConfiguration }
        self.maximumConcurrent = maximumConcurrent; self.maximumBytes = maximumBytes
    }

    /// Reserves initial-callback capacity immediately; overload never waits behind an ordinary REST queue.
    /// - Parameter encodedBytes: Positive bounded complete callback JSON size; uploads use separate endpoint ownership.
    /// - Returns: Opaque single-owner reservation, containing no interaction identifier or secret.
    /// - Throws: Cancellation, invalid configuration, or acknowledgement capacity exhaustion.
    func acquire(encodedBytes: Int) throws -> UUID {
        try Task.checkCancellation()
        guard encodedBytes > 0 else { throw InteractionLifecycleError.invalidConfiguration }
        guard reservations.count < maximumConcurrent, encodedBytes <= maximumBytes - bytes else {
            DiscordLog.makeLogger("interactions.admission").debug("Initial acknowledgement capacity exhausted", metadata: ["dk.event": "interactions.admission.overloaded", "dk.active": .stringConvertible(reservations.count), "dk.bytes": .stringConvertible(bytes)])
            throw InteractionLifecycleError.acknowledgementCapacityExceeded
        }
        let id = UUID(); reservations[id] = encodedBytes; bytes += encodedBytes
        DiscordLog.makeLogger("interactions.admission").trace("Initial acknowledgement capacity reserved", metadata: ["dk.event": "interactions.admission.acquired", "dk.active": .stringConvertible(reservations.count), "dk.bytes": .stringConvertible(bytes)])
        return id
    }

    /// Releases a reservation after confirmed success, safe rejection or ambiguous submission.
    /// - Parameter reservation: Reservation owned by the caller; repeated/unknown release is harmless.
    func release(_ reservation: UUID) {
        guard let count = reservations.removeValue(forKey: reservation) else { return }
        bytes -= count
        DiscordLog.makeLogger("interactions.admission").trace("Initial acknowledgement capacity released", metadata: ["dk.event": "interactions.admission.released", "dk.active": .stringConvertible(reservations.count), "dk.bytes": .stringConvertible(bytes)])
    }

    /// Reports bounded aggregate counters without retaining identities or diagnostic labels.
    /// - Returns: Current in-flight callback count and encoded JSON bytes, zero after all owners release.
    public func snapshot() -> (activeCount: Int, encodedBytes: Int) { (reservations.count, bytes) }
}
