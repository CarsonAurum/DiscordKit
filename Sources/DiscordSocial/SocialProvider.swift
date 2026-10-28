// File: Sources/DiscordSocial/SocialProvider.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// Host capabilities explicitly asserted by the embedding application after qualification.
/// A desktop IPC adapter never implies a mobile or console Social integration.
public enum SocialHost: String, Sendable, Hashable, CaseIterable {
    case none, desktopRPC, activityHost, nativeAudio
}

/// Static prerequisites for one narrow provider; availability remains session-specific.
public struct SocialProviderRequirements: Sendable, Equatable {
    public let host: SocialHost
    public let scopes: Set<String>

    /// Stores exact host and OAuth scope requirements without probing or authorizing anything.
    /// - Parameters:
    ///   - host: Required qualified host, or `.none` for public HTTP; default `.none`.
    ///   - scopes: Exact approved user scopes. Defaults to empty; a bot never supplies these.
    public init(host: SocialHost = .none, scopes: Set<String> = []) {
        self.host = host; self.scopes = scopes
    }
}

/// Small validated presence common to the owned RPC and Activity providers.
/// Extended activity fields remain available on those providers' typed APIs.
public struct SocialPresence: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public let name: String
    public let details: String?
    public let state: String?

    /// Validates at most three bounded display strings without issuing a presence update.
    /// - Parameters:
    ///   - name: Nonempty name, at most 128 UTF-8 bytes. Activity providers require their
    ///     configured application name because the host owns the response-only name field.
    ///   - details: Optional display detail, at most 128 UTF-8 bytes; nil omits the field.
    ///   - state: Optional display state, at most 128 UTF-8 bytes; nil omits the field.
    /// - Throws: `SocialFailure.invalidConfiguration` for empty name or excessive bytes.
    public init(name: String, details: String? = nil, state: String? = nil) throws {
        guard !name.isEmpty, name.utf8.count <= 128,
              (details?.utf8.count ?? 0) <= 128, (state?.utf8.count ?? 0) <= 128 else {
            throw SocialFailure.invalidConfiguration
        }
        self.name = name; self.details = details; self.state = state
    }

    /// Conceals display text, which can contain user-provided private information.
    public var description: String { "SocialPresence(redacted)" }

    /// Prevents reflection from expanding display strings.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Narrow user-profile reader over a caller-owned, already configured public HTTP client.
public protocol SocialProfileProvider<ProviderClock>: Sendable {
    associatedtype ProviderClock: Clock where ProviderClock.Duration == Duration
    /// Exact scopes and host prerequisites; this declaration performs no I/O.
    var profileRequirements: SocialProviderRequirements {
        /// Reads the provider's declared profile prerequisites without performing authorization or I/O.
        /// - Returns: Required scopes and host capabilities for consent coordination; the declaration
        ///   does not prove that the current account has granted scopes or that a host is available.
        get
    }
    /// Reads the authenticated user's profile using the documented v10 `/users/@me` route.
    /// - Parameter context: Monotonic deadline/cancellation shared with the owning client.
    /// - Returns: Complete implemented `User` projection; no identity or scope is inferred.
    /// - Throws: Cancellation, deadline, authentication, rate-limit, transport or schema errors.
    func currentProfile(context: TransportContext<ProviderClock>) async throws -> User
}

/// Narrow presence writer over an explicitly selected and authorized local/browser host.
public protocol SocialPresenceProvider<ProviderClock>: Sendable {
    associatedtype ProviderClock: Clock where ProviderClock.Duration == Duration
    /// Exact approved scopes and qualified host needed for this provider.
    var presenceRequirements: SocialProviderRequirements {
        /// Reads the provider's declared presence prerequisites without mutating presence or starting work.
        /// - Returns: Required approved scopes and host capabilities; actual consent and host
        ///   availability must still be checked before the owning client admits a mutation.
        get
    }
    /// Writes one bounded presence; mutation failures are never automatically replayed.
    /// - Parameters:
    ///   - presence: Common display fields; host-specific limitations must fail explicitly.
    ///   - context: Shared monotonic deadline/cancellation; implementations cooperate with both.
    /// - Throws: Cancellation, deadline, host, validation, authentication or ambiguous I/O errors.
    func updatePresence(_ presence: SocialPresence, context: TransportContext<ProviderClock>) async throws
}

/// Safe coordination failures; arbitrary provider errors and payloads are not diagnostic text.
public enum SocialFailure: Error, Sendable, Equatable {
    case invalidConfiguration, closed, unauthorized, unavailableHost, missingScope
    case missingProvider, overloaded, mutationInProgress, staleSession, accountMismatch
    case providerFailure
}
