// File: Tests/DiscordCommandDSLTests/FamilyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import Foundation
import Testing

/// Synthetic exact-route and typed-response evidence. No test registers commands, fetches resources,
/// connects to Discord, or qualifies live notification, client interoperability or display behavior.
@Suite(.timeLimit(.minutes(1))) struct InteractionFamilyTests {
    /// Context-menu lowering matches direct models, preserves all metadata and never executes retained work.
    /// - Throws: Unexpected fixture/model/schema construction errors fail the test.
    @Test func metadataAndInertConstruction() async throws {
        let recorder = InteractionFamilyRecorder()
        let metadata = ContextMenuCommandMetadata(name: "Inspect Person", nameLocalizations: .value(["en-US": "Inspect Person"]),
            defaultMemberPermissions: .value("8"), integrationTypes: [.guildInstall], contexts: [.guild], nsfw: true)
        let source = DefinitionSourceLocation(fileID: "Families", line: 7, column: 3)
        let user = try UserCommand(id: "user", handler: InteractionFamilyUser(metadata: metadata, recorder: recorder), source: source)
        let compiled = try CommandCompilation.compile(user)
        let direct = try CommandDefinition.contextMenu(name: metadata.name, type: .user,
            nameLocalizations: metadata.nameLocalizations, defaultMemberPermissions: metadata.defaultMemberPermissions,
            integrationTypes: metadata.integrationTypes, contexts: metadata.contexts, nsfw: metadata.nsfw)
        #expect(compiled.definitions[0].request.jsonValue() == direct.request.jsonValue())
        #expect(compiled.routes[0].key == (try .command(name: metadata.name, type: .user)))
        #expect(compiled.description.declarations[0].declaration.source == source)
        #expect(await recorder.events.isEmpty)
        #expect(throws: CommandCompilationDiagnostic.self) {
            try UserCommand(id: "invalid", handler: InteractionFamilyUser(metadata: .init(name: ""), recorder: recorder))
        }
        #expect(throws: DiscordError.self) { try ComponentCommand(id: "invalid", handler: InteractionFamilyComponent(customID: "", recorder: recorder)) }
        #expect(throws: DiscordError.self) {
            try ComponentCommand(id: "invalid", handler: InteractionFamilyComponent(componentType: .textInput, recorder: recorder))
        }
        #expect(throws: DiscordError.self) { try ModalCommand(id: "invalid", handler: InteractionFamilyModal(customID: "", recorder: recorder)) }
        let message = try MessageCommand(id: "message", handler: InteractionFamilyMessage(recorder: recorder))
        #expect(message.family.definitions[0].request.type == .message)
        let component = try ComponentCommand(id: "component", handler: InteractionFamilyComponent(recorder: recorder))
        let modal = try ModalCommand(id: "modal", handler: InteractionFamilyModal(recorder: recorder))
        #expect(component.family.definitions.isEmpty)
        #expect(modal.family.definitions.isEmpty)
        #expect(component.family.routes[0].key != modal.family.routes[0].key)
        let emptyMessage = MessageCommandTarget(id: MessageID(rawValue: UInt64.max))
        #expect(emptyMessage.message == .absent)
    }

    /// User and message targets preserve full snowflakes and optional partial resolved objects in either receipt mode.
    /// - Parameters:
    ///   - user: Selects user rather than message target domain.
    ///   - mode: HTTP or trusted normalized Gateway receipt; both use an injected local response sink.
    /// - Throws: Unexpected fixture or routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [InteractionDeliveryMode.http, .gateway])
    func contextMenuTarget(user: Bool, mode: InteractionDeliveryMode) async throws {
        let recorder = InteractionFamilyRecorder()
        let data = try Self.commandData(user: user, resolved: user ? #"{"users":{"18446744073709551615":{"id":"18446744073709551615","username":"partial","discriminator":"0","avatar":null}},"members":{"18446744073709551615":{"nick":"partial"}}}"# : #"{"messages":{"18446744073709551615":{"id":"18446744073709551615","content":"partial-only"}}}"#)
        let context = try Self.context(kind: 2, data: data, recorder: recorder, mode: mode)
        let compiled = user ? try CommandCompilation.compile(UserCommand(id: "u", handler: InteractionFamilyUser(recorder: recorder)))
            : try CommandCompilation.compile(MessageCommand(id: "m", handler: InteractionFamilyMessage(recorder: recorder)))
        #expect(try await compiled.makeRouter().route(context))
        #expect(await recorder.events == [user ? "user:18446744073709551615:resolved" : "message:18446744073709551615:resolved", "initial:4"])
        #expect(await context.responder.snapshot() == .acknowledged(.channelMessageWithSource))
    }

    /// Missing/null targets, slash-only options and contradictory resolved IDs fail before acknowledgement or work.
    /// - Parameters:
    ///   - user: Selects the user or message context-menu handler.
    ///   - defect: Injects missing/null target, nonempty/null options, or contradictory resolved identity.
    /// - Throws: Unexpected fixture errors fail; routing failures and untouched ownership are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [0, 1, 2, 3, 4])
    func invalidTargetBeforeExecution(user: Bool, defect: Int) async throws {
        let recorder = InteractionFamilyRecorder()
        var data = try Self.commandData(user: user)
        if defect == 0 { data.removeValue(forKey: "target_id") }
        if defect == 1 { data["target_id"] = .null }
        if defect == 2 { data["options"] = try Self.json(#"[{"name":"unexpected","type":3,"value":"x"}]"#) }
        if defect == 3 { data["options"] = .null }
        if defect == 4 {
            data["resolved"] = try Self.json(user ? #"{"users":{"18446744073709551615":{"id":"2","username":"bad","discriminator":"0","avatar":null}}}"# : #"{"messages":{"18446744073709551615":{"id":"2"}}}"#)
        }
        if defect == 1 || defect == 3 {
            #expect(throws: DiscordError.self) { try Self.context(kind: 2, data: data, recorder: recorder) }
            #expect(await recorder.events.isEmpty)
            return
        }
        let context = try Self.context(kind: 2, data: data, recorder: recorder)
        let compiled = user ? try CommandCompilation.compile(UserCommand(id: "u", handler: InteractionFamilyDeferredUser(recorder: recorder)))
            : try CommandCompilation.compile(MessageCommand(id: "m", handler: InteractionFamilyDeferredMessage(recorder: recorder)))
        await #expect(throws: (any Error).self) { try await compiled.makeRouter().route(context) }
        #expect(await recorder.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Explicit deferred/manual context-menu protocols retain one responder, fixed visibility and correct order.
    /// - Parameter variant: User/message crossed with deferred/manual execution.
    /// - Throws: Unexpected fixture/routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2, 3]) func contextMenuOwnership(variant: Int) async throws {
        let recorder = InteractionFamilyRecorder(), user = variant < 2, manual = variant % 2 == 1
        let compiled: CompiledCommands
        switch variant {
        case 0: compiled = try CommandCompilation.compile(UserCommand(id: "u", handler: InteractionFamilyDeferredUser(recorder: recorder)))
        case 1: compiled = try CommandCompilation.compile(UserCommand(id: "u", handler: InteractionFamilyManualUser(recorder: recorder)))
        case 2: compiled = try CommandCompilation.compile(MessageCommand(id: "m", handler: InteractionFamilyDeferredMessage(recorder: recorder)))
        default: compiled = try CommandCompilation.compile(MessageCommand(id: "m", handler: InteractionFamilyManualMessage(recorder: recorder)))
        }
        #expect(await recorder.events.isEmpty)
        let context = try Self.context(kind: 2, data: Self.commandData(user: user), recorder: recorder)
        #expect(try await compiled.makeRouter().route(context))
        #expect(await recorder.events == (manual ? ["manual", "initial:4"] : ["initial:5", "deferred", "edit"]))
    }

    /// Button/select input is exact, finite, namespace-separated, and rejects unrelated IDs without running work.
    /// - Throws: Unexpected fixture or routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func componentAndModalNamespaces() async throws {
        let recorder = InteractionFamilyRecorder()
        let component = try ComponentCommand(id: "component", handler: InteractionFamilyComponent(recorder: recorder))
        let modal = try ModalCommand(id: "modal", handler: InteractionFamilyModal(recorder: recorder))
        let router = try CommandRouter(routes: component.family.routes + modal.family.routes)
        let componentContext = try Self.context(kind: 3, data: ["custom_id": .string("shared"), "component_type": .number(JSONNumber(rawValue: "2"))], recorder: recorder, sourceMessage: true)
        #expect(try await router.route(componentContext))
        let modalContext = try Self.context(kind: 5, data: Self.modalData(), recorder: recorder)
        #expect(try await router.route(modalContext))
        #expect(await recorder.events == ["component:0", "initial:7", "modal:hello:false", "initial:4"])
        let unmatched = try Self.context(kind: 3, data: ["custom_id": .string("shared:suffix"), "component_type": .number(JSONNumber(rawValue: "2"))], recorder: recorder, sourceMessage: true)
        #expect(try await router.route(unmatched) == false)
        #expect(await unmatched.responder.snapshot() == .pending)
    }

    /// Current selects preserve empty/value order and partial resolution; malformed kinds/counts/values fail locally.
    /// - Throws: Unexpected controlled projection errors fail the test.
    @Test func componentInputValidation() throws {
        for kind in [ComponentType.stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect] {
            let values = kind == .stringSelect ? ["a", "b"] : ["18446744073709551615", "2"]
            let data = try InteractionComponentData(data: Self.json(#"{"custom_id":"x","component_type":\#(kind.rawValue),"values":[],"resolved":{}}"#).serialized())
            let empty = try ComponentInput(data, componentType: kind)
            #expect(empty.values.isEmpty)
            let supplied = try InteractionComponentData(data: JSONValue.object(["custom_id": .string("x"), "component_type": .number(JSONNumber(rawValue: String(kind.rawValue))), "values": .array(values.map(JSONValue.string))]).serialized())
            #expect(try ComponentInput(supplied, componentType: kind).values == values)
        }
        for json in [#"{"custom_id":"x","component_type":2,"values":[]}"#,
            #"{"custom_id":"x","component_type":5,"values":["bad"]}"#,
            #"{"custom_id":"x","component_type":3,"values":["same","same"]}"#,
            #"{"custom_id":"x","component_type":999}"#,
            #"{"custom_id":"","component_type":2}"#] {
            let data = try InteractionComponentData(data: Data(json.utf8))
            let kind = data.componentType.knownValue ?? .button
            #expect(throws: DiscordError.self) { try ComponentInput(data, componentType: kind) }
        }
        #expect(throws: DiscordError.self) {
            try InteractionComponentData(data: Data(#"{"custom_id":"x","component_type":3,"values":null}"#.utf8))
        }
        let button = try InteractionComponentData(data: Data(#"{"custom_id":"x","component_type":2}"#.utf8))
        #expect(throws: DiscordError.self) { try ComponentInput(button, componentType: .stringSelect) }
        let tooMany = try InteractionComponentData(data: JSONValue.object(["custom_id": .string("x"), "component_type": .number(JSONNumber(rawValue: "3")), "values": .array((0..<26).map { .string(String($0)) })]).serialized())
        #expect(throws: DiscordError.self) { try ComponentInput(tooMany, componentType: .stringSelect) }
    }

    /// Missing component source messages and typed modal updates fail before any handler or callback.
    /// - Parameter modal: Selects the modal update family rather than a component update.
    /// - Throws: Unexpected fixture errors fail; exact no-work ownership behavior is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func missingSourceMessage(modal: Bool) async throws {
        let recorder = InteractionFamilyRecorder()
        let compiled = modal ? try CommandCompilation.compile(ModalCommand(id: "m", handler: InteractionFamilyModalUpdate(recorder: recorder)))
            : try CommandCompilation.compile(ComponentCommand(id: "c", handler: InteractionFamilyComponent(recorder: recorder)))
        let data = try (modal ? Self.modalData() : ["custom_id": .string("shared"), "component_type": .number(JSONNumber(rawValue: "2"))])
        let context = try Self.context(kind: modal ? 5 : 3, data: data, recorder: recorder)
        await #expect(throws: (any Error).self) { try await compiled.makeRouter().route(context) }
        #expect(await recorder.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Immediate modal/update wrappers preserve exact existing payloads and redact nested content.
    /// - Throws: Unexpected fixture construction errors fail; illegal deferred updates are asserted.
    @Test func responseWrappers() throws {
        let input = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":4,"custom_id":"text","style":1,"label":"Text"}]}"#.utf8))
        let definition = try InteractionModal(customID: "private-marker", title: "Private", components: [input])
        let modal = ModalResponse(definition)
        #expect(try modal.interactionResponse.jsonValue(interactionType: .applicationCommand) == InteractionResponse.modal(definition).jsonValue(interactionType: .applicationCommand))
        let update = try UpdateMessageResponse(InteractionMessageEdit(content: .null, embeds: .value([])))
        #expect(try update.edit.jsonValue() == .object(["content": .null, "embeds": .array([])]))
        #expect(UpdateMessageResponse.requiresSourceMessage)
        #expect(!MessageResponse.requiresSourceMessage)
        #expect(throws: DiscordError.self) { try UpdateMessageResponse(InteractionMessageEdit(deferredResponse: true)) }
        for value in [modal as any CustomStringConvertible, update] {
            #expect(value.description.hasSuffix("(redacted)"))
            #expect(String(reflecting: value).hasSuffix("(redacted)"))
            #expect(Mirror(reflecting: value).children.count == 1)
        }
    }

    /// Component/modal defers precede user work, use explicit callback kinds, and complete through one edit.
    /// - Parameters:
    ///   - modal: Selects typed modal fields rather than button input.
    ///   - update: Selects update defer rather than an ephemeral loading message.
    /// - Throws: Unexpected fixture or routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func deferredComponentModal(modal: Bool, update: Bool) async throws {
        let recorder = InteractionFamilyRecorder(), mode: DeferredInteractionResponseMode = update ? .update : .message(.ephemeral)
        let compiled = modal ? try CommandCompilation.compile(ModalCommand(id: "m", handler: InteractionFamilyDeferredModal(responseMode: mode, recorder: recorder)))
            : try CommandCompilation.compile(ComponentCommand(id: "c", handler: InteractionFamilyDeferredComponent(responseMode: mode, recorder: recorder)))
        #expect(await recorder.events.isEmpty)
        let data = try (modal ? Self.modalData() : ["custom_id": .string("shared"), "component_type": .number(JSONNumber(rawValue: "2"))])
        let context = try Self.context(kind: modal ? 5 : 3, data: data, recorder: recorder, sourceMessage: true)
        #expect(try await compiled.makeRouter().route(context))
        #expect(await recorder.events == [update ? "initial:6" : "initial:5", "deferred", "edit"])
        #expect(await context.responder.snapshot() == .acknowledged(update ? .deferredUpdateMessage : .deferredChannelMessageWithSource))
    }

    /// Manual component/modal behavior uses only its retained response owner and creates no automatic callback.
    /// - Parameter modal: Selects a modal submission rather than button input.
    /// - Throws: Unexpected fixture or routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func manualComponentModal(modal: Bool) async throws {
        let recorder = InteractionFamilyRecorder()
        let compiled = modal ? try CommandCompilation.compile(ModalCommand(id: "m", handler: InteractionFamilyManualModal(recorder: recorder)))
            : try CommandCompilation.compile(ComponentCommand(id: "c", handler: InteractionFamilyManualComponent(recorder: recorder)))
        let data = try (modal ? Self.modalData() : ["custom_id": .string("shared"), "component_type": .number(JSONNumber(rawValue: "2"))])
        let context = try Self.context(kind: modal ? 5 : 3, data: data, recorder: recorder, sourceMessage: true)
        #expect(try await compiled.makeRouter().route(context))
        #expect(await recorder.events == ["manual", "initial:4"])
    }

    /// Cancellation immediately before routing or at handler return cannot transmit a callback and releases admission.
    /// - Parameter before: Cancel before admission rather than while returning a valid response.
    /// - Throws: Unexpected fixture errors fail; cancellation is asserted exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func cancellation(before: Bool) async throws {
        let recorder = InteractionFamilyRecorder()
        let command = try UserCommand(id: "u", handler: InteractionFamilyCancellingUser(recorder: recorder))
        let router = try CommandCompilation.compile(command).makeRouter()
        let context = try Self.context(kind: 2, data: Self.commandData(user: true), recorder: recorder)
        let task = Task {
            if before { withUnsafeCurrentTask { $0?.cancel() } }
            return try await router.route(context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.events == (before ? [] : ["cancelled"]))
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }


    /// Invalid modal fields are rejected before explicit defer and before any typed user handler work.
    /// - Parameter defect: Supplies undeclared, wrong-kind, repeated, or missing required fields.
    /// - Throws: Unexpected fixture errors fail; no-response ownership is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2, 3]) func invalidModalBeforeDeferredWork(defect: Int) async throws {
        let recorder = InteractionFamilyRecorder()
        var data = try Self.modalData()
        let roots: String
        switch defect {
        case 0: roots = #"[{"type":18,"component":{"type":4,"custom_id":"extra","value":"x"}}]"#
        case 1: roots = #"[{"type":18,"component":{"type":23,"custom_id":"text","value":true}}]"#
        case 2: roots = #"[{"type":18,"component":{"type":4,"custom_id":"text","value":"a"}},{"type":18,"component":{"type":4,"custom_id":"text","value":"b"}}]"#
        default: roots = #"[{"type":18,"component":{"type":4,"custom_id":"text","value":"x"}}]"#
        }
        data["components"] = try Self.json(roots)
        let context = try Self.context(kind: 5, data: data, recorder: recorder)
        let router = try CommandCompilation.compile(ModalCommand(id: "m", handler: InteractionFamilyDeferredModal(recorder: recorder))).makeRouter()
        await #expect(throws: (any Error).self) { try await router.route(context) }
        #expect(await recorder.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Public response protocol conformers cannot escape a family's legal callback allowlist at runtime.
    /// - Throws: Unexpected fixture errors fail; exact pre-send validation and unchanged ownership are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func customResponseCannotBypassFamily() async throws {
        let recorder = InteractionFamilyRecorder()
        let context = try Self.context(kind: 2, data: Self.commandData(user: true), recorder: recorder)
        let router = try CommandCompilation.compile(UserCommand(id: "u", handler: ForbiddenUserResponseHandler())).makeRouter()
        await #expect(throws: DiscordError.self) { try await router.route(context) }
        #expect(await recorder.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Parses exact small JSON fixture text without changing numeric spelling or resource presence.
    /// - Parameter source: Controlled JSON fixture text.
    /// - Returns: Bounded immutable JSON tree.
    /// - Throws: Fixture syntax/bounds errors.
    private static func json(_ source: String) throws -> JSONValue { try JSONValue.parse(Data(source.utf8)) }

    /// Produces an admitted menu-data object with an extreme target snowflake and optional partial maps.
    /// - Parameters:
    ///   - user: Selects the user or message command discriminator.
    ///   - resolved: Optional complete resolved-data JSON; nil omits it.
    /// - Returns: Finite normalized command data with no slash options.
    /// - Throws: Controlled fixture JSON errors.
    private static func commandData(user: Bool, resolved: String? = nil) throws -> [String: JSONValue] {
        var data: [String: JSONValue] = ["id": .string("8"), "name": .string(user ? "Inspect Person" : "Inspect Message"),
            "type": .number(try JSONNumber(rawValue: user ? "2" : "3")), "target_id": .string(String(UInt64.max))]
        if let resolved { data["resolved"] = try json(resolved) }
        return data
    }

    /// Returns the current-label modal fixture with explicit empty text preservation and unchecked state.
    /// - Returns: Two completely typed label children in wire order.
    /// - Throws: Controlled fixture parse errors.
    private static func modalData() throws -> [String: JSONValue] {
        guard case .object(let fields) = try json(#"{"custom_id":"shared","components":[{"type":18,"component":{"type":4,"custom_id":"text","value":"hello"}},{"type":18,"component":{"type":23,"custom_id":"checked","value":false}}]}"#)
        else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Builds an inert normalized synthetic context with virtual time and an injected response recorder.
    /// - Parameters:
    ///   - kind: Known interaction discriminator selected by the fixture.
    ///   - data: Complete corresponding command/component/modal data.
    ///   - recorder: Isolated response/work observer; no real transport is created.
    ///   - mode: Synthetic receipt mode, default HTTP.
    ///   - sourceMessage: Whether to include a full triggering message, default false.
    /// - Returns: One exact context/responder pair with pending acknowledgement ownership.
    /// - Throws: Controlled fixture projection/context/admission errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func context(kind: Int, data: [String: JSONValue], recorder: InteractionFamilyRecorder,
        mode: InteractionDeliveryMode = .http, sourceMessage: Bool = false) throws -> InteractionContext {
        var fields: [String: JSONValue] = ["id": .string("7"), "application_id": .string("9"),
            "type": .number(try JSONNumber(rawValue: String(kind))), "version": .number(try JSONNumber(rawValue: "1")),
            "token": .string("fixture-token"), "app_permissions": .string("0"), "entitlements": .array([]),
            "authorizing_integration_owners": .object([:]), "attachment_size_limit": .number(try JSONNumber(rawValue: "10485760")), "data": .object(data)]
        if sourceMessage { fields["message"] = try json(familyMessageJSON) }
        let interaction = try Interaction(data: JSONValue.object(fields).serialized())
        let clock = ManualClock()
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode, clock: InteractionClock(clock),
            sink: InteractionResponseSink(initial: { response, _ in await recorder.append("initial:\(response.type.rawValue)") },
                editOriginal: { _, _ in await recorder.append("edit"); return try Message(data: Data(familyMessageJSON.utf8)) }),
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

private let familyMessageJSON = #"{"id":"1","channel_id":"2","author":{"id":"3","username":"fixture","discriminator":"0","avatar":null},"content":"Done","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#

/// Per-test actor-isolated event recorder without detached work or live transport.
private actor InteractionFamilyRecorder {
    var events: [String] = []
    /// Appends one bounded synthetic event, preserving observed ordering across suspension points.
    /// - Parameter event: Fixed test marker; never credentials or raw user content.
    func append(_ event: String) { events.append(event) }
}

/// Inert immediate user fixture using exact user-domain target observations.
private struct InteractionFamilyUser: UserCommandHandler {
    var metadata = ContextMenuCommandMetadata(name: "Inspect Person")
    let recorder: InteractionFamilyRecorder
    /// Returns captured finite registration metadata without executing behavior.
    var command: ContextMenuCommandMetadata { metadata }
    /// Records selected identity and partial presence, then returns an immediate JSON-only message.
    /// - Parameters:
    ///   - context: Immutable normalized fixture snapshot without response ownership.
    ///   - target: Validated user target, including all 64 bits and optional user/member projections.
    /// - Returns: A validated message without sending it directly.
    /// - Throws: Controlled message validation errors.
    func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        let presence = if case .value = target.user { "resolved" } else { "missing" }
        await recorder.append("user:\(target.id):\(presence)")
        return try MessageResponse(InteractionMessageCreate(content: .value("selected")))
    }
}

/// Inert immediate message fixture accepting a partial message rather than requiring a full resource.
private struct InteractionFamilyMessage: MessageCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic message-menu metadata without work.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Message") }
    /// Records exact target/partial presence and returns a validated message.
    /// - Parameters:
    ///   - context: Immutable normalized fixture snapshot.
    ///   - target: Exact message-domain reference with optional partial observation.
    /// - Returns: An immediate JSON-only message.
    /// - Throws: Controlled message validation errors.
    func execute(_ context: CommandContext, target: MessageCommandTarget) async throws -> MessageResponse {
        let presence = if case .value = target.message { "resolved" } else { "missing" }
        await recorder.append("message:\(target.id):\(presence)")
        return try MessageResponse(InteractionMessageCreate(content: .value("selected")))
    }
}

/// Typed two-field submission aggregate used by immediate, deferred and manual modal fixtures.
private struct InteractionFamilyModalValues: ModalValues {
    let text: String
    let checked: Bool
    /// Returns a finite deterministic schema without constructing aggregate values or executing work.
    static var schema: ModalSchema<Self> {
        /// Validates exact text/checkbox field descriptors before any invocation is admitted.
        /// - Returns: A fresh aggregate constructor with no network or acknowledgement ownership.
        /// - Throws: Controlled descriptor/schema validation errors.
        get throws {
            let text = try ModalField<String>(customID: "text"), checked = try ModalField<Bool>(customID: "checked")
            return try ModalSchema(fields: [text.erased, checked.erased]) {
                try Self(text: $0.value(for: text), checked: $0.value(for: checked))
            }
        }
    }
}

/// Controlled deferred user target fixture with inert captured metadata.
private struct InteractionFamilyDeferredUser: DeferredUserCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic menu registration without handler execution or I/O.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Person") }
    /// Explicitly fixes ephemeral visibility when the initial acknowledgement succeeds.
    var responseVisibility: CommandResponseVisibility { .ephemeral }
    /// Records admitted work and returns one deferred original edit.
    /// - Parameters:
    ///   - context: Confirmed-defer immutable snapshot after complete target admission.
    ///   - target: Validated same-interaction user identity and optional partial observations.
    /// - Returns: A validated original edit with explicit deferred-response evidence.
    /// - Throws: Controlled model or responder failures; no fallback or retry occurs.
    func execute(_ context: DeferredCommandContext, target: UserReference) async throws -> DeferredMessageResponse {
        await recorder.append("deferred")
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("done"), deferredResponse: true))
    }
}

/// Controlled manual user target fixture with inert captured metadata.
private struct InteractionFamilyManualUser: ManualUserCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic menu registration without handler execution or I/O.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Person") }
    /// Records admitted work and explicitly sends one initial message.
    /// - Parameters:
    ///   - context: Existing exact responder after complete target admission.
    ///   - target: Validated same-interaction user identity and optional partial observations.
    /// - Throws: Controlled model or responder failures; no fallback or retry occurs.
    func execute(_ context: InteractionContext, target: UserReference) async throws {
        await recorder.append("manual")
        try await context.responder.reply(InteractionMessageCreate(content: .value("done")))
    }
}

/// Controlled deferred message target fixture with inert captured metadata.
private struct InteractionFamilyDeferredMessage: DeferredMessageCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic menu registration without handler execution or I/O.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Message") }
    /// Records admitted work and returns one deferred original edit.
    /// - Parameters:
    ///   - context: Confirmed-defer immutable snapshot after complete target admission.
    ///   - target: Validated same-interaction message identity and optional partial observations.
    /// - Returns: A validated original edit with explicit deferred-response evidence.
    /// - Throws: Controlled model or responder failures; no fallback or retry occurs.
    func execute(_ context: DeferredCommandContext, target: MessageCommandTarget) async throws -> DeferredMessageResponse {
        await recorder.append("deferred")
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("done"), deferredResponse: true))
    }
}

/// Controlled manual message target fixture with inert captured metadata.
private struct InteractionFamilyManualMessage: ManualMessageCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic menu registration without handler execution or I/O.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Message") }
    /// Records admitted work and explicitly sends one initial message.
    /// - Parameters:
    ///   - context: Existing exact responder after complete target admission.
    ///   - target: Validated same-interaction message identity and optional partial observations.
    /// - Throws: Controlled model or responder failures; no fallback or retry occurs.
    func execute(_ context: InteractionContext, target: MessageCommandTarget) async throws {
        await recorder.append("manual")
        try await context.responder.reply(InteractionMessageCreate(content: .value("done")))
    }
}

/// Controlled immediate component fixture with no work during construction.
private struct InteractionFamilyComponent: ComponentHandler {
    var customID = "shared"
    var componentType: ComponentType = .button
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Immutable restricted snapshot after complete input admission.
    ///   - input: Validated button/select observation without hydration.
    /// - Returns: An immediate source-message update.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: CommandContext, input: ComponentInput) async throws -> UpdateMessageResponse {
        await recorder.append("component:\(input.values.count)")
        return try UpdateMessageResponse(InteractionMessageEdit(content: .value("updated")))
    }
}

/// Controlled deferred component fixture with no work during construction.
private struct InteractionFamilyDeferredComponent: DeferredComponentHandler {
    var customID = "shared"
    var componentType: ComponentType = .button
    var responseMode: DeferredInteractionResponseMode = .message(.public)
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Confirmed-defer snapshot after complete input admission.
    ///   - input: Validated button/select observation without hydration.
    /// - Returns: One validated original edit.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: DeferredCommandContext, input: ComponentInput) async throws -> DeferredMessageResponse {
        await recorder.append("deferred")
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("done"), deferredResponse: responseMode != .update))
    }
}

/// Controlled manual component fixture with no work during construction.
private struct InteractionFamilyManualComponent: ManualComponentHandler {
    var customID = "shared"
    var componentType: ComponentType = .button
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Exact explicit response owner after complete input admission.
    ///   - input: Validated button/select observation without hydration.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: InteractionContext, input: ComponentInput) async throws {
        await recorder.append("manual")
        try await context.responder.reply(InteractionMessageCreate(content: .value("done")))
    }
}

/// Controlled immediate modal fixture with no work during construction.
private struct InteractionFamilyModal: ModalHandler {
    typealias Values = InteractionFamilyModalValues
    var customID = "shared"
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Immutable restricted snapshot after complete input admission.
    ///   - values: Validated fresh typed modal fields without hydration.
    /// - Returns: One validated immediate message.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: CommandContext, values: InteractionFamilyModalValues) async throws -> MessageResponse {
        await recorder.append("modal:\(values.text):\(values.checked)")
        return try MessageResponse(InteractionMessageCreate(content: .value("submitted")))
    }
}

/// Controlled deferred modal fixture with no work during construction.
private struct InteractionFamilyDeferredModal: DeferredModalHandler {
    typealias Values = InteractionFamilyModalValues
    var customID = "shared"
    var responseMode: DeferredInteractionResponseMode = .message(.public)
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Confirmed-defer snapshot after complete input admission.
    ///   - values: Validated fresh typed modal fields without hydration.
    /// - Returns: One validated original edit.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: DeferredCommandContext, values: InteractionFamilyModalValues) async throws -> DeferredMessageResponse {
        await recorder.append("deferred")
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("done"), deferredResponse: responseMode != .update))
    }
}

/// Controlled manual modal fixture with no work during construction.
private struct InteractionFamilyManualModal: ManualModalHandler {
    typealias Values = InteractionFamilyModalValues
    var customID = "shared"
    let recorder: InteractionFamilyRecorder
    /// Records admitted input and completes the selected explicit response policy.
    /// - Parameters:
    ///   - context: Exact explicit response owner after complete input admission.
    ///   - values: Validated fresh typed modal fields without hydration.
    /// - Throws: Controlled model/lifecycle failures; failures never create fallback or retry work.
    func execute(_ context: InteractionContext, values: InteractionFamilyModalValues) async throws {
        await recorder.append("manual")
        try await context.responder.reply(InteractionMessageCreate(content: .value("done")))
    }
}

/// Modal update fixture proving source-message admission occurs before user work.
private struct InteractionFamilyModalUpdate: ModalHandler {
    typealias Values = MissingSourceModalValues
    let recorder: InteractionFamilyRecorder
    /// Returns the exact shared namespace ID without work.
    var customID: String { "shared" }
    /// Records admitted work and returns a JSON-only source update.
    /// - Parameters:
    ///   - context: Immutable snapshot whose triggering message has already been required.
    ///   - values: Fully validated fresh modal aggregate.
    /// - Returns: One validated immediate original-message update.
    /// - Throws: Controlled edit validation errors.
    func execute(_ context: CommandContext, values: MissingSourceModalValues) async throws -> UpdateMessageResponse {
        await recorder.append("modal-update")
        return try UpdateMessageResponse(InteractionMessageEdit(content: .value("updated")))
    }
}

/// User fixture cancelling its router task after producing valid local work.
private struct InteractionFamilyCancellingUser: UserCommandHandler {
    let recorder: InteractionFamilyRecorder
    /// Returns deterministic finite registration metadata without work.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Person") }
    /// Cancels the current task before returning a valid immediate message.
    /// - Parameters:
    ///   - context: Immutable invocation snapshot without acknowledgement authority.
    ///   - target: Completely admitted user reference; never hydrated.
    /// - Returns: A valid message which lowering must not transmit after cancellation.
    /// - Throws: Controlled message validation errors.
    func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        await recorder.append("cancelled")
        withUnsafeCurrentTask { $0?.cancel() }
        return try MessageResponse(InteractionMessageCreate(content: .value("must not send")))
    }
}

/// Modal update values whose aggregate constructor must never run for a missing source message.
private struct MissingSourceModalValues: ModalValues {
    /// Builds the same valid finite fields so a misplaced source-message guard would invoke user construction.
    static var schema: ModalSchema<Self> {
        /// Captures a constructor that records an issue if source-less input is admitted too far.
        /// - Returns: A valid finite schema; its aggregate constructor must remain unexecuted in this test.
        /// - Throws: Controlled descriptor/schema errors.
        get throws {
            let text = try ModalField<String>(customID: "text"), checked = try ModalField<Bool>(customID: "checked")
            return try ModalSchema(fields: [text.erased, checked.erased]) { _ in
                Issue.record("Missing source message reached a user aggregate constructor")
                return Self()
            }
        }
    }
}

/// Deliberately invalid public extension-point output; lowering must still validate callback compatibility.
private struct ForbiddenCommandResponse: CommandInitialResponse {
    /// Returns an illegal implicit defer for an immediate command family without sending it.
    var interactionResponse: InteractionResponse { .deferredMessage() }
}

/// Public-protocol fixture proving marker conformance alone never bypasses response-family admission.
private struct ForbiddenUserResponseHandler: UserCommandHandler {
    /// Returns the finite target command name without work.
    var command: ContextMenuCommandMetadata { .init(name: "Inspect Person") }
    /// Produces an illegal custom response after valid target admission.
    /// - Parameters:
    ///   - context: Immutable exact interaction snapshot without response authority.
    ///   - target: Validated user-domain target reference.
    /// - Returns: A deliberately invalid callback which lowering must reject before sending.
    func execute(_ context: CommandContext, target: UserReference) async -> ForbiddenCommandResponse { .init() }
}
