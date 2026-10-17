import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Local expression request validation covers exact wire bodies, presence, Unicode scalar bounds,
/// canonical media and allocation limits without credentials, media playback or live requests.
@Suite struct ExpressionRequestTests {
    /// Every request produces exactly its documented fields and preserves absent/null/empty distinctions.
    /// - Throws: Unexpected request validation or numeric construction fails the test.
    @Test func completeBodiesAndPresence() throws {
        let image = "data:image/png;base64,YQ=="
        let audio = "data:audio/mpeg;base64,YQ=="
        let roles: [RoleID] = [.init(rawValue: .max), .init(rawValue: 0)]
        let emoji = try GuildEmojiCreate(name: "private-emoji", image: image, roles: roles)
        #expect(emoji.jsonValue() == .object(["name": .string("private-emoji"), "image": .string(image),
            "roles": .array([.string("18446744073709551615"), .string("0")])]))
        #expect(try GuildEmojiCreate(name: "ab", image: image).jsonValue() ==
            .object(["name": .string("ab"), "image": .string(image), "roles": .array([])]))
        #expect(try GuildEmojiModify().jsonValue() == .object([:]))
        #expect(try GuildEmojiModify(name: .value("ab"), roles: .null).jsonValue() ==
            .object(["name": .string("ab"), "roles": .null]))
        #expect(try GuildEmojiModify(roles: .value([])).jsonValue() == .object(["roles": .array([])]))
        #expect(try GuildEmojiModify(roles: .value(roles)).jsonValue() == .object([
            "roles": .array([.string("18446744073709551615"), .string("0")])]))
        #expect(try ApplicationEmojiCreate(name: "ab", image: image).jsonValue() ==
            .object(["name": .string("ab"), "image": .string(image)]))
        #expect(try ApplicationEmojiModify(name: "ab").jsonValue() == .object(["name": .string("ab")]))
        #expect(try ApplicationEmojiModify().jsonValue() == .object([:]))
        #expect(try ApplicationEmojiModify(name: .absent).jsonValue() == .object([:]))
        #expect(try ApplicationEmojiModify(name: .value("ab")).jsonValue() == .object(["name": .string("ab")]))
        #expect(try GuildStickerModify().jsonValue() == .object([:]))
        #expect(try GuildStickerModify(name: .value("ab"), description: .value("description"), tags: .value("wave")).jsonValue() ==
            .object(["name": .string("ab"), "description": .string("description"), "tags": .string("wave")]))
        #expect(try GuildStickerModify(description: .null, tags: .value("")).jsonValue() ==
            .object(["description": .null, "tags": .string("")]))
        #expect(try GuildSoundboardSoundCreate(name: "ab", sound: audio).jsonValue() ==
            .object(["name": .string("ab"), "sound": .string(audio)]))
        let sound = try GuildSoundboardSoundCreate(name: "ab", sound: audio, volume: .value(0.25),
            emojiID: .value(.init(rawValue: .max)), emojiName: .value("🦆"))
        #expect(sound.jsonValue() == .object(["name": .string("ab"), "sound": .string(audio),
            "volume": .number(try JSONNumber(rawValue: "0.25")),
            "emoji_id": .string("18446744073709551615"), "emoji_name": .string("🦆")]))
        #expect(try GuildSoundboardSoundCreate(name: "ab", sound: audio, volume: .null, emojiID: .null,
            emojiName: .null).jsonValue() == .object(["name": .string("ab"), "sound": .string(audio),
                "volume": .null, "emoji_id": .null, "emoji_name": .null]))
        #expect(try GuildSoundboardSoundModify().jsonValue() == .object([:]))
        #expect(try GuildSoundboardSoundModify(name: .value("ab"), volume: .null, emojiID: .null,
            emojiName: .null).jsonValue() == .object(["name": .string("ab"), "volume": .null,
                "emoji_id": .null, "emoji_name": .null]))
        #expect(try GuildSoundboardSoundModify(volume: .value(0.25), emojiID: .value(.init(rawValue: .max)),
            emojiName: .value("🦆")).jsonValue() == .object(["volume": .number(try JSONNumber(rawValue: "0.25")),
                "emoji_id": .string("18446744073709551615"), "emoji_name": .string("🦆")]))
        #expect(try SoundboardSoundSend(soundID: .init(rawValue: 1)).jsonValue() == .object(["sound_id": .string("1")]))
        #expect(try SoundboardSoundSend(soundID: .init(rawValue: .max), sourceGuildID: .null).jsonValue() ==
            .object(["sound_id": .string("18446744073709551615"), "source_guild_id": .null]))
        #expect(try SoundboardSoundSend(soundID: .init(rawValue: 0), sourceGuildID: .value(.init(rawValue: .max))).jsonValue() ==
            .object(["sound_id": .string("0"), "source_guild_id": .string("18446744073709551615")]))
    }

    /// Guild/application names, exact role order, distinctness, transport capacity and current image media are enforced.
    /// Premium role semantics remain server checks because an ID contains no subscription integration context.
    /// - Throws: Unexpected valid constructor failures fail the test.
    @Test func emojiNamesRolesAndMedia() throws {
        let image = "data:image/png;base64,YQ=="
        for length in [2, 32] {
            let name = String(repeating: "x", count: length)
            #expect(try GuildEmojiCreate(name: name, image: image).jsonValue() ==
                .object(["name": .string(name), "image": .string(image), "roles": .array([])]))
            #expect(try GuildEmojiModify(name: .value(name)).jsonValue() == .object(["name": .string(name)]))
            #expect(try ApplicationEmojiCreate(name: name, image: image).jsonValue() ==
                .object(["name": .string(name), "image": .string(image)]))
            #expect(try ApplicationEmojiModify(name: name).jsonValue() == .object(["name": .string(name)]))
            #expect(try ApplicationEmojiModify(name: .value(name)).jsonValue() == .object(["name": .string(name)]))
        }
        for invalid in ["", "x", String(repeating: "x", count: 33)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiCreate(name: invalid, image: image) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiModify(name: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiCreate(name: invalid, image: image) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiModify(name: invalid) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiModify(name: .value(invalid)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiModify(name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiModify(name: .null) }
        let roles = (0..<1_521).map { RoleID(rawValue: UInt64($0)) }
        let expected = JSONValue.array(roles.map { .string($0.description) })
        guard case .object(let create) = try GuildEmojiCreate(name: "ab", image: image, roles: roles).jsonValue(),
              case .object(let modify) = try GuildEmojiModify(roles: .value(roles)).jsonValue()
        else { Issue.record("Expected objects"); return }
        #expect(create["roles"] == expected)
        #expect(modify["roles"] == expected)
        let excessive = roles + [.init(rawValue: 1_521)]
        #expect(throws: DiscordError.validation(.limitExceeded)) { try GuildEmojiCreate(name: "ab", image: image, roles: excessive) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try GuildEmojiModify(roles: .value(excessive)) }
        let duplicates: [RoleID] = [.init(rawValue: .max), .init(rawValue: .max)]
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiCreate(name: "ab", image: image, roles: duplicates) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiModify(roles: .value(duplicates)) }
        for media in ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif"] {
            let uri = "data:\(media);base64,YQ=="
            #expect(try ApplicationEmojiCreate(name: "ab", image: uri).jsonValue() ==
                .object(["name": .string("ab"), "image": .string(uri)]))
            #expect(try GuildEmojiCreate(name: "ab", image: uri).jsonValue() ==
                .object(["name": .string("ab"), "image": .string(uri), "roles": .array([])]))
        }
        for uri in ["data:audio/ogg;base64,YQ==", "data:image/svg+xml;base64,YQ==", "data:image/jpg;base64,YQ=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiCreate(name: "ab", image: uri) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiCreate(name: "ab", image: uri) }
        }
    }

    /// Sticker PATCH follows the written nullable description, 2...30 names and maximum-only tags rules.
    /// It rejects empty description values while preserving explicit null and empty tag updates.
    /// - Throws: Unexpected valid constructor failures fail the test.
    @Test func stickerMetadataBounds() throws {
        for nameLength in [2, 30] {
            for descriptionLength in [2, 100] {
                for tagsLength in [0, 200] {
                    let name = String(repeating: "x", count: nameLength)
                    let description = String(repeating: "d", count: descriptionLength)
                    let tags = String(repeating: "t", count: tagsLength)
                    #expect(try GuildStickerModify(name: .value(name), description: .value(description), tags: .value(tags)).jsonValue() ==
                        .object(["name": .string(name), "description": .string(description), "tags": .string(tags)]))
                }
            }
        }
        for invalid in ["", "x", String(repeating: "x", count: 31)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildStickerModify(name: .value(invalid)) }
        }
        for invalid in ["", "x", String(repeating: "x", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildStickerModify(description: .value(invalid)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildStickerModify(tags: .value(String(repeating: "x", count: 201))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildStickerModify(name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildStickerModify(tags: .null) }
    }

    /// Sound creation/editing covers endpoint text limits, nullable settings, both media types and finite normalized volume.
    /// MIME/content matching, audio duration and independent emoji-selector compatibility remain Discord checks.
    /// - Throws: Unexpected valid request/numeric construction fails the test.
    @Test func soundboardBoundsAndMedia() throws {
        let audio = "data:audio/mpeg;base64,YQ=="
        for nameLength in [2, 32] {
            let name = String(repeating: "s", count: nameLength)
            #expect(try GuildSoundboardSoundCreate(name: name, sound: audio).jsonValue() ==
                .object(["name": .string(name), "sound": .string(audio)]))
            #expect(try GuildSoundboardSoundModify(name: .value(name)).jsonValue() == .object(["name": .string(name)]))
        }
        for invalid in ["", "x", String(repeating: "x", count: 33)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundCreate(name: invalid, sound: audio) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundModify(name: .value(invalid)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundModify(name: .null) }
        for volume in [0.0, -0.0, 0.25, 1.0] {
            let number = JSONValue.number(try JSONNumber(rawValue: String(volume)))
            #expect(try GuildSoundboardSoundCreate(name: "ab", sound: audio, volume: .value(volume)).jsonValue() ==
                .object(["name": .string("ab"), "sound": .string(audio), "volume": number]))
            #expect(try GuildSoundboardSoundModify(volume: .value(volume)).jsonValue() == .object(["volume": number]))
        }
        for invalid in [-Double.leastNonzeroMagnitude, 1.0000000000000002, -1, 2, .infinity, -.infinity, .nan] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildSoundboardSoundCreate(name: "ab", sound: audio, volume: .value(invalid))
            }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundModify(volume: .value(invalid)) }
        }
        for length in [1, 32] {
            let emoji = String(repeating: "🦆", count: length)
            #expect(try GuildSoundboardSoundModify(emojiName: .value(emoji)).jsonValue() == .object(["emoji_name": .string(emoji)]))
            #expect(try GuildSoundboardSoundCreate(name: "ab", sound: audio, emojiName: .value(emoji)).jsonValue() ==
                .object(["name": .string("ab"), "sound": .string(audio), "emoji_name": .string(emoji)]))
        }
        for invalid in ["", String(repeating: "🦆", count: 33)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundModify(emojiName: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildSoundboardSoundCreate(name: "ab", sound: audio, emojiName: .value(invalid))
            }
        }
        #expect(try GuildSoundboardSoundCreate(name: "ab", sound: "data:audio/ogg;base64,YQ==").jsonValue() ==
            .object(["name": .string("ab"), "sound": .string("data:audio/ogg;base64,YQ==")]))
        for invalid in ["data:audio/wav;base64,YQ==", "data:video/ogg;base64,YQ==", "data:image/png;base64,YQ=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildSoundboardSoundCreate(name: "ab", sound: invalid) }
        }
    }

    /// URI validation rejects malformed/noncanonical input and enforces encoded/decoded bounds before large allocations.
    /// Exact caps, one-byte excess, predecode excess and invalid internal configurations exercise each failure path.
    /// - Throws: Unexpected valid request construction fails the test.
    @Test func dataURILimitsAndCanonicalSyntax() throws {
        let image = uri(media: "image/png", bytes: 262_144)
        #expect(try ApplicationEmojiCreate(name: "ab", image: image).jsonValue() ==
            .object(["name": .string("ab"), "image": .string(image)]))
        #expect(try GuildEmojiCreate(name: "ab", image: image).jsonValue() ==
            .object(["name": .string("ab"), "image": .string(image), "roles": .array([])]))
        let audio = uri(media: "audio/mpeg", bytes: 512_000)
        #expect(try GuildSoundboardSoundCreate(name: "ab", sound: audio).jsonValue() ==
            .object(["name": .string("ab"), "sound": .string(audio)]))
        for excess in [1, 3, 100] {
            #expect(throws: DiscordError.validation(.limitExceeded)) {
                try GuildEmojiCreate(name: "ab", image: uri(media: "image/png", bytes: 262_144 + excess))
            }
            #expect(throws: DiscordError.validation(.limitExceeded)) {
                try ApplicationEmojiCreate(name: "ab", image: uri(media: "image/png", bytes: 262_144 + excess))
            }
            #expect(throws: DiscordError.validation(.limitExceeded)) {
                try GuildSoundboardSoundCreate(name: "ab", sound: uri(media: "audio/ogg", bytes: 512_000 + excess))
            }
        }
        let invalid = ["", "YQ==", "data:image/png,YQ==", "data:image/png;base64,", "data:image/png;base64,YQ",
            "data:image/png;base64,YR==", "data:image/png;base64,YQ===", "data:image/png;base64,YQ==\n",
            "data:image/png;base64,Y Q==", "data:image/png;base64,_w==", "data:image/png;charset=utf-8;base64,YQ==",
            "DATA:image/png;base64,YQ==", "data:IMAGE/PNG;base64,YQ==", "data:;base64,YQ==",
            "data:image/png;base64,YQ==;base64,YQ=="]
        for value in invalid {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiCreate(name: "ab", image: value) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEmojiCreate(name: "ab", image: value) }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildSoundboardSoundCreate(name: "ab", sound: value.replacingOccurrences(of: "image/png", with: "audio/mpeg"))
            }
        }
        for maximum in [0, -1, Int.min, Int.max, Int.max / 4 * 3] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try expressionRequestDataURI("data:image/png;base64,YQ==", mediaTypes: ["image/png"], maximumBytes: maximum)
            }
        }
        #expect(try expressionRequestDataURI("data:image/png;base64,YQ==", mediaTypes: ["image/png"], maximumBytes: 1) ==
            .string("data:image/png;base64,YQ=="))
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try expressionRequestDataURI("data:image/png;base64,YWI=", mediaTypes: ["image/png"], maximumBytes: 1)
        }
    }

    /// Scalar counts preserve decomposed Unicode and every request conceals outgoing media/text in diagnostics.
    /// All bodies are immutable and repeatable, with exact JSON serialization available only explicitly.
    /// - Throws: Unexpected valid request construction or serialization fails the test.
    @Test func unicodeScalarsAndRedaction() throws {
        let decomposed = "e\u{301}"
        let image = "data:image/png;base64,YQ=="
        let audio = "data:audio/ogg;base64,YQ=="
        #expect(try ApplicationEmojiModify(name: decomposed).jsonValue() == .object(["name": .string(decomposed)]))
        #expect(try GuildStickerModify(name: .value(decomposed), description: .value(decomposed)).jsonValue() ==
            .object(["name": .string(decomposed), "description": .string(decomposed)]))
        let maximum = String(repeating: decomposed, count: 16)
        #expect(try ApplicationEmojiModify(name: maximum).jsonValue() == .object(["name": .string(maximum)]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEmojiModify(name: maximum + decomposed) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildStickerModify(name: .value(String(repeating: decomposed, count: 16)))
        }
        let payloads: [any GuildRequestPayload] = [
            try GuildEmojiCreate(name: "private-emoji", image: image),
            try GuildEmojiModify(name: .value("private-emoji")),
            try ApplicationEmojiCreate(name: "private-emoji", image: image),
            try ApplicationEmojiModify(name: "private-emoji"),
            try ApplicationEmojiModify(),
            try GuildStickerModify(name: .value("private-sticker"), description: .value("private-description")),
            try GuildSoundboardSoundCreate(name: "private-sound", sound: audio),
            try GuildSoundboardSoundModify(name: .value("private-sound")),
            try SoundboardSoundSend(soundID: .init(rawValue: .max), sourceGuildID: .value(.init(rawValue: .max)))
        ]
        for payload in payloads {
            #expect(!payload.description.contains("private-"))
            #expect(!payload.description.contains("YQ=="))
            #expect(payload.debugDescription == payload.description)
            #expect(!String(reflecting: payload).contains("private-"))
            #expect(payload.customMirror.children.count == 1)
            #expect(payload.jsonValue() == payload.jsonValue())
            #expect(try JSONValue.parse(payload.jsonValue().serialized()) == payload.jsonValue())
        }
    }

    /// Creates deterministic canonical media transport bytes without claiming valid decoded image/audio content.
    /// - Parameters:
    ///   - media: MIME type used by the tested endpoint.
    ///   - bytes: Nonnegative decoded byte count, including boundary and excessive sizes.
    /// - Returns: Canonical data URI whose payload repeats one fixed byte.
    private func uri(media: String, bytes: Int) -> String {
        "data:\(media);base64,\(Data(repeating: 0x61, count: bytes).base64EncodedString())"
    }
}
