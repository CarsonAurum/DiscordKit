// File: Sources/DiscordCore/Credentials.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// A secret string whose ordinary descriptions and reflection conceal its value.
///
/// Secrets deliberately do not conform to `Codable` or `RawRepresentable`.
/// This is diagnostic hygiene, not encrypted memory or a sandbox: callers with
/// explicit access can copy the value, and Swift strings do not guarantee erasure.
public struct Secret<Tag>: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private let value: String

    /// Stores a nonempty credential after rejecting Unicode whitespace and controls.
    /// Format, expiry, permissions and server acceptance remain unverified.
    /// - Parameter value: The exact token or secret, without an authorization prefix.
    /// - Throws: `DiscordError.validation(.emptyCredential)` for empty strings, or
    ///   `.invalidCredential` for whitespace/control characters, including CR/LF.
    public init(_ value: String) throws {
        guard !value.isEmpty else { throw DiscordError.validation(.emptyCredential) }
        guard !value.unicodeScalars.contains(where: {
            $0.properties.isWhitespace || $0.properties.generalCategory == .control
        }) else { throw DiscordError.validation(.invalidCredential) }
        self.value = value
    }

    /// Explicitly exposes the secret to a synchronous adapter operation.
    /// The closure can retain/copy the string; callers must prevent it from reaching
    /// logs, arbitrary origins or diagnostics. No allocation wiping is promised.
    /// - Parameter body: A synchronous operation using the exact secret.
    /// - Returns: The closure's result, which the caller must handle securely.
    /// - Throws: Rethrows only errors from `body`, without wrapping their descriptions.
    public func withUnsafeValue<Result>(_ body: (String) throws -> Result) rethrows -> Result {
        try body(value)
    }

    /// A fixed marker independent of secret content or length.
    public var description: String { "[REDACTED]" }

    /// A fixed marker used by `String(reflecting:)` and debug output.
    public var debugDescription: String { "[REDACTED]" }

    /// A diagnostic mirror containing no secret value, prefix or length.
    public var customMirror: Mirror {
        Mirror(self, children: ["value": "[REDACTED]"])
    }
}

/// Marks a bot token; it cannot be substituted for an OAuth bearer token.
public enum BotTokenTag: Sendable {}
/// Marks an OAuth2 bearer access token.
public enum BearerTokenTag: Sendable {}
/// Marks an interaction callback/followup token.
public enum InteractionTokenTag: Sendable {}
/// Marks a webhook token.
public enum WebhookTokenTag: Sendable {}
/// Marks a confidential OAuth2 client secret.
public enum ClientSecretTag: Sendable {}
/// A redacted bot authentication secret.
public typealias BotToken = Secret<BotTokenTag>
/// A redacted OAuth2 bearer authentication secret.
public typealias BearerToken = Secret<BearerTokenTag>
/// A redacted interaction token; endpoint-specific lifetime is checked elsewhere.
public typealias InteractionToken = Secret<InteractionTokenTag>
/// A redacted webhook authentication secret.
public typealias WebhookToken = Secret<WebhookTokenTag>
/// A redacted confidential-client secret, unsuitable for distribution in public apps.
public typealias ClientSecret = Secret<ClientSecretTag>

/// Typed credential selection without a live authentication or origin policy.
/// Adapters must apply endpoint permissions, token lifetimes and origin checks;
/// merely possessing a credential does not authorize sending it anywhere.
public enum Credential: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    /// An operation that intentionally carries no credential.
    case none
    /// Bot authentication, distinct from bearer authentication.
    case bot(BotToken)
    /// OAuth2 bearer authentication.
    case bearer(BearerToken)
    /// An interaction token carried in an endpoint path.
    case interaction(InteractionToken)
    /// A webhook identifier plus its path-carried secret token.
    case webhook(WebhookID, WebhookToken)

    /// A fixed category label that conceals all associated values.
    public var description: String {
        switch self {
        case .none: "Credential.none"
        case .bot: "Credential.bot([REDACTED])"
        case .bearer: "Credential.bearer([REDACTED])"
        case .interaction: "Credential.interaction([REDACTED])"
        case .webhook: "Credential.webhook([REDACTED])"
        }
    }

    /// The same safe category label used by the ordinary description.
    public var debugDescription: String { description }

    /// A mirror exposing only the safe category description.
    public var customMirror: Mirror {
        Mirror(self, children: ["credential": description])
    }
}
