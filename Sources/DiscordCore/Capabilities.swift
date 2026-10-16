/// Runtime capabilities that implementations must qualify on their actual host.
/// These names do not claim the corresponding transport or feature is implemented.
public enum PlatformCapability: String, CaseIterable, Sendable, Codable {
    case http
    case webSocket
    case datagram
    case localIPC
    case httpIngress
    case browserAuthorization
    case audioCapture
    case audioPlayback
    case backgroundExecution
}

/// Closed, safe reasons for unavailable functionality; policy and implementation
/// limits remain distinguishable without platform-specific exception text.
public enum CapabilityUnavailableReason: String, CaseIterable, Sendable, Codable {
    case unsupportedPlatform
    case restrictedByHost
    case permissionDenied
    case missingConfiguration
    case notImplemented
    case notQualified
    case missingUpstreamContract
}

/// A result of explicitly checking a capability, separate from API parity status.
public enum CapabilityAvailability: Equatable, Sendable, Codable {
    /// The checking implementation established availability in its documented scope.
    case available
    /// The checking implementation cannot provide the requested capability.
    case unavailable(CapabilityUnavailableReason)

    /// Requires availability without converting an unavailable result into success.
    /// This performs no host probing and has no side effects or suspension points.
    /// - Throws: `DiscordError.capabilityUnavailable` with the preserved reason.
    public func requireAvailable() throws {
        if case let .unavailable(reason) = self {
            throw DiscordError.capabilityUnavailable(reason)
        }
    }
}
