// File: Sources/DiscordModels/AuditLogValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Marker separating audit entry identifiers from affected resource identifiers.
public enum AuditLogEntryTag: Sendable {}
/// Exact unsigned audit entry snowflake, including zero as an explicit pagination boundary.
public typealias AuditLogEntryID = Snowflake<AuditLogEntryTag>
/// Marker for application commands referenced by an audit response, independent of command execution.
public enum ApplicationCommandTag: Sendable {}
/// Exact unsigned application command snowflake; decoding does not establish command availability.
public typealias ApplicationCommandID = Snowflake<ApplicationCommandTag>
/// Marker for guild scheduled events referenced by an audit response.
public enum GuildScheduledEventTag: Sendable {}
/// Exact unsigned scheduled event snowflake shared by audit references and the scheduled-event REST catalog.
public typealias GuildScheduledEventID = Snowflake<GuildScheduledEventTag>

/// Known API v10 administrative action codes, verified 2026-10-16 against the official Audit Log
/// reference and discord-api-spec OpenAPI preview. Recognition describes the action identifier only;
/// it does not claim typed change schemas or REST/Gateway support for the affected resource family.
/// `RawValue<AuditLogEvent>` preserves future integral action codes without assigning guessed semantics.
public enum AuditLogEvent: Int, Sendable, CaseIterable {
    /// GUILD_UPDATE (1).
    case guildUpdate = 1
    /// CHANNEL_CREATE (10).
    case channelCreate = 10
    /// CHANNEL_UPDATE (11).
    case channelUpdate = 11
    /// CHANNEL_DELETE (12).
    case channelDelete = 12
    /// CHANNEL_OVERWRITE_CREATE (13).
    case channelOverwriteCreate = 13
    /// CHANNEL_OVERWRITE_UPDATE (14).
    case channelOverwriteUpdate = 14
    /// CHANNEL_OVERWRITE_DELETE (15).
    case channelOverwriteDelete = 15
    /// MEMBER_KICK (20).
    case memberKick = 20
    /// MEMBER_PRUNE (21).
    case memberPrune = 21
    /// MEMBER_BAN_ADD (22).
    case memberBanAdd = 22
    /// MEMBER_BAN_REMOVE (23).
    case memberBanRemove = 23
    /// MEMBER_UPDATE (24).
    case memberUpdate = 24
    /// MEMBER_ROLE_UPDATE (25).
    case memberRoleUpdate = 25
    /// MEMBER_MOVE (26).
    case memberMove = 26
    /// MEMBER_DISCONNECT (27).
    case memberDisconnect = 27
    /// BOT_ADD (28).
    case botAdd = 28
    /// ROLE_CREATE (30).
    case roleCreate = 30
    /// ROLE_UPDATE (31).
    case roleUpdate = 31
    /// ROLE_DELETE (32).
    case roleDelete = 32
    /// INVITE_CREATE (40).
    case inviteCreate = 40
    /// INVITE_UPDATE (41).
    case inviteUpdate = 41
    /// INVITE_DELETE (42).
    case inviteDelete = 42
    /// WEBHOOK_CREATE (50).
    case webhookCreate = 50
    /// WEBHOOK_UPDATE (51).
    case webhookUpdate = 51
    /// WEBHOOK_DELETE (52).
    case webhookDelete = 52
    /// EMOJI_CREATE (60).
    case emojiCreate = 60
    /// EMOJI_UPDATE (61).
    case emojiUpdate = 61
    /// EMOJI_DELETE (62).
    case emojiDelete = 62
    /// MESSAGE_DELETE (72).
    case messageDelete = 72
    /// MESSAGE_BULK_DELETE (73).
    case messageBulkDelete = 73
    /// MESSAGE_PIN (74).
    case messagePin = 74
    /// MESSAGE_UNPIN (75).
    case messageUnpin = 75
    /// INTEGRATION_CREATE (80).
    case integrationCreate = 80
    /// INTEGRATION_UPDATE (81).
    case integrationUpdate = 81
    /// INTEGRATION_DELETE (82).
    case integrationDelete = 82
    /// STAGE_INSTANCE_CREATE (83).
    case stageInstanceCreate = 83
    /// STAGE_INSTANCE_UPDATE (84).
    case stageInstanceUpdate = 84
    /// STAGE_INSTANCE_DELETE (85).
    case stageInstanceDelete = 85
    /// STICKER_CREATE (90).
    case stickerCreate = 90
    /// STICKER_UPDATE (91).
    case stickerUpdate = 91
    /// STICKER_DELETE (92).
    case stickerDelete = 92
    /// GUILD_SCHEDULED_EVENT_CREATE (100).
    case guildScheduledEventCreate = 100
    /// GUILD_SCHEDULED_EVENT_UPDATE (101).
    case guildScheduledEventUpdate = 101
    /// GUILD_SCHEDULED_EVENT_DELETE (102).
    case guildScheduledEventDelete = 102
    /// THREAD_CREATE (110).
    case threadCreate = 110
    /// THREAD_UPDATE (111).
    case threadUpdate = 111
    /// THREAD_DELETE (112).
    case threadDelete = 112
    /// APPLICATION_COMMAND_PERMISSION_UPDATE (121).
    case applicationCommandPermissionUpdate = 121
    /// SOUNDBOARD_SOUND_CREATE (130).
    case soundboardSoundCreate = 130
    /// SOUNDBOARD_SOUND_UPDATE (131).
    case soundboardSoundUpdate = 131
    /// SOUNDBOARD_SOUND_DELETE (132).
    case soundboardSoundDelete = 132
    /// AUTO_MODERATION_RULE_CREATE (140).
    case autoModerationRuleCreate = 140
    /// AUTO_MODERATION_RULE_UPDATE (141).
    case autoModerationRuleUpdate = 141
    /// AUTO_MODERATION_RULE_DELETE (142).
    case autoModerationRuleDelete = 142
    /// AUTO_MODERATION_BLOCK_MESSAGE (143).
    case autoModerationBlockMessage = 143
    /// AUTO_MODERATION_FLAG_TO_CHANNEL (144).
    case autoModerationFlagToChannel = 144
    /// AUTO_MODERATION_USER_COMM_DISABLED (145).
    case autoModerationUserCommunicationDisabled = 145
    /// AUTO_MODERATION_QUARANTINE_USER (146).
    case autoModerationQuarantineUser = 146
    /// CREATOR_MONETIZATION_REQUEST_CREATED (150).
    case creatorMonetizationRequestCreated = 150
    /// CREATOR_MONETIZATION_TERMS_ACCEPTED (151).
    case creatorMonetizationTermsAccepted = 151
    /// ONBOARDING_PROMPT_CREATE (163).
    case onboardingPromptCreate = 163
    /// ONBOARDING_PROMPT_UPDATE (164).
    case onboardingPromptUpdate = 164
    /// ONBOARDING_PROMPT_DELETE (165).
    case onboardingPromptDelete = 165
    /// ONBOARDING_CREATE (166).
    case onboardingCreate = 166
    /// ONBOARDING_UPDATE (167).
    case onboardingUpdate = 167
    /// GUILD_HOME_FEATURE_ITEM (171); currently enumerated only in the official OpenAPI preview.
    case guildHomeFeatureItem = 171
    /// GUILD_HOME_REMOVE_ITEM (172); currently enumerated only in the official OpenAPI preview.
    case guildHomeRemoveItem = 172
    /// HARMFUL_LINKS_BLOCKED_MESSAGE (180); currently enumerated only in the official OpenAPI preview.
    case harmfulLinksBlockedMessage = 180
    /// HOME_SETTINGS_CREATE (190).
    case homeSettingsCreate = 190
    /// HOME_SETTINGS_UPDATE (191).
    case homeSettingsUpdate = 191
    /// VOICE_CHANNEL_STATUS_CREATE (192).
    case voiceChannelStatusCreate = 192
    /// VOICE_CHANNEL_STATUS_DELETE (193).
    case voiceChannelStatusDelete = 193
    /// GUILD_SCHEDULED_EVENT_EXCEPTION_CREATE (200); currently enumerated only in the official OpenAPI preview.
    case guildScheduledEventExceptionCreate = 200
    /// GUILD_SCHEDULED_EVENT_EXCEPTION_UPDATE (201); currently enumerated only in the official OpenAPI preview.
    case guildScheduledEventExceptionUpdate = 201
    /// GUILD_SCHEDULED_EVENT_EXCEPTION_DELETE (202); currently enumerated only in the official OpenAPI preview.
    case guildScheduledEventExceptionDelete = 202
    /// GUILD_PROFILE_UPDATE (211); currently enumerated only in the official OpenAPI preview.
    case guildProfileUpdate = 211
}
