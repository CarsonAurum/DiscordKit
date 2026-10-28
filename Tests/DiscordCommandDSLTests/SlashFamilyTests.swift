// File: Tests/DiscordCommandDSLTests/SlashFamilyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import Foundation
import Testing

/// Synthetic grouped routing and catalog admission tests; construction owns no network or user work.
@Suite(.timeLimit(.minutes(1))) struct SlashFamilyTests {
    /// A custom family cannot charge one route's snapshot and retain another route's behavior.
    /// Both individual families are valid; their disagreement must fail compilation before any handler executes.
    /// - Throws: Unexpected valid exact-route construction errors fail the test.
    @Test func familySnapshotMismatch() throws {
        let advertised = ExistingCommandFamily(id: "forged", routes: [CommandRoute(key: try .component(customID: "advertised")) { _ in
            Issue.record("Compilation executed advertised behavior")
        }])
        let retained = ExistingCommandFamily(id: "retained", routes: [CommandRoute(key: try .component(customID: "retained")) { _ in
            Issue.record("Compilation executed retained behavior")
        }])
        #expect(try CommandCompilation.compile(advertised).routes.map(\.key) == advertised.family.routes.map(\.key))
        let forged = SnapshotMismatchFamily(declaration: advertised.declaration, family: retained.family)
        #expect(throws: CommandCompilationDiagnostic.self) { try CommandCompilation.compile(forged) }
    }

    /// Root/group/subcommand registration equals direct existing-model construction, with exact route order.
    /// HTTP and trusted normalized receipt modes preserve manual response ownership and fresh decoding.
    /// - Parameter gateway: Selects the injected delivery mode without creating a Gateway host.
    /// - Throws: Unexpected authoring, model or local routing errors fail this test.
    @Test(arguments: [false, true]) func groupedParityAndInvocation(gateway: Bool) async throws {
        let recorder = SlashFamilyRecorder()
        let leaf = try SlashSubcommand(handler: FamilyLeaf(recorder: recorder))
        let group = try SlashSubcommandGroup(name: "tools", description: "Tools", subcommands: [leaf],
            nameLocalizations: .value(["de": "werkzeuge"]))
        let command = SlashCommandMetadata(name: "utility", description: "Utilities", defaultMemberPermissions: .value("0"))
        let tree = try SlashCommandTree(id: "tree", command: command, children: [.subcommand(leaf), .group(group)])
        let compiled = try CommandCompilation.compile(tree)
        let direct = try CommandDefinition.slash(name: "utility", description: "Utilities", defaultMemberPermissions: .value("0")) {
            try ApplicationCommandOptionCreate(type: .subcommand, name: "lookup", description: "Lookup", options: [
                ApplicationCommandOptionCreate(type: .string, name: "query", description: "Query", required: true)
            ])
            try ApplicationCommandOptionCreate(type: .subcommandGroup, name: "tools", description: "Tools",
                nameLocalizations: .value(["de": "werkzeuge"]), options: [
                    ApplicationCommandOptionCreate(type: .subcommand, name: "lookup", description: "Lookup", options: [
                        ApplicationCommandOptionCreate(type: .string, name: "query", description: "Query", required: true)
                    ])
                ])
        }
        #expect(compiled.definitions[0].request.jsonValue() == direct.request.jsonValue())
        #expect(compiled.routes.map(\.key) == [try .command(name: "utility", path: ["lookup"]),
            try .command(name: "utility", path: ["tools", "lookup"])])
        #expect(await recorder.values.isEmpty)
        let router = try compiled.makeRouter()
        let mode: InteractionDeliveryMode = gateway ? .gateway : .http
        for path in [["lookup"], ["tools", "lookup"]] {
            let context = try SlashFamilyFixtures.context(path: path, options: #"[{"name":"query","type":3,"value":"Ada"}]"#, mode: mode)
            #expect(try await router.route(context))
            #expect(await context.responder.snapshot() == .pending)
        }
        #expect(await recorder.values == ["Ada", "Ada"])
        #expect(await router.activeHandlerCount == 0)
    }

    /// Empty subcommands admit omitted children; immediate/deferred/modal leaves retain separate callback families.
    /// - Throws: Unexpected synthetic route/response errors fail the test.
    @Test func emptyAndResponseFamilies() async throws {
        let immediate = try SlashSubcommand(handler: SlashFamilyImmediate())
        let deferred = try SlashSubcommand(handler: SlashFamilyDeferred())
        let modal = try SlashSubcommand(handler: SlashFamilyModal())
        let tree = try SlashCommandTree(id: "response-tree", command: .init(name: "utility", description: "Utilities"),
            children: [.subcommand(immediate), .subcommand(deferred), .subcommand(modal)])
        let plan = try CommandCompilation.compile(tree)
        let router = try plan.makeRouter()
        for (name, kind) in [("immediate", 4), ("deferred", 5), ("modal", 9)] {
            let recorder = SlashFamilyResponseRecorder()
            let context = try SlashFamilyFixtures.context(path: [name], options: nil, responseRecorder: recorder)
            if name == "deferred" {
                // Continuation editing is unsupported by this inert sink; defer itself must still succeed once.
                await #expect(throws: (any Error).self) { try await router.route(context) }
            } else { #expect(try await router.route(context)) }
            #expect(await recorder.types == [kind])
        }
        let root = try CommandCompilation.compile(try SlashCommand(id: "modal-root", handler: SlashFamilyModal()))
        let rootContext = try SlashFamilyFixtures.context(name: "modal", options: "[]")
        #expect(try await root.makeRouter().route(rootContext))
    }

    /// Structural metadata accounts every nested route; duplicate/empty/oversized groups and root-only leaf fields fail.
    /// - Throws: Unexpected valid authoring setup fails; expected admission errors are asserted.
    @Test func structuralAdmission() throws {
        let leaf = try SlashSubcommand(handler: FamilyLeaf(recorder: SlashFamilyRecorder()))
        #expect(throws: (any Error).self) { try SlashSubcommandGroup(name: "empty", description: "Empty", subcommands: []) }
        #expect(throws: (any Error).self) { try SlashSubcommandGroup(name: "duplicate", description: "Duplicate", subcommands: [leaf, leaf]) }
        #expect(throws: (any Error).self) { try SlashSubcommandGroup(name: "large", description: "Large", subcommands: Array(repeating: leaf, count: 26)) }
        #expect(throws: (any Error).self) {
            try SlashCommandTree(id: "empty", command: .init(name: "utility", description: "Utilities"), children: [])
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try SlashSubcommand(handler: FamilyLeaf(recorder: SlashFamilyRecorder(), rootSettings: true))
        }
        let group = try SlashSubcommandGroup(name: "tools", description: "Tools", subcommands: [leaf])
        let tree = try SlashCommandTree(id: "tree", command: .init(name: "utility", description: "Utilities"),
            children: [.subcommand(leaf), .group(group)])
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(tree, limits: .init(maxDeclarations: 1)) }
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(tree, limits: .init(maxTextBytes: 10)) }
        let compiled = try CommandCompilation.compile(tree)
        #expect(compiled.description.textBytes > 400)
        #expect(try CommandCompilation.compile(tree).description == compiled.description)
        #expect(throws: (any Error).self) {
            try SlashCommandTree(id: "duplicate", command: .init(name: "utility", description: "Utilities"),
                children: [.subcommand(leaf), .subcommand(leaf)])
        }
    }

    /// Wrong paths, unsupported kinds, invalid envelopes and incomplete arguments never execute user work.
    /// - Parameter variant: Independent malformed route/complete-argument case.
    /// - Throws: Setup failures fail; expected routing or decoding rejection is explicitly asserted.
    @Test(arguments: 0..<7) func malformedPaths(variant: Int) async throws {
        let recorder = SlashFamilyRecorder()
        let leaf = try SlashSubcommand(handler: FamilyLeaf(recorder: recorder))
        let tree = try SlashCommandTree(id: "tree", command: .init(name: "utility", description: "Utilities"),
            children: [.group(try SlashSubcommandGroup(name: "tools", description: "Tools", subcommands: [leaf]))])
        let router = try CommandCompilation.compile(tree).makeRouter()
        let context: InteractionContext
        switch variant {
        case 0: context = try SlashFamilyFixtures.context(path: ["tools", "other"], options: "[]")
        case 1: context = try SlashFamilyFixtures.context(path: ["lookup"], options: "[]")
        case 2: context = try SlashFamilyFixtures.context(path: ["tools", "lookup"], options: "[]", type: 4)
        case 3: context = try SlashFamilyFixtures.context(path: ["tools", "lookup"], options: "[]")
        case 4: context = try SlashFamilyFixtures.context(path: ["tools", "lookup"], options: #"[{"name":"query","type":3,"value":"x","focused":true}]"#)
        case 5: context = try SlashFamilyFixtures.context(options: #"[{"name":"tools","type":2,"focused":false,"options":[{"name":"lookup","type":1}]}]"#)
        default:
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try SlashFamilyFixtures.context(options: #"[{"name":"tools","type":2,"options":null}]"#)
            }
            #expect(await recorder.values.isEmpty)
            return
        }
        if variant == 3 || variant == 4 {
            await #expect(throws: ArgumentDiagnostic.self) { try await router.route(context) }
        } else { #expect(try await router.route(context) == false) }
        #expect(await recorder.values.isEmpty)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Existing adapters support names reused across types, app-owned entry points and Discord-owned launch registration.
    /// Coverage and duplicate exact identities fail at compilation before handlers execute.
    /// - Throws: Unexpected valid setup errors fail; invalid catalogs are explicitly rejected.
    @Test func existingFamiliesAndRegistrationCoverage() throws {
        let slash = try CommandDefinition.slash(name: "shared", description: "Shared")
        let user = try CommandDefinition.contextMenu(name: "shared", type: .user)
        let app = try CommandDefinition.entryPoint(name: "Open", description: "Open", handler: .appHandler)
        let launch = try CommandDefinition.entryPoint(name: "Launch", description: "Launch", handler: .discordLaunchActivity)
        let routes = try [CommandRoute(key: .command(name: "shared")) { _ in },
            CommandRoute(key: .command(name: "shared", type: .user)) { _ in },
            CommandRoute(key: .command(name: "Open", type: .primaryEntryPoint)) { _ in }]
        let family = ExistingCommandFamily(id: "existing", definitions: [slash, user, app, launch], routes: routes)
        let compiled = try CommandCompilation.compile(family)
        #expect(compiled.definitions.count == 4)
        #expect(compiled.routes.count == 3)
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(ExistingCommandFamily(id: "missing", definitions: [slash]))
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(ExistingCommandFamily(id: "duplicate", definitions: [slash, slash], routes: [routes[0]]))
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(ExistingCommandFamily(id: "wrong", definitions: [launch], routes: [routes[2]]))
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(ExistingCommandFamily(id: "duplicate-route", routes: [routes[0], routes[0]]))
        }
    }
}

/// A deliberately inconsistent public extension point proves compilation compares the complete immutable snapshot.
private struct SnapshotMismatchFamily: CommandFamilyContribution {
    let declaration: RawDefinitionContribution
    let family: CommandFamily
}

/// Shared synthetic command fixture for grouped and autocomplete tests; no authenticated network calls occur.
enum SlashFamilyFixtures {
    /// Builds a finite normalized interaction and its exact existing responder, without starting timers.
    /// - Parameters:
    ///   - name: Root slash name, default utility.
    ///   - path: Zero through two synthetic subcommand segments.
    ///   - options: Leaf JSON array, or nil to omit the final options field.
    ///   - type: Incoming command/autocomplete kind, default command.
    ///   - mode: Synthetic delivery mode, default HTTP.
    ///   - responseRecorder: Optional local initial-response observer.
    /// - Returns: Pending trusted-origin context with an inert initial sink and unsupported continuations.
    /// - Throws: JSON/model/response-owner fixture construction errors.
    static func context(name: String = "utility", path: [String] = [], options: String? = "[]", type: Int = 2,
        mode: InteractionDeliveryMode = .http, responseRecorder: SlashFamilyResponseRecorder? = nil) throws -> InteractionContext {
        var children = try options.map { try JSONValue.parse(Data($0.utf8)) }
        for index in path.indices.reversed() {
            var fields: [String: JSONValue] = ["name": .string(path[index]),
                "type": .number(try JSONNumber(rawValue: index == 0 && path.count == 2 ? "2" : "1"))]
            fields["options"] = children
            children = .array([.object(fields)])
        }
        var data: [String: JSONValue] = ["id": .string("8"), "name": .string(name),
            "type": .number(try JSONNumber(rawValue: "1"))]
        data["options"] = children
        let interaction = try Interaction(data: JSONValue.object([
            "id": .string("18446744073709551615"), "application_id": .string("9"),
            "type": .number(try JSONNumber(rawValue: String(type))), "token": .string("synthetic"),
            "version": .number(try JSONNumber(rawValue: "1")), "app_permissions": .string("0"),
            "entitlements": .array([]), "authorizing_integration_owners": .object([:]),
            "attachment_size_limit": .number(try JSONNumber(rawValue: "10485760")), "data": .object(data)
        ]).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode,
            clock: InteractionClock(ContinuousClock()), sink: InteractionResponseSink(initial: { response, _ in
                await responseRecorder?.record(response.type.rawValue)
            }), admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

/// Actor-local observations keep parallel synthetic invocations independent.
actor SlashFamilyRecorder {
    var values: [String] = []
    /// Appends one admitted decoded argument; no response or network work occurs.
    /// - Parameter value: Synthetic decoded argument.
    func record(_ value: String) { values.append(value) }
}

/// Local initial callback observer, preserving only bounded callback discriminators.
actor SlashFamilyResponseRecorder {
    var types: [Int] = []
    /// Records the single initial callback kind without retaining payloads.
    /// - Parameter type: Existing callback discriminator.
    func record(_ type: Int) { types.append(type) }
}

/// Typed required leaf used by direct-payload and complete-decoding tests.
private struct FamilyArguments: CommandArguments {
    let query: String
    /// Captures one required descriptor without constructing invocation values.
    static var schema: CommandArgumentSchema<Self> {
        /// Returns inert finite schema; descriptor/schema validation errors propagate.
        get throws {
            let query = try ArgumentOption<String>(name: "query", description: "Query")
            return try CommandArgumentSchema(options: [query.erased]) { try Self(query: $0.value(for: query)) }
        }
    }
}

/// No-input response-family schema; its constructor runs only during explicit invocation.
private struct FamilyEmptyArguments: CommandArguments {
    /// Returns an empty schema preserving zero-argument invocation semantics.
    static var schema: CommandArgumentSchema<Self> {
        /// Captures an inert empty constructor; schema errors propagate.
        get throws { try CommandArgumentSchema(options: []) { _ in Self() } }
    }
}

/// Manual leaf records complete decoded data while preserving its pending responder.
private struct FamilyLeaf: ManualSlashCommandHandler {
    let recorder: SlashFamilyRecorder
    var rootSettings = false
    /// Returns leaf metadata, optionally injecting a forbidden root setting for regression coverage.
    var command: SlashCommandMetadata { .init(name: "lookup", description: "Lookup", nsfw: rootSettings ? true : nil) }
    /// Records one invocation after all required values have passed decoding.
    /// - Parameters:
    ///   - context: Existing response owner, deliberately unused.
    ///   - arguments: Fresh complete invocation values.
    func execute(_ context: InteractionContext, arguments: FamilyArguments) async throws { await recorder.record(arguments.query) }
}

/// Immediate message leaf exercises response ownership without network operations.
private struct SlashFamilyImmediate: SlashCommandHandler {
    typealias Arguments = FamilyEmptyArguments
    /// Supplies inert immediate leaf metadata.
    var command: SlashCommandMetadata { .init(name: "immediate", description: "Immediate") }
    /// Returns one validated immediate message.
    /// - Parameters:
    ///   - context: Restricted immutable snapshot.
    ///   - arguments: Empty fully validated values.
    /// - Returns: Validated JSON message.
    /// - Throws: Unexpected model validation errors.
    func execute(_ context: CommandContext, arguments: FamilyEmptyArguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Ready")))
    }
}

/// Deferred message leaf verifies explicit defer followed by edit-original ownership.
private struct SlashFamilyDeferred: DeferredSlashCommandHandler {
    typealias Arguments = FamilyEmptyArguments
    /// Supplies inert deferred leaf metadata.
    var command: SlashCommandMetadata { .init(name: "deferred", description: "Deferred") }
    /// Returns a validated deferred original edit for the existing continuation owner.
    /// - Parameters:
    ///   - context: Restricted post-defer snapshot.
    ///   - arguments: Empty admitted values.
    /// - Returns: Deferred-only original edit.
    /// - Throws: Unexpected model validation errors.
    func execute(_ context: DeferredCommandContext, arguments: FamilyEmptyArguments) async throws -> DeferredMessageResponse {
        try DeferredMessageResponse(InteractionMessageEdit(content: .value("Ready"), deferredResponse: true))
    }
}

/// Modal-only leaf exposes no competing message or defer response method.
private struct SlashFamilyModal: ModalSlashCommandHandler {
    typealias Arguments = FamilyEmptyArguments
    /// Supplies inert modal leaf metadata.
    var command: SlashCommandMetadata { .init(name: "modal", description: "Modal") }
    /// Returns a validated label/text-input modal for later separate submission handling.
    /// - Parameters:
    ///   - context: Restricted immutable invocation snapshot.
    ///   - arguments: Empty fully admitted values.
    /// - Returns: An existing-model modal wrapped in the legal initial response family.
    /// - Throws: Existing modal/component validation errors.
    func execute(_ context: CommandContext, arguments: FamilyEmptyArguments) async throws -> ModalResponse {
        ModalResponse(try InteractionModal(customID: "edit", title: "Edit", components: [
            MessageComponent(data: Data(#"{"type":1,"components":[{"type":4,"custom_id":"text","style":1,"label":"Text"}]}"#.utf8))
        ]))
    }
}
