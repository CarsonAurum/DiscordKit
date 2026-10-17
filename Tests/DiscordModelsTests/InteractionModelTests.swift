import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Verifies incoming interactions and callback results using exact, independently authored API v10 fixtures.
@Suite struct InteractionModelTests {
    /// Full command input projects exact IDs, partial resolved resources, all context fields and unknown numeric lexemes.
    /// No resolved message is incorrectly treated as a complete Message, and diagnostics conceal the continuation token.
    /// - Throws: Unexpected projection/fixture failures fail the test.
    @Test func completeCommandInput() throws {
        let input = try Interaction(data: Self.commandBytes())
        #expect(input.id.rawValue == UInt64.max)
        #expect(input.applicationID.rawValue == 9_007_199_254_740_993)
        #expect(input.type.knownValue == .applicationCommand)
        #expect(input.version == 1)
        #expect(input.token.withUnsafeValue { $0 } == "synthetic-interaction-secret")
        #expect(input.guildID == .value(.init(rawValue: 3)))
        #expect(input.channelID == .value(.init(rawValue: 4)))
        #expect(input.appPermissions == .value("18446744073709551616"))
        #expect(input.locale == .value("en-US"))
        #expect(input.guildLocale == .value("fr"))
        #expect(input.context == .value(.init(.guild)))
        #expect(input.authorizingIntegrationOwners == .value(["0": "0", "1": "18446744073709551615"]))
        #expect(input.attachmentSizeLimit == .value(20 * 1_048_576))
        guard case .value(.command(let command)) = input.data else { Issue.record("Expected command data"); return }
        #expect(command.id.rawValue == UInt64.max)
        #expect(command.name == "inspect")
        #expect(command.type.knownValue == .message)
        #expect(command.guildID == .value(.init(rawValue: 3)))
        #expect(command.targetID == .value(.init(rawValue: 7)))
        guard case .value(let resolved) = command.resolved else { Issue.record("Expected resolved data"); return }
        #expect(resolved.members == .value(["7": try MessageRelatedResource(data: Data(#"{"roles":[],"permissions":"8"}"#.utf8))]))
        guard case .value(let messages) = resolved.messages else { Issue.record("Expected partial messages"); return }
        #expect(messages["7"]?.id == .value("7"))
        #expect(messages["7"]?.rawFields["content"] == .string("partial"))
        #expect(input.rawFields["future"] == .number(try JSONNumber(rawValue: "12345678901234567890.123456789")))
        #expect(try input.jsonValue() == JSONValue.parse(Self.commandBytes()))
        #expect(!String(describing: input).contains("synthetic-interaction-secret"))
        #expect(!String(reflecting: input).contains("partial"))
        #expect(input.customMirror.children.count == 1)
        #expect(input.member != .absent)
        #expect(input.user == .absent)
        #expect(input.channel != .absent)
        #expect(input.guild != .absent)
        #expect(input.entitlements != .absent)
    }

    /// Premium interaction entitlement entries use the complete typed projection and preserve future origins,
    /// deleted/consumed flags, absent perpetual-test lifecycle fields and exact unknown numeric content.
    /// Every malformed nested entry is rejected without exposing continuation tokens or granting access.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func premiumEntitlementProjection() throws {
        let entitlement = try JSONValue.parse(Data(#"{"id":"18446744073709551615","sku_id":"9007199254740993","application_id":"3","user_id":"4","type":99,"deleted":true,"consumed":true,"future":12345678901234567890.123456789}"#.utf8))
        var fields = try Self.object(Self.commandBytes())
        fields["entitlements"] = .array([entitlement])
        let input = try Interaction(data: JSONValue.object(fields).serialized())
        guard case .value(let values) = input.entitlements else { Issue.record("Expected premium entitlements"); return }
        let projected = try #require(values.first)
        #expect(projected.id.rawValue == .max)
        #expect(projected.skuID.rawValue == 9_007_199_254_740_993)
        #expect(projected.type.rawValue == 99 && projected.type.knownValue == nil)
        #expect(projected.deleted && projected.consumed == .value(true))
        #expect(projected.startsAt == .absent && projected.endsAt == .absent)
        #expect(projected.jsonValue() == entitlement)
        #expect(input.jsonValue() == .object(fields))
        for invalid in [JSONValue.null, .string("private"), .object([:]),
                        .object(["id": .string("18446744073709551616")])] {
            fields["entitlements"] = .array([invalid])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Interaction(data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Minimal PING, future kinds and explicit context metadata are accepted without invented enum support.
    /// Known command/component/modal interactions must contain a nonnull, correctly shaped data object.
    /// - Throws: Unexpected parse or serialization failures fail the test.
    @Test func pingUnknownAndVariants() throws {
        let ping = try Interaction(data: Data(Self.baseJSON.utf8))
        #expect(ping.type.knownValue == .ping)
        #expect(ping.data == .absent)
        #expect(ping.appPermissions == .absent)
        #expect(ping.entitlements == .absent)
        #expect(ping.attachmentSizeLimit == .absent)
        let future = try Self.input(type: 99, data: .object(["future": .null]))
        #expect(future.type.knownValue == nil)
        #expect(future.data == .value(.unknown(.object(["future": .null]))))
        for (kind, data) in [(2, #"{"id":"2","name":"test","type":99}"#),
                              (4, #"{"id":"2","name":"test","type":1,"options":[{"name":"q","type":3,"value":"partial","focused":true}]}"#),
                              (3, #"{"custom_id":"select","component_type":3,"id":4294967295,"values":[],"resolved":{}}"#),
                              (5, #"{"custom_id":"modal","components":[{"type":18,"id":1,"component":{"type":21,"custom_id":"radio","value":null}},{"type":18,"component":{"type":23,"custom_id":"check","value":false}}],"resolved":{}}"#)] {
            let interaction = try Self.input(type: kind, data: JSONValue.parse(Data(data.utf8)))
            #expect(interaction.type.rawValue == kind)
            #expect(interaction.data != .absent)
            switch interaction.data {
            case .value(.command(let value)): #expect(value.name == "test")
            case .value(.component(let value)): #expect(value.values == .value([])); #expect(value.id == .value(UInt32.max))
            case .value(.modal(let value)): #expect(value.components.count == 2); #expect(value.components[0].component != .absent)
            default: Issue.record("Expected typed input data")
            }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Self.input(type: kind, data: nil) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Self.input(type: kind, data: .null) }
        }
        let unknownComponent = try InteractionComponentData(data: Data(#"{"custom_id":"future","component_type":99,"future":1}"#.utf8))
        #expect(unknownComponent.componentType.knownValue == nil)
        #expect(unknownComponent.values == .absent)
    }

    /// Every optional root field retains omission and rejects forbidden null/wrong scalar/container values.
    /// - Parameter name: Modeled optional root key.
    /// - Throws: Unexpected fixture/serialization failures fail the test; sanitized invalid-response is asserted.
    @Test(arguments: ["guild", "guild_id", "channel", "channel_id", "member", "user", "message", "app_permissions", "locale", "guild_locale", "entitlements", "authorizing_integration_owners", "context", "attachment_size_limit"])
    func malformedOptionalRootFields(name: String) throws {
        var object = try Self.object(Data(Self.baseJSON.utf8))
        object[name] = .null
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(object).serialized()) }
        object[name] = .array([])
        if name != "entitlements" {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(object).serialized()) }
        }
    }

    /// Required IDs/type/token/version reject omission, null, malformed values and unsupported versions safely.
    /// - Parameter name: Required interaction key.
    /// - Throws: Unexpected fixture/serialization failures fail the test.
    @Test(arguments: ["id", "application_id", "type", "token", "version"])
    func requiredRootFields(name: String) throws {
        for invalid: JSONValue? in [nil, .null, .bool(false), .array([])] {
            var object = try Self.object(Data(Self.baseJSON.utf8))
            object[name] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(object).serialized()) }
        }
        var object = try Self.object(Data(Self.baseJSON.utf8))
        object["token"] = .string("secret with whitespace")
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(object).serialized()) }
        object["token"] = .string("valid")
        object["version"] = .number(try JSONNumber(rawValue: "2"))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(object).serialized()) }
    }

    /// Known non-PING kinds require current context metadata while permissions retain arbitrary-width decimal values.
    /// PING/future contexts may omit metadata, but invalid supplied permissions/owners/byte limits remain malformed.
    /// - Parameter name: One table-required metadata key for currently known non-PING interactions.
    /// - Throws: Unexpected fixture/serialization failures fail the test; safe schema rejection is asserted.
    @Test(arguments: ["app_permissions", "entitlements", "authorizing_integration_owners", "attachment_size_limit"])
    func requiredNonPingContext(name: String) throws {
        var fields = try Self.object(Self.commandBytes())
        fields.removeValue(forKey: name)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(fields).serialized()) }
        for invalid in ["", "-1", "1.5", "secret", " 8", "0x10"] {
            fields = try Self.object(Self.commandBytes()); fields["app_permissions"] = .string(invalid)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(fields).serialized()) }
        }
        fields = try Self.object(Self.commandBytes())
        fields["authorizing_integration_owners"] = .object(["1": .string("18446744073709551616")])
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(fields).serialized()) }
        fields["authorizing_integration_owners"] = .object([:])
        fields["attachment_size_limit"] = .number(try JSONNumber(rawValue: "-1"))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Interaction(data: JSONValue.object(fields).serialized()) }
    }

    /// All eleven option kinds preserve valid recursive/scalar forms, autocomplete focus and large exact numbers.
    /// - Parameter kind: One documented application-command option discriminator.
    /// - Throws: Unexpected decoder failures fail the test.
    @Test(arguments: 1...11) func commandOptionKinds(kind: Int) throws {
        let scalar = kind == 5 ? "true" : kind == 4 ? "9007199254740991" : kind == 10 ? "1.23000000000001" : #""18446744073709551615""#
        let body = kind <= 2 ? #""options":[{"name":"child","type":3,"value":"ok"}]"# : #""value":\#(scalar)"#
        let option = try InteractionCommandOption(data: Data(#"{"name":"option","type":\#(kind),\#(body),"focused":true,"future":null}"#.utf8))
        #expect(option.type.rawValue == kind)
        #expect(option.focused == .value(true))
        #expect(option.rawFields["future"] == .null)
        #expect(!String(reflecting: option).contains("18446744073709551615"))
        if kind <= 2 { #expect(option.options != .absent) } else { #expect(option.value != .absent) }
        let unknown = try InteractionCommandOption(data: Data(#"{"name":"future","type":99,"value":true}"#.utf8))
        #expect(unknown.type.knownValue == nil)
    }

    /// Malformed option scalars, mutually exclusive subtrees and invalid dictionaries fail at the exact typed boundary.
    /// - Parameter json: Independently authored invalid option fixture.
    /// - Throws: No expected failure escapes; errors must remain sanitized.
    @Test(arguments: [#"{"name":"x","type":4,"value":1.5}"#, #"{"name":"x","type":4,"value":1e2}"#, #"{"name":"x","type":3,"value":false}"#, #"{"name":"x","type":5,"value":"false"}"#, #"{"name":"x","type":1,"value":"x"}"#, #"{"name":"x","type":3,"value":null}"#, #"{"name":"x","type":3,"value":"x","options":[]}"#, #"{"name":"x","type":3,"options":{}}"#, #"{"name":"x","type":3,"focused":null}"#, #"{"name":"x","type":3,"value":{}}"#, #"{"name":"x","type":6,"value":"not-an-id"}"#, #"{"name":"x","type":11,"value":"18446744073709551616"}"#])
    func invalidOptions(json: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try InteractionCommandOption(data: Data(json.utf8)) }
    }

    /// Partial resolved maps retain all categories and reject malformed keys, roots and typed values.
    /// Member-only maps remain partial snapshots; no hidden user lookup or hydration occurs.
    /// - Parameter category: Each currently documented resolved category.
    /// - Throws: Unexpected fixture or parse failures fail the test.
    @Test(arguments: ["users", "members", "roles", "channels", "messages", "attachments"])
    func resolvedDictionaryValidation(category: String) throws {
        let empty = try InteractionResolvedData(data: Data("{}".utf8))
        #expect(empty.rawFields.isEmpty)
        for json in [#"{"\#(category)":null}"#, #"{"\#(category)":[]}"#,
                     #"{"\#(category)":{"not-an-id":{}}}"#, #"{"\#(category)":{"18446744073709551616":{}}}"#,
                     #"{"\#(category)":{"1":false}}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try InteractionResolvedData(data: Data(json.utf8)) }
        }
        let value = try InteractionResolvedData(data: Data(#"{"\#(category)":{},"future":{"opaque":1}}"#.utf8))
        #expect(value.rawFields[category] == .object([:]))
        #expect(value.rawFields["future"] != nil)
        #expect(value.customMirror.children.count == 1)
    }

    /// Callback results preserve optional absence/null differences, Activity and message resources and future kinds.
    /// Required nested resources for currently documented result alternatives are enforced.
    /// - Throws: Unexpected bounded projection failures fail the test.
    @Test func callbackResults() throws {
        let empty = try InteractionCallbackResponse(data: Data(#"{"interaction":{"id":"18446744073709551615","type":99}}"#.utf8))
        #expect(empty.interaction.id.rawValue == UInt64.max)
        #expect(empty.interaction.type.knownValue == nil)
        #expect(empty.interaction.responseMessageID == .absent)
        #expect(empty.resource == .absent)
        let activity = try InteractionCallbackResponse(data: Data(#"{"interaction":{"id":"1","type":2,"activity_instance_id":null,"response_message_id":"9007199254740993","response_message_loading":false,"response_message_ephemeral":true,"channel_id":"4","guild_id":"3"},"resource":{"type":12,"activity_instance":{"id":"opaque-instance","future":1}},"future":true}"#.utf8))
        #expect(activity.interaction.activityInstanceID == .null)
        #expect(activity.interaction.responseMessageID == .value(.init(rawValue: 9_007_199_254_740_993)))
        #expect(activity.interaction.responseMessageLoading == .value(false))
        #expect(activity.interaction.responseMessageEphemeral == .value(true))
        #expect(activity.interaction.channelID == .value(.init(rawValue: 4)))
        #expect(activity.interaction.guildID == .value(.init(rawValue: 3)))
        guard case .value(let resource) = activity.resource else { Issue.record("Expected Activity"); return }
        #expect(resource.type.knownValue == .launchActivity)
        #expect(resource.activityInstance != .absent)
        #expect(resource.message == .absent)
        #expect(activity.rawFields["future"] == .bool(true))
        #expect(!String(reflecting: activity).contains("opaque-instance"))
        #expect(activity.customMirror.children.count == 1)
        for type in [4, 7] {
            let message = try InteractionCallbackResource(data: Data(#"{"type":\#(type),"message":\#(Self.messageJSON)}"#.utf8))
            #expect(message.message != .absent)
            #expect(message.activityInstance == .absent)
            #expect(message.type.rawValue == type)
        }
        let unknown = try InteractionCallbackResource(data: Data(#"{"type":13,"future":{"exact":9007199254740993}}"#.utf8))
        #expect(unknown.type.knownValue == nil)
        #expect(unknown.rawFields["future"] != nil)
    }

    /// Callback metadata, result envelopes and resource alternatives reject malformed known data.
    /// - Parameter json: Invalid callback-result fixture.
    /// - Throws: Unexpected errors outside the explicitly asserted safe schema failure fail the test.
    @Test(arguments: ["null", "{}", #"{"interaction":null}"#, #"{"interaction":{}}"#, #"{"interaction":{"id":"1","type":2},"resource":null}"#, #"{"interaction":{"id":"1","type":2,"response_message_loading":null}}"#, #"{"interaction":{"id":"1","type":2},"resource":{"type":12}}"#, #"{"interaction":{"id":"1","type":2},"resource":{"type":12,"activity_instance":{"id":1}}}"#, #"{"interaction":{"id":"1","type":2},"resource":{"type":4}}"#, #"{"interaction":{"id":"1","type":2},"resource":{"type":7,"message":{}}}"#])
    func invalidCallbackResults(json: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try InteractionCallbackResponse(data: Data(json.utf8)) }
    }

    /// Every public model entry point applies whole-document JSON bounds before inspecting fields or traversing children.
    /// Unknown fields participate in the same limits and cannot evade byte/depth/node admission.
    /// - Throws: Unexpected JSON-limit construction failures fail the test.
    @Test func publicEntryPointBounds() throws {
        let parsers: [(Data, JSONLimits) throws -> Void] = [
            { _ = try Interaction(data: $0, limits: $1) }, { _ = try InteractionResolvedData(data: $0, limits: $1) },
            { _ = try InteractionCommandData(data: $0, limits: $1) }, { _ = try InteractionCommandOption(data: $0, limits: $1) },
            { _ = try InteractionComponentData(data: $0, limits: $1) }, { _ = try InteractionModalData(data: $0, limits: $1) },
            { _ = try InteractionCallback(data: $0, limits: $1) }, { _ = try InteractionCallbackResource(data: $0, limits: $1) },
            { _ = try InteractionCallbackResponse(data: $0, limits: $1) }]
        for parse in parsers {
            #expect(throws: (any Error).self) { try parse(Data(#"{"unknown":"too many bytes"}"#.utf8), JSONLimits(maximumBytes: 5)) }
            #expect(throws: (any Error).self) { try parse(Data(#"{"unknown":[[[true]]]}"#.utf8), JSONLimits(maximumDepth: 2)) }
            #expect(throws: (any Error).self) { try parse(Data(#"{"unknown":[true,false]}"#.utf8), JSONLimits(maximumNodes: 2)) }
        }
    }

    /// Parses an independent command fixture containing every currently modeled context field.
    /// - Returns: Exact finite UTF-8 JSON fixture without any live or production credential.
    static func commandBytes() -> Data {
        Data(#"{"id":"18446744073709551615","application_id":"9007199254740993","type":2,"token":"synthetic-interaction-secret","version":1,"guild":{"id":"3","name":"guild"},"guild_id":"3","channel":{"id":"4","type":0},"channel_id":"4","member":{"roles":[],"permissions":"8"},"app_permissions":"18446744073709551616","locale":"en-US","guild_locale":"fr","entitlements":[],"authorizing_integration_owners":{"0":"0","1":"18446744073709551615"},"context":0,"attachment_size_limit":20971520,"data":{"id":"18446744073709551615","name":"inspect","type":3,"guild_id":"3","target_id":"7","resolved":{"members":{"7":{"roles":[],"permissions":"8"}},"messages":{"7":{"id":"7","content":"partial"}},"channels":{"4":{"id":"4","app_permissions":"8"}},"roles":{"8":{"id":"8","name":"role"}},"users":{},"attachments":{}},"options":[]},"future":12345678901234567890.123456789}"#.utf8)
    }

    /// Composes a variant input from a minimal required root while preserving supplied data presence exactly.
    /// - Parameters:
    ///   - type: Integral incoming interaction kind, including unknown future values.
    ///   - data: Nil omits data; null and values remain explicit.
    /// - Returns: Parsed bounded interaction with the requested variant.
    /// - Throws: Fixture serialization or production schema errors.
    static func input(type: Int, data: JSONValue?) throws -> Interaction {
        var fields = try object(Data(baseJSON.utf8))
        fields["type"] = .number(try JSONNumber(rawValue: String(type)))
        fields["data"] = data
        fields["app_permissions"] = .string("0")
        fields["entitlements"] = .array([])
        fields["authorizing_integration_owners"] = .object([:])
        fields["attachment_size_limit"] = .number(try JSONNumber(rawValue: "20971520"))
        return try Interaction(data: JSONValue.object(fields).serialized())
    }

    /// Requires one exact object for focused fixture mutations, avoiding a lossy Foundation JSON bridge.
    /// - Parameter data: Complete bounded object fixture.
    /// - Returns: Original exact dictionary including numeric lexemes.
    /// - Throws: Parser errors or a test invariant failure when the fixture is not an object.
    static func object(_ data: Data) throws -> [String: JSONValue] {
        let value = try JSONValue.parse(data)
        guard case .object(let fields) = value else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Minimal PING intentionally omits contextual fields not needed for the acknowledgement payload.
    static let baseJSON = #"{"id":"1","application_id":"2","type":1,"token":"synthetic","version":1}"#
    /// Independent complete Message fixture used by callback-resource alternatives.
    static let messageJSON = #"{"id":"7","channel_id":"4","author":{"id":"5","username":"user","discriminator":"0","avatar":null},"content":"response","timestamp":"2026-10-16T12:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":20}"#
}
