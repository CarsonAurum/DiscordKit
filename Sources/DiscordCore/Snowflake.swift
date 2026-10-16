import Foundation

/// A Discord snowflake retaining all 64 unsigned bits and its resource type.
///
/// HTTP JSON uses decimal strings, never floating-point numbers. Zero is accepted
/// for pagination boundaries. Tags have no runtime representation. This value
/// does not prove that a resource exists or that its timestamp is trustworthy.
/// See https://docs.discord.com/developers/reference#snowflakes (verified 2026-10-15).
public struct Snowflake<Tag>: RawRepresentable, Hashable, Comparable, Sendable,
    LosslessStringConvertible, Codable
{
    /// The unmodified unsigned identifier, including worker/process/increment bits.
    public let rawValue: UInt64

    /// Discord's epoch, in milliseconds since 1970-01-01T00:00:00Z.
    public static var epochMilliseconds: UInt64 { 1_420_070_400_000 }

    /// Wraps all 64 bits without validating resource existence or timestamp age.
    /// - Parameter rawValue: Any unsigned 64-bit value, including zero.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Parses a nonempty ASCII decimal string without signs or whitespace.
    /// Leading zeroes are accepted and canonicalized when formatted or encoded.
    /// - Parameter description: Decimal digits representing an unsigned 64-bit ID.
    /// - Returns: Nil for nondecimal input, empty input, or overflow.
    public init?(_ description: String) {
        guard !description.isEmpty,
            description.utf8.allSatisfy({ (48...57).contains($0) }),
            let value = UInt64(description)
        else { return nil }
        rawValue = value
    }

    /// Constructs the first possible snowflake at a millisecond boundary.
    /// Worker, process and sequence bits are zero; no resource is created.
    /// - Parameter timestampMilliseconds: Unix milliseconds in the Discord epoch's
    ///   inclusive 42-bit timestamp range.
    /// - Throws: `SnowflakeTimestampError.beforeEpoch` before 2015, or
    ///   `SnowflakeTimestampError.outOfRange` after the final representable millisecond.
    public init(timestampMilliseconds: UInt64) throws {
        guard timestampMilliseconds >= Self.epochMilliseconds else {
            throw SnowflakeTimestampError.beforeEpoch
        }
        let elapsed = timestampMilliseconds - Self.epochMilliseconds
        guard elapsed <= UInt64.max >> 22 else {
            throw SnowflakeTimestampError.outOfRange
        }
        rawValue = elapsed << 22
    }

    /// Reads the timestamp in Unix milliseconds without dropping low timestamp bits.
    /// Shifting leaves at most 42 bits; adding the epoch therefore cannot overflow
    /// `UInt64`. No floating-point conversion or resource lookup occurs.
    public var timestampMilliseconds: UInt64 {
        (rawValue >> 22) + Self.epochMilliseconds
    }

    /// The extracted UTC instant, accurate to the snowflake's millisecond resolution.
    /// The bounded integer millisecond value is exactly representable by `Double`;
    /// `Date` may round its fractional-second storage to its native precision.
    public var timestamp: Date {
        Date(timeIntervalSince1970: Double(timestampMilliseconds) / 1_000)
    }

    /// The canonical decimal form without signs, padding or localization.
    public var description: String { String(rawValue) }

    /// Compares unsigned identifier values within the same tag type.
    /// - Parameters:
    ///   - lhs: The left identifier.
    ///   - rhs: The right identifier of the same resource type.
    /// - Returns: Whether `lhs` precedes `rhs` numerically.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Decodes a decimal JSON string without accepting lossy numeric values.
    /// - Parameter decoder: Decoder positioned at a single string value.
    /// - Throws: Decoder errors for null/nonstring values, or `DecodingError` for
    ///   invalid digits or unsigned overflow. The error excludes the input text.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an unsigned 64-bit decimal snowflake string."
            )
        }
        self = value
    }

    /// Encodes the exact unsigned identifier as a decimal string.
    /// - Parameter encoder: Encoder receiving one string value.
    /// - Throws: Errors reported by the supplied encoder.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Failures when converting a Unix timestamp into Discord's 42-bit time field.
public enum SnowflakeTimestampError: Error, Equatable, Sendable {
    /// The timestamp is earlier than Discord's epoch.
    case beforeEpoch
    /// The timestamp cannot fit in the snowflake's timestamp field.
    case outOfRange
}

/// Marker distinguishing Discord users from other snowflake resources.
public enum UserTag: Sendable {}
/// Marker distinguishing Discord channels from other snowflake resources.
public enum ChannelTag: Sendable {}
/// Marker distinguishing Discord guilds from other snowflake resources.
public enum GuildTag: Sendable {}
/// Marker distinguishing Discord messages from other snowflake resources.
public enum MessageTag: Sendable {}
/// Marker distinguishing Discord applications from other snowflake resources.
public enum ApplicationTag: Sendable {}
/// Marker distinguishing Discord webhooks from other snowflake resources.
public enum WebhookTag: Sendable {}
/// Marker distinguishing Discord roles from other snowflake resources.
public enum RoleTag: Sendable {}
/// A strongly typed Discord user identifier.
public typealias UserID = Snowflake<UserTag>
/// A strongly typed Discord channel identifier.
public typealias ChannelID = Snowflake<ChannelTag>
/// A strongly typed Discord guild identifier.
public typealias GuildID = Snowflake<GuildTag>
/// A strongly typed Discord message identifier.
public typealias MessageID = Snowflake<MessageTag>
/// A strongly typed Discord application identifier.
public typealias ApplicationID = Snowflake<ApplicationTag>
/// A strongly typed Discord webhook identifier.
public typealias WebhookID = Snowflake<WebhookTag>
/// A strongly typed Discord role identifier.
public typealias RoleID = Snowflake<RoleTag>

/// An opaque external-provider string identifier, deliberately not a snowflake.
/// Values preserve exact spelling, including leading zeroes and empty strings;
/// provider-specific validation belongs to that provider's implementation.
public struct ExternalIdentifier<Tag>: RawRepresentable, Hashable, Sendable, Codable {
    /// The provider's unmodified opaque identifier.
    public let rawValue: String

    /// Wraps a string without imposing Discord or provider-specific validation.
    /// - Parameter rawValue: Any exact provider identifier string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Decodes one opaque string, rejecting numbers and nulls.
    /// - Parameter decoder: Decoder positioned at an external identifier.
    /// - Throws: Errors reported by the decoder for nonstring or invalid data.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Encodes one opaque string without numeric normalization.
    /// - Parameter encoder: Encoder receiving the identifier.
    /// - Throws: Errors reported by the encoder.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Marker for external provider names, such as an authentication provider key.
public enum ExternalProviderTag: Sendable {}
/// Marker for a provider's user/account identifier.
public enum ExternalUserTag: Sendable {}
/// An external provider identifier, distinct from its user/account identifiers.
public typealias ExternalProviderID = ExternalIdentifier<ExternalProviderTag>
/// An external user identifier, distinct from Discord user snowflakes.
public typealias ExternalUserID = ExternalIdentifier<ExternalUserTag>
