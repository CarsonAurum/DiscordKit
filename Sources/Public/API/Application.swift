//
//  Application.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

public struct Application: DiscordModel {
    public let id: Snowflake
    public let name: String?
    public let icon: String?
    public let appDescription: String?
    public let rpcOrigins: [String]?
    public let isPublicBot: Bool?
    public let requiresCodeGrant: Bool?
    public let bot: User?
    public let termsOfServiceURL: String?
    public let privacyPolicyURL: String?
    public let owner: User?
    public let verifyKey: String?
    public let team: Team?
    public let guildID: Snowflake?
    public let guild: Guild?
    public let primarySKUID: Snowflake?
    public let slug: String?
    public let coverImage: String?
    public let flags: Flags?
    public let approximateGuildCount: Int?
    public let approximateUserInstallCount: Int?
    public let redirectURIs: [String]?
    public let interactionsEndpointURL: String?
    public let roleConnectionsVerificationURL: String?
    public let eventWebhooksURL: String?
    public let eventWebhooksStatus: EventWebhookStatus?
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
        case appDescription = "description"
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

extension Application: CustomStringConvertible {
    public var description: String {
        var values = [String]()
        values.append("\(id)")
        if let name = name { values.append(name) }
        if let icon = icon { values.append(icon) }
        if let appDescription = appDescription { values.append("Description: \(appDescription)") }
        if let rpcOrigins = rpcOrigins { values.append("RPC: \(rpcOrigins.joined(separator: ", "))") }
        if let isPublicBot = isPublicBot { values.append("Is Public Bot: \(isPublicBot)") }
        if let requiresCodeGrant = requiresCodeGrant { values.append("Requires Code Grant: \(requiresCodeGrant)") }
        if let bot = bot { values.append("Bot User: \(bot)") }
        if let termsOfServiceURL = termsOfServiceURL { values.append("TOS: \(termsOfServiceURL)") }
        if let privacyPolicyURL = privacyPolicyURL { values.append("Privacy Policy: \(privacyPolicyURL)") }
        if let owner = owner { values.append("Owner: \(owner)") }
        if let verifyKey = verifyKey { values.append("Verify Key \(verifyKey)") }
        if let team = team { values.append("\(team)") }
        if let guildID = guildID { values.append("Guild: \(guildID)") }
        if let guild = guild { values.append("Guild: \(guild)") }
        if let primarySKUID = primarySKUID { values.append("Primary SKU: \(primarySKUID)") }
        if let slug = slug { values.append("Slug: \(slug)") }
        if let coverImage = coverImage { values.append("Cover Image: \(coverImage)") }
        if let flags = flags { values.append("Flags: \(flags)") }
        if let approximateGuildCount = approximateGuildCount {
            values.append("Approximate Guild Count: \(approximateGuildCount)")
        }
        if let approximateUserInstallCount = approximateUserInstallCount {
            values.append("Approximate User Install Count: \(approximateUserInstallCount)")
        }
        if let redirectURIs = redirectURIs { values.append("Redirects: \(redirectURIs.joined(separator: ", "))") }
        if let interactionsEndpointURL = interactionsEndpointURL {
            values.append("Interactions Endpoint: \(interactionsEndpointURL)")
        }
        if let roleConnectionsVerificationURL = roleConnectionsVerificationURL {
            values.append("Role Connections Verification URL: \(roleConnectionsVerificationURL)")
        }
        if let eventWebhooksURL = eventWebhooksURL { values.append("Event Webhooks URL: \(eventWebhooksURL)") }
        if let eventWebhooksStatus = eventWebhooksStatus { values.append("Webhook Status: \(eventWebhooksStatus)") }
        if let eventWebhooksTypes = eventWebhooksTypes {
            values.append("Webhook Types: \(eventWebhooksTypes.joined(separator: ", "))")
        }
        if let tags = tags { values.append("Tags: \(tags.joined(separator: ", "))") }
        if let installParams = installParams { values.append("Install Params: \(installParams)") }
        if let integrationTypesConfig = integrationTypesConfig {
            values.append("Integration Types Config: \(integrationTypesConfig)")
        }
        if let customInstallURL = customInstallURL { values.append("Custom Install URL: \(customInstallURL)") }
        return "[\(values.joined(separator: " || "))]"
    }
}

extension Application {
    public enum IntegrationType: Int, DiscordModel {
        case guildInstall = 0
        case userInstall = 1
    }
}

extension Application.IntegrationType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .guildInstall:
            return "Guild Install"
        case .userInstall:
            return "User Install"
        }
    }
}

extension Application {
    public enum EventWebhookStatus: Int, DiscordModel {
        case disabled = 1
        case enabled = 2
        case disabledByDiscord = 3
    }
}

extension Application.EventWebhookStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .enabled:
            return "Enabled"
        case .disabledByDiscord:
            return "Disabled by Discord"
        }
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

extension Application {
    public struct InstallParams: DiscordModel {
        public let scopes: [String]
        public let permissions: String
    }
}

extension Application.InstallParams: CustomStringConvertible {
    public var description: String {
        "[Scopes: \(scopes.joined(separator: ", ")) || Permission: \(permissions)]"
    }
}
