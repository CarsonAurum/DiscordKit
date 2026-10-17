import DiscordCore
import Foundation

/// Independently versioned webhook envelope kinds; these values are unrelated to InteractionType.
public enum WebhookEventEnvelopeType: Int, Sendable, CaseIterable {
    case ping = 0, event = 1
}

/// Written webhook names verified 2026-10-17. Quest enrollment is documented but unavailable upstream.
public enum WebhookEventType: String, Sendable, CaseIterable {
    case applicationAuthorized = "APPLICATION_AUTHORIZED"
    case applicationDeauthorized = "APPLICATION_DEAUTHORIZED"
    case entitlementCreate = "ENTITLEMENT_CREATE", entitlementUpdate = "ENTITLEMENT_UPDATE", entitlementDelete = "ENTITLEMENT_DELETE"
    case questUserEnrollment = "QUEST_USER_ENROLLMENT"
    case lobbyMessageCreate = "LOBBY_MESSAGE_CREATE", lobbyMessageUpdate = "LOBBY_MESSAGE_UPDATE", lobbyMessageDelete = "LOBBY_MESSAGE_DELETE"
    case gameDirectMessageCreate = "GAME_DIRECT_MESSAGE_CREATE", gameDirectMessageUpdate = "GAME_DIRECT_MESSAGE_UPDATE"
    case gameDirectMessageDelete = "GAME_DIRECT_MESSAGE_DELETE"
}

/// Authorization/deauthorization snapshot, without granting scopes or assuming an active SDK session.
public struct WebhookApplicationAuthorization: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let user: User
    /// Required on authorization events, absent on ordinary deauthorization events.
    public let scopes: Field<[String]>
    public let integrationType: Field<RawValue<ApplicationIntegrationType>>
    /// A partial guild snapshot; unrelated full Guild requirements are intentionally not imposed.
    public let guild: Field<MessageRelatedResource>
    public let rawFields: [String: JSONValue]

    /// Parses a bounded authorization snapshot without token access, account changes or I/O.
    /// - Parameters:
    ///   - data: Complete object containing a User; event-specific scopes are checked by WebhookEvent.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown fields.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors for malformed known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree already bounded at its outer document.
    /// - Parameters:
    ///   - value: Original nonnull object, including retained future keys.
    ///   - limits: Bounds established at the complete document root.
    /// - Throws: Sanitized invalid-response errors for missing User data or incompatible known fields.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try object.messageModel("user", User.self)
        scopes = try object.field("scopes", [String].self)
        integrationType = try object.field("integration_type", RawValue<ApplicationIntegrationType>.self)
        guild = try object.messageField("guild", MessageRelatedResource.self)
        rawFields = object.resource.fields
    }
}

/// Partial social-message event projection shared by lobby and standard/provisional DM variants.
/// Create, update and delete snapshots have different completeness; omission is preserved and never
/// interpreted as a clear operation. SDK-specific fields not listed here remain exact in rawFields.
public struct WebhookMessageData: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: MessageID
    public let type: Field<RawValue<MessageType>>
    public let content: Field<String>
    public let lobbyID: Field<LobbyID>
    public let channelID: Field<ChannelID>
    public let author: Field<User>
    public let flags: Field<UInt64>
    public let applicationID: Field<ApplicationID>
    public let channel: Field<MessageRelatedResource>
    public let metadata: Field<[String: String]>
    /// Verbatim optional timestamp strings retain upstream offset and fractional spellings.
    public let timestamp: Field<String>
    public let editedTimestamp: Field<String>
    public let rawFields: [String: JSONValue]

    /// Parses one partial social-message event without fetching messages, users, channels or attachments.
    /// - Parameters:
    ///   - data: Complete JSON object containing an exact message ID; other fields remain presence-aware.
    ///   - limits: Bounds covering all known and unknown fields in the whole document.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for malformed modeled fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded partial event without imposing full REST Message requirements.
    /// - Parameters:
    ///   - value: Original nonnull object; unrelated SDK union fields are retained unchanged.
    ///   - limits: Bounds established at the complete document root.
    /// - Throws: Sanitized invalid-response errors for invalid IDs, forbidden nulls or known field types.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageID.self)
        type = try object.field("type", RawValue<MessageType>.self)
        content = try object.field("content", String.self)
        lobbyID = try object.field("lobby_id", LobbyID.self)
        channelID = try object.field("channel_id", ChannelID.self)
        author = try object.messageField("author", User.self)
        flags = try object.field("flags", UInt64.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        channel = try object.messageField("channel", MessageRelatedResource.self)
        metadata = try object.field("metadata", [String: String].self, nullable: true)
        timestamp = try object.field("timestamp", String.self)
        editedTimestamp = try object.field("edited_timestamp", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Typed event payload alternatives. Unknown names, including unavailable Quest enrollment schemas,
/// retain their exact object without inventing authorization or interaction callback semantics.
public enum WebhookEventData: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case applicationAuthorized(WebhookApplicationAuthorization)
    case applicationDeauthorized(WebhookApplicationAuthorization)
    case entitlement(Entitlement)
    case lobbyMessage(WebhookMessageData)
    case gameDirectMessage(WebhookMessageData)
    case unknown(JSONValue)

    /// Conceals message text, user data and future event fields in ordinary diagnostics.
    public var description: String { "WebhookEventData(redacted)" }
    /// Uses the same safe representation for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostic traversal from exposing payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// One webhook event body. Delivery can be duplicated, delayed and unordered; timestamps do not
/// establish a total order and the written envelope provides no unique event delivery identifier.
public struct WebhookEvent: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let type: RawValue<WebhookEventType>
    /// Verbatim ISO8601 text. Official examples omit offsets, so parsing does not invent a timezone.
    public let timestamp: String
    public let data: Field<WebhookEventData>
    public let rawFields: [String: JSONValue]

    /// Parses a bounded event without acknowledging delivery, changing account state or performing I/O.
    /// - Parameters:
    ///   - data: Complete event-body object containing type/timestamp and event-specific data.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown event data.
    /// - Throws: JSON bounds/syntax or sanitized invalid-response errors for malformed known variants.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded event and selects only documented data schemas.
    /// - Parameters:
    ///   - value: Original nonnull event object.
    ///   - limits: Bounds established by the complete outer document.
    /// - Throws: Sanitized invalid-response errors for missing identity/timestamp, required known data,
    ///   authorization scopes, lobby-delete identity or incompatible modeled fields. Unknown events may omit data.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        let kind = try object.required("type", RawValue<WebhookEventType>.self)
        type = kind
        timestamp = try object.required("timestamp", String.self)
        guard !timestamp.isEmpty else { throw DiscordError.transport(.invalidResponse) }
        data = try object.nested("data") { subtree in
            switch kind.knownValue {
            case .applicationAuthorized:
                let payload = try WebhookApplicationAuthorization(value: subtree, limits: limits)
                guard case .value = payload.scopes else { throw DiscordError.transport(.invalidResponse) }
                return .applicationAuthorized(payload)
            case .applicationDeauthorized:
                return .applicationDeauthorized(try WebhookApplicationAuthorization(value: subtree, limits: limits))
            case .entitlementCreate, .entitlementUpdate, .entitlementDelete:
                return .entitlement(try Entitlement(value: subtree, limits: limits))
            case .lobbyMessageCreate, .lobbyMessageUpdate, .lobbyMessageDelete:
                let payload = try WebhookMessageData(value: subtree, limits: limits)
                guard case .value = payload.lobbyID else { throw DiscordError.transport(.invalidResponse) }
                return .lobbyMessage(payload)
            case .gameDirectMessageCreate, .gameDirectMessageUpdate, .gameDirectMessageDelete:
                return .gameDirectMessage(try WebhookMessageData(value: subtree, limits: limits))
            default:
                guard case .object = subtree else { throw DiscordError.transport(.invalidResponse) }
                return .unknown(subtree)
            }
        }
        if let known = kind.knownValue, known != .questUserEnrollment, case .absent = data {
            throw DiscordError.transport(.invalidResponse)
        }
        rawFields = object.resource.fields
    }
}

/// Independently versioned HTTP webhook envelope. Parsing preserves future envelope versions and
/// kinds; an ingress processor must explicitly decide whether it understands them before acknowledging.
/// See https://docs.discord.com/developers/events/webhook-events (verified 2026-10-17).
public struct WebhookEventEnvelope: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let version: Int
    public let applicationID: ApplicationID
    public let type: RawValue<WebhookEventEnvelopeType>
    public let event: Field<WebhookEvent>
    public let rawFields: [String: JSONValue]

    /// Parses a bounded envelope; signature validation must occur before calling this at untrusted ingress.
    /// - Parameters:
    ///   - data: Complete original UTF-8 body, including required version/application_id/type.
    ///   - limits: Whole-document byte/depth/node bounds shared by all nested projections.
    /// - Throws: JSON bounds/syntax or sanitized invalid-response errors for incompatible known fields.
    /// No signature checks, acknowledgments, network operations or durable writes occur here.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a complete bounded envelope, preserving minimal PING and unknown outer kinds.
    /// - Parameters:
    ///   - value: Original nonnull object retaining unknown fields and exact numeric lexemes.
    ///   - limits: Bounds established at the complete document root.
    /// - Throws: Sanitized invalid-response errors for malformed required fields or a known event without a body.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        version = try object.required("version", Int.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        type = try object.required("type", RawValue<WebhookEventEnvelopeType>.self)
        if version == 1, type.knownValue != nil {
            event = try object.messageField("event", WebhookEvent.self)
            if type.knownValue == .event, case .absent = event { throw DiscordError.transport(.invalidResponse) }
        } else {
            // Future outer protocols retain their whole tree without applying today's event-body schema.
            event = .absent
        }
        rawFields = object.resource.fields
    }
}
