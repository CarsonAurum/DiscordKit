import DiscordCore
import Foundation
import Testing
@testable import DiscordOAuth

/// Callbackless installation tests verify URL construction without browser, authentication or network work.
@Suite struct OAuthInstallationURLTests {
    /// Guild installs retain full-width identifiers/permission bits while omitting user-token callback fields.
    /// - Throws: Unexpected fixed-fixture validation failures.
    @Test func guildInstallation() throws {
        let installation = try OAuthInstallationURL(clientID: .init(rawValue: .max),
            permissions: "18446744073709551616", guildID: .init(rawValue: .max), disableGuildSelection: true)
        #expect(installation.url.scheme == "https")
        #expect(installation.url.host == "discord.com")
        #expect(installation.url.path == "/oauth2/authorize")
        #expect(installation.url.port == nil)
        #expect(installation.url.user == nil)
        #expect(installation.url.fragment == nil)
        #expect(installation.url.absoluteString.contains("scope=applications.commands%20bot"))
        let fields = try #require(URLComponents(url: installation.url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value ?? "") })
        #expect(values["client_id"] == "18446744073709551615")
        #expect(values["permissions"] == "18446744073709551616")
        #expect(values["guild_id"] == "18446744073709551615")
        #expect(values["disable_guild_select"] == "true")
        #expect(values["integration_type"] == "0")
        for field in ["response_type", "redirect_uri", "state", "code_challenge", "client_secret"] { #expect(values[field] == nil) }
        #expect(installation.description == "OAuthInstallationURL(redacted)")
        #expect(installation.debugDescription == installation.description)
        #expect(installation.customMirror.children.count == 1)
        _ = try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["bot"], permissions: "0")
        _ = try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["bot"], permissions: String(repeating: "9", count: 256))
    }

    /// User installation requests commands without bot or guild metadata; default guild selection remains optional.
    /// - Throws: Unexpected fixed-fixture validation failures.
    @Test func userInstallation() throws {
        let installation = try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["applications.commands"], installationContext: .user)
        #expect(installation.url.absoluteString == "https://discord.com/oauth2/authorize?client_id=1&scope=applications.commands&integration_type=1")
        let defaults = try OAuthInstallationURL(clientID: .init(rawValue: 1))
        #expect(!defaults.url.absoluteString.contains("permissions="))
        #expect(!defaults.url.absoluteString.contains("guild_id="))
        #expect(!defaults.url.absoluteString.contains("disable_guild_select="))
    }

    /// Rejects user-token scopes, malformed permissions, missing locked guilds and incompatible user-install options.
    /// - Throws: Unexpected secret-free fixture setup failures.
    @Test func invalidInstallations() throws {
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 0)) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: []) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["identify"]) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["applications.commands"], permissions: "1") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), guildID: .init(rawValue: 0)) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), disableGuildSelection: true) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), installationContext: .user) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), scopes: ["applications.commands"], installationContext: .user, guildID: .init(rawValue: 2)) }
        for permissions in ["", "-1", "+1", "1 2", "1&redirect_uri=https://evil.example", "١", String(repeating: "9", count: 257)] {
            #expect(throws: OAuthError.invalidRequest) { try OAuthInstallationURL(clientID: .init(rawValue: 1), permissions: permissions) }
        }
    }
}
