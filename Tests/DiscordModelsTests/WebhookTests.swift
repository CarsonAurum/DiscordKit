import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Webhook model and request contracts use finite independent fixtures without credentials or live Discord calls.
@Suite struct WebhookTests {
    /// Incoming/follower/application variants preserve all known fields, future values and credential redaction.
    /// - Throws: Unexpected bounded fixture/model errors fail the test.
    @Test func variantsAndRedaction() throws {
        let webhook = try Webhook(data: Data(Self.fixture.utf8))
        #expect(webhook.id.rawValue == UInt64.max)
        #expect(webhook.type.knownValue == .incoming)
        #expect(webhook.guildID == .null)
        #expect(webhook.channelID == .null)
        #expect(webhook.name == .value("private-name"))
        #expect(webhook.avatar == .null && webhook.applicationID == .null)
        #expect(webhook.user == .absent)
        #expect(webhook.sourceGuild == .absent && webhook.sourceChannel == .absent)
        if case .value(let token) = webhook.token { #expect(token.withUnsafeValue { $0 } == "private-token") }
        else { Issue.record("Expected secret webhook token") }
        #expect(webhook.withUnsafeURL { $0 } == "https://discord.com/api/webhooks/1/private-token")
        #expect(webhook.withUnsafeFields { $0["future"] } == .number(try JSONNumber(rawValue: "184467440737095516160001")))
        for text in [String(describing: webhook), String(reflecting: webhook), String(reflecting: Mirror(reflecting: webhook))] {
            #expect(!text.contains("private") && !text.contains("18446744073709551615"))
        }
        var fields = webhook.withUnsafeFields { $0 }
        fields.removeValue(forKey: "token"); fields.removeValue(forKey: "url")
        fields["type"] = .number(try JSONNumber(rawValue: "91"))
        let future = try Webhook(data: JSONValue.object(fields).serialized())
        #expect(future.type.knownValue == nil && future.type.rawValue == 91)
        #expect(future.withUnsafeURL { $0 } == nil)
        if case .absent = future.token {} else { Issue.record("Expected omitted token") }
        fields["type"] = .number(try JSONNumber(rawValue: "2"))
        fields["source_guild"] = try JSONValue.parse(Data(#"{"id":"18446744073709551615","name":"source","icon":null,"future":true}"#.utf8))
        fields["source_channel"] = try JSONValue.parse(Data(#"{"id":"18446744073709551615","name":"news","future":true}"#.utf8))
        fields["user"] = try JSONValue.parse(Data(#"{"id":"1","username":"creator","discriminator":"0","avatar":null}"#.utf8))
        let follower = try Webhook(data: JSONValue.object(fields).serialized())
        if case .value(let guild) = follower.sourceGuild {
            #expect(guild.id.rawValue == UInt64.max && guild.name == "source" && guild.icon == .null)
            #expect(try WebhookSourceGuild(data: guild.jsonValue().serialized()) == guild)
        } else { Issue.record("Expected source guild") }
        if case .value(let channel) = follower.sourceChannel {
            #expect(channel.id.rawValue == UInt64.max && channel.name == "news")
            #expect(try WebhookSourceChannel(data: channel.jsonValue().serialized()) == channel)
        } else { Issue.record("Expected source channel") }
        if case .value(let user) = follower.user { #expect(user.username == "creator") }
        else { Issue.record("Expected creator projection") }
        fields["type"] = .number(try JSONNumber(rawValue: "3"))
        fields["application_id"] = .string("18446744073709551615")
        #expect(try Webhook(data: JSONValue.object(fields).serialized()).applicationID == .value(.init(rawValue: UInt64.max)))
    }

    /// Required fields reject omission, forbidden nulls and wrong types while nullable keys retain explicit null.
    /// - Parameter key: Every required field plus all modeled optional fields.
    /// - Throws: Unexpected fixture setup errors fail the test; schema errors are asserted.
    @Test(arguments: ["id", "type", "channel_id", "name", "avatar", "application_id", "guild_id", "user", "token", "source_guild", "source_channel", "url"])
    func malformedFields(key: String) throws {
        var fields = try #require(try JSONValue.parse(Data(Self.fixture.utf8)).objectValue)
        fields[key] = .bool(true)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Webhook(data: JSONValue.object(fields).serialized()) }
        fields[key] = .null
        if ["channel_id", "name", "avatar", "application_id", "guild_id"].contains(key) {
            _ = try Webhook(data: JSONValue.object(fields).serialized())
        } else { #expect(throws: DiscordError.transport(.invalidResponse)) { try Webhook(data: JSONValue.object(fields).serialized()) } }
        fields.removeValue(forKey: key)
        if ["id", "type", "channel_id", "name", "avatar", "application_id"].contains(key) {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Webhook(data: JSONValue.object(fields).serialized()) }
        } else { _ = try Webhook(data: JSONValue.object(fields).serialized()) }
    }

    /// Safe parser limits, invalid token text and malformed follower subsets cannot leak credential diagnostics.
    /// - Throws: Unexpected valid-fixture errors fail the test.
    @Test func boundsAndNestedErrors() throws {
        #expect(throws: (any Error).self) { try Webhook(data: Data(Self.fixture.utf8), limits: JSONLimits(maximumBytes: 10)) }
        for token in ["", "private token", "private\ntoken"] {
            var fields = try #require(try JSONValue.parse(Data(Self.fixture.utf8)).objectValue)
            fields["token"] = .string(token)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Webhook(data: JSONValue.object(fields).serialized()) }
        }
        for bytes in [Data("null".utf8), Data("{}".utf8), Data("[]".utf8)] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookSourceGuild(data: bytes) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookSourceChannel(data: bytes) }
        }
    }

    /// Metadata names/images/nullability obey explicit creation and PATCH bounds without normalization.
    /// - Throws: Unexpected valid request errors fail the test.
    @Test func metadataRequests() throws {
        #expect(try WebhookCreate(name: "A", avatar: .null).jsonValue() == .object(["name": .string("A"), "avatar": .null]))
        #expect(try WebhookCreate(name: String(repeating: "a", count: 80), avatar: .value("YQ==")).jsonValue().objectValue?["avatar"] == .string("YQ=="))
        #expect(try WebhookModify().jsonValue() == .object([:]))
        #expect(try WebhookModify(name: .value("changed"), avatar: .null, channelID: .value(.init(rawValue: UInt64.max))).jsonValue() == .object([
            "name": .string("changed"), "avatar": .null, "channel_id": .string("18446744073709551615")]))
        for name in ["", String(repeating: "a", count: 81), "DisCoRd", "myCLYDEbot", "bad\nname"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookCreate(name: name) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookModify(name: .value(name)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookModify(name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookModify(channelID: .null) }
        for image in ["", "!", "YQ", "data:text/plain;base64,YQ=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookCreate(name: "a", avatar: .value(image)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookModify(avatar: .value(image)) }
        }
    }

    /// Native execution retains webhook-only overrides, validates forum routing and rejects channel-only fields.
    /// - Throws: Unexpected request/component fixture errors fail the test.
    @Test func executeRoutingAndOverrides() throws {
        let request = try WebhookExecute(message: MessageCreate(content: .value("hello")), username: .value("override"),
            avatarURL: .value("https://example.com/a.png"), threadName: .value("new"), appliedTags: .value([.init(rawValue: UInt64.max)]))
        #expect(try request.jsonValue(isForumOrMedia: true).objectValue?["applied_tags"] == .array([.string("18446744073709551615")]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try request.jsonValue(threadID: .init(rawValue: 1)) }
        let ordinary = try WebhookExecute(message: MessageCreate(content: .value("hello")))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ordinary.jsonValue(isForumOrMedia: true) }
        #expect(try ordinary.jsonValue(threadID: .init(rawValue: 1), isForumOrMedia: true).objectValue?["content"] == .string("hello"))
        for message in [try MessageCreate(nonce: .value(.string("n"))), try MessageCreate(stickerIDs: .value([])),
                        try MessageCreate(enforceNonce: .value(false)), try MessageCreate(flags: .value(.isVoiceMessage))] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookExecute(message: message) }
        }
        for url in ["no-url", "file:///tmp/x", "https://user:pass@example.com/"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookExecute(message: MessageCreate(), avatarURL: .value(url)) }
        }
        _ = try WebhookExecute(message: MessageCreate(), avatarURL: .value("https://example.com/" + String(repeating: "x", count: 2_028)))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookExecute(message: MessageCreate(), avatarURL: .value("https://example.com/" + String(repeating: "x", count: 2_029)))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookExecute(message: MessageCreate(), username: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookExecute(message: MessageCreate(), threadName: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookExecute(message: MessageCreate(), appliedTags: .value([])) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookExecute(message: MessageCreate(), threadName: .value("t"), appliedTags: .value([.init(rawValue: 1), .init(rawValue: 1)]))
        }
        #expect(!String(reflecting: request).contains("override"))
    }

    /// Component ownership, explicit opt-in, V2 file exclusion and edit migration resets enforce webhook-specific rules.
    /// - Throws: Unexpected fixture/request errors fail the test.
    @Test func componentsEditsAndUploads() throws {
        let interactive = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":2,"style":1,"label":"go","custom_id":"private"}]}"#.utf8))
        let link = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":2,"style":5,"label":"go","url":"https://example.com"}]}"#.utf8))
        let create = try WebhookExecute(message: MessageCreate(components: .value([interactive])))
        #expect(throws: DiscordError.validation(.invalidValue)) { try create.jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try create.jsonValue(withComponents: true) }
        #expect(try create.jsonValue(ownership: .applicationOwned).objectValue?["components"] != nil)
        let linked = try WebhookExecute(message: MessageCreate(components: .value([link])))
        #expect(try linked.jsonValue(withComponents: true).objectValue?["components"] != nil)
        let v2 = try MessageComponent(data: Data(#"{"type":10,"content":"text"}"#.utf8))
        let v2Create = try WebhookExecute(message: MessageCreate(components: .value([v2]), flags: .value(.isComponentsV2)))
        #expect(throws: DiscordError.validation(.invalidValue)) { try v2Create.jsonValue(uploadIDs: [0], withComponents: true) }
        #expect(try v2Create.jsonValue(withComponents: true).objectValue?["flags"] == .number(try JSONNumber(rawValue: "32768")))
        let edit = try WebhookMessageEdit(content: .null, embeds: .null, flags: .value(.isComponentsV2),
            components: .value([v2]), attachments: .null, poll: .null)
        let fields = try #require(try edit.jsonValue(withComponents: true).objectValue)
        #expect(fields["content"] == .null && fields["embeds"] == .null && fields["attachments"] == .null && fields["poll"] == .null)
        #expect(fields["sticker_ids"] == nil)
        #expect(throws: DiscordError.validation(.missingValue)) { try edit.jsonValue(uploadIDs: [0], withComponents: true) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookMessageEdit(flags: .value(.isComponentsV2)) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookMessageEdit(flags: .value([]), previousFlags: 1 << 15)
        }
        let uploaded = try MessageAttachmentRequest(id: .upload(0), filename: "a.txt")
        let fileComponent = try MessageComponent(data: Data(#"{"type":13,"file":{"url":"attachment://a.txt"}}"#.utf8))
        let existingV2 = try WebhookMessageEdit(components: .value([fileComponent]), attachments: .value([uploaded]), previousFlags: 1 << 15)
        let existingV2Fields = try #require(try existingV2.jsonValue(uploadIDs: [0], withComponents: true).objectValue)
        #expect(existingV2Fields["components"] == .array([try fileComponent.jsonValue()]))
        #expect(existingV2Fields["attachments"] == .array([try uploaded.jsonValue()]))
        #expect(existingV2Fields["flags"] == nil && existingV2Fields["content"] == nil && existingV2Fields["embeds"] == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try existingV2.jsonValue(withComponents: true) }
        let uploadEdit = try WebhookMessageEdit(attachments: .value([uploaded]))
        #expect(try uploadEdit.jsonValue(uploadIDs: [0]).objectValue?["attachments"] != nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try uploadEdit.jsonValue() }
        #expect(throws: DiscordError.validation(.missingValue)) { try WebhookMessageEdit().jsonValue(uploadIDs: [0]) }
        for clearing in [Field<[MessageComponent]>.null, .value([])] {
            let clear = try WebhookMessageEdit(components: clearing)
            #expect(throws: DiscordError.validation(.invalidValue)) { try clear.jsonValue() }
            #expect(try clear.jsonValue(withComponents: true).objectValue?["components"] != nil)
            #expect(try clear.jsonValue(ownership: .applicationOwned).objectValue?["components"] != nil)
        }
        #expect(try WebhookMessageEdit(content: .null, components: .null).jsonValue(withComponents: true) == .object(["content": .null, "components": .null]))
    }

    /// Independent complete incoming fixture includes nullable required keys and exact unknown numeric data.
    static let fixture = #"{"id":"18446744073709551615","type":1,"guild_id":null,"channel_id":null,"name":"private-name","avatar":null,"token":"private-token","application_id":null,"url":"https://discord.com/api/webhooks/1/private-token","future":184467440737095516160001}"#
}

/// Local exact-tree extraction used solely by webhook assertions, without encoding or lossy bridges.
private extension JSONValue {
    /// Returns object fields or nil for nonobject roots, preserving numeric lexemes and unknown values.
    var objectValue: [String: JSONValue]? { if case .object(let fields) = self { fields } else { nil } }
}
