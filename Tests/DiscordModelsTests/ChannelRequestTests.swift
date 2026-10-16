import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Validates API v10 channel payloads without credentials, network access or nondeterministic state.
@Suite struct ChannelRequestTests {
    /// Permission strings preserve every bit beyond machine width, explicit nulls and caller spelling.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func permissionDecimalAndPresence() throws {
        let huge = String(repeating: "9", count: 300)
        let overwrite = try ChannelPermissionOverwrite(id: .init(rawValue: .max), type: .role,
                                                       allow: .value(huge), deny: .null)
        #expect(overwrite.id.rawValue == .max)
        #expect(overwrite.type == .role)
        #expect(overwrite.allow == .value(huge))
        #expect(overwrite.deny == .null)
        #expect(try object(overwrite.jsonValue()) == ["id": .string("18446744073709551615"),
            "type": number(0), "allow": .string(huge), "deny": .null])
        let edit = try ChannelPermissionEdit(type: .member, allow: .null, deny: .value("000123"))
        #expect(edit.type == .member)
        #expect(edit.allow == .null)
        #expect(edit.deny == .value("000123"))
        #expect(try object(edit.jsonValue()) == ["type": number(1), "allow": .null, "deny": .string("000123")])
        #expect(try ChannelPermissionEdit(type: .role).jsonValue() == .object(["type": number(0)]))
        #expect(try ChannelPermissionOverwrite(id: .init(rawValue: 0), type: .member).jsonValue() ==
            .object(["id": .string("0"), "type": number(1)]))
        #expect(try ChannelPermissionEdit(type: .member, allow: .value("0"), deny: .value("18446744073709551616")).jsonValue() != .null)
    }

    /// Unsigned ASCII decimal grammar excludes alternate numeric spellings and never echoes invalid input.
    /// - Parameter value: One malformed permission decimal tested in both edit and overwrite selectors.
    @Test(arguments: ["", "-1", "+1", " 1", "1 ", "1.0", "1e2", "１２", "١", "1\n", "secret-token"])
    func malformedPermissionDecimals(_ value: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelPermissionEdit(type: .role, allow: .value(value)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelPermissionEdit(type: .member, deny: .value(value)) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelPermissionOverwrite(id: .init(rawValue: 1), type: .role, allow: .value(value))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelPermissionOverwrite(id: .init(rawValue: 1), type: .member, deny: .value(value))
        }
    }

    /// Reaction constructors enforce exactly one selector and tag updates keep omitted/nullable emoji states distinct.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func forumReactionsAndTags() throws {
        #expect(ChannelDefaultReactionRequest(emojiID: .init(rawValue: .max)).jsonValue() ==
            .object(["emoji_id": .string("18446744073709551615"), "emoji_name": .null]))
        #expect(try ChannelDefaultReactionRequest(emojiName: "🦊").jsonValue() ==
            .object(["emoji_id": .null, "emoji_name": .string("🦊")]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelDefaultReactionRequest(emojiName: "") }
        let tag = try ChannelForumTagRequest(id: .init(rawValue: .max), name: String(repeating: "🦊", count: 20),
            moderated: false, emojiID: .null, emojiName: .value("🦊"))
        #expect(tag.id?.rawValue == .max)
        #expect(tag.name.unicodeScalars.count == 20)
        #expect(tag.moderated == false)
        #expect(tag.emojiID == .null)
        #expect(tag.emojiName == .value("🦊"))
        #expect(try object(tag.jsonValue()) == ["id": .string("18446744073709551615"),
            "name": .string(String(repeating: "🦊", count: 20)), "moderated": .bool(false),
            "emoji_id": .null, "emoji_name": .string("🦊")])
        #expect(try ChannelForumTagRequest(name: "").jsonValue() == .object(["name": .string("")]))
        #expect(try ChannelForumTagRequest(name: "new", moderated: true,
            emojiID: .value(.init(rawValue: 1)), emojiName: .null).jsonValue() ==
            .object(["name": .string("new"), "moderated": .bool(true), "emoji_id": .string("1"), "emoji_name": .null]))
        #expect(throws: DiscordError.validation(.limitExceeded)) { try ChannelForumTagRequest(name: String(repeating: "x", count: 21)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelForumTagRequest(name: "x", emojiName: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelForumTagRequest(name: "x", emojiID: .value(.init(rawValue: 1)), emojiName: .value("🦊"))
        }
    }

    /// Forum modifications cover the complete applicable payload and preserve field units and exact IDs.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func completeForumModification() throws {
        let overwrite = try ChannelPermissionOverwrite(id: .init(rawValue: .max), type: .member,
                                                       allow: .value("18446744073709551616"), deny: .null)
        let tag = try ChannelForumTagRequest(id: .init(rawValue: 42), name: "tag")
        let reaction = try ChannelDefaultReactionRequest(emojiName: "🦊")
        let request = try ChannelModify(channelType: .guildForum, name: .value("forum"), position: .value(Int.max),
            topic: .value(String(repeating: "a", count: 4_096)), nsfw: .value(false), rateLimitPerUser: .value(21_600),
            permissionOverwrites: .value([overwrite]), parentID: .value(.init(rawValue: .max)),
            defaultAutoArchiveDuration: .value(10_080), flags: .value([.requireTag, .isSpoilerChannel]),
            availableTags: .value([tag]), defaultReactionEmoji: .value(reaction),
            defaultThreadRateLimitPerUser: .value(21_600), defaultSortOrder: .value(.creationDate),
            defaultForumLayout: .value(.galleryView))
        let fields = try object(request.jsonValue())
        #expect(request.channelType == .guildForum)
        #expect(request.parentChannelType == nil)
        #expect(fields.count == 14)
        #expect(fields["position"] == number(Int.max))
        #expect(fields["topic"] == .string(String(repeating: "a", count: 4_096)))
        #expect(fields["flags"] == number((1 << 4) | (1 << 21)))
        #expect(fields["permission_overwrites"] == .array([overwrite.jsonValue()]))
        #expect(fields["available_tags"] == .array([tag.jsonValue()]))
        #expect(fields["default_reaction_emoji"] == reaction.jsonValue())
        #expect(fields["parent_id"] == .string("18446744073709551615"))
        #expect(fields["default_sort_order"] == number(1))
        #expect(fields["default_forum_layout"] == number(2))
        #expect(try JSONValue.parse(request.jsonValue().serialized()) == request.jsonValue())
    }

    /// Voice/stage, group DM, category and thread payloads encode their distinct settings without context leakage.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func otherCompleteModifications() throws {
        let voice = try ChannelModify(channelType: .guildVoice, name: .value("voice"), position: .null,
            nsfw: .null, rateLimitPerUser: .null, bitrate: .value(384_000), userLimit: .value(99),
            permissionOverwrites: .null, parentID: .null, rtcRegion: .null, videoQualityMode: .value(.full), flags: .value([]))
        let voiceFields = try object(voice.jsonValue())
        #expect(voiceFields["bitrate"] == number(384_000))
        #expect(voiceFields["video_quality_mode"] == number(2))
        #expect(voiceFields["rtc_region"] == .null)
        #expect(voiceFields["permission_overwrites"] == .null)
        #expect(voiceFields["position"] == .null)
        #expect(try ChannelModify(channelType: .guildStageVoice, bitrate: .value(64_000), userLimit: .value(10_000),
            rtcRegion: .value("us-west"), videoQualityMode: .value(.auto)).jsonValue() ==
            .object(["bitrate": number(64_000), "user_limit": number(10_000), "rtc_region": .string("us-west"), "video_quality_mode": number(1)]))
        #expect(try ChannelModify(channelType: .groupDM, name: .value("group"), icon: .value("data:image/png;base64,AQID")).jsonValue() ==
            .object(["name": .string("group"), "icon": .string("data:image/png;base64,AQID")]))
        #expect(try ChannelModify(channelType: .groupDM, icon: .value("AQID")).jsonValue() == .object(["icon": .string("AQID")]))
        #expect(try ChannelModify(channelType: .guildCategory, position: .value(0), permissionOverwrites: .value([])).jsonValue() ==
            .object(["position": number(0), "permission_overwrites": .array([])]))
        #expect(try ChannelModify(channelType: .guildText, type: .value(.guildAnnouncement)).jsonValue() == .object(["type": number(5)]))
        #expect(try ChannelModify(channelType: .guildAnnouncement, type: .value(.guildText)).jsonValue() == .object(["type": number(0)]))
        let thread = try ChannelModify(channelType: .publicThread, parentChannelType: .guildForum,
            name: .value("thread"), rateLimitPerUser: .null, flags: .value(.pinned), archived: .value(false),
            autoArchiveDuration: .value(4_320), locked: .value(true), appliedTags: .value([.init(rawValue: .max)]))
        #expect(thread.parentChannelType == .guildForum)
        let threadFields = try object(thread.jsonValue())
        #expect(threadFields.count == 7)
        #expect(threadFields["archived"] == .bool(false))
        #expect(threadFields["locked"] == .bool(true))
        #expect(threadFields["applied_tags"] == .array([.string("18446744073709551615")]))
        #expect(threadFields["parentChannelType"] == nil)
    }

    /// Every documented field is accepted only by its documented channel kinds, including empty no-op edits.
    /// - Parameter field: Stable request-field fixture tested against every known channel kind.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test(arguments: ["name", "icon", "type", "position", "topic", "nsfw", "rate", "bitrate", "users", "overwrites",
        "parent", "region", "quality", "defaultArchive", "flags", "tags", "reaction", "defaultRate", "sort", "layout",
        "archived", "archive", "locked", "invitable", "applied"])
    func channelKindFieldMatrix(_ field: String) throws {
        let supported: [String: Set<Int>] = [
            "name": [0, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 16], "icon": [3], "type": [0, 5],
            "position": [0, 2, 4, 5, 13, 14, 15, 16], "topic": [0, 5, 15, 16], "nsfw": [0, 2, 5, 13, 15, 16],
            "rate": [0, 2, 10, 11, 12, 13, 15, 16], "bitrate": [2, 13], "users": [2, 13],
            "overwrites": [0, 2, 4, 5, 13, 14, 15, 16], "parent": [0, 2, 5, 13, 15, 16], "region": [2, 13],
            "quality": [2, 13], "defaultArchive": [0, 5, 15, 16], "flags": [0, 2, 5, 10, 11, 12, 15, 16],
            "tags": [15, 16], "reaction": [15, 16], "defaultRate": [0, 15, 16], "sort": [15, 16], "layout": [15],
            "archived": [10, 11, 12], "archive": [10, 11, 12], "locked": [10, 11, 12], "invitable": [12], "applied": [11]
        ]
        for raw in [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 16] {
            let kind = try #require(ChannelType(rawValue: raw))
            if supported[field]?.contains(raw) == true {
                #expect(try modification(kind, field).jsonValue() != .null)
            } else {
                #expect(throws: DiscordError.validation(.invalidValue)) { try modification(kind, field) }
            }
            if raw != 1 { #expect(try ChannelModify(channelType: kind).jsonValue() == .object([:])) }
        }
    }

    /// Nullable guild fields transmit explicit null; required-shaped fields reject null even with valid context.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func modificationNullability() throws {
        let forum = try ChannelModify(channelType: .guildForum, position: .null, topic: .null, nsfw: .null,
            rateLimitPerUser: .null, permissionOverwrites: .null, parentID: .null,
            defaultAutoArchiveDuration: .null, defaultReactionEmoji: .null, defaultSortOrder: .null)
        #expect(try object(forum.jsonValue()).values.allSatisfy { $0 == .null })
        #expect(try object(forum.jsonValue()).count == 9)
        let voice = try ChannelModify(channelType: .guildVoice, bitrate: .null, userLimit: .null, rtcRegion: .null, videoQualityMode: .null)
        #expect(try object(voice.jsonValue()).values.allSatisfy { $0 == .null })
        let invalid: [() throws -> ChannelModify] = [
            { try ChannelModify(channelType: .guildText, name: .null) },
            { try ChannelModify(channelType: .groupDM, icon: .null) },
            { try ChannelModify(channelType: .guildText, type: .null) },
            { try ChannelModify(channelType: .guildText, flags: .null) },
            { try ChannelModify(channelType: .guildForum, availableTags: .null) },
            { try ChannelModify(channelType: .guildText, defaultThreadRateLimitPerUser: .null) },
            { try ChannelModify(channelType: .guildForum, defaultForumLayout: .null) },
            { try ChannelModify(channelType: .publicThread, archived: .null) },
            { try ChannelModify(channelType: .publicThread, autoArchiveDuration: .null) },
            { try ChannelModify(channelType: .publicThread, locked: .null) },
            { try ChannelModify(channelType: .privateThread, invitable: .null) },
            { try ChannelModify(channelType: .publicThread, parentChannelType: .guildForum, appliedTags: .null) }
        ]
        for make in invalid { #expect(throws: DiscordError.validation(.invalidValue)) { try make() } }
    }

    /// String and numeric boundaries cover scalars, zero/unlimited settings and both voice channel ceilings.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func modificationBounds() throws {
        #expect(try ChannelModify(channelType: .guildText, name: .value(String(repeating: "🦊", count: 100)),
            topic: .value(String(repeating: "a", count: 1_024)), rateLimitPerUser: .value(0), defaultThreadRateLimitPerUser: .value(0)).jsonValue() != .null)
        #expect(try ChannelModify(channelType: .guildVoice, bitrate: .value(8_000), userLimit: .value(0)).jsonValue() != .null)
        #expect(try ChannelModify(channelType: .guildText, position: .value(Int.min)).jsonValue() == .object(["position": number(Int.min)]))
        for kind in [ChannelType.guildText, .guildForum, .guildMedia, .guildAnnouncement] {
            let maximum = [15, 16].contains(kind.rawValue) ? 4_096 : 1_024
            #expect(throws: DiscordError.validation(.limitExceeded)) { try ChannelModify(channelType: kind, topic: .value(String(repeating: "a", count: maximum + 1))) }
        }
        let invalid: [() throws -> ChannelModify] = [
            { try ChannelModify(channelType: .guildText, name: .value("")) },
            { try ChannelModify(channelType: .guildText, name: .value(String(repeating: "x", count: 101))) },
            { try ChannelModify(channelType: .guildText, type: .value(.guildVoice)) },
            { try ChannelModify(channelType: .guildText, rateLimitPerUser: .value(-1)) },
            { try ChannelModify(channelType: .guildText, rateLimitPerUser: .value(21_601)) },
            { try ChannelModify(channelType: .guildText, defaultThreadRateLimitPerUser: .value(-1)) },
            { try ChannelModify(channelType: .guildForum, defaultThreadRateLimitPerUser: .value(21_601)) },
            { try ChannelModify(channelType: .guildVoice, bitrate: .value(7_999)) },
            { try ChannelModify(channelType: .guildVoice, bitrate: .value(384_001)) },
            { try ChannelModify(channelType: .guildStageVoice, bitrate: .value(64_001)) },
            { try ChannelModify(channelType: .guildVoice, userLimit: .value(-1)) },
            { try ChannelModify(channelType: .guildVoice, userLimit: .value(100)) },
            { try ChannelModify(channelType: .guildStageVoice, userLimit: .value(10_001)) },
            { try ChannelModify(channelType: .guildVoice, rtcRegion: .value("")) },
            { try ChannelModify(channelType: .guildText, defaultAutoArchiveDuration: .value(61)) },
            { try ChannelModify(channelType: .publicThread, autoArchiveDuration: .value(0)) }
        ]
        for make in invalid { #expect(throws: DiscordError.validation(.invalidValue)) { try make() } }
        for value in [60, 1_440, 4_320, 10_080] {
            #expect(try ChannelModify(channelType: .guildText, defaultAutoArchiveDuration: .value(value)).jsonValue() == .object(["default_auto_archive_duration": number(value)]))
        }
        for icon in ["", "invalid-base64", "AQI", "data:image/;base64,AQID", "data:text/plain;base64,AQID", "data:image/png,AQID", "data:image/png;base64,"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .groupDM, icon: .value(icon)) }
        }
    }

    /// Writable flags are scoped to kinds/parents; tags and overwrite lists reject ambiguous duplicate IDs.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func flagsTagsAndOverwriteCombinations() throws {
        #expect(try ChannelModify(channelType: .guildMedia, flags: .value([.requireTag, .hideMediaDownloadOptions, .isSpoilerChannel])).jsonValue() != .null)
        #expect(try ChannelModify(channelType: .publicThread, parentChannelType: .guildMedia, flags: .value(.pinned), appliedTags: .value([])).jsonValue() != .null)
        #expect(try ChannelModify(channelType: .guildText, nsfw: .value(false), flags: .value(.isSpoilerChannel)).jsonValue() != .null)
        let invalid: [() throws -> ChannelModify] = [
            { try ChannelModify(channelType: .guildText, flags: .value(.channelObfuscated)) },
            { try ChannelModify(channelType: .guildForum, flags: .value(.hideMediaDownloadOptions)) },
            { try ChannelModify(channelType: .guildVoice, flags: .value(.requireTag)) },
            { try ChannelModify(channelType: .guildText, flags: .value(.pinned)) },
            { try ChannelModify(channelType: .publicThread, flags: .value(.pinned)) },
            { try ChannelModify(channelType: .publicThread, parentChannelType: .guildText, flags: .value(.pinned)) },
            { try ChannelModify(channelType: .guildText, nsfw: .value(true), flags: .value(.isSpoilerChannel)) },
            { try ChannelModify(channelType: .guildText, flags: .value(.init(rawValue: .max))) },
            { try ChannelModify(channelType: .publicThread, appliedTags: .value([])) }
        ]
        for make in invalid { #expect(throws: DiscordError.validation(.invalidValue)) { try make() } }
        let tags = try (0..<20).map { try ChannelForumTagRequest(id: .init(rawValue: UInt64($0)), name: "tag") }
        #expect(try ChannelModify(channelType: .guildForum, availableTags: .value(tags)).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .guildForum, availableTags: .value(tags + [tags[0]])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .guildForum, availableTags: .value([tags[0], tags[0]])) }
        #expect(try ChannelModify(channelType: .guildForum, availableTags: .value([ChannelForumTagRequest(name: "a"), ChannelForumTagRequest(name: "b")])).jsonValue() != .null)
        let overwrite = try ChannelPermissionOverwrite(id: .init(rawValue: 1), type: .role)
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .guildText, permissionOverwrites: .value([overwrite, overwrite])) }
        let member = try ChannelPermissionOverwrite(id: .init(rawValue: 1), type: .member)
        #expect(try ChannelModify(channelType: .guildText, permissionOverwrites: .value([overwrite, member])).jsonValue() != .null)
        let applied = (0..<5).map { ForumTagID(rawValue: UInt64($0)) }
        #expect(try ChannelModify(channelType: .publicThread, parentChannelType: .guildForum, appliedTags: .value(applied)).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .publicThread, parentChannelType: .guildForum, appliedTags: .value(applied + [.init(rawValue: 9)])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelModify(channelType: .publicThread, parentChannelType: .guildForum, appliedTags: .value([applied[0], applied[0]])) }
    }

    /// Voice status clear/empty/boundary settings and recipient diagnostics retain their distinct security semantics.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func voiceStatusAndRecipientSecrets() throws {
        #expect(try VoiceChannelStatus(status: nil).jsonValue() == .object(["status": .null]))
        #expect(try VoiceChannelStatus(status: "").status == "")
        #expect(try VoiceChannelStatus(status: String(repeating: "🦊", count: 500)).jsonValue() ==
            .object(["status": .string(String(repeating: "🦊", count: 500))]))
        #expect(throws: DiscordError.validation(.limitExceeded)) { try VoiceChannelStatus(status: String(repeating: "x", count: 501)) }
        let request = try GroupDMRecipientAdd(accessToken: "sensitive-oauth-token", nick: "private-nickname")
        #expect(request.jsonValue() == .object(["access_token": .string("sensitive-oauth-token"), "nick": .string("private-nickname")]))
        #expect(request.description == "GroupDMRecipientAdd(redacted)")
        #expect(request.debugDescription == request.description)
        #expect(!String(reflecting: request).contains("sensitive"))
        #expect(!String(describing: request).contains("nickname"))
        #expect(Mirror(reflecting: request).children.count == 1)
        #expect(Mirror(reflecting: request).children.first?.label == "redacted")
        #expect(GroupDMRecipientAdd(accessToken: try BearerToken("token"), nick: "").jsonValue() ==
            .object(["access_token": .string("token"), "nick": .string("")]))
        #expect(throws: DiscordError.validation(.emptyCredential)) { try GroupDMRecipientAdd(accessToken: "", nick: "nickname") }
        #expect(throws: DiscordError.validation(.invalidCredential)) { try GroupDMRecipientAdd(accessToken: "token\n", nick: "nickname") }
    }

    /// Thread starts preserve v10 private defaults and reject fields that cannot apply to the requested thread kind.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func threadStarts() throws {
        #expect(try ThreadStartFromMessage(name: "thread").jsonValue() == .object(["name": .string("thread")]))
        #expect(try ThreadStartFromMessage(name: "thread", autoArchiveDuration: 60, rateLimitPerUser: .null).jsonValue() ==
            .object(["name": .string("thread"), "auto_archive_duration": number(60), "rate_limit_per_user": .null]))
        #expect(try ThreadStartWithoutMessage(name: "thread", invitable: false).jsonValue() ==
            .object(["name": .string("thread"), "invitable": .bool(false)]))
        #expect(try ThreadStartWithoutMessage(name: "thread", type: .privateThread, autoArchiveDuration: 10_080,
            invitable: true, rateLimitPerUser: .value(21_600)).jsonValue() == .object(["name": .string("thread"),
            "type": number(12), "auto_archive_duration": number(10_080), "invitable": .bool(true), "rate_limit_per_user": number(21_600)]))
        for kind in [ChannelType.announcementThread, .publicThread] {
            #expect(try ThreadStartWithoutMessage(name: "t", type: kind).jsonValue() == .object(["name": .string("t"), "type": number(kind.rawValue)]))
            #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartWithoutMessage(name: "t", type: kind, invitable: false) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartWithoutMessage(name: "t", type: .guildText) }
        for name in ["", String(repeating: "a", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartFromMessage(name: name) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartWithoutMessage(name: name) }
        }
        for duration in [60, 1_440, 4_320, 10_080] {
            #expect(try ThreadStartFromMessage(name: String(repeating: "🦊", count: 100), autoArchiveDuration: duration).jsonValue() != .null)
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartFromMessage(name: "x", autoArchiveDuration: 0) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartWithoutMessage(name: "x", autoArchiveDuration: 61) }
        for rate in [-1, 21_601] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartFromMessage(name: "x", rateLimitPerUser: .value(rate)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ThreadStartWithoutMessage(name: "x", rateLimitPerUser: .value(rate)) }
        }
    }

    /// Forum/media first messages use the shared message validator while enforcing the narrower endpoint schema.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func forumThreadMessagesAndUploads() throws {
        let embed = try MessageEmbed(data: Data("{\"title\":\"title\"}".utf8))
        let attachment = try MessageAttachmentRequest(id: .upload(7), description: "alt")
        let mentions = try MessageAllowedMentions(parse: [])
        let message = try MessageCreate(content: .value("post"), embeds: .value([embed]), allowedMentions: .value(mentions),
            components: .value([]), stickerIDs: .value([.init(rawValue: .max)]), attachments: .value([attachment]),
            flags: .value([.suppressEmbeds, .suppressNotifications]))
        let request = try ForumThreadStart(name: "thread", message: message, autoArchiveDuration: 1_440,
            rateLimitPerUser: .null, appliedTags: [.init(rawValue: .max)])
        let fields = try object(request.jsonValue(uploadIDs: [7], uploadContentTypes: [7: "image/png"]))
        #expect(try fields["message"] == message.jsonValue(uploadIDs: [7]))
        #expect(fields["applied_tags"] == .array([.string("18446744073709551615")]))
        #expect(fields["rate_limit_per_user"] == .null)
        #expect(fields["auto_archive_duration"] == number(1_440))
        #expect(request.message.content == .value("post"))
        #expect(try ForumThreadStart(name: "t", message: MessageCreate(content: .value("post"))).jsonValue() ==
            .object(["name": .string("t"), "message": .object(["content": .string("post")])]))
        let fileOnly = try ForumThreadStart(name: "t", message: MessageCreate())
        #expect(try fileOnly.jsonValue(uploadIDs: [0]) == .object(["name": .string("t"), "message": .object([:])]))
        #expect(throws: DiscordError.validation(.missingValue)) { try fileOnly.jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try fileOnly.jsonValue(uploadIDs: [-1]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try fileOnly.jsonValue(uploadIDs: [0, 0]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try request.jsonValue(uploadIDs: [0]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "", message: message) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "t", message: message, autoArchiveDuration: 61) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "t", message: message, rateLimitPerUser: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "t", message: message, appliedTags: [.init(rawValue: 1), .init(rawValue: 1)]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "t", message: message, appliedTags: (0..<6).map { .init(rawValue: UInt64($0)) }) }
        #expect(try ForumThreadStart(name: "t", message: MessageCreate(content: .value("post")), rateLimitPerUser: .value(0), appliedTags: []).jsonValue() != .null)
    }

    /// Create Message options outside the forum message schema are rejected before any upload resources are acquired.
    /// - Throws: Unexpected request/fixture validation, JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func forumRejectsOtherMessageFields() throws {
        let reference = try MessageReference(data: Data("{\"message_id\":\"1\"}".utf8))
        let poll = try PollCreate(question: "q", answers: [PollMedia(text: .value("a")), PollMedia(text: .value("b"))])
        let theme = try MessageSharedClientTheme(data: Data("{\"colors\":[],\"gradient_angle\":0,\"base_mix\":0}".utf8))
        let messages = try [
            MessageCreate(content: .value("x"), nonce: .value(.string("nonce"))),
            MessageCreate(content: .value("x"), tts: .value(false)),
            MessageCreate(content: .value("x"), messageReference: .value(reference)),
            MessageCreate(content: .value("x"), enforceNonce: .value(false)),
            MessageCreate(content: .value("x"), poll: .value(poll)),
            MessageCreate(content: .value("x"), sharedClientTheme: .value(theme)),
            MessageCreate(flags: .value(.isVoiceMessage)),
            MessageCreate(components: .value([]), flags: .value(.isComponentsV2))
        ]
        for message in messages {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ForumThreadStart(name: "t", message: message) }
        }
    }

    /// Builds one minimal field fixture for the table of documented channel-kind eligibility.
    /// - Parameters:
    ///   - kind: Existing channel kind under test, including the intentionally unsupported direct-DM variant.
    ///   - field: Stable fixture selector from the parameterized matrix.
    /// - Returns: A payload containing precisely the selected nonnull field and required context.
    /// - Throws: Production validation errors for an incompatible kind; a test failure for unknown selectors.
    private func modification(_ kind: ChannelType, _ field: String) throws -> ChannelModify {
        switch field {
        case "name": try ChannelModify(channelType: kind, name: .value("x"))
        case "icon": try ChannelModify(channelType: kind, icon: .value("AQID"))
        case "type": try ChannelModify(channelType: kind, type: .value(.guildText))
        case "position": try ChannelModify(channelType: kind, position: .value(0))
        case "topic": try ChannelModify(channelType: kind, topic: .value(""))
        case "nsfw": try ChannelModify(channelType: kind, nsfw: .value(false))
        case "rate": try ChannelModify(channelType: kind, rateLimitPerUser: .value(0))
        case "bitrate": try ChannelModify(channelType: kind, bitrate: .value(8_000))
        case "users": try ChannelModify(channelType: kind, userLimit: .value(0))
        case "overwrites": try ChannelModify(channelType: kind, permissionOverwrites: .value([]))
        case "parent": try ChannelModify(channelType: kind, parentID: .value(.init(rawValue: 1)))
        case "region": try ChannelModify(channelType: kind, rtcRegion: .value("us-west"))
        case "quality": try ChannelModify(channelType: kind, videoQualityMode: .value(.auto))
        case "defaultArchive": try ChannelModify(channelType: kind, defaultAutoArchiveDuration: .value(60))
        case "flags": try ChannelModify(channelType: kind, flags: .value([]))
        case "tags": try ChannelModify(channelType: kind, availableTags: .value([]))
        case "reaction": try ChannelModify(channelType: kind, defaultReactionEmoji: .value(.init(emojiID: .init(rawValue: 1))))
        case "defaultRate": try ChannelModify(channelType: kind, defaultThreadRateLimitPerUser: .value(0))
        case "sort": try ChannelModify(channelType: kind, defaultSortOrder: .value(.latestActivity))
        case "layout": try ChannelModify(channelType: kind, defaultForumLayout: .value(.notSet))
        case "archived": try ChannelModify(channelType: kind, archived: .value(false))
        case "archive": try ChannelModify(channelType: kind, autoArchiveDuration: .value(60))
        case "locked": try ChannelModify(channelType: kind, locked: .value(false))
        case "invitable": try ChannelModify(channelType: kind, invitable: .value(false))
        case "applied": try ChannelModify(channelType: kind, parentChannelType: .guildForum, appliedTags: .value([]))
        default: throw DiscordError.validation(.missingValue)
        }
    }

    /// Extracts object fields so assertions cannot silently ignore an unexpected nonobject result.
    /// - Parameter value: JSON value returned by the request encoder under test.
    /// - Returns: Required object's complete dictionary, including explicit nulls.
    /// - Throws: A recorded Swift Testing issue when the result is not an object.
    private func object(_ value: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let fields) = value else { Issue.record("Expected an object"); throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Constructs exact integral expectations without a floating-point conversion.
    /// - Parameter value: Expected signed integer, including the platform maximum.
    /// - Returns: A JSON integer preserving the complete decimal spelling.
    /// Integral formatting is a test invariant; a violated invariant deliberately fails immediately.
    private func number(_ value: Int) -> JSONValue { .number(try! JSONNumber(rawValue: String(value))) }
}
