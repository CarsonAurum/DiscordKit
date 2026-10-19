/// Closed package-only owner evidence shared across transport, HTTP and invocation boundaries.
/// It contains no error objects, URLs, credentials or request/response content.
package enum InvocationOwnerFailure: Sendable {
    case rateLimitClosed
    case rateLimitInvalidRequest
    case rateLimitUnknownReservation
    case rateLimitCoordinatorUnavailable
    case transportClosed
    case transportConcurrentRead
    case transportInvalidLimit
    case transportScriptExhausted
}

/// Inert caller-task observation of terminal owner failures before lower layers normalize public errors.
package enum InvocationOwnerFailureScope {
    @TaskLocal package static var observer: (@Sendable (InvocationOwnerFailure) async -> Void)?

    /// Forwards one reviewed owner category to an explicit scoped observer in the current task.
    /// - Parameter failure: Closed safe evidence; no arbitrary error or payload crosses this boundary.
    /// The observer cannot throw, starts no package-owned task or queue, and never changes retry policy.
    package static func record(_ failure: InvocationOwnerFailure) async { await observer?(failure) }
}
