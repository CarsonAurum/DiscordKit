import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises immutable API v10 guild request validation without network requests, credentials or timing sleeps.
@Suite struct GuildRequestTests {
    /// Defaults preserve omission, serialization is repeatable, and every request inherits redacted diagnostics.
    /// - Throws: Unexpected constructor, fixture or JSON-number validation fails the test.
    @Test func emptyRequestsAndDiagnostics() throws {
        let requests: [any GuildRequestPayload] = try [GuildModify(), GuildMemberModify(), GuildCurrentMemberModify(),
            GuildCurrentUserNickModify(), GuildBanCreate(), GuildRoleCreate(), GuildRoleModify(), GuildPrune(),
            GuildWidgetModify(), GuildWelcomeScreenModify(), GuildOnboardingModify(), GuildIncidentActionsModify()]
        for request in requests {
            #expect(request.jsonValue() == .object([:]))
            #expect(request.jsonValue() == request.jsonValue())
            #expect(request.description.hasSuffix("(redacted)"))
            #expect(request.debugDescription == request.description)
            #expect(Mirror(reflecting: request).children.count == 1)
        }
    }

    /// All guild settings encode their actual wire keys, scalar enum values and UInt64 snowflake extremes.
    /// - Throws: Unexpected constructor or JSON fixture validation fails the test.
    @Test func completeGuildModify() throws {
        let request = try GuildModify(name: .value(" Guild "), region: .null, verificationLevel: .value(.veryHigh),
            defaultMessageNotifications: .value(.onlyMentions), explicitContentFilter: .value(.allMembers),
            afkChannelID: .value(.init(rawValue: .max)), afkTimeout: .value(3_600), icon: .value("YQ=="),
            splash: .value("data:image/png;base64,YQ=="), discoverySplash: .null, banner: .null,
            systemChannelID: .null, systemChannelFlags: .value(.init(rawValue: 63)), rulesChannelID: .null,
            publicUpdatesChannelID: .value(.init(rawValue: 1)), preferredLocale: .value("en-US"),
            features: .value(["COMMUNITY", "INVITES_DISABLED"]), description: .value(""),
            premiumProgressBarEnabled: .value(false), safetyAlertsChannelID: .null)
        #expect(try object(request.jsonValue()) == ["name": .string(" Guild "), "region": .null,
            "verification_level": number(4), "default_message_notifications": number(1), "explicit_content_filter": number(2),
            "afk_channel_id": .string("18446744073709551615"), "afk_timeout": number(3_600),
            "icon": .string("YQ=="), "splash": .string("data:image/png;base64,YQ=="), "discovery_splash": .null,
            "banner": .null, "system_channel_id": .null, "system_channel_flags": number(63), "rules_channel_id": .null,
            "public_updates_channel_id": .string("1"), "preferred_locale": .string("en-US"),
            "features": .array([.string("COMMUNITY"), .string("INVITES_DISABLED")]), "description": .string(""),
            "premium_progress_bar_enabled": .bool(false), "safety_alerts_channel_id": .null])
        #expect(try GuildModify(name: .value(String(repeating: "🦊", count: 100)),
            description: .value(String(repeating: "d", count: 300))).jsonValue() != .null)
        #expect(try GuildModify(preferredLocale: .null, features: .value([])).jsonValue() ==
            .object(["features": .array([]), "preferred_locale": .null]))
        #expect(try GuildModify(verificationLevel: .null, defaultMessageNotifications: .null,
            explicitContentFilter: .null, afkChannelID: .null, icon: .null, splash: .null,
            description: .null).jsonValue() == .object(["verification_level": .null,
                "default_message_notifications": .null, "explicit_content_filter": .null,
                "afk_channel_id": .null, "icon": .null, "splash": .null, "description": .null]))
    }

    /// Invalid guild names are checked after trimming leading/trailing whitespace, without mutating valid spelling.
    /// - Parameter name: One invalid empty, whitespace-only, too-short or too-long guild name.
    @Test(arguments: ["", " ", " a ", "\n\t", String(repeating: "a", count: 101)])
    func invalidGuildNames(_ name: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(name: .value(name)) }
    }

    /// Guild settings reject forbidden nulls, malformed feature lists and invalid published bounds.
    @Test func invalidGuildSettings() {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(afkTimeout: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(afkTimeout: .value(61)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(systemChannelFlags: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(systemChannelFlags: .value(.init(rawValue: .max))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(features: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(features: .value([""])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(features: .value(["COMMUNITY", "COMMUNITY"])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(preferredLocale: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(region: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(premiumProgressBarEnabled: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(description: .value(String(repeating: "x", count: 301))) }
    }

    /// Every documented AFK timeout choice remains accepted with its exact unit of seconds.
    /// - Parameter seconds: One legal timeout, including both endpoints of the discrete choice set.
    /// - Throws: Unexpected constructor or number validation fails the test.
    @Test(arguments: [60, 300, 900, 1_800, 3_600]) func afkTimeoutChoices(_ seconds: Int) throws {
        #expect(try GuildModify(afkTimeout: .value(seconds)).jsonValue() == .object(["afk_timeout": number(seconds)]))
    }

    /// All image-bearing guild/profile/role settings reject malformed transport syntax without exposing input.
    /// - Parameter image: Invalid raw base64 or invalid image data URI.
    @Test(arguments: ["", "a", "YQ=", "YQ===", "YQ==\n", "data:image/;base64,YQ==", "data:text/plain;base64,YQ==", "data:image/png,YQ==", "data:image/png;base64,", "private-content"])
    func invalidImages(_ image: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(icon: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(splash: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(discoverySplash: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(banner: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(homeHeader: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildCurrentMemberModify(avatar: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildCurrentMemberModify(banner: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(icon: .value(image)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(icon: .value(image)) }
    }

    /// Forum creation covers all applicable settings and keeps optional nulls distinct from omissions.
    /// - Throws: Unexpected request or fixture validation fails the test.
    @Test func completeForumCreation() throws {
        let tag = try ChannelForumTagRequest(name: "tag")
        let overwrite = try ChannelPermissionOverwrite(id: .init(rawValue: .max), type: .role, allow: .value("18446744073709551616"))
        let reaction = try ChannelDefaultReactionRequest(emojiName: "🦊")
        let request = try GuildChannelCreate(name: "forum", type: .value(.guildForum), topic: .value(String(repeating: "x", count: 1_024)),
            rateLimitPerUser: .value(21_600), position: .value(Int.max), permissionOverwrites: .value([overwrite]),
            parentID: .value(.init(rawValue: .max)), nsfw: .value(false), defaultAutoArchiveDuration: .value(10_080),
            defaultReactionEmoji: .value(reaction), availableTags: .value([tag]), defaultSortOrder: .value(.creationDate),
            defaultForumLayout: .value(.galleryView), defaultThreadRateLimitPerUser: .value(21_600), flags: .value(.requireTag))
        let fields = try object(request.jsonValue())
        #expect(fields.count == 15)
        #expect(fields["name"] == .string("forum"))
        #expect(fields["type"] == number(15))
        #expect(fields["topic"] == .string(String(repeating: "x", count: 1_024)))
        #expect(fields["rate_limit_per_user"] == number(21_600))
        #expect(fields["position"] == number(Int.max))
        #expect(fields["permission_overwrites"] == .array([overwrite.jsonValue()]))
        #expect(fields["parent_id"] == .string("18446744073709551615"))
        #expect(fields["nsfw"] == .bool(false))
        #expect(fields["default_auto_archive_duration"] == number(10_080))
        #expect(fields["default_reaction_emoji"] == reaction.jsonValue())
        #expect(fields["available_tags"] == .array([tag.jsonValue()]))
        #expect(fields["default_sort_order"] == number(1))
        #expect(fields["default_forum_layout"] == number(2))
        #expect(fields["default_thread_rate_limit_per_user"] == number(21_600))
        #expect(fields["flags"] == number(16))
        #expect(try GuildChannelCreate(name: "default").jsonValue() == .object(["name": .string("default")]))
        #expect(try GuildChannelCreate(name: "null", type: .null, topic: .null, rateLimitPerUser: .null,
            position: .null, permissionOverwrites: .null, parentID: .null, nsfw: .null,
            defaultAutoArchiveDuration: .null, defaultThreadRateLimitPerUser: .null, flags: .null).jsonValue() ==
            .object(["name": .string("null"), "type": .null, "topic": .null, "rate_limit_per_user": .null,
                "position": .null, "permission_overwrites": .null, "parent_id": .null, "nsfw": .null,
                "default_auto_archive_duration": .null, "default_thread_rate_limit_per_user": .null, "flags": .null]))
    }

    /// Voice/stage creation observes distinct bitrate/user limits while preserving automatic region selection.
    /// - Throws: Unexpected request or fixture validation fails the test.
    @Test func voiceAndMediaCreation() throws {
        #expect(try GuildChannelCreate(name: "voice", type: .value(.guildVoice), bitrate: .value(384_000),
            userLimit: .value(99), rtcRegion: .null, videoQualityMode: .value(.full)).jsonValue() ==
            .object(["name": .string("voice"), "type": number(2), "bitrate": number(384_000),
                "user_limit": number(99), "rtc_region": .null, "video_quality_mode": number(2)]))
        #expect(try GuildChannelCreate(name: "stage", type: .value(.guildStageVoice), bitrate: .value(64_000),
            userLimit: .value(10_000), rtcRegion: .value("us-west"), videoQualityMode: .null).jsonValue() ==
            .object(["name": .string("stage"), "type": number(13), "bitrate": number(64_000),
                "user_limit": number(10_000), "rtc_region": .string("us-west"), "video_quality_mode": .null]))
        #expect(try GuildChannelCreate(name: "media", type: .value(.guildMedia),
            defaultReactionEmoji: .null, availableTags: .value([]), defaultSortOrder: .null,
            flags: .value(.init(rawValue: (1 << 15) | (1 << 21)))).jsonValue() != .null)
        #expect(try GuildChannelCreate(name: "category", type: .value(.guildCategory)).jsonValue() != .null)
        #expect(try GuildChannelCreate(name: "directory", type: .value(.guildDirectory)).jsonValue() != .null)
        #expect(try GuildChannelCreate(name: "announcement", type: .value(.guildAnnouncement),
            defaultThreadRateLimitPerUser: .value(0)).jsonValue() != .null)
        #expect(try GuildChannelCreate(name: String(repeating: "🦊", count: 100), type: .value(.guildVoice),
            bitrate: .value(8_000), userLimit: .value(0), rateLimitPerUser: .value(0)).jsonValue() != .null)
    }

    /// Direct/group DMs and threads cannot be created through the guild-channel endpoint.
    /// - Parameter type: One existing Discord channel kind with a different creation endpoint.
    @Test(arguments: [ChannelType.dm, .groupDM, .announcementThread, .publicThread, .privateThread])
    func invalidCreateChannelKinds(_ type: ChannelType) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(type)) }
    }

    /// Channel creation rejects type-incompatible fields, unsupported flags, duplicate overwrites and invalid limits.
    /// - Throws: Unexpected fixture construction fails the test; expected constructor failures are asserted locally.
    @Test func invalidCreateChannelSettings() throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: String(repeating: "x", count: 101)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", topic: .value(String(repeating: "x", count: 1_025))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), topic: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", bitrate: .value(8_000)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), bitrate: .value(7_999)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), bitrate: .value(384_001)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildStageVoice), bitrate: .value(64_001)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), userLimit: .value(100)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildStageVoice), userLimit: .value(10_001)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), userLimit: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", rateLimitPerUser: .value(21_601)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", rateLimitPerUser: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", defaultAutoArchiveDuration: .value(0)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", defaultThreadRateLimitPerUser: .value(21_601)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildVoice), rtcRegion: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildCategory), parentID: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildMedia), nsfw: .value(true)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildMedia), defaultForumLayout: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", flags: .value(.init(rawValue: .max))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", nsfw: .value(true), flags: .value(.isSpoilerChannel)) }
        let overwrite = try ChannelPermissionOverwrite(id: .init(rawValue: 1), type: .role)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", permissionOverwrites: .value([overwrite, overwrite])) }
        let tag = try ChannelForumTagRequest(id: .init(rawValue: 1), name: "tag")
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildForum), availableTags: .value([tag, tag])) }
        let newTag = try ChannelForumTagRequest(name: "tag")
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", type: .value(.guildForum), availableTags: .value(Array(repeating: newTag, count: 21))) }
        let overwrites = try (0..<101).map { try ChannelPermissionOverwrite(id: .init(rawValue: UInt64($0)), type: .role) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "x", permissionOverwrites: .value(overwrites)) }
    }

    /// Partial ordering entries preserve nulls and exact signed numeric extremes for channel and role endpoints.
    /// - Throws: Unexpected request/number validation fails the test.
    @Test func orderingEntries() throws {
        let channel = try GuildChannelPosition(id: .init(rawValue: .max), position: .value(Int.min), lockPermissions: .value(false),
            parentID: .null, flags: .value(.requireTag))
        #expect(channel.id.rawValue == .max)
        #expect(channel.parentID == .null)
        #expect(channel.jsonValue() == .object(["id": .string("18446744073709551615"), "position": number(Int.min),
            "lock_permissions": .bool(false), "parent_id": .null, "flags": number(16)]))
        #expect(try GuildChannelPosition(id: .init(rawValue: 0)).jsonValue() == .object(["id": .string("0")]))
        #expect(try GuildChannelPosition(id: .init(rawValue: 1), position: .null, lockPermissions: .null,
            parentID: .value(.init(rawValue: .max)), flags: .null).jsonValue() == .object(["id": .string("1"),
                "position": .null, "lock_permissions": .null, "parent_id": .string("18446744073709551615"), "flags": .null]))
        let role = try GuildRolePosition(id: .init(rawValue: .max), position: .value(Int.max))
        #expect(role.id.rawValue == .max)
        #expect(role.jsonValue() == .object(["id": .string("18446744073709551615"), "position": number(Int.max)]))
        #expect(try GuildRolePosition(id: .init(rawValue: 0)).jsonValue() == .object(["id": .string("0")]))
        #expect(try GuildRolePosition(id: .init(rawValue: 1), position: .null).jsonValue() == .object(["id": .string("1"), "position": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelPosition(id: .init(rawValue: 1), flags: .value(.init(rawValue: .max))) }
    }

    /// Member-add stores a typed credential safely and exposes it only during explicit outgoing serialization.
    /// - Throws: Unexpected token/request/fixture validation fails the test.
    @Test func memberAddCredentialAndFields() throws {
        let secret = "test-only-oauth-token"
        let request = try GuildMemberAdd(accessToken: secret, nick: .value("private nickname"),
            roles: .value([.init(rawValue: .max), .init(rawValue: 0)]), mute: .value(false), deaf: .value(true))
        #expect(request.jsonValue() == .object(["access_token": .string(secret), "nick": .string("private nickname"),
            "roles": .array([.string("18446744073709551615"), .string("0")]), "mute": .bool(false), "deaf": .bool(true)]))
        #expect(try GuildMemberAdd(accessToken: BearerToken(secret)).jsonValue() == .object(["access_token": .string(secret)]))
        #expect(try GuildMemberAdd(accessToken: secret, nick: .value(""), roles: .value([])).jsonValue() ==
            .object(["access_token": .string(secret), "nick": .string(""), "roles": .array([])]))
        #expect(!String(describing: request).contains(secret))
        #expect(!String(reflecting: request).contains(secret))
        #expect(!String(describing: request).contains("private nickname"))
        #expect(!String(describing: Mirror(reflecting: request).children.map(\.value)).contains(secret))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, nick: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, roles: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, mute: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, deaf: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, roles: .value([.init(rawValue: 1), .init(rawValue: 1)])) }
        #expect(throws: (any Error).self) { try GuildMemberAdd(accessToken: "invalid token") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberAdd(accessToken: secret, nick: .value(String(repeating: "x", count: 33))) }
    }

    /// Member patches preserve all nullable fields, writable flags and exact timeout spellings with a fixed clock.
    /// - Throws: Unexpected timestamp/request/fixture validation fails the test.
    @Test func memberModifyAndCurrentProfile() throws {
        let now = try timestamp("2026-10-16T00:00:00Z")
        let deadline = try timestamp("2026-11-13T01:00:00+01:00")
        #expect(try GuildMemberModify(nick: .value(String(repeating: "🦊", count: 32)), roles: .value([.init(rawValue: .max)]),
            mute: .value(true), deaf: .value(false), channelID: .value(.init(rawValue: .max)),
            communicationDisabledUntil: .value(deadline), flags: .value(.init(rawValue: 4)), referenceTime: now.date).jsonValue() ==
            .object(["nick": .string(String(repeating: "🦊", count: 32)), "roles": .array([.string("18446744073709551615")]),
                "mute": .bool(true), "deaf": .bool(false), "channel_id": .string("18446744073709551615"),
                "communication_disabled_until": .string(deadline.rawValue), "flags": number(4)]))
        #expect(try GuildMemberModify(nick: .null, roles: .null, mute: .null, deaf: .null, channelID: .null,
            communicationDisabledUntil: .null, flags: .null).jsonValue() == .object(["nick": .null, "roles": .null,
                "mute": .null, "deaf": .null, "channel_id": .null, "communication_disabled_until": .null, "flags": .null]))
        #expect(try GuildCurrentMemberModify(nick: .value("private nickname"), banner: .value("YQ=="),
            avatar: .value("data:image/png;base64,YQ=="), bio: .value(String(repeating: "b", count: 300))).jsonValue() ==
            .object(["nick": .string("private nickname"), "banner": .string("YQ=="),
                "avatar": .string("data:image/png;base64,YQ=="), "bio": .string(String(repeating: "b", count: 300))]))
        #expect(try GuildCurrentMemberModify(nick: .null, banner: .null, avatar: .null, bio: .null).jsonValue() ==
            .object(["nick": .null, "banner": .null, "avatar": .null, "bio": .null]))
        #expect(try GuildCurrentUserNickModify(nick: .value("")).jsonValue() == .object(["nick": .string("")]))
        #expect(try GuildCurrentUserNickModify(nick: .null).jsonValue() == .object(["nick": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberModify(nick: .value(String(repeating: "x", count: 33))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildCurrentMemberModify(nick: .value(String(repeating: "x", count: 33))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildCurrentUserNickModify(nick: .value(String(repeating: "x", count: 33))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildCurrentMemberModify(bio: .value(String(repeating: "x", count: 301))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberModify(roles: .value([.init(rawValue: 1), .init(rawValue: 1)])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberModify(flags: .value(.init(rawValue: 1))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberModify(flags: .value(.init(rawValue: .max))) }
        #expect(try GuildMemberModify(roles: .value([]), flags: .value(.init(rawValue: 0))).jsonValue() ==
            .object(["roles": .array([]), "flags": number(0)]))
    }

    /// Timeout/incident boundaries use an injected clock, preserve fractional spelling and reject stale or oversized windows.
    /// - Throws: Unexpected timestamp/request/fixture validation fails the test.
    @Test func deadlineBoundsAndIncidentActions() throws {
        let now = try timestamp("2026-10-16T00:00:00.123456789Z")
        let incidentMaximum = try timestamp("2026-10-17T00:00:00.123456789Z")
        let timeoutMaximum = try timestamp("2026-11-13T00:00:00.123456789Z")
        #expect(try GuildIncidentActionsModify(invitesDisabledUntil: .value(now), dmsDisabledUntil: .value(incidentMaximum),
            referenceTime: now.date).jsonValue() == .object(["invites_disabled_until": .string(now.rawValue),
                "dms_disabled_until": .string(incidentMaximum.rawValue)]))
        #expect(try GuildIncidentActionsModify(invitesDisabledUntil: .null, dmsDisabledUntil: .null).jsonValue() ==
            .object(["invites_disabled_until": .null, "dms_disabled_until": .null]))
        #expect(try GuildMemberModify(communicationDisabledUntil: .value(timeoutMaximum), referenceTime: now.date).jsonValue() ==
            .object(["communication_disabled_until": .string(timeoutMaximum.rawValue)]))
        let past = try timestamp("2026-10-15T23:59:59Z")
        let overIncident = try timestamp("2026-10-17T00:00:01Z")
        let overTimeout = try timestamp("2026-11-13T00:00:01Z")
        for invalid in [past, overIncident] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildIncidentActionsModify(invitesDisabledUntil: .value(invalid), referenceTime: now.date) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildIncidentActionsModify(dmsDisabledUntil: .value(invalid), referenceTime: now.date) }
        }
        for invalid in [past, overTimeout] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildMemberModify(communicationDisabledUntil: .value(invalid), referenceTime: now.date) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildIncidentActionsModify(invitesDisabledUntil: .value(now), referenceTime: Date(timeIntervalSince1970: .infinity))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildMemberModify(communicationDisabledUntil: .value(now), referenceTime: Date(timeIntervalSince1970: .nan))
        }
    }

    /// Single/bulk bans validate explicit request size, exact IDs and second/day deletion boundaries.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func banPayloads() throws {
        #expect(try GuildBanCreate(deleteMessageSeconds: .value(0)).jsonValue() == .object(["delete_message_seconds": number(0)]))
        #expect(try GuildBanCreate(deleteMessageSeconds: .value(604_800)).jsonValue() == .object(["delete_message_seconds": number(604_800)]))
        #expect(try GuildBanCreate(deleteMessageDays: .value(7)).jsonValue() == .object(["delete_message_days": number(7)]))
        #expect(try GuildBanCreate(deleteMessageDays: .value(0)).jsonValue() == .object(["delete_message_days": number(0)]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageSeconds: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageDays: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageSeconds: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageSeconds: .value(604_801)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageDays: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageDays: .value(8)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBanCreate(deleteMessageSeconds: .value(0), deleteMessageDays: .value(0)) }
        let users: [UserID] = [.init(rawValue: .max), .init(rawValue: 0)]
        let bulk = try GuildBulkBan(userIDs: users, deleteMessageSeconds: .value(604_800))
        #expect(bulk.userIDs == users)
        #expect(bulk.jsonValue() == .object(["user_ids": .array([.string("18446744073709551615"), .string("0")]), "delete_message_seconds": number(604_800)]))
        #expect(try GuildBulkBan(userIDs: [.init(rawValue: 1)]).jsonValue() == .object(["user_ids": .array([.string("1")])]))
        #expect(try GuildBulkBan(userIDs: (0..<200).map { .init(rawValue: UInt64($0)) }).userIDs.count == 200)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: (0..<201).map { .init(rawValue: UInt64($0)) }) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: [.init(rawValue: 1), .init(rawValue: 1)]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: users, deleteMessageSeconds: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: users, deleteMessageSeconds: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildBulkBan(userIDs: users, deleteMessageSeconds: .value(604_801)) }
    }

    /// Modern RGB colors encode nullable gradients and enforce Discord's fixed holographic triple.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func roleColors() throws {
        #expect(try GuildRoleColorsRequest(primaryColor: 0).jsonValue() == .object(["primary_color": number(0), "secondary_color": .null, "tertiary_color": .null]))
        #expect(try GuildRoleColorsRequest(primaryColor: 0xFF_FFFF, secondaryColor: 0).jsonValue() ==
            .object(["primary_color": number(0xFF_FFFF), "secondary_color": number(0), "tertiary_color": .null]))
        #expect(try GuildRoleColorsRequest(primaryColor: 11_127_295, secondaryColor: 16_759_788, tertiaryColor: 16_761_760).jsonValue() ==
            .object(["primary_color": number(11_127_295), "secondary_color": number(16_759_788), "tertiary_color": number(16_761_760)]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: -1) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0x100_0000) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0, secondaryColor: -1) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0, secondaryColor: 0x100_0000) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0, tertiaryColor: -1) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0, tertiaryColor: 0x100_0000) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 0, secondaryColor: 1, tertiaryColor: 2) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 11_127_295, tertiaryColor: 16_761_760) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleColorsRequest(primaryColor: 11_127_295, secondaryColor: 16_759_788, tertiaryColor: 1) }
    }

    /// Role create/modify preserve arbitrary-width decimal permissions and their distinct nullable contracts.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func rolePayloads() throws {
        let decimal = String(repeating: "9", count: 300)
        let colors = try GuildRoleColorsRequest(primaryColor: 12, secondaryColor: 34)
        let create = try GuildRoleCreate(name: .value(String(repeating: "🦊", count: 100)), permissions: .value(decimal),
            colors: .value(colors), hoist: .value(true), icon: .value("YQ=="), unicodeEmoji: .null, mentionable: .value(false))
        #expect(create.jsonValue() == .object(["name": .string(String(repeating: "🦊", count: 100)), "permissions": .string(decimal),
            "colors": colors.jsonValue(), "hoist": .bool(true), "icon": .string("YQ=="), "unicode_emoji": .null, "mentionable": .bool(false)]))
        #expect(try GuildRoleModify(name: .value("role"), permissions: .value("00018446744073709551616"), color: .value(0xFF_FFFF),
            hoist: .value(false), icon: .null, unicodeEmoji: .value("🦊"), mentionable: .value(true)).jsonValue() ==
            .object(["name": .string("role"), "permissions": .string("00018446744073709551616"), "color": number(0xFF_FFFF),
                "hoist": .bool(false), "icon": .null, "unicode_emoji": .string("🦊"), "mentionable": .bool(true)]))
        #expect(try GuildRoleModify(name: .null, permissions: .null, color: .null, colors: .null, hoist: .null,
            icon: .null, unicodeEmoji: .null, mentionable: .null).jsonValue() == .object(["name": .null,
                "permissions": .null, "color": .null, "colors": .null, "hoist": .null, "icon": .null,
                "unicode_emoji": .null, "mentionable": .null]))
        #expect(try GuildRoleCreate(color: .value(0), unicodeEmoji: .value("🦊")).jsonValue() ==
            .object(["color": number(0), "unicode_emoji": .string("🦊")]))
        #expect(try GuildRoleModify(colors: .value(colors), icon: .value("data:image/png;base64,YQ==")).jsonValue() ==
            .object(["colors": colors.jsonValue(), "icon": .string("data:image/png;base64,YQ==")]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(permissions: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(color: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(colors: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(hoist: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(mentionable: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(name: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(name: .value(String(repeating: "x", count: 101))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(color: .value(-1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(color: .value(0x100_0000)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(color: .value(1), colors: .value(colors)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(color: .value(1), colors: .value(colors)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(icon: .value("YQ=="), unicodeEmoji: .value("🦊")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(icon: .value("YQ=="), unicodeEmoji: .value("🦊")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(unicodeEmoji: .value("")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(unicodeEmoji: .value(String(repeating: "e", count: 101))) }
        #expect(try GuildRoleModify(unicodeEmoji: .value(String(repeating: "e", count: 100))).jsonValue() != .null)
    }

    /// Decimal grammar rejects signs, spacing, exponents, non-ASCII digits and invalid content in both role operations.
    /// - Parameter decimal: One malformed permissions string, never echoed by a production validation error.
    @Test(arguments: ["", "-1", "+1", " 1", "1 ", "1.0", "1e2", "１２", "١", "1\n", "private-content"])
    func malformedRolePermissions(_ decimal: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleCreate(permissions: .value(decimal)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildRoleModify(permissions: .value(decimal)) }
    }

    /// Prune and widget operations preserve explicit false/empty/null settings and reject invalid bounds.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func pruneAndWidgetPayloads() throws {
        #expect(try GuildPrune(days: .value(30), computePruneCount: .value(false),
            includeRoles: .value([.init(rawValue: .max), .init(rawValue: 0)]), reason: .value("private audit reason")).jsonValue() ==
            .object(["days": number(30), "compute_prune_count": .bool(false), "include_roles": .array([
                .string("18446744073709551615"), .string("0")]), "reason": .string("private audit reason")]))
        #expect(try GuildPrune(days: .value(1), computePruneCount: .value(true), includeRoles: .value([]), reason: .value("")).jsonValue() ==
            .object(["days": number(1), "compute_prune_count": .bool(true), "include_roles": .array([]), "reason": .string("")]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(days: .value(0)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(days: .value(31)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(days: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(computePruneCount: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(includeRoles: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(reason: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildPrune(includeRoles: .value([.init(rawValue: 1), .init(rawValue: 1)])) }
        #expect(try GuildWidgetModify(enabled: .value(false), channelID: .null).jsonValue() ==
            .object(["enabled": .bool(false), "channel_id": .null]))
        #expect(try GuildWidgetModify(enabled: .value(true), channelID: .value(.init(rawValue: .max))).jsonValue() ==
            .object(["enabled": .bool(true), "channel_id": .string("18446744073709551615")]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWidgetModify(enabled: .null) }
    }

    /// Welcome channels preserve custom emoji ID/name pairs, nullable removals and the five-channel bound.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func welcomePayloads() throws {
        let channel = try GuildWelcomeChannelRequest(channelID: .init(rawValue: .max),
            description: String(repeating: "🦊", count: 50), emojiID: .value(.init(rawValue: .max)), emojiName: .value("custom"))
        #expect(channel.channelID.rawValue == .max)
        #expect(channel.jsonValue() == .object(["channel_id": .string("18446744073709551615"),
            "description": .string(String(repeating: "🦊", count: 50)), "emoji_id": .string("18446744073709551615"), "emoji_name": .string("custom")]))
        #expect(try GuildWelcomeChannelRequest(channelID: .init(rawValue: 1), description: "x").jsonValue() ==
            .object(["channel_id": .string("1"), "description": .string("x")]))
        #expect(try GuildWelcomeChannelRequest(channelID: .init(rawValue: 1), description: "x", emojiID: .null,
            emojiName: .null).jsonValue() == .object(["channel_id": .string("1"), "description": .string("x"), "emoji_id": .null, "emoji_name": .null]))
        #expect(try GuildWelcomeScreenModify(enabled: .value(false), welcomeChannels: .value([channel]),
            description: .value(String(repeating: "d", count: 140))).jsonValue() == .object(["enabled": .bool(false),
                "welcome_channels": .array([channel.jsonValue()]), "description": .string(String(repeating: "d", count: 140))]))
        #expect(try GuildWelcomeScreenModify(enabled: .null, welcomeChannels: .null, description: .null).jsonValue() ==
            .object(["enabled": .null, "welcome_channels": .null, "description": .null]))
        #expect(try GuildWelcomeScreenModify(enabled: .value(true), welcomeChannels: .value([]), description: .value("")).jsonValue() != .null)
        let five = try (0..<5).map { try GuildWelcomeChannelRequest(channelID: .init(rawValue: UInt64($0)), description: "x") }
        #expect(try GuildWelcomeScreenModify(welcomeChannels: .value(five)).jsonValue() == .object(["welcome_channels": .array(five.map { $0.jsonValue() })]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWelcomeChannelRequest(channelID: .init(rawValue: 1), description: "") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWelcomeChannelRequest(channelID: .init(rawValue: 1), description: String(repeating: "d", count: 51)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWelcomeScreenModify(welcomeChannels: .value([channel, channel])) }
        let six = try (0..<6).map { try GuildWelcomeChannelRequest(channelID: .init(rawValue: UInt64($0)), description: "x") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWelcomeScreenModify(welcomeChannels: .value(six)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildWelcomeScreenModify(description: .value(String(repeating: "d", count: 141))) }
    }

    /// Onboarding nested requests cover every wire key, flattened emoji fields, nullable options and exact IDs.
    /// - Throws: Unexpected request/fixture validation fails the test.
    @Test func onboardingPayloads() throws {
        let option = try GuildOnboardingOptionRequest(title: String(repeating: "🦊", count: 50), id: .value(.init(rawValue: .max)),
            description: .value(String(repeating: "d", count: 100)), channelIDs: .value([.init(rawValue: .max)]),
            roleIDs: .value([.init(rawValue: .max)]), emojiID: .value(.init(rawValue: .max)), emojiName: .value("custom"), emojiAnimated: .value(true))
        #expect(option.id == .value(.init(rawValue: .max)))
        #expect(option.jsonValue() == .object(["title": .string(String(repeating: "🦊", count: 50)), "id": .string("18446744073709551615"),
            "description": .string(String(repeating: "d", count: 100)), "channel_ids": .array([.string("18446744073709551615")]),
            "role_ids": .array([.string("18446744073709551615")]), "emoji_id": .string("18446744073709551615"),
            "emoji_name": .string("custom"), "emoji_animated": .bool(true)]))
        let prompt = try GuildOnboardingPromptRequest(id: .init(rawValue: .max), title: String(repeating: "p", count: 100),
            options: [option], type: .value(.dropdown), singleSelect: .value(true), required: .value(false), inOnboarding: .value(true))
        #expect(prompt.id.rawValue == .max)
        #expect(prompt.jsonValue() == .object(["id": .string("18446744073709551615"), "title": .string(String(repeating: "p", count: 100)),
            "options": .array([option.jsonValue()]), "type": number(1), "single_select": .bool(true), "required": .bool(false), "in_onboarding": .bool(true)]))
        #expect(try GuildOnboardingModify(prompts: .value([prompt]), defaultChannelIDs: .value([.init(rawValue: .max)]),
            enabled: .value(false), mode: .value(.advanced)).jsonValue() == .object(["prompts": .array([prompt.jsonValue()]),
                "default_channel_ids": .array([.string("18446744073709551615")]), "enabled": .bool(false), "mode": number(1)]))
        let nullableOption = try GuildOnboardingOptionRequest(title: "x", id: .null, description: .null,
            channelIDs: .null, roleIDs: .null, emojiID: .null, emojiName: .null, emojiAnimated: .null)
        #expect(nullableOption.jsonValue() == .object(["title": .string("x"), "id": .null, "description": .null,
            "channel_ids": .null, "role_ids": .null, "emoji_id": .null, "emoji_name": .null, "emoji_animated": .null]))
        #expect(try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: [nullableOption], type: .null,
            singleSelect: .null, required: .null, inOnboarding: .null).jsonValue() == .object(["id": .string("1"), "title": .string("p"),
                "options": .array([nullableOption.jsonValue()]), "type": .null, "single_select": .null, "required": .null, "in_onboarding": .null]))
        #expect(try GuildOnboardingModify(prompts: .null, defaultChannelIDs: .null, enabled: .null, mode: .null).jsonValue() ==
            .object(["prompts": .null, "default_channel_ids": .null, "enabled": .null, "mode": .null]))
        let minimal = try GuildOnboardingOptionRequest(title: "x")
        #expect(minimal.id == .absent)
        #expect(minimal.jsonValue() == .object(["title": .string("x")]))
        #expect(try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: [minimal]).jsonValue() ==
            .object(["id": .string("1"), "title": .string("p"), "options": .array([minimal.jsonValue()])]))
        #expect(try GuildOnboardingOptionRequest(title: "x", description: .value(""), channelIDs: .value([]), roleIDs: .value([]),
            emojiName: .value("🦊"), emojiAnimated: .value(false)).jsonValue() != .null)
        // Permission-dependent enabling constraints deliberately remain server checks when the prior state is unknown.
        #expect(try GuildOnboardingModify(enabled: .value(true), mode: .value(.default)).jsonValue() ==
            .object(["enabled": .bool(true), "mode": number(0)]))
    }

    /// Onboarding enforces each published collection/string bound and duplicate-ID rule without guessing permissions.
    /// - Throws: Unexpected fixture validation fails the test; expected failures are asserted locally.
    @Test func onboardingBoundsAndDuplicates() throws {
        let channels: [ChannelID] = (0..<501).map { .init(rawValue: UInt64($0)) }
        let roles: [RoleID] = (0..<51).map { .init(rawValue: UInt64($0)) }
        let option = try GuildOnboardingOptionRequest(title: "o", id: .value(.init(rawValue: 1)))
        let anonymous = try GuildOnboardingOptionRequest(title: "o")
        #expect(try GuildOnboardingOptionRequest(title: "o", channelIDs: .value(Array(channels.prefix(50))),
            roleIDs: .value(Array(roles.prefix(50))), emojiName: .value(String(repeating: "e", count: 100))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: String(repeating: "x", count: 51)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", description: .value(String(repeating: "d", count: 101))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", emojiName: .value(String(repeating: "e", count: 101))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", channelIDs: .value(Array(channels.prefix(51)))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", roleIDs: .value(roles)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", channelIDs: .value([channels[0], channels[0]])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingOptionRequest(title: "o", roleIDs: .value([roles[0], roles[0]])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "", options: [option]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: String(repeating: "p", count: 101), options: [option]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: [option, option]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: Array(repeating: anonymous, count: 51)) }
        #expect(try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: "p", options: Array(repeating: anonymous, count: 50)).jsonValue() != .null)
        let prompts = try (0..<16).map { try GuildOnboardingPromptRequest(id: .init(rawValue: UInt64($0)), title: "p", options: [anonymous]) }
        #expect(try GuildOnboardingModify(prompts: .value(Array(prompts.prefix(15))), defaultChannelIDs: .value(Array(channels.prefix(500)))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingModify(prompts: .value(prompts)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingModify(prompts: .value([prompts[0], prompts[0]])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingModify(defaultChannelIDs: .value(channels)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildOnboardingModify(defaultChannelIDs: .value([channels[0], channels[0]])) }
        #expect(try GuildOnboardingModify(prompts: .value([]), defaultChannelIDs: .value([])).jsonValue() ==
            .object(["prompts": .array([]), "default_channel_ids": .array([])]))
    }

    /// All newly introduced content-bearing request types redact descriptions, debug output and recursive reflection.
    /// - Throws: Unexpected constructor validation fails the test.
    @Test func contentRedactionAcrossRequests() throws {
        let secret = "private-content"
        let option = try GuildOnboardingOptionRequest(title: secret, description: .value(secret))
        let prompt = try GuildOnboardingPromptRequest(id: .init(rawValue: 1), title: secret, options: [option])
        let welcome = try GuildWelcomeChannelRequest(channelID: .init(rawValue: 1), description: secret)
        let requests: [any GuildRequestPayload] = try [GuildModify(name: .value(secret), description: .value(secret)),
            GuildChannelCreate(name: secret), GuildChannelPosition(id: .init(rawValue: 1)),
            GuildMemberAdd(accessToken: "test-only-token", nick: .value(secret)), GuildMemberModify(nick: .value(secret)),
            GuildCurrentMemberModify(nick: .value(secret), bio: .value(secret)), GuildCurrentUserNickModify(nick: .value(secret)),
            GuildBulkBan(userIDs: [.init(rawValue: 1)]), GuildRoleColorsRequest(primaryColor: 1),
            GuildRoleCreate(name: .value(secret)), GuildRoleModify(name: .value(secret)), GuildRolePosition(id: .init(rawValue: 1)),
            GuildPrune(reason: .value(secret)), GuildWelcomeScreenModify(welcomeChannels: .value([welcome]), description: .value(secret)),
            GuildOnboardingModify(prompts: .value([prompt])), option, prompt, welcome]
        for request in requests {
            #expect(!request.description.contains(secret))
            #expect(!request.debugDescription.contains(secret))
            #expect(Mirror(reflecting: request).children.first?.label == "redacted")
            #expect(Mirror(reflecting: request).children.first?.value as? Bool == true)
        }
    }

    /// Official preview-only image/search fields retain explicit nullable compatibility without exposing raw dictionaries.
    /// - Throws: Unexpected request construction or expected-value fixture validation fails the test.
    @Test func officialSchemaCompatibilityFields() throws {
        #expect(try GuildModify(homeHeader: .value("data:image/png;base64,YQ==")).jsonValue() ==
            .object(["home_header": .string("data:image/png;base64,YQ==")]))
        #expect(try GuildModify(homeHeader: .null).jsonValue() == .object(["home_header": .null]))
        #expect(GuildDefaultTagSetting.allCases.map(\.rawValue) == ["match_all", "match_some"])
        #expect(GuildDefaultTagSetting(rawValue: "future") == nil)
        for setting in GuildDefaultTagSetting.allCases {
            for type in [ChannelType.guildForum, .guildMedia] {
                #expect(try GuildChannelCreate(name: "forum", type: .value(type), defaultTagSetting: .value(setting)).jsonValue() ==
                    .object(["name": .string("forum"), "type": number(type.rawValue), "default_tag_setting": .string(setting.rawValue)]))
            }
        }
        #expect(try GuildChannelCreate(name: "forum", type: .value(.guildForum), defaultTagSetting: .null).jsonValue() ==
            .object(["name": .string("forum"), "type": number(15), "default_tag_setting": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "text", defaultTagSetting: .value(.matchSome)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildChannelCreate(name: "text", defaultTagSetting: .null) }
        let image = try GuildModify(homeHeader: .value("YQ=="))
        #expect(!String(reflecting: image).contains("YQ=="))
    }

    /// Published role/token/features/prune caps are enforced at both endpoints of each accepted collection bound.
    /// - Throws: Unexpected fixture/request validation fails the test; oversized input failures are asserted locally.
    @Test func publishedSupplementalRequestBounds() throws {
        let roles: [RoleID] = (0..<351).map { .init(rawValue: UInt64($0)) }
        let token = String(repeating: "t", count: 10_240)
        #expect(try GuildMemberAdd(accessToken: token, roles: .value(Array(roles.prefix(250)))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try GuildMemberAdd(accessToken: token + "t")
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try GuildMemberAdd(accessToken: token, roles: .value(Array(roles.prefix(251))))
        }
        #expect(try GuildMemberModify(roles: .value(Array(roles.prefix(350)))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try GuildMemberModify(roles: .value(roles)) }
        #expect(try GuildPrune(includeRoles: .value(Array(roles.prefix(100)))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try GuildPrune(includeRoles: .value(Array(roles.prefix(101)))) }
        let features = (0..<1_522).map { "FUTURE_" + String($0) }
        #expect(try GuildModify(features: .value(Array(features.prefix(1_521)))).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildModify(features: .value(features)) }
        let overwrites = try (0..<100).map { try ChannelPermissionOverwrite(id: .init(rawValue: UInt64($0)), type: .role) }
        #expect(try GuildChannelCreate(name: "x", permissionOverwrites: .value(overwrites)).jsonValue() != .null)
    }

    /// Extracts expected JSON objects without silently treating another JSON shape as an empty object.
    /// - Parameter value: The request serialization under test.
    /// - Returns: Object fields for exact key/value assertions.
    /// - Throws: A required-value failure if the request produced a nonobject representation.
    private func object(_ value: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let fields) = value else { Issue.record("Expected an object request body"); return try #require(nil as [String: JSONValue]?) }
        return fields
    }

    /// Creates exact numeric fixtures without losing signed/unsigned precision through floating-point conversion.
    /// - Parameter value: Any integral expected wire value.
    /// - Returns: Canonical JSON numeric fixture.
    /// Integral formatting is canonical JSON, so the forced parse is confined to deterministic test fixtures.
    private func number<Value: BinaryInteger>(_ value: Value) -> JSONValue {
        .number(try! JSONNumber(rawValue: String(value)))
    }

    /// Parses a fixed clock/deadline fixture using the same strict lossless timestamp profile as production models.
    /// - Parameter value: Complete ISO8601 timestamp literal with an explicit offset.
    /// - Returns: Deterministic timestamp preserving its exact spelling and precision.
    /// - Throws: Timestamp grammar/date errors for an invalid test fixture.
    private func timestamp(_ value: String) throws -> DiscordTimestamp { try .init(rawValue: value) }
}
