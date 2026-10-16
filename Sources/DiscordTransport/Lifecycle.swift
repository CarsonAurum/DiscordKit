/// Failures owned by transport infrastructure rather than Discord endpoint policy.
public enum TransportFailure: Error, Equatable, Sendable {
    case deadlineExceeded
    case closed
    case concurrentRead
    case invalidLimit
    case chunkTooLarge(limit: Int, actual: Int)
    case scriptExhausted
}

/// An injected monotonic clock and optional absolute deadline for one operation.
///
/// Instants belong to the supplied clock. Adapters must propagate cancellation,
/// release operation-owned resources on failure, and never replay a request.
public struct TransportContext<C: Clock>: Sendable where C.Duration == Duration {
    public let clock: C
    public let deadline: C.Instant?

    /// Creates a context without starting work or consulting wall time.
    /// - Parameters:
    ///   - clock: Clock whose instants define the operation's time domain.
    ///   - deadline: Inclusive expiration instant; `nil` imposes no deadline.
    public init(clock: C, deadline: C.Instant? = nil) {
        self.clock = clock
        self.deadline = deadline
    }

    /// Checks cooperative cancellation before checking the inclusive deadline.
    /// - Throws: `CancellationError` for a cancelled task, or
    ///   `TransportFailure.deadlineExceeded` when the clock has reached the deadline.
    public func check() throws {
        try Task.checkCancellation()
        if let deadline, clock.now >= deadline { throw TransportFailure.deadlineExceeded }
    }

    /// Runs an operation with a structured deadline race and awaits both children.
    ///
    /// The losing child is cancelled and awaited before returning. The operation
    /// must cooperate with cancellation; this cannot forcibly interrupt blocking
    /// code. Simultaneous operation/deadline completion has no ordering guarantee.
    /// - Parameter operation: Work owned by this call; must clean up before exiting.
    /// - Returns: The operation result when it completes before expiration.
    /// - Throws: Cancellation, expiration, or the operation's original error.
    public func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try check()
        guard let deadline else {
            let value = try await operation()
            try Task.checkCancellation()
            return value
        }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(until: deadline, tolerance: nil)
                throw TransportFailure.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return value
        }
    }
}

/// Ownership of a resource whose close operation is safe to repeat concurrently.
public protocol TransportResource: Sendable {
    /// Discards pending input, prevents further operations, and releases ownership.
    ///
    /// Implementations reserve closure before suspending, unblock pending operations,
    /// and release each resource exactly once. Returning means cleanup has completed;
    /// closing an already closed resource succeeds without additional effects.
    func close() async
}
