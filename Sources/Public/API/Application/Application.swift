//
//  Application.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import NovaMacros

// MARK: - Application

/// A container for developer platform features that can be installed to discord servers and user accounts.
@CodingKeys(.custom([
    "appDescription": "description",
]))
@PrettyDescription
public struct Application: Codable, Hashable, Sendable, CustomStringConvertible {
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
    public let termsOfServiceUrl: String?
    /// URL of the app's privacy policy.
    public let privacyPolicyUrl: String?
    /// Partial user for the owner of the app.
    public let owner: User?
    /// Hex encoded key for verification in interactions and the GameSDK's GetTicket
    public let verifyKey: String?
    /// If the app belongs to a team, this will be a list of the members of that team.
    public let team: Team?
    /// Guild associated with the app.
    public let guildId: Snowflake?
    /// Partial object of the associated guild.
    public let guild: Guild?
    /// If this app is a game sold on discord, this field will be the id of the "Game SKU" that is created, if exists.
    public let primarySkuId: Snowflake?
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
    public let redirectUris: [String]?
    /// Interactions endpoint URL for the app.
    public let interactionsEndpointUrl: String?
    /// Role connection verification URL for the app.
    public let roleConnectionsVerificationUrl: String?
    /// Event webhooks URL for the app to receive webhook events.
    public let eventWebhooksUrl: String?
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
    public let customInstallUrl: String?
}
