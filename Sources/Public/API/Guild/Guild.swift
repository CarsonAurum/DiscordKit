//
//  Guild.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

public struct Guild: DiscordModel {
    public let id: Snowflake
    public let name: String?
    public let icon: String?
    public let iconHash: String?
    public let splash: String?
    public let discoverySplash: String?
    public let isOwner: Bool?
    public let ownerID: Snowflake?
    public let permissions: Permissions?
    public let afkChannelID: Snowflake?
    public let afkTimeout: Int?
    public let isWidgetEnabled: Bool?
    public let widgetChannelID: Snowflake?
    public let verificationLevel: VerificationLevel?
    public let defaultMessageNotifications: DefaultMessageNotificationLevel?
    public let explicitContentFilter: ExplicitContentFilter?
    public let roles: [Role]
    public let emojis: [Emoji]
    public let features: [Feature]
}
