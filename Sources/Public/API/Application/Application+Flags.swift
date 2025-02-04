//
//  Application+Flags.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - Flags

extension Application {
    public struct Flags: OptionSet, DiscordModel {
        
        public static let applicationAutoModerationRuleCreateBadge = Flags(rawValue: 1 << 6)
        public static let gatewayPresence = Flags(rawValue: 1 << 12)
        public static let gatewayPresenceLimited = Flags(rawValue: 1 << 13)
        public static let gatewayGuildMembers = Flags(rawValue: 1 << 14)
        public static let gatewayGuildMembersLimited = Flags(rawValue: 1 << 15)
        public static let verificationPendingGuildLimit = Flags(rawValue: 1 << 16)
        public static let embedded = Flags(rawValue: 1 << 17)
        public static let gatewayMessageContent = Flags(rawValue: 1 << 18)
        public static let gatewayMessageContentLimited = Flags(rawValue: 1 << 19)
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
