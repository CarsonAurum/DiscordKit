// File: Sources/DiscordSocial/SocialModels.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Exact authorization domain for application-supplied social observations.
///
/// A scope is neither a credential nor proof of consent. The application must verify
/// consent and assign a fresh generation whenever that consent, identity, or visibility
/// changes. No token is stored, and observations never cross an exact scope boundary.
public struct SocialScope: Equatable, Hashable, Sendable {
    /// Application for which the provider obtained authorized observations.
    public let applicationID: ApplicationID
    /// Signed-in account whose social relationships are represented.
    public let accountID: UserID
    /// Caller-owned authorization generation; rotate after revocation or account changes.
    public let consentGeneration: UInt64

    /// Binds one account's observations to an exact application and consent generation.
    /// - Parameters:
    ///   - applicationID: Nonzero Discord application identifier, validated on activation.
    ///   - accountID: Nonzero authenticated account identifier, validated on activation.
    ///   - consentGeneration: Fresh caller-owned generation; zero is accepted.
    public init(applicationID: ApplicationID, accountID: UserID, consentGeneration: UInt64) {
        self.applicationID = applicationID
        self.accountID = accountID
        self.consentGeneration = consentGeneration
    }
}

/// Application-normalized user display data; this is not a Discord wire projection.
///
/// The trusted provider selects only authorized fields. All strings remain display
/// data and must be escaped by the presentation layer. Store admission bounds UTF-8
/// bytes; construction performs no lookup, authorization, persistence, or I/O.
public struct SocialUser: Equatable, Sendable {
    /// Exact unsigned Discord user identifier.
    public let id: UserID
    /// Provider-supplied username; empty strings remain valid display data.
    public let username: String
    /// Optional display name; nil means unavailable or explicitly cleared.
    public let displayName: String?
    /// Optional avatar reference; it is retained without fetching or interpreting URLs.
    public let avatar: String?
    /// Optional trusted-provider presence; unavailable presence never implies offline or online.
    public let presence: SocialUserPresence?

    /// Creates immutable display data for later bounded store admission.
    /// - Parameters:
    ///   - id: Nonzero user identifier, validated by store admission.
    ///   - username: Exact provider-supplied username, including an empty value.
    ///   - displayName: Optional display name; defaults to unavailable.
    ///   - avatar: Optional opaque avatar reference; defaults to unavailable.
    ///   - presence: Optional complete presence observation for the exact snapshot/event scope; defaults to unavailable.
    public init(id: UserID, username: String, displayName: String? = nil, avatar: String? = nil,
                presence: SocialUserPresence? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.presence = presence
    }
}

/// Provider-normalized availability; cases deliberately have no invented Discord wire values.
public enum SocialUserPresenceStatus: Equatable, Sendable {
    /// Online and available.
    case online
    /// Online with idle availability.
    case idle
    /// Online with do-not-disturb availability; this does not authorize contact.
    case doNotDisturb
    /// Explicitly observed offline, irrespective of any retained activity metadata.
    case offline
    /// Unrecognized provider status; it never becomes online or offline by inference.
    case unknown(Int)
}

/// Fixed-size application-supplied presence metadata, scoped by its enclosing observation.
///
/// This model owns no remote presence feed. Status, current activity, and prior-play
/// knowledge must come from the authorized provider for the exact account/application
/// scope. There is one optional application ID and one boolean, so metadata cannot
/// accumulate activity arrays, history, strings, or additional unbounded state.
public struct SocialUserPresence: Equatable, Sendable {
    /// Exact normalized availability; unknown values remain unknown.
    public let status: SocialUserPresenceStatus
    /// Currently played application, or nil if absent/unavailable; store admission rejects zero.
    public let playingApplicationID: ApplicationID?
    /// Whether the trusted provider knows this user previously played the enclosing scope's application.
    public let hasPlayedScopedApplication: Bool

    /// Creates bounded complete presence metadata without lookup, subscription, or remote authorization.
    /// - Parameters:
    ///   - status: Provider-normalized availability, preserving unknown cases.
    ///   - playingApplicationID: Optional nonzero current application; defaults to unavailable.
    ///   - hasPlayedScopedApplication: Provider-supplied prior-play knowledge for the enclosing scope;
    ///     defaults to false when unestablished and never transfers between application scopes.
    public init(status: SocialUserPresenceStatus, playingApplicationID: ApplicationID? = nil,
                hasPlayedScopedApplication: Bool = false) {
        self.status = status
        self.playingApplicationID = playingApplicationID
        self.hasPlayedScopedApplication = hasPlayedScopedApplication
    }
}

/// Local relationship list groups derived from authorized availability and exact scoped game activity.
public enum SocialPresenceGroup: Equatable, Sendable {
    /// Online/idle/do-not-disturb users playing the exact enclosing application.
    case onlinePlayingGame
    /// Online/idle/do-not-disturb users without that exact application activity.
    case onlineElsewhere
    /// Explicitly observed offline users.
    case offline
    /// Users with absent or unrecognized availability; never inferred online or offline.
    case unknown
}

/// Local relationship groups normalized by an authorized application provider.
///
/// Cases have no wire values. Unknown provider kinds retain their integer identity
/// without becoming a friend or an authorization grant. Being unblocked or a friend
/// never independently authorizes chat, voice, presence, purchases, or account linking.
public enum SocialRelationshipKind: Equatable, Hashable, Sendable {
    /// An accepted friendship observed by the authorized provider.
    case friend
    /// A request received by the signed-in account.
    case incomingRequest
    /// A request sent by the signed-in account.
    case outgoingRequest
    /// A user blocked by the signed-in account.
    case blocked
    /// An unmodeled provider kind, preserved without guessing its behavior.
    case unknown(Int)
}

/// One complete relationship observation for the scoped account and another user.
public struct SocialRelationship: Equatable, Sendable {
    /// User to whom this relationship applies.
    public let userID: UserID
    /// Provider-normalized relationship category.
    public let kind: SocialRelationshipKind

    /// Constructs a relationship without performing a remote mutation.
    /// - Parameters:
    ///   - userID: Nonzero user identifier with a matching admitted user record.
    ///   - kind: Exact provider-normalized category; unknown values remain distinct.
    public init(userID: UserID, kind: SocialRelationshipKind) {
        self.userID = userID
        self.kind = kind
    }
}

/// Fixed resident-state limits for a single account; there are no hidden event queues.
public struct SocialStateLimits: Equatable, Sendable {
    /// Maximum distinct users retained, including users without a relationship.
    public let maximumUsers: Int
    /// Maximum distinct relationships retained.
    public let maximumRelationships: Int
    /// Maximum total UTF-8 bytes in one user's username, display name, and avatar.
    public let maximumUserStringBytes: Int
    /// Maximum sum of retained users' string bytes, excluding fixed Swift object overhead.
    public let maximumTotalStringBytes: Int

    /// Validates positive account-local resident-state budgets.
    /// - Parameters:
    ///   - maximumUsers: Positive user count; defaults to 4,096.
    ///   - maximumRelationships: Positive relationship count; defaults to 4,096.
    ///   - maximumUserStringBytes: Positive per-user UTF-8 byte limit; defaults to 4,096.
    ///   - maximumTotalStringBytes: Positive aggregate UTF-8 byte limit; defaults to 4 MiB.
    /// - Throws: `SocialStateError.invalidLimits` if any limit is not positive.
    public init(
        maximumUsers: Int = 4_096,
        maximumRelationships: Int = 4_096,
        maximumUserStringBytes: Int = 4_096,
        maximumTotalStringBytes: Int = 4_194_304
    ) throws {
        guard maximumUsers > 0, maximumRelationships > 0,
            maximumUserStringBytes > 0, maximumTotalStringBytes > 0
        else { throw SocialStateError.invalidLimits }
        self.maximumUsers = maximumUsers
        self.maximumRelationships = maximumRelationships
        self.maximumUserStringBytes = maximumUserStringBytes
        self.maximumTotalStringBytes = maximumTotalStringBytes
    }
}

/// A complete authorized baseline for one provider connection generation.
///
/// Generation/sequence are local provider ordering metadata, not invented Discord
/// protocol fields. A snapshot must include each relationship's complete user.
public struct SocialStateSnapshot: Equatable, Sendable {
    /// Exact account/application/consent domain.
    public let scope: SocialScope
    /// Monotonic provider connection generation; a new connection uses a higher value.
    public let generation: UInt64
    /// Last observation included in this complete baseline.
    public let sequence: UInt64
    /// Complete authorized users; duplicate identifiers are invalid.
    public let users: [SocialUser]
    /// Complete authorized relationships; duplicate or dangling identifiers are invalid.
    public let relationships: [SocialRelationship]

    /// Wraps a complete baseline for atomic store validation and replacement.
    /// - Parameters:
    ///   - scope: Previously activated exact authorization domain.
    ///   - generation: Provider-owned connection generation.
    ///   - sequence: Last included provider sequence, including zero or `UInt64.max`.
    ///   - users: Complete user records within configured limits.
    ///   - relationships: Complete relationship records referencing `users`.
    public init(
        scope: SocialScope, generation: UInt64, sequence: UInt64,
        users: [SocialUser], relationships: [SocialRelationship]
    ) {
        self.scope = scope
        self.generation = generation
        self.sequence = sequence
        self.users = users
        self.relationships = relationships
    }
}

/// A single complete provider change; omitted fields never silently patch a user.
public enum SocialStateChange: Equatable, Sendable {
    /// Replace or insert complete user display data.
    case upsertUser(SocialUser)
    /// Remove a user and its relationship together to prevent dangling references.
    case removeUser(UserID)
    /// Replace or insert a relationship for an already present user.
    case upsertRelationship(SocialRelationship)
    /// Remove the relationship while retaining its independently authorized user data.
    case removeRelationship(UserID)
}

/// An exact-scope ordered change supplied by an application-controlled provider.
public struct SocialStateEvent: Equatable, Sendable {
    /// Exact account/application/consent domain.
    public let scope: SocialScope
    /// Connection generation in which this change was observed.
    public let generation: UInt64
    /// Contiguous sequence after the admitted baseline or prior event.
    public let sequence: UInt64
    /// One complete bounded mutation.
    public let change: SocialStateChange

    /// Wraps an event without opening a subscription or executing a remote operation.
    /// - Parameters:
    ///   - scope: Exact previously activated domain.
    ///   - generation: Provider connection generation.
    ///   - sequence: Next sequence; duplicates/older values are ignored.
    ///   - change: Complete normalized state change, validated at admission.
    public init(scope: SocialScope, generation: UInt64, sequence: UInt64, change: SocialStateChange) {
        self.scope = scope
        self.generation = generation
        self.sequence = sequence
        self.change = change
    }
}

/// Whether local relationship queries can currently present a complete baseline.
public enum SocialSynchronization: Equatable, Sendable {
    /// No consent scope is active; no account data is retained.
    case inactive
    /// An active scope requires a fresh complete snapshot; no account data is exposed.
    case needsSnapshot
    /// A complete baseline and all following admitted events are present.
    case synchronized
}

/// Observable result of ordered local state admission.
public enum SocialApplyOutcome: Equatable, Sendable {
    /// A complete snapshot or contiguous event was installed.
    case applied
    /// A duplicate/older snapshot or event was ignored without changing state.
    case ignoredStale
    /// The event cannot establish a baseline; the caller must request a full snapshot.
    case requiresSnapshot
}

/// Sanitized local validation failures; errors never contain user display data.
public enum SocialStateError: Error, Equatable, Sendable {
    /// A configured resident-state budget was not positive.
    case invalidLimits
    /// Application/account, admitted user, or present activity application identifier was zero.
    case invalidIdentifier
    /// No active consent domain exists, or the supplied domain differs exactly.
    case scopeMismatch
    /// A complete snapshot repeated a user or relationship identifier.
    case duplicateIdentifier
    /// A relationship referenced a user absent from the same admitted state.
    case missingUser
    /// A resident count or string-byte limit would be exceeded.
    case capacityExceeded
}

/// Immutable account-local query result copied from the actor without hidden I/O.
///
/// Arrays are sorted by exact unsigned user identifier for deterministic rendering.
/// This value is an ephemeral local observation and grants no remote permissions.
public struct SocialStateView: Equatable, Sendable {
    /// Active exact consent domain, or nil after clearing.
    public let scope: SocialScope?
    /// Highest connection generation observed, even while a new snapshot is required.
    public let generation: UInt64?
    /// Highest ordering watermark; events at or below it cannot restore missing state.
    public let sequence: UInt64?
    /// Whether arrays contain a complete synchronized observation.
    public let synchronization: SocialSynchronization
    /// Admitted users sorted by unsigned ID; empty without a synchronized baseline.
    public let users: [SocialUser]
    /// Admitted relationships sorted by unsigned ID; empty without a baseline.
    public let relationships: [SocialRelationship]

    /// Locates a user in this immutable observation without remote lookup or caching.
    /// - Parameter id: Exact unsigned user identifier.
    /// - Returns: Matching complete user, or nil when missing or unsynchronized.
    public func user(for id: UserID) -> SocialUser? {
        users.first { $0.id == id }
    }

    /// Locates an account-relative relationship without inferring remote permissions.
    /// - Parameter id: Exact unsigned other-user identifier.
    /// - Returns: Matching relationship, or nil when missing or unsynchronized.
    public func relationship(for id: UserID) -> SocialRelationship? {
        relationships.first { $0.userID == id }
    }

    /// Groups authorized users by the exact normalized relationship kind.
    /// - Parameter kind: Desired category; unknown integer identities remain distinct.
    /// - Returns: Matching users in unsigned-ID order; absent groups return an empty array.
    public func users(in kind: SocialRelationshipKind) -> [SocialUser] {
        let identifiers = Set(relationships.filter { $0.kind == kind }.map(\.userID))
        return users.filter { identifiers.contains($0.id) }
    }

    /// Searches only admitted friends using Unicode-lowercased substring matching.
    ///
    /// This deterministic local display search does not implement Discord's native
    /// username-search ranking, remote discovery, or locale-specific collation.
    /// - Parameter query: Username substring; an empty string returns all friends.
    /// - Returns: Friends whose usernames match, in unsigned-ID order.
    public func friends(matchingUsername query: String) -> [SocialUser] {
        let foldedQuery = query.lowercased()
        return users(in: .friend).filter {
            foldedQuery.isEmpty || $0.username.lowercased().contains(foldedQuery)
        }
    }

    /// Partitions all admitted relationships using provider-supplied presence for this exact application.
    ///
    /// The online/playing/elsewhere/offline behavior follows the public Social SDK
    /// [GetRelationshipsByGroup](https://discord.com/developers/docs/social-sdk/classdiscordpp_1_1Client.html#a9f7898d3f3d1ec92b06c662df70746d5)
    /// contract (verified 2026-10-18), with an additional explicit unknown group.
    /// Online-elsewhere users known to have played this scoped game appear first;
    /// remaining ties and all other groups use unsigned user-ID order. No remote
    /// presence discovery or native relationship handle identity is implied.
    /// - Parameter group: Desired local presence partition, independent of relationship kind.
    /// - Returns: Matching relationships in deterministic order; inactive or empty groups return an empty array.
    public func relationships(inPresenceGroup group: SocialPresenceGroup) -> [SocialRelationship] {
        guard let scope else { return [] }
        let usersByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        return relationships.filter { relationship in
            guard let user = usersByID[relationship.userID] else { return false }
            return presenceGroup(for: user, applicationID: scope.applicationID) == group
        }.sorted { lhs, rhs in
            if group == .onlineElsewhere {
                let leftPlayed = usersByID[lhs.userID]?.presence?.hasPlayedScopedApplication == true
                let rightPlayed = usersByID[rhs.userID]?.presence?.hasPlayedScopedApplication == true
                if leftPlayed != rightPlayed { return leftPlayed }
            }
            return lhs.userID < rhs.userID
        }
    }

    /// Returns complete display users in the corresponding local relationship presence-group order.
    /// - Parameter group: Exact application-scoped presence partition.
    /// - Returns: Authorized users with admitted relationships; unrelated cached users are excluded.
    ///   Online-elsewhere prior-play ordering and unknown handling match `relationships(inPresenceGroup:)`.
    public func users(inPresenceGroup group: SocialPresenceGroup) -> [SocialUser] {
        let usersByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        return relationships(inPresenceGroup: group).compactMap { usersByID[$0.userID] }
    }

    /// Derives a presence partition without treating absent/unrecognized status as evidence of availability.
    /// - Parameters:
    ///   - user: One complete authorized display/presence observation.
    ///   - applicationID: Exact enclosing scope's application; other applications never count as this game.
    /// - Returns: Unknown for unavailable status, offline for explicit offline, otherwise the exact activity partition.
    private func presenceGroup(for user: SocialUser, applicationID: ApplicationID) -> SocialPresenceGroup {
        guard let presence = user.presence else { return .unknown }
        switch presence.status {
        case .unknown: return .unknown
        case .offline: return .offline
        case .online, .idle, .doNotDisturb:
            return presence.playingApplicationID == applicationID ? .onlinePlayingGame : .onlineElsewhere
        }
    }
}

extension SocialScope: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialScope(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialUser: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialUser(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialRelationship: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialRelationship(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialStateSnapshot: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialStateSnapshot(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialStateChange: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialStateChange(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialStateEvent: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialStateEvent(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialStateView: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals account identity and social display data during ordinary diagnostics.
    public var description: String { "SocialStateView(redacted)" }
    /// Conceals account identity and social display data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking account identities, relationship categories, or user data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension SocialUserPresence: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Conceals user availability and activity data during ordinary diagnostics.
    public var description: String { "SocialUserPresence(redacted)" }
    /// Conceals availability and activity data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking observed availability, activity, or prior-play data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
