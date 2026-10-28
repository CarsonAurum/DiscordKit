// File: Sources/DiscordModels/MessageRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Mention categories explicitly permitted while Discord parses visible message content.
public enum MessageMentionType: String, Sendable, Hashable { case roles, users, everyone }

/// Explicit mention policy for message creation or editing; omission restores Discord's defaults.
public struct MessageAllowedMentions: Sendable, Hashable {
    public let parse: [MessageMentionType]?
    public let roles: [RoleID]?
    public let users: [UserID]?
    public let repliedUser: Bool?
    public let roleIDs: Field<[RoleID]>
    public let userIDs: Field<[UserID]>

    /// Validates mention selectors without sending notifications or checking permissions.
    /// - Parameters:
    ///   - parse: Categories to parse, or `nil` to omit; `[]` disables automatic parsing.
    ///   - roles: Explicit role IDs, at most 100 distinct IDs; incompatible with parsing nonempty role lists.
    ///   - users: Explicit user IDs, at most 100 distinct IDs; incompatible with parsing nonempty user lists.
    ///   - repliedUser: Whether a reply may mention its author; `nil` preserves Discord's default `false`.
    /// - Throws: Safe validation errors for duplicate selectors, excessive IDs or conflicting categories.
    public init(parse: [MessageMentionType]? = nil, roles: [RoleID]? = nil,
                users: [UserID]? = nil, repliedUser: Bool? = nil) throws {
        try self.init(parse: parse, roles: roles.map { .value($0) } ?? .absent,
                      users: users.map { .value($0) } ?? .absent, repliedUser: repliedUser)
    }

    /// Preserves explicitly null selectors, which Discord permits alongside parsed mention categories.
    /// - Parameters:
    ///   - parse: Optional distinct categories; an empty array disables automatic parsing.
    ///   - roles: Omitted, null, or up to 100 distinct explicit roles; nonempty conflicts with parsed roles.
    ///   - users: Omitted, null, or up to 100 distinct explicit users; nonempty conflicts with parsed users.
    ///   - repliedUser: Optional reply-author notification setting.
    /// - Throws: Safe validation errors for duplicate, excessive or mutually exclusive selectors.
    public init(parse: [MessageMentionType]? = nil, roles: Field<[RoleID]>,
                users: Field<[UserID]>, repliedUser: Bool? = nil) throws {
        let roleValues: [RoleID]? = if case .value(let values) = roles { values } else { nil }
        let userValues: [UserID]? = if case .value(let values) = users { values } else { nil }
        guard Set(parse ?? []).count == (parse?.count ?? 0),
              (roleValues?.count ?? 0) <= 100, (userValues?.count ?? 0) <= 100,
              Set(roleValues ?? []).count == (roleValues?.count ?? 0), Set(userValues ?? []).count == (userValues?.count ?? 0),
              !(parse?.contains(.roles) == true && roleValues?.isEmpty == false),
              !(parse?.contains(.users) == true && userValues?.isEmpty == false)
        else { throw DiscordError.validation(.invalidValue) }
        self.parse = parse; self.roles = roleValues; self.users = userValues; self.repliedUser = repliedUser
        roleIDs = roles; userIDs = users
    }

    /// Produces the exact nonnull allowed-mentions object, retaining omitted versus empty selectors.
    /// - Returns: An object consumed by Discord API v10 message operations; permissions still govern mentions.
    public func jsonValue() -> JSONValue {
        var fields: [String: JSONValue] = [:]
        if let parse { fields["parse"] = .array(parse.map { .string($0.rawValue) }) }
        switch roleIDs {
        case .absent: break
        case .null: fields["roles"] = .null
        case .value(let values): fields["roles"] = .array(values.map { .string($0.description) })
        }
        switch userIDs {
        case .absent: break
        case .null: fields["users"] = .null
        case .value(let values): fields["users"] = .array(values.map { .string($0.description) })
        }
        if let repliedUser { fields["replied_user"] = .bool(repliedUser) }
        return .object(fields)
    }
}

/// Distinguishes an existing attachment retained by an edit from a multipart upload placeholder.
public enum MessageAttachmentRequestID: Sendable, Hashable {
    case existing(AttachmentID)
    case upload(Int)
}

/// Metadata for a new file or an attachment explicitly retained by a message edit.
public struct MessageAttachmentRequest: Sendable, Hashable {
    public let id: MessageAttachmentRequestID
    public let filename: String?
    public let title: String?
    public let description: String?
    public let durationSecs: Double?
    public let waveform: String?
    public let isSpoiler: Bool?

    /// Validates metadata independently of the bytes owned by the HTTP upload factory.
    /// - Parameters:
    ///   - id: Existing decimal snowflake or nonnegative `files[n]` placeholder.
    ///   - filename: Optional wire filename; no local file is opened.
    ///   - title: Optional display title.
    ///   - description: Optional alt text, up to 1,024 Unicode scalars.
    ///   - durationSecs: Optional finite nonnegative audio/video duration, in seconds; required for voice messages.
    ///   - waveform: Optional canonical base64 sampled bytes, up to 256 bytes; required for voice messages.
    ///   - isSpoiler: Whether Discord should blur the attachment; omission preserves its existing setting.
    /// - Throws: Safe validation errors for negative upload IDs, excessive descriptions, invalid duration/waveform,
    ///   or immutable existing-attachment fields. Existing attachments permit only description/isSpoiler updates.
    public init(id: MessageAttachmentRequestID, filename: String? = nil, title: String? = nil,
                description: String? = nil, durationSecs: Double? = nil, waveform: String? = nil,
                isSpoiler: Bool? = nil) throws {
        if case .upload(let index) = id, index < 0 { throw DiscordError.validation(.invalidValue) }
        if case .existing = id {
            guard filename == nil, title == nil, durationSecs == nil, waveform == nil
            else { throw DiscordError.validation(.invalidValue) }
        }
        guard (description?.unicodeScalars.count ?? 0) <= 1_024,
              durationSecs.map({ $0.isFinite && $0 >= 0 }) ?? true
        else { throw DiscordError.validation(.invalidValue) }
        if let waveform {
            guard let bytes = Data(base64Encoded: waveform), bytes.count <= 256,
                  bytes.base64EncodedString() == waveform else { throw DiscordError.validation(.invalidValue) }
        }
        self.id = id; self.filename = filename; self.title = title; self.description = description
        self.durationSecs = durationSecs; self.waveform = waveform; self.isSpoiler = isSpoiler
    }

    /// Serializes metadata without loading or embedding file bytes.
    /// - Returns: A request attachment object; existing IDs remain decimal strings and upload IDs remain numbers.
    /// - Throws: A JSON numeric validation error only if an invariant of Swift finite-number formatting changes.
    public func jsonValue() throws -> JSONValue {
        var fields: [String: JSONValue] = [:]
        switch id {
        case .existing(let value): fields["id"] = .string(value.description)
        case .upload(let value): fields["id"] = try messageRequestNumber(value)
        }
        if let filename { fields["filename"] = .string(filename) }
        if let title { fields["title"] = .string(title) }
        if let description { fields["description"] = .string(description) }
        if let durationSecs { fields["duration_secs"] = .number(try JSONNumber(rawValue: String(durationSecs))) }
        if let waveform { fields["waveform"] = .string(waveform) }
        if let isSpoiler { fields["is_spoiler"] = .bool(isSpoiler) }
        return .object(fields)
    }
}

/// Exact integer or string nonce used by Discord's bounded, recent-message deduplication window.
public enum MessageNonce: Sendable, Hashable {
    case integer(Int64)
    case unsignedInteger(UInt64)
    case string(String)

    /// Converts a nonce without rounding numeric identifiers.
    /// - Returns: An integer number or string, limited to 25 Unicode scalars in its wire representation.
    /// - Throws: A safe validation error for an overlong string nonce.
    public func jsonValue() throws -> JSONValue {
        switch self {
        case .integer(let value): return try messageRequestNumber(value)
        case .unsignedInteger(let value): return try messageRequestNumber(value)
        case .string(let value):
            guard value.unicodeScalars.count <= 25 else { throw DiscordError.validation(.invalidValue) }
            return .string(value)
        }
    }
}

/// Flags accepted by Create Message; arbitrary raw bits are rejected during request validation.
public struct MessageCreateFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public static let suppressEmbeds = Self(rawValue: 1 << 2)
    public static let suppressNotifications = Self(rawValue: 1 << 12)
    public static let isVoiceMessage = Self(rawValue: 1 << 13)
    public static let isComponentsV2 = Self(rawValue: 1 << 15)

    /// Stores flag bits; request construction validates the operation-specific allowed mask.
    /// - Parameter rawValue: Unsigned bitfield; no permission or upstream state is inferred.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Editable flags plus explicitly retained existing bits when previous flags are supplied.
public struct MessageEditFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public static let suppressEmbeds = Self(rawValue: 1 << 2)
    public static let isComponentsV2 = Self(rawValue: 1 << 15)

    /// Stores the complete outgoing bitfield; validation compares it with `MessageEdit.previousFlags`.
    /// - Parameter rawValue: Unsigned bits including any immutable bits being retained.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Typed API v10 Create Message payload, independent of transport, credentials and file ownership.
///
/// `jsonValue` validates the complete payload together with actual upload IDs. Sending requires
/// SEND_MESSAGES, plus SEND_TTS_MESSAGES for TTS and READ_MESSAGE_HISTORY for replies. Forward
/// eligibility and permissions remain server decisions. Enforced nonces only deduplicate within
/// Discord's recent-message window and do not establish general mutation retry safety.
public struct MessageCreate: Sendable {
    public let content: Field<String>
    public let nonce: Field<MessageNonce>
    public let tts: Field<Bool>
    public let embeds: Field<[MessageEmbed]>
    public let allowedMentions: Field<MessageAllowedMentions>
    public let messageReference: Field<MessageReference>
    public let components: Field<[MessageComponent]>
    public let stickerIDs: Field<[StickerID]>
    public let attachments: Field<[MessageAttachmentRequest]>
    public let flags: Field<MessageCreateFlags>
    public let enforceNonce: Field<Bool>
    public let poll: Field<PollCreate>
    public let sharedClientTheme: Field<MessageSharedClientTheme>

    /// Stores and validates all non-file create fields without allocating upload resources.
    /// - Parameters:
    ///   - content: Omitted or nonnull content, up to 2,000 Unicode scalars.
    ///   - nonce: Omitted or exact integer/string nonce, up to 25 characters.
    ///   - tts: Omitted or explicit TTS setting.
    ///   - embeds: Omitted or up to 10 sendable rich embeds, at most 6,000 aggregate text scalars.
    ///   - allowedMentions: Omitted or explicit parsing/notification policy.
    ///   - messageReference: Omitted or reply/forward reference; message ID is required when sending.
    ///   - components: Omitted or validated legacy/V2 message components selected by flags.
    ///   - stickerIDs: Omitted or up to three distinct sticker snowflakes.
    ///   - attachments: Omitted or metadata for new multipart upload IDs; existing IDs are edit-only.
    ///   - flags: Omitted or supported creation flags; V2 excludes traditional content fields.
    ///   - enforceNonce: Omitted or explicit recent nonce enforcement; omission retains upstream defaults.
    ///   - poll: Omitted or validated poll creation payload.
    ///   - sharedClientTheme: Omitted or shared client theme; incompatible with V2 messages.
    /// - Throws: Safe validation errors for forbidden nulls, invalid field combinations or field limits.
    ///   Empty/file-only requests are permitted here and validated against uploads by `jsonValue`.
    public init(content: Field<String> = .absent, nonce: Field<MessageNonce> = .absent,
                tts: Field<Bool> = .absent, embeds: Field<[MessageEmbed]> = .absent,
                allowedMentions: Field<MessageAllowedMentions> = .absent,
                messageReference: Field<MessageReference> = .absent,
                components: Field<[MessageComponent]> = .absent, stickerIDs: Field<[StickerID]> = .absent,
                attachments: Field<[MessageAttachmentRequest]> = .absent,
                flags: Field<MessageCreateFlags> = .absent, enforceNonce: Field<Bool> = .absent,
                poll: Field<PollCreate> = .absent, sharedClientTheme: Field<MessageSharedClientTheme> = .absent) throws {
        self.content = content; self.nonce = nonce; self.tts = tts; self.embeds = embeds
        self.allowedMentions = allowedMentions; self.messageReference = messageReference; self.components = components
        self.stickerIDs = stickerIDs; self.attachments = attachments; self.flags = flags
        self.enforceNonce = enforceNonce; self.poll = poll; self.sharedClientTheme = sharedClientTheme
        _ = try build(uploadIDs: nil, uploadContentTypes: [:])
    }

    /// Validates the complete outgoing create payload, including upload/reference/voice invariants.
    /// - Parameters:
    ///   - uploadIDs: Distinct nonnegative IDs of actual `files[n]` parts; defaults to no uploads.
    ///   - uploadContentTypes: Media types by upload ID, required for voice-message audio validation.
    /// - Returns: Non-file JSON object suitable for JSON or a multipart `payload_json` part.
    /// - Throws: Safe validation errors for an empty message, unmatched attachment IDs, incompatible flags,
    ///   invalid forwarded references or voice messages without exactly one fully described audio upload.
    public func jsonValue(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        try build(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
    }

    /// Serializes a complete request while preserving absent/null distinctions and numeric spellings.
    /// - Parameters:
    ///   - uploadIDs: Actual multipart file IDs, empty for JSON-only messages.
    ///   - uploadContentTypes: Actual media types for voice-message validation.
    ///   - limits: Explicit UTF-8, nesting and node bounds, defaulting to the shared JSON limits.
    /// - Returns: Deterministic complete UTF-8 JSON, excluding binary file bytes.
    /// - Throws: Complete request validation errors or bounded JSON serialization errors.
    public func serialized(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:],
                           limits: JSONLimits = .default) throws -> Data {
        try jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes).serialized(limits: limits)
    }

    /// Builds one immutable object; a nil upload list performs only context-independent initialization checks.
    /// - Parameters:
    ///   - uploadIDs: Actual IDs, or nil before file ownership has been supplied.
    ///   - uploadContentTypes: Content types belonging to those actual file IDs.
    /// - Returns: Validated fields without copying binary content.
    /// - Throws: Safe validation errors or nested request-model errors.
    private func build(uploadIDs: [Int]?, uploadContentTypes: [Int: String]) throws -> JSONValue {
        var result: [String: JSONValue] = [:]
        try messageRequestField(content, name: "content", into: &result) { value in
            guard value.unicodeScalars.count <= 2_000 else { throw DiscordError.validation(.limitExceeded) }
            return .string(value)
        }
        try messageRequestField(nonce, name: "nonce", into: &result) { try $0.jsonValue() }
        try messageRequestField(tts, name: "tts", into: &result) { .bool($0) }
        try messageRequestField(embeds, name: "embeds", into: &result) { try messageRequestEmbeds($0) }
        try messageRequestField(allowedMentions, name: "allowed_mentions", into: &result) { $0.jsonValue() }
        try messageRequestField(messageReference, name: "message_reference", into: &result) { $0.jsonValue() }
        try messageRequestField(stickerIDs, name: "sticker_ids", into: &result) { try messageRequestStickers($0) }
        try messageRequestField(attachments, name: "attachments", into: &result) { .array(try $0.map { try $0.jsonValue() }) }
        try messageRequestField(flags, name: "flags", into: &result) { try messageRequestNumber($0.rawValue) }
        try messageRequestField(enforceNonce, name: "enforce_nonce", into: &result) { .bool($0) }
        try messageRequestField(poll, name: "poll", into: &result) { try $0.jsonValue() }
        try messageRequestField(sharedClientTheme, name: "shared_client_theme", into: &result) { try messageRequestTheme($0) }
        let bits: UInt64 = if case .value(let flags) = flags { flags.rawValue } else { 0 }
        guard bits & ~UInt64((1 << 2) | (1 << 12) | (1 << 13) | (1 << 15)) == 0
        else { throw DiscordError.validation(.invalidValue) }
        guard bits & (1 << 13) == 0 || bits & (1 << 15) == 0 else { throw DiscordError.validation(.invalidValue) }
        let v2 = bits & (1 << 15) != 0
        try messageRequestField(components, name: "components", into: &result) {
            try MessageComponent.validateMessage($0, componentsV2: v2)
            return .array(try $0.map { try $0.jsonValue() })
        }
        if v2 {
            guard ["content", "embeds", "sticker_ids", "poll", "shared_client_theme"].allSatisfy({ result[$0] == nil })
            else { throw DiscordError.validation(.invalidValue) }
        }
        var forward = false
        if case .object(let reference) = result["message_reference"] {
            guard Set(reference.keys).isSubset(of: ["type", "message_id", "channel_id", "guild_id", "fail_if_not_exists"])
            else { throw DiscordError.validation(.invalidValue) }
            guard case .string = reference["message_id"] else { throw DiscordError.validation(.missingValue) }
            forward = reference["type"] == (try messageRequestNumber(1))
            if forward, case .string = reference["channel_id"] {} else if forward { throw DiscordError.validation(.missingValue) }
            if let type = reference["type"], type != (try messageRequestNumber(0)), type != (try messageRequestNumber(1)) {
                throw DiscordError.validation(.invalidValue)
            }
        }
        if let uploadIDs {
            try messageRequestAttachments(attachments, uploadIDs: uploadIDs, editing: false)
            let nonempty = ["content", "embeds", "sticker_ids", "components"].contains { name in
                switch result[name] { case .string(let text): !text.isEmpty; case .array(let values): !values.isEmpty; default: false }
            }
            guard forward || nonempty || !uploadIDs.isEmpty || result["poll"] != nil || result["shared_client_theme"] != nil
            else { throw DiscordError.validation(.missingValue) }
            if bits & (1 << 13) != 0 {
                guard uploadIDs.count == 1, case .value(let metadata) = attachments, metadata.count == 1,
                      metadata[0].durationSecs.map({ $0 > 0 }) == true,
                      metadata[0].waveform.map({ !$0.isEmpty }) == true,
                      uploadContentTypes[uploadIDs[0]]?.lowercased().hasPrefix("audio/") == true,
                      ["content", "embeds", "sticker_ids", "components", "poll", "shared_client_theme", "message_reference"].allSatisfy({ result[$0] == nil }),
                      result["tts"] != .bool(true)
                else { throw DiscordError.validation(.invalidValue) }
            }
        }
        return .object(result)
    }
}

/// Presence-aware API v10 edit payload with explicit retention and optional previous-flag evidence.
///
/// Absent fields preserve existing values; null is transmitted explicitly because Discord documents
/// edit parameters as nullable. An attachment array is the complete post-edit retained-and-new set.
/// Omitted allowed mentions restore Discord's defaults whenever edited content is reparsed.
public struct MessageEdit: Sendable {
    public let content: Field<String>
    public let embeds: Field<[MessageEmbed]>
    public let flags: Field<MessageEditFlags>
    public let allowedMentions: Field<MessageAllowedMentions>
    public let components: Field<[MessageComponent]>
    public let attachments: Field<[MessageAttachmentRequest]>
    public let stickerIDs: Field<[StickerID]>
    public let poll: Field<PollCreate>
    public let previousFlags: UInt64?

    /// Validates an edit without retrieving the original message or opening upload resources.
    /// - Parameters:
    ///   - content: Absent preserves content; null clears it; values are at most 2,000 Unicode scalars.
    ///   - embeds: Absent preserves embeds; null or an empty array clears them; up to 10/6,000 text scalars.
    ///   - flags: Complete outgoing flags; only SUPPRESS_EMBEDS and setting IS_COMPONENTS_V2 may change.
    ///   - allowedMentions: Absent uses Discord's edit defaults; null is retained explicitly.
    ///   - components: Absent preserves components; null/empty clears them; otherwise validated for resulting flags.
    ///   - attachments: Absent preserves existing files when no uploads are supplied; null/empty removes retained
    ///     files. Uploads require an explicit complete array of all retained and all newly uploaded file IDs,
    ///     following the API v10 uploading-files rule that PATCH appends only listed new files.
    ///   - stickerIDs: V2 migration reset only; an empty array or null is accepted, never replacement stickers.
    ///   - poll: V2 migration reset only; null is accepted, creating/replacing polls by edit is unsupported.
    ///   - previousFlags: Optional observed original bitfield, required to retain noneditable bits. Enables
    ///     rejection of voice edits, immutable-bit changes and attempts to remove the irreversible V2 flag.
    /// - Throws: Safe validation errors for excess content, invalid flags or incomplete V2 resets. Without
    ///   previous evidence, only editable flag bits may be sent and server-side voice restrictions still apply.
    public init(content: Field<String> = .absent, embeds: Field<[MessageEmbed]> = .absent,
                flags: Field<MessageEditFlags> = .absent, allowedMentions: Field<MessageAllowedMentions> = .absent,
                components: Field<[MessageComponent]> = .absent,
                attachments: Field<[MessageAttachmentRequest]> = .absent,
                stickerIDs: Field<[StickerID]> = .absent, poll: Field<PollCreate> = .absent,
                previousFlags: UInt64? = nil) throws {
        self.content = content; self.embeds = embeds; self.flags = flags; self.allowedMentions = allowedMentions
        self.components = components; self.attachments = attachments; self.stickerIDs = stickerIDs
        self.poll = poll; self.previousFlags = previousFlags
        _ = try build(uploadIDs: nil)
    }

    /// Produces an edit object after validating the complete retained/new attachment set.
    /// - Parameters:
    ///   - uploadIDs: Distinct nonnegative IDs of actual multipart file parts, empty for JSON edits.
    ///   - uploadContentTypes: Reserved media-type context for symmetry with creation; voice edits are prohibited.
    /// - Returns: Exact partial-update JSON; no fields are synthesized and null remains distinct from omission.
    /// - Throws: Safe field, flag, V2 transition or attachment-retention validation errors.
    public func jsonValue(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        try build(uploadIDs: uploadIDs)
    }

    /// Serializes an edit with explicit resource bounds and deterministic object key ordering.
    /// - Parameters:
    ///   - uploadIDs: Actual multipart upload IDs, empty when no files are appended.
    ///   - limits: Complete JSON byte, depth and node limits.
    /// - Returns: UTF-8 JSON containing only explicitly selected fields.
    /// - Throws: Request validation or bounded serialization errors.
    public func serialized(uploadIDs: [Int] = [], limits: JSONLimits = .default) throws -> Data {
        try jsonValue(uploadIDs: uploadIDs).serialized(limits: limits)
    }

    /// Builds a partial update while checking state transitions independently of network ownership.
    /// - Parameter uploadIDs: Actual upload IDs, or nil during initial field validation.
    /// - Returns: Presence-preserving JSON object.
    /// - Throws: Safe validation errors for invalid nullable values, flag transitions or retained-file sets.
    private func build(uploadIDs: [Int]?) throws -> JSONValue {
        if let previousFlags, previousFlags & (1 << 13) != 0 { throw DiscordError.validation(.invalidValue) }
        let mask: UInt64 = (1 << 2) | (1 << 15)
        let old = previousFlags ?? 0
        var resulting = old
        if case .value(let flags) = flags {
            resulting = flags.rawValue
            guard (resulting ^ old) & ~mask == 0, old & (1 << 15) == 0 || resulting & (1 << 15) != 0
            else { throw DiscordError.validation(.invalidValue) }
        }
        let v2 = resulting & (1 << 15) != 0
        let transition = v2 && old & (1 << 15) == 0
        if transition {
            guard case .null = content, case .value(let embeds) = embeds, embeds.isEmpty,
                  case .value(let stickers) = stickerIDs, stickers.isEmpty, case .null = poll
            else { throw DiscordError.validation(.invalidValue) }
        }
        var result: [String: JSONValue] = [:]
        try messageRequestField(content, name: "content", nullable: true, into: &result) {
            guard $0.unicodeScalars.count <= 2_000 else { throw DiscordError.validation(.limitExceeded) }
            return .string($0)
        }
        try messageRequestField(embeds, name: "embeds", nullable: true, into: &result) { try messageRequestEmbeds($0) }
        try messageRequestField(flags, name: "flags", nullable: true, into: &result) { try messageRequestNumber($0.rawValue) }
        try messageRequestField(allowedMentions, name: "allowed_mentions", nullable: true, into: &result) { $0.jsonValue() }
        try messageRequestField(components, name: "components", nullable: true, into: &result) {
            try MessageComponent.validateMessage($0, componentsV2: v2); return .array(try $0.map { try $0.jsonValue() })
        }
        try messageRequestField(attachments, name: "attachments", nullable: true, into: &result) { .array(try $0.map { try $0.jsonValue() }) }
        try messageRequestField(stickerIDs, name: "sticker_ids", nullable: true, into: &result) {
            guard $0.isEmpty else { throw DiscordError.validation(.invalidValue) }; return .array([])
        }
        if case .value = poll { throw DiscordError.validation(.invalidValue) }
        try messageRequestField(poll, name: "poll", nullable: true, into: &result) { try $0.jsonValue() }
        if v2 {
            if case .value = content { throw DiscordError.validation(.invalidValue) }
            if case .value(let values) = embeds, !values.isEmpty { throw DiscordError.validation(.invalidValue) }
        }
        if let uploadIDs { try messageRequestAttachments(attachments, uploadIDs: uploadIDs, editing: true) }
        return .object(result)
    }
}

/// Inserts one request field while enforcing endpoint-specific outer nullability.
/// - Parameters:
///   - field: Omitted, explicit null, or typed payload.
///   - name: Exact JSON key.
///   - nullable: Whether explicit null is legal, default false for creation.
///   - fields: Object being built synchronously; no partially built object escapes on error.
///   - encode: Typed payload validator/encoder; invoked only for present nonnull values.
/// - Throws: Safe invalid-value errors for forbidden null or errors from the typed encoder.
private func messageRequestField<Value>(_ field: Field<Value>, name: String, nullable: Bool = false,
                                       into fields: inout [String: JSONValue], encode: (Value) throws -> JSONValue) throws {
    switch field {
    case .absent: break
    case .null:
        guard nullable else { throw DiscordError.validation(.invalidValue) }; fields[name] = .null
    case .value(let value): fields[name] = try encode(value)
    }
}

/// Formats an integral Swift value as an exact JSON integer without a floating-point bridge.
/// - Parameter value: Signed or unsigned binary integer, including extreme values.
/// - Returns: A numeric JSON value with canonical decimal spelling.
/// - Throws: `JSONValueError.invalidNumber` only if the integer-formatting invariant is violated.
private func messageRequestNumber<Value: BinaryInteger>(_ value: Value) throws -> JSONValue {
    .number(try JSONNumber(rawValue: String(value)))
}

/// Validates the create-message sticker bound and rejects duplicate IDs.
/// - Parameter values: Typed sticker snowflakes, including the empty array.
/// - Returns: Canonical decimal-string IDs in caller order.
/// - Throws: Safe invalid-value errors for more than three IDs or duplicates.
private func messageRequestStickers(_ values: [StickerID]) throws -> JSONValue {
    guard values.count <= 3, Set(values).count == values.count else { throw DiscordError.validation(.invalidValue) }
    return .array(values.map { .string($0.description) })
}

/// Validates complete upload associations and explicit edit retention without opening files.
/// - Parameters:
///   - field: Optional complete attachment metadata list; null is edit-only and removes retained files.
///   - uploadIDs: Actual multipart placeholder IDs; at most ten distinct nonnegative values.
///   - editing: Whether existing attachment IDs are permitted and uploads require an explicit retention list.
/// - Throws: Safe validation errors for duplicate IDs, unmatched uploads, create-time retained IDs or excessive files.
private func messageRequestAttachments(_ field: Field<[MessageAttachmentRequest]>, uploadIDs: [Int], editing: Bool) throws {
    guard uploadIDs.count <= 10, uploadIDs.allSatisfy({ $0 >= 0 }), Set(uploadIDs).count == uploadIDs.count
    else { throw DiscordError.validation(.invalidValue) }
    guard case .value(let values) = field else {
        if editing, !uploadIDs.isEmpty { throw DiscordError.validation(.missingValue) }
        if case .null = field, !uploadIDs.isEmpty { throw DiscordError.validation(.invalidValue) }
        return
    }
    guard values.count <= 10, Set(values.map(\.id)).count == values.count else { throw DiscordError.validation(.invalidValue) }
    var placeholders = Set<Int>()
    for attachment in values {
        switch attachment.id {
        case .existing: guard editing else { throw DiscordError.validation(.invalidValue) }
        case .upload(let id): placeholders.insert(id)
        }
    }
    guard placeholders == Set(uploadIDs) else { throw DiscordError.validation(.invalidValue) }
}

/// Validates the sendable rich-embed subset and both individual and aggregate text bounds.
/// - Parameter values: Up to ten typed embeds; response-only/unknown fields are rejected for outgoing messages.
/// - Returns: Original numeric-preserving embed objects after validation.
/// - Throws: Safe validation errors for unsupported fields, malformed nested structures or Discord text limits.
private func messageRequestEmbeds(_ values: [MessageEmbed]) throws -> JSONValue {
    guard values.count <= 10 else { throw DiscordError.validation(.limitExceeded) }
    var total = 0
    let allowed: Set<String> = ["title", "description", "url", "timestamp", "color", "footer", "image", "thumbnail", "author", "fields", "flags", "components"]
    for embed in values {
        guard case .object(let fields) = embed.jsonValue(), Set(fields.keys).isSubset(of: allowed)
        else { throw DiscordError.validation(.invalidValue) }
        for (name, maximum) in [("title", 256), ("description", 4_096)] {
            if let value = fields[name] {
                guard case .string(let text) = value, messageRequestEmbedTextLength(text) <= maximum else { throw DiscordError.validation(.invalidValue) }
                total += messageRequestEmbedTextLength(text)
            }
        }
        for (name, textKey, maximum, allowedKeys) in [
            ("footer", "text", 2_048, Set(["text", "icon_url", "proxy_icon_url"])),
            ("author", "name", 256, Set(["name", "url", "icon_url", "proxy_icon_url"]))
        ] {
            if let value = fields[name] {
                guard case .object(let nested) = value, Set(nested.keys).isSubset(of: allowedKeys),
                      case .string(let text) = nested[textKey], messageRequestEmbedTextLength(text) <= maximum,
                      nested.values.allSatisfy({ if case .string = $0 { true } else { false } })
                else { throw DiscordError.validation(.invalidValue) }
                total += messageRequestEmbedTextLength(text)
            }
        }
        for name in ["image", "thumbnail"] {
            if let value = fields[name] {
                guard case .object(let nested) = value,
                      Set(nested.keys).isSubset(of: ["url", "content_type", "placeholder", "placeholder_version", "description", "flags"]),
                      case .string = nested["url"]
                else { throw DiscordError.validation(.invalidValue) }
                for key in ["content_type", "placeholder", "description"] {
                    if let value = nested[key], case .string = value {} else if nested[key] != nil { throw DiscordError.validation(.invalidValue) }
                }
                for key in ["placeholder_version", "flags"] {
                    if let value = nested[key] {
                        guard case .number(let number) = value, UInt64(number.rawValue) != nil
                        else { throw DiscordError.validation(.invalidValue) }
                    }
                }
            }
        }
        if let value = fields["fields"] {
            guard case .array(let rows) = value, rows.count <= 25 else { throw DiscordError.validation(.invalidValue) }
            for row in rows {
                guard case .object(let nested) = row, Set(nested.keys).isSubset(of: ["name", "value", "inline"]),
                      case .string(let name) = nested["name"], messageRequestEmbedTextLength(name) <= 256,
                      case .string(let value) = nested["value"], messageRequestEmbedTextLength(value) <= 1_024
                else { throw DiscordError.validation(.invalidValue) }
                if let inline = nested["inline"], case .bool = inline {} else if nested["inline"] != nil { throw DiscordError.validation(.invalidValue) }
                total += messageRequestEmbedTextLength(name) + messageRequestEmbedTextLength(value)
            }
        }
        for name in ["url", "timestamp"] {
            if let value = fields[name], case .string = value {} else if fields[name] != nil { throw DiscordError.validation(.invalidValue) }
        }
        if let color = fields["color"] {
            guard case .number(let number) = color, let value = UInt64(number.rawValue), value <= 0xFFFFFF
            else { throw DiscordError.validation(.invalidValue) }
        }
        if let flags = fields["flags"] {
            guard case .number(let number) = flags, UInt64(number.rawValue) != nil
            else { throw DiscordError.validation(.invalidValue) }
        }
        if let components = fields["components"], case .array = components {} else if fields["components"] != nil {
            throw DiscordError.validation(.invalidValue)
        }
        guard total <= 6_000 else { throw DiscordError.validation(.limitExceeded) }
    }
    return .array(values.map { $0.jsonValue() })
}

/// Counts embed text according to Discord's inclusive bounds after automatic outer whitespace trimming.
/// - Parameter value: Original outgoing text, retained unchanged in serialized requests.
/// - Returns: Unicode scalar count after trimming Foundation whitespace/newline characters at both ends.
private func messageRequestEmbedTextLength(_ value: String) -> Int {
    value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
}

/// Validates shared-theme request ranges while preserving explicit nullable base-theme selection.
/// - Parameter theme: Typed response-compatible theme value; outgoing requests accept only known fields.
/// - Returns: Original theme object with unchanged colors and exact integer values.
/// - Throws: Safe invalid-value errors for more than five nonhex RGB colors, invalid percentages/angles,
///   unknown base-theme values or unknown outgoing fields. Empty colors are accepted because no minimum is documented.
private func messageRequestTheme(_ theme: MessageSharedClientTheme) throws -> JSONValue {
    let value = theme.jsonValue()
    guard case .object(let fields) = value,
          Set(fields.keys).isSubset(of: ["colors", "gradient_angle", "base_mix", "base_theme"]),
          case .array(let colors) = fields["colors"], colors.count <= 5
    else { throw DiscordError.validation(.invalidValue) }
    for color in colors {
        guard case .string(let text) = color, text.utf8.count == 6,
              text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { throw DiscordError.validation(.invalidValue) }
    }
    for (key, maximum) in [("gradient_angle", 360), ("base_mix", 100)] {
        guard case .number(let number) = fields[key], let integer = Int(number.rawValue), (0...maximum).contains(integer)
        else { throw DiscordError.validation(.invalidValue) }
    }
    if let base = fields["base_theme"], base != .null {
        guard case .number(let number) = base, let integer = Int(number.rawValue), (0...4).contains(integer)
        else { throw DiscordError.validation(.invalidValue) }
    }
    return value
}
