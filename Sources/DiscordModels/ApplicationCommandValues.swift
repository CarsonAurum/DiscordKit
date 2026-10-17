import DiscordCore

/// API v10 ApplicationCommandType wire values, verified 2026-10-16; response RawValue wrappers retain future values.
public enum ApplicationCommandType: Int, Sendable, CaseIterable {
    /// Documented wire value 1.
    case chatInput = 1
    /// Documented wire value 2.
    case user = 2
    /// Documented wire value 3.
    case message = 3
    /// Documented wire value 4.
    case primaryEntryPoint = 4
}

/// API v10 ApplicationCommandOptionType wire values, verified 2026-10-16; response RawValue wrappers retain future values.
public enum ApplicationCommandOptionType: Int, Sendable, CaseIterable {
    /// Documented wire value 1.
    case subcommand = 1
    /// Documented wire value 2.
    case subcommandGroup = 2
    /// Documented wire value 3.
    case string = 3
    /// Documented wire value 4.
    case integer = 4
    /// Documented wire value 5.
    case boolean = 5
    /// Documented wire value 6.
    case user = 6
    /// Documented wire value 7.
    case channel = 7
    /// Documented wire value 8.
    case role = 8
    /// Documented wire value 9.
    case mentionable = 9
    /// Documented wire value 10.
    case number = 10
    /// Documented wire value 11.
    case attachment = 11
}

/// API v10 ApplicationCommandHandler wire values, verified 2026-10-16; response RawValue wrappers retain future values.
public enum ApplicationCommandHandler: Int, Sendable, CaseIterable {
    /// Documented wire value 1.
    case appHandler = 1
    /// Documented wire value 2.
    case discordLaunchActivity = 2
}

/// API v10 InteractionContextType wire values, verified 2026-10-16; response RawValue wrappers retain future values.
public enum InteractionContextType: Int, Sendable, CaseIterable {
    /// Documented wire value 0.
    case guild = 0
    /// Documented wire value 1.
    case botDM = 1
    /// Documented wire value 2.
    case privateChannel = 2
}

/// API v10 ApplicationCommandPermissionType wire values, verified 2026-10-16; response RawValue wrappers retain future values.
public enum ApplicationCommandPermissionType: Int, Sendable, CaseIterable {
    /// Documented wire value 1.
    case role = 1
    /// Documented wire value 2.
    case user = 2
    /// Documented wire value 3.
    case channel = 3
}

/// Exact choice payload, separating text from arbitrary-precision numeric response lexemes.
/// Numeric request validation applies separately according to the owning option type.
public enum ApplicationCommandChoiceValue: Sendable, Equatable {
    /// A string choice; outgoing values are bounded to 100 Unicode scalars.
    case string(String)
    /// An exact JSON number, preserving integer precision and fractional/exponent spelling.
    case number(JSONNumber)

    /// Projects a bounded scalar without coercing strings to numbers or imposing request limits.
    /// - Parameter value: Original choice value from a complete, parser-bounded document.
    /// - Throws: Sanitized invalid-response errors for null, booleans, arrays or objects.
    init(value: JSONValue) throws {
        switch value {
        case .string(let text): self = .string(text)
        case .number(let number): self = .number(number)
        default: throw DiscordError.transport(.invalidResponse)
        }
    }

    /// Exposes the exact scalar for deliberate encoding; this does not validate a mutation.
    /// - Returns: Original string or number, without normalization, I/O or logging.
    public func jsonValue() -> JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .number(let value): .number(value)
        }
    }
}
