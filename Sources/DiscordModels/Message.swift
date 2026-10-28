// File: Sources/DiscordModels/Message.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

extension Poll: MessageTreeProjectable {}
extension PartialEmoji: MessageTreeProjectable {}
extension MessageComponent: MessageTreeProjectable {
    /// Adapts an already bounded subtree to the component decoder without another parse.
    /// - Parameters:
    ///   - value: Original component object from a bounded message response.
    ///   - limits: The containing document's established limits.
    /// - Throws: Safe component projection errors for incompatible known fields.
    convenience init(value: JSONValue, limits: JSONLimits) throws {
        try self.init(verifiedValue: value, limits: limits)
    }
}

/// Exact integer-or-string nonce returned by Discord. Unknown integer widths survive unchanged.
public enum MessageNonceValue: Sendable, Equatable {
    /// A JSON integer token; original sign and digit spelling survive.
    case integer(JSONNumber)
    /// An opaque string; no numeric coercion is performed.
    case string(String)

    /// Interprets an already bounded nonce without accepting null, fractions or exponent spelling.
    /// - Parameter value: Original nonce subtree, restricted to strings or integer JSON tokens.
    /// - Throws: Safe invalid-response errors for another JSON type or a nonintegral token.
    init(value: JSONValue) throws {
        switch value {
        case .string(let text): self = .string(text)
        case .number(let number) where !number.rawValue.contains(".") && !number.rawValue.contains("e") && !number.rawValue.contains("E"):
            self = .integer(number)
        default: throw DiscordError.transport(.invalidResponse)
        }
    }
}

/// The documented minimal forwarding snapshot. It deliberately excludes author identity; it is not a full Message and cannot substitute for current authorization.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageSnapshotContent: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: RawValue<MessageType>
    /// Required nonnull `content` wire field; original values and unknown sibling fields remain in rawFields.
    public let content: String
    /// Required nonnull `embeds` wire field; original values and unknown sibling fields remain in rawFields.
    public let embeds: [MessageEmbed]
    /// Required nonnull `attachments` wire field; original values and unknown sibling fields remain in rawFields.
    public let attachments: [MessageAttachment]
    /// Required nonnull `timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let timestamp: DiscordTimestamp
    /// Required nullable `edited_timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let editedTimestamp: Nullable<DiscordTimestamp>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
    /// Required nonnull `mentions` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentions: [MessageAuthor]
    /// Required nonnull `mention_roles` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentionRoles: [RoleID]
    /// Optional nonnull `stickers` wire field; original values and unknown sibling fields remain in rawFields.
    public let stickers: Field<[MessageRelatedResource]>
    /// Optional nonnull `sticker_items` wire field; original values and unknown sibling fields remain in rawFields.
    public let stickerItems: Field<[MessageStickerItem]>
    /// Optional nonnull `components` wire field; original values and unknown sibling fields remain in rawFields.
    public let components: Field<[MessageComponent]>
    /// Optional nonnull `message_snapshots` wire field; original values and unknown sibling fields remain in rawFields.
    public let messageSnapshots: Field<[MessageSnapshot]>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses one complete object with bounded exact JSON before projecting known fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; missing required keys, forbidden nulls and wrong field types fail.
    ///   - limits: Whole-document UTF-8 byte, container-depth and node limits; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or safe invalid-response errors. No I/O or suspension occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree, sharing immutable raw storage with its containing document.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded parse.
    ///   - limits: Bounds established by that parse, also used for exact scalar decoding.
    /// - Throws: Safe invalid-response errors for incompatible known fields. Unknown keys are retained.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<MessageType>.self)
        content = try object.required("content", String.self)
        embeds = try object.messageModels("embeds", MessageEmbed.self)
        attachments = try object.messageModels("attachments", MessageAttachment.self)
        timestamp = try object.required("timestamp", DiscordTimestamp.self)
        editedTimestamp = try object.required("edited_timestamp", Nullable<DiscordTimestamp>.self)
        flags = try object.field("flags", UInt64.self)
        mentions = try object.messageModels("mentions", MessageAuthor.self)
        mentionRoles = try object.required("mention_roles", [RoleID].self)
        stickers = try object.messageArray("stickers", MessageRelatedResource.self)
        stickerItems = try object.messageArray("sticker_items", MessageStickerItem.self)
        components = try object.messageArray("components", MessageComponent.self)
        messageSnapshots = try object.messageArray("message_snapshots", MessageSnapshot.self)
        rawFields = object.resource.fields
    }
}

/// A point-in-time forwarding envelope. Decoder depth follows caller JSONLimits; Discord currently limits forward snapshot nesting to one.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageSnapshot: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `message` wire field; original values and unknown sibling fields remain in rawFields.
    public let message: MessageSnapshotContent
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses one complete object with bounded exact JSON before projecting known fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; missing required keys, forbidden nulls and wrong field types fail.
    ///   - limits: Whole-document UTF-8 byte, container-depth and node limits; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or safe invalid-response errors. No I/O or suspension occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree, sharing immutable raw storage with its containing document.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded parse.
    ///   - limits: Bounds established by that parse, also used for exact scalar decoding.
    /// - Throws: Safe invalid-response errors for incompatible known fields. Unknown keys are retained.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        message = try object.messageModel("message", MessageSnapshotContent.self)
        rawFields = object.resource.fields
    }
}

/// Guild search results preserve nested hit groups and explicit indexing metadata. totalResults may change during search; short groups do not establish exhaustion.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageSearchResults: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `doing_deep_historical_index` wire field; original values and unknown sibling fields remain in rawFields.
    public let doingDeepHistoricalIndex: Bool
    /// Optional nonnull `documents_indexed` wire field; original values and unknown sibling fields remain in rawFields.
    public let documentsIndexed: Field<Int>
    /// Required nonnull `total_results` wire field; original values and unknown sibling fields remain in rawFields.
    public let totalResults: Int
    /// Optional nonnull `threads` wire field; original values and unknown sibling fields remain in rawFields.
    public let threads: Field<[MessageRelatedResource]>
    /// Optional nonnull `members` wire field; original values and unknown sibling fields remain in rawFields.
    public let members: Field<[MessageRelatedResource]>
    /// Optional nonnull `analytics_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let analyticsID: Field<String>
    /// Nested match groups in server order; groups are preserved even when empty.
    public let messages: [[Message]]
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses one complete object with bounded exact JSON before projecting known fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; missing required keys, forbidden nulls and wrong field types fail.
    ///   - limits: Whole-document UTF-8 byte, container-depth and node limits; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or safe invalid-response errors. No I/O or suspension occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree, sharing immutable raw storage with its containing document.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded parse.
    ///   - limits: Bounds established by that parse, also used for exact scalar decoding.
    /// - Throws: Safe invalid-response errors for incompatible known fields. Unknown keys are retained.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        doingDeepHistoricalIndex = try object.required("doing_deep_historical_index", Bool.self)
        documentsIndexed = try object.field("documents_indexed", Int.self)
        totalResults = try object.required("total_results", Int.self)
        threads = try object.messageArray("threads", MessageRelatedResource.self)
        members = try object.messageArray("members", MessageRelatedResource.self)
        analyticsID = try object.field("analytics_id", String.self)
        guard case .array(let groups) = object.resource.fields["messages"] else { throw DiscordError.transport(.invalidResponse) }
        messages = try groups.map { group in
            guard case .array(let values) = group else { throw DiscordError.transport(.invalidResponse) }
            return try values.map { try Message(value: $0, limits: limits) }
        }
        guard totalResults >= 0 else { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Search's HTTP 202 indexing response. The endpoint helper uses this delay rather than mistaking it for an empty result.
public struct MessageSearchIndexing: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Discord's numeric indexing code, currently 110000.
    public let code: Int
    /// Human-readable upstream text, concealed from ordinary diagnostics.
    public let message: String
    /// Optional count of indexed documents; omission is retained.
    public let documentsIndexed: Field<Int>
    /// Nonnegative finite server delay in seconds; zero requires the operation helper's configured minimum delay.
    public let retryAfter: Double
    /// Exact original object including future metadata.
    public let rawFields: [String: JSONValue]

    /// Parses one complete bounded indexing response synchronously.
    /// - Parameters:
    ///   - data: UTF-8 indexing object with required code, message and retry_after fields.
    ///   - limits: Whole-document parser limits, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON syntax/bounds or safe invalid-response errors for malformed fields/delays.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded indexing subtree and checks finite nonnegative delay.
    /// - Parameters:
    ///   - value: Original object subtree from the bounded root.
    ///   - limits: Bounds established by that parse.
    /// - Throws: Safe invalid-response errors for missing/mistyped fields, another code, or invalid delay.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        code = try object.required("code", Int.self)
        message = try object.required("message", String.self)
        documentsIndexed = try object.field("documents_indexed", Int.self)
        guard code == 110000, case .value(let delay) = try object.messageNumber("retry_after"), delay >= 0
        else { throw DiscordError.transport(.invalidResponse) }
        retryAfter = delay
        rawFields = object.resource.fields
    }
}

/// Explicit success alternatives for Search Guild Messages: results (HTTP 200) or indexing (HTTP 202).
/// This data-only decoder recognizes the documented indexing code, since Endpoint's decoder does not receive status.
public enum MessageSearchResponse: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A completed result snapshot; result count and indexing state remain advisory during changes.
    case results(MessageSearchResults)
    /// An indexing response that requires bounded delayed polling rather than pagination.
    case indexing(MessageSearchIndexing)

    /// Parses a complete bounded success body, preserving all typed and unknown response data.
    /// - Parameters:
    ///   - data: UTF-8 object from an accepted 200/202 response.
    ///   - limits: Whole-document parser bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for an unrecognized response shape.
    public init(data: Data, limits: JSONLimits = .default) throws {
        let value = try JSONValue.parse(data, limits: limits)
        let object = try PayloadObject(value, limits: limits)
        if case .number(let code) = object.resource.fields["code"], code.rawValue == "110000" {
            self = .indexing(try MessageSearchIndexing(value: value, limits: limits))
        } else {
            self = .results(try MessageSearchResults(value: value, limits: limits))
        }
    }

    /// Conceals result bodies and upstream indexing text from ordinary formatting.
    public var description: String { "MessageSearchResponse(redacted)" }
    /// Uses the same redacted marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from exposing result messages.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Variant-aware interaction metadata attached to a response message. Future interaction types preserve their raw object.
public struct MessageInteractionMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Interaction identifier independent of its response message identifier.
    public let id: MessageInteractionID
    /// Raw integral interaction type; known metadata alternatives are 2, 3 and 5.
    public let type: Int
    /// The user responsible for the interaction.
    public let user: MessageAuthor
    /// Installation-context keys and exact decimal owner identifiers, including the documented zero guild owner.
    public let authorizingIntegrationOwners: [String: String]
    /// Original response identifier on follow-up messages.
    public let originalResponseMessageID: Field<MessageID>
    /// Optional user-command target.
    public let targetUser: Field<MessageAuthor>
    /// Optional message-command target identifier.
    public let targetMessageID: Field<MessageID>
    /// Component source identifier, required for the known type-3 metadata alternative.
    public let interactedMessageID: Field<MessageID>
    private let triggeringMetadata: Field<[MessageInteractionMetadata]>
    /// Metadata that opened a modal. Required for type 5; storage indirection preserves value semantics without a recursive-size type.
    public var triggeringInteractionMetadata: Field<MessageInteractionMetadata> {
        switch triggeringMetadata {
        case .absent: .absent
        case .null: .null
        case .value(let values): values.first.map(Field.value) ?? .absent
        }
    }
    /// Complete original object including future alternatives and unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded metadata object and validates known alternative-specific required keys.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with common id/type/user/installation-owner fields.
    ///   - limits: Whole-document byte/depth/node limits; defaults to the standard bounds.
    /// - Throws: JSON syntax/bounds or safe invalid-response errors for missing/mistyped keys.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects recursively bounded metadata without launching work or reparsing subtrees.
    /// - Parameters:
    ///   - value: Original object subtree from a bounded containing response.
    ///   - limits: Bounds established by that containing response.
    /// - Throws: Safe invalid-response errors for malformed owners, fields or known variants.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageInteractionID.self)
        type = try object.required("type", Int.self)
        user = try object.messageModel("user", MessageAuthor.self)
        authorizingIntegrationOwners = try object.required("authorizing_integration_owners", [String: String].self)
        guard authorizingIntegrationOwners.values.allSatisfy({ value in
            !value.isEmpty && value.utf8.allSatisfy({ (48...57).contains($0) }) && UInt64(value) != nil
        }) else { throw DiscordError.transport(.invalidResponse) }
        originalResponseMessageID = try object.field("original_response_message_id", MessageID.self)
        targetUser = try object.messageField("target_user", MessageAuthor.self)
        targetMessageID = try object.field("target_message_id", MessageID.self)
        interactedMessageID = try object.field("interacted_message_id", MessageID.self)
        triggeringMetadata = try object.nested("triggering_interaction_metadata") {
            [try MessageInteractionMetadata(value: $0, limits: limits)]
        }
        if type == 3, case .absent = interactedMessageID { throw DiscordError.transport(.invalidResponse) }
        if type == 5, case .absent = triggeringMetadata { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Interaction resolved data retains typed users and explicit related-resource projections for other catalog families.
/// Channel/member/role/attachment projections remain partial until their family schemas are adopted; raw data is lossless.
public struct MessageResolvedData: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional map of user snowflakes to message-compatible user projections.
    public let users: Field<[String: MessageAuthor]>
    /// Optional member objects, preserving exact fields from the Interactions schema.
    public let members: Field<[String: MessageRelatedResource]>
    /// Optional role objects, preserving exact fields from the Permissions schema.
    public let roles: Field<[String: MessageRelatedResource]>
    /// Optional channel objects, preserving exact fields from the Interactions schema.
    public let channels: Field<[String: MessageRelatedResource]>
    /// Optional complete messages keyed by snowflake.
    public let messages: Field<[String: Message]>
    /// Optional complete message attachments keyed by snowflake.
    public let attachments: Field<[String: MessageAttachment]>
    /// Complete original object, including future dictionary categories.
    public let rawFields: [String: JSONValue]

    /// Parses a complete bounded resolved-data object without I/O or suspension.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; each known dictionary must contain typed object values.
    ///   - limits: Whole-document JSON byte/depth/node limits, defaulting to standard bounds.
    /// - Throws: JSON syntax/bounds or safe invalid-response errors for malformed dictionaries/values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects already bounded dictionaries while preserving key spelling and unknown fields.
    /// - Parameters:
    ///   - value: Original object subtree from a bounded response.
    ///   - limits: Bounds applied to the complete containing document.
    /// - Throws: Safe invalid-response errors for malformed dictionary roots, IDs or values.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        users = try object.messageDictionary("users", MessageAuthor.self)
        members = try object.messageDictionary("members", MessageRelatedResource.self)
        roles = try object.messageDictionary("roles", MessageRelatedResource.self)
        channels = try object.messageDictionary("channels", MessageRelatedResource.self)
        messages = try object.messageDictionary("messages", Message.self)
        attachments = try object.messageDictionary("attachments", MessageAttachment.self)
        rawFields = object.resource.fields
    }
}

extension PayloadObject {
    /// Projects an optional snowflake-keyed object dictionary without erasing its key spelling.
    /// - Parameters:
    ///   - name: Optional nonnull object key.
    ///   - type: Typed projection applied to every original value.
    /// - Returns: Absent or the complete typed dictionary, including an empty dictionary.
    /// - Throws: Safe invalid-response errors for invalid decimal keys or malformed objects/values.
    func messageDictionary<T: MessageTreeProjectable>(_ name: String, _ type: T.Type) throws -> Field<[String: T]> {
        try nested(name) { value in
            guard case .object(let values) = value, values.keys.allSatisfy({ key in
                !key.isEmpty && key.utf8.allSatisfy({ (48...57).contains($0) }) && UInt64(key) != nil
            }) else { throw DiscordError.transport(.invalidResponse) }
            return try values.mapValues { try T(value: $0, limits: limits) }
        }
    }
}

/// An API v10 message response, including exact forward snapshots and nullable referenced-message state. Empty content/media can reflect MESSAGE_CONTENT intent filtering; never infer authorization from a retained snapshot.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct Message: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: MessageID
    /// Required nonnull `channel_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `author` wire field; original values and unknown sibling fields remain in rawFields.
    public let author: MessageAuthor
    /// Required nonnull `content` wire field; original values and unknown sibling fields remain in rawFields.
    public let content: String
    /// Required nonnull `timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let timestamp: DiscordTimestamp
    /// Required nullable `edited_timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let editedTimestamp: Nullable<DiscordTimestamp>
    /// Required nonnull `tts` wire field; original values and unknown sibling fields remain in rawFields.
    public let tts: Bool
    /// Required nonnull `mention_everyone` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentionEveryone: Bool
    /// Required nonnull `mentions` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentions: [MessageAuthor]
    /// Required nonnull `mention_roles` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentionRoles: [RoleID]
    /// Optional nonnull `mention_channels` wire field; original values and unknown sibling fields remain in rawFields.
    public let mentionChannels: Field<[MessageChannelMention]>
    /// Required nonnull `attachments` wire field; original values and unknown sibling fields remain in rawFields.
    public let attachments: [MessageAttachment]
    /// Required nonnull `embeds` wire field; original values and unknown sibling fields remain in rawFields.
    public let embeds: [MessageEmbed]
    /// Optional nonnull `reactions` wire field; original values and unknown sibling fields remain in rawFields.
    public let reactions: Field<[MessageReaction]>
    /// Required nonnull `pinned` wire field; original values and unknown sibling fields remain in rawFields.
    public let pinned: Bool
    /// Optional nonnull `webhook_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let webhookID: Field<WebhookID>
    /// Required nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: RawValue<MessageType>
    /// Optional nonnull `activity` wire field; original values and unknown sibling fields remain in rawFields.
    public let activity: Field<MessageActivity>
    /// Optional nonnull `application` wire field; original values and unknown sibling fields remain in rawFields.
    public let application: Field<MessageRelatedResource>
    /// Optional nonnull `application_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let applicationID: Field<ApplicationID>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `message_reference` wire field; original values and unknown sibling fields remain in rawFields.
    public let messageReference: Field<MessageReference>
    /// Optional nonnull `message_snapshots` wire field; original values and unknown sibling fields remain in rawFields.
    public let messageSnapshots: Field<[MessageSnapshot]>
    /// Optional nonnull `interaction_metadata` wire field; original values and unknown sibling fields remain in rawFields.
    public let interactionMetadata: Field<MessageInteractionMetadata>
    /// Optional nonnull `interaction` wire field; original values and unknown sibling fields remain in rawFields.
    public let interaction: Field<MessageLegacyInteraction>
    /// Optional nonnull `thread` wire field; original values and unknown sibling fields remain in rawFields.
    public let thread: Field<MessageRelatedResource>
    /// Optional nonnull `components` wire field; original values and unknown sibling fields remain in rawFields.
    public let components: Field<[MessageComponent]>
    /// Optional nonnull `sticker_items` wire field; original values and unknown sibling fields remain in rawFields.
    public let stickerItems: Field<[MessageStickerItem]>
    /// Optional nonnull `stickers` wire field; original values and unknown sibling fields remain in rawFields.
    public let stickers: Field<[MessageRelatedResource]>
    /// Optional nonnull `position` wire field; original values and unknown sibling fields remain in rawFields.
    public let position: Field<Int>
    /// Optional nonnull `role_subscription_data` wire field; original values and unknown sibling fields remain in rawFields.
    public let roleSubscriptionData: Field<MessageRoleSubscriptionData>
    /// Optional nonnull `resolved` wire field; original values and unknown sibling fields remain in rawFields.
    public let resolved: Field<MessageResolvedData>
    /// Optional nonnull `poll` wire field; original values and unknown sibling fields remain in rawFields.
    public let poll: Field<Poll>
    /// Optional nonnull `call` wire field; original values and unknown sibling fields remain in rawFields.
    public let call: Field<MessageCall>
    /// Optional nonnull `shared_client_theme` wire field; original values and unknown sibling fields remain in rawFields.
    public let sharedClientTheme: Field<MessageSharedClientTheme>
    /// Optional exact string-or-integer nonce, without floating-point coercion.
    public let nonce: Field<MessageNonceValue>
    private let referencedMessages: Field<[Message]>
    /// The replied-to message: absent means unfetched/unknown, null means deleted, and value contains the full fetched snapshot.
    public var referencedMessage: Field<Message> {
        switch referencedMessages {
        case .absent: .absent
        case .null: .null
        case .value(let values): values.first.map(Field.value) ?? .absent
        }
    }
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses one complete object with bounded exact JSON before projecting known fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; missing required keys, forbidden nulls and wrong field types fail.
    ///   - limits: Whole-document UTF-8 byte, container-depth and node limits; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or safe invalid-response errors. No I/O or suspension occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree, sharing immutable raw storage with its containing document.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded parse.
    ///   - limits: Bounds established by that parse, also used for exact scalar decoding.
    /// - Throws: Safe invalid-response errors for incompatible known fields. Unknown keys are retained.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        author = try object.messageModel("author", MessageAuthor.self)
        content = try object.required("content", String.self)
        timestamp = try object.required("timestamp", DiscordTimestamp.self)
        editedTimestamp = try object.required("edited_timestamp", Nullable<DiscordTimestamp>.self)
        tts = try object.required("tts", Bool.self)
        mentionEveryone = try object.required("mention_everyone", Bool.self)
        mentions = try object.messageModels("mentions", MessageAuthor.self)
        mentionRoles = try object.required("mention_roles", [RoleID].self)
        mentionChannels = try object.messageArray("mention_channels", MessageChannelMention.self)
        attachments = try object.messageModels("attachments", MessageAttachment.self)
        embeds = try object.messageModels("embeds", MessageEmbed.self)
        reactions = try object.messageArray("reactions", MessageReaction.self)
        pinned = try object.required("pinned", Bool.self)
        webhookID = try object.field("webhook_id", WebhookID.self)
        type = try object.required("type", RawValue<MessageType>.self)
        activity = try object.messageField("activity", MessageActivity.self)
        application = try object.messageField("application", MessageRelatedResource.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        flags = try object.field("flags", UInt64.self)
        messageReference = try object.messageField("message_reference", MessageReference.self)
        messageSnapshots = try object.messageArray("message_snapshots", MessageSnapshot.self)
        interactionMetadata = try object.messageField("interaction_metadata", MessageInteractionMetadata.self)
        interaction = try object.messageField("interaction", MessageLegacyInteraction.self)
        thread = try object.messageField("thread", MessageRelatedResource.self)
        components = try object.messageArray("components", MessageComponent.self)
        stickerItems = try object.messageArray("sticker_items", MessageStickerItem.self)
        stickers = try object.messageArray("stickers", MessageRelatedResource.self)
        position = try object.field("position", Int.self)
        roleSubscriptionData = try object.messageField("role_subscription_data", MessageRoleSubscriptionData.self)
        resolved = try object.messageField("resolved", MessageResolvedData.self)
        poll = try object.messageField("poll", Poll.self)
        call = try object.messageField("call", MessageCall.self)
        sharedClientTheme = try object.messageField("shared_client_theme", MessageSharedClientTheme.self)
        nonce = try object.nested("nonce") { try MessageNonceValue(value: $0) }
        referencedMessages = try object.nested("referenced_message", nullable: true) {
            [try Message(value: $0, limits: limits)]
        }
        rawFields = object.resource.fields
    }
}
