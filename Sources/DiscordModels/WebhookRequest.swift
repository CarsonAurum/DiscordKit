import DiscordCore
import Foundation

/// Validated API v10 webhook creation; execution requires MANAGE_WEBHOOKS.
public struct WebhookCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Validates a required webhook name and optional nullable avatar without acquiring resources.
    /// - Parameters:
    ///   - name: 1...80 scalars, excluding case-insensitive Discord/Clyde substrings and control characters.
    ///   - avatar: Omitted by default, null for no avatar, or canonical base64/image-data URI.
    /// - Throws: Safe invalid-value errors for invalid name/image data; Discord enforces additional nickname rules.
    public init(name: String, avatar: Field<String> = .absent) throws {
        var result = ["name": try webhookName(name)]
        try guildRequestField(avatar, name: "avatar", nullable: true, into: &result, encode: guildRequestImage)
        fields = result
    }
    /// Produces the exact validated creation object without defaults or permission lookups.
    /// - Returns: Credential-free JSON; explicit callers own safe handling of avatar bytes.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Presence-aware webhook metadata PATCH; only bot-authenticated endpoints permit channel movement.
public struct WebhookModify: GuildRequestPayload {
    private let fields: [String: JSONValue]
    public let channelID: Field<ChannelID>
    /// Validates optional changes without fetching the original webhook.
    /// - Parameters:
    ///   - name: Omitted preserves the name; nonnull names follow the create-name bounds.
    ///   - avatar: Omitted preserves; null removes; present values are validated canonical image data.
    ///   - channelID: Omitted preserves destination; nonnull channel moves require bot authentication.
    /// - Throws: Safe field/name/image errors. Token endpoint construction rejects any supplied channel ID.
    public init(name: Field<String> = .absent, avatar: Field<String> = .absent,
                channelID: Field<ChannelID> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result, encode: webhookName)
        try guildRequestField(avatar, name: "avatar", nullable: true, into: &result, encode: guildRequestImage)
        try guildRequestField(channelID, name: "channel_id", into: &result) { .string($0.description) }
        self.channelID = channelID; fields = result
    }
    /// Produces the exact PATCH object, retaining explicit avatar removal and empty changes.
    /// - Returns: Validated JSON without inferred server values or additional reads.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Explicit webhook component ownership evidence, checked locally without a hidden webhook read.
public enum WebhookComponentOwnership: Sendable {
    /// Application-owned webhook; Discord always respects components, including interactive controls.
    case applicationOwned
    /// Ordinary incoming webhook; requires with_components=true and only noninteractive controls.
    case incoming
}

/// API v10 native webhook execution fields, reusing validated message content and bounded upload metadata.
/// Channel-only references/nonces/stickers/themes and voice flags are rejected. Omitted values preserve
/// Discord defaults. Thread names/tags require forum/media channels; current channel type remains a server check.
public struct WebhookExecute: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let message: MessageCreate
    public let threadName: Field<String>
    private let extras: [String: JSONValue]

    /// Validates non-file webhook fields synchronously; file associations are checked by jsonValue.
    /// - Parameters:
    ///   - message: Typed content/embeds/components/poll/mentions/TTS/attachment metadata. Only webhook flags are permitted.
    ///   - username: Omitted uses the webhook name; nonnull override must have 1...80 scalars.
    ///   - avatarURL: Omitted uses the avatar; nonnull absolute HTTP(S) URL has at most 2,048 scalars and no user credentials.
    ///   - threadName: Omitted sends to the channel or selected thread; nonnull 1...100 scalar name creates a forum/media thread.
    ///   - appliedTags: Omitted preserves defaults; up to five distinct tags, permitted only with a new thread name.
    /// - Throws: Safe invalid-value errors for unsupported fields, flags or contradictory thread metadata.
    ///   Empty/file-only message bodies remain valid until complete upload validation.
    public init(message: MessageCreate, username: Field<String> = .absent, avatarURL: Field<String> = .absent,
                threadName: Field<String> = .absent, appliedTags: Field<[ForumTagID]> = .absent) throws {
        guard case .absent = message.nonce, case .absent = message.messageReference,
              case .absent = message.stickerIDs, case .absent = message.enforceNonce,
              case .absent = message.sharedClientTheme else { throw DiscordError.validation(.invalidValue) }
        if case .value(let flags) = message.flags {
            guard flags.rawValue & ~UInt64((1 << 2) | (1 << 12) | (1 << 15)) == 0
            else { throw DiscordError.validation(.invalidValue) }
        }
        var fields: [String: JSONValue] = [:]
        try guildRequestField(username, name: "username", into: &fields) { try guildRequestText($0, length: 1...80) }
        try guildRequestField(avatarURL, name: "avatar_url", into: &fields) { value in
            guard value.unicodeScalars.count <= 2_048, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, url.user == nil, url.password == nil
            else { throw DiscordError.validation(.invalidValue) }
            return .string(value)
        }
        try guildRequestField(threadName, name: "thread_name", into: &fields) { try guildRequestText($0, length: 1...100) }
        try guildRequestField(appliedTags, name: "applied_tags", into: &fields) { values in
            guard case .value = threadName, values.count <= 5, Set(values).count == values.count
            else { throw DiscordError.validation(.invalidValue) }
            return .array(values.map { .string($0.description) })
        }
        self.message = message; self.threadName = threadName; extras = fields
    }

    /// Validates the full payload, component eligibility and forum/media routing without opening file sources.
    /// - Parameters:
    ///   - uploadIDs: Actual distinct nonnegative multipart file IDs, empty for JSON requests.
    ///   - threadID: Optional existing destination thread; conflicts with a new thread name.
    ///   - isForumOrMedia: True requires either an existing thread ID or a new thread name; default false cannot infer type.
    ///   - ownership: Explicit caller-known ownership; incoming by default restricts interactive components.
    ///   - withComponents: False default mirrors Discord; incoming components require an explicit true value.
    /// - Returns: Complete non-file JSON including only explicitly supplied webhook extras.
    /// - Throws: Safe field/upload errors, missing content/thread errors or invalid component/V2 combinations.
    ///   Components V2 cannot accompany uploaded files on this endpoint, per the current webhook reference.
    public func jsonValue(uploadIDs: [Int] = [], threadID: ChannelID? = nil, isForumOrMedia: Bool = false,
                          ownership: WebhookComponentOwnership = .incoming, withComponents: Bool = false) throws -> JSONValue {
        let hasName: Bool = if case .value = threadName { true } else { false }
        guard !(threadID != nil && hasName), !isForumOrMedia || threadID != nil || hasName
        else { throw DiscordError.validation(.invalidValue) }
        try webhookComponents(message.components, ownership: ownership, withComponents: withComponents)
        if case .value(let flags) = message.flags, flags.contains(.isComponentsV2), !uploadIDs.isEmpty {
            throw DiscordError.validation(.invalidValue)
        }
        guard case .object(var fields) = try message.jsonValue(uploadIDs: uploadIDs)
        else { throw DiscordError.validation(.invalidValue) }
        fields.merge(extras) { _, value in value }
        return .object(fields)
    }
    /// Conceals message text, URLs and attachment metadata in normal diagnostics.
    public var description: String { "WebhookExecute(redacted)" }
    /// Conceals outgoing content in debug formatting.
    public var debugDescription: String { description }
    /// Conceals all nested outgoing message values and URL strings.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// API v10 webhook-message PATCH with complete attachment retention and nullable reset fields.
/// Ordinary webhook edits cannot create polls; deferred interaction poll creation is a separate surface.
public struct WebhookMessageEdit: Sendable {
    private let edit: MessageEdit
    private let fields: [String: JSONValue]
    private let components: Field<[MessageComponent]>

    /// Validates an edit without reading current state, assuming only supplied previous-flag evidence.
    /// - Parameters:
    ///   - content: Omitted preserves; null clears; values have at most 2,000 scalars.
    ///   - embeds: Omitted preserves; null/empty clears; present values use shared rich-embed bounds.
    ///   - flags: Nullable outgoing flags; only SUPPRESS_EMBEDS/setting IS_COMPONENTS_V2 are mutable.
    ///   - allowedMentions: Omitted restores Discord edit defaults; nullable explicit policy is preserved.
    ///   - components: Omitted preserves; null/empty clears; present values obey resulting component flags.
    ///   - attachments: Complete retained-and-new attachment set; uploads require an explicit array. Null removes all.
    ///   - poll: Omitted preserves existing poll; only null is writable on ordinary webhook edits.
    ///   - previousFlags: Optional observed original flags, needed to retain immutable bits or prove V2 already set.
    ///     Existing V2 messages may append uploads with a complete attachment retention array.
    /// - Throws: Safe field/flag errors. Transitioning to V2 requires explicit null content/embeds/attachments/poll;
    ///   this conservative reset cannot retain traditional fields or upload new files.
    public init(content: Field<String> = .absent, embeds: Field<[MessageEmbed]> = .absent,
                flags: Field<MessageEditFlags> = .absent, allowedMentions: Field<MessageAllowedMentions> = .absent,
                components: Field<[MessageComponent]> = .absent, attachments: Field<[MessageAttachmentRequest]> = .absent,
                poll: Field<PollCreate> = .absent, previousFlags: UInt64? = nil) throws {
        let bits = if case .value(let flags) = flags { flags.rawValue } else { previousFlags ?? 0 }
        let isV2 = bits & (1 << 15) != 0
        let transition = isV2 && (previousFlags ?? 0) & (1 << 15) == 0
        if transition {
            guard case .null = content, case .null = embeds, case .null = attachments, case .null = poll
            else { throw DiscordError.validation(.invalidValue) }
        }
        let validated = try MessageEdit(content: content, embeds: transition ? .value([]) : embeds, flags: flags,
            allowedMentions: allowedMentions, components: components, attachments: attachments,
            stickerIDs: transition ? .value([]) : .absent, poll: poll, previousFlags: previousFlags)
        self.edit = validated; self.components = components
        // Initialization cannot validate actual upload IDs. Preserve explicitly nullable webhook fields separately.
        var fields: [String: JSONValue] = [:]
        if transition { fields["embeds"] = .null }
        self.fields = fields
    }

    /// Checks upload retention and component eligibility before bounded body construction.
    /// - Parameters:
    ///   - uploadIDs: Actual distinct multipart file IDs, empty by default.
    ///   - ownership: Incoming by default; application-owned permits interactive components.
    ///   - withComponents: Incoming component edits require true; ignored for application-owned eligibility.
    /// - Returns: Exact webhook PATCH JSON without channel-only sticker reset fields.
    /// - Throws: Safe retention/component errors. Initial V2 migration clears attachments and cannot upload;
    ///   subsequent edits of an observed V2 message permit uploads under the ordinary retention rules.
    public func jsonValue(uploadIDs: [Int] = [], ownership: WebhookComponentOwnership = .incoming,
                          withComponents: Bool = false) throws -> JSONValue {
        try webhookComponents(components, ownership: ownership, withComponents: withComponents)
        guard case .object(var result) = try edit.jsonValue(uploadIDs: uploadIDs)
        else { throw DiscordError.validation(.invalidValue) }
        result.removeValue(forKey: "sticker_ids")
        result.merge(fields) { _, value in value }
        return .object(result)
    }
}

/// Validates current documented webhook-name bounds while keeping Discord's additional nickname checks upstream.
/// - Parameter value: Exact name, never normalized or trimmed.
/// - Returns: Original JSON string.
/// - Throws: Sanitized invalid-value errors for empty/overlong names, forbidden substrings or controls.
private func webhookName(_ value: String) throws -> JSONValue {
    guard (1...80).contains(value.unicodeScalars.count), !value.lowercased().contains("discord"),
          !value.lowercased().contains("clyde"), !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Rejects component submissions Discord would ignore, and interactive components on ordinary incoming webhooks.
/// - Parameters:
///   - components: Optional complete validated message component array; explicit null/empty also requires incoming opt-in.
///   - ownership: Explicit application-ownership evidence, never inferred from possession of the token.
///   - withComponents: Query opt-in required for nonempty incoming components.
/// - Throws: Safe invalid-value errors for ignored or interactive incoming components; recursion is bounded by model limits.
private func webhookComponents(_ components: Field<[MessageComponent]>, ownership: WebhookComponentOwnership,
                               withComponents: Bool) throws {
    if case .absent = components { return }
    if case .applicationOwned = ownership { return }
    guard withComponents else { throw DiscordError.validation(.invalidValue) }
    guard case .value(let values) = components else { return }
    var pending = values
    while let component = pending.popLast() {
        let fields = try component.jsonValue()
        // Interactive controls carry custom_id; link and premium buttons remain noninteractive.
        guard case .object(let object) = fields, object["custom_id"] == nil
        else { throw DiscordError.validation(.invalidValue) }
        if case .value(let children) = component.components { pending.append(contentsOf: children) }
        if case .value(let accessory) = component.accessory { pending.append(accessory) }
    }
}
