//
//  Application+Flags.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - Flags

extension Application {
    /// An app's public flags
    public struct Flags: OptionSet, DiscordModel {
        /// Indicates if an app uses the automoderation API.
        public static let applicationAutoModerationRuleCreateBadge = Flags(rawValue: 1 << 6)
        /// Intent required for bots in 100 or more servers to receive presence update events.
        public static let gatewayPresence = Flags(rawValue: 1 << 12)
        /// Intent required for bots in under 100 servers to receive presence update events.
        public static let gatewayPresenceLimited = Flags(rawValue: 1 << 13)
        /// Intent required for bots in 100 or more servers to receive member-related events.
        public static let gatewayGuildMembers = Flags(rawValue: 1 << 14)
        /// Intent required for bots in under 100 servers to receive member related events.
        public static let gatewayGuildMembersLimited = Flags(rawValue: 1 << 15)
        /// Indicates unusual growth of an app that prevents verification.
        public static let verificationPendingGuildLimit = Flags(rawValue: 1 << 16)
        /// Indicates if an app is embedded within the Discord client.
        public static let embedded = Flags(rawValue: 1 << 17)
        /// Intent required for bots in 100 or more servers to receive message content.
        public static let gatewayMessageContent = Flags(rawValue: 1 << 18)
        /// Intent required for bots in under 100 servers to receive message content.
        public static let gatewayMessageContentLimited = Flags(rawValue: 1 << 19)
        /// Indicates if an app has registered global application commands.
        public static let applicationCommandBadge = Flags(rawValue: 1 << 23)
        
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension Application.Flags: CustomStringConvertible {
    public var description: String {
        var result: [String] = []
        if self.contains(.applicationAutoModerationRuleCreateBadge) {
            result.append("App Auto Moderation Rule Create Bage")
        }
        if self.contains(.gatewayPresence) { result.append("Gateway Presence") }
        if contains(.gatewayPresenceLimited) { result.append("Gateway Presence (Limited)") }
        if contains(.gatewayGuildMembers) { result.append("Gateway Guild Members") }
        if contains(.gatewayGuildMembersLimited) { result.append("Gateway Guild Members (Limited)") }
        if contains(.verificationPendingGuildLimit) { result.append("Verification Pending Guild Limit") }
        if contains(.embedded) { result.append("Embedded") }
        if contains(.gatewayMessageContent) { result.append("Gateway Message Content") }
        if contains(.gatewayMessageContentLimited) { result.append("Gateway Message Content (Limited)") }
        if contains(.applicationCommandBadge) { result.append("Application Command Badge") }
        return "[\(result.joined(separator: ", "))]"
    }
}
