//
//  Application.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

public struct Application: DiscordModel {
    public let id: Snowflake
    public let name: String
    public let icon: String?
    public let description: String
    public let rpcOrigins: [String]?
    public let isPublicBot: Bool
    public let requiresCodeGrant: Bool
    public let bot: User?
    public let termsOfServiceURL: String?
    public let privacyPolicyURL: String?
    public let owner: User?
    public let verifyKey: String
    public let team: Team?
    public let guildID: Snowflake
    public let guild: Guild?
    public let primarySKUID: Snowflake?
    public let slug: String?
    public let coverImage: String?
    public let flags: Flags
    public let approximateGuildCount: Int?
    public let approximateUserInstallCount: Int?
    public let redirectURIs: [String]?
    public let interactionsEndpointURL: String?
    public let roleConnectionsVerificationURL: String?
    public let eventWebhooksURL: String?
    public let eventWebhooksStatus: EventWebhookStatus
    public let eventWebhooksTypes: [String]?
    public let tags: [String]?
    public let installParams: InstallParams?
    public let integrationTypesConfig: [IntegrationType: String]?
    public let customInstallURL: String?
}

extension Application {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case description
        case rpcOrigins = "rpc_origins"
        case isPublicBot = "bot_public"
        case requiresCodeGrant = "bot_require_code_grant"
        case bot
        case termsOfServiceURL = "terms_of_service_url"
        case privacyPolicyURL = "privacy_policy_url"
        case owner
        case verifyKey = "verify_key"
        case team
        case guildID = "guild_id"
        case guild
        case primarySKUID = "primary_sku_id"
        case slug
        case coverImage = "cover_image"
        case flags
        case approximateGuildCount = "approximate_guild_count"
        case approximateUserInstallCount = "approximate_user_install_count"
        case redirectURIs = "redirect_uris"
        case interactionsEndpointURL = "interactions_endpoint_url"
        case roleConnectionsVerificationURL = "role_connections_verification_url"
        case eventWebhooksURL = "event_webhooks_url"
        case eventWebhooksStatus = "event_webhooks_status"
        case eventWebhooksTypes = "event_webhooks_types"
        case tags
        case installParams = "install_params"
        case integrationTypesConfig = "integration_types_config"
        case customInstallURL = "custom_install_url"
    }
}

extension Application {
    public enum IntegrationType: Int, DiscordModel {
        case guildInstall = 0
        case userInstall = 1
    }
}

extension Application {
    public enum EventWebhookStatus: Int, DiscordModel {
        case disabled = 1
        case enabled = 2
        case disabledByDiscord = 3
    }
}

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

extension Application {
    public struct InstallParams: DiscordModel {
        public let scopes: [String]
        public let permissions: String
    }
}
