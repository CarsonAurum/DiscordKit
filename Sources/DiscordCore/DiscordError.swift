/// Stable validation categories containing no untrusted input or secret strings.
public enum ValidationFailure: String, Error, Sendable, Codable {
    /// A required credential was an empty string.
    case emptyCredential
    /// A credential contained whitespace or control characters.
    case invalidCredential
    /// A value violated an operation's documented requirements.
    case invalidValue
    /// A required field or prerequisite was missing.
    case missingValue
    /// An operation exceeded a configured bound.
    case limitExceeded
}

/// Transport failure categories without underlying error descriptions or URLs.
public enum TransportFailureKind: String, Sendable, Codable {
    /// A connection could not be established.
    case connectionFailed
    /// The peer closed or disconnected before a required result.
    case disconnected
    /// A configured monotonic deadline expired.
    case deadlineExceeded
    /// Received transport data violated the negotiated protocol.
    case invalidResponse
    /// A bounded transport buffer or body limit was exceeded.
    case limitExceeded
}

/// Why a non-idempotent operation's result is indeterminate.
public enum MutationUncertainty: String, Sendable, Codable {
    /// Cancellation occurred after the operation may have reached the server.
    case cancelledAfterSubmission
    /// The connection failed after the operation may have reached the server.
    case connectionLostAfterSubmission
    /// A deadline expired after the operation may have reached the server.
    case deadlineAfterSubmission
    /// The server returned a 5xx response after a mutation may already have taken effect.
    case serverErrorAfterSubmission
}

/// Safe, typed failures shared by DiscordKit surfaces.
///
/// Untrusted server messages, request/response bodies, URLs and underlying error
/// descriptions are deliberately excluded. API numeric codes remain open to
/// unknown future values. Adapters must decide whether submission occurred;
/// `cancelled` alone never establishes that retrying a mutation is safe.
public enum DiscordError: Error, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    /// An HTTP response carrying its status and optional numeric Discord error code.
    /// The status/code are evidence only; this type does not classify retry safety.
    case api(status: Int, code: Int?)
    /// A local validation failure before a valid operation could be constructed.
    case validation(ValidationFailure)
    /// A transport failure whose category contains no unsafe error text.
    case transport(TransportFailureKind)
    /// Cooperative cancellation; the caller still needs operation-specific outcome evidence.
    case cancelled
    /// A mutation may already have executed. Reconcile server state or use an
    /// operation-specific idempotency contract before deciding whether to retry.
    case unknownMutationOutcome(MutationUncertainty)
    /// A host or implementation does not provide a required capability.
    case capabilityUnavailable(CapabilityUnavailableReason)

    /// A stable diagnostic using only numeric values and closed category names.
    public var description: String {
        switch self {
        case let .api(status, code):
            "Discord API failure (HTTP \(status), code \(code.map(String.init) ?? "unknown"))"
        case let .validation(reason): "Discord validation failure: \(reason.rawValue)"
        case let .transport(reason): "Discord transport failure: \(reason.rawValue)"
        case .cancelled: "Discord operation cancelled"
        case let .unknownMutationOutcome(reason): "Discord mutation outcome unknown: \(reason.rawValue)"
        case let .capabilityUnavailable(reason): "Discord capability unavailable: \(reason.rawValue)"
        }
    }

    /// The same diagnostic-safe summary used by ordinary string interpolation.
    public var debugDescription: String { description }

    /// A mirror exposing only the safe summary, never a response or underlying error.
    public var customMirror: Mirror {
        Mirror(self, children: ["error": description])
    }
}
