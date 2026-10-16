/// A forward-compatible wire value retaining raw values unknown to this library version.
///
/// Wrap a typed, `RawRepresentable` enum to recognize existing cases without making
/// decoding fail when Discord adds a case. Equality and hashing use the raw value;
/// known-case lookup is computed each time and never rewrites an unknown value.
/// This type does not confer API support on an unrecognized value.
public struct RawValue<Known: RawRepresentable & Sendable>: Sendable, Hashable
where Known.RawValue: Codable & Hashable & Sendable {
    /// The original raw payload, including a value unknown to `Known`.
    public let rawValue: Known.RawValue

    /// Resolves a typed case when the current enum recognizes this raw value.
    ///
    /// Lookup is synchronous, has the behavior of `Known.init(rawValue:)`, and
    /// returns nil for an unknown case without modifying the retained payload.
    public var knownValue: Known? { Known(rawValue: rawValue) }

    /// Stores a wire value without requiring a recognized enum case.
    /// - Parameter rawValue: Any raw payload accepted by its own type, including future Discord values.
    public init(rawValue: Known.RawValue) {
        self.rawValue = rawValue
    }

    /// Stores the raw representation of a recognized case.
    /// - Parameter knownValue: The known case whose raw value will be preserved.
    public init(_ knownValue: Known) {
        self.rawValue = knownValue.rawValue
    }
}

extension RawValue: Codable {
    /// Decodes the raw payload without rejecting unknown enum cases.
    /// - Parameter decoder: A decoder positioned at a raw scalar or its type's own representation.
    /// - Throws: Errors from decoding `Known.RawValue`; unknown enum cases are not errors.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Known.RawValue.self)
    }

    /// Encodes the retained raw payload, whether or not its enum case is recognized.
    /// - Parameter encoder: The destination encoder, which receives the unmodified raw value.
    /// - Throws: Errors from encoding the raw payload.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
