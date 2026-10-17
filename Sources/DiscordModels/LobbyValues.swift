import DiscordCore

/// Marker separating lobby identifiers from ordinary channel identifiers despite shared wire representation.
public enum LobbyTag: Sendable {}
/// Exact unsigned 64-bit lobby identifier, serialized as decimal text without floating-point conversion.
public typealias LobbyID = Snowflake<LobbyTag>

/// Written API v10 lobby member capabilities, verified 2026-10-16 against the Lobby resource.
/// Unknown bits survive construction and set operations; a snapshot never grants current permissions.
public struct LobbyMemberFlags: OptionSet, Sendable, Hashable {
    /// Complete unsigned bitfield, including unknown future flags.
    public let rawValue: UInt64

    /// Retains a complete bitfield without checking current membership or channel-link eligibility.
    /// - Parameter rawValue: Any unsigned 64-bit value, including zero and future bits.
    /// Construction is synchronous, owns no external resources and performs no authorization or I/O.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The member can link an existing text channel to the lobby, subject to Discord's authorization checks.
    public static let canLinkLobby = Self(rawValue: 1 << 0)
}
