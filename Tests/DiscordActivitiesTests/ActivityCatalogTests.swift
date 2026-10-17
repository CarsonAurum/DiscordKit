import DiscordCore
import Foundation
import Testing
@testable import DiscordActivities

/// Type-erased fixture keeps every public object projection under the same malformed-field regression matrix.
private struct ActivityCatalogFixture: Sendable {
    let name: String
    let required: Set<String>
    let nullable: Set<String>
    let wrong: [String: JSONValue]
    let project: @Sendable (JSONValue) throws -> [String: JSONValue]

    /// Retains exact schema constraints and a typed decoder without invoking it during test discovery.
    /// - Parameters:
    ///   - name: Concrete public projection type name, used to select deterministic test data.
    ///   - required: Keys whose omission is invalid.
    ///   - nullable: Keys whose explicit null is accepted.
    ///   - wrong: Per-field incompatible values; unconstrained JSONValue fields are intentionally excluded.
    ///   - project: Typed initializer returning original fields after validation.
    init(name: String, required: Set<String>, nullable: Set<String>, wrong: [String: JSONValue],
         project: @escaping @Sendable (JSONValue) throws -> [String: JSONValue]) {
        self.name = name; self.required = required; self.nullable = nullable
        self.wrong = wrong; self.project = project
    }
}

/// All typed SDK object projections, independently exercised with missing, null and incompatible field values.
private let activityCatalogFixtures: [ActivityCatalogFixture] = [
    .init(name: "ActivityAuthorization", required: ["code"], nullable: [], wrong: ["code": .bool(false)]) { try activityCatalogProject(ActivityAuthorization.self, value: $0) },
    .init(name: "ActivityApplication", required: ["description", "id", "name"], nullable: ["icon"], wrong: ["description": .bool(false), "icon": .bool(false), "id": .bool(false), "rpc_origins": .string("wrong-type"), "name": .bool(false)]) { try activityCatalogProject(ActivityApplication.self, value: $0) },
    .init(name: "ActivityAuthenticatedUser", required: ["username", "discriminator", "id", "public_flags"], nullable: ["avatar", "global_name"], wrong: ["username": .bool(false), "discriminator": .bool(false), "id": .bool(false), "avatar": .bool(false), "public_flags": .bool(false), "global_name": .bool(false)]) { try activityCatalogProject(ActivityAuthenticatedUser.self, value: $0) },
    .init(name: "ActivityAuthentication", required: ["access_token", "user", "scopes", "expires", "application"], nullable: [], wrong: ["access_token": .bool(false), "user": .string("wrong-type"), "scopes": .string("wrong-type"), "expires": .bool(false), "application": .string("wrong-type")]) { try activityCatalogProject(ActivityAuthentication.self, value: $0) },
    .init(name: "ActivityAvatarDecoration", required: ["asset"], nullable: [], wrong: ["asset": .bool(false), "sku_id": .bool(false)]) { try activityCatalogProject(ActivityAvatarDecoration.self, value: $0) },
    .init(name: "ActivityParticipantDecoration", required: [], nullable: ["asset"], wrong: ["asset": .bool(false), "skuId": .bool(false), "expiresAt": .bool(false)]) { try activityCatalogProject(ActivityParticipantDecoration.self, value: $0) },
    .init(name: "ActivityUser", required: ["id", "username", "discriminator", "avatar_decoration_data", "bot"], nullable: ["global_name", "avatar", "avatar_decoration_data", "flags", "premium_type"], wrong: ["id": .bool(false), "username": .bool(false), "discriminator": .bool(false), "global_name": .bool(false), "avatar": .bool(false), "avatar_decoration_data": .string("wrong-type"), "bot": .string("wrong-type"), "flags": .bool(false), "premium_type": .bool(false)]) { try activityCatalogProject(ActivityUser.self, value: $0) },
    .init(name: "ActivityParticipant", required: ["id", "username", "discriminator", "flags", "bot"], nullable: ["global_name", "avatar", "avatar_decoration_data", "premium_type"], wrong: ["id": .bool(false), "username": .bool(false), "global_name": .bool(false), "discriminator": .bool(false), "avatar": .bool(false), "flags": .bool(false), "bot": .string("wrong-type"), "avatar_decoration_data": .string("wrong-type"), "premium_type": .bool(false), "nickname": .bool(false)]) { try activityCatalogProject(ActivityParticipant.self, value: $0) },
    .init(name: "ActivityParticipants", required: ["participants"], nullable: [], wrong: ["participants": .string("wrong-type")]) { try activityCatalogProject(ActivityParticipants.self, value: $0) },
    .init(name: "ActivityGuildMember", required: ["user", "roles", "joined_at", "deaf", "mute"], nullable: ["nick"], wrong: ["user": .string("wrong-type"), "nick": .bool(false), "roles": .string("wrong-type"), "joined_at": .bool(false), "deaf": .string("wrong-type"), "mute": .string("wrong-type")]) { try activityCatalogProject(ActivityGuildMember.self, value: $0) },
    .init(name: "ActivityMemberDecoration", required: ["asset"], nullable: ["sku_id"], wrong: ["asset": .bool(false), "sku_id": .bool(false)]) { try activityCatalogProject(ActivityMemberDecoration.self, value: $0) },
    .init(name: "ActivityGuildMemberUpdate", required: ["user_id", "guild_id"], nullable: ["nick", "avatar", "avatar_decoration_data", "color_string"], wrong: ["user_id": .bool(false), "nick": .bool(false), "guild_id": .bool(false), "avatar": .bool(false), "avatar_decoration_data": .string("wrong-type"), "color_string": .bool(false)]) { try activityCatalogProject(ActivityGuildMemberUpdate.self, value: $0) },
    .init(name: "ActivityVoiceState", required: ["mute", "deaf", "self_mute", "self_deaf", "suppress"], nullable: [], wrong: ["mute": .string("wrong-type"), "deaf": .string("wrong-type"), "self_mute": .string("wrong-type"), "self_deaf": .string("wrong-type"), "suppress": .string("wrong-type")]) { try activityCatalogProject(ActivityVoiceState.self, value: $0) },
    .init(name: "ActivityUserVoiceState", required: ["mute", "nick", "user", "voice_state", "volume"], nullable: [], wrong: ["mute": .string("wrong-type"), "nick": .bool(false), "user": .string("wrong-type"), "voice_state": .string("wrong-type"), "volume": .bool(false)]) { try activityCatalogProject(ActivityUserVoiceState.self, value: $0) },
    .init(name: "ActivityEmoji", required: ["id"], nullable: ["name", "roles", "user", "require_colons", "managed", "animated", "available"], wrong: ["id": .bool(false), "name": .bool(false), "roles": .string("wrong-type"), "user": .string("wrong-type"), "require_colons": .string("wrong-type"), "managed": .string("wrong-type"), "animated": .string("wrong-type"), "available": .string("wrong-type")]) { try activityCatalogProject(ActivityEmoji.self, value: $0) },
    .init(name: "ActivityTimestamps", required: [], nullable: [], wrong: ["start": .bool(false), "end": .bool(false)]) { try activityCatalogProject(ActivityTimestamps.self, value: $0) },
    .init(name: "ActivityParty", required: [], nullable: ["id", "size"], wrong: ["id": .bool(false), "size": .string("wrong-type")]) { try activityCatalogProject(ActivityParty.self, value: $0) },
    .init(name: "ActivityAssets", required: [], nullable: ["large_image", "large_text", "large_url", "small_image", "small_text", "small_url"], wrong: ["large_image": .bool(false), "large_text": .bool(false), "large_url": .bool(false), "small_image": .bool(false), "small_text": .bool(false), "small_url": .bool(false)]) { try activityCatalogProject(ActivityAssets.self, value: $0) },
    .init(name: "ActivitySecrets", required: [], nullable: [], wrong: ["join": .bool(false), "match": .bool(false)]) { try activityCatalogProject(ActivitySecrets.self, value: $0) },
    .init(name: "ActivityRichPresence", required: ["name", "type"], nullable: ["url", "created_at", "timestamps", "application_id", "details", "details_url", "state", "state_url", "emoji", "party", "assets", "secrets", "instance", "flags"], wrong: ["name": .bool(false), "type": .bool(false), "url": .bool(false), "created_at": .bool(false), "timestamps": .string("wrong-type"), "application_id": .bool(false), "details": .bool(false), "details_url": .bool(false), "state": .bool(false), "state_url": .bool(false), "emoji": .string("wrong-type"), "party": .string("wrong-type"), "assets": .string("wrong-type"), "secrets": .string("wrong-type"), "instance": .string("wrong-type"), "flags": .bool(false)]) { try activityCatalogProject(ActivityRichPresence.self, value: $0) },
    .init(name: "ActivityPresenceEmoji", required: ["name"], nullable: ["id", "animated"], wrong: ["name": .bool(false), "id": .bool(false), "animated": .string("wrong-type")]) { try activityCatalogProject(ActivityPresenceEmoji.self, value: $0) },
    .init(name: "ActivityPresenceAssets", required: [], nullable: [], wrong: ["large_image": .bool(false), "large_text": .bool(false), "large_url": .bool(false), "small_image": .bool(false), "small_text": .bool(false), "small_url": .bool(false)]) { try activityCatalogProject(ActivityPresenceAssets.self, value: $0) },
    .init(name: "ActivityPresenceParty", required: [], nullable: [], wrong: ["id": .bool(false), "size": .string("wrong-type"), "privacy": .bool(false)]) { try activityCatalogProject(ActivityPresenceParty.self, value: $0) },
    .init(name: "ActivityPresenceActivity", required: ["name"], nullable: ["url", "emoji"], wrong: ["session_id": .bool(false), "type": .bool(false), "name": .bool(false), "url": .bool(false), "application_id": .bool(false), "status_display_type": .bool(false), "state": .bool(false), "state_url": .bool(false), "details": .bool(false), "details_url": .bool(false), "emoji": .string("wrong-type"), "assets": .string("wrong-type"), "timestamps": .string("wrong-type"), "party": .string("wrong-type"), "secrets": .string("wrong-type"), "sync_id": .bool(false), "created_at": .bool(false), "instance": .string("wrong-type"), "flags": .bool(false), "metadata": .string("wrong-type"), "platform": .bool(false), "supported_platforms": .string("wrong-type"), "buttons": .string("wrong-type"), "hangStatus": .bool(false)]) { try activityCatalogProject(ActivityPresenceActivity.self, value: $0) },
    .init(name: "ActivityMetadata", required: [], nullable: [], wrong: [:]) { try activityCatalogProject(ActivityMetadata.self, value: $0) },
    .init(name: "ActivityPresence", required: ["status"], nullable: ["activity"], wrong: ["status": .bool(false), "activity": .string("wrong-type")]) { try activityCatalogProject(ActivityPresence.self, value: $0) },
    .init(name: "ActivityRelationship", required: ["type", "user"], nullable: [], wrong: ["type": .bool(false), "user": .string("wrong-type"), "presence": .string("wrong-type")]) { try activityCatalogProject(ActivityRelationship.self, value: $0) },
    .init(name: "ActivityRelationships", required: ["relationships"], nullable: [], wrong: ["relationships": .string("wrong-type")]) { try activityCatalogProject(ActivityRelationships.self, value: $0) },
    .init(name: "ActivityPrice", required: ["amount", "currency"], nullable: [], wrong: ["amount": .bool(false), "currency": .bool(false)]) { try activityCatalogProject(ActivityPrice.self, value: $0) },
    .init(name: "ActivitySKU", required: ["id", "name", "type", "price", "application_id", "flags", "release_date"], nullable: ["release_date"], wrong: ["id": .bool(false), "name": .bool(false), "type": .bool(false), "price": .string("wrong-type"), "application_id": .bool(false), "flags": .bool(false), "release_date": .bool(false)]) { try activityCatalogProject(ActivitySKU.self, value: $0) },
    .init(name: "ActivitySKUs", required: ["skus"], nullable: [], wrong: ["skus": .string("wrong-type")]) { try activityCatalogProject(ActivitySKUs.self, value: $0) },
    .init(name: "ActivityEntitlement", required: ["id", "sku_id", "application_id", "user_id", "gift_code_flags", "type"], nullable: ["gifter_user_id", "branches", "starts_at", "ends_at", "parent_id", "consumed", "deleted", "gift_code_batch_id"], wrong: ["id": .bool(false), "sku_id": .bool(false), "application_id": .bool(false), "user_id": .bool(false), "gift_code_flags": .bool(false), "type": .bool(false), "gifter_user_id": .bool(false), "branches": .string("wrong-type"), "starts_at": .bool(false), "ends_at": .bool(false), "parent_id": .bool(false), "consumed": .string("wrong-type"), "deleted": .string("wrong-type"), "gift_code_batch_id": .bool(false)]) { try activityCatalogProject(ActivityEntitlement.self, value: $0) },
    .init(name: "ActivityEntitlements", required: ["entitlements"], nullable: [], wrong: ["entitlements": .string("wrong-type")]) { try activityCatalogProject(ActivityEntitlements.self, value: $0) },
    .init(name: "ActivityPermissions", required: ["permissions"], nullable: [], wrong: ["permissions": .bool(false)]) { try activityCatalogProject(ActivityPermissions.self, value: $0) },
    .init(name: "ActivityPlatformBehaviors", required: [], nullable: [], wrong: ["iosKeyboardResizesView": .string("wrong-type")]) { try activityCatalogProject(ActivityPlatformBehaviors.self, value: $0) },
    .init(name: "ActivityExternalLink", required: ["opened"], nullable: ["opened"], wrong: ["opened": .string("wrong-type")]) { try activityCatalogProject(ActivityExternalLink.self, value: $0) },
    .init(name: "ActivityConfig", required: ["use_interactive_pip"], nullable: [], wrong: ["use_interactive_pip": .string("wrong-type")]) { try activityCatalogProject(ActivityConfig.self, value: $0) },
    .init(name: "ActivityLocale", required: ["locale"], nullable: [], wrong: ["locale": .bool(false)]) { try activityCatalogProject(ActivityLocale.self, value: $0) },
    .init(name: "ActivityHardwareAcceleration", required: ["enabled"], nullable: [], wrong: ["enabled": .string("wrong-type")]) { try activityCatalogProject(ActivityHardwareAcceleration.self, value: $0) },
    .init(name: "ActivityQuest", required: ["quest_id", "external_cta_url"], nullable: ["enrolled_at", "completed_at"], wrong: ["quest_id": .bool(false), "enrolled_at": .bool(false), "completed_at": .bool(false), "external_cta_url": .bool(false)]) { try activityCatalogProject(ActivityQuest.self, value: $0) },
    .init(name: "ActivityQuestEnrollment", required: ["quest_id", "is_enrolled"], nullable: ["enrolled_at"], wrong: ["quest_id": .bool(false), "is_enrolled": .string("wrong-type"), "enrolled_at": .bool(false)]) { try activityCatalogProject(ActivityQuestEnrollment.self, value: $0) },
    .init(name: "ActivityQuestEnrollmentUpdate", required: ["quest_id", "is_enrolled", "enrolled_at"], nullable: [], wrong: ["quest_id": .bool(false), "is_enrolled": .string("wrong-type"), "enrolled_at": .bool(false)]) { try activityCatalogProject(ActivityQuestEnrollmentUpdate.self, value: $0) },
    .init(name: "ActivityImageUpload", required: ["image_url"], nullable: [], wrong: ["image_url": .bool(false)]) { try activityCatalogProject(ActivityImageUpload.self, value: $0) },
    .init(name: "ActivityProxyTicket", required: ["ticket"], nullable: [], wrong: ["ticket": .bool(false)]) { try activityCatalogProject(ActivityProxyTicket.self, value: $0) },
    .init(name: "ActivitySuccess", required: ["success"], nullable: [], wrong: ["success": .string("wrong-type")]) { try activityCatalogProject(ActivitySuccess.self, value: $0) },
    .init(name: "ActivityShareLink", required: ["success", "didCopyLink", "didSendMessage"], nullable: [], wrong: ["success": .string("wrong-type"), "didCopyLink": .string("wrong-type"), "didSendMessage": .string("wrong-type")]) { try activityCatalogProject(ActivityShareLink.self, value: $0) },
    .init(name: "ActivityReadyConfig", required: ["api_endpoint", "environment"], nullable: [], wrong: ["cdn_host": .bool(false), "api_endpoint": .bool(false), "environment": .bool(false)]) { try activityCatalogProject(ActivityReadyConfig.self, value: $0) },
    .init(name: "ActivityReadyUser", required: ["id", "username", "discriminator"], nullable: [], wrong: ["id": .bool(false), "username": .bool(false), "discriminator": .bool(false), "avatar": .bool(false)]) { try activityCatalogProject(ActivityReadyUser.self, value: $0) },
    .init(name: "ActivityReady", required: ["v", "config"], nullable: [], wrong: ["v": .bool(false), "config": .string("wrong-type"), "user": .string("wrong-type")]) { try activityCatalogProject(ActivityReady.self, value: $0) },
    .init(name: "ActivitySpeaking", required: ["user_id"], nullable: [], wrong: ["lobby_id": .bool(false), "channel_id": .bool(false), "user_id": .bool(false)]) { try activityCatalogProject(ActivitySpeaking.self, value: $0) },
    .init(name: "ActivityLayoutUpdate", required: ["layout_mode"], nullable: [], wrong: ["layout_mode": .bool(false)]) { try activityCatalogProject(ActivityLayoutUpdate.self, value: $0) },
    .init(name: "ActivityOrientationUpdate", required: ["screen_orientation", "orientation"], nullable: [], wrong: ["screen_orientation": .bool(false), "orientation": .bool(false)]) { try activityCatalogProject(ActivityOrientationUpdate.self, value: $0) },
    .init(name: "ActivityThermalUpdate", required: ["thermal_state"], nullable: [], wrong: ["thermal_state": .bool(false)]) { try activityCatalogProject(ActivityThermalUpdate.self, value: $0) },
    .init(name: "ActivityEntitlementCreate", required: ["entitlement"], nullable: [], wrong: ["entitlement": .string("wrong-type")]) { try activityCatalogProject(ActivityEntitlementCreate.self, value: $0) },
    .init(name: "ActivityJoin", required: ["applicationId", "secret"], nullable: [], wrong: ["applicationId": .bool(false), "secret": .bool(false)]) { try activityCatalogProject(ActivityJoin.self, value: $0) },
    .init(name: "ActivityHostError", required: ["code"], nullable: [], wrong: ["code": .bool(false), "message": .bool(false)]) { try activityCatalogProject(ActivityHostError.self, value: $0) },
    .init(name: "ActivitySubscriptionResponse", required: ["evt"], nullable: [], wrong: ["evt": .bool(false)]) { try activityCatalogProject(ActivitySubscriptionResponse.self, value: $0) },
    .init(name: "ActivityChannelMention", required: ["id", "guild_id", "type", "name"], nullable: [], wrong: ["id": .bool(false), "guild_id": .bool(false), "type": .bool(false), "name": .bool(false)]) { try activityCatalogProject(ActivityChannelMention.self, value: $0) },
    .init(name: "ActivityAttachment", required: ["id", "filename", "size", "url", "proxy_url"], nullable: ["height", "width"], wrong: ["id": .bool(false), "filename": .bool(false), "size": .bool(false), "url": .bool(false), "proxy_url": .bool(false), "height": .bool(false), "width": .bool(false)]) { try activityCatalogProject(ActivityAttachment.self, value: $0) },
    .init(name: "ActivityEmbedFooter", required: ["text"], nullable: ["icon_url", "proxy_icon_url"], wrong: ["text": .bool(false), "icon_url": .bool(false), "proxy_icon_url": .bool(false)]) { try activityCatalogProject(ActivityEmbedFooter.self, value: $0) },
    .init(name: "ActivityImage", required: [], nullable: ["url", "proxy_url", "height", "width"], wrong: ["url": .bool(false), "proxy_url": .bool(false), "height": .bool(false), "width": .bool(false)]) { try activityCatalogProject(ActivityImage.self, value: $0) },
    .init(name: "ActivityVideo", required: [], nullable: ["url", "height", "width"], wrong: ["url": .bool(false), "height": .bool(false), "width": .bool(false)]) { try activityCatalogProject(ActivityVideo.self, value: $0) },
    .init(name: "ActivityEmbedProvider", required: [], nullable: ["name", "url"], wrong: ["name": .bool(false), "url": .bool(false)]) { try activityCatalogProject(ActivityEmbedProvider.self, value: $0) },
    .init(name: "ActivityEmbedAuthor", required: [], nullable: ["name", "url", "icon_url", "proxy_icon_url"], wrong: ["name": .bool(false), "url": .bool(false), "icon_url": .bool(false), "proxy_icon_url": .bool(false)]) { try activityCatalogProject(ActivityEmbedAuthor.self, value: $0) },
    .init(name: "ActivityEmbedField", required: ["name", "value", "inline"], nullable: [], wrong: ["name": .bool(false), "value": .bool(false), "inline": .string("wrong-type")]) { try activityCatalogProject(ActivityEmbedField.self, value: $0) },
    .init(name: "ActivityEmbed", required: [], nullable: ["title", "type", "description", "url", "timestamp", "color", "footer", "image", "thumbnail", "video", "provider", "author", "fields"], wrong: ["title": .bool(false), "type": .bool(false), "description": .bool(false), "url": .bool(false), "timestamp": .bool(false), "color": .bool(false), "footer": .string("wrong-type"), "image": .string("wrong-type"), "thumbnail": .string("wrong-type"), "video": .string("wrong-type"), "provider": .string("wrong-type"), "author": .string("wrong-type"), "fields": .string("wrong-type")]) { try activityCatalogProject(ActivityEmbed.self, value: $0) },
    .init(name: "ActivityReaction", required: ["count", "me", "emoji"], nullable: [], wrong: ["count": .bool(false), "me": .string("wrong-type"), "emoji": .string("wrong-type")]) { try activityCatalogProject(ActivityReaction.self, value: $0) },
    .init(name: "ActivityMessageActivity", required: ["type"], nullable: ["party_id"], wrong: ["type": .bool(false), "party_id": .bool(false)]) { try activityCatalogProject(ActivityMessageActivity.self, value: $0) },
    .init(name: "ActivityMessageApplication", required: ["id", "description", "name"], nullable: ["cover_image", "icon"], wrong: ["id": .bool(false), "cover_image": .bool(false), "description": .bool(false), "icon": .bool(false), "name": .bool(false)]) { try activityCatalogProject(ActivityMessageApplication.self, value: $0) },
    .init(name: "ActivityMessageReference", required: [], nullable: ["message_id", "channel_id", "guild_id"], wrong: ["message_id": .bool(false), "channel_id": .bool(false), "guild_id": .bool(false)]) { try activityCatalogProject(ActivityMessageReference.self, value: $0) },
    .init(name: "ActivityMessage", required: ["id", "channel_id", "content", "timestamp", "tts", "mention_everyone", "mentions", "mention_roles", "mention_channels", "attachments", "embeds", "pinned", "type"], nullable: ["guild_id", "author", "member", "edited_timestamp", "reactions", "nonce", "webhook_id", "activity", "application", "message_reference", "flags", "stickers", "referenced_message"], wrong: ["id": .bool(false), "channel_id": .bool(false), "guild_id": .bool(false), "author": .string("wrong-type"), "member": .string("wrong-type"), "content": .bool(false), "timestamp": .bool(false), "edited_timestamp": .bool(false), "tts": .string("wrong-type"), "mention_everyone": .string("wrong-type"), "mentions": .string("wrong-type"), "mention_roles": .string("wrong-type"), "mention_channels": .string("wrong-type"), "attachments": .string("wrong-type"), "embeds": .string("wrong-type"), "reactions": .string("wrong-type"), "pinned": .string("wrong-type"), "webhook_id": .bool(false), "type": .bool(false), "activity": .string("wrong-type"), "application": .string("wrong-type"), "message_reference": .string("wrong-type"), "flags": .bool(false), "stickers": .string("wrong-type")]) { try activityCatalogProject(ActivityMessage.self, value: $0) },
    .init(name: "ActivityChannel", required: ["id", "type", "voice_states", "messages"], nullable: ["guild_id", "name", "topic", "bitrate", "user_limit", "position"], wrong: ["id": .bool(false), "type": .bool(false), "guild_id": .bool(false), "name": .bool(false), "topic": .bool(false), "bitrate": .bool(false), "user_limit": .bool(false), "position": .bool(false), "voice_states": .string("wrong-type"), "messages": .string("wrong-type")]) { try activityCatalogProject(ActivityChannel.self, value: $0) },
 ]

/// Creates realistic, nested SDK fixture objects with large IDs, unknown enum values and sensitive sentinel strings.
/// - Parameter name: Concrete projection type from the finite test matrix.
/// - Returns: A complete valid object, including optional fields, with deterministic typed children.
/// - Throws: JSON number grammar errors, or an explicit fixture error if a registered name has no data.
private func activityCatalogFixture(_ name: String) throws -> JSONValue {
    switch name {
    case "ActivityAuthorization": return .object([
            "code": .string("sensitive-sentinel")
        ])
    case "ActivityApplication": return .object([
            "description": .string("sensitive-sentinel"),
            "icon": .string("sensitive-sentinel"),
            "id": .string("18446744073709551615"),
            "rpc_origins": .array([.string("sensitive-sentinel")]),
            "name": .string("sensitive-sentinel")
        ])
    case "ActivityAuthenticatedUser": return .object([
            "username": .string("sensitive-sentinel"),
            "discriminator": .string("sensitive-sentinel"),
            "id": .string("18446744073709551615"),
            "avatar": .string("sensitive-sentinel"),
            "public_flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "global_name": .string("sensitive-sentinel")
        ])
    case "ActivityAuthentication": return .object([
            "access_token": .string("sensitive-sentinel"),
            "user": try activityCatalogFixture("ActivityAuthenticatedUser"),
            "scopes": .array([.string("future-scalar")]),
            "expires": .string("sensitive-sentinel"),
            "application": try activityCatalogFixture("ActivityApplication")
        ])
    case "ActivityAvatarDecoration": return .object([
            "asset": .string("sensitive-sentinel"),
            "sku_id": .string("18446744073709551615")
        ])
    case "ActivityParticipantDecoration": return .object([
            "asset": .string("sensitive-sentinel"),
            "skuId": .string("sensitive-sentinel"),
            "expiresAt": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityUser": return .object([
            "id": .string("18446744073709551615"),
            "username": .string("sensitive-sentinel"),
            "discriminator": .string("sensitive-sentinel"),
            "global_name": .string("sensitive-sentinel"),
            "avatar": .string("sensitive-sentinel"),
            "avatar_decoration_data": try activityCatalogFixture("ActivityAvatarDecoration"),
            "bot": .bool(true),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "premium_type": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityParticipant": return .object([
            "id": .string("18446744073709551615"),
            "username": .string("sensitive-sentinel"),
            "global_name": .string("sensitive-sentinel"),
            "discriminator": .string("sensitive-sentinel"),
            "avatar": .string("sensitive-sentinel"),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "bot": .bool(true),
            "avatar_decoration_data": try activityCatalogFixture("ActivityParticipantDecoration"),
            "premium_type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "nickname": .string("sensitive-sentinel")
        ])
    case "ActivityParticipants": return .object([
            "participants": .array([try activityCatalogFixture("ActivityParticipant")])
        ])
    case "ActivityGuildMember": return .object([
            "user": try activityCatalogFixture("ActivityUser"),
            "nick": .string("sensitive-sentinel"),
            "roles": .array([.string("sensitive-sentinel")]),
            "joined_at": .string("sensitive-sentinel"),
            "deaf": .bool(true),
            "mute": .bool(true)
        ])
    case "ActivityMemberDecoration": return .object([
            "asset": .string("sensitive-sentinel"),
            "sku_id": .string("18446744073709551615")
        ])
    case "ActivityGuildMemberUpdate": return .object([
            "user_id": .string("18446744073709551615"),
            "nick": .string("sensitive-sentinel"),
            "guild_id": .string("18446744073709551615"),
            "avatar": .string("sensitive-sentinel"),
            "avatar_decoration_data": try activityCatalogFixture("ActivityMemberDecoration"),
            "color_string": .string("sensitive-sentinel")
        ])
    case "ActivityVoiceState": return .object([
            "mute": .bool(true),
            "deaf": .bool(true),
            "self_mute": .bool(true),
            "self_deaf": .bool(true),
            "suppress": .bool(true)
        ])
    case "ActivityUserVoiceState": return .object([
            "mute": .bool(true),
            "nick": .string("sensitive-sentinel"),
            "user": try activityCatalogFixture("ActivityUser"),
            "voice_state": try activityCatalogFixture("ActivityVoiceState"),
            "volume": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityEmoji": return .object([
            "id": .string("18446744073709551615"),
            "name": .string("sensitive-sentinel"),
            "roles": .array([.string("sensitive-sentinel")]),
            "user": try activityCatalogFixture("ActivityUser"),
            "require_colons": .bool(true),
            "managed": .bool(true),
            "animated": .bool(true),
            "available": .bool(true)
        ])
    case "ActivityTimestamps": return .object([
            "start": .number(try JSONNumber(rawValue: "9007199254740993")),
            "end": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityParty": return .object([
            "id": .string("18446744073709551615"),
            "size": .array([.number(try JSONNumber(rawValue: "9007199254740993")), .number(try JSONNumber(rawValue: "9007199254740993"))])
        ])
    case "ActivityAssets": return .object([
            "large_image": .string("sensitive-sentinel"),
            "large_text": .string("sensitive-sentinel"),
            "large_url": .string("https://example.com/large"),
            "small_image": .string("sensitive-sentinel"),
            "small_text": .string("sensitive-sentinel"),
            "small_url": .string("https://example.com/small")
        ])
    case "ActivitySecrets": return .object([
            "join": .string("sensitive-sentinel"),
            "match": .string("sensitive-sentinel")
        ])
    case "ActivityRichPresence": return .object([
            "name": .string("sensitive-sentinel"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "url": .string("sensitive-sentinel"),
            "created_at": .number(try JSONNumber(rawValue: "9007199254740993")),
            "timestamps": try activityCatalogFixture("ActivityTimestamps"),
            "application_id": .string("18446744073709551615"),
            "details": .string("sensitive-sentinel"),
            "details_url": .string("https://example.com/details"),
            "state": .string("sensitive-sentinel"),
            "state_url": .string("https://example.com/state"),
            "emoji": try activityCatalogFixture("ActivityEmoji"),
            "party": try activityCatalogFixture("ActivityParty"),
            "assets": try activityCatalogFixture("ActivityAssets"),
            "secrets": try activityCatalogFixture("ActivitySecrets"),
            "instance": .bool(true),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityPresenceEmoji": return .object([
            "name": .string("sensitive-sentinel"),
            "id": .string("18446744073709551615"),
            "animated": .bool(true)
        ])
    case "ActivityPresenceAssets": return .object([
            "large_image": .string("sensitive-sentinel"),
            "large_text": .string("sensitive-sentinel"),
            "large_url": .string("https://example.com/large"),
            "small_image": .string("sensitive-sentinel"),
            "small_text": .string("sensitive-sentinel"),
            "small_url": .string("https://example.com/small")
        ])
    case "ActivityPresenceParty": return .object([
            "id": .string("18446744073709551615"),
            "size": .array([.number(try JSONNumber(rawValue: "9007199254740993")), .number(try JSONNumber(rawValue: "9007199254740993"))]),
            "privacy": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityPresenceActivity": return .object([
            "session_id": .string("sensitive-sentinel"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "name": .string("sensitive-sentinel"),
            "url": .string("sensitive-sentinel"),
            "application_id": .string("18446744073709551615"),
            "status_display_type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "state": .string("sensitive-sentinel"),
            "state_url": .string("https://example.com/state"),
            "details": .string("sensitive-sentinel"),
            "details_url": .string("https://example.com/details"),
            "emoji": try activityCatalogFixture("ActivityPresenceEmoji"),
            "assets": try activityCatalogFixture("ActivityPresenceAssets"),
            "timestamps": try activityCatalogFixture("ActivityTimestamps"),
            "party": try activityCatalogFixture("ActivityPresenceParty"),
            "secrets": try activityCatalogFixture("ActivitySecrets"),
            "sync_id": .string("sensitive-sentinel"),
            "created_at": .number(try JSONNumber(rawValue: "9007199254740993")),
            "instance": .bool(true),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "metadata": try activityCatalogFixture("ActivityMetadata"),
            "platform": .string("sensitive-sentinel"),
            "supported_platforms": .array([.string("sensitive-sentinel")]),
            "buttons": .array([.string("sensitive-sentinel")]),
            "hangStatus": .string("sensitive-sentinel")
        ])
    case "ActivityMetadata": return .object([:])
    case "ActivityPresence": return .object([
            "status": .string("sensitive-sentinel"),
            "activity": try activityCatalogFixture("ActivityPresenceActivity")
        ])
    case "ActivityRelationship": return .object([
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "user": try activityCatalogFixture("ActivityParticipant"),
            "presence": try activityCatalogFixture("ActivityPresence")
        ])
    case "ActivityRelationships": return .object([
            "relationships": .array([try activityCatalogFixture("ActivityRelationship")])
        ])
    case "ActivityPrice": return .object([
            "amount": .number(try JSONNumber(rawValue: "9007199254740993")),
            "currency": .string("sensitive-sentinel")
        ])
    case "ActivitySKU": return .object([
            "id": .string("18446744073709551615"),
            "name": .string("sensitive-sentinel"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "price": try activityCatalogFixture("ActivityPrice"),
            "application_id": .string("18446744073709551615"),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "release_date": .string("sensitive-sentinel")
        ])
    case "ActivitySKUs": return .object([
            "skus": .array([try activityCatalogFixture("ActivitySKU")])
        ])
    case "ActivityEntitlement": return .object([
            "id": .string("18446744073709551615"),
            "sku_id": .string("18446744073709551615"),
            "application_id": .string("18446744073709551615"),
            "user_id": .string("18446744073709551615"),
            "gift_code_flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "gifter_user_id": .string("sensitive-sentinel"),
            "branches": .array([.string("sensitive-sentinel")]),
            "starts_at": .string("sensitive-sentinel"),
            "ends_at": .string("sensitive-sentinel"),
            "parent_id": .string("sensitive-sentinel"),
            "consumed": .bool(true),
            "deleted": .bool(true),
            "gift_code_batch_id": .string("sensitive-sentinel")
        ])
    case "ActivityEntitlements": return .object([
            "entitlements": .array([try activityCatalogFixture("ActivityEntitlement")])
        ])
    case "ActivityPermissions": return .object([
            "permissions": .string("18446744073709551616000")
        ])
    case "ActivityPlatformBehaviors": return .object([
            "iosKeyboardResizesView": .bool(true)
        ])
    case "ActivityExternalLink": return .object([
            "opened": .bool(true)
        ])
    case "ActivityConfig": return .object([
            "use_interactive_pip": .bool(true)
        ])
    case "ActivityLocale": return .object([
            "locale": .string("sensitive-sentinel")
        ])
    case "ActivityHardwareAcceleration": return .object([
            "enabled": .bool(true)
        ])
    case "ActivityQuest": return .object([
            "quest_id": .string("sensitive-sentinel"),
            "enrolled_at": .string("sensitive-sentinel"),
            "completed_at": .string("sensitive-sentinel"),
            "external_cta_url": .string("sensitive-sentinel")
        ])
    case "ActivityQuestEnrollment": return .object([
            "quest_id": .string("sensitive-sentinel"),
            "is_enrolled": .bool(true),
            "enrolled_at": .string("sensitive-sentinel")
        ])
    case "ActivityQuestEnrollmentUpdate": return .object([
            "quest_id": .string("sensitive-sentinel"),
            "is_enrolled": .bool(true),
            "enrolled_at": .string("2024-02-29")
        ])
    case "ActivityImageUpload": return .object([
            "image_url": .string("sensitive-sentinel")
        ])
    case "ActivityProxyTicket": return .object([
            "ticket": .string("sensitive-sentinel")
        ])
    case "ActivitySuccess": return .object([
            "success": .bool(true)
        ])
    case "ActivityShareLink": return .object([
            "success": .bool(true),
            "didCopyLink": .bool(true),
            "didSendMessage": .bool(true)
        ])
    case "ActivityReadyConfig": return .object([
            "cdn_host": .string("sensitive-sentinel"),
            "api_endpoint": .string("sensitive-sentinel"),
            "environment": .string("sensitive-sentinel")
        ])
    case "ActivityReadyUser": return .object([
            "id": .string("18446744073709551615"),
            "username": .string("sensitive-sentinel"),
            "discriminator": .string("sensitive-sentinel"),
            "avatar": .string("sensitive-sentinel")
        ])
    case "ActivityReady": return .object([
            "v": .number(try JSONNumber(rawValue: "9007199254740993")),
            "config": try activityCatalogFixture("ActivityReadyConfig"),
            "user": try activityCatalogFixture("ActivityReadyUser")
        ])
    case "ActivitySpeaking": return .object([
            "lobby_id": .string("sensitive-sentinel"),
            "channel_id": .string("18446744073709551615"),
            "user_id": .string("18446744073709551615")
        ])
    case "ActivityLayoutUpdate": return .object([
            "layout_mode": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityOrientationUpdate": return .object([
            "screen_orientation": .number(try JSONNumber(rawValue: "9007199254740993")),
            "orientation": .string("sensitive-sentinel")
        ])
    case "ActivityThermalUpdate": return .object([
            "thermal_state": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityEntitlementCreate": return .object([
            "entitlement": try activityCatalogFixture("ActivityEntitlement")
        ])
    case "ActivityJoin": return .object([
            "applicationId": .string("sensitive-sentinel"),
            "secret": .string("sensitive-sentinel")
        ])
    case "ActivityHostError": return .object([
            "code": .number(try JSONNumber(rawValue: "9007199254740993")),
            "message": .string("sensitive-sentinel")
        ])
    case "ActivitySubscriptionResponse": return .object([
            "evt": .string("sensitive-sentinel")
        ])
    case "ActivityChannelMention": return .object([
            "id": .string("18446744073709551615"),
            "guild_id": .string("18446744073709551615"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "name": .string("sensitive-sentinel")
        ])
    case "ActivityAttachment": return .object([
            "id": .string("18446744073709551615"),
            "filename": .string("sensitive-sentinel"),
            "size": .number(try JSONNumber(rawValue: "9007199254740993")),
            "url": .string("sensitive-sentinel"),
            "proxy_url": .string("sensitive-sentinel"),
            "height": .number(try JSONNumber(rawValue: "9007199254740993")),
            "width": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityEmbedFooter": return .object([
            "text": .string("sensitive-sentinel"),
            "icon_url": .string("sensitive-sentinel"),
            "proxy_icon_url": .string("sensitive-sentinel")
        ])
    case "ActivityImage": return .object([
            "url": .string("sensitive-sentinel"),
            "proxy_url": .string("sensitive-sentinel"),
            "height": .number(try JSONNumber(rawValue: "9007199254740993")),
            "width": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityVideo": return .object([
            "url": .string("sensitive-sentinel"),
            "height": .number(try JSONNumber(rawValue: "9007199254740993")),
            "width": .number(try JSONNumber(rawValue: "9007199254740993"))
        ])
    case "ActivityEmbedProvider": return .object([
            "name": .string("sensitive-sentinel"),
            "url": .string("sensitive-sentinel")
        ])
    case "ActivityEmbedAuthor": return .object([
            "name": .string("sensitive-sentinel"),
            "url": .string("sensitive-sentinel"),
            "icon_url": .string("sensitive-sentinel"),
            "proxy_icon_url": .string("sensitive-sentinel")
        ])
    case "ActivityEmbedField": return .object([
            "name": .string("sensitive-sentinel"),
            "value": .string("sensitive-sentinel"),
            "inline": .bool(true)
        ])
    case "ActivityEmbed": return .object([
            "title": .string("sensitive-sentinel"),
            "type": .string("sensitive-sentinel"),
            "description": .string("sensitive-sentinel"),
            "url": .string("sensitive-sentinel"),
            "timestamp": .string("sensitive-sentinel"),
            "color": .number(try JSONNumber(rawValue: "9007199254740993")),
            "footer": try activityCatalogFixture("ActivityEmbedFooter"),
            "image": try activityCatalogFixture("ActivityImage"),
            "thumbnail": try activityCatalogFixture("ActivityImage"),
            "video": try activityCatalogFixture("ActivityVideo"),
            "provider": try activityCatalogFixture("ActivityEmbedProvider"),
            "author": try activityCatalogFixture("ActivityEmbedAuthor"),
            "fields": .array([try activityCatalogFixture("ActivityEmbedField")])
        ])
    case "ActivityReaction": return .object([
            "count": .number(try JSONNumber(rawValue: "9007199254740993")),
            "me": .bool(true),
            "emoji": try activityCatalogFixture("ActivityEmoji")
        ])
    case "ActivityMessageActivity": return .object([
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "party_id": .string("sensitive-sentinel")
        ])
    case "ActivityMessageApplication": return .object([
            "id": .string("18446744073709551615"),
            "cover_image": .string("sensitive-sentinel"),
            "description": .string("sensitive-sentinel"),
            "icon": .string("sensitive-sentinel"),
            "name": .string("sensitive-sentinel")
        ])
    case "ActivityMessageReference": return .object([
            "message_id": .string("sensitive-sentinel"),
            "channel_id": .string("18446744073709551615"),
            "guild_id": .string("18446744073709551615")
        ])
    case "ActivityMessage": return .object([
            "id": .string("18446744073709551615"),
            "channel_id": .string("18446744073709551615"),
            "guild_id": .string("18446744073709551615"),
            "author": try activityCatalogFixture("ActivityUser"),
            "member": try activityCatalogFixture("ActivityGuildMember"),
            "content": .string("sensitive-sentinel"),
            "timestamp": .string("sensitive-sentinel"),
            "edited_timestamp": .string("sensitive-sentinel"),
            "tts": .bool(true),
            "mention_everyone": .bool(true),
            "mentions": .array([try activityCatalogFixture("ActivityUser")]),
            "mention_roles": .array([.string("sensitive-sentinel")]),
            "mention_channels": .array([try activityCatalogFixture("ActivityChannelMention")]),
            "attachments": .array([try activityCatalogFixture("ActivityAttachment")]),
            "embeds": .array([try activityCatalogFixture("ActivityEmbed")]),
            "reactions": .array([try activityCatalogFixture("ActivityReaction")]),
            "nonce": .string("future-scalar"),
            "pinned": .bool(true),
            "webhook_id": .string("sensitive-sentinel"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "activity": try activityCatalogFixture("ActivityMessageActivity"),
            "application": try activityCatalogFixture("ActivityMessageApplication"),
            "message_reference": try activityCatalogFixture("ActivityMessageReference"),
            "flags": .number(try JSONNumber(rawValue: "9007199254740993")),
            "stickers": .array([.string("future-scalar")]),
            "referenced_message": .string("future-scalar")
        ])
    case "ActivityChannel": return .object([
            "id": .string("18446744073709551615"),
            "type": .number(try JSONNumber(rawValue: "9007199254740993")),
            "guild_id": .string("18446744073709551615"),
            "name": .string("sensitive-sentinel"),
            "topic": .string("sensitive-sentinel"),
            "bitrate": .number(try JSONNumber(rawValue: "9007199254740993")),
            "user_limit": .number(try JSONNumber(rawValue: "9007199254740993")),
            "position": .number(try JSONNumber(rawValue: "9007199254740993")),
            "voice_states": .array([try activityCatalogFixture("ActivityUserVoiceState")]),
            "messages": .array([try activityCatalogFixture("ActivityMessage")])
        ])
    default: throw ActivityCatalogError.invalidPayload
    }
}

@Suite("ActivityCatalogTests")
struct ActivityCatalogTests {
    /// Every modeled field rejects omission/null/type errors according to the pinned schema, while unknown values round trip.
    /// All fixtures are deterministic and local; no Discord service, token, bridge or wall-clock sleeps are used.
    @Test(arguments: activityCatalogFixtures)
    private func typedResponsesRejectMalformedValues(_ fixture: ActivityCatalogFixture) throws {
        guard case .object(var fields) = try activityCatalogFixture(fixture.name) else {
            Issue.record("Fixture must be an object"); return
        }
        let number = try JSONNumber(rawValue: "1.2300e1000")
        fields["future_unknown"] = .object(["precise": .number(number)])
        #expect(try fixture.project(.object(fields)) == fields)
        for key in fields.keys where key != "future_unknown" {
            var omitted = fields; omitted.removeValue(forKey: key)
            if fixture.required.contains(key) {
                #expect(throws: ActivityCatalogError.invalidPayload) { try fixture.project(.object(omitted)) }
            } else { #expect(try fixture.project(.object(omitted)) == omitted) }
            var nulled = fields; nulled[key] = .null
            if fixture.nullable.contains(key) {
                #expect(try fixture.project(.object(nulled)) == nulled)
            } else { #expect(throws: ActivityCatalogError.invalidPayload) { try fixture.project(.object(nulled)) } }
            if let bad = fixture.wrong[key] {
                var malformed = fields; malformed[key] = bad
                #expect(throws: ActivityCatalogError.invalidPayload) { try fixture.project(.object(malformed)) }
            }
        }
        for invalid: JSONValue in [.null, .array([]), .string("secret"), .bool(true)] {
            #expect(throws: ActivityCatalogError.invalidPayload) { try fixture.project(invalid) }
        }
    }
}

/// Checks typed and bounded byte construction, exact raw fields, equality and diagnostic redaction for every object type.
/// - Parameters:
///   - type: Concrete public object projection under test.
///   - value: Already-bounded fixture, including future keys and exact numeric lexemes.
/// - Returns: Original fields only after all public construction paths agree.
/// - Throws: Expected projection/JSON errors for malformed inputs; callers assert those errors explicitly.
private func activityCatalogProject<P: ActivityPayload>(_ type: P.Type, value: JSONValue) throws -> [String: JSONValue] {
    let result = try P(value: value)
    let fromBytes = try P(data: value.serialized())
    #expect(result == fromBytes)
    #expect(!result.description.contains("sensitive-sentinel"))
    #expect(!result.debugDescription.contains("sensitive-sentinel"))
    #expect(result.customMirror.children.count == 1)
    return result.rawFields
}

/// Asserts exact request identity, response decoding and default redaction without executing a bridge operation.
/// - Parameters:
///   - request: Factory descriptor whose associated response type must compile at the call site.
///   - command: Exact expected wire command.
///   - arguments: Complete expected argument object; omission matters.
///   - response: Valid deterministic response data subtree, including null/array variants.
/// - Throws: Any construction/decoding error, which fails the calling Swift Testing case.
private func activityCatalogRequest<R>(_ request: ActivityRequest<R>, command: ActivityCommand,
    arguments: [String: JSONValue] = [:], response: JSONValue) throws {
    #expect(request.command == command)
    #expect(request.arguments == arguments)
    #expect(request.event == nil)
    _ = try request.decode(response)
    _ = try request.decode(data: response.serialized())
    #expect(!request.description.contains("sensitive-sentinel"))
    #expect(request.debugDescription == request.description)
    #expect(request.customMirror.children.count == 2)
    #expect(throws: (any Error).self) { try request.decode(.bool(false)) }
}

extension ActivityCatalogTests {
    /// Every actual SDK export has a typed factory, exact command/argument mapping and executable typed response codec.
    /// The historical participant name maps to the same wire command, without inventing an additional SDK operation.
    @Test func allExportedCommandsHaveTypedFactories() throws {
        try activityCatalogRequest(ActivityRequests.authorize(clientID: "app", scopes: ["identify"]), command: .authorize,
            arguments: ["client_id": .string("app"), "scope": .array([.string("identify")]), "response_type": .string("code")],
            response: activityCatalogFixture("ActivityAuthorization"))
        try activityCatalogRequest(ActivityRequests.authenticate(), command: .authenticate, response: activityCatalogFixture("ActivityAuthentication"))
        try activityCatalogRequest(ActivityRequests.captureLog(level: .info, message: "message"), command: .captureLog,
            arguments: ["level": .string("info"), "message": .string("message")], response: .null)
        try activityCatalogRequest(ActivityRequests.encourageHardwareAcceleration(), command: .encourageHardwareAcceleration, response: activityCatalogFixture("ActivityHardwareAcceleration"))
        try activityCatalogRequest(ActivityRequests.getChannel(channelID: "18446744073709551615"), command: .getChannel,
            arguments: ["channel_id": .string("18446744073709551615")], response: activityCatalogFixture("ActivityChannel"))
        try activityCatalogRequest(ActivityRequests.getChannelPermissions(), command: .getChannelPermissions, response: activityCatalogFixture("ActivityPermissions"))
        try activityCatalogRequest(ActivityRequests.getEntitlements(), command: .getEntitlements, response: activityCatalogFixture("ActivityEntitlements"))
        try activityCatalogRequest(ActivityRequests.getPlatformBehaviors(), command: .getPlatformBehaviors, response: activityCatalogFixture("ActivityPlatformBehaviors"))
        try activityCatalogRequest(ActivityRequests.getSkus(), command: .getSkus, response: activityCatalogFixture("ActivitySKUs"))
        try activityCatalogRequest(ActivityRequests.openExternalLink(url: "https://example.com"), command: .openExternalLink,
            arguments: ["url": .string("https://example.com")], response: .object(["opened": .bool(false)]))
        try activityCatalogRequest(ActivityRequests.openInviteDialog(), command: .openInviteDialog, response: .null)
        try activityCatalogRequest(ActivityRequests.setActivity(activity: .null), command: .setActivity,
            arguments: ["activity": .null], response: activityCatalogFixture("ActivityRichPresence"))
        try activityCatalogRequest(ActivityRequests.setConfig(useInteractivePIP: false), command: .setConfig,
            arguments: ["use_interactive_pip": .bool(false)], response: .object(["use_interactive_pip": .bool(false)]))
        try activityCatalogRequest(ActivityRequests.setOrientationLockState(.unlocked), command: .setOrientationLockState,
            arguments: ["lock_state": try activityInteger(1)], response: .null)
        try activityCatalogRequest(ActivityRequests.startPurchase(skuID: "sku"), command: .startPurchase,
            arguments: ["sku_id": .string("sku")], response: .array([]))
        try activityCatalogRequest(ActivityRequests.userSettingsGetLocale(), command: .userSettingsGetLocale, response: activityCatalogFixture("ActivityLocale"))
        try activityCatalogRequest(ActivityRequests.getActivityInstanceConnectedParticipants(), command: .getActivityInstanceConnectedParticipants, response: activityCatalogFixture("ActivityParticipants"))
        try activityCatalogRequest(ActivityRequests.getQuest(), command: .getQuest, response: activityCatalogFixture("ActivityQuest"))
        try activityCatalogRequest(ActivityRequests.getQuestEnrollmentStatus(questID: "quest"), command: .getQuestEnrollmentStatus,
            arguments: ["quest_id": .string("quest")], response: activityCatalogFixture("ActivityQuestEnrollment"))
        try activityCatalogRequest(ActivityRequests.getRelationships(), command: .getRelationships, response: activityCatalogFixture("ActivityRelationships"))
        try activityCatalogRequest(ActivityRequests.getUser(id: "user"), command: .getUser,
            arguments: ["id": .string("user")], response: .null)
        try activityCatalogRequest(ActivityRequests.initiateImageUpload(), command: .initiateImageUpload, response: activityCatalogFixture("ActivityImageUpload"))
        try activityCatalogRequest(ActivityRequests.inviteUserEmbedded(userID: "user"), command: .inviteUserEmbedded,
            arguments: ["user_id": .string("user")], response: .object([:]))
        try activityCatalogRequest(ActivityRequests.openShareMomentDialog(mediaURL: "https://cdn.discordapp.com/media"), command: .openShareMomentDialog,
            arguments: ["mediaUrl": .string("https://cdn.discordapp.com/media")], response: .null)
        try activityCatalogRequest(ActivityRequests.questStartTimer(questID: "quest"), command: .questStartTimer,
            arguments: ["quest_id": .string("quest")], response: .object(["success": .bool(true)]))
        try activityCatalogRequest(ActivityRequests.requestProxyTicketRefresh(), command: .requestProxyTicketRefresh, response: activityCatalogFixture("ActivityProxyTicket"))
        try activityCatalogRequest(ActivityRequests.shareInteraction(command: "play"), command: .shareInteraction,
            arguments: ["command": .string("play")], response: .object(["success": .bool(true)]))
        try activityCatalogRequest(ActivityRequests.shareLink(message: "hello"), command: .shareLink,
            arguments: ["message": .string("hello")], response: activityCatalogFixture("ActivityShareLink"))
        #expect(ActivityCommand.exported.count == 28)
        #expect(Set(ActivityCommand.exported).count == 28)
        #expect(ActivityCommand.allCases.count == 30)
        let alias = try ActivityRequests.getInstanceConnectedParticipants()
        #expect(alias.command == .getActivityInstanceConnectedParticipants)
        #expect(alias.arguments.isEmpty)
        #expect(try alias.decode(activityCatalogFixture("ActivityParticipants")).participants.count == 1)
    }

    /// Every known dispatch and ERROR has a typed data projection; new names retain arbitrary data without normalization.
    @Test func allExportedEventsHaveTypedProjections() throws {
        let cases: [(ActivityEventName, String)] = [
            (.ready, "ActivityReady"), (.voiceStateUpdate, "ActivityUserVoiceState"),
            (.speakingStart, "ActivitySpeaking"), (.speakingStop, "ActivitySpeaking"),
            (.activityLayoutModeUpdate, "ActivityLayoutUpdate"), (.orientationUpdate, "ActivityOrientationUpdate"),
            (.currentUserUpdate, "ActivityUser"), (.currentGuildMemberUpdate, "ActivityGuildMemberUpdate"),
            (.entitlementCreate, "ActivityEntitlementCreate"), (.thermalStateUpdate, "ActivityThermalUpdate"),
            (.activityInstanceParticipantsUpdate, "ActivityParticipants"), (.relationshipUpdate, "ActivityRelationship"),
            (.activityJoin, "ActivityJoin"), (.questEnrollmentStatusUpdate, "ActivityQuestEnrollmentUpdate"),
            (.error, "ActivityHostError")
        ]
        #expect(Set(cases.map(\.0)).subtracting([.error]) == Set(ActivityEventName.exported))
        for (name, fixture) in cases {
            let value = try activityCatalogFixture(fixture)
            let event = try ActivityEventPayload(name: name, value: value)
            #expect(event == (try ActivityEventPayload(name: name, value: value)))
            #expect(event.description == "ActivityEventPayload(redacted)")
            #expect(event.debugDescription == event.description)
            #expect(event.customMirror.children.count == 1)
            #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityEventPayload(name: name, value: .null) }
        }
        let name = ActivityEventName(rawValue: "FUTURE_EVENT")
        let value = try JSONValue.parse("[1.2300e1000,null,{\"secret\":\"sensitive-sentinel\"}]")
        #expect(try ActivityEventPayload(name: name, value: value) == .unknown(name: name, value: value))
    }

    /// Metadata distinguishes documented host/scopes from source-only exports and current terms/preview constraints.
    @Test func catalogAvailabilityAndScopeEvidenceRemainBounded() {
        for platform in ActivityHostPlatform.allCases {
            #expect(ActivityCommand.getChannel.availability(on: platform) == .documentedSupported)
            #expect(ActivityCommand.getQuest.availability(on: platform) == .sourceOnly)
            #expect(ActivityEventName.ready.availability(on: platform) == .documentedSupported)
            #expect(ActivityEventName.relationshipUpdate.availability(on: platform) == .sourceOnly)
            #expect(ActivityCommand.setConfig.availability(on: platform) == (platform == .web ? .documentedSupported : .unsupported))
            #expect(ActivityCommand.setOrientationLockState.availability(on: platform) == (platform == .web ? .unsupported : .documentedSupported))
        }
        #expect(ActivityCommand.getChannel.requiredScopes == ["guilds"])
        #expect(ActivityCommand.getChannelPermissions.requiredScopes == ["guilds.members.read"])
        #expect(ActivityCommand.setActivity.requiredScopes == ["rpc.activities.write"])
        #expect(ActivityCommand.userSettingsGetLocale.requiredScopes == ["identify"])
        #expect(ActivityCommand.getRelationships.requiresSocialSDKTerms)
        #expect(ActivityCommand.authorize.scopesAreDocumented)
        #expect(!ActivityCommand.getUser.scopesAreDocumented)
        #expect(ActivityEventName.currentUserUpdate.requiredScopes == ["identify"])
        #expect(ActivityEventName.currentGuildMemberUpdate.requiredScopes == ["identify", "guilds.members.read"])
        #expect(ActivityEventName.speakingStart.requiredScopes == ["rpc.voice.read"])
        #expect(ActivityEventName.relationshipUpdate.requiredScopes == ["relationships.read"])
        #expect(ActivityEventName.entitlementCreate.unavailableDuringDeveloperPreview)
        #expect(!ActivityEventName.questEnrollmentStatusUpdate.scopesAreDocumented)
        #expect(!ActivityEventName(rawValue: "FUTURE_EVENT").scopesAreDocumented)
        #expect(ActivityLogLevel.allCases.count == 5)
        #expect(ActivityOrientationLockState.allCases.map(\.rawValue) == [1, 2, 3])
    }

    /// Credential and descriptor constructors reject invalid inputs, enforce whole-object bounds and redact reflection.
    @Test func requestBoundsCredentialsAndSubscriptionRules() throws {
        let token = try ActivityUserAccessToken(oauthAccessToken: "sensitive-sentinel")
        #expect(token.description == "ActivityUserAccessToken(redacted)")
        #expect(token.debugDescription == token.description)
        #expect(token.customMirror.children.count == 1)
        for invalid in ["", "has space", "Bot token", "Bearer token", "line\nfeed", "é", String(repeating: "x", count: 16_385)] {
            #expect(throws: ActivityCatalogError.invalidAccessToken) { try ActivityUserAccessToken(oauthAccessToken: invalid) }
        }
        _ = try ActivityUserAccessToken(oauthAccessToken: String(repeating: "x", count: 16_384))
        let auth = try ActivityRequests.authenticate(accessToken: .value(token))
        #expect(auth.arguments == ["access_token": .string("sensitive-sentinel")])
        #expect(try ActivityRequests.authenticate(accessToken: .null).arguments == ["access_token": .null])
        #expect(try ActivityRequests.authenticate().arguments.isEmpty)
        let bounded: ActivityRequest<JSONValue> = try .init(command: .getQuest) { $0 }
        #expect(try bounded.decode(.null) == .null)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try bounded.decode(data: Data("{}".utf8), limits: JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.duplicateKey(byteOffset: 7)) { try bounded.decode(data: Data("{\"a\":1,\"a\":2}".utf8)) }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try ActivityRequest<JSONValue>(command: .getQuest, arguments: ["large": .string("payload")], limits: JSONLimits(maximumBytes: 2)) { $0 }
        }
        for command in [ActivityCommand.subscribe, .unsubscribe] {
            for invalid in [nil, .ready, .error, ActivityEventName(rawValue: ""), ActivityEventName(rawValue: "bad\nname"), ActivityEventName(rawValue: String(repeating: "a", count: 129))] as [ActivityEventName?] {
                #expect(throws: ActivityCatalogError.invalidArguments) {
                    try ActivityRequest<JSONValue>(command: command, event: invalid) { $0 }
                }
            }
            let valid = try ActivityRequest<JSONValue>(command: command, arguments: ["channel_id": .string("channel")], event: .voiceStateUpdate) { $0 }
            #expect(valid.event == .voiceStateUpdate)
        }
        #expect(throws: ActivityCatalogError.invalidArguments) {
            try ActivityRequest<JSONValue>(command: .getQuest, event: .speakingStart) { $0 }
        }
    }

    /// Authorization, presence, orientation and purchase fields preserve omission/null and exact numeric wire data.
    @Test func typedRequestPresenceAndCompatibilityShapes() throws {
        let authorization = try ActivityRequests.authorize(clientID: "app", scopes: [], codeChallenge: .value("challenge"),
            state: .value("state"), responseTypeCode: false, promptNone: true)
        #expect(authorization.arguments == ["client_id": .string("app"), "scope": .array([]), "code_challenge": .string("challenge"),
            "code_challenge_method": .string("S256"), "state": .string("state"), "prompt": .string("none")])
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.authorize(clientID: "app", scopes: [], state: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.authorize(clientID: "app", scopes: [], codeChallenge: .null) }
        let timestamp = try ActivityTimestamps(value: .object(["start": .number(JSONNumber(rawValue: "9007199254740993"))]))
        let assets = try ActivityAssets(value: .object(["large_image": .string("asset")]))
        let party = try ActivityParty(value: .object(["size": .array([])]))
        let secrets = try ActivitySecrets(value: .object(["join": .string("sensitive-sentinel")]))
        let presence = try ActivityPresenceUpdate(state: .null, stateURL: .value("https://example.com/state"), details: .value("details"),
            detailsURL: .null, timestamps: .value(timestamp), assets: .value(assets), party: .value(party),
            secrets: .value(secrets), instance: .value(true), type: .value(JSONNumber(rawValue: "789")))
        #expect(presence.rawFields["state"] == .null)
        #expect(presence.rawFields["details_url"] == .null)
        #expect(presence.rawFields["timestamps"] == .object(timestamp.rawFields))
        #expect(presence.rawFields["assets"] == .object(assets.rawFields))
        #expect(presence.rawFields["party"] == .object(party.rawFields))
        #expect(presence.rawFields["secrets"] == .object(secrets.rawFields))
        #expect(try ActivityRequests.setActivity(activity: .value(presence)).arguments == ["activity": .object(presence.rawFields)])
        #expect(try ActivityPresenceUpdate().rawFields.isEmpty)
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityPresenceUpdate(type: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityPresenceUpdate(stateURL: .value("relative/path")) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityPresenceUpdate(detailsURL: .value("")) }
        #expect(presence.description == "ActivityPresenceUpdate(redacted)")
        #expect(presence.debugDescription == presence.description)
        #expect(presence.customMirror.children.count == 1)
        let orientation = try ActivityRequests.setOrientationLockState(.portrait, pictureInPictureLockState: .null, gridLockState: .value(.landscape))
        #expect(orientation.arguments == ["lock_state": try activityInteger(2), "picture_in_picture_lock_state": .null, "grid_lock_state": try activityInteger(3)])
        let legacy = try ActivityRequests.setOrientationLockState(.landscape, gridLockState: .value(.portrait), omitGridForLegacyHost: true)
        #expect(legacy.arguments == ["lock_state": try activityInteger(3)])
        let pid = try JSONNumber(rawValue: "1.25")
        #expect(try ActivityRequests.startPurchase(skuID: "sku", pid: .value(pid)).arguments["pid"] == .number(pid))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.startPurchase(skuID: "sku", pid: .null) }
    }

    /// Generated string limits follow JavaScript UTF-16 counts, including supplementary emoji and exact boundaries.
    @Test func stringLimitsAndShareComponentBranches() throws {
        _ = try ActivityRequests.getUser(id: String(repeating: "x", count: 64))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.getUser(id: String(repeating: "x", count: 65)) }
        _ = try ActivityRequests.getUser(id: String(repeating: "😀", count: 32))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.getUser(id: String(repeating: "😀", count: 33)) }
        _ = try ActivityRequests.openShareMomentDialog(mediaURL: String(repeating: "x", count: 1024))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.openShareMomentDialog(mediaURL: String(repeating: "x", count: 1025)) }
        _ = try ActivityRequests.inviteUserEmbedded(userID: "id", content: .value(String(repeating: "x", count: 1024)))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.inviteUserEmbedded(userID: "id", content: .value(String(repeating: "x", count: 1025))) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.inviteUserEmbedded(userID: "id", content: .null) }
        _ = try ActivityRequests.shareLink(message: String(repeating: "x", count: 1000), customID: .value(String(repeating: "x", count: 64)), linkID: .value(String(repeating: "x", count: 64)))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareLink(message: String(repeating: "x", count: 1001)) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareLink(message: "", customID: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareLink(message: "", linkID: .value(String(repeating: "x", count: 65))) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareLink(message: "", customID: .value(String(repeating: "x", count: 65))) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareLink(message: "", linkID: .null) }
        let button = try ActivityShareButton(style: 5, label: .value(String(repeating: "x", count: 80)), customID: .value(String(repeating: "x", count: 100)))
        let row = try ActivityShareRow(buttons: .value(Array(repeating: button, count: 5)))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 0) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 6) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 1, label: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 1, customID: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 1, label: .value(String(repeating: "x", count: 81))) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareButton(style: 1, customID: .value(String(repeating: "x", count: 101))) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareRow(buttons: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityShareRow(buttons: .value(Array(repeating: button, count: 6))) }
        let option = ActivityShareOption(name: "name", value: "value")
        let preview = ActivitySharePreview(height: try JSONNumber(rawValue: "1.5"), url: "url", width: try JSONNumber(rawValue: "2"))
        let shared = try ActivityRequests.shareInteraction(command: "play", options: .value([option]), content: .value(String(repeating: "x", count: 2000)),
            requireLaunchChannel: .value(false), previewImage: .value(preview), components: .value([row]), pid: .value(JSONNumber(rawValue: "12")))
        #expect(shared.arguments["options"] == .array([.object(["name": .string("name"), "value": .string("value")])]))
        #expect(shared.arguments["preview_image"] == .object(["height": .number(preview.height), "url": .string("url"), "width": .number(preview.width)]))
        #expect(shared.arguments["require_launch_channel"] == .bool(false))
        #expect(shared.arguments["pid"] == .number(try JSONNumber(rawValue: "12")))
        guard case .array(let rows) = shared.arguments["components"], case .object(let fields) = rows.first,
              case .array(let buttons) = fields["components"], case .object(let first) = buttons.first else {
            Issue.record("Expected typed action row and buttons"); return
        }
        #expect(fields["type"] == (try activityInteger(1)))
        #expect(first["type"] == (try activityInteger(2)))
        #expect(first["style"] == (try activityInteger(5)))
        #expect(buttons.count == 5)
        #expect(first["label"] == .string(String(repeating: "x", count: 80)))
        #expect(first["custom_id"] == .string(String(repeating: "x", count: 100)))
        let emptyRow = try ActivityShareRow()
        let minimalButton = try ActivityShareButton(style: 1)
        _ = try ActivityRequests.shareInteraction(command: "", components: .value([emptyRow, ActivityShareRow(buttons: .value([minimalButton]))]))
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", options: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", content: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", requireLaunchChannel: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", previewImage: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", components: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", pid: .null) }
        #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityRequests.shareInteraction(command: "", content: .value(String(repeating: "x", count: 2001))) }
    }

    /// Nullable top-level responses, large bitsets and precise unknown values remain lossless and diagnostics redact data.
    @Test func nullableResponsesPrecisionAndTypedFieldValues() throws {
        let empty = try ActivityEmptyResponse(value: .object(["secret": .string("sensitive-sentinel")]))
        #expect(empty.value == .value(["secret": .string("sensitive-sentinel")]))
        #expect(try ActivityEmptyResponse(value: .null).value == .null)
        #expect(empty.debugDescription == empty.description)
        #expect(empty.customMirror.children.count == 1)
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityEmptyResponse(value: .array([])) }
        let purchase = try ActivityPurchaseResponse(value: .array([activityCatalogFixture("ActivityEntitlement")]))
        if case .value(let values) = purchase.entitlements { #expect(values.count == 1); #expect(values[0].id == "18446744073709551615") }
        else { Issue.record("Expected entitlements") }
        #expect(try ActivityPurchaseResponse(value: .null).entitlements == .null)
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityPurchaseResponse(value: .array([.null])) }
        #expect(purchase.description == purchase.debugDescription)
        #expect(purchase.customMirror.children.count == 1)
        let user = try ActivityUserResponse(value: activityCatalogFixture("ActivityParticipant"))
        if case .value(let participant) = user.user { #expect(participant.id == "18446744073709551615"); #expect(participant.bot) }
        else { Issue.record("Expected participant") }
        #expect(user.description == user.debugDescription)
        #expect(user.customMirror.children.count == 1)
        #expect(try ActivityUserResponse(value: .null).user == .null)
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityUserResponse(value: .string("bad")) }
        for value: JSONValue in [.string("18446744073709551616000"), .number(try JSONNumber(rawValue: "18446744073709551616000")), .string("0")] {
            let permissions = try ActivityPermissionValue(value: value)
            #expect(permissions.rawValue == value)
            #expect(!permissions.decimalRepresentation.isEmpty)
            #expect(permissions.description == permissions.debugDescription)
            #expect(permissions.customMirror.children.count == 1)
        }
        for invalid: JSONValue in [.string(""), .string("1e3"), .string("-1"), .string("１２"), .number(try JSONNumber(rawValue: "1.0")), .bool(true)] {
            #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityPermissionValue(value: invalid) }
        }
        let result = try ActivityRequests.openExternalLink(url: "url").decode(.null)
        #expect(result.opened == .null)
        let absent = try ActivityPlatformBehaviors(value: .object([:]))
        #expect(absent.iosKeyboardResizesView == .absent)
        let enrollment = try ActivityQuestEnrollment(value: .object(["quest_id": .string("q"), "is_enrolled": .bool(false), "enrolled_at": .null]))
        #expect(enrollment.enrolledAt == .null)
        #expect(!enrollment.isEnrolled)
        let raw = try JSONValue.parse("{\"name\":\"test\",\"type\":9007199254740993,\"details\":null,\"new\":1.2300e1000}")
        let presence = try ActivityRichPresence(value: raw)
        #expect(presence.name == "test")
        #expect(presence.type.rawValue == "9007199254740993")
        #expect(presence.details == .null)
        #expect(presence.state == .absent)
        #expect(presence.rawFields["new"] == .number(try JSONNumber(rawValue: "1.2300e1000")))
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityPresenceParty(value: .object(["size": .array([])])) }
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityMessage(value: .object([:])) }
        let authentication = try ActivityAuthentication(value: activityCatalogFixture("ActivityAuthentication"))
        #expect(authentication.accessToken == "sensitive-sentinel")
        #expect(authentication.user.publicFlags.rawValue == "9007199254740993")
        #expect(authentication.application.id == "18446744073709551615")
    }
}

extension ActivityCatalogTests {
    /// Source-only quest event dates validate Gregorian leap years and exact date spelling without depending on time zones.
    @Test func questDatesScopeUnionsAndSensitiveComponents() throws {
        for valid in ["2024-02-29", "2000-02-29", "2026-10-17", "0000-02-29", "9999-12-31"] {
            let event = try ActivityQuestEnrollmentUpdate(value: .object(["quest_id": .string("q"), "is_enrolled": .bool(true), "enrolled_at": .string(valid)]))
            #expect(event.enrolledAt == valid)
        }
        for invalid in ["1900-02-29", "2025-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "2026-01-00", "2026-1-01", "", "2026-10-17T00:00:00Z", "２０２６-10-17"] {
            #expect(throws: ActivityCatalogError.invalidPayload) {
                try ActivityQuestEnrollmentUpdate(value: .object(["quest_id": .string("q"), "is_enrolled": .bool(true), "enrolled_at": .string(invalid)]))
            }
        }
        for value: JSONValue in [.string("future.scope"), .number(try JSONNumber(rawValue: "-1")), .number(try JSONNumber(rawValue: "9007199254740993"))] {
            #expect(try ActivityOAuthScope(value: value).rawValue == value)
        }
        for invalid: JSONValue in [.null, .bool(true), .array([]), .object([:])] {
            #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityOAuthScope(value: invalid) }
            guard case .object(var fields) = try activityCatalogFixture("ActivityAuthentication") else { return }
            fields["scopes"] = .array([invalid])
            #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityAuthentication(value: .object(fields)) }
        }
        let option = ActivityShareOption(name: "secret", value: "sensitive-sentinel")
        let preview = ActivitySharePreview(height: try JSONNumber(rawValue: "1"), url: "sensitive-sentinel", width: try JSONNumber(rawValue: "2"))
        let button = try ActivityShareButton(style: 1, label: .value("sensitive-sentinel"))
        let row = try ActivityShareRow(buttons: .value([button]))
        for component in [option, preview, button, row] as [any ActivityRequestPayload] {
            #expect(component.description == "ActivityRequestPayload(redacted)")
            #expect(component.debugDescription == component.description)
            #expect(component.customMirror.children.count == 1)
        }
        #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityAssets(value: .object(["large_url": .string("relative/path")])) }
        #expect(throws: ActivityCatalogError.invalidPayload) {
            try ActivityRichPresence(value: .object(["name": .string("game"), "type": .number(JSONNumber(rawValue: "0")), "state_url": .string("relative/path")]))
        }
        #expect(throws: ActivityCatalogError.invalidPayload) {
            try ActivityRichPresence(value: .object(["name": .string("game"), "type": .number(JSONNumber(rawValue: "0")), "details_url": .string("")]))
        }
    }
}
