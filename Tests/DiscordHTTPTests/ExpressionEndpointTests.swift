import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Independent API v10 wire and response fixtures covering every currently documented expression operation.
@Suite struct ExpressionEndpointTests {
    /// All 25 descriptors expose exact routes/statuses, bot/public auth, partitions and conservative mutation policy.
    /// - Throws: Unexpected descriptor, credential, body or response fixture failures fail this test.
    @Test func completeCatalog() throws {
        let descriptors = try Self.catalog()
        #expect(descriptors.count == 25)
        let bot = Credential.bot(try BotToken("synthetic"))
        let bearer = Credential.bearer(try BearerToken("synthetic"))
        let methods = ["GET", "GET", "POST", "PATCH", "DELETE", "GET", "GET", "POST", "PATCH", "DELETE",
            "GET", "GET", "GET", "GET", "GET", "POST", "PATCH", "DELETE",
            "GET", "GET", "GET", "POST", "PATCH", "DELETE", "POST"]
        let guild = "guilds/18446744073709551615/"
        let app = "applications/18446744073709551615/"
        let id = "18446744073709551615"
        let suffixes = [guild + "emojis", guild + "emojis/" + id, guild + "emojis", guild + "emojis/" + id,
            guild + "emojis/" + id, app + "emojis", app + "emojis/" + id, app + "emojis", app + "emojis/" + id,
            app + "emojis/" + id, "stickers/" + id, "sticker-packs", "sticker-packs/" + id,
            guild + "stickers", guild + "stickers/" + id, guild + "stickers", guild + "stickers/" + id,
            guild + "stickers/" + id, "soundboard-default-sounds", guild + "soundboard-sounds",
            guild + "soundboard-sounds/" + id, guild + "soundboard-sounds", guild + "soundboard-sounds/" + id,
            guild + "soundboard-sounds/" + id, "channels/" + id + "/send-soundboard-sound"]
        let targetIndices: Set<Int> = [1, 3, 4, 6, 8, 9, 14, 16, 17, 20, 22, 23]
        let creations: Set<Int> = [2, 7, 15, 21]
        let empties: Set<Int> = [4, 9, 17, 23, 24]
        let bodyIndices: Set<Int> = [2, 3, 7, 8, 15, 16, 21, 22, 24]
        for (index, item) in descriptors.enumerated() {
            let (endpoint, bytes) = item
            let request = try endpoint.makeRequest(credential: bot, userAgent: "DiscordBot test")
            #expect(request.method == methods[index])
            #expect(request.url.absoluteString == "https://discord.com/api/v10/" + suffixes[index])
            #expect(endpoint.query.isEmpty)
            #expect(endpoint.authentication == (index == 11 ? .none : .bot))
            #expect(request.headers.contains { $0.name == "Authorization" } == (index != 11))
            if index != 11 {
                #expect(throws: DiscordError.validation(.missingValue)) {
                    try endpoint.makeRequest(credential: bearer, userAgent: "DiscordBot test")
                }
            }
            #expect(endpoint.majorParameter == ((index < 5 || (13...17).contains(index) || index >= 19) ? id : nil))
            #expect(endpoint.usesGlobalLimit)
            #expect(endpoint.successStatuses == (creations.contains(index) ? [201] : empties.contains(index) ? [204] : [200]))
            #expect(endpoint.retrySafety == (methods[index] == "GET" ? .safe : .unsafe))
            #expect(endpoint.readPolicy?.coalescing == (methods[index] == "GET" ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.bulk == nil)
            #expect((endpoint.body != nil) == bodyIndices.contains(index))
            #expect(try endpoint.decode(bytes) == bytes)
            #expect(endpoint.auditReason == nil)
            let route = endpoint.route
            #expect(!route.contains(id))
            #expect(route.hasPrefix(index >= 5 && index <= 9 ? "/applications/{application.id}/" :
                index == 24 ? "/channels/{channel.id}/" :
                index < 5 || (13...17).contains(index) || (19...23).contains(index) ? "/guilds/{guild.id}/" : "/"))
            if targetIndices.contains(index) {
                #expect(route.hasSuffix(index <= 9 ? "/{emoji.id}" : index <= 17 ? "/{sticker.id}" : "/{sound.id}"))
            }
            #expect(!String(reflecting: endpoint).contains(id))
            for bad in [Data("null".utf8), Data("{}".utf8), Data("true".utf8), Data("[null]".utf8)] {
                #expect(throws: (any Error).self) { try endpoint.decode(bad) }
            }
            if ![0, 13, 18].contains(index) { #expect(throws: (any Error).self) { try endpoint.decode(Data("[]".utf8)) } }
            if !empties.contains(index) { #expect(throws: (any Error).self) { try endpoint.decode(Data()) } }
        }
    }

    /// Optional policies retain explicit TTL/coalescing/tags; nil disables reuse for every expression read.
    /// - Throws: Unexpected descriptor errors fail this test; invalid TTLs are explicitly asserted.
    @Test func scopedReadPolicies() throws {
        let guild = GuildID(rawValue: 1), app = ApplicationID(rawValue: 2)
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["caller"])
        let reads: [(ReadPolicy?) throws -> Endpoint<Data>] = [
            { try Self.erase(EmojiEndpoints.listGuild(guildID: guild, readPolicy: $0)) },
            { try Self.erase(EmojiEndpoints.getGuild(guildID: guild, emojiID: .init(rawValue: 3), readPolicy: $0)) },
            { try Self.erase(EmojiEndpoints.listApplication(applicationID: app, readPolicy: $0)) },
            { try Self.erase(EmojiEndpoints.getApplication(applicationID: app, emojiID: .init(rawValue: 3), readPolicy: $0)) },
            { try Self.erase(StickerEndpoints.get(stickerID: .init(rawValue: 3), readPolicy: $0)) },
            { try Self.erase(StickerEndpoints.listPacks(readPolicy: $0)) },
            { try Self.erase(StickerEndpoints.getPack(packID: .init(rawValue: 3), readPolicy: $0)) },
            { try Self.erase(StickerEndpoints.listGuild(guildID: guild, readPolicy: $0)) },
            { try Self.erase(StickerEndpoints.getGuild(guildID: guild, stickerID: .init(rawValue: 3), readPolicy: $0)) },
            { try Self.erase(SoundboardEndpoints.listDefault(readPolicy: $0)) },
            { try Self.erase(SoundboardEndpoints.listGuild(guildID: guild, readPolicy: $0)) },
            { try Self.erase(SoundboardEndpoints.getGuild(guildID: guild, soundID: .init(rawValue: 3), readPolicy: $0)) },
        ]
        for make in reads {
            let endpoint = try make(policy)
            #expect(endpoint.readPolicy?.coalescing == false)
            #expect(endpoint.readPolicy?.timeToLive == .seconds(2))
            #expect(endpoint.readPolicy?.tags.contains("caller") == true)
            #expect(endpoint.invalidates.isEmpty)
            #expect(try make(nil).readPolicy == nil)
            #expect(throws: DiscordError.validation(.invalidValue)) { try make(ReadPolicy(timeToLive: .zero)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try make(ReadPolicy(timeToLive: .seconds(-1))) }
        }
        #expect(try EmojiEndpoints.listGuild(guildID: guild).readPolicy?.tags == ["emoji-catalog", "guild-catalog"])
        #expect(try EmojiEndpoints.listApplication(applicationID: app).readPolicy?.tags == ["application-emoji-catalog"])
        #expect(try StickerEndpoints.listPacks().readPolicy?.tags == ["sticker-pack-catalog"])
        #expect(try SoundboardEndpoints.listDefault().readPolicy?.tags == ["default-soundboard-catalog"])
    }

    /// Writes invalidate appropriate scoped catalogs; playback sends no audit or metadata invalidation.
    /// - Throws: Unexpected descriptor or request validation errors fail this test.
    @Test func mutationInvalidationAndAudit() throws {
        let descriptors = try Self.catalog()
        for index in [2, 3, 4, 15, 16, 17, 21, 22, 23] {
            let catalog = index <= 4 ? "emoji-catalog" : index <= 17 ? "sticker-catalog" : "soundboard-catalog"
            #expect(descriptors[index].0.invalidates == [catalog, "guild-catalog", "guild:18446744073709551615",
                "channel-catalog", "message-search", "message-catalog", "audit-log-catalog"])
        }
        for index in [7, 8, 9] { #expect(descriptors[index].0.invalidates == ["application-emoji-catalog"]) }
        #expect(descriptors[24].0.invalidates.isEmpty)
        let reason = "why +&日本"
        let audit = try EmojiEndpoints.deleteGuild(guildID: .init(rawValue: 1), emojiID: .init(rawValue: 2), auditReason: reason)
        let request = try audit.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(request.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "why%20%2B%26%E6%97%A5%E6%9C%AC" })
        #expect(!String(reflecting: audit).contains(reason))
        let mutations: [(String) throws -> Endpoint<Data>] = [
            { try Self.erase(EmojiEndpoints.createGuild(guildID: .init(rawValue: 1), request: Self.emojiCreation(), auditReason: $0)) },
            { try Self.erase(EmojiEndpoints.modifyGuild(guildID: .init(rawValue: 1), emojiID: .init(rawValue: 2), request: GuildEmojiModify(), auditReason: $0)) },
            { try Self.erase(EmojiEndpoints.deleteGuild(guildID: .init(rawValue: 1), emojiID: .init(rawValue: 2), auditReason: $0)) },
            { try Self.erase(StickerEndpoints.createGuild(guildID: .init(rawValue: 1), name: "fixture", description: "", tags: "wave", file: Self.stickerFile(), auditReason: $0)) },
            { try Self.erase(StickerEndpoints.modifyGuild(guildID: .init(rawValue: 1), stickerID: .init(rawValue: 2), request: GuildStickerModify(), auditReason: $0)) },
            { try Self.erase(StickerEndpoints.deleteGuild(guildID: .init(rawValue: 1), stickerID: .init(rawValue: 2), auditReason: $0)) },
            { try Self.erase(SoundboardEndpoints.createGuild(guildID: .init(rawValue: 1), request: Self.soundCreation(), auditReason: $0)) },
            { try Self.erase(SoundboardEndpoints.modifyGuild(guildID: .init(rawValue: 1), soundID: .init(rawValue: 2), request: GuildSoundboardSoundModify(), auditReason: $0)) },
            { try Self.erase(SoundboardEndpoints.deleteGuild(guildID: .init(rawValue: 1), soundID: .init(rawValue: 2), auditReason: $0)) },
        ]
        for make in mutations {
            #expect(try make(String(repeating: "a", count: 512)).auditReason?.count == 512)
            for bad in ["\n", String(repeating: "a", count: 513)] {
                #expect(throws: DiscordError.validation(.invalidValue)) { try make(bad) }
            }
        }
    }

    /// Validated creation/edit/play JSON retains exact IDs, explicit nulls, and only documented fields.
    /// - Throws: Unexpected request, body or descriptor errors fail this test.
    @Test func requestBodiesAndEmptyCollections() throws {
        let descriptors = try Self.catalog()
        let expected: [Int: JSONValue] = [
            2: try Self.emojiCreation().jsonValue(),
            3: try GuildEmojiModify(name: .value("renamed"), roles: .null).jsonValue(),
            7: try ApplicationEmojiCreate(name: "fixture", image: Self.imageURI).jsonValue(),
            8: try ApplicationEmojiModify(name: "renamed").jsonValue(),
            16: try GuildStickerModify(name: .value("renamed"), description: .null, tags: .value("new")).jsonValue(),
            21: try Self.soundCreation().jsonValue(),
            22: try GuildSoundboardSoundModify(name: .value("renamed"), volume: .null, emojiID: .null, emojiName: .value("🔥")).jsonValue(),
            24: try SoundboardSoundSend(soundID: .init(rawValue: UInt64.max), sourceGuildID: .value(.init(rawValue: UInt64.max))).jsonValue(),
        ]
        for (index, body) in expected {
            #expect(try JSONValue.parse(#require(descriptors[index].0.body?.storedBodyBytes)) == body)
            #expect(descriptors[index].0.body?.contentType == "application/json")
        }
        #expect(descriptors[15].0.body?.contentType.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(try EmojiEndpoints.listGuild(guildID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
        #expect(try StickerEndpoints.listGuild(guildID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
        #expect(try SoundboardEndpoints.listDefault().decode(Data("[]".utf8)).isEmpty)
        #expect(try EmojiEndpoints.listApplication(applicationID: .init(rawValue: 1)).decode(Data(#"{"items":[]}"#.utf8)).items.isEmpty)
        #expect(try StickerEndpoints.listPacks().decode(Data(#"{"sticker_packs":[]}"#.utf8)).stickerPacks.isEmpty)
        #expect(try SoundboardEndpoints.listGuild(guildID: .init(rawValue: 1)).decode(Data(#"{"items":[]}"#.utf8)).items.isEmpty)
        let local = try SoundboardEndpoints.send(channelID: .init(rawValue: 1), request: SoundboardSoundSend(soundID: .init(rawValue: 1)))
        #expect(try JSONValue.parse(#require(local.body?.storedBodyBytes)) == .object(["sound_id": .string("1")]))
    }

    /// Constructs all 25 typed descriptors and erases their results only after invoking their original decoders.
    /// - Returns: Stable emoji(10), sticker(8), soundboard(7) order, with independent successful response bytes.
    /// - Throws: Local fixture/request/descriptor errors before any I/O.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: UInt64.max), app = ApplicationID(rawValue: UInt64.max)
        let emoji = EmojiID(rawValue: UInt64.max), sticker = StickerID(rawValue: UInt64.max)
        let sound = SoundboardSoundID(rawValue: UInt64.max)
        let e = Data(emojiJSON.utf8), s = Data(stickerJSON.utf8), b = Data(soundJSON.utf8)
        return [
            (try erase(EmojiEndpoints.listGuild(guildID: guild)), Data(("[" + emojiJSON + "]").utf8)),
            (try erase(EmojiEndpoints.getGuild(guildID: guild, emojiID: emoji)), e),
            (try erase(EmojiEndpoints.createGuild(guildID: guild, request: emojiCreation())), e),
            (try erase(EmojiEndpoints.modifyGuild(guildID: guild, emojiID: emoji, request: GuildEmojiModify(name: .value("renamed"), roles: .null))), e),
            (try erase(EmojiEndpoints.deleteGuild(guildID: guild, emojiID: emoji)), Data()),
            (try erase(EmojiEndpoints.listApplication(applicationID: app)), Data(("{\"items\":[" + emojiJSON + "]}").utf8)),
            (try erase(EmojiEndpoints.getApplication(applicationID: app, emojiID: emoji)), e),
            (try erase(EmojiEndpoints.createApplication(applicationID: app, request: ApplicationEmojiCreate(name: "fixture", image: imageURI))), e),
            (try erase(EmojiEndpoints.modifyApplication(applicationID: app, emojiID: emoji, request: ApplicationEmojiModify(name: "renamed"))), e),
            (try erase(EmojiEndpoints.deleteApplication(applicationID: app, emojiID: emoji)), Data()),
            (try erase(StickerEndpoints.get(stickerID: sticker)), s),
            (try erase(StickerEndpoints.listPacks()), Data(("{\"sticker_packs\":[" + packJSON + "]}").utf8)),
            (try erase(StickerEndpoints.getPack(packID: .init(rawValue: UInt64.max))), Data(packJSON.utf8)),
            (try erase(StickerEndpoints.listGuild(guildID: guild)), Data(("[" + stickerJSON + "]").utf8)),
            (try erase(StickerEndpoints.getGuild(guildID: guild, stickerID: sticker)), s),
            (try erase(StickerEndpoints.createGuild(guildID: guild, name: "fixture", description: "", tags: "wave", file: stickerFile())), s),
            (try erase(StickerEndpoints.modifyGuild(guildID: guild, stickerID: sticker,
                request: GuildStickerModify(name: .value("renamed"), description: .null, tags: .value("new")))), s),
            (try erase(StickerEndpoints.deleteGuild(guildID: guild, stickerID: sticker)), Data()),
            (try erase(SoundboardEndpoints.listDefault()), Data(("[" + soundJSON + "]").utf8)),
            (try erase(SoundboardEndpoints.listGuild(guildID: guild)), Data(("{\"items\":[" + soundJSON + "]}").utf8)),
            (try erase(SoundboardEndpoints.getGuild(guildID: guild, soundID: sound)), b),
            (try erase(SoundboardEndpoints.createGuild(guildID: guild, request: soundCreation())), b),
            (try erase(SoundboardEndpoints.modifyGuild(guildID: guild, soundID: sound,
                request: GuildSoundboardSoundModify(name: .value("renamed"), volume: .null, emojiID: .null, emojiName: .value("🔥")))), b),
            (try erase(SoundboardEndpoints.deleteGuild(guildID: guild, soundID: sound)), Data()),
            (try erase(SoundboardEndpoints.send(channelID: .init(rawValue: UInt64.max),
                request: SoundboardSoundSend(soundID: sound, sourceGuildID: .value(guild)))), Data()),
        ]
    }

    /// Copies immutable wire policy while retaining the original typed decoder's response validation.
    /// - Parameter endpoint: Typed expression operation under test.
    /// - Returns: Descriptor returning original bytes only after the typed decoder accepts them.
    /// - Throws: Descriptor errors while preserving all production metadata.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Makes a valid bounded guild emoji request with maximum-width role IDs.
    /// - Returns: Complete create payload; premium role eligibility remains an upstream server-state check.
    /// - Throws: Unexpected request validation errors fail fixture users.
    static func emojiCreation() throws -> GuildEmojiCreate {
        try GuildEmojiCreate(name: "fixture", image: imageURI, roles: [.init(rawValue: UInt64.max)])
    }

    /// Makes a valid bounded guild sound request without testing codec-specific media duration here.
    /// - Returns: Complete required sound payload with an MP3 data URI and explicit optional selectors.
    /// - Throws: Unexpected request validation errors fail fixture users.
    static func soundCreation() throws -> GuildSoundboardSoundCreate {
        try GuildSoundboardSoundCreate(name: "fixture", sound: "data:audio/mpeg;base64,SUQz", volume: .value(0.5),
            emojiID: .value(.init(rawValue: UInt64.max)), emojiName: .null)
    }

    /// Constructs owned upload bytes with a declared supported PNG media type; media inspection stays server-owned.
    /// - Returns: Small bounded sticker upload, reused independently by each descriptor construction.
    /// - Throws: Unexpected upload-file validation errors fail fixture users.
    static func stickerFile() throws -> StickerUploadFile {
        try StickerUploadFile(filename: "sticker.png", contentType: "image/png", bytes: Data([137, 80, 78, 71, 13, 10, 26, 10]))
    }

    /// Small base64 image fixture with no live file, network or Discord credential dependency.
    static let imageURI = "data:image/png;base64,iVBORw0KGgo="
    /// Independent emoji response with all written optional fields and unknown future metadata.
    static let emojiJSON = #"{"id":"18446744073709551615","name":"fixture","roles":["18446744073709551615"],"user":{"id":"7","username":"u","discriminator":"0","avatar":null},"require_colons":true,"managed":false,"animated":true,"available":false,"future":{"x":1}}"#
    /// Independent guild sticker with required nullable description and every optional written field.
    static let stickerJSON = #"{"id":"18446744073709551615","pack_id":"5","name":"fixture","description":null,"tags":"wave","type":2,"format_type":4,"available":false,"guild_id":"18446744073709551615","user":{"id":"7","username":"u","discriminator":"0","avatar":null},"sort_value":0,"future":true}"#
    /// Independent standard pack envelope uses an empty permitted sticker collection.
    static let packJSON = #"{"id":"18446744073709551615","stickers":[],"name":"pack","sku_id":"18446744073709551615","cover_sticker_id":"2","description":"fixture pack","banner_asset_id":"18446744073709551615","future":true}"#
    /// Independent sound fixture preserves nullable emoji name, unavailable state and maximum snowflakes.
    static let soundJSON = #"{"name":"fixture","sound_id":"18446744073709551615","volume":0.5,"emoji_id":"18446744073709551615","emoji_name":null,"guild_id":"18446744073709551615","available":false,"user":{"id":"7","username":"u","discriminator":"0","avatar":null},"future":true}"#
}
