//
//  Application.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - Application

/// A container for developer platform features that can be installed to discord servers and user accounts.
public struct Application: DiscordModel {
    
    /// The ID of the application.
    public let id: Snowflake
    
    /// The name of the app.
    public let name: String?
    
    /// The icon hash of the app.
    public let icon: String?
    
    /// Description of the app
    public let appDescription: String?
    
    /// List of RPC origin URLs, if RPC is enabled.
    public let rpcOrigins: [String]?
    
    /// When `false`, only the app owner can add the app to guilds.
    public let isPublicBot: Bool?
    
    /// When `true` the app's bot will only join on completion of the full OAuth2 code grant flow.
    public let requiresCodeGrant: Bool?
    
    /// Partial user object for the bot associated with the app.
    public let bot: User?
    
    /// URL of the app's terms of service.
    public let termsOfServiceURL: String?
    
    /// URL of the app's privacy policy.
    public let privacyPolicyURL: String?
    
    /// Partial user for the owner of the app.
    public let owner: User?
    
    /// Hex encoded key for verification in interactions and the GameSDK's GetTicket
    public let verifyKey: String?
    
    /// If the app belongs to a team, this will be a list of the members of that team.
    public let team: Team?
    
    /// Guild associated with the app.
    public let guildID: Snowflake?
    
    /// Partial object of the associated guild.
    public let guild: Guild?
    
    /// If this app is a game sold on discord, this field will be the id of the "Game SKU" that is created, if exists.
    public let primarySKUID: Snowflake?
    
    /// If this app is a game sold on discord, this field will be the URL slug that links to the store page.
    public let slug: String?
    
    /// App's default rich presence invite cover hash.
    public let coverImage: String?
    
    /// Apps public flags.
    public let flags: Flags?
    
    /// Approximate count of the guilds the app has been added to.
    public let approximateGuildCount: Int?
    
    /// Approximate count of users that have installed the app.
    public let approximateUserInstallCount: Int?
    
    /// Array of redirect URIs for the app.
    public let redirectURIs: [String]?
    
    /// Interactions endpoint URL for the app.
    public let interactionsEndpointURL: String?
    
    /// Role connection verification URL for the app.
    public let roleConnectionsVerificationURL: String?
    
    /// Event webhooks URL for the app to receive webhook events.
    public let eventWebhooksURL: String?
    
    /// If webhook events are enabled for the app, this value will be filled.
    public let eventWebhooksStatus: EventWebhookStatus?
    
    /// List of webhook event types the app subscribes to.
    public let eventWebhooksTypes: [String]?
    
    /// List of tags describing the content and functionality of the app.
    public let tags: [String]?
    
    /// Settings for the app's default in-app authorization link, if enabled.
    public let installParams: InstallParams?
    
    /// Default scopes and permissions for each supported installation context.
    public let integrationTypesConfig: [IntegrationType: String]?
    
    /// Default custom authorization URL for the app, if enabled.
    public let customInstallURL: String?
}

// MARK: Codable

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

// MARK: CustomStringConvertible

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

// MARK: - IntegrationType

extension Application {
    
    /// Where an app can be installed.
    public enum IntegrationType: Int, DiscordModel {
        
        /// App is installable to servers.
        case guildInstall = 0
        
        /// App is installable to users.
        case userInstall = 1
    }
}

// MARK: CustomStringConvertible

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

// MARK: - IntegrationTypeConfiguration

extension Application {
    
    /// Configuration for a specific installation context.
    public struct IntegrationTypeConfiguration: DiscordModel {
        
        /// Install params for the specific in-app authorization context.
        public let installParams: InstallParams?
    }
}

// MARK: Codable

extension Application.IntegrationTypeConfiguration {
    enum CodingKeys: String, CodingKey {
        case installParams = "oauth2_install_params"
    }
}

// MARK: CustomStringConvertible

extension Application.IntegrationTypeConfiguration: CustomStringConvertible {
    public var description: String {
        if let installParams = installParams {
            return "\(installParams)"
        } else {
            return "None"
        }
    }
}

// MARK: - EventWebhookStatus

extension Application {
    
    /// Status indicating whether event webhooks are enabled or disabled for an application.
    public enum EventWebhookStatus: Int, DiscordModel {
        
        /// Webhook events disabled by developer.
        case disabled = 1
        
        /// Webhook events enabled by developer.
        case enabled = 2
        
        /// Webhook events disabled by discord -- usually due to activity.
        case disabledByDiscord = 3
    }
}

// MARK: CustomStringConvertible

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
