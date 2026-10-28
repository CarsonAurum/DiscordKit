// File: Packages/DiscordDSLMacros/Tests/DiscordDSLMacrosTests/FamilyParityTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordInteractions
import DiscordModels
import Foundation
import Testing

/// Compiled context-menu and grouped-leaf authoring agrees with independent protocol construction.
@Suite(.timeLimit(.minutes(1))) struct FamilyParityTests {
    /// Generated user factories preserve exact registration, target decoding and initial-message ownership.
    /// - Throws: Unexpected local model, compilation, routing or response validation errors fail the test.
    @Test func userMenuMatchesHandwrittenHandler() async throws {
        let source = DefinitionSourceLocation(fileID: "Families.swift", line: 1, column: 1)
        let generated = try CommandCompilation.compile(GeneratedUserMenu().contribution(id: "user", source: source))
        let direct = try CommandCompilation.compile(DiscordCommandDSL.UserCommand(id: "user", handler: DirectUserMenu(), source: source))
        try await compare(generated: generated, direct: direct, data: .object([
            "id": .string("8"), "name": .string("Inspect User"), "type": .number(JSONNumber(rawValue: "2")),
            "target_id": .string("18446744073709551615"),
        ]), expectedResponse: try InteractionResponse.message(InteractionMessageCreate(content: .value("user:18446744073709551615"))).jsonValue())
    }

    /// Generated message factories preserve target kind and do not hydrate absent resolved observations.
    /// - Throws: Unexpected synthetic model, command lowering or response ownership errors fail the test.
    @Test func messageMenuMatchesHandwrittenHandler() async throws {
        let source = DefinitionSourceLocation(fileID: "Families.swift", line: 1, column: 1)
        let generated = try CommandCompilation.compile(GeneratedMessageMenu().contribution(id: "message", source: source))
        let direct = try CommandCompilation.compile(DiscordCommandDSL.MessageCommand(id: "message", handler: DirectMessageMenu(), source: source))
        try await compare(generated: generated, direct: direct, data: .object([
            "id": .string("8"), "name": .string("Inspect Message"), "type": .number(JSONNumber(rawValue: "3")),
            "target_id": .string("18446744073709551615"),
        ]), expectedResponse: try InteractionResponse.message(InteractionMessageCreate(content: .value("message:18446744073709551615"))).jsonValue())
    }

    /// A real generated leaf builds an explicit group and executes only its exact nested route.
    /// - Throws: Unexpected schema/group validation, model or routing failures fail the test.
    @Test func groupedSlashMatchesHandwrittenLeaf() async throws {
        let source = DefinitionSourceLocation(fileID: "Families.swift", line: 1, column: 1)
        let generatedLeaf = try GeneratedGroupedLeaf().slashSubcommand()
        let directLeaf = try SlashSubcommand(handler: DirectGroupedLeaf())
        let generated = try CommandCompilation.compile(SlashCommandTree(id: "tree",
            command: .init(name: "tools", description: "Grouped tools"),
            children: [.group(try SlashSubcommandGroup(name: "people", description: "People tools", subcommands: [generatedLeaf]))],
            source: source))
        let direct = try CommandCompilation.compile(SlashCommandTree(id: "tree",
            command: .init(name: "tools", description: "Grouped tools"),
            children: [.group(try SlashSubcommandGroup(name: "people", description: "People tools", subcommands: [directLeaf]))],
            source: source))
        try await compare(generated: generated, direct: direct, data: .object([
            "id": .string("8"), "name": .string("tools"), "type": .number(JSONNumber(rawValue: "1")),
            "options": .array([.object([
                "name": .string("people"), "type": .number(JSONNumber(rawValue: "2")),
                "options": .array([.object([
                    "name": .string("greet"), "type": .number(JSONNumber(rawValue: "1")),
                    "options": .array([.object(["name": .string("person"), "type": .number(JSONNumber(rawValue: "3")), "value": .string("Ada")])]),
                ])]),
            ])]),
        ]), expectedResponse: try InteractionResponse.message(InteractionMessageCreate(content: .value("Hello Ada"))).jsonValue())
    }

    /// The slash macro preserves immediate-modal ownership for root and grouped-leaf factories.
    /// - Throws: Unexpected schema, modal validation, compilation or response-owner errors fail the test.
    @Test func modalSlashMatchesHandwrittenHandler() async throws {
        let source = DefinitionSourceLocation(fileID: "Families.swift", line: 1, column: 1)
        let generatedHandler = GeneratedModalSlash()
        let generated = try CommandCompilation.compile(generatedHandler.contribution(id: "modal", source: source))
        let direct = try CommandCompilation.compile(DiscordCommandDSL.SlashCommand(id: "modal", handler: DirectModalSlash(), source: source))
        _ = try generatedHandler.slashSubcommand()
        try await compare(generated: generated, direct: direct, data: .object([
            "id": .string("8"), "name": .string("show"), "type": .number(JSONNumber(rawValue: "1")),
        ]), expectedResponse: try familyParityModal().interactionResponse.jsonValue())
    }

    /// Compares inert plans and then independently invokes their real compiled routes once.
    /// - Parameters:
    ///   - generated: Compiler-generated metadata/factory output compiled into a finite plan.
    ///   - direct: Independently handwritten protocol handler compiled through ordinary constructors.
    ///   - data: Trusted local command data for both independent response owners.
    ///   - expectedResponse: Exact complete callback JSON proving the selected typed response family executed.
    /// - Throws: Unexpected local interaction, route or payload validation errors fail the test.
    private func compare(generated: CompiledCommands, direct: CompiledCommands, data: JSONValue,
                         expectedResponse: JSONValue) async throws {
        #expect(generated.definitions.map { $0.request.jsonValue() } == direct.definitions.map { $0.request.jsonValue() })
        #expect(generated.description == direct.description)
        #expect(generated.routes.map(\.key) == direct.routes.map(\.key))
        let generatedTrace = FamilyParityTrace()
        let directTrace = FamilyParityTrace()
        let generatedContext = try context(data: data, trace: generatedTrace)
        let directContext = try context(data: data, trace: directTrace)
        let generatedRouter = try generated.makeRouter()
        let directRouter = try direct.makeRouter()
        #expect(await generatedTrace.responses.isEmpty)
        #expect(await directTrace.responses.isEmpty)
        #expect(try await generatedRouter.route(generatedContext))
        #expect(try await directRouter.route(directContext))
        #expect(await generatedTrace.responses == [expectedResponse])
        #expect(await directTrace.responses == [expectedResponse])
        let generatedState = await generatedContext.responder.snapshot()
        #expect(generatedState == (await directContext.responder.snapshot()))
        #expect(generatedState != .pending)
        #expect(await generatedRouter.activeHandlerCount == 0)
        #expect(await directRouter.activeHandlerCount == 0)
    }

    /// Builds an inert local command invocation whose sink only records callback JSON in an actor.
    /// - Parameters:
    ///   - data: Complete synthetic API v10 command data, including exact target or nested option path.
    ///   - trace: Response recorder isolated to this one invocation; no transport or credentials are created.
    /// - Returns: Pending HTTP-normalized context using the existing unique responder and monotonic clock.
    /// - Throws: Existing model, acknowledgement-admission or trusted-context validation errors.
    private func context(data: JSONValue, trace: FamilyParityTrace) throws -> InteractionContext {
        let interaction = try Interaction(data: JSONValue.object([
            "id": .string("18446744073709551615"), "application_id": .string("9"),
            "type": .number(JSONNumber(rawValue: "2")), "token": .string("synthetic"),
            "version": .number(JSONNumber(rawValue: "1")), "app_permissions": .string("0"),
            "entitlements": .array([]), "authorizing_integration_owners": .object([:]),
            "attachment_size_limit": .number(JSONNumber(rawValue: "10485760")), "data": data,
        ]).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .http,
            clock: InteractionClock(ContinuousClock()), sink: InteractionResponseSink(initial: { response, _ in
                await trace.record(try response.jsonValue())
            }), admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: .http, responder: responder)
    }
}

/// Generated immediate user-target declaration; no methods execute during expansion or compilation.
@UserCommand("Inspect User")
private struct GeneratedUserMenu: UserCommandHandler {
    /// Returns the selected user identifier while preserving unresolved same-interaction observations.
    /// - Parameters:
    ///   - context: Immutable invocation context without acknowledgement access.
    ///   - target: Invocation-local user reference carrying the full unsigned identifier.
    /// - Returns: One validated immediate JSON message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        #expect(target.user == .absent)
        return try MessageResponse(InteractionMessageCreate(content: .value("user:\(target.id.description)")))
    }
}

/// Independent handwritten user-menu metadata and behavior for direct runtime comparison.
private struct DirectUserMenu: UserCommandHandler {
    /// Supplies the exact display name independently of the macro-generated witness.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect User") }
    /// Returns the independently decoded selected user identifier.
    /// - Parameters:
    ///   - context: Immutable normalized invocation with no raw responder methods.
    ///   - target: Same-interaction user reference; the full identifier is retained.
    /// - Returns: One validated immediate message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        #expect(target.user == .absent)
        return try MessageResponse(InteractionMessageCreate(content: .value("user:\(target.id.description)")))
    }
}

/// Generated immediate message-target declaration with a target contract separate from user menus.
@MessageCommand("Inspect Message")
private struct GeneratedMessageMenu: MessageCommandHandler {
    /// Returns the selected message identity without fetching unresolved message data.
    /// - Parameters:
    ///   - context: Immutable normalized invocation with no response ownership operations.
    ///   - target: Exact message target retaining absent partial observations.
    /// - Returns: One validated JSON-only message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, target: MessageCommandTarget) async throws -> MessageResponse {
        #expect(target.message == .absent)
        return try MessageResponse(InteractionMessageCreate(content: .value("message:\(target.id.description)")))
    }
}

/// Independent handwritten message menu retaining the same display name and typed behavior.
private struct DirectMessageMenu: MessageCommandHandler {
    /// Supplies the exact registration name independently of compiler-generated metadata.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Message") }
    /// Produces an equivalent response from a separately decoded message target.
    /// - Parameters:
    ///   - context: Immutable command snapshot with no raw response owner.
    ///   - target: Same-invocation message identity and partial observations.
    /// - Returns: One validated immediate message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, target: MessageCommandTarget) async throws -> MessageResponse {
        #expect(target.message == .absent)
        return try MessageResponse(InteractionMessageCreate(content: .value("message:\(target.id.description)")))
    }
}

/// One generated schema supplies invocation-local typed state for both grouped implementations.
@CommandArguments
private struct FamilyLeafArguments {
    @Option(description: "Person") let person: String
}

/// The generated leaf factory is used only by an explicit root/group tree in the parity test.
@SlashCommand("greet", description: "Greet a person")
private struct GeneratedGroupedLeaf: SlashCommandHandler {
    typealias Arguments = FamilyLeafArguments
    /// Returns the decoded greeting without owning its group/root registration or response sink.
    /// - Parameters:
    ///   - context: Immutable invocation containing the complete root/group path.
    ///   - arguments: Fresh compiler-generated leaf arguments decoded only after exact route admission.
    /// - Returns: One validated immediate message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Hello \(arguments.person)")))
    }
}

/// Independent handwritten leaf proves grouping reuses the established typed handler contract.
private struct DirectGroupedLeaf: SlashCommandHandler {
    typealias Arguments = FamilyLeafArguments
    /// Supplies the same finite leaf metadata independently of the macro witness.
    var command: SlashCommandMetadata { .init(name: "greet", description: "Greet a person") }
    /// Produces the same greeting from independently decoded arguments at the exact group path.
    /// - Parameters:
    ///   - context: Immutable invocation with no acknowledgement operations.
    ///   - arguments: Fresh typed leaf values from the retained schema.
    /// - Returns: One validated JSON-only message.
    /// - Throws: Existing local message validation errors.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Hello \(arguments.person)")))
    }
}

/// Independent actor records only explicit route effects; constructing a plan leaves it empty.
private actor FamilyParityTrace {
    var responses: [JSONValue] = []
    /// Records exactly one locally serialized response in actor admission order.
    /// - Parameter response: Validated callback JSON from this invocation's unique existing responder.
    func record(_ response: JSONValue) { responses.append(response) }
}

/// An empty generated schema proves immediate modal handling needs no special argument reflection.
@CommandArguments
private struct FamilyModalArguments {}

/// Real macro expansion retains the modal-specific protocol instead of synthesizing manual ownership.
@SlashCommand("show", description: "Show information")
private struct GeneratedModalSlash: ModalSlashCommandHandler {
    typealias Arguments = FamilyModalArguments
    /// Produces a modal with no deferral or response-owner access.
    /// - Parameters:
    ///   - context: Immutable immediate command snapshot.
    ///   - arguments: Fresh empty typed aggregate decoded before work.
    /// - Returns: One validated information modal.
    /// - Throws: Existing modal/component validation errors.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> ModalResponse {
        try familyParityModal()
    }
}

/// Independent handwritten metadata and response signature for the legal immediate-modal family.
private struct DirectModalSlash: ModalSlashCommandHandler {
    typealias Arguments = FamilyModalArguments
    /// Supplies the same finite registration independently of compiler-generated members.
    var command: SlashCommandMetadata { .init(name: "show", description: "Show information") }
    /// Returns an equivalent modal through the separate typed immediate contract.
    /// - Parameters:
    ///   - context: Immutable immediate invocation snapshot.
    ///   - arguments: Fresh empty schema aggregate decoded before handler execution.
    /// - Returns: One locally validated modal callback.
    /// - Throws: Existing modal/component validation errors.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> ModalResponse {
        try familyParityModal()
    }
}

/// Constructs a controlled existing-model information modal with no custom decoding or I/O.
/// - Returns: One validated modal used by independent handlers and their explicit expected callback.
/// - Throws: Existing local component or modal definition validation errors.
private func familyParityModal() throws -> ModalResponse {
    let display = try MessageComponent(data: Data(#"{"type":10,"content":"Information"}"#.utf8))
    return ModalResponse(try InteractionModal(customID: "information", title: "Information", components: [display]))
}
