// File: Sources/DiscordOAuth/OAuthInstallationURL.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A callbackless bot/application-command installation URL using Discord's fixed authorization origin.
/// Installing does not acquire a user bearer token or establish guild membership. Portal-enabled contexts,
/// bot visibility, requested permissions and the installer's authority remain Discord's server-side checks.
public struct OAuthInstallationURL: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let url: URL

    /// Builds the documented callbackless bot or command installation URL without starting browser or network work.
    /// - Parameters:
    ///   - clientID: Nonzero application snowflake, preserving all unsigned 64 bits.
    ///   - scopes: Nonempty subset of bot/applications.commands, default both. Other scopes require a full
    ///     `OAuthAuthorizationFlow` because they acquire a user authorization code.
    ///   - installationContext: Guild installation by default; user installation permits only applications.commands.
    ///     The app must enable the selected context in the Developer Portal.
    ///   - permissions: Optional nonempty ASCII decimal bot permission bits, at most 256 digits. Unknown/future bits
    ///     are retained exactly; requires bot scope and guild context. No implicit administrator permission is added.
    ///   - guildID: Optional nonzero preferred guild, meaningful only for guild installation. This is an untrusted UI hint.
    ///   - disableGuildSelection: Whether to lock the supplied guild hint, default false; requires guildID.
    /// - Throws: `OAuthError.invalidRequest` for invalid scopes, zero IDs, malformed/oversized decimal permission bits,
    ///   a locked selection without a guild, or guild/bot options in a user installation. No secrets are accepted.
    /// The generated URL omits response_type, redirect_uri, state and proof-key fields by design; it has no callback to consume.
    public init(clientID: ApplicationID, scopes: Set<String> = ["bot", "applications.commands"],
                installationContext: OAuthInstallationContext = .guild, permissions: String? = nil,
                guildID: GuildID? = nil, disableGuildSelection: Bool = false) throws {
        guard clientID.rawValue != 0, guildID?.rawValue != 0, !scopes.isEmpty,
              scopes.isSubset(of: ["bot", "applications.commands"]),
              !disableGuildSelection || guildID != nil,
              permissions.map({ scopes.contains("bot") && !$0.isEmpty && $0.utf8.count <= 256 &&
                  $0.utf8.allSatisfy({ (48...57).contains($0) }) }) ?? true,
              installationContext != .user || (!scopes.contains("bot") && permissions == nil && guildID == nil)
        else { throw OAuthError.invalidRequest }
        var components = URLComponents(string: "https://discord.com/oauth2/authorize")!
        var fields = [URLQueryItem(name: "client_id", value: clientID.description),
            URLQueryItem(name: "scope", value: scopes.sorted().joined(separator: " ")),
            URLQueryItem(name: "integration_type", value: String(installationContext.rawValue))]
        if let permissions { fields.append(URLQueryItem(name: "permissions", value: permissions)) }
        if let guildID { fields.append(URLQueryItem(name: "guild_id", value: guildID.description)) }
        if disableGuildSelection { fields.append(URLQueryItem(name: "disable_guild_select", value: "true")) }
        components.queryItems = fields
        url = components.url!
    }

    /// Conceals requested permissions and guild hints in ordinary diagnostics.
    public var description: String { "OAuthInstallationURL(redacted)" }
    /// Conceals requested permissions and guild hints in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostics from exposing installation metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
