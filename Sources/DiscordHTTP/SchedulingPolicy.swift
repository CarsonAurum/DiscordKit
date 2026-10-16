import Foundation

/// Scheduling precedence. FIFO ordering is preserved within each identity/route/class.
/// Both classes have equal weight across eligible partitions and share aggregate caps.
public enum SchedulingClass: Sendable, Hashable {
    case ordinary
    case control
}

/// Finite process-local HTTP admission budgets; these are resource limits, not Discord quotas.
public struct SchedulingPolicy: Sendable {
    public let maximumQueuedRequests: Int
    public let maximumQueuedRequestsPerIdentity: Int
    public let maximumQueuedBytes: Int
    public let maximumQueuedBytesPerIdentity: Int
    public let maximumConcurrentRequests: Int
    public let maximumConcurrentRequestsPerIdentity: Int
    public let maximumMetadata: Int
    public let maximumQueueAge: Duration
    public let fairnessInterval: Duration
    public let reservationLifetime: Duration
    public let provisionalWindow: Duration
    public let initialGlobalRequestsPerSecond: Int
    public let invalidRequestThreshold: Int
    public let invalidRequestWindow: Duration

    /// Validates finite scheduling, metadata, uncertainty and initial discovery budgets.
    /// - Parameters:
    ///   - maximumQueuedRequests: Total queued requests, default 1,024; positive.
    ///   - maximumQueuedRequestsPerIdentity: Queued requests per opaque identity, default 128; positive.
    ///   - maximumQueuedBytes: Accounted total request bytes, default 16 MiB; nonnegative.
    ///   - maximumQueuedBytesPerIdentity: Accounted bytes per identity, default 4 MiB; nonnegative.
    ///   - maximumConcurrentRequests: Total in-flight reservations, default 64; positive.
    ///   - maximumConcurrentRequestsPerIdentity: In-flight reservations per identity, default 8; positive.
    ///   - maximumMetadata: Total retained rate keys and aliases, default 4,096; positive.
    ///   - maximumQueueAge: Maximum queue residence, default 30 seconds; positive.
    ///   - fairnessInterval: Maximum polling interval for eligible waiters, default 10 ms; positive.
    ///   - reservationLifetime: Maximum admission ownership, default 60 seconds; positive.
    ///   - provisionalWindow: Conservative unknown-route window, default one second; positive.
    ///   - initialGlobalRequestsPerSecond: Configurable initial credential-wide requests/second, default 50.
    ///     Learned global retry delays override this startup allowance. Interaction callbacks can opt out.
    ///   - invalidRequestThreshold: Egress invalid-response trip threshold, default 9,000; positive.
    ///   - invalidRequestWindow: Egress invalid-response counting window, default ten minutes; positive.
    /// - Precondition: Counts and durations satisfy the ranges described above.
    public init(
        maximumQueuedRequests: Int = 1_024,
        maximumQueuedRequestsPerIdentity: Int = 128,
        maximumQueuedBytes: Int = 16 * 1_024 * 1_024,
        maximumQueuedBytesPerIdentity: Int = 4 * 1_024 * 1_024,
        maximumConcurrentRequests: Int = 64,
        maximumConcurrentRequestsPerIdentity: Int = 8,
        maximumMetadata: Int = 4_096,
        maximumQueueAge: Duration = .seconds(30),
        fairnessInterval: Duration = .milliseconds(10),
        reservationLifetime: Duration = .seconds(60),
        provisionalWindow: Duration = .seconds(1),
        initialGlobalRequestsPerSecond: Int = 50,
        invalidRequestThreshold: Int = 9_000,
        invalidRequestWindow: Duration = .seconds(600)
    ) {
        precondition(maximumQueuedRequests > 0 && maximumQueuedRequestsPerIdentity > 0)
        precondition(maximumQueuedBytes >= 0 && maximumQueuedBytesPerIdentity >= 0)
        precondition(maximumConcurrentRequests > 0 && maximumConcurrentRequestsPerIdentity > 0)
        precondition(maximumMetadata > 0 && initialGlobalRequestsPerSecond > 0 && invalidRequestThreshold > 0)
        precondition(maximumQueueAge > .zero && fairnessInterval > .zero && reservationLifetime > .zero)
        precondition(provisionalWindow > .zero && invalidRequestWindow > .zero)
        self.maximumQueuedRequests = maximumQueuedRequests
        self.maximumQueuedRequestsPerIdentity = maximumQueuedRequestsPerIdentity
        self.maximumQueuedBytes = maximumQueuedBytes
        self.maximumQueuedBytesPerIdentity = maximumQueuedBytesPerIdentity
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.maximumConcurrentRequestsPerIdentity = maximumConcurrentRequestsPerIdentity
        self.maximumMetadata = maximumMetadata
        self.maximumQueueAge = maximumQueueAge
        self.fairnessInterval = fairnessInterval
        self.reservationLifetime = reservationLifetime
        self.provisionalWindow = provisionalWindow
        self.initialGlobalRequestsPerSecond = initialGlobalRequestsPerSecond
        self.invalidRequestThreshold = invalidRequestThreshold
        self.invalidRequestWindow = invalidRequestWindow
    }
}

/// Fail-closed admission failures; none authorize bypassing a shared coordinator.
public enum RateLimitFailure: Error, Sendable, Equatable {
    case queueFull
    case metadataFull
    case deadlineExceeded
    case closed
    case invalidRequest
    case reservationExpired
    case unknownReservation
    case coordinatorUnavailable
}

/// Bounded, credential-free counters suitable for tests and aggregate diagnostics.
public struct SchedulingSnapshot: Sendable, Equatable {
    public let queuedCount: Int
    public let queuedBytes: Int
    public let activeCount: Int
    public let metadataCount: Int
    public let orderedOperationsCount: Int

    /// Captures current aggregate resource ownership without identity labels.
    /// - Parameters:
    ///   - queuedCount: Nonnegative waiters currently retained.
    ///   - queuedBytes: Nonnegative accounted request bytes in that queue.
    ///   - activeCount: Nonnegative active reservations.
    ///   - metadataCount: Nonnegative retained rate keys and aliases.
    ///   - orderedOperationsCount: Locally held whole-operation ordering leases, default zero.
    public init(queuedCount: Int, queuedBytes: Int, activeCount: Int, metadataCount: Int, orderedOperationsCount: Int = 0) {
        self.queuedCount = queuedCount
        self.queuedBytes = queuedBytes
        self.activeCount = activeCount
        self.metadataCount = metadataCount
        self.orderedOperationsCount = orderedOperationsCount
    }
}
