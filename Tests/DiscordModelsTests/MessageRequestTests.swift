import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises outgoing message semantics independently of credentials, transport and live Discord state.
@Suite struct MessageRequestTests {
    /// Creation covers every JSON field and preserves exact numeric nonces and large snowflakes.
    @Test func completeCreateFields() throws {
        let reference = try MessageReference(data: Data("{\"type\":0,\"message_id\":\"18446744073709551615\"}".utf8))
        let embed = try MessageEmbed(data: Data("{\"title\":\"hello\",\"color\":16777215}".utf8))
        let poll = try PollCreate(question: "choose", answers: [PollMedia(text: .value("one")), PollMedia(text: .value("two"))])
        let theme = try MessageSharedClientTheme(data: Data("{\"colors\":[\"5865F2\"],\"gradient_angle\":360,\"base_mix\":100,\"base_theme\":null}".utf8))
        let attachment = try MessageAttachmentRequest(id: .upload(42), filename: "x.ogg", title: "title",
            description: "alt", durationSecs: 1.5, waveform: "AQID", isSpoiler: true)
        let request = try MessageCreate(content: .value("hello"), nonce: .value(.unsignedInteger(UInt64.max)),
            tts: .value(false), embeds: .value([embed]),
            allowedMentions: .value(MessageAllowedMentions(parse: [], repliedUser: false)),
            messageReference: .value(reference), components: .value([]),
            stickerIDs: .value([StickerID(rawValue: UInt64.max)]), attachments: .value([attachment]),
            flags: .value([.suppressEmbeds, .suppressNotifications]), enforceNonce: .value(true),
            poll: .value(poll), sharedClientTheme: .value(theme))
        let object = try fields(request.jsonValue(uploadIDs: [42]))
        #expect(object.count == 13)
        #expect(object["nonce"] == .number(try JSONNumber(rawValue: "18446744073709551615")))
        #expect(object["sticker_ids"] == .array([.string("18446744073709551615")]))
        #expect(object["tts"] == .bool(false))
        #expect(object["poll"] == (try poll.jsonValue()))
        #expect(try JSONValue.parse(request.serialized(uploadIDs: [42])) == .object(object))
        #expect(try attachment.jsonValue() == JSONValue.parse("{\"id\":42,\"filename\":\"x.ogg\",\"title\":\"title\",\"description\":\"alt\",\"duration_secs\":1.5,\"waveform\":\"AQID\",\"is_spoiler\":true}"))
    }

    /// Text and nonce boundaries use scalar counts while exact integer variants avoid floating-point conversion.
    @Test func contentNonceAndStickerBounds() throws {
        #expect(try MessageCreate(content: .value(String(repeating: "🦊", count: 2_000))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try MessageCreate(content: .value(String(repeating: "a", count: 2_001))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(content: .null) }
        #expect(try MessageNonce.string(String(repeating: "x", count: 25)).jsonValue() == .string(String(repeating: "x", count: 25)))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageNonce.string(String(repeating: "x", count: 26)).jsonValue() }
        #expect(try MessageNonce.integer(Int64.min).jsonValue() == .number(try JSONNumber(rawValue: String(Int64.min))))
        #expect(try MessageCreate(stickerIDs: .value((0..<3).map { StickerID(rawValue: UInt64($0)) })).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(stickerIDs: .value((0..<4).map { StickerID(rawValue: UInt64($0)) })) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(stickerIDs: .value([StickerID(rawValue: 1), StickerID(rawValue: 1)])) }
        #expect(throws: (any Error).self) { try MessageCreate(content: .value("x")).serialized(limits: .init(maximumBytes: 1)) }
    }

    /// Every create-only field rejects null even when another content field makes the message nonempty.
    @Test func createRejectsNullableFields() throws {
        let invalid: [() throws -> MessageCreate] = [
            { try MessageCreate(nonce: .null) }, { try MessageCreate(tts: .null) }, { try MessageCreate(embeds: .null) },
            { try MessageCreate(allowedMentions: .null) }, { try MessageCreate(messageReference: .null) },
            { try MessageCreate(components: .null) }, { try MessageCreate(stickerIDs: .null) },
            { try MessageCreate(attachments: .null) }, { try MessageCreate(flags: .null) },
            { try MessageCreate(enforceNonce: .null) }, { try MessageCreate(poll: .null) },
            { try MessageCreate(sharedClientTheme: .null) }
        ]
        for constructor in invalid { #expect(throws: DiscordError.validation(.invalidValue)) { try constructor() } }
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageCreate().jsonValue() }
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageCreate(content: .value(""), embeds: .value([])).jsonValue() }
        #expect(try MessageCreate().jsonValue(uploadIDs: [0]) == .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(content: .value("x"), flags: .value(.init(rawValue: 1))) }
    }

    /// Allowed mention policies preserve omission, empty selectors, explicit null and maximum-sized lists.
    @Test func mentionsPresenceAndConflicts() throws {
        #expect(try MessageAllowedMentions().jsonValue() == .object([:]))
        #expect(try MessageAllowedMentions(parse: [], roles: [], users: [], repliedUser: false).jsonValue() ==
            .object(["parse": .array([]), "roles": .array([]), "users": .array([]), "replied_user": .bool(false)]))
        #expect(try MessageAllowedMentions(parse: [.roles, .users], roles: .null, users: .null).jsonValue() ==
            .object(["parse": .array([.string("roles"), .string("users")]), "roles": .null, "users": .null]))
        let roles = (0..<100).map { RoleID(rawValue: UInt64($0)) }
        let users = (0..<100).map { UserID(rawValue: UInt64($0)) }
        #expect(try MessageAllowedMentions(parse: [.everyone], roles: roles, users: users).roles?.count == 100)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(parse: [.users, .users]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(roles: roles + [RoleID(rawValue: 100)]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(users: users + [UserID(rawValue: 100)]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(roles: [roles[0], roles[0]]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(users: [users[0], users[0]]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(parse: [.roles], roles: roles) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAllowedMentions(parse: [.users], users: users) }
    }

    /// Replies need a message; forwards additionally need a channel and can be reference-only messages.
    @Test func replyForwardValidation() throws {
        let forward = try MessageReference(data: Data("{\"type\":1,\"message_id\":\"42\",\"channel_id\":\"24\"}".utf8))
        #expect(try MessageCreate(messageReference: .value(forward)).jsonValue() == .object(["message_reference": forward.jsonValue()]))
        let missingChannel = try MessageReference(data: Data("{\"type\":1,\"message_id\":\"42\"}".utf8))
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageCreate(messageReference: .value(missingChannel)) }
        let missingMessage = try MessageReference(data: Data("{\"channel_id\":\"42\"}".utf8))
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageCreate(messageReference: .value(missingMessage)) }
        let reply = try MessageReference(data: Data("{\"message_id\":\"42\"}".utf8))
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageCreate(messageReference: .value(reply)).jsonValue() }
        let unknown = try MessageReference(data: Data("{\"type\":999,\"message_id\":\"42\"}".utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(content: .value("x"), messageReference: .value(unknown)) }
    }

    /// Attachment metadata distinguishes file placeholders from retained snowflakes and rejects malformed voice data.
    @Test func attachmentMetadataAndRetention() throws {
        let retained = try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: UInt64.max)), description: "alt", isSpoiler: false)
        let fresh = try MessageAttachmentRequest(id: .upload(42), description: String(repeating: "a", count: 1_024))
        #expect(try MessageEdit(attachments: .value([retained, fresh])).jsonValue(uploadIDs: [42]) != .null)
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageEdit().jsonValue(uploadIDs: [42]) }
        #expect(try MessageEdit(attachments: .value([])).jsonValue() == .object(["attachments": .array([])]))
        #expect(try MessageEdit(attachments: .null).jsonValue() == .object(["attachments": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(attachments: .value([retained])).jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(attachments: .value([fresh, fresh])).jsonValue(uploadIDs: [42]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(attachments: .value([fresh])).jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(attachments: .value([])).jsonValue(uploadIDs: [42]) }
        #expect(throws: DiscordError.validation(.missingValue)) { try MessageEdit(attachments: .null).jsonValue(uploadIDs: [42]) }
        for ids in [[-1], [0, 0], Array(0...10)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate().jsonValue(uploadIDs: ids) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .upload(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .upload(0), description: String(repeating: "a", count: 1_025)) }
        for duration in [-1, Double.nan, .infinity] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .upload(0), durationSecs: duration) }
        }
        for waveform in ["!", "AQ", Data(repeating: 1, count: 257).base64EncodedString()] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .upload(0), waveform: waveform) }
        }
        #expect(try MessageAttachmentRequest(id: .upload(0), durationSecs: 0, waveform: Data(repeating: 0, count: 256).base64EncodedString()).waveform != nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: 1)), filename: "rename") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: 1)), title: "rename") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: 1)), durationSecs: 1) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: 1)), waveform: "AQ==") }
    }

    /// Voice messages require one positive-duration audio upload and cannot mix ordinary message content.
    @Test func voiceMessageConstraints() throws {
        let attachment = try MessageAttachmentRequest(id: .upload(0), durationSecs: 1, waveform: "AQ==")
        let voice = try MessageCreate(attachments: .value([attachment]), flags: .value(.isVoiceMessage))
        #expect(try voice.jsonValue(uploadIDs: [0], uploadContentTypes: [0: "audio/ogg"]) != .null)
        for types in [[:], [0: "application/ogg"]] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try voice.jsonValue(uploadIDs: [0], uploadContentTypes: types) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try voice.jsonValue(uploadIDs: [0, 1], uploadContentTypes: [0: "audio/ogg"]) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageCreate(content: .value("x"), attachments: .value([attachment]), flags: .value(.isVoiceMessage))
                .jsonValue(uploadIDs: [0], uploadContentTypes: [0: "audio/ogg"])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(flags: .value([.isVoiceMessage, .isComponentsV2])) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageCreate(tts: .value(true), attachments: .value([attachment]), flags: .value(.isVoiceMessage))
                .jsonValue(uploadIDs: [0], uploadContentTypes: [0: "audio/ogg"])
        }
        let incomplete = try MessageAttachmentRequest(id: .upload(0))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageCreate(attachments: .value([incomplete]), flags: .value(.isVoiceMessage))
                .jsonValue(uploadIDs: [0], uploadContentTypes: [0: "audio/ogg"])
        }
    }

    /// Edit nulls remain distinct from absent fields; immutable bits and irreversible V2 state are protected.
    @Test func editPresenceFlagsAndV2Transitions() throws {
        let empty = try MessageEdit()
        #expect(try empty.jsonValue() == .object([:]))
        #expect(try empty.serialized() == Data("{}".utf8))
        let nulls = try MessageEdit(content: .null, embeds: .null, flags: .null, allowedMentions: .null,
                                   components: .null, attachments: .null, stickerIDs: .null, poll: .null)
        #expect(try fields(nulls.jsonValue()).count == 8)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try MessageEdit(content: .value(String(repeating: "x", count: 2_001))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(flags: .value(.init(rawValue: 1))) }
        let retained = try MessageEdit(flags: .value(.init(rawValue: (1 << 12) | (1 << 2))), previousFlags: 1 << 12)
        #expect(try fields(retained.jsonValue())["flags"] == .number(try JSONNumber(rawValue: "4100")))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(flags: .value([]), previousFlags: 1 << 12) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(content: .null, previousFlags: 1 << 13) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(flags: .value([]), previousFlags: 1 << 15) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(flags: .value(.isComponentsV2)) }
        let transition = try MessageEdit(content: .null, embeds: .value([]), flags: .value(.isComponentsV2), stickerIDs: .value([]), poll: .null)
        #expect(try fields(transition.jsonValue()).count == 5)
        #expect(try MessageEdit(components: .value([]), previousFlags: 1 << 15).jsonValue() == .object(["components": .array([])]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(content: .value("x"), previousFlags: 1 << 15) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(stickerIDs: .value([StickerID(rawValue: 1)])) }
        let poll = try PollCreate(question: "x", answers: [PollMedia(text: .value("a")), PollMedia(text: .value("b"))])
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageEdit(poll: .value(poll)) }
        let v2 = try MessageComponent(jsonValue: JSONValue.parse("{\"type\":10,\"content\":\"hello\"}"))
        #expect(try MessageCreate(components: .value([v2]), flags: .value(.isComponentsV2)).jsonValue() != .null)
        #expect(throws: (any Error).self) { try MessageCreate(components: .value([v2])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(content: .value(""), flags: .value(.isComponentsV2)) }
    }

    /// Rich embeds use trimmed inclusive text limits and reject only documented read-only fields.
    @Test func embedLimitsAndCurrentWritableMedia() throws {
        let padded = try MessageEmbed(data: JSONValue.object(["title": .string(" \n" + String(repeating: "a", count: 256) + "\n ")]).serialized())
        #expect(try MessageCreate(embeds: .value([padded])).jsonValue() != .null)
        let maximal = try MessageEmbed(data: JSONValue.object(["description": .string(String(repeating: "a", count: 3_000))]).serialized())
        #expect(try MessageCreate(embeds: .value([maximal, maximal])).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try MessageCreate(embeds: .value([maximal, maximal, padded])) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try MessageCreate(embeds: .value(Array(repeating: padded, count: 11))) }
        let writable = try MessageEmbed(data: Data("{\"title\":\"media\",\"flags\":32,\"components\":[],\"image\":{\"url\":\"https://example.com/a.png\",\"content_type\":\"image/png\",\"description\":\"alt\",\"placeholder\":\"hash\",\"placeholder_version\":1,\"flags\":32}}".utf8))
        #expect(try MessageCreate(embeds: .value([writable])).jsonValue() != .null)
        for json in ["{\"type\":\"rich\"}", "{\"provider\":{}}", "{\"video\":{}}", "{\"image\":{\"url\":\"x\",\"height\":1}}",
                     "{\"image\":{\"url\":\"x\",\"proxy_url\":\"x\"}}", "{\"future\":1}"] {
            let embed = try MessageEmbed(data: Data(json.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([embed])) }
        }
        for (key, count) in [("title", 257), ("description", 4_097)] {
            let embed = try MessageEmbed(data: JSONValue.object([key: .string(String(repeating: "a", count: count))]).serialized())
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([embed])) }
        }
        for json in [
            "{\"footer\":{\"text\":\"ok\",\"proxy_icon_url\":\"https://example.com/icon\"},\"author\":{\"name\":\"ok\",\"url\":\"https://example.com\",\"proxy_icon_url\":\"https://example.com/icon\"},\"fields\":[{\"name\":\"name\",\"value\":\"value\",\"inline\":false}]}",
            "{\"thumbnail\":{\"url\":\"https://example.com/x\",\"placeholder_version\":0,\"flags\":0}}"
        ] {
            let embed = try MessageEmbed(data: Data(json.utf8))
            #expect(try MessageEdit(embeds: .value([embed])).jsonValue() != .null)
        }
        let tooManyFields = try MessageEmbed(data: JSONValue.object(["fields": .array(Array(repeating: .object(["name": .string("n"), "value": .string("v")]), count: 26))]).serialized())
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([tooManyFields])) }
        let bigFooter = try MessageEmbed(data: JSONValue.object(["footer": .object(["text": .string(String(repeating: "x", count: 2_049))])]).serialized())
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([bigFooter])) }
        let bigAuthor = try MessageEmbed(data: JSONValue.object(["author": .object(["name": .string(String(repeating: "x", count: 257))])]).serialized())
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([bigAuthor])) }
        for json in ["{\"color\":16777216}", "{\"image\":{\"url\":\"x\",\"placeholder_version\":-1}}"] {
            let embed = try MessageEmbed(data: Data(json.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(embeds: .value([embed])) }
        }
    }

    /// Shared theme requests enforce documented upper bounds while retaining optional nullable base selection.
    @Test func sharedThemeBounds() throws {
        for json in [
            "{\"colors\":[],\"gradient_angle\":0,\"base_mix\":0}",
            "{\"colors\":[\"abcdef\",\"123456\",\"ABCDEF\",\"000000\",\"FFFFFF\"],\"gradient_angle\":360,\"base_mix\":100,\"base_theme\":4}"
        ] {
            let theme = try MessageSharedClientTheme(data: Data(json.utf8))
            #expect(try MessageCreate(sharedClientTheme: .value(theme)).jsonValue() != .null)
        }
        for json in [
            "{\"colors\":[\"nothex\"],\"gradient_angle\":0,\"base_mix\":0}",
            "{\"colors\":[\"abc\"],\"gradient_angle\":0,\"base_mix\":0}",
            "{\"colors\":[\"000000\",\"000000\",\"000000\",\"000000\",\"000000\",\"000000\"],\"gradient_angle\":0,\"base_mix\":0}",
            "{\"colors\":[],\"gradient_angle\":361,\"base_mix\":0}",
            "{\"colors\":[],\"gradient_angle\":0,\"base_mix\":101}",
            "{\"colors\":[],\"gradient_angle\":0,\"base_mix\":0,\"base_theme\":99}",
            "{\"colors\":[],\"gradient_angle\":0,\"base_mix\":0,\"future\":1}"
        ] {
            let theme = try MessageSharedClientTheme(data: Data(json.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageCreate(sharedClientTheme: .value(theme)) }
        }
    }

    /// Extracts a JSON object to keep assertions focused on observable outgoing fields.
    /// - Parameter value: Expected complete request object.
    /// - Returns: Validated field dictionary.
    /// - Throws: A Swift Testing requirement failure for an unexpected root kind.
    private func fields(_ value: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let fields) = value else { throw DiscordError.validation(.invalidValue) }
        return fields
    }
}
