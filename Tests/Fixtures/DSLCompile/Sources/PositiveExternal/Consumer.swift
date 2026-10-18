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

/// An explicit immediate protocol preserves typed response ownership instead of adding manual conformance.
@SlashCommand("immediate", description: "External immediate consumer")
public struct ImmediateConsumer: DiscordCommandDSL.SlashCommandHandler {
    public typealias Arguments = ConsumerArguments

    /// Returns one validated message while type-checking immutable typed-context fields from another package.
    /// - Parameters:
    ///   - context: Normalized snapshot with no raw response owner.
    ///   - arguments: Fresh validated compiler-generated invocation values.
    /// - Returns: One immediate message, using the existing message model without builders or implicit I/O.
    /// - Throws: Existing local message validation errors; fixture compilation never executes the handler.
    public func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        _ = context.deliveryMode
        _ = context.interaction.id
        return try MessageResponse(InteractionMessageCreate(content: .value(arguments.person)))
    }
}

/// An explicit deferred protocol keeps defer and original-edit ownership inside the runtime adapter.
@SlashCommand("deferred", description: "External deferred consumer")
public struct DeferredConsumer: DeferredSlashCommandHandler {
    public typealias Arguments = ConsumerArguments

    /// Selects immutable initial visibility without invoking user work or acknowledgement mechanics.
    public var responseVisibility: CommandResponseVisibility { .ephemeral }

    /// Returns a partial original edit through the distinct typed completion family.
    /// - Parameters:
    ///   - context: Snapshot supplied after the runtime adapter confirms its deferred acknowledgement.
    ///   - arguments: Complete fresh arguments decoded before that acknowledgement.
    /// - Returns: One validated original edit; no follow-up or second initial response can be represented.
    /// - Throws: Existing local edit validation errors; fixture compilation starts no work.
    public func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        _ = context.deliveryMode
        _ = context.interaction.id
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value(arguments.person)))
    }
}

/// Type-checks both generated typed-family contribution factories from outside the macro package.
/// - Returns: Definitions from two validated inert contributions; no execution or registration occurs.
/// - Throws: Existing schema, metadata or default-value validation errors.
public func typedExternalContributions() throws -> [String] {
    let source = DefinitionSourceLocation(fileID: "External.swift", line: 1, column: 1)
    let immediate: DiscordCommandDSL.SlashCommand<ImmediateConsumer> = try ImmediateConsumer().contribution(id: "immediate", source: source)
    let deferred: DiscordCommandDSL.SlashCommand<DeferredConsumer> = try DeferredConsumer().contribution(id: "deferred", source: source)
    return [immediate.definition.request.name, deferred.definition.request.name]
}
