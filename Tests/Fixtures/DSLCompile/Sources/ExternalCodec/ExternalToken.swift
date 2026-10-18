import DiscordCommandDSL
import DiscordCore
import DiscordModels

/// Separately compiled custom codec whose conformance cannot be inferred from the consumer source syntax.
public struct ExternalToken: ArgumentValue {
    public let text: String
    /// Uses the published string option contract without adding a macro-specific argument type.
    public static var optionType: ApplicationCommandOptionType { .string }

    /// Retains any bounded fixture string without registration, network or handler work.
    /// - Parameter text: Exact nonsecret synthetic marker, validated by the ordinary runtime schema.
    public init(text: String) { self.text = text }

    /// Delegates wire presence and kind checking to the existing runtime codec.
    /// - Parameters:
    ///   - value: Same-invocation scalar; absence/null remain distinct codec failures.
    ///   - resolved: Same-invocation partial observations, unused for strings.
    /// - Returns: The exact string wrapped in this separately compiled public value.
    /// - Throws: Built-in String `ArgumentValueError` failures for absent, null or incompatible scalar input.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        Self(text: try String.decodeArgument(value, resolved: resolved))
    }

    /// Encodes the retained string synchronously for runtime default and constraint validation.
    public var argumentValue: Field<JSONValue> { .value(.string(text)) }
}
