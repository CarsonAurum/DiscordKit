// File: Examples/OAuthApp/Sources/OAuthApp/OAuthApp.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordOAuth
import Foundation

/// Independent OAuth adoption without a Gateway connection or a concrete network backend.
@main
struct OAuthApp {
    /// Builds a fresh state/PKCE-bound consent flow without opening UI or exchanging credentials.
    /// The synthetic ID/redirect must be replaced with a registered application in a real host.
    /// A real host injects OAuthBrowserAdapter presentation, then exchanges the validated code
    /// using OAuthClient and its explicitly owned REST transport. No sensitive URL is logged.
    static func main() async {
        do {
            let flow = try OAuthAuthorizationFlow(clientID: ApplicationID(rawValue: 1),
                redirectURI: URL(string: "https://example.com/oauth/callback")!,
                scopes: ["identify", "applications.commands"], installationContext: .user)
            _ = flow.authorizationURL
            print("Constructed a state-bound user-install flow with S256 PKCE; no browser or network work started.")
        } catch {
            print("OAuth configuration is invalid.")
        }
    }
}
