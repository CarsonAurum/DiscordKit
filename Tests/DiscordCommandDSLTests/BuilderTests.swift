import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordModels
import Foundation
import Testing

/// Offline builder/model parity and admission checks. No test owns a transport, acknowledgement or command registry.
@Suite struct BuilderTests {
    /// Ordered branches, optional omission, arrays and finite loops produce the exact existing model payload.
    /// Empty strings remain explicit and text blocks join with newlines; optional branches execute only when selected.
    /// - Throws: Unexpected valid fixture, content, JSON or model errors fail the test.
    @Test func messageBranchesArraysAndDirectParity() throws {
        let embed = try MessageEmbed(data: Data(#"{"title":"Details","description":"Body"}"#.utf8))
        let include = true, omitted = false
        let response = try MessageResponse(visibility: .ephemeral) {
            Text("First")
            if include { Text("Selected") } else { Text("Forbidden") }
            if omitted { Text("Also forbidden") }
            [Text("Array one"), Text("Array two")]
            for text in ["Loop one", "Loop two"] { Text(MessageContent(text)) }
            if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) { Embed(embed) }
        }
        let direct = try InteractionMessageCreate(content: .value("First\nSelected\nArray one\nArray two\nLoop one\nLoop two"),
            embeds: .value([embed]), allowedMentions: .value(MessageAllowedMentions(parse: [], repliedUser: false)),
            flags: .value(.ephemeral))
        #expect(try response.message.jsonValue() == direct.jsonValue())
        let second = try MessageResponse {
            if false { Text("Forbidden") } else { Text("Second") }
            Text("")
        }
        #expect(try Self.fields(second)["content"] == .string("Second\n"))
        let nested = MessageBuilder.buildExpression(Text("Composed"))
        #expect(try Self.fields(MessageResponse { nested })["content"] == .string("Composed"))
        #expect(throws: DiscordError.self) { try MessageResponse {} }
        #expect(throws: DiscordError.self) { try MessageResponse { Text("") } }
    }

    /// Legacy rows preserve exact factory fields, source order, raw models and all four interactive style choices.
    /// - Throws: Unexpected valid projection/model errors fail the test.
    @Test func legacyRowsAndRawAdoption() throws {
        let raw = try Self.component(#"{"type":2,"style":1,"label":"Raw","custom_id":"raw"}"#)
        let response = try MessageResponse {
            Text("Choose")
            Components {
                Component.actionRow {
                    Component.button("Primary", customID: "primary")
                    Component.button("Secondary", customID: "secondary", style: .secondary)
                    Component.button("Success", customID: "success", style: .success, disabled: true)
                    Component.button("Danger", customID: "danger", style: .danger)
                    raw
                }
            }
        }
        let expected = try Self.component(#"{"type":1,"components":[{"type":2,"style":1,"label":"Primary","custom_id":"primary","disabled":false},{"type":2,"style":2,"label":"Secondary","custom_id":"secondary","disabled":false},{"type":2,"style":3,"label":"Success","custom_id":"success","disabled":true},{"type":2,"style":4,"label":"Danger","custom_id":"danger","disabled":false},{"type":2,"style":1,"label":"Raw","custom_id":"raw"}]}"#)
        let direct = try InteractionMessageCreate(content: .value("Choose"),
            allowedMentions: .value(MessageAllowedMentions(parse: [], repliedUser: false)), components: .value([expected]))
        #expect(try response.message.jsonValue() == direct.jsonValue())
        #expect(try Self.fields(response)["flags"] == nil)
        let alternate = try MessageResponse {
            Components {
                Component.actionRow {
                    if false { Component.button("Forbidden", customID: "forbidden") }
                    else { [raw] }
                    if true { Component.button("Optional", customID: "optional") }
                    if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
                        Component.linkButton("Available", url: "https://docs.discord.com")
                    }
                }
            }
        }
        let alternateRow = try #require(Self.components(alternate).first)
        guard case .value(let children) = alternateRow.components else { Issue.record("Expected row children"); return }
        #expect(children.count == 3)
        #expect(children[0] == raw)
    }

    /// Typed URL/premium buttons and every auto-populated select family lower to validated existing components.
    /// - Throws: Unexpected valid projection/model errors fail the test.
    @Test func typedButtonsAndSelects() throws {
        let option = try ComponentOption(data: Data(#"{"label":"One","value":"one","default":true}"#.utf8))
        let response = try MessageResponse {
            Components(mode: .legacy) {
                Component.actionRow {
                    Component.linkButton("Docs", url: "https://docs.discord.com")
                    Component.premiumButton(skuID: SKUID(rawValue: UInt64.max), disabled: true)
                }
                Component.actionRow {
                    Component.stringSelect(customID: "strings", options: [option], placeholder: "Choose", minimum: 0)
                }
                for kind in [ComponentSelectKind.user, .role, .mentionable] {
                    Component.actionRow { Component.select(kind, customID: "kind-\(kind.rawValue)", placeholder: "Select") }
                }
            }
        }
        #expect(try Self.components(response).count == 5)
        let channel = try MessageResponse {
            Components {
                Component.actionRow { Component.select(.channel, customID: "channel", minimum: 0, maximum: 25, disabled: true) }
            }
        }
        let channelFields = try #require(Self.components(channel).first?.rawFields)
        #expect(channelFields["type"] == .number(try JSONNumber(rawValue: "1")))
        let parsed = try #require(Self.components(channel).first)
        guard case .value(let children) = parsed.components else { Issue.record("Expected select child"); return }
        #expect(children[0].type.knownValue == .channelSelect)
        #expect(children[0].minValues == .value(0))
        #expect(children[0].maxValues == .value(25))
        #expect(children[0].disabled == .value(true))
    }

    /// V2 mode is inferred across component blocks and aggregate mention allowlists retain source-order first use.
    /// Text-display policies include typed IDs only, even when adopted raw components contain mention-looking text.
    /// - Throws: Unexpected valid content, projection or model errors fail the test.
    @Test func v2LayoutsAndAggregateMentions() throws {
        let first = UserID(rawValue: 101), second = UserID(rawValue: 202), role = RoleID(rawValue: UInt64.max)
        let thumbnail = try Self.component(#"{"type":11,"media":{"url":"https://example.com/image.png"},"description":null}"#)
        let raw = try Self.component(#"{"type":10,"content":"@everyone <@999>"}"#)
        let enabled = true
        let response = try MessageResponse(visibility: .ephemeral) {
            Components {
                Component.container(accentColor: 0x123456, spoiler: true) {
                    Component.section(accessory: Component(thumbnail)) {
                        Component.textDisplay("Hello \(user: second) \(role: role)")
                        if enabled { Component.textDisplay("Again \(user: second)") } else { raw }
                    }
                    if false { raw }
                    [Component.separator(), Component.separator(divider: false, spacing: 2)]
                    for id in ["left", "right"] {
                        Component.actionRow { Component.button("Press", customID: id) }
                    }
                }
            }
            Components(mode: .v2) {
                Component.section(accessory: .button("More", customID: "more")) {
                    Component.textDisplay("Then \(user: first) \(user: second)")
                }
                raw
            }
        }
        let fields = try Self.fields(response)
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: "32832")))
        #expect(fields["content"] == nil)
        #expect(fields["allowed_mentions"] == .object(["parse": .array([]), "users": .array([.string("202"), .string("101")]),
            "roles": .array([.string(String(UInt64.max))]), "replied_user": .bool(false)]))
        #expect(try Self.components(response).count == 3)
        let direct = try InteractionMessageCreate(allowedMentions: .value(MessageAllowedMentions(parse: [],
            roles: [role], users: [second, first], repliedUser: false)),
            components: .value(Self.components(response)), flags: .value([.ephemeral, .isComponentsV2]))
        #expect(try response.message.jsonValue() == direct.jsonValue())
        let policy = try MessageAllowedMentions(parse: [.everyone], repliedUser: true)
        let overridden = try MessageResponse(allowedMentions: policy) {
            Components { raw }
        }
        #expect(try Self.fields(overridden)["allowed_mentions"] == policy.jsonValue())
    }

    /// Illegal layouts, duplicate identities, explicit mode conflicts and V2 field conflicts fail during construction.
    /// No response object exists that a command router could transmit after one of these failures.
    /// - Throws: Unexpected fixture projection errors fail the test.
    @Test func invalidLayoutsAndFieldCombinations() throws {
        let modal = try Self.component(#"{"type":4,"style":1,"custom_id":"input","label":"Input"}"#)
        let unknown = try Self.component(#"{"type":999,"content":"future"}"#)
        let rich = try MessageEmbed(data: Data(#"{"title":"Embed"}"#.utf8))
        #expect(throws: DiscordError.self) { try MessageResponse { Components { Component.button("Orphan", customID: "orphan") } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { Component.actionRow {} } } }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.button("A", customID: "same"); Component.button("B", customID: "same") } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.button("A", customID: "a"); Component.select(.user, customID: "s") } } }
        }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { modal } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { unknown } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components(mode: .legacy) { Component.textDisplay("V2") } } }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components(mode: .legacy) {}; Components(mode: .v2) { Component.textDisplay("V2") } }
        }
        #expect(throws: DiscordError.self) { try MessageResponse { Text("Conflict"); Components { Component.textDisplay("V2") } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Embed(rich); Components { Component.textDisplay("V2") } } }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.section(accessory: .separator()) { Component.textDisplay("Text") } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.section(accessory: .button("Button", customID: "b")) { Component.separator() } } }
        }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { Component.container { Component.container {} } } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { Component.container(accentColor: -1) { Component.textDisplay("Text") } } } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { Component.separator(spacing: 3) } } }
    }

    /// Mention policies merge across independent V2 text nodes, deduplicate repeated IDs and enforce the global bound.
    /// An explicit whole-message override is deliberate and may suppress all typed mention intents together.
    /// - Throws: Unexpected valid safe-content/model errors fail the test.
    @Test func aggregateMentionBoundaryAndExplicitOverride() throws {
        let first = MessageContent.joined((1...60).map { id in "\(user: UserID(rawValue: UInt64(id)))" }, separator: " ")
        let second = MessageContent.joined((41...100).map { id in "\(user: UserID(rawValue: UInt64(id)))" }, separator: " ")
        let overflow = MessageContent.joined((61...120).map { id in "\(user: UserID(rawValue: UInt64(id)))" }, separator: " ")
        let valid = try MessageResponse { Components { Component.textDisplay(first); Component.textDisplay(second) } }
        guard case .object(let mentions) = try Self.fields(valid)["allowed_mentions"],
              case .array(let users) = mentions["users"] else { Issue.record("Expected explicit users"); return }
        #expect(users.count == 100)
        #expect(users.first == .string("1"))
        #expect(users.last == .string("100"))
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.textDisplay(first); Component.textDisplay(overflow) } }
        }
        let none = try MessageAllowedMentions(parse: [], repliedUser: false)
        let overridden = try MessageResponse(allowedMentions: none) {
            Components { Component.textDisplay(first); Component.textDisplay(overflow) }
        }
        #expect(try Self.fields(overridden)["allowed_mentions"] == none.jsonValue())
    }

    /// Model-owned text/embeds/button/select limits and authoring count/byte/depth bounds reject complete responses.
    /// Sticky saturation prevents a later valid declaration from admitting the retained prefix after overflow.
    /// - Throws: Unexpected valid boundary fixture errors fail the test.
    @Test func boundedAdmissionAndStickyOverflow() throws {
        let lastValid = try MessageResponse { Text(MessageContent(String(repeating: "a", count: 2_000))) }
        #expect(try Self.fields(lastValid)["content"] == .string(String(repeating: "a", count: 2_000)))
        #expect(throws: DiscordError.self) { try MessageResponse { Text(MessageContent(String(repeating: "a", count: 2_001))) } }
        #expect(throws: DiscordError.self) {
            try MessageResponse { for _ in 0..<65 { Text("a") }; Text("tail") }
        }
        let sixtyFour = try MessageResponse { for _ in 0..<64 { Text("a") } }
        #expect(try Self.fields(sixtyFour)["content"] == .string(Array(repeating: "a", count: 64).joined(separator: "\n")))
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { for index in 0..<41 { Component.textDisplay("\(String(index))") }; Component.separator() } }
        }
        let forty = try MessageResponse { Components { for _ in 0..<40 { Component.separator() } } }
        #expect(try Self.components(forty).count == 40)
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { for index in 0..<6 { Component.actionRow { Component.button("Button", customID: "id-\(index)") } } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { for index in 0..<6 { Component.button("Button", customID: "id-\(index)") } } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.button(String(repeating: "a", count: 81), customID: "long") } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.stringSelect(customID: "empty", options: []) } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.select(.user, customID: "invalid", minimum: 2, maximum: 1) } } }
        }
        #expect(throws: DiscordError.self) {
            try MessageResponse { Components { Component.actionRow { Component.linkButton("Invalid", url: "") } } }
        }
        #expect(throws: (any Error).self) {
            try MessageResponse { Components { Component.textDisplay(MessageContent(String(repeating: "a", count: 65_536))) } }
        }
        var nested = Component.textDisplay("Leaf")
        for _ in 0..<9 { let child = nested; nested = Component.container { child } }
        #expect(throws: DiscordError.self) { try MessageResponse { Components { nested } } }
        let embed = try MessageEmbed(data: Data(#"{"title":"Count"}"#.utf8))
        #expect(throws: DiscordError.self) { try MessageResponse { Array(repeating: Embed(embed), count: 11) } }
    }

    /// Deferred builders preserve absence, explicit empty replacements, observed visibility and exact raw null edits.
    /// Builder construction never changes the deferred acknowledgement's immutable ephemeral state.
    /// - Throws: Unexpected valid content/model errors fail the test.
    @Test func deferredPresenceAndExistingModelEscape() throws {
        #expect(try DeferredMessageResponse {}.edit.jsonValue() == .object([:]))
        let edit = try DeferredMessageResponse {
            Text("")
            Components {}
        }
        #expect(try edit.edit.jsonValue() == .object(["content": .string(""), "components": .array([]),
            "allowed_mentions": .object(["parse": .array([]), "replied_user": .bool(false)])]))
        let raw = try DeferredMessageResponse(InteractionMessageEdit(content: .null, embeds: .value([]),
            allowedMentions: .null, components: .null, deferredResponse: true))
        #expect(try raw.edit.jsonValue() == .object(["content": .null, "embeds": .array([]), "allowed_mentions": .null, "components": .null]))
        let v2 = try DeferredMessageResponse(previousFlags: (1 << 15) | (1 << 6)) {
            Components { Component.textDisplay("Updated") }
        }
        guard case .object(let fields) = try v2.edit.jsonValue() else { Issue.record("Expected edit object"); return }
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: "32832")))
        #expect(fields["content"] == nil)
        #expect(throws: DiscordError.self) {
            try DeferredMessageResponse(previousFlags: (1 << 15) | (1 << 6)) { Text("Forbidden traditional content") }
        }
        #expect(throws: DiscordError.self) {
            try DeferredMessageResponse { Components { Component.textDisplay("Migration requires explicit clears") } }
        }
        #expect(throws: DiscordError.self) {
            try DeferredMessageResponse(previousFlags: 1 << 15) { Components(mode: .legacy) {} }
        }
        let rows = try (0..<6).map { index in
            try Self.component(#"{"type":1,"components":[{"type":2,"style":1,"label":"Button","custom_id":"existing-\#(index)","disabled":false}]}"#)
        }
        let existingFlags: UInt64 = (1 << 15) | (1 << 6)
        let automatic = try DeferredMessageResponse(previousFlags: existingFlags) {
            Components {
                for index in 0..<6 {
                    Component.actionRow { Component.button("Button", customID: "existing-\(index)") }
                }
            }
        }
        let direct = try InteractionMessageEdit(allowedMentions: .value(MessageAllowedMentions(parse: [], repliedUser: false)),
            components: .value(rows), deferredResponse: true, previousFlags: existingFlags)
        #expect(try automatic.edit.jsonValue() == direct.jsonValue())
        #expect(try DeferredMessageResponse(previousFlags: existingFlags) {}.edit.jsonValue() == .object([:]))
        let override = try MessageAllowedMentions(parse: [.everyone])
        let explicit = try DeferredMessageResponse(allowedMentions: override) { Text("@everyone") }
        guard case .object(let overridden) = try explicit.edit.jsonValue() else { Issue.record("Expected edit object"); return }
        #expect(overridden["allowed_mentions"] == override.jsonValue())
    }

    /// Formatting and reflection of structural values conceal content, interaction identities and mention IDs.
    /// - Throws: Unexpected safe structural composition errors fail the test.
    @Test func redactedDiagnostics() throws {
        let component = Component.textDisplay("private-marker")
        let list = ComponentBuilder.buildExpression(component)
        let body = MessageBuilder.buildExpression(Text("private-marker"))
        for value in [component as any CustomStringConvertible, list, body] {
            #expect(value.description.hasSuffix("(redacted)"))
            #expect(!String(reflecting: value).contains("private-marker"))
            #expect(Mirror(reflecting: value).children.count == 1)
        }
    }

    /// Projects a synthetic existing component without requesting external services or introducing test-only schema rules.
    /// - Parameter json: Complete exact fixture JSON in the existing model format.
    /// - Returns: Existing component projection, retaining all omission/null information.
    /// - Throws: JSON/projection errors for malformed fixture data.
    private static func component(_ json: String) throws -> MessageComponent { try MessageComponent(data: Data(json.utf8)) }

    /// Unwraps the exact resulting existing model message object for focused field assertions.
    /// - Parameter response: Already validated immediate response.
    /// - Returns: Exact model-owned JSON fields, without reinterpreting content or flag semantics.
    /// - Throws: Unexpected serialization failures or test requirement failure for a nonobject payload.
    private static func fields(_ response: MessageResponse) throws -> [String: JSONValue] {
        guard case .object(let fields) = try response.message.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Projects the final ordered component array through existing models for parity and field assertions.
    /// - Parameter response: Already validated immediate response containing components.
    /// - Returns: Exact existing component models, or an empty array when no component array exists.
    /// - Throws: Model/JSON errors when an unexpected invalid fixture reaches the helper.
    private static func components(_ response: MessageResponse) throws -> [MessageComponent] {
        guard case .array(let components) = try fields(response)["components"] else { return [] }
        return try components.map { try MessageComponent(jsonValue: $0) }
    }
}
