import DiscordCore
import Foundation

/// Written API v10 Lobby fields, verified 2026-10-16. Related channels use the existing Channel
/// projection; preview-only lobby flags and webhook configuration remain exact in rawFields.
/// A snapshot establishes neither current membership nor Social SDK access to a backend-created lobby.
public struct Lobby: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact lobby snowflake; its domain remains distinct from linked guild channels.
    public let id: LobbyID
    /// Application that owns the lobby.
    public let applicationID: ApplicationID
    /// Required nullable string dictionary; null remains distinct from an empty dictionary.
    public let metadata: Nullable<[String: String]>
    /// Members in the original response order, including an empty array.
    public let members: [LobbyMember]
    /// Optional linked guild channel. Omission is preserved and explicit null is forbidden by the written schema.
    public let linkedChannel: Field<Channel>
    /// Complete original object, preserving unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded immutable lobby without fetching members, linking channels or joining a voice call.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; every written required field must be present.
    ///   - limits: Whole-document bounds, including unknown fields; default 1 MiB, depth 64 and 100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing keys, forbidden
    ///   nulls, incompatible known types or invalid exact identifiers. Correct malformed input before retrying.
    /// Parsing is synchronous, does not observe cancellation, and owns no credentials or network resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded lobby subtree without reparsing nested members or unknown data.
    /// - Parameters:
    ///   - value: Original object from a document that passed the supplied parser limits.
    ///   - limits: Bounds established at that document's root, reused for exact scalar validation.
    /// - Throws: Sanitized invalid-response errors for malformed modeled fields. No I/O, suspension,
    ///   authorization inference or state mutation occurs; immutable original JSON remains shared.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", LobbyID.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        metadata = try object.required("metadata", Nullable<[String: String]>.self)
        members = try object.messageModels("members", LobbyMember.self)
        linkedChannel = try object.messageField("linked_channel", Channel.self)
        rawFields = object.resource.fields
    }
}

/// Written API v10 Lobby Member fields, including the additional name supported by Create/Modify
/// Lobby since 2026-08-12. Missing metadata, flags and display names retain their own presence.
/// Response parsing does not impose outgoing text limits or infer a missing flag's default.
public struct LobbyMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact Discord user ID.
    public let id: UserID
    /// Optional nullable dictionary; absent, null and an empty dictionary remain distinct.
    public let metadata: Field<[String: String]>
    /// Optional complete unsigned capability bitfield; use LobbyMemberFlags for known bit checks.
    public let flags: Field<UInt64>
    /// Optional nonnull in-game display name; a message retains its own independent historical snapshot.
    public let additionalName: Field<String>
    /// Complete original member, preserving unknown fields and numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded member snapshot without hydrating a User or changing lobby membership.
    /// - Parameters:
    ///   - data: Complete UTF-8 member object with a required nonnull ID.
    ///   - limits: Bounds for all known and unknown JSON; default 1 MiB, depth 64 and 100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for invalid known fields.
    /// Parsing is synchronous, owns no external resources and does not suspend or check cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a member subtree whose complete containing document already satisfied parser bounds.
    /// - Parameters:
    ///   - value: Original nonnull object, including unknown member fields.
    ///   - limits: Bounds established at the root and reused for exact integer decoding.
    /// - Throws: Sanitized invalid-response errors for invalid IDs, forbidden nulls or mistyped known data.
    /// Work is synchronous with no I/O, mutation, suspension or resource acquisition.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", UserID.self)
        metadata = try object.field("metadata", [String: String].self, nullable: true)
        flags = try object.field("flags", UInt64.self)
        additionalName = try object.field("additional_name", String.self)
        rawFields = object.resource.fields
    }
}

/// The author's additional display name captured when a lobby message was sent. It is a historical
/// name snapshot, not a complete LobbyMember, and carries no membership identity or current capability.
public struct LobbyMessageMemberSnapshot: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull additional name at send time, independent of later member edits or removal.
    public let additionalName: String
    /// Complete original snapshot, retaining future fields and exact numbers; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded author-name snapshot without consulting current lobby membership.
    /// - Parameters:
    ///   - data: Complete UTF-8 object containing additional_name as a string.
    ///   - limits: Whole-document bounds including unknown data; default 1 MiB, depth 64 and 100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing or mistyped names.
    /// Parsing is synchronous and performs no I/O, cancellation check or external resource acquisition.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one original snapshot subtree after the containing document passed its parser bounds.
    /// - Parameters:
    ///   - value: Original nonnull object with a required nonnull string name.
    ///   - limits: Root-document bounds reused for scalar validation.
    /// - Throws: Sanitized invalid-response errors for a nonobject or an invalid required name.
    /// Construction is synchronous and leaves current membership and all external state untouched.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        additionalName = try object.required("additional_name", String.self)
        rawFields = object.resource.fields
    }
}

/// Written API v10 lobby message, distinct from a guild Message. Dispatch metadata may be missing
/// from history and is not persisted to a linked guild message. A returned lobby message does not
/// establish that forwarding to a linked channel succeeded; Discord may deliver locally after AutoMod rejection.
public struct LobbyMessage: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact message ID.
    public let id: MessageID
    /// Known or future integral message kind.
    public let type: RawValue<MessageType>
    /// Original message content, without normalization or outgoing nonempty validation.
    public let content: String
    /// Lobby in which the message was sent.
    public let lobbyID: LobbyID
    /// Compatibility channel identifier, documented as equal to lobbyID; no value is synthesized or rewritten.
    public let channelID: ChannelID
    /// User snapshot of the sender. Parsing does not hydrate current account or entitlement state.
    public let author: User
    /// Optional author-name snapshot; omission means no additional name was captured.
    public let lobbyMember: Field<LobbyMessageMemberSnapshot>
    /// Optional nullable dispatch-only metadata; absence in history does not imply an empty dispatch value.
    public let metadata: Field<[String: String]>
    /// Optional nullable application-scoped moderation data, independent of message metadata.
    public let moderationMetadata: Field<[String: String]>
    /// Complete unsigned message flags including future bits, without eligibility inference.
    public let flags: UInt64
    /// Application that sent the message, required by the written resource contract.
    public let applicationID: ApplicationID
    /// Complete original message, retaining unknown fields and exact numbers; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded message snapshot without fetching assets, joining a lobby or sending a message.
    /// - Parameters:
    ///   - data: Complete UTF-8 object following the written Lobby Message contract.
    ///   - limits: Bounds for all JSON, including nested author and unknown data; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for invalid modeled fields.
    /// Parsing is synchronous, owns no external resources and performs no I/O or cooperative cancellation check.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded message subtree while sharing immutable raw data with nested views.
    /// - Parameters:
    ///   - value: Original nonnull message object from the containing bounded document.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for missing, forbidden-null, mistyped or overflowing fields.
    /// No I/O, permission inference, mutation, suspension or external resource acquisition occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageID.self)
        type = try object.required("type", RawValue<MessageType>.self)
        content = try object.required("content", String.self)
        lobbyID = try object.required("lobby_id", LobbyID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        author = try object.messageModel("author", User.self)
        lobbyMember = try object.messageField("lobby_member", LobbyMessageMemberSnapshot.self)
        metadata = try object.field("metadata", [String: String].self, nullable: true)
        moderationMetadata = try object.field("moderation_metadata", [String: String].self, nullable: true)
        flags = try object.required("flags", UInt64.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        rawFields = object.resource.fields
    }
}

/// Written API v10 targeted linked-channel invite response. Discord documents these invites as
/// single use with one-hour expiry; the response contains no timestamps or local validity guarantee.
public struct LobbyInvite: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required opaque invite code; ordinary formatting and reflection conceal it.
    public let code: String
    /// Complete original invite, preserving future fields and exact numbers; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded invite without following its code or joining the associated guild.
    /// - Parameters:
    ///   - data: Complete UTF-8 response object containing a nonnull string code.
    ///   - limits: Whole-document bounds including unknown fields; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for an invalid required code.
    /// Work is synchronous and performs no I/O, suspension or resource acquisition.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded invite subtree without exposing its code in failure diagnostics.
    /// - Parameters:
    ///   - value: Original nonnull object from a bounded response document.
    ///   - limits: Root-document bounds reused for scalar validation.
    /// - Throws: Sanitized invalid-response errors for a nonobject or missing/null/nonstring code.
    /// No I/O, state mutation, cancellation check or resource ownership changes occur.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        code = try object.required("code", String.self)
        rawFields = object.resource.fields
    }
}
