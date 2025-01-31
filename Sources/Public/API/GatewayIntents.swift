//
//  GatewayIntents.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

// MARK: - GatewayIntent

/// A bitset representing the collection of events to which an app will respond.
///
/// - SeeAlso: `https://discord.com/developers/docs/events/gateway#gateway-intents`
public struct GatewayIntents: OptionSet, Codable, Hashable, Sendable {
    
    /// Receive guild events
    public static let guilds = GatewayIntents(rawValue: 1 << 0)
    
    /// Receive guild member events
    public static let guildMembers = GatewayIntents(rawValue: 1 << 1)
    
    /// Receive guild moderation events
    public static let guildModeration = GatewayIntents(rawValue: 1 << 2)
    
    /// Receive emoji, sticker, and soundboard events
    public static let guildExpressions = GatewayIntents(rawValue: 1 << 3)
    
    /// Receive integration events
    public static let guildIntegrations = GatewayIntents(rawValue: 1 << 4)
    
    /// Receive webhook events
    public static let guildWebhooks = GatewayIntents(rawValue: 1 << 5)
    
    /// Receive invite management events
    public static let guildInvites = GatewayIntents(rawValue: 1 << 6)
    
    /// Receive voice state events
    public static let guildVoiceStates = GatewayIntents(rawValue: 1 << 7)
    
    /// Receive precence events.
    public static let guildPresences = GatewayIntents(rawValue: 1 << 8)
    
    /// Receive message events sent within a guild.
    /// - Note: To receive content, ``GatewayIntents/messageContent`` is required
    public static let guildMessages = GatewayIntents(rawValue: 1 << 9)
    
    /// Receive message reaction events sent within a guild.
    public static let guildMessageReactions = GatewayIntents(rawValue: 1 << 10)
    
    /// Receive message typing events sent within a guild.
    public static let guildMessageTyping = GatewayIntents(rawValue: 1 << 11)
    
    /// Receive message events sent within direct messages.
    public static let directMessages = GatewayIntents(rawValue: 1 << 12)
    
    /// Receive message reactions sent within direct messages.
    public static let directMessageReactions = GatewayIntents(rawValue: 1 << 13)
    
    /// Receive message type event sent within direct messages.
    public static let directMessageTyping = GatewayIntents(rawValue: 1 << 14)
    
    /// A unique intent required to access message content across all APIs
    /// - SeeAlso: `https://discord.com/developers/docs/events/gateway#message-content-intent`
    public static let messageContent = GatewayIntents(rawValue: 1 << 15)
    
    /// Receive scheduled event events within a guild.
    public static let guildScheduledEvents = GatewayIntents(rawValue: 1 << 16)
    
    /// Receive events when auto moderation is configured.
    public static let autoModerationConfiguration = GatewayIntents(rawValue: 1 << 20)
    
    /// Receive events with auto moderate carries out an action.
    public static let autoModerationExecution = GatewayIntents(rawValue: 1 << 21)
    
    /// Receive poll vote events within a guild.
    public static let guildMessagePolls = GatewayIntents(rawValue: 1 << 24)
    
    /// Receive poll vote events within direct messages.
    public static let directMessagePolls = GatewayIntents(rawValue: 1 << 25)
    
    /// A collection of all valid intents, for convenience.
    public static let all: GatewayIntents = [
        .guilds,
        .guildMembers,
        .guildModeration,
        .guildExpressions,
        .guildIntegrations,
        .guildWebhooks,
        .guildInvites,
        .guildVoiceStates,
        .guildPresences,
        .guildMessages,
        .guildMessageReactions,
        .guildMessageTyping,
        .directMessages,
        .directMessageReactions,
        .directMessageTyping,
        .messageContent,
        .guildScheduledEvents,
        .autoModerationConfiguration,
        .autoModerationExecution,
        .guildMessagePolls,
        .directMessagePolls
    ]
    
    /// A collection of intents for which special verification is required via the Discord developer dashboard before passing the intent to the gateway.
    ///
    /// - SeeAlso: `https://discord.com/developers/docs/events/gateway#privileged-intents`
    public static let privileged: GatewayIntents = [
        .guildPresences,
        .guildMembers,
        .messageContent
    ]
    
    /// The default intents recommended by Discord's developer documentation.
    public static let `default`: GatewayIntents = [
        .guildMessages,
        .guilds
    ]
    
    /// The raw value, combined intents.
    public let rawValue: UInt64
    
    /// Construct a new gateway intent.
    /// - Parameter rawValue: The new raw value.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

// MARK: CustomStringConvertible

extension GatewayIntents: CustomStringConvertible {
    public var description: String {
        
        if self == .all {
            return "All Intents"
        }
        
        var cases = [String]()
        
        if contains(.guilds) { cases.append("Guilds") }
        if contains(.guildMembers) { cases.append("Guild Members") }
        if contains(.guildModeration) { cases.append("Guild Moderation") }
        if contains(.guildExpressions) { cases.append("Guild Expressions") }
        if contains(.guildIntegrations) { cases.append("Guild Integrations") }
        if contains(.guildWebhooks) { cases.append("Guild Webhooks") }
        if contains(.guildInvites) { cases.append("Guild Invites") }
        if contains(.guildVoiceStates) { cases.append("Guild Voice States") }
        if contains(.guildPresences) { cases.append("Guild Presences") }
        if contains(.guildMessages) { cases.append("Guild Messages") }
        if contains(.guildMessageReactions) { cases.append("Guild Message Reactions") }
        if contains(.guildMessageTyping) { cases.append("Guild Message Typing") }
        if contains(.directMessages) { cases.append("Direct Messages") }
        if contains(.directMessageReactions) { cases.append("Direct Message Reactions") }
        if contains(.directMessageTyping) { cases.append("Direct Message Typing") }
        if contains(.messageContent) { cases.append("Message Content") }
        if contains(.guildScheduledEvents) { cases.append("Guild Scheduled Events") }
        if contains(.autoModerationConfiguration) { cases.append("Auto Moderation Configuration") }
        if contains(.autoModerationExecution) { cases.append("Auto Moderation Execution") }
        if contains(.guildMessagePolls) { cases.append("Guild Message Polls") }
        if contains(.directMessagePolls) { cases.append("Direct Message Polls") }
        
        return "\(cases.joined(separator: ", "))"
    }
}
