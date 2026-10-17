import DiscordCore
import Foundation


/// Every documented Gateway v10 dispatch name, verified 2026-10-16 against the official event reference.
/// Hello, Reconnect and Invalid Session are opcodes, not named dispatches. Raw strings retain future names.
public enum GatewayDispatchName: String, Sendable, CaseIterable {
    /// Official `READY` dispatch.
    case ready = "READY"
    /// Official `RESUMED` dispatch.
    case resumed = "RESUMED"
    /// Official `RATE_LIMITED` dispatch.
    case rateLimited = "RATE_LIMITED"
    /// Official `APPLICATION_COMMAND_PERMISSIONS_UPDATE` dispatch.
    case applicationCommandPermissionsUpdate = "APPLICATION_COMMAND_PERMISSIONS_UPDATE"
    /// Official `AUTO_MODERATION_RULE_CREATE` dispatch.
    case autoModerationRuleCreate = "AUTO_MODERATION_RULE_CREATE"
    /// Official `AUTO_MODERATION_RULE_UPDATE` dispatch.
    case autoModerationRuleUpdate = "AUTO_MODERATION_RULE_UPDATE"
    /// Official `AUTO_MODERATION_RULE_DELETE` dispatch.
    case autoModerationRuleDelete = "AUTO_MODERATION_RULE_DELETE"
    /// Official `AUTO_MODERATION_ACTION_EXECUTION` dispatch.
    case autoModerationActionExecution = "AUTO_MODERATION_ACTION_EXECUTION"
    /// Official `CHANNEL_CREATE` dispatch.
    case channelCreate = "CHANNEL_CREATE"
    /// Official `CHANNEL_UPDATE` dispatch.
    case channelUpdate = "CHANNEL_UPDATE"
    /// Official `CHANNEL_DELETE` dispatch.
    case channelDelete = "CHANNEL_DELETE"
    /// Official `CHANNEL_INFO` dispatch.
    case channelInfo = "CHANNEL_INFO"
    /// Official `CHANNEL_PINS_UPDATE` dispatch.
    case channelPinsUpdate = "CHANNEL_PINS_UPDATE"
    /// Official `THREAD_CREATE` dispatch.
    case threadCreate = "THREAD_CREATE"
    /// Official `THREAD_UPDATE` dispatch.
    case threadUpdate = "THREAD_UPDATE"
    /// Official `THREAD_DELETE` dispatch.
    case threadDelete = "THREAD_DELETE"
    /// Official `THREAD_LIST_SYNC` dispatch.
    case threadListSync = "THREAD_LIST_SYNC"
    /// Official `THREAD_MEMBER_UPDATE` dispatch.
    case threadMemberUpdate = "THREAD_MEMBER_UPDATE"
    /// Official `THREAD_MEMBERS_UPDATE` dispatch.
    case threadMembersUpdate = "THREAD_MEMBERS_UPDATE"
    /// Official `ENTITLEMENT_CREATE` dispatch.
    case entitlementCreate = "ENTITLEMENT_CREATE"
    /// Official `ENTITLEMENT_UPDATE` dispatch.
    case entitlementUpdate = "ENTITLEMENT_UPDATE"
    /// Official `ENTITLEMENT_DELETE` dispatch.
    case entitlementDelete = "ENTITLEMENT_DELETE"
    /// Official `GUILD_CREATE` dispatch.
    case guildCreate = "GUILD_CREATE"
    /// Official `GUILD_UPDATE` dispatch.
    case guildUpdate = "GUILD_UPDATE"
    /// Official `GUILD_DELETE` dispatch.
    case guildDelete = "GUILD_DELETE"
    /// Official `GUILD_AUDIT_LOG_ENTRY_CREATE` dispatch.
    case guildAuditLogEntryCreate = "GUILD_AUDIT_LOG_ENTRY_CREATE"
    /// Official `GUILD_BAN_ADD` dispatch.
    case guildBanAdd = "GUILD_BAN_ADD"
    /// Official `GUILD_BAN_REMOVE` dispatch.
    case guildBanRemove = "GUILD_BAN_REMOVE"
    /// Official `GUILD_EMOJIS_UPDATE` dispatch.
    case guildEmojisUpdate = "GUILD_EMOJIS_UPDATE"
    /// Official `GUILD_STICKERS_UPDATE` dispatch.
    case guildStickersUpdate = "GUILD_STICKERS_UPDATE"
    /// Official `GUILD_INTEGRATIONS_UPDATE` dispatch.
    case guildIntegrationsUpdate = "GUILD_INTEGRATIONS_UPDATE"
    /// Official `GUILD_MEMBER_ADD` dispatch.
    case guildMemberAdd = "GUILD_MEMBER_ADD"
    /// Official `GUILD_MEMBER_REMOVE` dispatch.
    case guildMemberRemove = "GUILD_MEMBER_REMOVE"
    /// Official `GUILD_MEMBER_UPDATE` dispatch.
    case guildMemberUpdate = "GUILD_MEMBER_UPDATE"
    /// Official `GUILD_MEMBERS_CHUNK` dispatch.
    case guildMembersChunk = "GUILD_MEMBERS_CHUNK"
    /// Official `GUILD_ROLE_CREATE` dispatch.
    case guildRoleCreate = "GUILD_ROLE_CREATE"
    /// Official `GUILD_ROLE_UPDATE` dispatch.
    case guildRoleUpdate = "GUILD_ROLE_UPDATE"
    /// Official `GUILD_ROLE_DELETE` dispatch.
    case guildRoleDelete = "GUILD_ROLE_DELETE"
    /// Official `GUILD_SCHEDULED_EVENT_CREATE` dispatch.
    case guildScheduledEventCreate = "GUILD_SCHEDULED_EVENT_CREATE"
    /// Official `GUILD_SCHEDULED_EVENT_UPDATE` dispatch.
    case guildScheduledEventUpdate = "GUILD_SCHEDULED_EVENT_UPDATE"
    /// Official `GUILD_SCHEDULED_EVENT_DELETE` dispatch.
    case guildScheduledEventDelete = "GUILD_SCHEDULED_EVENT_DELETE"
    /// Official `GUILD_SCHEDULED_EVENT_USER_ADD` dispatch.
    case guildScheduledEventUserAdd = "GUILD_SCHEDULED_EVENT_USER_ADD"
    /// Official `GUILD_SCHEDULED_EVENT_USER_REMOVE` dispatch.
    case guildScheduledEventUserRemove = "GUILD_SCHEDULED_EVENT_USER_REMOVE"
    /// Official `GUILD_SOUNDBOARD_SOUND_CREATE` dispatch.
    case guildSoundboardSoundCreate = "GUILD_SOUNDBOARD_SOUND_CREATE"
    /// Official `GUILD_SOUNDBOARD_SOUND_UPDATE` dispatch.
    case guildSoundboardSoundUpdate = "GUILD_SOUNDBOARD_SOUND_UPDATE"
    /// Official `GUILD_SOUNDBOARD_SOUND_DELETE` dispatch.
    case guildSoundboardSoundDelete = "GUILD_SOUNDBOARD_SOUND_DELETE"
    /// Official `GUILD_SOUNDBOARD_SOUNDS_UPDATE` dispatch.
    case guildSoundboardSoundsUpdate = "GUILD_SOUNDBOARD_SOUNDS_UPDATE"
    /// Official `SOUNDBOARD_SOUNDS` dispatch.
    case soundboardSounds = "SOUNDBOARD_SOUNDS"
    /// Official `INTEGRATION_CREATE` dispatch.
    case integrationCreate = "INTEGRATION_CREATE"
    /// Official `INTEGRATION_UPDATE` dispatch.
    case integrationUpdate = "INTEGRATION_UPDATE"
    /// Official `INTEGRATION_DELETE` dispatch.
    case integrationDelete = "INTEGRATION_DELETE"
    /// Official `INTERACTION_CREATE` dispatch.
    case interactionCreate = "INTERACTION_CREATE"
    /// Official `INVITE_CREATE` dispatch.
    case inviteCreate = "INVITE_CREATE"
    /// Official `INVITE_DELETE` dispatch.
    case inviteDelete = "INVITE_DELETE"
    /// Official `MESSAGE_CREATE` dispatch.
    case messageCreate = "MESSAGE_CREATE"
    /// Official `MESSAGE_UPDATE` dispatch.
    case messageUpdate = "MESSAGE_UPDATE"
    /// Official `MESSAGE_DELETE` dispatch.
    case messageDelete = "MESSAGE_DELETE"
    /// Official `MESSAGE_DELETE_BULK` dispatch.
    case messageDeleteBulk = "MESSAGE_DELETE_BULK"
    /// Official `MESSAGE_REACTION_ADD` dispatch.
    case messageReactionAdd = "MESSAGE_REACTION_ADD"
    /// Official `MESSAGE_REACTION_REMOVE` dispatch.
    case messageReactionRemove = "MESSAGE_REACTION_REMOVE"
    /// Official `MESSAGE_REACTION_REMOVE_ALL` dispatch.
    case messageReactionRemoveAll = "MESSAGE_REACTION_REMOVE_ALL"
    /// Official `MESSAGE_REACTION_REMOVE_EMOJI` dispatch.
    case messageReactionRemoveEmoji = "MESSAGE_REACTION_REMOVE_EMOJI"
    /// Official `PRESENCE_UPDATE` dispatch.
    case presenceUpdate = "PRESENCE_UPDATE"
    /// Official `STAGE_INSTANCE_CREATE` dispatch.
    case stageInstanceCreate = "STAGE_INSTANCE_CREATE"
    /// Official `STAGE_INSTANCE_UPDATE` dispatch.
    case stageInstanceUpdate = "STAGE_INSTANCE_UPDATE"
    /// Official `STAGE_INSTANCE_DELETE` dispatch.
    case stageInstanceDelete = "STAGE_INSTANCE_DELETE"
    /// Official `SUBSCRIPTION_CREATE` dispatch.
    case subscriptionCreate = "SUBSCRIPTION_CREATE"
    /// Official `SUBSCRIPTION_UPDATE` dispatch.
    case subscriptionUpdate = "SUBSCRIPTION_UPDATE"
    /// Official `SUBSCRIPTION_DELETE` dispatch.
    case subscriptionDelete = "SUBSCRIPTION_DELETE"
    /// Official `TYPING_START` dispatch.
    case typingStart = "TYPING_START"
    /// Official `USER_UPDATE` dispatch.
    case userUpdate = "USER_UPDATE"
    /// Official `VOICE_CHANNEL_EFFECT_SEND` dispatch.
    case voiceChannelEffectSend = "VOICE_CHANNEL_EFFECT_SEND"
    /// Official `VOICE_CHANNEL_START_TIME_UPDATE` dispatch.
    case voiceChannelStartTimeUpdate = "VOICE_CHANNEL_START_TIME_UPDATE"
    /// Official `VOICE_CHANNEL_STATUS_UPDATE` dispatch.
    case voiceChannelStatusUpdate = "VOICE_CHANNEL_STATUS_UPDATE"
    /// Official `VOICE_STATE_UPDATE` dispatch.
    case voiceStateUpdate = "VOICE_STATE_UPDATE"
    /// Official `VOICE_SERVER_UPDATE` dispatch.
    case voiceServerUpdate = "VOICE_SERVER_UPDATE"
    /// Official `WEBHOOKS_UPDATE` dispatch.
    case webhooksUpdate = "WEBHOOKS_UPDATE"
    /// Official `MESSAGE_POLL_VOTE_ADD` dispatch.
    case messagePollVoteAdd = "MESSAGE_POLL_VOTE_ADD"
    /// Official `MESSAGE_POLL_VOTE_REMOVE` dispatch.
    case messagePollVoteRemove = "MESSAGE_POLL_VOTE_REMOVE"
}

/// Typed current Gateway dispatch catalog with a lossless future-name fallback.
/// Cases are boxed to keep dispatch values and async task stack use bounded across this large catalog.
/// Payload values are immutable Sendable snapshots. Per-shard ordering, intent visibility, permission gates,
/// replay/duplicate handling and request correlation remain runtime responsibilities. API v10, verified 2026-10-16.
/// https://docs.discord.com/developers/events/gateway-events
public indirect enum GatewayDispatch: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// `READY`; see the payload type for presence and resource limitations.
    case ready(GatewayReady)
    /// `RESUMED`; see the payload type for presence and resource limitations.
    case resumed(GatewayResumed)
    /// `RATE_LIMITED`; see the payload type for presence and resource limitations.
    case rateLimited(GatewayRateLimited)
    /// `APPLICATION_COMMAND_PERMISSIONS_UPDATE`; see the payload type for presence and resource limitations.
    case applicationCommandPermissionsUpdate(GuildApplicationCommandPermissions)
    /// `AUTO_MODERATION_RULE_CREATE`; see the payload type for presence and resource limitations.
    case autoModerationRuleCreate(AutoModerationRule)
    /// `AUTO_MODERATION_RULE_UPDATE`; see the payload type for presence and resource limitations.
    case autoModerationRuleUpdate(AutoModerationRule)
    /// `AUTO_MODERATION_RULE_DELETE`; see the payload type for presence and resource limitations.
    case autoModerationRuleDelete(AutoModerationRule)
    /// `AUTO_MODERATION_ACTION_EXECUTION`; see the payload type for presence and resource limitations.
    case autoModerationActionExecution(GatewayAutoModerationActionExecution)
    /// `CHANNEL_CREATE`; see the payload type for presence and resource limitations.
    case channelCreate(Channel)
    /// `CHANNEL_UPDATE`; see the payload type for presence and resource limitations.
    case channelUpdate(Channel)
    /// `CHANNEL_DELETE`; see the payload type for presence and resource limitations.
    case channelDelete(Channel)
    /// `CHANNEL_INFO`; see the payload type for presence and resource limitations.
    case channelInfo(GatewayChannelInfo)
    /// `CHANNEL_PINS_UPDATE`; see the payload type for presence and resource limitations.
    case channelPinsUpdate(GatewayChannelPinsUpdate)
    /// `THREAD_CREATE`; see the payload type for presence and resource limitations.
    case threadCreate(GatewayThreadCreate)
    /// `THREAD_UPDATE`; see the payload type for presence and resource limitations.
    case threadUpdate(Channel)
    /// `THREAD_DELETE`; see the payload type for presence and resource limitations.
    case threadDelete(GatewayThreadDelete)
    /// `THREAD_LIST_SYNC`; see the payload type for presence and resource limitations.
    case threadListSync(GatewayThreadListSync)
    /// `THREAD_MEMBER_UPDATE`; see the payload type for presence and resource limitations.
    case threadMemberUpdate(GatewayThreadMemberUpdate)
    /// `THREAD_MEMBERS_UPDATE`; see the payload type for presence and resource limitations.
    case threadMembersUpdate(GatewayThreadMembersUpdate)
    /// `ENTITLEMENT_CREATE`; see the payload type for presence and resource limitations.
    case entitlementCreate(Entitlement)
    /// `ENTITLEMENT_UPDATE`; see the payload type for presence and resource limitations.
    case entitlementUpdate(Entitlement)
    /// `ENTITLEMENT_DELETE`; see the payload type for presence and resource limitations.
    case entitlementDelete(Entitlement)
    /// `GUILD_CREATE`; see the payload type for presence and resource limitations.
    case guildCreate(GatewayGuildCreate)
    /// `GUILD_UPDATE`; see the payload type for presence and resource limitations.
    case guildUpdate(Guild)
    /// `GUILD_DELETE`; see the payload type for presence and resource limitations.
    case guildDelete(GatewayGuildAvailability)
    /// `GUILD_AUDIT_LOG_ENTRY_CREATE`; see the payload type for presence and resource limitations.
    case guildAuditLogEntryCreate(GatewayGuildAuditLogEntryCreate)
    /// `GUILD_BAN_ADD`; see the payload type for presence and resource limitations.
    case guildBanAdd(GatewayGuildUser)
    /// `GUILD_BAN_REMOVE`; see the payload type for presence and resource limitations.
    case guildBanRemove(GatewayGuildUser)
    /// `GUILD_EMOJIS_UPDATE`; see the payload type for presence and resource limitations.
    case guildEmojisUpdate(GatewayGuildEmojisUpdate)
    /// `GUILD_STICKERS_UPDATE`; see the payload type for presence and resource limitations.
    case guildStickersUpdate(GatewayGuildStickersUpdate)
    /// `GUILD_INTEGRATIONS_UPDATE`; see the payload type for presence and resource limitations.
    case guildIntegrationsUpdate(GatewayGuildIntegrationsUpdate)
    /// `GUILD_MEMBER_ADD`; see the payload type for presence and resource limitations.
    case guildMemberAdd(GatewayGuildMemberAdd)
    /// `GUILD_MEMBER_REMOVE`; see the payload type for presence and resource limitations.
    case guildMemberRemove(GatewayGuildUser)
    /// `GUILD_MEMBER_UPDATE`; see the payload type for presence and resource limitations.
    case guildMemberUpdate(GatewayGuildMemberUpdate)
    /// `GUILD_MEMBERS_CHUNK`; see the payload type for presence and resource limitations.
    case guildMembersChunk(GatewayGuildMembersChunk)
    /// `GUILD_ROLE_CREATE`; see the payload type for presence and resource limitations.
    case guildRoleCreate(GatewayGuildRoleUpdate)
    /// `GUILD_ROLE_UPDATE`; see the payload type for presence and resource limitations.
    case guildRoleUpdate(GatewayGuildRoleUpdate)
    /// `GUILD_ROLE_DELETE`; see the payload type for presence and resource limitations.
    case guildRoleDelete(GatewayGuildRoleDelete)
    /// `GUILD_SCHEDULED_EVENT_CREATE`; see the payload type for presence and resource limitations.
    case guildScheduledEventCreate(GuildScheduledEvent)
    /// `GUILD_SCHEDULED_EVENT_UPDATE`; see the payload type for presence and resource limitations.
    case guildScheduledEventUpdate(GuildScheduledEvent)
    /// `GUILD_SCHEDULED_EVENT_DELETE`; see the payload type for presence and resource limitations.
    case guildScheduledEventDelete(GuildScheduledEvent)
    /// `GUILD_SCHEDULED_EVENT_USER_ADD`; see the payload type for presence and resource limitations.
    case guildScheduledEventUserAdd(GatewayScheduledEventUser)
    /// `GUILD_SCHEDULED_EVENT_USER_REMOVE`; see the payload type for presence and resource limitations.
    case guildScheduledEventUserRemove(GatewayScheduledEventUser)
    /// `GUILD_SOUNDBOARD_SOUND_CREATE`; see the payload type for presence and resource limitations.
    case guildSoundboardSoundCreate(SoundboardSound)
    /// `GUILD_SOUNDBOARD_SOUND_UPDATE`; see the payload type for presence and resource limitations.
    case guildSoundboardSoundUpdate(SoundboardSound)
    /// `GUILD_SOUNDBOARD_SOUND_DELETE`; see the payload type for presence and resource limitations.
    case guildSoundboardSoundDelete(GatewayGuildSoundboardSoundDelete)
    /// `GUILD_SOUNDBOARD_SOUNDS_UPDATE`; see the payload type for presence and resource limitations.
    case guildSoundboardSoundsUpdate(GatewaySoundboardSounds)
    /// `SOUNDBOARD_SOUNDS`; see the payload type for presence and resource limitations.
    case soundboardSounds(GatewaySoundboardSounds)
    /// `INTEGRATION_CREATE`; see the payload type for presence and resource limitations.
    case integrationCreate(GatewayIntegrationUpdate)
    /// `INTEGRATION_UPDATE`; see the payload type for presence and resource limitations.
    case integrationUpdate(GatewayIntegrationUpdate)
    /// `INTEGRATION_DELETE`; see the payload type for presence and resource limitations.
    case integrationDelete(GatewayIntegrationDelete)
    /// `INTERACTION_CREATE`; see the payload type for presence and resource limitations.
    case interactionCreate(Interaction)
    /// `INVITE_CREATE`; see the payload type for presence and resource limitations.
    case inviteCreate(GatewayInviteCreate)
    /// `INVITE_DELETE`; see the payload type for presence and resource limitations.
    case inviteDelete(GatewayInviteDelete)
    /// `MESSAGE_CREATE`; see the payload type for presence and resource limitations.
    case messageCreate(GatewayMessageCreate)
    /// `MESSAGE_UPDATE`; see the payload type for presence and resource limitations.
    case messageUpdate(GatewayMessageUpdate)
    /// `MESSAGE_DELETE`; see the payload type for presence and resource limitations.
    case messageDelete(GatewayMessageDelete)
    /// `MESSAGE_DELETE_BULK`; see the payload type for presence and resource limitations.
    case messageDeleteBulk(GatewayMessageDeleteBulk)
    /// `MESSAGE_REACTION_ADD`; see the payload type for presence and resource limitations.
    case messageReactionAdd(GatewayMessageReactionAdd)
    /// `MESSAGE_REACTION_REMOVE`; see the payload type for presence and resource limitations.
    case messageReactionRemove(GatewayMessageReactionRemove)
    /// `MESSAGE_REACTION_REMOVE_ALL`; see the payload type for presence and resource limitations.
    case messageReactionRemoveAll(GatewayMessageReactionRemoveAll)
    /// `MESSAGE_REACTION_REMOVE_EMOJI`; see the payload type for presence and resource limitations.
    case messageReactionRemoveEmoji(GatewayMessageReactionRemoveEmoji)
    /// `PRESENCE_UPDATE`; see the payload type for presence and resource limitations.
    case presenceUpdate(GatewayPresenceUpdate)
    /// `STAGE_INSTANCE_CREATE`; see the payload type for presence and resource limitations.
    case stageInstanceCreate(StageInstance)
    /// `STAGE_INSTANCE_UPDATE`; see the payload type for presence and resource limitations.
    case stageInstanceUpdate(StageInstance)
    /// `STAGE_INSTANCE_DELETE`; see the payload type for presence and resource limitations.
    case stageInstanceDelete(StageInstance)
    /// `SUBSCRIPTION_CREATE`; see the payload type for presence and resource limitations.
    case subscriptionCreate(Subscription)
    /// `SUBSCRIPTION_UPDATE`; see the payload type for presence and resource limitations.
    case subscriptionUpdate(Subscription)
    /// `SUBSCRIPTION_DELETE`; see the payload type for presence and resource limitations.
    case subscriptionDelete(Subscription)
    /// `TYPING_START`; see the payload type for presence and resource limitations.
    case typingStart(GatewayTypingStart)
    /// `USER_UPDATE`; see the payload type for presence and resource limitations.
    case userUpdate(User)
    /// `VOICE_CHANNEL_EFFECT_SEND`; see the payload type for presence and resource limitations.
    case voiceChannelEffectSend(GatewayVoiceChannelEffect)
    /// `VOICE_CHANNEL_START_TIME_UPDATE`; see the payload type for presence and resource limitations.
    case voiceChannelStartTimeUpdate(GatewayVoiceChannelStartTimeUpdate)
    /// `VOICE_CHANNEL_STATUS_UPDATE`; see the payload type for presence and resource limitations.
    case voiceChannelStatusUpdate(GatewayVoiceChannelStatusUpdate)
    /// `VOICE_STATE_UPDATE`; see the payload type for presence and resource limitations.
    case voiceStateUpdate(VoiceState)
    /// `VOICE_SERVER_UPDATE`; see the payload type for presence and resource limitations.
    case voiceServerUpdate(GatewayVoiceServerUpdate)
    /// `WEBHOOKS_UPDATE`; see the payload type for presence and resource limitations.
    case webhooksUpdate(GatewayWebhooksUpdate)
    /// `MESSAGE_POLL_VOTE_ADD`; see the payload type for presence and resource limitations.
    case messagePollVoteAdd(GatewayMessagePollVote)
    /// `MESSAGE_POLL_VOTE_REMOVE`; see the payload type for presence and resource limitations.
    case messagePollVoteRemove(GatewayMessagePollVote)
    /// An unrecognized exact event name and arbitrary data, including scalar/null future payloads.
    case unknown(name: String, data: JSONValue)

    /// Parses a complete bounded dispatch payload, retaining unknown fields and future names.
    /// - Parameters:
    ///   - name: Exact case-sensitive wire event name. Unknown spellings remain accessible unchanged.
    ///   - data: Complete UTF-8 JSON event data, excluding the Gateway envelope.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown fields; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for malformed
    ///   current typed payloads. Unknown names accept any bounded JSON root. No I/O or suspension occurs.
    public init(name: String, data: Data, limits: JSONLimits = .default) throws {
        try self.init(validatedName: name, value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an existing JSON tree after enforcing caller-selected whole-tree bounds.
    /// - Parameters:
    ///   - name: Exact case-sensitive dispatch name; unknown values are preserved.
    ///   - value: Immutable event-data tree, including unknown numeric spellings.
    ///   - limits: Serialization bounds validated before projection; defaults to standard JSON bounds.
    /// - Throws: JSON bound/limit errors or sanitized invalid-response errors for malformed current payloads.
    /// This synchronous operation serializes once to establish bounds; it performs no network, task or cache work.
    public init(name: String, value: JSONValue, limits: JSONLimits = .default) throws {
        _ = try value.serialized(limits: limits)
        try self.init(validatedName: name, value: value, limits: limits)
    }

    /// Selects the current typed schema after complete outer bounds have already been validated.
    /// - Parameters:
    ///   - validatedName: Exact wire event name; it need not be a known enum value.
    ///   - value: Original immutable tree with established whole-document bounds.
    ///   - limits: Those established bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a malformed known event; unknown names never reject schema.
    private init(validatedName: String, value: JSONValue, limits: JSONLimits) throws {
        switch GatewayDispatchName(rawValue: validatedName) {
        case .ready: self = .ready(try GatewayReady(value: value, limits: limits))
        case .resumed: self = .resumed(try GatewayResumed(value: value, limits: limits))
        case .rateLimited: self = .rateLimited(try GatewayRateLimited(value: value, limits: limits))
        case .applicationCommandPermissionsUpdate: self = .applicationCommandPermissionsUpdate(try GuildApplicationCommandPermissions(value: value, limits: limits))
        case .autoModerationRuleCreate: self = .autoModerationRuleCreate(try AutoModerationRule(value: value, limits: limits))
        case .autoModerationRuleUpdate: self = .autoModerationRuleUpdate(try AutoModerationRule(value: value, limits: limits))
        case .autoModerationRuleDelete: self = .autoModerationRuleDelete(try AutoModerationRule(value: value, limits: limits))
        case .autoModerationActionExecution: self = .autoModerationActionExecution(try GatewayAutoModerationActionExecution(value: value, limits: limits))
        case .channelCreate: self = .channelCreate(try Channel(value: value, limits: limits))
        case .channelUpdate: self = .channelUpdate(try Channel(value: value, limits: limits))
        case .channelDelete: self = .channelDelete(try Channel(value: value, limits: limits))
        case .channelInfo: self = .channelInfo(try GatewayChannelInfo(value: value, limits: limits))
        case .channelPinsUpdate: self = .channelPinsUpdate(try GatewayChannelPinsUpdate(value: value, limits: limits))
        case .threadCreate: self = .threadCreate(try GatewayThreadCreate(value: value, limits: limits))
        case .threadUpdate: self = .threadUpdate(try Channel(value: value, limits: limits))
        case .threadDelete: self = .threadDelete(try GatewayThreadDelete(value: value, limits: limits))
        case .threadListSync: self = .threadListSync(try GatewayThreadListSync(value: value, limits: limits))
        case .threadMemberUpdate: self = .threadMemberUpdate(try GatewayThreadMemberUpdate(value: value, limits: limits))
        case .threadMembersUpdate: self = .threadMembersUpdate(try GatewayThreadMembersUpdate(value: value, limits: limits))
        case .entitlementCreate: self = .entitlementCreate(try Entitlement(value: value, limits: limits))
        case .entitlementUpdate: self = .entitlementUpdate(try Entitlement(value: value, limits: limits))
        case .entitlementDelete: self = .entitlementDelete(try Entitlement(value: value, limits: limits))
        case .guildCreate: self = .guildCreate(try GatewayGuildCreate(value: value, limits: limits))
        case .guildUpdate: self = .guildUpdate(try Guild(value: value, limits: limits))
        case .guildDelete: self = .guildDelete(try GatewayGuildAvailability(value: value, limits: limits))
        case .guildAuditLogEntryCreate: self = .guildAuditLogEntryCreate(try GatewayGuildAuditLogEntryCreate(value: value, limits: limits))
        case .guildBanAdd: self = .guildBanAdd(try GatewayGuildUser(value: value, limits: limits))
        case .guildBanRemove: self = .guildBanRemove(try GatewayGuildUser(value: value, limits: limits))
        case .guildEmojisUpdate: self = .guildEmojisUpdate(try GatewayGuildEmojisUpdate(value: value, limits: limits))
        case .guildStickersUpdate: self = .guildStickersUpdate(try GatewayGuildStickersUpdate(value: value, limits: limits))
        case .guildIntegrationsUpdate: self = .guildIntegrationsUpdate(try GatewayGuildIntegrationsUpdate(value: value, limits: limits))
        case .guildMemberAdd: self = .guildMemberAdd(try GatewayGuildMemberAdd(value: value, limits: limits))
        case .guildMemberRemove: self = .guildMemberRemove(try GatewayGuildUser(value: value, limits: limits))
        case .guildMemberUpdate: self = .guildMemberUpdate(try GatewayGuildMemberUpdate(value: value, limits: limits))
        case .guildMembersChunk: self = .guildMembersChunk(try GatewayGuildMembersChunk(value: value, limits: limits))
        case .guildRoleCreate: self = .guildRoleCreate(try GatewayGuildRoleUpdate(value: value, limits: limits))
        case .guildRoleUpdate: self = .guildRoleUpdate(try GatewayGuildRoleUpdate(value: value, limits: limits))
        case .guildRoleDelete: self = .guildRoleDelete(try GatewayGuildRoleDelete(value: value, limits: limits))
        case .guildScheduledEventCreate: self = .guildScheduledEventCreate(try GuildScheduledEvent(value: value, limits: limits))
        case .guildScheduledEventUpdate: self = .guildScheduledEventUpdate(try GuildScheduledEvent(value: value, limits: limits))
        case .guildScheduledEventDelete: self = .guildScheduledEventDelete(try GuildScheduledEvent(value: value, limits: limits))
        case .guildScheduledEventUserAdd: self = .guildScheduledEventUserAdd(try GatewayScheduledEventUser(value: value, limits: limits))
        case .guildScheduledEventUserRemove: self = .guildScheduledEventUserRemove(try GatewayScheduledEventUser(value: value, limits: limits))
        case .guildSoundboardSoundCreate: self = .guildSoundboardSoundCreate(try SoundboardSound(value: value, limits: limits))
        case .guildSoundboardSoundUpdate: self = .guildSoundboardSoundUpdate(try SoundboardSound(value: value, limits: limits))
        case .guildSoundboardSoundDelete: self = .guildSoundboardSoundDelete(try GatewayGuildSoundboardSoundDelete(value: value, limits: limits))
        case .guildSoundboardSoundsUpdate: self = .guildSoundboardSoundsUpdate(try GatewaySoundboardSounds(value: value, limits: limits))
        case .soundboardSounds: self = .soundboardSounds(try GatewaySoundboardSounds(value: value, limits: limits))
        case .integrationCreate: self = .integrationCreate(try GatewayIntegrationUpdate(value: value, limits: limits))
        case .integrationUpdate: self = .integrationUpdate(try GatewayIntegrationUpdate(value: value, limits: limits))
        case .integrationDelete: self = .integrationDelete(try GatewayIntegrationDelete(value: value, limits: limits))
        case .interactionCreate: self = .interactionCreate(try Interaction(value: value, limits: limits))
        case .inviteCreate: self = .inviteCreate(try GatewayInviteCreate(value: value, limits: limits))
        case .inviteDelete: self = .inviteDelete(try GatewayInviteDelete(value: value, limits: limits))
        case .messageCreate: self = .messageCreate(try GatewayMessageCreate(value: value, limits: limits))
        case .messageUpdate: self = .messageUpdate(try GatewayMessageUpdate(value: value, limits: limits))
        case .messageDelete: self = .messageDelete(try GatewayMessageDelete(value: value, limits: limits))
        case .messageDeleteBulk: self = .messageDeleteBulk(try GatewayMessageDeleteBulk(value: value, limits: limits))
        case .messageReactionAdd: self = .messageReactionAdd(try GatewayMessageReactionAdd(value: value, limits: limits))
        case .messageReactionRemove: self = .messageReactionRemove(try GatewayMessageReactionRemove(value: value, limits: limits))
        case .messageReactionRemoveAll: self = .messageReactionRemoveAll(try GatewayMessageReactionRemoveAll(value: value, limits: limits))
        case .messageReactionRemoveEmoji: self = .messageReactionRemoveEmoji(try GatewayMessageReactionRemoveEmoji(value: value, limits: limits))
        case .presenceUpdate: self = .presenceUpdate(try GatewayPresenceUpdate(value: value, limits: limits))
        case .stageInstanceCreate: self = .stageInstanceCreate(try StageInstance(value: value, limits: limits))
        case .stageInstanceUpdate: self = .stageInstanceUpdate(try StageInstance(value: value, limits: limits))
        case .stageInstanceDelete: self = .stageInstanceDelete(try StageInstance(value: value, limits: limits))
        case .subscriptionCreate: self = .subscriptionCreate(try Subscription(value: value, limits: limits))
        case .subscriptionUpdate: self = .subscriptionUpdate(try Subscription(value: value, limits: limits))
        case .subscriptionDelete: self = .subscriptionDelete(try Subscription(value: value, limits: limits))
        case .typingStart: self = .typingStart(try GatewayTypingStart(value: value, limits: limits))
        case .userUpdate: self = .userUpdate(try User(value: value, limits: limits))
        case .voiceChannelEffectSend: self = .voiceChannelEffectSend(try GatewayVoiceChannelEffect(value: value, limits: limits))
        case .voiceChannelStartTimeUpdate: self = .voiceChannelStartTimeUpdate(try GatewayVoiceChannelStartTimeUpdate(value: value, limits: limits))
        case .voiceChannelStatusUpdate: self = .voiceChannelStatusUpdate(try GatewayVoiceChannelStatusUpdate(value: value, limits: limits))
        case .voiceStateUpdate: self = .voiceStateUpdate(try VoiceState(value: value, limits: limits))
        case .voiceServerUpdate: self = .voiceServerUpdate(try GatewayVoiceServerUpdate(value: value, limits: limits))
        case .webhooksUpdate: self = .webhooksUpdate(try GatewayWebhooksUpdate(value: value, limits: limits))
        case .messagePollVoteAdd: self = .messagePollVoteAdd(try GatewayMessagePollVote(value: value, limits: limits))
        case .messagePollVoteRemove: self = .messagePollVoteRemove(try GatewayMessagePollVote(value: value, limits: limits))
        case nil: self = .unknown(name: validatedName, data: value)
        }
    }

    /// Returns the exact dispatch name without rendering payload values.
    public var name: String {
        switch self {
        case .ready: "READY"
        case .resumed: "RESUMED"
        case .rateLimited: "RATE_LIMITED"
        case .applicationCommandPermissionsUpdate: "APPLICATION_COMMAND_PERMISSIONS_UPDATE"
        case .autoModerationRuleCreate: "AUTO_MODERATION_RULE_CREATE"
        case .autoModerationRuleUpdate: "AUTO_MODERATION_RULE_UPDATE"
        case .autoModerationRuleDelete: "AUTO_MODERATION_RULE_DELETE"
        case .autoModerationActionExecution: "AUTO_MODERATION_ACTION_EXECUTION"
        case .channelCreate: "CHANNEL_CREATE"
        case .channelUpdate: "CHANNEL_UPDATE"
        case .channelDelete: "CHANNEL_DELETE"
        case .channelInfo: "CHANNEL_INFO"
        case .channelPinsUpdate: "CHANNEL_PINS_UPDATE"
        case .threadCreate: "THREAD_CREATE"
        case .threadUpdate: "THREAD_UPDATE"
        case .threadDelete: "THREAD_DELETE"
        case .threadListSync: "THREAD_LIST_SYNC"
        case .threadMemberUpdate: "THREAD_MEMBER_UPDATE"
        case .threadMembersUpdate: "THREAD_MEMBERS_UPDATE"
        case .entitlementCreate: "ENTITLEMENT_CREATE"
        case .entitlementUpdate: "ENTITLEMENT_UPDATE"
        case .entitlementDelete: "ENTITLEMENT_DELETE"
        case .guildCreate: "GUILD_CREATE"
        case .guildUpdate: "GUILD_UPDATE"
        case .guildDelete: "GUILD_DELETE"
        case .guildAuditLogEntryCreate: "GUILD_AUDIT_LOG_ENTRY_CREATE"
        case .guildBanAdd: "GUILD_BAN_ADD"
        case .guildBanRemove: "GUILD_BAN_REMOVE"
        case .guildEmojisUpdate: "GUILD_EMOJIS_UPDATE"
        case .guildStickersUpdate: "GUILD_STICKERS_UPDATE"
        case .guildIntegrationsUpdate: "GUILD_INTEGRATIONS_UPDATE"
        case .guildMemberAdd: "GUILD_MEMBER_ADD"
        case .guildMemberRemove: "GUILD_MEMBER_REMOVE"
        case .guildMemberUpdate: "GUILD_MEMBER_UPDATE"
        case .guildMembersChunk: "GUILD_MEMBERS_CHUNK"
        case .guildRoleCreate: "GUILD_ROLE_CREATE"
        case .guildRoleUpdate: "GUILD_ROLE_UPDATE"
        case .guildRoleDelete: "GUILD_ROLE_DELETE"
        case .guildScheduledEventCreate: "GUILD_SCHEDULED_EVENT_CREATE"
        case .guildScheduledEventUpdate: "GUILD_SCHEDULED_EVENT_UPDATE"
        case .guildScheduledEventDelete: "GUILD_SCHEDULED_EVENT_DELETE"
        case .guildScheduledEventUserAdd: "GUILD_SCHEDULED_EVENT_USER_ADD"
        case .guildScheduledEventUserRemove: "GUILD_SCHEDULED_EVENT_USER_REMOVE"
        case .guildSoundboardSoundCreate: "GUILD_SOUNDBOARD_SOUND_CREATE"
        case .guildSoundboardSoundUpdate: "GUILD_SOUNDBOARD_SOUND_UPDATE"
        case .guildSoundboardSoundDelete: "GUILD_SOUNDBOARD_SOUND_DELETE"
        case .guildSoundboardSoundsUpdate: "GUILD_SOUNDBOARD_SOUNDS_UPDATE"
        case .soundboardSounds: "SOUNDBOARD_SOUNDS"
        case .integrationCreate: "INTEGRATION_CREATE"
        case .integrationUpdate: "INTEGRATION_UPDATE"
        case .integrationDelete: "INTEGRATION_DELETE"
        case .interactionCreate: "INTERACTION_CREATE"
        case .inviteCreate: "INVITE_CREATE"
        case .inviteDelete: "INVITE_DELETE"
        case .messageCreate: "MESSAGE_CREATE"
        case .messageUpdate: "MESSAGE_UPDATE"
        case .messageDelete: "MESSAGE_DELETE"
        case .messageDeleteBulk: "MESSAGE_DELETE_BULK"
        case .messageReactionAdd: "MESSAGE_REACTION_ADD"
        case .messageReactionRemove: "MESSAGE_REACTION_REMOVE"
        case .messageReactionRemoveAll: "MESSAGE_REACTION_REMOVE_ALL"
        case .messageReactionRemoveEmoji: "MESSAGE_REACTION_REMOVE_EMOJI"
        case .presenceUpdate: "PRESENCE_UPDATE"
        case .stageInstanceCreate: "STAGE_INSTANCE_CREATE"
        case .stageInstanceUpdate: "STAGE_INSTANCE_UPDATE"
        case .stageInstanceDelete: "STAGE_INSTANCE_DELETE"
        case .subscriptionCreate: "SUBSCRIPTION_CREATE"
        case .subscriptionUpdate: "SUBSCRIPTION_UPDATE"
        case .subscriptionDelete: "SUBSCRIPTION_DELETE"
        case .typingStart: "TYPING_START"
        case .userUpdate: "USER_UPDATE"
        case .voiceChannelEffectSend: "VOICE_CHANNEL_EFFECT_SEND"
        case .voiceChannelStartTimeUpdate: "VOICE_CHANNEL_START_TIME_UPDATE"
        case .voiceChannelStatusUpdate: "VOICE_CHANNEL_STATUS_UPDATE"
        case .voiceStateUpdate: "VOICE_STATE_UPDATE"
        case .voiceServerUpdate: "VOICE_SERVER_UPDATE"
        case .webhooksUpdate: "WEBHOOKS_UPDATE"
        case .messagePollVoteAdd: "MESSAGE_POLL_VOTE_ADD"
        case .messagePollVoteRemove: "MESSAGE_POLL_VOTE_REMOVE"
        case .unknown(let name, _): name
        }
    }

    /// Returns complete original event data for deliberate inspection or persistence.
    /// - Returns: Exact semantic JSON, preserving unknown fields and numeric lexemes; no envelope is added.
    public func jsonValue() -> JSONValue {
        switch self {
        case .ready(let payload): payload.jsonValue()
        case .resumed(let payload): payload.jsonValue()
        case .rateLimited(let payload): payload.jsonValue()
        case .applicationCommandPermissionsUpdate(let payload): payload.jsonValue()
        case .autoModerationRuleCreate(let payload): payload.jsonValue()
        case .autoModerationRuleUpdate(let payload): payload.jsonValue()
        case .autoModerationRuleDelete(let payload): payload.jsonValue()
        case .autoModerationActionExecution(let payload): payload.jsonValue()
        case .channelCreate(let payload): payload.jsonValue()
        case .channelUpdate(let payload): payload.jsonValue()
        case .channelDelete(let payload): payload.jsonValue()
        case .channelInfo(let payload): payload.jsonValue()
        case .channelPinsUpdate(let payload): payload.jsonValue()
        case .threadCreate(let payload): payload.jsonValue()
        case .threadUpdate(let payload): payload.jsonValue()
        case .threadDelete(let payload): payload.jsonValue()
        case .threadListSync(let payload): payload.jsonValue()
        case .threadMemberUpdate(let payload): payload.jsonValue()
        case .threadMembersUpdate(let payload): payload.jsonValue()
        case .entitlementCreate(let payload): payload.jsonValue()
        case .entitlementUpdate(let payload): payload.jsonValue()
        case .entitlementDelete(let payload): payload.jsonValue()
        case .guildCreate(let payload): payload.jsonValue()
        case .guildUpdate(let payload): payload.jsonValue()
        case .guildDelete(let payload): payload.jsonValue()
        case .guildAuditLogEntryCreate(let payload): payload.jsonValue()
        case .guildBanAdd(let payload): payload.jsonValue()
        case .guildBanRemove(let payload): payload.jsonValue()
        case .guildEmojisUpdate(let payload): payload.jsonValue()
        case .guildStickersUpdate(let payload): payload.jsonValue()
        case .guildIntegrationsUpdate(let payload): payload.jsonValue()
        case .guildMemberAdd(let payload): payload.jsonValue()
        case .guildMemberRemove(let payload): payload.jsonValue()
        case .guildMemberUpdate(let payload): payload.jsonValue()
        case .guildMembersChunk(let payload): payload.jsonValue()
        case .guildRoleCreate(let payload): payload.jsonValue()
        case .guildRoleUpdate(let payload): payload.jsonValue()
        case .guildRoleDelete(let payload): payload.jsonValue()
        case .guildScheduledEventCreate(let payload): payload.jsonValue()
        case .guildScheduledEventUpdate(let payload): payload.jsonValue()
        case .guildScheduledEventDelete(let payload): payload.jsonValue()
        case .guildScheduledEventUserAdd(let payload): payload.jsonValue()
        case .guildScheduledEventUserRemove(let payload): payload.jsonValue()
        case .guildSoundboardSoundCreate(let payload): payload.jsonValue()
        case .guildSoundboardSoundUpdate(let payload): payload.jsonValue()
        case .guildSoundboardSoundDelete(let payload): payload.jsonValue()
        case .guildSoundboardSoundsUpdate(let payload): payload.jsonValue()
        case .soundboardSounds(let payload): payload.jsonValue()
        case .integrationCreate(let payload): payload.jsonValue()
        case .integrationUpdate(let payload): payload.jsonValue()
        case .integrationDelete(let payload): payload.jsonValue()
        case .interactionCreate(let payload): payload.jsonValue()
        case .inviteCreate(let payload): payload.jsonValue()
        case .inviteDelete(let payload): payload.jsonValue()
        case .messageCreate(let payload): payload.jsonValue()
        case .messageUpdate(let payload): payload.jsonValue()
        case .messageDelete(let payload): payload.jsonValue()
        case .messageDeleteBulk(let payload): payload.jsonValue()
        case .messageReactionAdd(let payload): payload.jsonValue()
        case .messageReactionRemove(let payload): payload.jsonValue()
        case .messageReactionRemoveAll(let payload): payload.jsonValue()
        case .messageReactionRemoveEmoji(let payload): payload.jsonValue()
        case .presenceUpdate(let payload): payload.jsonValue()
        case .stageInstanceCreate(let payload): payload.jsonValue()
        case .stageInstanceUpdate(let payload): payload.jsonValue()
        case .stageInstanceDelete(let payload): payload.jsonValue()
        case .subscriptionCreate(let payload): payload.jsonValue()
        case .subscriptionUpdate(let payload): payload.jsonValue()
        case .subscriptionDelete(let payload): payload.jsonValue()
        case .typingStart(let payload): payload.jsonValue()
        case .userUpdate(let payload): payload.jsonValue()
        case .voiceChannelEffectSend(let payload): payload.jsonValue()
        case .voiceChannelStartTimeUpdate(let payload): payload.jsonValue()
        case .voiceChannelStatusUpdate(let payload): payload.jsonValue()
        case .voiceStateUpdate(let payload): payload.jsonValue()
        case .voiceServerUpdate(let payload): payload.jsonValue()
        case .webhooksUpdate(let payload): payload.jsonValue()
        case .messagePollVoteAdd(let payload): payload.jsonValue()
        case .messagePollVoteRemove(let payload): payload.jsonValue()
        case .unknown(_, let data): data
        }
    }

    /// Conceals payload data and user-controlled unknown event names in ordinary diagnostics.
    public var description: String { "GatewayDispatch(redacted)" }
    /// Uses the same redacted debug marker.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing tokens, personal data and unknown payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
