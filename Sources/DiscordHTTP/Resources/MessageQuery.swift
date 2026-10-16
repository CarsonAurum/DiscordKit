import DiscordCore
import DiscordModels
import Foundation

/// One mutually exclusive history cursor; history is returned newest first.
public enum MessageHistoryPosition: Sendable, Hashable {
    case before(MessageID), after(MessageID), around(MessageID)
}

/// The two documented reaction-list variants; burst reactions are also called super reactions.
public enum MessageReactionType: Int, Sendable, CaseIterable { case normal = 0, burst = 1 }

/// Unescaped reaction route value. Descriptors apply UTF-8 percent encoding exactly once.
public enum ReactionEmoji: Sendable, Hashable {
    case unicode(String)
    case custom(name: String, id: Snowflake<EmojiTag>)

    /// Validates a route segment without looking up emoji availability or permissions.
    /// - Returns: Unicode text or `name:id`; never a pre-escaped string.
    /// - Throws: A safe validation error for empty names, controls or path separators.
    func segment() throws -> String {
        let result: String
        switch self {
        case .unicode(let text): result = text
        case .custom(let name, let id):
            guard !name.isEmpty, !name.contains(":") else { throw DiscordError.validation(.invalidValue) }
            result = name + ":" + id.description
        }
        guard !result.isEmpty, result != ".", result != "..", !result.contains("/"), !result.contains("\\"),
              !result.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw DiscordError.validation(.invalidValue) }
        return result
    }
}

/// Tag for custom emoji IDs without importing the later emoji-resource family.
public enum EmojiTag: Sendable {}

/// Search author filters, including the documented negative forms.
public enum MessageSearchAuthor: String, Sendable, CaseIterable {
    case user, bot, webhook
    case excludeUser = "-user", excludeBot = "-bot", excludeWebhook = "-webhook"
}

/// Search presence filters. Negative forms exclude matching messages.
public enum MessageSearchHas: String, Sendable, CaseIterable {
    case image, sound, video, file, sticker, embed, link, poll, snapshot
    case excludeImage = "-image", excludeSound = "-sound", excludeVideo = "-video"
    case excludeFile = "-file", excludeSticker = "-sticker", excludeEmbed = "-embed"
    case excludeLink = "-link", excludePoll = "-poll", excludeSnapshot = "-snapshot"
}

/// Search embed classes differ from the actual message embed type vocabulary.
public enum MessageSearchEmbed: String, Sendable, CaseIterable { case image, video, gif, sound, article }
/// Relevance ignores sort direction. Timestamp sorting is Discord's default.
public enum MessageSearchSort: String, Sendable, CaseIterable { case timestamp, relevance }
/// Search direction; descending is the upstream default.
public enum MessageSearchOrder: String, Sendable, CaseIterable { case asc, desc }

/// Complete API v10 guild-message search query, verified 2026-10-16.
///
/// Arrays encode repeated names (without brackets) as required by the official reference.
/// Construction performs no I/O. Search requires READ_MESSAGE_HISTORY and the application's
/// MESSAGE_CONTENT eligibility. Neither a result nor a cached snapshot establishes permissions.
public struct MessageSearchQuery: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let limit: Int
    public let offset: Int
    public let fields: [QueryItem]

    /// Validates all currently documented filters while preserving array order and exact IDs.
    /// - Parameters:
    ///   - limit: Results per request, 1...25; default 25.
    ///   - offset: Initial search offset, 0...9975; default zero.
    ///   - maximumID: Optional exclusive upper snowflake boundary.
    ///   - minimumID: Optional exclusive lower snowflake boundary.
    ///   - slop: Optional token gap, 0...100; omission uses Discord's default two.
    ///   - content: Optional content filter, at most 1,024 Unicode scalars.
    ///   - channelIDs: At most 500 channel filters; an empty array omits the parameter.
    ///   - authorTypes: Known positive or negative author categories.
    ///   - authorIDs: At most 100 exact author IDs.
    ///   - mentions: At most 100 user mention filters.
    ///   - mentionRoleIDs: At most 100 role mention filters.
    ///   - mentionEveryone: Optional inclusion/exclusion of everyone mentions.
    ///   - repliedToUserIDs: At most 100 reply-author filters.
    ///   - repliedToMessageIDs: At most 100 reply-target filters.
    ///   - pinned: Optional pinned-state filter.
    ///   - has: Known positive or negative content-presence filters.
    ///   - embedTypes: Search-specific embed classes.
    ///   - embedProviders: At most 100 case-sensitive provider strings, 256 scalars each.
    ///   - linkHostnames: At most 100 hostname strings, 256 scalars each.
    ///   - attachmentFilenames: At most 100 filename filters, 1,024 scalars each.
    ///   - attachmentExtensions: At most 100 extension filters, 256 scalars each.
    ///   - sortBy: Optional algorithm; omission uses timestamp. Relevance ignores direction.
    ///   - sortOrder: Optional direction; omission uses descending.
    ///   - includeNSFW: Optional inclusion of age-restricted channels; omission uses false.
    /// - Throws: Safe validation errors for out-of-range counts or lengths. No normalization,
    ///   permission lookup or deduplication is performed. Aggregate query text is bounded by
    ///   endpoint construction to 1 MiB and 2,048 fields, including a later paging offset.
    public init(limit: Int = 25, offset: Int = 0, maximumID: MessageID? = nil, minimumID: MessageID? = nil,
                slop: Int? = nil, content: String? = nil, channelIDs: [ChannelID] = [],
                authorTypes: [MessageSearchAuthor] = [], authorIDs: [UserID] = [], mentions: [UserID] = [],
                mentionRoleIDs: [RoleID] = [], mentionEveryone: Bool? = nil,
                repliedToUserIDs: [UserID] = [], repliedToMessageIDs: [MessageID] = [], pinned: Bool? = nil,
                has: [MessageSearchHas] = [], embedTypes: [MessageSearchEmbed] = [],
                embedProviders: [String] = [], linkHostnames: [String] = [], attachmentFilenames: [String] = [],
                attachmentExtensions: [String] = [], sortBy: MessageSearchSort? = nil,
                sortOrder: MessageSearchOrder? = nil, includeNSFW: Bool? = nil) throws {
        guard (1...25).contains(limit), (0...9_975).contains(offset), slop.map({ (0...100).contains($0) }) ?? true,
              (content?.unicodeScalars.count ?? 0) <= 1_024, channelIDs.count <= 500,
              [authorIDs.count, mentions.count, mentionRoleIDs.count, repliedToUserIDs.count,
               repliedToMessageIDs.count, embedProviders.count, linkHostnames.count,
               attachmentFilenames.count, attachmentExtensions.count].allSatisfy({ $0 <= 100 }),
              authorTypes.count <= 6, has.count <= 18, embedTypes.count <= 5,
              (embedProviders + linkHostnames + attachmentExtensions).allSatisfy({ $0.unicodeScalars.count <= 256 }),
              attachmentFilenames.allSatisfy({ $0.unicodeScalars.count <= 1_024 })
        else { throw DiscordError.validation(.invalidValue) }
        self.limit = limit; self.offset = offset
        var fields = [QueryItem(name: "limit", value: String(limit))]
        if let maximumID { fields.append(.init(name: "max_id", value: maximumID.description)) }
        if let minimumID { fields.append(.init(name: "min_id", value: minimumID.description)) }
        if let slop { fields.append(.init(name: "slop", value: String(slop))) }
        if let content { fields.append(.init(name: "content", value: content)) }
        let arrays: [(String, [String])] = [
            ("channel_id", channelIDs.map(\.description)), ("author_type", authorTypes.map(\.rawValue)),
            ("author_id", authorIDs.map(\.description)), ("mentions", mentions.map(\.description)),
            ("mentions_role_id", mentionRoleIDs.map(\.description)),
            ("replied_to_user_id", repliedToUserIDs.map(\.description)),
            ("replied_to_message_id", repliedToMessageIDs.map(\.description)),
            ("has", has.map(\.rawValue)), ("embed_type", embedTypes.map(\.rawValue)),
            ("embed_provider", embedProviders), ("link_hostname", linkHostnames),
            ("attachment_filename", attachmentFilenames), ("attachment_extension", attachmentExtensions),
        ]
        for (key, values) in arrays { fields += values.map { QueryItem(name: key, value: $0) } }
        if let mentionEveryone { fields.append(.init(name: "mention_everyone", value: String(mentionEveryone))) }
        if let pinned { fields.append(.init(name: "pinned", value: String(pinned))) }
        if let sortBy { fields.append(.init(name: "sort_by", value: sortBy.rawValue)) }
        if let sortOrder { fields.append(.init(name: "sort_order", value: sortOrder.rawValue)) }
        if let includeNSFW { fields.append(.init(name: "include_nsfw", value: String(includeNSFW))) }
        self.fields = fields
    }

    /// Produces a new page query without mutating the original filter set or performing I/O.
    /// - Parameter offset: Explicit next offset, 0...9975; nil uses the configured initial offset.
    /// - Returns: Complete ordered repeated fields with one offset key.
    /// - Throws: A safe validation error outside Discord's search window.
    public func queryItems(offset: Int? = nil) throws -> [QueryItem] {
        let offset = offset ?? self.offset
        guard (0...9_975).contains(offset) else { throw DiscordError.validation(.invalidValue) }
        return fields + [QueryItem(name: "offset", value: String(offset))]
    }

    /// Hides content filters, filenames and identifiers from ordinary diagnostics.
    public var description: String { "MessageSearchQuery(redacted)" }
    /// Uses the same redacted marker in debug output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding retained search data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
