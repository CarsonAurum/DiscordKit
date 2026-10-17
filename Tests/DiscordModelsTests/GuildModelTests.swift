import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Deterministic schema fixtures covering every guild-owned response initializer and modeled field.
/// Related resource families remain partial and no live Discord connection or credential is used.
@Suite struct GuildModelTests {
    /// Both public bounded parsing and internal subtree projection preserve exact objects and redact diagnostics.
    /// - Parameter fixture: One independently valid minimal and fully populated guild-owned response shape.
    /// - Throws: Unexpected parser, schema or serialization failures fail the test.
    @Test(arguments: GuildModelFixture.all)
    fileprivate func exactTreesAndDiagnostics(fixture: GuildModelFixture) throws {
        for source in [fixture.minimal, fixture.populated] {
            let bytes = Data(source.utf8)
            let expected = try JSONValue.parse(bytes)
            let parsed = try fixture.parse(bytes, .default)
            let projected = try fixture.project(expected, .default)
            #expect(parsed.jsonValue() == expected)
            #expect(projected.rawFields == parsed.rawFields)
            #expect(try parsed.jsonValue().serialized() == expected.serialized())
            #expect(!parsed.description.contains("private-"))
            #expect(!parsed.debugDescription.contains("private-"))
            #expect(!String(reflecting: parsed).contains("private-"))
            #expect(parsed.customMirror.children.count == 1)
            #expect(Mirror(reflecting: parsed).children.count == 1)
        }
    }

    /// Every field rejects wrong shapes; nullable and optional contracts distinguish null, absence and values.
    /// Required nullable keys reject omission, and null-sentinel tags reject Boolean substitutions.
    /// - Parameter fixture: One schema with a valid fully populated baseline and explicit field contracts.
    /// - Throws: Fixture parsing/serialization failures fail the test; expected schema errors are asserted.
    @Test(arguments: GuildModelFixture.all)
    fileprivate func fieldPresenceAndMalformedValues(fixture: GuildModelFixture) throws {
        guard case .object(let original) = try JSONValue.parse(fixture.populated) else { Issue.record("Fixture root"); return }
        for field in fixture.fields {
            var missing = original
            missing[field.name] = nil
            let missingBytes = try JSONValue.object(missing).serialized()
            if field.optional {
                let parsed = try fixture.parse(missingBytes, .default)
                #expect(parsed.rawFields[field.name] == nil)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(missingBytes, .default) }
            }
            var null = original
            null[field.name] = .null
            let nullBytes = try JSONValue.object(null).serialized()
            if field.nullable {
                let parsed = try fixture.parse(nullBytes, .default)
                #expect(parsed.rawFields[field.name] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(nullBytes, .default) }
            }
            for invalid in field.invalid {
                var malformed = original
                malformed[field.name] = try JSONValue.parse(invalid)
                let bytes = try JSONValue.object(malformed).serialized()
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(bytes, .default) }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(.object(malformed), .default) }
            }
        }
    }

    /// All standalone initializers enforce whole-document parser limits, including unknown nested content.
    /// Scalar/array roots, malformed syntax and known nested schema failures are sanitized independently.
    /// - Parameter fixture: A complete response object retaining unknown deeply nested future data.
    /// - Throws: Unexpected fixture failures fail the test; expected bounds errors are asserted.
    @Test(arguments: GuildModelFixture.all)
    fileprivate func rootsSyntaxAndBounds(fixture: GuildModelFixture) throws {
        let bytes = Data(fixture.populated.utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try fixture.parse(bytes, JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try fixture.parse(bytes, JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try fixture.parse(bytes, JSONLimits(maximumNodes: 1))
        }
        #expect(throws: JSONValueError.self) { try fixture.parse(Data("{".utf8), .default) }
        for invalid in ["[]", "null", "true", "1", #""private-root""#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(Data(invalid.utf8), .default) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(JSONValue.parse(invalid), .default) }
        }
    }

    /// Public typed fields expose the complete populated schema, retaining unknown enums and high snowflakes.
    /// Nested fields share exact bounded JSON rather than converting unknown values through Foundation.
    /// - Throws: Unexpected parsing, timestamp or field extraction failures fail the test.
    @Test func typedPropertiesAndFutureValues() throws {
        do {
            let model = try Guild(data: Data(#"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","icon_hash":"private-icon_hash","splash":"private-splash","discovery_splash":"private-discovery_splash","owner":true,"owner_id":"18446744073709551615","permissions":"184467440737095516161844674407370955161","region":"private-region","afk_channel_id":"18446744073709551615","afk_timeout":1,"widget_enabled":true,"widget_channel_id":"18446744073709551615","verification_level":999,"default_message_notifications":999,"explicit_content_filter":999,"roles":[{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"icon":"private-icon","unicode_emoji":"private-unicode_emoji","position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"tags":{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null},"flags":9223372036854775809}],"emojis":[{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}}],"features":["FUTURE_VARIANT"],"mfa_level":999,"application_id":"18446744073709551615","system_channel_id":"18446744073709551615","system_channel_flags":9223372036854775809,"rules_channel_id":"18446744073709551615","max_presences":1,"max_members":1,"vanity_url_code":"private-vanity_url_code","description":"private-description","banner":"private-banner","premium_tier":999,"premium_subscription_count":1,"preferred_locale":"private-preferred_locale","public_updates_channel_id":"18446744073709551615","max_video_channel_users":1,"max_stage_video_channel_users":1,"approximate_member_count":1,"approximate_presence_count":1,"welcome_screen":{"description":"private-description","welcome_channels":[{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name"}]},"nsfw_level":999,"stickers":[{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}}],"premium_progress_bar_enabled":true,"safety_alerts_channel_id":"18446744073709551615","incidents_data":{"invites_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dms_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dm_spam_detected_at":"2026-10-16T12:34:56.123456789+00:00","raid_detected_at":"2026-10-16T12:34:56.123456789+00:00"},"home_header":"private-home_header","nsfw":true,"premium_progress_bar_enabled_user_updated_at":"2026-10-16T12:34:56.123456789+00:00","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name == "private-name")
            #expect(model.icon.guildModelNullableValue == "private-icon")
            #expect(model.iconHash.guildModelValue == "private-icon_hash")
            #expect(model.splash.guildModelNullableValue == "private-splash")
            #expect(model.discoverySplash.guildModelValue == "private-discovery_splash")
            #expect(model.owner.guildModelValue == true)
            #expect(model.ownerID.rawValue == UInt64.max)
            #expect(model.permissions.guildModelValue == "184467440737095516161844674407370955161")
            #expect(model.region.guildModelValue == "private-region")
            #expect(model.afkChannelID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.afkTimeout == 1)
            #expect(model.widgetEnabled.guildModelValue == true)
            #expect(model.widgetChannelID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.verificationLevel.rawValue == 999 && model.verificationLevel.knownValue == nil)
            #expect(model.defaultMessageNotifications.rawValue == 999 && model.defaultMessageNotifications.knownValue == nil)
            #expect(model.explicitContentFilter.rawValue == 999 && model.explicitContentFilter.knownValue == nil)
            #expect(model.roles.count == 1)
            #expect(model.emojis.count == 1)
            #expect(model.features.first?.rawValue == "FUTURE_VARIANT" && model.features.first?.knownValue == nil)
            #expect(model.mfaLevel.rawValue == 999 && model.mfaLevel.knownValue == nil)
            #expect(model.applicationID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.systemChannelID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.systemChannelFlags == 9223372036854775809)
            #expect(model.rulesChannelID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.maxPresences.guildModelValue == 1)
            #expect(model.maxMembers.guildModelValue == 1)
            #expect(model.vanityURLCode.guildModelNullableValue == "private-vanity_url_code")
            #expect(model.guildDescription.guildModelNullableValue == "private-description")
            #expect(model.banner.guildModelNullableValue == "private-banner")
            #expect(model.premiumTier.rawValue == 999 && model.premiumTier.knownValue == nil)
            #expect(model.premiumSubscriptionCount.guildModelValue == 1)
            #expect(model.preferredLocale == "private-preferred_locale")
            #expect(model.publicUpdatesChannelID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.maxVideoChannelUsers.guildModelValue == 1)
            #expect(model.maxStageVideoChannelUsers.guildModelValue == 1)
            #expect(model.approximateMemberCount.guildModelValue == 1)
            #expect(model.approximatePresenceCount.guildModelValue == 1)
            #expect(model.welcomeScreen.guildModelValue?.jsonValue() == model.rawFields["welcome_screen"])
            #expect(model.nsfwLevel.rawValue == 999 && model.nsfwLevel.knownValue == nil)
            #expect(model.stickers.guildModelValue?.count == 1)
            #expect(model.premiumProgressBarEnabled == true)
            #expect(model.safetyAlertsChannelID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.incidentsData.guildModelNullableValue?.jsonValue() == model.rawFields["incidents_data"])
            #expect(model.homeHeader.guildModelValue == "private-home_header")
            #expect(model.nsfw.guildModelValue == true)
            #expect(model.premiumProgressBarEnabledUserUpdatedAt.guildModelValue?.nanosecond == 123_456_789)
        }
        do {
            let model = try GuildUnavailable(data: Data(#"{"id":"18446744073709551615","unavailable":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.unavailable == true)
        }
        do {
            let model = try GuildPreview(data: Data(#"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","splash":"private-splash","discovery_splash":"private-discovery_splash","emojis":[{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}}],"features":["FUTURE_VARIANT"],"approximate_member_count":1,"approximate_presence_count":1,"description":"private-description","stickers":[{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}}],"home_header":"private-home_header","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name == "private-name")
            #expect(model.icon.guildModelNullableValue == "private-icon")
            #expect(model.splash.guildModelNullableValue == "private-splash")
            #expect(model.discoverySplash.guildModelNullableValue == "private-discovery_splash")
            #expect(model.emojis.count == 1)
            #expect(model.features.first?.rawValue == "FUTURE_VARIANT" && model.features.first?.knownValue == nil)
            #expect(model.approximateMemberCount == 1)
            #expect(model.approximatePresenceCount == 1)
            #expect(model.guildDescription.guildModelNullableValue == "private-description")
            #expect(model.stickers.count == 1)
            #expect(model.homeHeader.guildModelValue == "private-home_header")
        }
        do {
            let model = try GuildMember(data: Data(#"{"user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789+00:00","premium_since":"2026-10-16T12:34:56.123456789+00:00","deaf":true,"mute":true,"flags":9223372036854775809,"pending":true,"permissions":"184467440737095516161844674407370955161","communication_disabled_until":"2026-10-16T12:34:56.123456789+00:00","avatar_decoration_data":{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}},"collectibles":{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.user.guildModelValue?.jsonValue() == model.rawFields["user"])
            #expect(model.nick.guildModelValue == "private-nick")
            #expect(model.avatar.guildModelValue == "private-avatar")
            #expect(model.banner.guildModelValue == "private-banner")
            #expect(model.roles.first?.rawValue == UInt64.max)
            #expect(model.joinedAt.guildModelNullableValue?.nanosecond == 123_456_789)
            #expect(model.premiumSince.guildModelValue?.nanosecond == 123_456_789)
            #expect(model.deaf == true)
            #expect(model.mute == true)
            #expect(model.flags == 9223372036854775809)
            #expect(model.pending.guildModelValue == true)
            #expect(model.permissions.guildModelValue == "184467440737095516161844674407370955161")
            #expect(model.communicationDisabledUntil.guildModelValue?.nanosecond == 123_456_789)
            #expect(model.avatarDecorationData.guildModelValue?.jsonValue() == model.rawFields["avatar_decoration_data"])
            #expect(model.collectibles.guildModelValue?.jsonValue() == model.rawFields["collectibles"])
        }
        do {
            let model = try GuildRole(data: Data(#"{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"icon":"private-icon","unicode_emoji":"private-unicode_emoji","position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"tags":{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null},"flags":9223372036854775809,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name == "private-name")
            #expect(model.color == 1)
            #expect(model.colors.jsonValue() == model.rawFields["colors"])
            #expect(model.hoist == true)
            #expect(model.icon.guildModelValue == "private-icon")
            #expect(model.unicodeEmoji.guildModelValue == "private-unicode_emoji")
            #expect(model.position == 1)
            #expect(model.permissions == "184467440737095516161844674407370955161")
            #expect(model.managed == true)
            #expect(model.mentionable == true)
            #expect(model.tags.guildModelValue?.jsonValue() == model.rawFields["tags"])
            #expect(model.flags == 9223372036854775809)
        }
        do {
            let model = try GuildRoleColors(data: Data(#"{"primary_color":1,"secondary_color":1,"tertiary_color":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.primaryColor == 1)
            #expect(model.secondaryColor.guildModelNullableValue == 1)
            #expect(model.tertiaryColor.guildModelNullableValue == 1)
        }
        do {
            let model = try GuildRoleTags(data: Data(#"{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.botID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.integrationID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.premiumSubscriber == .null)
            #expect(model.subscriptionListingID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.availableForPurchase == .null)
            #expect(model.guildConnections == .null)
        }
        do {
            let model = try GuildBan(data: Data(#"{"reason":"private-reason","user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.reason.guildModelNullableValue == "private-reason")
            #expect(model.user.jsonValue() == model.rawFields["user"])
        }
        do {
            let model = try GuildBulkBanResult(data: Data(#"{"banned_users":["18446744073709551615"],"failed_users":["18446744073709551615"],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.bannedUsers.first?.rawValue == UInt64.max)
            #expect(model.failedUsers.first?.rawValue == UInt64.max)
        }
        do {
            let model = try GuildNickname(data: Data(#"{"nick":"private-nick","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.nick.guildModelNullableValue == "private-nick")
        }
        do {
            let model = try GuildPruneCount(data: Data(#"{"pruned":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.pruned.guildModelNullableValue == 1)
        }
        do {
            let model = try GuildVoiceRegion(data: Data(#"{"id":"private-id","name":"private-name","optimal":true,"deprecated":true,"custom":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id == "private-id")
            #expect(model.name == "private-name")
            #expect(model.optimal == true)
            #expect(model.deprecated == true)
            #expect(model.custom == true)
        }
        do {
            let model = try GuildIntegration(data: Data(#"{"id":"private-id","name":"private-name","type":"FUTURE_VARIANT","enabled":true,"syncing":true,"role_id":"18446744073709551615","enable_emoticons":true,"expire_behavior":999,"expire_grace_period":1,"user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"account":{"id":"private-id","name":"private-name"},"synced_at":"2026-10-16T12:34:56.123456789+00:00","subscriber_count":1,"revoked":true,"application":{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","bot":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"type":999,"cover_image":"private-cover_image","primary_sku_id":"18446744073709551615","flags":9223372036854775809,"flags_new":"private-flags_new"},"scopes":["private-scopes"],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id == "private-id")
            #expect(model.name.guildModelNullableValue == "private-name")
            #expect(model.type.rawValue == "FUTURE_VARIANT" && model.type.knownValue == nil)
            #expect(model.enabled == true)
            #expect(model.syncing.guildModelValue == true)
            #expect(model.roleID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.enableEmoticons.guildModelValue == true)
            #expect(model.expireBehavior.guildModelValue?.rawValue == 999 && model.expireBehavior.guildModelValue?.knownValue == nil)
            #expect(model.expireGracePeriod.guildModelValue == 1)
            #expect(model.user.guildModelValue?.jsonValue() == model.rawFields["user"])
            #expect(model.account.jsonValue() == model.rawFields["account"])
            #expect(model.syncedAt.guildModelValue?.nanosecond == 123_456_789)
            #expect(model.subscriberCount.guildModelValue == 1)
            #expect(model.revoked.guildModelValue == true)
            #expect(model.application.guildModelValue?.jsonValue() == model.rawFields["application"])
            #expect(model.scopes.guildModelValue?.first == "private-scopes")
        }
        do {
            let model = try GuildIntegrationAccount(data: Data(#"{"id":"private-id","name":"private-name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id == "private-id")
            #expect(model.name == "private-name")
        }
        do {
            let model = try GuildIntegrationApplication(data: Data(#"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","bot":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"type":999,"cover_image":"private-cover_image","primary_sku_id":"18446744073709551615","flags":9223372036854775809,"flags_new":"private-flags_new","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name == "private-name")
            #expect(model.icon.guildModelNullableValue == "private-icon")
            #expect(model.applicationDescription == "private-description")
            #expect(model.bot.guildModelValue?.jsonValue() == model.rawFields["bot"])
            #expect(model.type.guildModelValue?.rawValue == 999 && model.type.guildModelValue?.knownValue == nil)
            #expect(model.coverImage.guildModelValue == "private-cover_image")
            #expect(model.primarySKUID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.flags.guildModelValue == 9223372036854775809)
            #expect(model.flagsNew.guildModelValue == "private-flags_new")
        }
        do {
            let model = try GuildWidgetSettings(data: Data(#"{"enabled":true,"channel_id":"18446744073709551615","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.enabled == true)
            #expect(model.channelID.guildModelNullableValue?.rawValue == UInt64.max)
        }
        do {
            let model = try GuildWidget(data: Data(#"{"id":"18446744073709551615","name":"private-name","instant_invite":"private-instant_invite","channels":[{"id":"18446744073709551615","name":"private-name","position":1}],"members":[{"id":"private-id","username":"private-username","discriminator":"private-discriminator","avatar":"private-avatar","status":"private-status","avatar_url":"private-avatar_url","deaf":true,"mute":true,"self_deaf":true,"self_mute":true,"suppress":true,"channel_id":"18446744073709551615","activity":{"name":"private-name"}}],"presence_count":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name == "private-name")
            #expect(model.instantInvite.guildModelNullableValue == "private-instant_invite")
            #expect(model.channels.count == 1)
            #expect(model.members.count == 1)
            #expect(model.presenceCount == 1)
        }
        do {
            let model = try GuildWidgetChannel(data: Data(#"{"id":"18446744073709551615","name":"private-name","position":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.name.guildModelValue == "private-name")
            #expect(model.position.guildModelValue == 1)
        }
        do {
            let model = try GuildWidgetMember(data: Data(#"{"id":"private-id","username":"private-username","discriminator":"private-discriminator","avatar":"private-avatar","status":"private-status","avatar_url":"private-avatar_url","deaf":true,"mute":true,"self_deaf":true,"self_mute":true,"suppress":true,"channel_id":"18446744073709551615","activity":{"name":"private-name"},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id == "private-id")
            #expect(model.username.guildModelValue == "private-username")
            #expect(model.discriminator.guildModelValue == "private-discriminator")
            #expect(model.avatar.guildModelValue == "private-avatar")
            #expect(model.status.guildModelValue == "private-status")
            #expect(model.avatarURL.guildModelValue == "private-avatar_url")
            #expect(model.deaf.guildModelValue == true)
            #expect(model.mute.guildModelValue == true)
            #expect(model.selfDeaf.guildModelValue == true)
            #expect(model.selfMute.guildModelValue == true)
            #expect(model.suppress.guildModelValue == true)
            #expect(model.channelID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.activity.guildModelValue?.jsonValue() == model.rawFields["activity"])
        }
        do {
            let model = try GuildVanityURL(data: Data(#"{"code":"private-code","uses":1,"error":{"message":"private-message","code":1},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.code.guildModelNullableValue == "private-code")
            #expect(model.uses == 1)
            #expect(model.error.guildModelValue?.jsonValue() == model.rawFields["error"])
        }
        do {
            let model = try GuildWelcomeScreen(data: Data(#"{"description":"private-description","welcome_channels":[{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name"}],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.welcomeDescription.guildModelNullableValue == "private-description")
            #expect(model.welcomeChannels.count == 1)
        }
        do {
            let model = try GuildWelcomeChannel(data: Data(#"{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.channelID.rawValue == UInt64.max)
            #expect(model.channelDescription == "private-description")
            #expect(model.emojiID.guildModelNullableValue?.rawValue == UInt64.max)
            #expect(model.emojiName.guildModelNullableValue == "private-emoji_name")
        }
        do {
            let model = try GuildOnboarding(data: Data(#"{"guild_id":"18446744073709551615","prompts":[{"id":"18446744073709551615","type":999,"options":[{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description"}],"title":"private-title","single_select":true,"required":true,"in_onboarding":true}],"default_channel_ids":["18446744073709551615"],"enabled":true,"mode":999,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.guildID.rawValue == UInt64.max)
            #expect(model.prompts.count == 1)
            #expect(model.defaultChannelIDs.first?.rawValue == UInt64.max)
            #expect(model.enabled == true)
            #expect(model.mode.rawValue == 999 && model.mode.knownValue == nil)
        }
        do {
            let model = try GuildOnboardingPrompt(data: Data(#"{"id":"18446744073709551615","type":999,"options":[{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description"}],"title":"private-title","single_select":true,"required":true,"in_onboarding":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.type.rawValue == 999 && model.type.knownValue == nil)
            #expect(model.options.count == 1)
            #expect(model.title == "private-title")
            #expect(model.singleSelect == true)
            #expect(model.required == true)
            #expect(model.inOnboarding == true)
        }
        do {
            let model = try GuildOnboardingOption(data: Data(#"{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.id.rawValue == UInt64.max)
            #expect(model.channelIDs.first?.rawValue == UInt64.max)
            #expect(model.roleIDs.first?.rawValue == UInt64.max)
            #expect(model.emoji.guildModelValue?.jsonValue() == model.rawFields["emoji"])
            #expect(model.emojiID.guildModelValue?.rawValue == UInt64.max)
            #expect(model.emojiName.guildModelValue == "private-emoji_name")
            #expect(model.emojiAnimated.guildModelValue == true)
            #expect(model.title == "private-title")
            #expect(model.optionDescription.guildModelNullableValue == "private-description")
        }
        do {
            let model = try GuildIncidentsData(data: Data(#"{"invites_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dms_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dm_spam_detected_at":"2026-10-16T12:34:56.123456789+00:00","raid_detected_at":"2026-10-16T12:34:56.123456789+00:00","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.invitesDisabledUntil.guildModelNullableValue?.nanosecond == 123_456_789)
            #expect(model.dmsDisabledUntil.guildModelNullableValue?.nanosecond == 123_456_789)
            #expect(model.dmSpamDetectedAt.guildModelValue?.nanosecond == 123_456_789)
            #expect(model.raidDetectedAt.guildModelValue?.nanosecond == 123_456_789)
        }
        do {
            let model = try GuildWidgetActivity(data: Data(#"{"name":"private-name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.name == "private-name")
        }
        do {
            let model = try GuildVanityError(data: Data(#"{"message":"private-message","code":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#.utf8))
            #expect(model.message == "private-message")
            #expect(model.code == 1)
        }
    }

    /// Minimal snapshots expose absent optional properties and explicit required nulls directly through typed APIs.
    /// Setting every nullable optional to null preserves that state rather than collapsing it to omission.
    /// Empty scalar/object arrays and false Boolean values remain valid without default substitution.
    /// - Throws: Unexpected fixture, schema, assertion or serialization errors fail the test.
    @Test func absentNullAndEmptyTypedProjections() throws {
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "Guild" })
            let minimal = try Guild(data: Data(fixture.minimal.utf8))
            #expect(minimal.iconHash == .absent)
            #expect(minimal.discoverySplash == .absent)
            #expect(minimal.owner == .absent)
            #expect(minimal.permissions == .absent)
            #expect(minimal.region == .absent)
            #expect(minimal.widgetEnabled == .absent)
            #expect(minimal.widgetChannelID == .absent)
            #expect(minimal.maxPresences == .absent)
            #expect(minimal.maxMembers == .absent)
            #expect(minimal.premiumSubscriptionCount == .absent)
            #expect(minimal.maxVideoChannelUsers == .absent)
            #expect(minimal.maxStageVideoChannelUsers == .absent)
            #expect(minimal.approximateMemberCount == .absent)
            #expect(minimal.approximatePresenceCount == .absent)
            #expect(minimal.welcomeScreen == .absent)
            #expect(minimal.stickers == .absent)
            #expect(minimal.homeHeader == .absent)
            #expect(minimal.nsfw == .absent)
            #expect(minimal.premiumProgressBarEnabledUserUpdatedAt == .absent)
            #expect(minimal.icon == .null)
            #expect(minimal.splash == .null)
            #expect(minimal.afkChannelID == .null)
            #expect(minimal.applicationID == .null)
            #expect(minimal.systemChannelID == .null)
            #expect(minimal.rulesChannelID == .null)
            #expect(minimal.vanityURLCode == .null)
            #expect(minimal.guildDescription == .null)
            #expect(minimal.banner == .null)
            #expect(minimal.publicUpdatesChannelID == .null)
            #expect(minimal.safetyAlertsChannelID == .null)
            #expect(minimal.incidentsData == .null)
            var fields = minimal.rawFields
            fields["icon_hash"] = .null
            fields["discovery_splash"] = .null
            fields["region"] = .null
            fields["widget_channel_id"] = .null
            fields["max_presences"] = .null
            fields["home_header"] = .null
            fields["premium_progress_bar_enabled_user_updated_at"] = .null
            fields["roles"] = .array([])
            fields["emojis"] = .array([])
            fields["features"] = .array([])
            fields["stickers"] = .array([])
            fields["owner"] = .bool(false)
            fields["widget_enabled"] = .bool(false)
            fields["premium_progress_bar_enabled"] = .bool(false)
            fields["nsfw"] = .bool(false)
            let changed = try Guild(data: JSONValue.object(fields).serialized())
            #expect(changed.iconHash == .null)
            #expect(changed.discoverySplash == .null)
            #expect(changed.region == .null)
            #expect(changed.widgetChannelID == .null)
            #expect(changed.maxPresences == .null)
            #expect(changed.homeHeader == .null)
            #expect(changed.premiumProgressBarEnabledUserUpdatedAt == .null)
            #expect(changed.roles.isEmpty)
            #expect(changed.emojis.isEmpty)
            #expect(changed.features.isEmpty)
            #expect(changed.stickers.guildModelValue?.isEmpty == true)
            #expect(changed.owner == .value(false))
            #expect(changed.widgetEnabled == .value(false))
            #expect(changed.premiumProgressBarEnabled == false)
            #expect(changed.nsfw == .value(false))
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildUnavailable" })
            let minimal = try GuildUnavailable(data: Data(fixture.minimal.utf8))
            var fields = minimal.rawFields
            fields["unavailable"] = .bool(false)
            let changed = try GuildUnavailable(data: JSONValue.object(fields).serialized())
            #expect(changed.unavailable == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildPreview" })
            let minimal = try GuildPreview(data: Data(fixture.minimal.utf8))
            #expect(minimal.homeHeader == .absent)
            #expect(minimal.icon == .null)
            #expect(minimal.splash == .null)
            #expect(minimal.discoverySplash == .null)
            #expect(minimal.guildDescription == .null)
            var fields = minimal.rawFields
            fields["home_header"] = .null
            fields["emojis"] = .array([])
            fields["features"] = .array([])
            fields["stickers"] = .array([])
            let changed = try GuildPreview(data: JSONValue.object(fields).serialized())
            #expect(changed.homeHeader == .null)
            #expect(changed.emojis.isEmpty)
            #expect(changed.features.isEmpty)
            #expect(changed.stickers.isEmpty)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildMember" })
            let minimal = try GuildMember(data: Data(fixture.minimal.utf8))
            #expect(minimal.user == .absent)
            #expect(minimal.nick == .absent)
            #expect(minimal.avatar == .absent)
            #expect(minimal.banner == .absent)
            #expect(minimal.premiumSince == .absent)
            #expect(minimal.pending == .absent)
            #expect(minimal.permissions == .absent)
            #expect(minimal.communicationDisabledUntil == .absent)
            #expect(minimal.avatarDecorationData == .absent)
            #expect(minimal.collectibles == .absent)
            #expect(minimal.joinedAt == .null)
            var fields = minimal.rawFields
            fields["nick"] = .null
            fields["avatar"] = .null
            fields["banner"] = .null
            fields["premium_since"] = .null
            fields["communication_disabled_until"] = .null
            fields["avatar_decoration_data"] = .null
            fields["collectibles"] = .null
            fields["roles"] = .array([])
            fields["deaf"] = .bool(false)
            fields["mute"] = .bool(false)
            fields["pending"] = .bool(false)
            let changed = try GuildMember(data: JSONValue.object(fields).serialized())
            #expect(changed.nick == .null)
            #expect(changed.avatar == .null)
            #expect(changed.banner == .null)
            #expect(changed.premiumSince == .null)
            #expect(changed.communicationDisabledUntil == .null)
            #expect(changed.avatarDecorationData == .null)
            #expect(changed.collectibles == .null)
            #expect(changed.roles.isEmpty)
            #expect(changed.deaf == false)
            #expect(changed.mute == false)
            #expect(changed.pending == .value(false))
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildRole" })
            let minimal = try GuildRole(data: Data(fixture.minimal.utf8))
            #expect(minimal.icon == .absent)
            #expect(minimal.unicodeEmoji == .absent)
            #expect(minimal.tags == .absent)
            var fields = minimal.rawFields
            fields["icon"] = .null
            fields["unicode_emoji"] = .null
            fields["hoist"] = .bool(false)
            fields["managed"] = .bool(false)
            fields["mentionable"] = .bool(false)
            let changed = try GuildRole(data: JSONValue.object(fields).serialized())
            #expect(changed.icon == .null)
            #expect(changed.unicodeEmoji == .null)
            #expect(changed.hoist == false)
            #expect(changed.managed == false)
            #expect(changed.mentionable == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildRoleColors" })
            let minimal = try GuildRoleColors(data: Data(fixture.minimal.utf8))
            #expect(minimal.secondaryColor == .null)
            #expect(minimal.tertiaryColor == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildRoleTags" })
            let minimal = try GuildRoleTags(data: Data(fixture.minimal.utf8))
            #expect(minimal.botID == .absent)
            #expect(minimal.integrationID == .absent)
            #expect(minimal.premiumSubscriber == .absent)
            #expect(minimal.subscriptionListingID == .absent)
            #expect(minimal.availableForPurchase == .absent)
            #expect(minimal.guildConnections == .absent)
            var fields = minimal.rawFields
            fields["premium_subscriber"] = .null
            fields["available_for_purchase"] = .null
            fields["guild_connections"] = .null
            let changed = try GuildRoleTags(data: JSONValue.object(fields).serialized())
            #expect(changed.premiumSubscriber == .null)
            #expect(changed.availableForPurchase == .null)
            #expect(changed.guildConnections == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildBan" })
            let minimal = try GuildBan(data: Data(fixture.minimal.utf8))
            #expect(minimal.reason == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildBulkBanResult" })
            let minimal = try GuildBulkBanResult(data: Data(fixture.minimal.utf8))
            var fields = minimal.rawFields
            fields["banned_users"] = .array([])
            fields["failed_users"] = .array([])
            let changed = try GuildBulkBanResult(data: JSONValue.object(fields).serialized())
            #expect(changed.bannedUsers.isEmpty)
            #expect(changed.failedUsers.isEmpty)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildNickname" })
            let minimal = try GuildNickname(data: Data(fixture.minimal.utf8))
            #expect(minimal.nick == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildPruneCount" })
            let minimal = try GuildPruneCount(data: Data(fixture.minimal.utf8))
            #expect(minimal.pruned == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildVoiceRegion" })
            let minimal = try GuildVoiceRegion(data: Data(fixture.minimal.utf8))
            var fields = minimal.rawFields
            fields["optimal"] = .bool(false)
            fields["deprecated"] = .bool(false)
            fields["custom"] = .bool(false)
            let changed = try GuildVoiceRegion(data: JSONValue.object(fields).serialized())
            #expect(changed.optimal == false)
            #expect(changed.deprecated == false)
            #expect(changed.custom == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildIntegration" })
            let minimal = try GuildIntegration(data: Data(fixture.minimal.utf8))
            #expect(minimal.syncing == .absent)
            #expect(minimal.roleID == .absent)
            #expect(minimal.enableEmoticons == .absent)
            #expect(minimal.expireBehavior == .absent)
            #expect(minimal.expireGracePeriod == .absent)
            #expect(minimal.user == .absent)
            #expect(minimal.syncedAt == .absent)
            #expect(minimal.subscriberCount == .absent)
            #expect(minimal.revoked == .absent)
            #expect(minimal.application == .absent)
            #expect(minimal.scopes == .absent)
            #expect(minimal.name == .null)
            var fields = minimal.rawFields
            fields["role_id"] = .null
            fields["scopes"] = .array([])
            fields["enabled"] = .bool(false)
            fields["syncing"] = .bool(false)
            fields["enable_emoticons"] = .bool(false)
            fields["revoked"] = .bool(false)
            let changed = try GuildIntegration(data: JSONValue.object(fields).serialized())
            #expect(changed.roleID == .null)
            #expect(changed.scopes.guildModelValue?.isEmpty == true)
            #expect(changed.enabled == false)
            #expect(changed.syncing == .value(false))
            #expect(changed.enableEmoticons == .value(false))
            #expect(changed.revoked == .value(false))
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildIntegrationApplication" })
            let minimal = try GuildIntegrationApplication(data: Data(fixture.minimal.utf8))
            #expect(minimal.bot == .absent)
            #expect(minimal.type == .absent)
            #expect(minimal.coverImage == .absent)
            #expect(minimal.primarySKUID == .absent)
            #expect(minimal.flags == .absent)
            #expect(minimal.flagsNew == .absent)
            #expect(minimal.icon == .null)
            var fields = minimal.rawFields
            fields["type"] = .null
            let changed = try GuildIntegrationApplication(data: JSONValue.object(fields).serialized())
            #expect(changed.type == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWidgetSettings" })
            let minimal = try GuildWidgetSettings(data: Data(fixture.minimal.utf8))
            #expect(minimal.channelID == .null)
            var fields = minimal.rawFields
            fields["enabled"] = .bool(false)
            let changed = try GuildWidgetSettings(data: JSONValue.object(fields).serialized())
            #expect(changed.enabled == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWidget" })
            let minimal = try GuildWidget(data: Data(fixture.minimal.utf8))
            #expect(minimal.instantInvite == .null)
            var fields = minimal.rawFields
            fields["channels"] = .array([])
            fields["members"] = .array([])
            let changed = try GuildWidget(data: JSONValue.object(fields).serialized())
            #expect(changed.channels.isEmpty)
            #expect(changed.members.isEmpty)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWidgetChannel" })
            let minimal = try GuildWidgetChannel(data: Data(fixture.minimal.utf8))
            #expect(minimal.name == .absent)
            #expect(minimal.position == .absent)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWidgetMember" })
            let minimal = try GuildWidgetMember(data: Data(fixture.minimal.utf8))
            #expect(minimal.username == .absent)
            #expect(minimal.discriminator == .absent)
            #expect(minimal.avatar == .absent)
            #expect(minimal.status == .absent)
            #expect(minimal.avatarURL == .absent)
            #expect(minimal.deaf == .absent)
            #expect(minimal.mute == .absent)
            #expect(minimal.selfDeaf == .absent)
            #expect(minimal.selfMute == .absent)
            #expect(minimal.suppress == .absent)
            #expect(minimal.channelID == .absent)
            #expect(minimal.activity == .absent)
            var fields = minimal.rawFields
            fields["avatar"] = .null
            fields["deaf"] = .bool(false)
            fields["mute"] = .bool(false)
            fields["self_deaf"] = .bool(false)
            fields["self_mute"] = .bool(false)
            fields["suppress"] = .bool(false)
            let changed = try GuildWidgetMember(data: JSONValue.object(fields).serialized())
            #expect(changed.avatar == .null)
            #expect(changed.deaf == .value(false))
            #expect(changed.mute == .value(false))
            #expect(changed.selfDeaf == .value(false))
            #expect(changed.selfMute == .value(false))
            #expect(changed.suppress == .value(false))
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildVanityURL" })
            let minimal = try GuildVanityURL(data: Data(fixture.minimal.utf8))
            #expect(minimal.error == .absent)
            #expect(minimal.code == .null)
            var fields = minimal.rawFields
            fields["error"] = .null
            let changed = try GuildVanityURL(data: JSONValue.object(fields).serialized())
            #expect(changed.error == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWelcomeScreen" })
            let minimal = try GuildWelcomeScreen(data: Data(fixture.minimal.utf8))
            #expect(minimal.welcomeDescription == .null)
            var fields = minimal.rawFields
            fields["welcome_channels"] = .array([])
            let changed = try GuildWelcomeScreen(data: JSONValue.object(fields).serialized())
            #expect(changed.welcomeChannels.isEmpty)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildWelcomeChannel" })
            let minimal = try GuildWelcomeChannel(data: Data(fixture.minimal.utf8))
            #expect(minimal.emojiID == .null)
            #expect(minimal.emojiName == .null)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildOnboarding" })
            let minimal = try GuildOnboarding(data: Data(fixture.minimal.utf8))
            var fields = minimal.rawFields
            fields["prompts"] = .array([])
            fields["default_channel_ids"] = .array([])
            fields["enabled"] = .bool(false)
            let changed = try GuildOnboarding(data: JSONValue.object(fields).serialized())
            #expect(changed.prompts.isEmpty)
            #expect(changed.defaultChannelIDs.isEmpty)
            #expect(changed.enabled == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildOnboardingPrompt" })
            let minimal = try GuildOnboardingPrompt(data: Data(fixture.minimal.utf8))
            var fields = minimal.rawFields
            fields["options"] = .array([])
            fields["single_select"] = .bool(false)
            fields["required"] = .bool(false)
            fields["in_onboarding"] = .bool(false)
            let changed = try GuildOnboardingPrompt(data: JSONValue.object(fields).serialized())
            #expect(changed.options.isEmpty)
            #expect(changed.singleSelect == false)
            #expect(changed.required == false)
            #expect(changed.inOnboarding == false)
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildOnboardingOption" })
            let minimal = try GuildOnboardingOption(data: Data(fixture.minimal.utf8))
            #expect(minimal.emoji == .absent)
            #expect(minimal.emojiID == .absent)
            #expect(minimal.emojiName == .absent)
            #expect(minimal.emojiAnimated == .absent)
            #expect(minimal.optionDescription == .null)
            var fields = minimal.rawFields
            fields["channel_ids"] = .array([])
            fields["role_ids"] = .array([])
            fields["emoji_animated"] = .bool(false)
            let changed = try GuildOnboardingOption(data: JSONValue.object(fields).serialized())
            #expect(changed.channelIDs.isEmpty)
            #expect(changed.roleIDs.isEmpty)
            #expect(changed.emojiAnimated == .value(false))
        }
        do {
            let fixture = try #require(GuildModelFixture.all.first { $0.name == "GuildIncidentsData" })
            let minimal = try GuildIncidentsData(data: Data(fixture.minimal.utf8))
            #expect(minimal.dmSpamDetectedAt == .absent)
            #expect(minimal.raidDetectedAt == .absent)
            #expect(minimal.invitesDisabledUntil == .null)
            #expect(minimal.dmsDisabledUntil == .null)
            var fields = minimal.rawFields
            fields["dm_spam_detected_at"] = .null
            fields["raid_detected_at"] = .null
            let changed = try GuildIncidentsData(data: JSONValue.object(fields).serialized())
            #expect(changed.dmSpamDetectedAt == .null)
            #expect(changed.raidDetectedAt == .null)
        }
    }

    /// Dynamic role counts accept empty maps and all 64 snowflake bits, rejecting aliasing, bad keys and bad counts.
    /// Prune explicit null means an uncomputed count; zero and positive results remain distinct.
    /// - Throws: Unexpected parse failures fail the test; all expected validation errors are asserted.
    @Test func dynamicCountsAndPruneNull() throws {
        let counts = try GuildRoleMemberCounts(data: Data(#"{"18446744073709551615":9223372036854775807,"0":0}"#.utf8))
        #expect(counts.counts[RoleID(rawValue: .max)] == Int.max)
        #expect(counts.counts[RoleID(rawValue: 0)] == 0)
        #expect(try GuildRoleMemberCounts(data: Data("{}".utf8)).counts.isEmpty)
        #expect(counts.description == "GuildRoleMemberCounts(redacted)")
        #expect(counts.customMirror.children.count == 1)
        #expect(counts.jsonValue() == .object(counts.rawFields))
        for invalid in [#"{"a":1}"#, #"{"18446744073709551616":1}"#, #"{"-1":1}"#, #"{"1":-1}"#,
                        #"{"1":1e0}"#, #"{"1":1.0}"#, #"{"1":9223372036854775808}"#, #"{"1":null}"#,
                        #"{"1":"2"}"#, #"{"1":true}"#, #"{"1":1,"01":2}"#, "null", "[]"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildRoleMemberCounts(data: Data(invalid.utf8)) }
        }
        for limits in [JSONLimits(maximumBytes: 1), JSONLimits(maximumNodes: 1)] {
            #expect(throws: JSONValueError.self) { try GuildRoleMemberCounts(data: Data(#"{"1":1}"#.utf8), limits: limits) }
        }
        #expect(try GuildPruneCount(data: Data(#"{"pruned":null}"#.utf8)).pruned == .null)
        #expect(try GuildPruneCount(data: Data(#"{"pruned":0}"#.utf8)).pruned == .value(0))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildPruneCount(data: Data(#"{"pruned":-1}"#.utf8)) }
    }

    /// Missing screening state stays absent, explicit pending transitions remain distinct, and guest join time is nullable.
    /// Role-tag null sentinels retain presence and arbitrary-width permission text never truncates to UInt64.
    /// - Throws: Unexpected parsing failures fail the test; forbidden permission strings are asserted.
    @Test func screeningTagsAndPermissionBoundaries() throws {
        let absent = try GuildMember(data: Data(#"{"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":0}"#.utf8))
        #expect(absent.pending == .absent && absent.user == .absent && absent.nick == .absent)
        #expect(absent.joinedAt == .null && absent.roles.isEmpty && absent.flags == 0)
        for pending in [true, false] {
            var fields = absent.rawFields
            fields["pending"] = .bool(pending)
            let member = try GuildMember(data: JSONValue.object(fields).serialized())
            #expect(member.pending == .value(pending))
        }
        let tags = try GuildRoleTags(data: Data(#"{"premium_subscriber":null,"available_for_purchase":null,"guild_connections":null}"#.utf8))
        #expect(tags.premiumSubscriber == .null && tags.availableForPurchase == .null && tags.guildConnections == .null)
        #expect(tags.botID == .absent && tags.integrationID == .absent && tags.subscriptionListingID == .absent)
        for invalid in ["", "-1", "+1", "1.0", "1e0", " 1", "١"] {
            var fields = absent.rawFields
            fields["permissions"] = .string(invalid)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildMember(data: JSONValue.object(fields).serialized()) }
        }
        let future = try JSONNumber(rawValue: "1.230000000000000000001e1000")
        let bytes = Data(GuildModelFixture.all[0].populated.utf8)
        let guild = try Guild(data: bytes)
        #expect(guild.rawFields["future_secret"] == .object(["numeric": .number(future), "text": .string("private-future")]))
        #expect(throws: JSONValueError.maximumDepthExceeded) { try Guild(data: bytes, limits: JSONLimits(maximumDepth: 2)) }
    }

    /// All named enum and flag constants match the current official wire values; wrappers keep unknown high bits.
    /// Widget image style iteration lists exactly the five documented server-rendered image variants.
    @Test func knownEnumsAndFlags() {
        #expect(GuildVerificationLevel.`none`.rawValue == 0)
        #expect(GuildVerificationLevel.low.rawValue == 1)
        #expect(GuildVerificationLevel.medium.rawValue == 2)
        #expect(GuildVerificationLevel.high.rawValue == 3)
        #expect(GuildVerificationLevel.veryHigh.rawValue == 4)
        #expect(GuildDefaultMessageNotificationLevel.allMessages.rawValue == 0)
        #expect(GuildDefaultMessageNotificationLevel.onlyMentions.rawValue == 1)
        #expect(GuildExplicitContentFilterLevel.disabled.rawValue == 0)
        #expect(GuildExplicitContentFilterLevel.membersWithoutRoles.rawValue == 1)
        #expect(GuildExplicitContentFilterLevel.allMembers.rawValue == 2)
        #expect(GuildMFALevel.`none`.rawValue == 0)
        #expect(GuildMFALevel.elevated.rawValue == 1)
        #expect(GuildPremiumTier.`none`.rawValue == 0)
        #expect(GuildPremiumTier.tier1.rawValue == 1)
        #expect(GuildPremiumTier.tier2.rawValue == 2)
        #expect(GuildPremiumTier.tier3.rawValue == 3)
        #expect(GuildNSFWLevel.`default`.rawValue == 0)
        #expect(GuildNSFWLevel.explicit.rawValue == 1)
        #expect(GuildNSFWLevel.safe.rawValue == 2)
        #expect(GuildNSFWLevel.ageRestricted.rawValue == 3)
        #expect(GuildOnboardingMode.`default`.rawValue == 0)
        #expect(GuildOnboardingMode.advanced.rawValue == 1)
        #expect(GuildOnboardingPromptType.multipleChoice.rawValue == 0)
        #expect(GuildOnboardingPromptType.dropdown.rawValue == 1)
        #expect(GuildIntegrationExpireBehavior.removeRole.rawValue == 0)
        #expect(GuildIntegrationExpireBehavior.kick.rawValue == 1)
        #expect(GuildIntegrationType.twitch.rawValue == "twitch")
        #expect(GuildIntegrationType.youtube.rawValue == "youtube")
        #expect(GuildIntegrationType.discord.rawValue == "discord")
        #expect(GuildIntegrationType.guildSubscription.rawValue == "guild_subscription")
        #expect(GuildWidgetImageStyle.shield.rawValue == "shield")
        #expect(GuildWidgetImageStyle.banner1.rawValue == "banner1")
        #expect(GuildWidgetImageStyle.banner2.rawValue == "banner2")
        #expect(GuildWidgetImageStyle.banner3.rawValue == "banner3")
        #expect(GuildWidgetImageStyle.banner4.rawValue == "banner4")
        #expect(GuildIntegrationApplicationType.guildRoleSubscriptions.rawValue == 4)
        #expect(GuildFeature.officialGameGuild.rawValue == "OFFICIAL_GAME_GUILD")
        #expect(GuildFeature.animatedBanner.rawValue == "ANIMATED_BANNER")
        #expect(GuildFeature.animatedIcon.rawValue == "ANIMATED_ICON")
        #expect(GuildFeature.applicationCommandPermissionsV2.rawValue == "APPLICATION_COMMAND_PERMISSIONS_V2")
        #expect(GuildFeature.autoModeration.rawValue == "AUTO_MODERATION")
        #expect(GuildFeature.banner.rawValue == "BANNER")
        #expect(GuildFeature.community.rawValue == "COMMUNITY")
        #expect(GuildFeature.creatorMonetizableProvisional.rawValue == "CREATOR_MONETIZABLE_PROVISIONAL")
        #expect(GuildFeature.creatorStorePage.rawValue == "CREATOR_STORE_PAGE")
        #expect(GuildFeature.developerSupportServer.rawValue == "DEVELOPER_SUPPORT_SERVER")
        #expect(GuildFeature.discoverable.rawValue == "DISCOVERABLE")
        #expect(GuildFeature.enhancedRoleColors.rawValue == "ENHANCED_ROLE_COLORS")
        #expect(GuildFeature.featurable.rawValue == "FEATURABLE")
        #expect(GuildFeature.guildTags.rawValue == "GUILD_TAGS")
        #expect(GuildFeature.guestsEnabled.rawValue == "GUESTS_ENABLED")
        #expect(GuildFeature.invitesDisabled.rawValue == "INVITES_DISABLED")
        #expect(GuildFeature.inviteSplash.rawValue == "INVITE_SPLASH")
        #expect(GuildFeature.memberVerificationGateEnabled.rawValue == "MEMBER_VERIFICATION_GATE_ENABLED")
        #expect(GuildFeature.moreSoundboard.rawValue == "MORE_SOUNDBOARD")
        #expect(GuildFeature.moreStickers.rawValue == "MORE_STICKERS")
        #expect(GuildFeature.news.rawValue == "NEWS")
        #expect(GuildFeature.partnered.rawValue == "PARTNERED")
        #expect(GuildFeature.previewEnabled.rawValue == "PREVIEW_ENABLED")
        #expect(GuildFeature.pruneRequiresAdmin.rawValue == "PRUNE_REQUIRES_ADMIN")
        #expect(GuildFeature.raidAlertsDisabled.rawValue == "RAID_ALERTS_DISABLED")
        #expect(GuildFeature.roleIcons.rawValue == "ROLE_ICONS")
        #expect(GuildFeature.roleSubscriptionsAvailableForPurchase.rawValue == "ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE")
        #expect(GuildFeature.roleSubscriptionsEnabled.rawValue == "ROLE_SUBSCRIPTIONS_ENABLED")
        #expect(GuildFeature.soundboard.rawValue == "SOUNDBOARD")
        #expect(GuildFeature.ticketedEventsEnabled.rawValue == "TICKETED_EVENTS_ENABLED")
        #expect(GuildFeature.vanityUrl.rawValue == "VANITY_URL")
        #expect(GuildFeature.verified.rawValue == "VERIFIED")
        #expect(GuildFeature.vipRegions.rawValue == "VIP_REGIONS")
        #expect(GuildFeature.welcomeScreenEnabled.rawValue == "WELCOME_SCREEN_ENABLED")
        #expect(GuildSystemChannelFlags(rawValue: .max).rawValue == UInt64.max)
        #expect(GuildSystemChannelFlags(rawValue: 0).isEmpty)
        #expect(GuildSystemChannelFlags.suppressJoinNotifications.rawValue == 1)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressJoinNotifications))
        #expect(GuildSystemChannelFlags.suppressPremiumSubscriptions.rawValue == 2)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressPremiumSubscriptions))
        #expect(GuildSystemChannelFlags.suppressGuildReminderNotifications.rawValue == 4)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressGuildReminderNotifications))
        #expect(GuildSystemChannelFlags.suppressJoinNotificationReplies.rawValue == 8)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressJoinNotificationReplies))
        #expect(GuildSystemChannelFlags.suppressRoleSubscriptionPurchaseNotifications.rawValue == 16)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressRoleSubscriptionPurchaseNotifications))
        #expect(GuildSystemChannelFlags.suppressRoleSubscriptionPurchaseNotificationReplies.rawValue == 32)
        #expect(GuildSystemChannelFlags(rawValue: .max).contains(.suppressRoleSubscriptionPurchaseNotificationReplies))
        #expect(GuildMemberFlags(rawValue: .max).rawValue == UInt64.max)
        #expect(GuildMemberFlags(rawValue: 0).isEmpty)
        #expect(GuildMemberFlags.didRejoin.rawValue == 1)
        #expect(GuildMemberFlags(rawValue: .max).contains(.didRejoin))
        #expect(GuildMemberFlags.completedOnboarding.rawValue == 2)
        #expect(GuildMemberFlags(rawValue: .max).contains(.completedOnboarding))
        #expect(GuildMemberFlags.bypassesVerification.rawValue == 4)
        #expect(GuildMemberFlags(rawValue: .max).contains(.bypassesVerification))
        #expect(GuildMemberFlags.startedOnboarding.rawValue == 8)
        #expect(GuildMemberFlags(rawValue: .max).contains(.startedOnboarding))
        #expect(GuildMemberFlags.isGuest.rawValue == 16)
        #expect(GuildMemberFlags(rawValue: .max).contains(.isGuest))
        #expect(GuildMemberFlags.startedHomeActions.rawValue == 32)
        #expect(GuildMemberFlags(rawValue: .max).contains(.startedHomeActions))
        #expect(GuildMemberFlags.completedHomeActions.rawValue == 64)
        #expect(GuildMemberFlags(rawValue: .max).contains(.completedHomeActions))
        #expect(GuildMemberFlags.automodQuarantinedUsername.rawValue == 128)
        #expect(GuildMemberFlags(rawValue: .max).contains(.automodQuarantinedUsername))
        #expect(GuildMemberFlags.dmSettingsUpsellAcknowledged.rawValue == 512)
        #expect(GuildMemberFlags(rawValue: .max).contains(.dmSettingsUpsellAcknowledged))
        #expect(GuildMemberFlags.automodQuarantinedGuildTag.rawValue == 1024)
        #expect(GuildMemberFlags(rawValue: .max).contains(.automodQuarantinedGuildTag))
        #expect(GuildRoleFlags(rawValue: .max).rawValue == UInt64.max)
        #expect(GuildRoleFlags(rawValue: 0).isEmpty)
        #expect(GuildRoleFlags.inPrompt.rawValue == 1)
        #expect(GuildRoleFlags(rawValue: .max).contains(.inPrompt))
        #expect(GuildWidgetImageStyle.allCases.map(\.rawValue) == ["shield", "banner1", "banner2", "banner3", "banner4"])
    }
}

/// Schema metadata for independently testing every field without reflecting sensitive production properties.
private struct GuildModelField: Sendable {
    let name: String
    let optional: Bool
    let nullable: Bool
    let invalid: [String]
}

/// Explicit fixture constructors exercise both the public root parser and bounded internal tree initializer.
private struct GuildModelFixture: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let minimal: String
    let populated: String
    let fields: [GuildModelField]
    let parse: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue
    let project: @Sendable (JSONValue, JSONLimits) throws -> any MessageResponseValue

    /// Identifies a synthetic schema case without expanding its large payload and closures in parameterized test logs.
    var description: String { name }
    /// Uses the concise synthetic schema name in debug test diagnostics.
    var debugDescription: String { name }

    static let all: [Self] = [
        Self(name: "Guild", minimal: #"{"id":"18446744073709551615","name":"private-name","icon":null,"splash":null,"owner_id":"18446744073709551615","afk_channel_id":null,"afk_timeout":1,"verification_level":999,"default_message_notifications":999,"explicit_content_filter":999,"roles":[],"emojis":[],"features":["FUTURE_VARIANT"],"mfa_level":999,"application_id":null,"system_channel_id":null,"system_channel_flags":9223372036854775809,"rules_channel_id":null,"vanity_url_code":null,"description":null,"banner":null,"premium_tier":999,"preferred_locale":"private-preferred_locale","public_updates_channel_id":null,"nsfw_level":999,"premium_progress_bar_enabled":true,"safety_alerts_channel_id":null,"incidents_data":null}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","icon_hash":"private-icon_hash","splash":"private-splash","discovery_splash":"private-discovery_splash","owner":true,"owner_id":"18446744073709551615","permissions":"184467440737095516161844674407370955161","region":"private-region","afk_channel_id":"18446744073709551615","afk_timeout":1,"widget_enabled":true,"widget_channel_id":"18446744073709551615","verification_level":999,"default_message_notifications":999,"explicit_content_filter":999,"roles":[{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"icon":"private-icon","unicode_emoji":"private-unicode_emoji","position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"tags":{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null},"flags":9223372036854775809}],"emojis":[{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}}],"features":["FUTURE_VARIANT"],"mfa_level":999,"application_id":"18446744073709551615","system_channel_id":"18446744073709551615","system_channel_flags":9223372036854775809,"rules_channel_id":"18446744073709551615","max_presences":1,"max_members":1,"vanity_url_code":"private-vanity_url_code","description":"private-description","banner":"private-banner","premium_tier":999,"premium_subscription_count":1,"preferred_locale":"private-preferred_locale","public_updates_channel_id":"18446744073709551615","max_video_channel_users":1,"max_stage_video_channel_users":1,"approximate_member_count":1,"approximate_presence_count":1,"welcome_screen":{"description":"private-description","welcome_channels":[{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name"}]},"nsfw_level":999,"stickers":[{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}}],"premium_progress_bar_enabled":true,"safety_alerts_channel_id":"18446744073709551615","incidents_data":{"invites_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dms_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dm_spam_detected_at":"2026-10-16T12:34:56.123456789+00:00","raid_detected_at":"2026-10-16T12:34:56.123456789+00:00"},"home_header":"private-home_header","nsfw":true,"premium_progress_bar_enabled_user_updated_at":"2026-10-16T12:34:56.123456789+00:00","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "icon", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "icon_hash", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "splash", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "discovery_splash", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "owner", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "owner_id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "permissions", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "region", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "afk_channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "afk_timeout", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "widget_enabled", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "widget_channel_id", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "verification_level", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "default_message_notifications", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "explicit_content_filter", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "roles", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "emojis", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "features", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "mfa_level", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "application_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "system_channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "system_channel_flags", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"18446744073709551616"#, #"-1"#]),
                GuildModelField(name: "rules_channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "max_presences", optional: true, nullable: true, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "max_members", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "vanity_url_code", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "description", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "banner", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "premium_tier", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "premium_subscription_count", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "preferred_locale", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "public_updates_channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "max_video_channel_users", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "max_stage_video_channel_users", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "approximate_member_count", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "approximate_presence_count", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "welcome_screen", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "nsfw_level", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "stickers", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "premium_progress_bar_enabled", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "safety_alerts_channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "incidents_data", optional: false, nullable: true, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "home_header", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "nsfw", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "premium_progress_bar_enabled_user_updated_at", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
             ], parse: { try Guild(data: $0, limits: $1) },
             project: { try Guild(value: $0, limits: $1) }),
        Self(name: "GuildUnavailable", minimal: #"{"id":"18446744073709551615","unavailable":true}"#,
             populated: #"{"id":"18446744073709551615","unavailable":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "unavailable", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildUnavailable(data: $0, limits: $1) },
             project: { try GuildUnavailable(value: $0, limits: $1) }),
        Self(name: "GuildPreview", minimal: #"{"id":"18446744073709551615","name":"private-name","icon":null,"splash":null,"discovery_splash":null,"emojis":[],"features":["FUTURE_VARIANT"],"approximate_member_count":1,"approximate_presence_count":1,"description":null,"stickers":[]}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","splash":"private-splash","discovery_splash":"private-discovery_splash","emojis":[{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}}],"features":["FUTURE_VARIANT"],"approximate_member_count":1,"approximate_presence_count":1,"description":"private-description","stickers":[{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}}],"home_header":"private-home_header","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "icon", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "splash", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "discovery_splash", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "emojis", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "features", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "approximate_member_count", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "approximate_presence_count", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "description", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "stickers", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "home_header", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildPreview(data: $0, limits: $1) },
             project: { try GuildPreview(value: $0, limits: $1) }),
        Self(name: "GuildMember", minimal: #"{"roles":["18446744073709551615"],"joined_at":null,"deaf":true,"mute":true,"flags":9223372036854775809}"#,
             populated: #"{"user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789+00:00","premium_since":"2026-10-16T12:34:56.123456789+00:00","deaf":true,"mute":true,"flags":9223372036854775809,"pending":true,"permissions":"184467440737095516161844674407370955161","communication_disabled_until":"2026-10-16T12:34:56.123456789+00:00","avatar_decoration_data":{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}},"collectibles":{"id":"18446744073709551615","name":"private-related","type":999,"future_secret":{"exact":"secret"}},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "user", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "nick", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "avatar", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "banner", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "roles", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "joined_at", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "premium_since", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "deaf", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "mute", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "flags", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"18446744073709551616"#, #"-1"#]),
                GuildModelField(name: "pending", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "permissions", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "communication_disabled_until", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "avatar_decoration_data", optional: true, nullable: true, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "collectibles", optional: true, nullable: true, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
             ], parse: { try GuildMember(data: $0, limits: $1) },
             project: { try GuildMember(value: $0, limits: $1) }),
        Self(name: "GuildRole", minimal: #"{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"flags":9223372036854775809}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"icon":"private-icon","unicode_emoji":"private-unicode_emoji","position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"tags":{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null},"flags":9223372036854775809,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "color", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "colors", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "hoist", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "icon", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "unicode_emoji", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "position", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "permissions", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "managed", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "mentionable", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "tags", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "flags", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"18446744073709551616"#, #"-1"#]),
             ], parse: { try GuildRole(data: $0, limits: $1) },
             project: { try GuildRole(value: $0, limits: $1) }),
        Self(name: "GuildRoleColors", minimal: #"{"primary_color":1,"secondary_color":null,"tertiary_color":null}"#,
             populated: #"{"primary_color":1,"secondary_color":1,"tertiary_color":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "primary_color", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "secondary_color", optional: false, nullable: true, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "tertiary_color", optional: false, nullable: true, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildRoleColors(data: $0, limits: $1) },
             project: { try GuildRoleColors(value: $0, limits: $1) }),
        Self(name: "GuildRoleTags", minimal: #"{}"#,
             populated: #"{"bot_id":"18446744073709551615","integration_id":"18446744073709551615","premium_subscriber":null,"subscription_listing_id":"18446744073709551615","available_for_purchase":null,"guild_connections":null,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "bot_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "integration_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "premium_subscriber", optional: true, nullable: true, invalid: [#"false"#, #"true"#, #"0"#, #""x""#, #"{}"#, #"[]"#]),
                GuildModelField(name: "subscription_listing_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "available_for_purchase", optional: true, nullable: true, invalid: [#"false"#, #"true"#, #"0"#, #""x""#, #"{}"#, #"[]"#]),
                GuildModelField(name: "guild_connections", optional: true, nullable: true, invalid: [#"false"#, #"true"#, #"0"#, #""x""#, #"{}"#, #"[]"#]),
             ], parse: { try GuildRoleTags(data: $0, limits: $1) },
             project: { try GuildRoleTags(value: $0, limits: $1) }),
        Self(name: "GuildBan", minimal: #"{"reason":null,"user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}}}"#,
             populated: #"{"reason":"private-reason","user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "reason", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "user", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
             ], parse: { try GuildBan(data: $0, limits: $1) },
             project: { try GuildBan(value: $0, limits: $1) }),
        Self(name: "GuildBulkBanResult", minimal: #"{"banned_users":["18446744073709551615"],"failed_users":["18446744073709551615"]}"#,
             populated: #"{"banned_users":["18446744073709551615"],"failed_users":["18446744073709551615"],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "banned_users", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "failed_users", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
             ], parse: { try GuildBulkBanResult(data: $0, limits: $1) },
             project: { try GuildBulkBanResult(value: $0, limits: $1) }),
        Self(name: "GuildNickname", minimal: #"{"nick":null}"#,
             populated: #"{"nick":"private-nick","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "nick", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildNickname(data: $0, limits: $1) },
             project: { try GuildNickname(value: $0, limits: $1) }),
        Self(name: "GuildPruneCount", minimal: #"{"pruned":null}"#,
             populated: #"{"pruned":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "pruned", optional: false, nullable: true, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildPruneCount(data: $0, limits: $1) },
             project: { try GuildPruneCount(value: $0, limits: $1) }),
        Self(name: "GuildVoiceRegion", minimal: #"{"id":"private-id","name":"private-name","optimal":true,"deprecated":true,"custom":true}"#,
             populated: #"{"id":"private-id","name":"private-name","optimal":true,"deprecated":true,"custom":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "optimal", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "deprecated", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "custom", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildVoiceRegion(data: $0, limits: $1) },
             project: { try GuildVoiceRegion(value: $0, limits: $1) }),
        Self(name: "GuildIntegration", minimal: #"{"id":"private-id","name":null,"type":"FUTURE_VARIANT","enabled":true,"account":{"id":"private-id","name":"private-name"}}"#,
             populated: #"{"id":"private-id","name":"private-name","type":"FUTURE_VARIANT","enabled":true,"syncing":true,"role_id":"18446744073709551615","enable_emoticons":true,"expire_behavior":999,"expire_grace_period":1,"user":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"account":{"id":"private-id","name":"private-name"},"synced_at":"2026-10-16T12:34:56.123456789+00:00","subscriber_count":1,"revoked":true,"application":{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","bot":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"type":999,"cover_image":"private-cover_image","primary_sku_id":"18446744073709551615","flags":9223372036854775809,"flags_new":"private-flags_new"},"scopes":["private-scopes"],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "name", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "type", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "enabled", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "syncing", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "role_id", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "enable_emoticons", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "expire_behavior", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "expire_grace_period", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "user", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "account", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "synced_at", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "subscriber_count", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "revoked", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "application", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "scopes", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
             ], parse: { try GuildIntegration(data: $0, limits: $1) },
             project: { try GuildIntegration(value: $0, limits: $1) }),
        Self(name: "GuildIntegrationAccount", minimal: #"{"id":"private-id","name":"private-name"}"#,
             populated: #"{"id":"private-id","name":"private-name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildIntegrationAccount(data: $0, limits: $1) },
             project: { try GuildIntegrationAccount(value: $0, limits: $1) }),
        Self(name: "GuildIntegrationApplication", minimal: #"{"id":"18446744073709551615","name":"private-name","icon":null,"description":"private-description"}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","bot":{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"exact":"secret"}},"type":999,"cover_image":"private-cover_image","primary_sku_id":"18446744073709551615","flags":9223372036854775809,"flags_new":"private-flags_new","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "icon", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "description", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "bot", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "type", optional: true, nullable: true, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "cover_image", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "primary_sku_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "flags", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"18446744073709551616"#, #"-1"#]),
                GuildModelField(name: "flags_new", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildIntegrationApplication(data: $0, limits: $1) },
             project: { try GuildIntegrationApplication(value: $0, limits: $1) }),
        Self(name: "GuildWidgetSettings", minimal: #"{"enabled":true,"channel_id":null}"#,
             populated: #"{"enabled":true,"channel_id":"18446744073709551615","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "enabled", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "channel_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
             ], parse: { try GuildWidgetSettings(data: $0, limits: $1) },
             project: { try GuildWidgetSettings(value: $0, limits: $1) }),
        Self(name: "GuildWidget", minimal: #"{"id":"18446744073709551615","name":"private-name","instant_invite":null,"channels":[],"members":[],"presence_count":1}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","instant_invite":"private-instant_invite","channels":[{"id":"18446744073709551615","name":"private-name","position":1}],"members":[{"id":"private-id","username":"private-username","discriminator":"private-discriminator","avatar":"private-avatar","status":"private-status","avatar_url":"private-avatar_url","deaf":true,"mute":true,"self_deaf":true,"self_mute":true,"suppress":true,"channel_id":"18446744073709551615","activity":{"name":"private-name"}}],"presence_count":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "instant_invite", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "channels", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "members", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "presence_count", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildWidget(data: $0, limits: $1) },
             project: { try GuildWidget(value: $0, limits: $1) }),
        Self(name: "GuildWidgetChannel", minimal: #"{"id":"18446744073709551615"}"#,
             populated: #"{"id":"18446744073709551615","name":"private-name","position":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "name", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "position", optional: true, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildWidgetChannel(data: $0, limits: $1) },
             project: { try GuildWidgetChannel(value: $0, limits: $1) }),
        Self(name: "GuildWidgetMember", minimal: #"{"id":"private-id"}"#,
             populated: #"{"id":"private-id","username":"private-username","discriminator":"private-discriminator","avatar":"private-avatar","status":"private-status","avatar_url":"private-avatar_url","deaf":true,"mute":true,"self_deaf":true,"self_mute":true,"suppress":true,"channel_id":"18446744073709551615","activity":{"name":"private-name"},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "username", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "discriminator", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "avatar", optional: true, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "status", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "avatar_url", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "deaf", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "mute", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "self_deaf", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "self_mute", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "suppress", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "channel_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "activity", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
             ], parse: { try GuildWidgetMember(data: $0, limits: $1) },
             project: { try GuildWidgetMember(value: $0, limits: $1) }),
        Self(name: "GuildVanityURL", minimal: #"{"code":null,"uses":1}"#,
             populated: #"{"code":"private-code","uses":1,"error":{"message":"private-message","code":1},"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "code", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "uses", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "error", optional: true, nullable: true, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
             ], parse: { try GuildVanityURL(data: $0, limits: $1) },
             project: { try GuildVanityURL(value: $0, limits: $1) }),
        Self(name: "GuildWelcomeScreen", minimal: #"{"description":null,"welcome_channels":[]}"#,
             populated: #"{"description":"private-description","welcome_channels":[{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name"}],"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "description", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "welcome_channels", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
             ], parse: { try GuildWelcomeScreen(data: $0, limits: $1) },
             project: { try GuildWelcomeScreen(value: $0, limits: $1) }),
        Self(name: "GuildWelcomeChannel", minimal: #"{"channel_id":"18446744073709551615","description":"private-description","emoji_id":null,"emoji_name":null}"#,
             populated: #"{"channel_id":"18446744073709551615","description":"private-description","emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "channel_id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "description", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "emoji_id", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "emoji_name", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildWelcomeChannel(data: $0, limits: $1) },
             project: { try GuildWelcomeChannel(value: $0, limits: $1) }),
        Self(name: "GuildOnboarding", minimal: #"{"guild_id":"18446744073709551615","prompts":[],"default_channel_ids":["18446744073709551615"],"enabled":true,"mode":999}"#,
             populated: #"{"guild_id":"18446744073709551615","prompts":[{"id":"18446744073709551615","type":999,"options":[{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description"}],"title":"private-title","single_select":true,"required":true,"in_onboarding":true}],"default_channel_ids":["18446744073709551615"],"enabled":true,"mode":999,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "guild_id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "prompts", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "default_channel_ids", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "enabled", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "mode", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildOnboarding(data: $0, limits: $1) },
             project: { try GuildOnboarding(value: $0, limits: $1) }),
        Self(name: "GuildOnboardingPrompt", minimal: #"{"id":"18446744073709551615","type":999,"options":[],"title":"private-title","single_select":true,"required":true,"in_onboarding":true}"#,
             populated: #"{"id":"18446744073709551615","type":999,"options":[{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description"}],"title":"private-title","single_select":true,"required":true,"in_onboarding":true,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "type", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
                GuildModelField(name: "options", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "title", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "single_select", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "required", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "in_onboarding", optional: false, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildOnboardingPrompt(data: $0, limits: $1) },
             project: { try GuildOnboardingPrompt(value: $0, limits: $1) }),
        Self(name: "GuildOnboardingOption", minimal: #"{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"title":"private-title","description":null}"#,
             populated: #"{"id":"18446744073709551615","channel_ids":["18446744073709551615"],"role_ids":["18446744073709551615"],"emoji":{"id":null,"name":"wave","animated":true,"future_secret":{"exact":"secret"}},"emoji_id":"18446744073709551615","emoji_name":"private-emoji_name","emoji_animated":true,"title":"private-title","description":"private-description","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "id", optional: false, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "channel_ids", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "role_ids", optional: false, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"{}"#, #"[null]"#, #"[false]"#]),
                GuildModelField(name: "emoji", optional: true, nullable: false, invalid: [#"false"#, #""x""#, #"1"#, #"[]"#]),
                GuildModelField(name: "emoji_id", optional: true, nullable: false, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""18446744073709551616""#, #""-1""#, #""x""#]),
                GuildModelField(name: "emoji_name", optional: true, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "emoji_animated", optional: true, nullable: false, invalid: [#""false""#, #"0"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "title", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "description", optional: false, nullable: true, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildOnboardingOption(data: $0, limits: $1) },
             project: { try GuildOnboardingOption(value: $0, limits: $1) }),
        Self(name: "GuildIncidentsData", minimal: #"{"invites_disabled_until":null,"dms_disabled_until":null}"#,
             populated: #"{"invites_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dms_disabled_until":"2026-10-16T12:34:56.123456789+00:00","dm_spam_detected_at":"2026-10-16T12:34:56.123456789+00:00","raid_detected_at":"2026-10-16T12:34:56.123456789+00:00","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "invites_disabled_until", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "dms_disabled_until", optional: false, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "dm_spam_detected_at", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
                GuildModelField(name: "raid_detected_at", optional: true, nullable: true, invalid: [#"1"#, #"true"#, #"{}"#, #"[]"#, #""not-time""#, #""2026-13-01T00:00:00Z""#]),
             ], parse: { try GuildIncidentsData(data: $0, limits: $1) },
             project: { try GuildIncidentsData(value: $0, limits: $1) }),
        Self(name: "GuildWidgetActivity", minimal: #"{"name":"private-name"}"#,
             populated: #"{"name":"private-name","future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "name", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
             ], parse: { try GuildWidgetActivity(data: $0, limits: $1) },
             project: { try GuildWidgetActivity(value: $0, limits: $1) }),
        Self(name: "GuildVanityError", minimal: #"{"message":"private-message","code":1}"#,
             populated: #"{"message":"private-message","code":1,"future_secret":{"numeric":1.230000000000000000001e1000,"text":"private-future"}}"#,
             fields: [
                GuildModelField(name: "message", optional: false, nullable: false, invalid: [#"false"#, #"1"#, #"{}"#, #"[]"#]),
                GuildModelField(name: "code", optional: false, nullable: false, invalid: [#""1""#, #"true"#, #"{}"#, #"[]"#, #"1.0"#, #"1e0"#, #"9223372036854775808"#]),
             ], parse: { try GuildVanityError(data: $0, limits: $1) },
             project: { try GuildVanityError(value: $0, limits: $1) }),
    ]
}

private extension Field {
    /// Extracts a present test value without conflating null and absent assertions in production code.
    /// - Returns: The wrapped value, or nil for explicit null and omission.
    var guildModelValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

private extension Nullable {
    /// Extracts a nonnull test value; assertions compare explicit null separately.
    /// - Returns: The wrapped value, or nil for explicit null.
    var guildModelNullableValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}
