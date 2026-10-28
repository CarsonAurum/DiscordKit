// File: Tests/Fixtures/DSLCompile/Sources/PositiveExternal/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

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
    /// - Returns: One immediate builder message with escaped dynamic text and no implicit I/O.
    /// - Throws: Existing local message validation errors; fixture compilation never executes the handler.
    public func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        _ = context.deliveryMode
        _ = context.interaction.id
        return try MessageResponse {
            Text("\(arguments.person)")
        }
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
        return try DeferredMessageResponse {
            Text("\(arguments.person)")
        }
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

/// External user context-menu metadata retains display case and spaces through real compilation.
@UserCommand("Inspect User")
public struct UserConsumer: UserCommandHandler {
    /// Returns a typed immediate message without resolving observations or creating background work.
    /// - Parameters:
    ///   - context: Immutable interaction snapshot with no responder access.
    ///   - target: Selected same-interaction user reference; its unresolved fields remain explicit.
    /// - Returns: A locally validated JSON message containing the exact target identifier.
    /// - Throws: Existing message validation errors; compilation never invokes this method.
    public func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        try MessageResponse { Text("\(target.id.description)") }
    }
}

/// External message context menus preserve an explicit manual response owner and typed message target.
@MessageCommand("Inspect Message")
public struct MessageConsumer {
    /// Type-checks selected message identity without implicit fetching, acknowledgement or execution.
    /// - Parameters:
    ///   - context: Existing manual response owner, left pending by the controlled fixture.
    ///   - target: Selected message reference from this invocation; no message hydration is inferred.
    /// - Throws: Caller cancellation; the fixture performs no external operations.
    public func execute(_ context: InteractionContext, target: MessageCommandTarget) async throws {
        try Task.checkCancellation()
        _ = target.id
    }
}

/// External deferred context-menu authoring preserves the distinct edit-original completion contract.
@MessageCommand("Defer Message")
public struct DeferredMessageConsumer: DeferredMessageCommandHandler {
    /// Completes an explicitly deferred response without raw responder access.
    /// - Parameters:
    ///   - context: Immutable snapshot after the runtime confirms its defer.
    ///   - target: Fresh typed target selected before acknowledgement.
    /// - Returns: One validated original-message edit containing the selected identifier.
    /// - Throws: Existing local payload validation errors; compiler fixtures execute no user work.
    public func execute(_ context: DeferredCommandContext, target: MessageCommandTarget) async throws -> DeferredMessageResponse {
        try DeferredMessageResponse { Text("\(target.id.description)") }
    }
}

/// External generated factories produce typed context-menu contributions and grouped slash leaves.
/// - Returns: Validated registration names from explicit finite compilation; no router or synchronization runs.
/// - Throws: Existing schema, leaf-metadata or registration errors.
public func familyExternalContributions() throws -> [String] {
    let source = DefinitionSourceLocation(fileID: "External.swift", line: 1, column: 1)
    let user: DiscordCommandDSL.UserCommand<UserConsumer> = try UserConsumer().contribution(id: "user", source: source)
    let message: DiscordCommandDSL.MessageCommand<MessageConsumer> = try MessageConsumer().contribution(id: "message", source: source)
    let deferred: DiscordCommandDSL.MessageCommand<DeferredMessageConsumer> = try DeferredMessageConsumer().contribution(id: "deferred-message", source: source)
    let leaf = try ConsumerCommand().slashSubcommand()
    let group = try SlashSubcommandGroup(name: "group", description: "External group", subcommands: [leaf])
    let tree = try SlashCommandTree(id: "tree", command: .init(name: "tree", description: "External tree"),
        children: [.group(group)], source: source)
    let plan = try CommandCompilation.compile(tree)
    return [user.family.definitions[0].request.name, message.family.definitions[0].request.name, deferred.family.definitions[0].request.name,
        plan.definitions[0].request.name]
}

/// An external focused-value provider retains typed partial input and a suggestions-only result.
public struct ExternalAutocompleteProvider: AutocompleteCommandHandler {
    public typealias Value = String

    /// Returns one correctly typed suggestion without constructing complete command arguments.
    /// - Parameters:
    ///   - context: Immutable authenticated interaction snapshot with no raw responder access.
    ///   - input: Admitted partial invocation; required siblings may still be absent.
    ///   - value: Present focused string, decoded independently from complete-command constraints.
    /// - Returns: A finite autocomplete-only response with one exact string suggestion.
    /// - Throws: Existing local choice/response validation errors; compiler fixtures execute no work.
    public func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> AutocompleteResponse<String> {
        try AutocompleteResponse([try AutocompleteChoice(name: "Suggestion", value: value)])
    }
}

/// Exact-ID components use their own typed input and legal immediate response marker.
public struct ExternalComponentHandler: ComponentHandler {
    /// A finite exact button ID; no prefix matching, subscription or registration starts.
    public var customID: String { "external:button" }
    /// Restricts this contribution to button interactions before handler execution.
    public var componentType: ComponentType { .button }

    /// Returns one validated component callback without low-level acknowledgement access.
    /// - Parameters:
    ///   - context: Immutable authenticated component invocation snapshot.
    ///   - input: Typed admitted component values and same-interaction partial resolution data.
    /// - Returns: One legal immediate new message; no implicit defer is selected.
    /// - Throws: Existing local message validation errors; this compiler fixture executes no handler.
    public func execute(_ context: CommandContext, input: ComponentInput) async throws -> MessageResponse {
        try MessageResponse { Text("Component") }
    }
}

/// External modal values declare a finite exact field schema without source reflection.
public struct ExternalModalValues: ModalValues {
    public let answer: String

    /// Captures one required text field and a fresh invocation-local aggregate constructor.
    /// - Throws: Existing descriptor/schema validation errors; access performs no decoding, tasks or I/O.
    public static var schema: ModalSchema<Self> {
        /// Returns one inert required-text descriptor and a fresh typed constructor without decoding input.
        /// - Throws: Existing descriptor or finite-schema validation errors.
        get throws {
            let answer = try ModalField<String>(customID: "answer")
            return try ModalSchema(fields: [answer.erased]) { Self(answer: try $0.value(for: answer)) }
        }
    }
}

/// Exact-ID modal submissions decode a distinct typed aggregate before their legal response runs.
public struct ExternalModalHandler: ModalHandler {
    public typealias Values = ExternalModalValues
    /// Exact modal identity, separate from the component-handler namespace.
    public var customID: String { "external:modal" }

    /// Produces one legal modal-submit message after complete typed field admission.
    /// - Parameters:
    ///   - context: Immutable normalized modal submission without raw acknowledgement operations.
    ///   - values: Fresh aggregate from this submission's exact declared fields.
    /// - Returns: A validated message; returning another modal is a separate invalid compile fixture.
    /// - Throws: Existing local message validation errors; no handler runs during compilation.
    public func execute(_ context: CommandContext, values: Values) async throws -> MessageResponse {
        try MessageResponse { Text("\(values.answer)") }
    }
}

/// Type-checks route-only protocol contributions independently of automatic registration or execution.
/// - Returns: The exact public route count from retained component, modal and autocomplete providers.
/// - Throws: Existing descriptor, ID, schema and route validation errors.
public func externalProtocolContributions() throws -> Int {
    let source = DefinitionSourceLocation(fileID: "External.swift", line: 1, column: 1)
    let component = try ComponentCommand(id: "component", handler: ExternalComponentHandler(), source: source)
    let modal = try ModalCommand(id: "modal", handler: ExternalModalHandler(), source: source)
    let option = try ArgumentOption<String>(name: "query", description: "Search query", autocomplete: true)
    let autocomplete = try AutocompleteCommand(id: "autocomplete", name: "search", option: option,
        handler: ExternalAutocompleteProvider(), source: source)
    return component.family.routes.count + modal.family.routes.count + autocomplete.family.routes.count
}

/// An immediate modal slash command uses a separate fixed response contract under the same authoring macro.
@SlashCommand("show", description: "Show a modal")
public struct ModalSlashConsumer: ModalSlashCommandHandler {
    public typealias Arguments = ConsumerArguments

    /// Returns an already validated modal before acknowledgement without exposing deferred completion.
    /// - Parameters:
    ///   - context: Immutable immediate invocation snapshot without the raw responder.
    ///   - arguments: Complete typed arguments admitted before user work; unused by this compile fixture.
    /// - Returns: A finite modal callback that cannot be represented as a deferred-message response.
    /// - Throws: Existing modal/component definition validation errors; compilation starts no work.
    public func execute(_ context: CommandContext, arguments: Arguments) async throws -> ModalResponse {
        let display = try MessageComponent(data: JSONValue.object([
            "type": .number(JSONNumber(rawValue: "10")), "content": .string("Information"),
        ]).serialized())
        return ModalResponse(try InteractionModal(customID: "external:modal", title: "Information", components: [display]))
    }
}

/// The same macro-authored immediate modal handler supports root and grouped-leaf contribution factories.
/// - Returns: The root registration name, proving both generated factories type-check externally.
/// - Throws: Existing schema, root-registration or leaf metadata validation errors.
public func externalModalSlashContribution() throws -> String {
    let handler = ModalSlashConsumer()
    let root: DiscordCommandDSL.SlashCommand<ModalSlashConsumer> = try handler.contribution(id: "show",
        source: .init(fileID: "External.swift", line: 1, column: 1))
    _ = try handler.slashSubcommand()
    return root.definition.request.name
}
