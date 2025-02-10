//
//  Message+Flags.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/8/25.
//

extension Message {
    public struct Flags: OptionSet, DiscordModel {
        
        public static let crossposted = Flags(rawValue: 1 << 0)
        public static let isCrosspost = Flags(rawValue: 1 << 1)
        public static let suppressEmbeds = Flags(rawValue: 1 << 2)
        public static let sourceMessageDeleted = Flags(rawValue: 1 << 3)
        public static let urgent = Flags(rawValue: 1 << 4)
        public static let hasThread = Flags(rawValue: 1 << 5)
        public static let ephemeral = Flags(rawValue: 1 << 6)
        public static let loading = Flags(rawValue: 1 << 7)
        public static let failedToMentionSomeRolesInThread = Flags(rawValue: 1 << 8)
        public static let suppressNotifications = Flags(rawValue: 1 << 12)
        public static let isVoiceMessage = Flags(rawValue: 1 << 13)
        public static let hasSnapshot = Flags(rawValue: 1 << 14)
        
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
}
