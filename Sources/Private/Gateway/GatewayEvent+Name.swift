//
//  GatewayEvent+Name.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - Name

extension GatewayEvent {
    
    /// A type-safe wrapper for the string name of dispatch events.
    enum Name: DiscordModel {
        
        /// Application command permission was updated.
        case applicationCommandPermissionsUpdate
        
        /// Auto moderation rule was created.
        case autoModerationRuleCreate
        
        /// Auto moderation rule was updated.
        case autoModerationRuleUpdate
        
        /// Auto moderation rule was deleted.
        case autoModerationRuleDelete
        
        /// Auto moderation rule was triggered and an action was executed.
        case autoModerationExecution
        
        /// New guild channel was created.
        case channelCreate
        
        /// Channel was updated.
        case channelUpdate
        
        /// Channel was deleted.
        case channelDelete
        
        case channelPinsUpdate
        
        case threadCreate
        
        case threadUpdate
        
        case threadDelete
        
        case threadListSync
        
        case threadMemberUpdate
        
        case threadMembersUpdate
        
        case entitlementCreate
        
        case entitlementUpdate
        
        case entitlementDelete
        
        /// Lazy-load for an unavailable guild, guild becomes available, or user joined a new guild.
        case guildCreate
        
        case guildUpdate
        
        case guildDelete
        
        case guildAuditLogEntryCreate
        
        case guildBanAdd
        
        case guildBanRemove
        
        case guildEmojisUpdate
        
        case guildStickersUpdate
        
        case guildIntegrationsUpdate
        
        case guildMemberAdd
        
        case guildMemberRemove
        
        case guildMemberUpdate
        
        case guildMembersChunk
        
        case guildRoleCreate
        
        case guildRoleUpdate
        
        case guildRoleDelete
        
        /// Guild scheduled event was created.
        case guildScheduledEventCreate
        
        /// Guild scheduled event was deleted.
        case guildScheduledEventDelete
        
        /// Guild scheduled event was updated.
        case guildScheduledEventUpdate
        
        case guildScheduledEventUserAdd
        
        case guildScheduledEventUserRemove
        
        case guildSoundboardSoundCreate
        
        case guildSoundboardSoundUpdate
        
        case guildSoundboardSoundDelete
        
        case guildSoundboardSoundsUpdate
        
        case soundboardSounds
        
        case integrationCreate
        
        case integrationUpdate
        
        case integrationDelete
        
        /// User used an interaction, such as an application command.
        case interactionCreate
        
        case inviteCreate
        
        case inviteDelete
        
        case messageCreate
        
        case messageUpdate
        
        case messageDelete
        
        case messageDeleteBulk
        
        case messageReactionAdd
        
        case messageReactionRemove
        
        case messageReactionRemoveAll
        
        case messageReactionRemoveEmoji
        
        /// Presence update event.
        case presenceUpdate
        
        case stageInstanceCreate
        
        case stageInstanceUpdate
        
        case stageInstanceDelete
        
        case typingStart
        
        case userUpdate
        
        case webhooksUpdate
        
        case messagePollVoteAdd
        
        case messagePollVoteRemove
        
        /// The ready event.
        case ready
        
        /// The resume completed successful.
        case resumed
        
        /// Not a dispatch event.
        case none
        
        /// An unknown event.
        case unknown(String)
    }
}

// MARK: Codable

extension GatewayEvent.Name {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "APPLICATION_COMMAND_PERMISSIONS_UPDATE": self = .applicationCommandPermissionsUpdate
        case "AUTO_MODERATION_RULE_CREATE":            self = .autoModerationRuleCreate
        case "AUTO_MODERATION_RULE_UPDATE":            self = .autoModerationRuleUpdate
        case "AUTO_MODERATION_RULE_DELETE":            self = .autoModerationRuleDelete
        case "AUTO_MODERATION_EXECUTION":              self = .autoModerationExecution
        case "CHANNEL_CREATE":                         self = .channelCreate
        case "CHANNEL_UPDATE":                         self = .channelUpdate
        case "CHANNEL_DELETE":                         self = .channelDelete
        case "CHANNEL_PINS_UPDATE":                    self = .channelPinsUpdate
        case "THREAD_CREATE":                          self = .threadCreate
        case "THREAD_UPDATE":                          self = .threadUpdate
        case "THREAD_DELETE":                          self = .threadDelete
        case "THREAD_LIST_SYNC":                       self = .threadListSync
        case "THREAD_MEMBER_UPDATE":                   self = .threadMemberUpdate
        case "THREAD_MEMBERS_UPDATE":                  self = .threadMembersUpdate
        case "ENTITLEMENT_CREATE":                     self = .entitlementCreate
        case "ENTITLEMENT_UPDATE":                     self = .entitlementUpdate
        case "ENTITLEMENT_DELETE":                     self = .entitlementDelete
        case "GUILD_CREATE":                           self = .guildCreate
        case "GUILD_UPDATE":                           self = .guildUpdate
        case "GUILD_DELETE":                           self = .guildDelete
        case "GUILD_AUDIT_LOG_ENTRY_CREATE":           self = .guildAuditLogEntryCreate
        case "GUILD_BAN_ADD":                          self = .guildBanAdd
        case "GUILD_BAN_REMOVE":                       self = .guildBanRemove
        case "GUILD_EMOJIS_UPDATE":                    self = .guildEmojisUpdate
        case "GUILD_STICKERS_UPDATE":                  self = .guildStickersUpdate
        case "GUILD_INTEGRATIONS_UPDATE":              self = .guildIntegrationsUpdate
        case "GUILD_MEMBER_ADD":                       self = .guildMemberAdd
        case "GUILD_MEMBER_REMOVE":                    self = .guildMemberRemove
        case "GUILD_MEMBER_UPDATE":                    self = .guildMemberUpdate
        case "GUILD_MEMBERS_CHUNK":                    self = .guildMembersChunk
        case "GUILD_ROLE_CREATE":                      self = .guildRoleCreate
        case "GUILD_ROLE_UPDATE":                      self = .guildRoleUpdate
        case "GUILD_ROLE_DELETE":                      self = .guildRoleDelete
        case "GUILD_SCHEDULED_EVENT_CREATE":           self = .guildScheduledEventCreate
        case "GUILD_SCHEDULED_EVENT_DELETE":           self = .guildScheduledEventDelete
        case "GUILD_SCHEDULED_EVENT_UPDATE":           self = .guildScheduledEventUpdate
        case "GUILD_SCHEDULED_EVENT_USER_ADD":         self = .guildScheduledEventUserAdd
        case "GUILD_SCHEDULED_EVENT_USER_REMOVE":      self = .guildScheduledEventUserRemove
        case "GUILD_SOUNDBOARD_SOUND_CREATE":          self = .guildSoundboardSoundCreate
        case "GUILD_SOUNDBOARD_SOUND_UPDATE":          self = .guildSoundboardSoundUpdate
        case "GUILD_SOUNDBOARD_SOUND_DELETE":          self = .guildSoundboardSoundDelete
        case "GUILD_SOUNDBOARD_SOUNDS_UPDATE":         self = .guildSoundboardSoundsUpdate
        case "SOUNDBOARD_SOUNDS":                      self = .soundboardSounds
        case "INTEGRATION_CREATE":                     self = .integrationCreate
        case "INTEGRATION_UPDATE":                     self = .integrationUpdate
        case "INTEGRATION_DELETE":                     self = .integrationDelete
        case "INTERACTION_CREATE":                     self = .interactionCreate
        case "INVITE_CREATE":                          self = .inviteCreate
        case "INVITE_DELETE":                          self = .inviteDelete
        case "MESSAGE_CREATE":                         self = .messageCreate
        case "MESSAGE_UPDATE":                         self = .messageUpdate
        case "MESSAGE_DELETE":                         self = .messageDelete
        case "MESSAGE_DELETE_BULK":                    self = .messageDeleteBulk
        case "MESSAGE_REACTION_ADD":                   self = .messageReactionAdd
        case "MESSAGE_REACTION_REMOVE":                self = .messageReactionRemove
        case "MESSAGE_REACTION_REMOVE_ALL":            self = .messageReactionRemoveAll
        case "MESSAGE_REACTION_REMOVE_EMOJI":          self = .messageReactionRemoveEmoji
        case "PRESENCE_UPDATE":                        self = .presenceUpdate
        case "STAGE_INSTANCE_CREATE":                  self = .stageInstanceCreate
        case "STAGE_INSTANCE_UPDATE":                  self = .stageInstanceUpdate
        case "STAGE_INSTANCE_DELETE":                  self = .stageInstanceDelete
        case "TYPING_START":                           self = .typingStart
        case "USER_UPDATE":                            self = .userUpdate
        case "WEBHOOKS_UPDATE":                        self = .webhooksUpdate
        case "MESSAGE_POLL_VOTE_ADD":                  self = .messagePollVoteAdd
        case "MESSAGE_POLL_VOTE_REMOVE":               self = .messagePollVoteRemove
        case "READY":                                  self = .ready
        case "RESUMED":                                self = .resumed
        default:                                       self = .unknown(rawValue)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .applicationCommandPermissionsUpdate: try container.encode("APPLICATION_COMMAND_PERMISSIONS_UPDATE")
        case .autoModerationRuleCreate:            try container.encode("AUTO_MODERATION_RULE_CREATE")
        case .autoModerationRuleUpdate:            try container.encode("AUTO_MODERATION_RULE_UPDATE")
        case .autoModerationRuleDelete:            try container.encode("AUTO_MODERATION_RULE_DELETE")
        case .autoModerationExecution:             try container.encode("AUTO_MODERATION_EXECUTION")
        case .channelCreate:                       try container.encode("CHANNEL_CREATE")
        case .channelUpdate:                       try container.encode("CHANNEL_UPDATE")
        case .channelDelete:                       try container.encode("CHANNEL_DELETE")
        case .channelPinsUpdate:                   try container.encode("CHANNEL_PINS_UPDATE")
        case .threadCreate:                        try container.encode("THREAD_CREATE")
        case .threadUpdate:                        try container.encode("THREAD_UPDATE")
        case .threadDelete:                        try container.encode("THREAD_DELETE")
        case .threadListSync:                      try container.encode("THREAD_LIST_SYNC")
        case .threadMemberUpdate:                  try container.encode("THREAD_MEMBER_UPDATE")
        case .threadMembersUpdate:                 try container.encode("THREAD_MEMBERS_UPDATE")
        case .entitlementCreate:                   try container.encode("ENTITLEMENT_CREATE")
        case .entitlementUpdate:                   try container.encode("ENTITLEMENT_UPDATE")
        case .entitlementDelete:                   try container.encode("ENTITLEMENT_DELETE")
        case .guildCreate:                         try container.encode("GUILD_CREATE")
        case .guildUpdate:                         try container.encode("GUILD_UPDATE")
        case .guildDelete:                         try container.encode("GUILD_DELETE")
        case .guildAuditLogEntryCreate:            try container.encode("GUILD_AUDIT_LOG_ENTRY_CREATE")
        case .guildBanAdd:                         try container.encode("GUILD_BAN_ADD")
        case .guildBanRemove:                      try container.encode("GUILD_BAN_REMOVE")
        case .guildEmojisUpdate:                   try container.encode("GUILD_EMOJIS_UPDATE")
        case .guildStickersUpdate:                 try container.encode("GUILD_STICKERS_UPDATE")
        case .guildIntegrationsUpdate:             try container.encode("GUILD_INTEGRATIONS_UPDATE")
        case .guildMemberAdd:                      try container.encode("GUILD_MEMBER_ADD")
        case .guildMemberRemove:                   try container.encode("GUILD_MEMBER_REMOVE")
        case .guildMemberUpdate:                   try container.encode("GUILD_MEMBER_UPDATE")
        case .guildMembersChunk:                   try container.encode("GUILD_MEMBERS_CHUNK")
        case .guildRoleCreate:                     try container.encode("GUILD_ROLE_CREATE")
        case .guildRoleUpdate:                     try container.encode("GUILD_ROLE_UPDATE")
        case .guildRoleDelete:                     try container.encode("GUILD_ROLE_DELETE")
        case .guildScheduledEventCreate:           try container.encode("GUILD_SCHEDULED_EVENT_CREATE")
        case .guildScheduledEventDelete:           try container.encode("GUILD_SCHEDULED_EVENT_DELETE")
        case .guildScheduledEventUpdate:           try container.encode("GUILD_SCHEDULED_EVENT_UPDATE")
        case .guildScheduledEventUserAdd:          try container.encode("GUILD_SCHEDULED_EVENT_USER_ADD")
        case .guildScheduledEventUserRemove:       try container.encode("GUILD_SCHEDULED_EVENT_USER_REMOVE")
        case .guildSoundboardSoundCreate:          try container.encode("GUILD_SOUNDBOARD_SOUND_CREATE")
        case .guildSoundboardSoundUpdate:          try container.encode("GUILD_SOUNDBOARD_SOUND_UPDATE")
        case .guildSoundboardSoundDelete:          try container.encode("GUILD_SOUNDBOARD_SOUND_DELETE")
        case .guildSoundboardSoundsUpdate:         try container.encode("GUILD_SOUNDBOARD_SOUNDS_UPDATE")
        case .soundboardSounds:                    try container.encode("SOUNDBOARD_SOUNDS")
        case .integrationCreate:                   try container.encode("INTEGRATION_CREATE")
        case .integrationUpdate:                   try container.encode("INTEGRATION_UPDATE")
        case .integrationDelete:                   try container.encode("INTEGRATION_DELETE")
        case .interactionCreate:                   try container.encode("INTERACTION_CREATE")
        case .inviteCreate:                        try container.encode("INVITE_CREATE")
        case .inviteDelete:                        try container.encode("INVITE_DELETE")
        case .messageCreate:                       try container.encode("MESSAGE_CREATE")
        case .messageUpdate:                       try container.encode("MESSAGE_UPDATE")
        case .messageDelete:                       try container.encode("MESSAGE_DELETE")
        case .messageDeleteBulk:                   try container.encode("MESSAGE_DELETE_BULK")
        case .messageReactionAdd:                  try container.encode("MESSAGE_REACTION_ADD")
        case .messageReactionRemove:               try container.encode("MESSAGE_REACTION_REMOVE")
        case .messageReactionRemoveAll:            try container.encode("MESSAGE_REACTION_REMOVE_ALL")
        case .messageReactionRemoveEmoji:          try container.encode("MESSAGE_REACTION_REMOVE_EMOJI")
        case .presenceUpdate:                      try container.encode("PRESENCE_UPDATE")
        case .stageInstanceCreate:                 try container.encode("STAGE_INSTANCE_CREATE")
        case .stageInstanceUpdate:                 try container.encode("STAGE_INSTANCE_UPDATE")
        case .stageInstanceDelete:                 try container.encode("STAGE_INSTANCE_DELETE")
        case .typingStart:                         try container.encode("TYPING_START")
        case .userUpdate:                          try container.encode("USER_UPDATE")
        case .webhooksUpdate:                      try container.encode("WEBHOOKS_UPDATE")
        case .messagePollVoteAdd:                  try container.encode("MESSAGE_POLL_VOTE_ADD")
        case .messagePollVoteRemove:               try container.encode("MESSAGE_POLL_VOTE_REMOVE")
        case .ready:                               try container.encode("READY")
        case .resumed:                             try container.encode("RESUMED")
        case .unknown(let value):                  try container.encode(value)
        case .none:                                try container.encodeNil()
        }
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent.Name: CustomStringConvertible {
    var description: String {
        switch self {
        case .applicationCommandPermissionsUpdate: return "APPLICATION_COMMAND_PERMISSIONS_UPDATE"
        case .autoModerationRuleCreate:            return "AUTO_MODERATION_RULE_CREATE"
        case .autoModerationRuleUpdate:            return "AUTO_MODERATION_RULE_UPDATE"
        case .autoModerationRuleDelete:            return "AUTO_MODERATION_RULE_DELETE"
        case .autoModerationExecution:             return "AUTO_MODERATION_EXECUTION"
        case .channelCreate:                       return "CHANNEL_CREATE"
        case .channelUpdate:                       return "CHANNEL_UPDATE"
        case .channelDelete:                       return "CHANNEL_DELETE"
        case .channelPinsUpdate:                   return "CHANNEL_PINS_UPDATE"
        case .threadCreate:                        return "THREAD_CREATE"
        case .threadUpdate:                        return "THREAD_UPDATE"
        case .threadDelete:                        return "THREAD_DELETE"
        case .threadListSync:                      return "THREAD_LIST_SYNC"
        case .threadMemberUpdate:                  return "THREAD_MEMBER_UPDATE"
        case .threadMembersUpdate:                 return "THREAD_MEMBERS_UPDATE"
        case .entitlementCreate:                   return "ENTITLEMENT_CREATE"
        case .entitlementUpdate:                   return "ENTITLEMENT_UPDATE"
        case .entitlementDelete:                   return "ENTITLEMENT_DELETE"
        case .guildCreate:                         return "GUILD_CREATE"
        case .guildUpdate:                         return "GUILD_UPDATE"
        case .guildDelete:                         return "GUILD_DELETE"
        case .guildAuditLogEntryCreate:            return "GUILD_AUDIT_LOG_ENTRY_CREATE"
        case .guildBanAdd:                         return "GUILD_BAN_ADD"
        case .guildBanRemove:                      return "GUILD_BAN_REMOVE"
        case .guildEmojisUpdate:                   return "GUILD_EMOJIS_UPDATE"
        case .guildStickersUpdate:                 return "GUILD_STICKERS_UPDATE"
        case .guildIntegrationsUpdate:             return "GUILD_INTEGRATIONS_UPDATE"
        case .guildMemberAdd:                      return "GUILD_MEMBER_ADD"
        case .guildMemberRemove:                   return "GUILD_MEMBER_REMOVE"
        case .guildMemberUpdate:                   return "GUILD_MEMBER_UPDATE"
        case .guildMembersChunk:                   return "GUILD_MEMBERS_CHUNK"
        case .guildRoleCreate:                     return "GUILD_ROLE_CREATE"
        case .guildRoleUpdate:                     return "GUILD_ROLE_UPDATE"
        case .guildRoleDelete:                     return "GUILD_ROLE_DELETE"
        case .guildScheduledEventCreate:           return "GUILD_SCHEDULED_EVENT_CREATE"
        case .guildScheduledEventDelete:           return "GUILD_SCHEDULED_EVENT_DELETE"
        case .guildScheduledEventUpdate:           return "GUILD_SCHEDULED_EVENT_UPDATE"
        case .guildScheduledEventUserAdd:          return "GUILD_SCHEDULED_EVENT_USER_ADD"
        case .guildScheduledEventUserRemove:       return "GUILD_SCHEDULED_EVENT_USER_REMOVE"
        case .guildSoundboardSoundCreate:          return "GUILD_SOUNDBOARD_SOUND_CREATE"
        case .guildSoundboardSoundUpdate:          return "GUILD_SOUNDBOARD_SOUND_UPDATE"
        case .guildSoundboardSoundDelete:          return "GUILD_SOUNDBOARD_SOUND_DELETE"
        case .guildSoundboardSoundsUpdate:         return "GUILD_SOUNDBOARD_SOUNDS_UPDATE"
        case .soundboardSounds:                    return "SOUNDBOARD_SOUNDS"
        case .integrationCreate:                   return "INTEGRATION_CREATE"
        case .integrationUpdate:                   return "INTEGRATION_UPDATE"
        case .integrationDelete:                   return "INTEGRATION_DELETE"
        case .interactionCreate:                   return "INTERACTION_CREATE"
        case .inviteCreate:                        return "INVITE_CREATE"
        case .inviteDelete:                        return "INVITE_DELETE"
        case .messageCreate:                       return "MESSAGE_CREATE"
        case .messageUpdate:                       return "MESSAGE_UPDATE"
        case .messageDelete:                       return "MESSAGE_DELETE"
        case .messageDeleteBulk:                   return "MESSAGE_DELETE_BULK"
        case .messageReactionAdd:                  return "MESSAGE_REACTION_ADD"
        case .messageReactionRemove:               return "MESSAGE_REACTION_REMOVE"
        case .messageReactionRemoveAll:            return "MESSAGE_REACTION_REMOVE_ALL"
        case .messageReactionRemoveEmoji:          return "MESSAGE_REACTION_REMOVE_EMOJI"
        case .presenceUpdate:                      return "PRESENCE_UPDATE"
        case .stageInstanceCreate:                 return "STAGE_INSTANCE_CREATE"
        case .stageInstanceUpdate:                 return "STAGE_INSTANCE_UPDATE"
        case .stageInstanceDelete:                 return "STAGE_INSTANCE_DELETE"
        case .typingStart:                         return "TYPING_START"
        case .userUpdate:                          return "USER_UPDATE"
        case .webhooksUpdate:                      return "WEBHOOKS_UPDATE"
        case .messagePollVoteAdd:                  return "MESSAGE_POLL_VOTE_ADD"
        case .messagePollVoteRemove:               return "MESSAGE_POLL_VOTE_REMOVE"
        case .ready:                               return "READY"
        case .resumed:                             return "RESUMED"
        case .unknown(let string):                 return string.uppercased()
        case .none:                                return "NO_NAME"
        }
    }
}
