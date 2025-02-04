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
