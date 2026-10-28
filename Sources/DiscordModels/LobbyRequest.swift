// File: Sources/DiscordModels/LobbyRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// API v10 lobby request payload. Construction validates published local constraints synchronously;
/// authorization, current membership, quotas and Social SDK access remain Discord's responsibility.
/// Descriptions and reflection conceal lobby secrets, display names, message content and invite-related data.
public protocol LobbyRequestPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Returns the exact immutable JSON body for deliberate transmission, preserving omission and explicit null.
    /// - Returns: A JSON object, or the root array required by Bulk Update Lobby Members; contains private data.
    func jsonValue() -> JSONValue
}

extension LobbyRequestPayload {
    /// Conceals lobby secrets and personal or message data from ordinary formatting.
    public var description: String { "\(Self.self)(redacted)" }
    /// Uses the same redacted marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing private request fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A member entry for Create/Modify Lobby. Omitting additionalName preserves an existing member's
/// name; null clears it. A Modify Lobby members array replaces membership, removing unlisted users.
public struct LobbyMemberRequest: LobbyRequestPayload {
    /// Exact user ID supplied in this member entry.
    public let id: UserID
    private let fields: [String: JSONValue]

    /// Validates a member entry without adding a user, checking eligibility or obtaining OAuth consent.
    /// - Parameters:
    ///   - id: Exact unsigned user ID, serialized as decimal text.
    ///   - metadata: Omitted by default; null clears, value replaces metadata. Sum of key/value Unicode scalars ≤1000.
    ///   - flags: Omitted by default; complete unsigned capability flags, retaining future bits for server validation.
    ///   - additionalName: Omitted by default; null clears, value must contain 1...80 Unicode scalars.
    /// - Throws: Safe invalid-value errors for oversized metadata or invalid names; numeric encoding errors are propagated.
    /// Construction is synchronous, performs no I/O or suspension, and owns no external resources.
    public init(id: UserID, metadata: Field<[String: String]> = .absent,
                flags: LobbyMemberFlags? = nil, additionalName: Field<String> = .absent) throws {
        self.id = id
        var result = try lobbyMemberRequestFields(metadata: metadata, flags: flags, additionalName: additionalName)
        result["id"] = .string(id.description)
        fields = result
    }

    /// Produces one validated array entry without adding omitted defaults.
    /// - Returns: An object containing the exact user ID and selected member changes.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /lobbies body. Backend-created lobbies cannot be joined or left with the Social SDK
/// client create/join API. Execution uses the owning application's bot credential and shared rate admission.
public struct CreateLobbyRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates a new backend-owned lobby without sending a request or creating a local lobby runtime.
    /// - Parameters:
    ///   - metadata: Omitted by default; nullable string dictionary with at most 1000 combined key/value Unicode scalars.
    ///   - members: Omitted by default; 0...25 distinct explicitly selected users. Empty is retained.
    ///   - idleTimeoutSeconds: Omitted by default; 5...604800 seconds before shutdown after becoming idle.
    /// - Throws: Safe invalid-value errors for published length/count/timeout violations or duplicate member IDs.
    /// Construction is synchronous with no I/O, suspension, credential access or resource acquisition.
    public init(metadata: Field<[String: String]> = .absent, members: [LobbyMemberRequest]? = nil,
                idleTimeoutSeconds: Int? = nil) throws {
        fields = try lobbyRequestFields(metadata: metadata, members: members, idleTimeoutSeconds: idleTimeoutSeconds)
    }

    /// Produces the exact create body; the empty object lets Discord apply every omitted default.
    /// - Returns: Immutable object containing only the caller's selected fields.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /lobbies/{lobby.id} body. Supplying members replaces the entire membership set;
/// an empty array removes all members. Omitted metadata, members and timeout retain their current values.
public struct ModifyLobbyRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates explicit lobby edits without fetching current state or silently merging membership mutations.
    /// - Parameters:
    ///   - metadata: Omitted by default; null clears, a dictionary replaces; combined key/value Unicode scalars ≤1000.
    ///   - members: Omitted by default; replacement array of 0...25 distinct users. Unlisted existing users are removed.
    ///   - idleTimeoutSeconds: Omitted by default; 5...604800 seconds after the lobby becomes idle.
    /// - Throws: Safe invalid-value errors for invalid metadata, timeout, excessive members or duplicate IDs.
    /// Construction is synchronous and owns no credentials, network resources or mutable external state.
    public init(metadata: Field<[String: String]> = .absent, members: [LobbyMemberRequest]? = nil,
                idleTimeoutSeconds: Int? = nil) throws {
        fields = try lobbyRequestFields(metadata: metadata, members: members, idleTimeoutSeconds: idleTimeoutSeconds)
    }

    /// Produces the exact PATCH object, keeping omission distinct from metadata clear and membership removal.
    /// - Returns: Immutable JSON object; an empty object contains no selected edits.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /lobbies body for caller-owned create/join by secret. Requires a Bearer token with
/// sdk.social_layer; updates lobby and calling member metadata on join. The secret is never logged implicitly.
public struct CreateOrJoinLobbyRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates create/join selection without searching for a lobby or inspecting the token's actual scopes.
    /// - Parameters:
    ///   - secret: Exact application-scoped secret, at most 250 Unicode scalars. The written reference publishes
    ///     no minimum; the value is preserved without normalization, hashing or automatic generation.
    ///   - idleTimeoutSeconds: Omitted by default; accepted published range 5...604800 seconds.
    ///   - lobbyMetadata: Omitted by default; nullable replacement map with combined key/value scalars ≤1000.
    ///   - memberMetadata: Omitted by default; nullable caller-member map with the same 1000-scalar bound.
    /// - Throws: Safe invalid-value errors for an oversized secret/map or invalid timeout; numeric errors propagate.
    /// Construction is synchronous and performs no I/O, authorization checks, suspension or state mutation.
    public init(secret: String, idleTimeoutSeconds: Int? = nil,
                lobbyMetadata: Field<[String: String]> = .absent,
                memberMetadata: Field<[String: String]> = .absent) throws {
        var result: [String: JSONValue] = ["secret": try guildRequestText(secret, length: 0...250)]
        try guildRequestField(lobbyMetadata, name: "lobby_metadata", nullable: true, into: &result) {
            try lobbyRequestMetadata($0, maximumTotalScalars: 1000)
        }
        try guildRequestField(memberMetadata, name: "member_metadata", nullable: true, into: &result) {
            try lobbyRequestMetadata($0, maximumTotalScalars: 1000)
        }
        if let idleTimeoutSeconds { result["idle_timeout_seconds"] = try guildRequestRange(idleTimeoutSeconds, 5...604800) }
        fields = result
    }

    /// Deliberately exposes the validated secret-bearing request for transport encoding.
    /// - Returns: Exact create/join JSON, including the secret; callers must keep this representation out of logs.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /lobbies/{lobby.id}/members/{user.id} body. Adds a user or edits an existing member.
/// The user ID belongs to the route and is deliberately excluded from this body.
public struct ModifyLobbyMemberRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates an explicit member upsert without requesting consent or changing membership locally.
    /// - Parameters:
    ///   - metadata: Omitted by default; null clears, value replaces; combined key/value Unicode scalars ≤1000.
    ///   - flags: Omitted by default; full unsigned capability flags, with eligibility checked by Discord.
    ///   - additionalName: Omitted preserves the current name; null clears it; value has 1...80 Unicode scalars.
    /// - Throws: Safe invalid-value errors for map/name bounds; exact numeric construction errors propagate.
    /// Construction is synchronous, owns no external resources and does not suspend or perform I/O.
    public init(metadata: Field<[String: String]> = .absent, flags: LobbyMemberFlags? = nil,
                additionalName: Field<String> = .absent) throws {
        fields = try lobbyMemberRequestFields(metadata: metadata, flags: flags, additionalName: additionalName)
    }

    /// Produces an exact member upsert body without a redundant route user ID or omitted defaults.
    /// - Returns: Immutable object, including an empty object for an upsert with no selected fields.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One API v10 Bulk Update Lobby Members entry. removeMember true requests removal; false or omission
/// requests upsert. A successful response contains only returned upserts; removals and silently rejected
/// permission/capacity upserts are omitted. Absence from a response must never be interpreted as a successful upsert.
public struct BulkLobbyMemberRequest: LobbyRequestPayload {
    /// Exact user ID for response correlation; response order is not a documented correlation contract.
    public let id: UserID
    /// Explicit removal choice; nil preserves the server's default false without adding a wire field.
    public let removeMember: Bool?
    private let fields: [String: JSONValue]

    /// Validates one explicit bulk mutation while preserving all optional field selections.
    /// - Parameters:
    ///   - id: Exact user to add, edit or remove, retained as a decimal string.
    ///   - metadata: Omitted by default; nullable map with combined key/value Unicode scalars ≤1000.
    ///   - flags: Omitted by default; full unsigned capability flags without guessed eligibility checks.
    ///   - additionalName: Omitted preserves, null clears, value contains 1...80 Unicode scalars.
    ///   - removeMember: Omitted by default; true removes, false explicitly selects upsert. Optional metadata
    ///     is preserved even for removal because the written API does not prohibit it or define local precedence.
    /// - Throws: Safe invalid-value errors for map/name bounds; exact numeric construction errors propagate.
    /// Construction is synchronous and does not inspect the user, perform I/O or mutate external state.
    public init(id: UserID, metadata: Field<[String: String]> = .absent, flags: LobbyMemberFlags? = nil,
                additionalName: Field<String> = .absent, removeMember: Bool? = nil) throws {
        self.id = id
        self.removeMember = removeMember
        var result = try lobbyMemberRequestFields(metadata: metadata, flags: flags, additionalName: additionalName)
        result["id"] = .string(id.description)
        if let removeMember { result["remove_member"] = .bool(removeMember) }
        fields = result
    }

    /// Produces one exact bulk-array entry while retaining omitted versus explicit false removal choices.
    /// - Returns: Immutable member mutation object, with no response success or removal confirmation implied.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /lobbies/{lobby.id}/members/bulk root-array body for 1...25 explicit distinct users.
/// Unknown Discord users can fail the request; permission/capacity failures may silently omit individual upserts.
/// The request preserves input order but supplies no atomicity, response-order or all-members-succeeded guarantee.
public struct BulkUpdateLobbyMembersRequest: LobbyRequestPayload {
    /// Ordered explicit mutations, retained for identity-based partial-result correlation.
    public let members: [BulkLobbyMemberRequest]

    /// Validates one published bulk request without splitting it, retrying omissions or performing hidden reads.
    /// - Parameter members: 1...25 mutations with distinct user IDs. Duplicate IDs are rejected to avoid
    ///   ambiguous removal/upsert ordering and response correlation; split conflicting intent explicitly.
    /// - Throws: Safe invalid-value errors for an empty/oversized array or duplicate user IDs.
    /// Construction is synchronous, performs no I/O and does not create tasks or own external resources.
    public init(members: [BulkLobbyMemberRequest]) throws {
        guard (1...25).contains(members.count), Set(members.map(\.id)).count == members.count
        else { throw DiscordError.validation(.invalidValue) }
        self.members = members
    }

    /// Produces the required root array, never an invented object wrapper or generic mutation batch.
    /// - Returns: Validated member entries in caller order, preserving all optional selections.
    public func jsonValue() -> JSONValue { .array(members.map { $0.jsonValue() }) }
}

/// API v10 PATCH /lobbies/{lobby.id}/channel-linking. Bearer caller must be a lobby member with
/// CanLinkLobby. Omitting channelID unlinks; no null channel ID or preliminary read is required.
public struct LinkLobbyChannelRequest: LobbyRequestPayload {
    /// Exact selected guild text channel, or nil to unlink the current channel.
    public let channelID: ChannelID?

    /// Selects a channel link or explicit unlink without checking current channel permissions.
    /// - Parameter channelID: Exact text-channel ID to link; nil, the default, produces an empty unlink object.
    /// Construction is synchronous, owns no external resources and performs no I/O or membership mutation.
    public init(channelID: ChannelID? = nil) { self.channelID = channelID }

    /// Produces the exact link object or the empty object required to unlink.
    /// - Returns: channel_id as decimal text when selected, otherwise an object with no fields.
    public func jsonValue() -> JSONValue {
        .object(channelID.map { ["channel_id": .string($0.description)] } ?? [:])
    }
}

/// API v10 POST /lobbies/{lobby.id}/messages body. Requires membership and sdk.social_layer Bearer
/// authorization. Discord may deliver to the lobby even when forwarding to a linked guild channel fails.
public struct SendLobbyMessageRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates an explicit lobby message without sending it or assuming guild-channel forwarding success.
    /// - Parameters:
    ///   - content: Nonempty original string; no upper content length is published for this endpoint.
    ///   - metadata: Omitted by default; nullable dispatch-only string dictionary, not persisted on the linked
    ///     channel message. No invented 1000-character lobby/member metadata bound is applied here.
    ///   - flags: Omitted by default; complete unsigned bitfield. The reference accepts only Social SDK-creatable
    ///     flags without publishing an exhaustive set; Discord validates creatability and unknown values.
    /// - Throws: Safe invalid-value errors for empty content; exact numeric encoding errors propagate.
    /// Construction is synchronous with no I/O, suspension, automatic retries or external resource ownership.
    public init(content: String, metadata: Field<[String: String]> = .absent, flags: UInt64? = nil) throws {
        var result: [String: JSONValue] = ["content": try guildRequestNonempty(content)]
        try guildRequestField(metadata, name: "metadata", nullable: true, into: &result) {
            try lobbyRequestMetadata($0, maximumTotalScalars: nil)
        }
        if let flags { result["flags"] = try guildRequestNumber(flags) }
        fields = result
    }

    /// Deliberately exposes the exact lobby message payload for transport encoding.
    /// - Returns: Immutable JSON body; callers must not log its message content or metadata unintentionally.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /lobbies/{lobby.id}/messages/{message.id}/moderation-metadata body. Bot-authenticated
/// application-scoped moderation data reaches active Social SDK clients as a real-time message update.
public struct LobbyMessageModerationRequest: LobbyRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates moderation metadata without interpreting its decisions or changing message content.
    /// - Parameter metadata: Free-form root dictionary with at most 5 keys; each key has at most 1024 and
    ///   each value at most 2000 Unicode scalars. Empty dictionaries and empty strings remain valid.
    /// - Throws: Safe invalid-value errors for excessive key count, key length or value length.
    /// Construction is synchronous, performs no I/O, and makes no local moderation or authorization decision.
    public init(metadata: [String: String]) throws {
        guard metadata.count <= 5, metadata.allSatisfy({ $0.key.unicodeScalars.count <= 1024 && $0.value.unicodeScalars.count <= 2000 })
        else { throw DiscordError.validation(.invalidValue) }
        fields = metadata.mapValues { .string($0) }
    }

    /// Produces the required free-form root dictionary without an invented metadata envelope.
    /// - Returns: Immutable moderation string dictionary, including an empty object when selected.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates shared lobby/member metadata while keeping message metadata's unpublished size bound explicit.
/// - Parameters:
///   - metadata: Exact unnormalized string dictionary, including empty keys/values and an empty map.
///   - maximumTotalScalars: Optional sum bound across keys and values; nil imposes no unpublished size rule.
/// - Returns: Exact JSON string dictionary without floating-point or Codable conversion.
/// - Throws: Safe invalid-value errors if the sum exceeds the selected bound; no map contents enter errors.
/// Validation is synchronous, linear in text length, and performs no I/O or external state mutation.
private func lobbyRequestMetadata(_ metadata: [String: String], maximumTotalScalars: Int?) throws -> JSONValue {
    if var remaining = maximumTotalScalars {
        for (key, value) in metadata {
            let keyCount = key.unicodeScalars.count
            guard keyCount <= remaining else { throw DiscordError.validation(.invalidValue) }
            remaining -= keyCount
            let valueCount = value.unicodeScalars.count
            guard valueCount <= remaining else { throw DiscordError.validation(.invalidValue) }
            remaining -= valueCount
        }
    }
    return .object(metadata.mapValues { .string($0) })
}

/// Validates and encodes fields shared by lobby member create, replacement, upsert and explicit bulk entries.
/// - Parameters:
///   - metadata: Omitted, null or replacement dictionary with at most 1000 combined key/value Unicode scalars.
///   - flags: Optional unsigned capability flags; zero and unknown bits remain exact for Discord's checks.
///   - additionalName: Omitted, null or 1...80 Unicode scalars, preserved without normalization.
/// - Returns: Exact optional member fields without an ID or bulk removal discriminator.
/// - Throws: Safe invalid-value errors for metadata/name constraints; exact numeric encoding errors propagate.
/// Work is synchronous and does not inspect membership, perform I/O or mutate external state.
private func lobbyMemberRequestFields(metadata: Field<[String: String]>, flags: LobbyMemberFlags?,
                                      additionalName: Field<String>) throws -> [String: JSONValue] {
    var fields: [String: JSONValue] = [:]
    try guildRequestField(metadata, name: "metadata", nullable: true, into: &fields) {
        try lobbyRequestMetadata($0, maximumTotalScalars: 1000)
    }
    if let flags { fields["flags"] = try guildRequestNumber(flags.rawValue) }
    try guildRequestField(additionalName, name: "additional_name", nullable: true, into: &fields) {
        try guildRequestText($0, length: 1...80)
    }
    return fields
}

/// Validates common create/modify lobby selections, preserving empty replacements and all omission semantics.
/// - Parameters:
///   - metadata: Omitted, null or replacement string dictionary; total key/value Unicode scalars ≤1000.
///   - members: Optional array of 0...25 distinct explicit member entries; empty remains a wire array.
///   - idleTimeoutSeconds: Optional integer in the inclusive published range 5...604800 seconds.
/// - Returns: Exact selected lobby fields without performing a membership fetch or automatic merge.
/// - Throws: Safe invalid-value errors for count, duplicate IDs, metadata sum or timeout violations.
/// Work is synchronous, linear in the bounded member count and metadata text, and owns no external resources.
private func lobbyRequestFields(metadata: Field<[String: String]>, members: [LobbyMemberRequest]?,
                                idleTimeoutSeconds: Int?) throws -> [String: JSONValue] {
    var fields: [String: JSONValue] = [:]
    try guildRequestField(metadata, name: "metadata", nullable: true, into: &fields) {
        try lobbyRequestMetadata($0, maximumTotalScalars: 1000)
    }
    if let members {
        guard members.count <= 25, Set(members.map(\.id)).count == members.count
        else { throw DiscordError.validation(.invalidValue) }
        fields["members"] = .array(members.map { $0.jsonValue() })
    }
    if let idleTimeoutSeconds { fields["idle_timeout_seconds"] = try guildRequestRange(idleTimeoutSeconds, 5...604800) }
    return fields
}
