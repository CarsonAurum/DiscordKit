//
//  Guild+SystemChannelFlags.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild {
    public struct SystemChannelFlags: OptionSet, DiscordModel {
        
        public static let suppressJoinNotifications = SystemChannelFlags(rawValue: 1 << 0)
        public static let suppressBoostSubscriptions = SystemChannelFlags(rawValue: 1 << 1)
        public static let suppressGuildReminderNotifications = SystemChannelFlags(rawValue: 1 << 2)
        public static let suppressJoinNotificationReplies = SystemChannelFlags(rawValue: 1 << 3)
        public static let suppressRoleSubscriptionPurchaseNotifications = SystemChannelFlags(rawValue: 1 << 4)
        public static let suppressRoleSubscriptionPurchaseNotificationReplies = SystemChannelFlags(rawValue: 1 << 5)
        
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
}
