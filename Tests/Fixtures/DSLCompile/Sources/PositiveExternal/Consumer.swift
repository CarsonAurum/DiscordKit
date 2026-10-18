import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordInteractions
import DiscordModels
import ExternalCodec

/// Imported choice conformance remains ordinary compiler-checked Swift, with no source lookup by macros.
public enum ConsumerColor: String, StringArgumentChoice { case red, blue }

/// An actual independently compiled consumer combines imported codecs, public access and typed defaults.
@CommandArguments
public struct ConsumerArguments {
    @Option(description: "Required external codec") public let token: ExternalToken
    @Option(description: "Required string") public let person: String
    @Option(description: "Color choice") public var color: ConsumerColor = .blue
    @Option(name: "count", description: "Optional count") public let repetitions: Int?
    @Option(description: "Explicit nil default") public var suffix: String? = nil
    @Option(description: "Literal default") public var enabled: Bool = true
}

/// Public generated methods must satisfy imported protocol requirements from outside the macro package.
@SlashCommand("external", description: "External consumer")
public struct ConsumerCommand {
    public typealias Arguments = ConsumerArguments
    /// Executes no fixture work; compilation still type-checks the external value and response context.
    /// - Parameters:
    ///   - context: Injected authenticated interaction, whose existing responder remains untouched.
    ///   - arguments: Fresh compiler-generated typed values, used only to prove external symbol access.
    public func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        _ = arguments.token.text
        _ = arguments.color.rawValue
    }
}

/// Separately type-checks the generated public factory and the explicit handwritten escape hatch.
/// - Returns: A validated inert contribution; no router, handler, registration or I/O starts.
/// - Throws: Existing runtime schema, codec-default or registration validation errors.
public func makeExternalContribution() throws -> DiscordCommandDSL.SlashCommand<ConsumerCommand> {
    try ConsumerCommand().contribution(id: "external", source: .init(fileID: "External.swift", line: 1, column: 1))
}

/// Type-checks the generated aggregate's real runtime decoding against a separately compiled return type.
/// - Parameter options: Complete invocation leaves validated by the existing runtime schema.
/// - Returns: The imported custom codec value retained by the generated argument initializer.
/// - Throws: Existing sanitized schema errors for malformed input; no lookup, transport or hydration occurs.
public func decodeExternalToken(options: [InteractionCommandOption]) throws -> ExternalToken {
    try ConsumerArguments.schema.decode(options: options, commandName: "external").token
}
