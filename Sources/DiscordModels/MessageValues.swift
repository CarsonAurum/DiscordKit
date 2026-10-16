import DiscordCore
import Foundation

/// A bounded message-resource projection whose original exact JSON remains available deliberately.
///
/// Parsing is synchronous, performs no I/O or credential access, and retains unknown fields.
/// Ordinary descriptions and reflection conceal payloads. These response values do not establish
/// current permissions, intent visibility, resource existence, or authorization to fetch URLs.
public protocol MessageResponseValue: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Complete original object, including unknown fields and exact numeric lexemes.
    var rawFields: [String: JSONValue] { get }

    /// Parses a complete object under explicit byte, depth and node limits.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; required keys and known field types are checked.
    ///   - limits: Bounds covering the entire document, including unknown nested values.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for schema violations.
    init(data: Data, limits: JSONLimits) throws
}

extension MessageResponseValue {
    /// Returns the exact semantic tree for deliberate inspection or operation-specific encoding.
    /// - Returns: The complete original object. Callers own subsequent logging and request validation.
    public func jsonValue() -> JSONValue { .object(rawFields) }
    /// Conceals payload values from ordinary formatting without allocating a serialized document.
    public var description: String { "\(Self.self)(redacted)" }
    /// Uses the same redacted marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing message content or signed asset URLs.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Internal subtree construction after a complete outer document has passed parser limits.
protocol MessageTreeProjectable: MessageResponseValue {
    /// Projects an already bounded immutable subtree without reparsing or normalizing unknown values.
    /// - Parameters:
    ///   - value: Original object subtree from the bounded root.
    ///   - limits: The bounds used to parse that root.
    /// - Throws: Sanitized invalid-response errors when a modeled field violates its contract.
    init(value: JSONValue, limits: JSONLimits) throws
}

extension PayloadObject {
    /// Requires one nested message-owned object, preserving unknown fields in its typed projection.
    /// - Parameters:
    ///   - name: Required wire key, which must contain a nonnull object.
    ///   - type: The projection type used for that object.
    /// - Returns: A typed view sharing immutable JSON subtree storage with the containing response.
    /// - Throws: Safe invalid-response errors for missing keys, wrong roots or malformed nested fields.
    func messageModel<T: MessageTreeProjectable>(_ name: String, _ type: T.Type) throws -> T {
        guard let value = resource.fields[name] else { throw DiscordError.transport(.invalidResponse) }
        return try T(value: value, limits: limits)
    }

    /// Projects an optional nested object while keeping omission separate from allowed explicit null.
    /// - Parameters:
    ///   - name: Optional wire key.
    ///   - type: The projection type used for present objects.
    ///   - nullable: Whether null is permitted; defaults to false.
    /// - Returns: Absent, permitted null, or the validated projection.
    /// - Throws: Safe invalid-response errors for forbidden null or malformed objects.
    func messageField<T: MessageTreeProjectable>(_ name: String, _ type: T.Type, nullable: Bool = false) throws -> Field<T> {
        try nested(name, nullable: nullable) { try T(value: $0, limits: limits) }
    }

    /// Requires an ordered array of message-owned objects and validates every element.
    /// - Parameters:
    ///   - name: Required key whose value must be a nonnull array.
    ///   - type: Projection applied to each element, in wire order.
    /// - Returns: The complete typed array, including an empty array.
    /// - Throws: Safe invalid-response errors for missing keys, wrong roots or invalid elements.
    func messageModels<T: MessageTreeProjectable>(_ name: String, _ type: T.Type) throws -> [T] {
        guard case .array(let values) = resource.fields[name] else { throw DiscordError.transport(.invalidResponse) }
        return try values.map { try T(value: $0, limits: limits) }
    }

    /// Projects an optional ordered object array without treating explicit null as omission.
    /// - Parameters:
    ///   - name: Optional nonnull array key.
    ///   - type: Projection applied once to each original subtree.
    /// - Returns: Absent or the complete typed array in wire order.
    /// - Throws: Safe invalid-response errors for null, wrong roots or malformed elements.
    func messageArray<T: MessageTreeProjectable>(_ name: String, _ type: T.Type) throws -> Field<[T]> {
        try array(name) { try T(value: $0, limits: limits) }
    }

    /// Projects an optional finite floating-point number without imposing integer token rules.
    /// - Parameter name: Optional nonnull numeric wire key, expressed in seconds where documented.
    /// - Returns: Absent or a finite Double; exact original spelling remains in rawFields.
    /// - Throws: Safe invalid-response errors for nonnumeric or nonfinite/out-of-range values.
    func messageNumber(_ name: String) throws -> Field<Double> {
        try nested(name) { value in
            guard case .number(let number) = value, let result = Double(number.rawValue), result.isFinite
            else { throw DiscordError.transport(.invalidResponse) }
            return result
        }
    }
}

/// Marker distinguishing attachment snowflakes from message and user identifiers.
public enum AttachmentTag: Sendable {}
/// Exact unsigned attachment identifier, including all 64 bits.
public typealias AttachmentID = Snowflake<AttachmentTag>
/// Marker distinguishing sticker snowflakes from other Discord resources.
public enum StickerTag: Sendable {}
/// Exact unsigned sticker identifier.
public typealias StickerID = Snowflake<StickerTag>
/// Marker for role subscription listing identifiers carried by purchase messages.
public enum RoleSubscriptionListingTag: Sendable {}
/// Exact unsigned role-subscription listing identifier.
public typealias RoleSubscriptionListingID = Snowflake<RoleSubscriptionListingTag>
/// Marker for interaction identifiers without coupling Messages to the Interactions product.
public enum MessageInteractionTag: Sendable {}
/// Exact unsigned interaction identifier carried by response metadata.
public typealias MessageInteractionID = Snowflake<MessageInteractionTag>

/// Documented API v10 MessageType values; RawValue preserves future values without claiming support.
public enum MessageType: Int, Sendable {
    /// The upstream `DEFAULT` variant with raw value 0.
    case `default` = 0
    /// The upstream `RECIPIENTADD` variant with raw value 1.
    case recipientAdd = 1
    /// The upstream `RECIPIENTREMOVE` variant with raw value 2.
    case recipientRemove = 2
    /// The upstream `CALL` variant with raw value 3.
    case call = 3
    /// The upstream `CHANNELNAMECHANGE` variant with raw value 4.
    case channelNameChange = 4
    /// The upstream `CHANNELICONCHANGE` variant with raw value 5.
    case channelIconChange = 5
    /// The upstream `CHANNELPINNEDMESSAGE` variant with raw value 6.
    case channelPinnedMessage = 6
    /// The upstream `USERJOIN` variant with raw value 7.
    case userJoin = 7
    /// The upstream `GUILDBOOST` variant with raw value 8.
    case guildBoost = 8
    /// The upstream `GUILDBOOSTTIER1` variant with raw value 9.
    case guildBoostTier1 = 9
    /// The upstream `GUILDBOOSTTIER2` variant with raw value 10.
    case guildBoostTier2 = 10
    /// The upstream `GUILDBOOSTTIER3` variant with raw value 11.
    case guildBoostTier3 = 11
    /// The upstream `CHANNELFOLLOWADD` variant with raw value 12.
    case channelFollowAdd = 12
    /// The upstream `GUILDDISCOVERYDISQUALIFIED` variant with raw value 14.
    case guildDiscoveryDisqualified = 14
    /// The upstream `GUILDDISCOVERYREQUALIFIED` variant with raw value 15.
    case guildDiscoveryRequalified = 15
    /// The upstream `GUILDDISCOVERYGRACEPERIODINITIALWARNING` variant with raw value 16.
    case guildDiscoveryGracePeriodInitialWarning = 16
    /// The upstream `GUILDDISCOVERYGRACEPERIODFINALWARNING` variant with raw value 17.
    case guildDiscoveryGracePeriodFinalWarning = 17
    /// The upstream `THREADCREATED` variant with raw value 18.
    case threadCreated = 18
    /// The upstream `REPLY` variant with raw value 19.
    case reply = 19
    /// The upstream `CHATINPUTCOMMAND` variant with raw value 20.
    case chatInputCommand = 20
    /// The upstream `THREADSTARTERMESSAGE` variant with raw value 21.
    case threadStarterMessage = 21
    /// The upstream `GUILDINVITEREMINDER` variant with raw value 22.
    case guildInviteReminder = 22
    /// The upstream `CONTEXTMENUCOMMAND` variant with raw value 23.
    case contextMenuCommand = 23
    /// The upstream `AUTOMODERATIONACTION` variant with raw value 24.
    case autoModerationAction = 24
    /// The upstream `ROLESUBSCRIPTIONPURCHASE` variant with raw value 25.
    case roleSubscriptionPurchase = 25
    /// The upstream `INTERACTIONPREMIUMUPSELL` variant with raw value 26.
    case interactionPremiumUpsell = 26
    /// The upstream `STAGESTART` variant with raw value 27.
    case stageStart = 27
    /// The upstream `STAGEEND` variant with raw value 28.
    case stageEnd = 28
    /// The upstream `STAGESPEAKER` variant with raw value 29.
    case stageSpeaker = 29
    /// The upstream `STAGETOPIC` variant with raw value 31.
    case stageTopic = 31
    /// The upstream `GUILDAPPLICATIONPREMIUMSUBSCRIPTION` variant with raw value 32.
    case guildApplicationPremiumSubscription = 32
    /// The upstream `GUILDINCIDENTALERTMODEENABLED` variant with raw value 36.
    case guildIncidentAlertModeEnabled = 36
    /// The upstream `GUILDINCIDENTALERTMODEDISABLED` variant with raw value 37.
    case guildIncidentAlertModeDisabled = 37
    /// The upstream `GUILDINCIDENTREPORTRAID` variant with raw value 38.
    case guildIncidentReportRaid = 38
    /// The upstream `GUILDINCIDENTREPORTFALSEALARM` variant with raw value 39.
    case guildIncidentReportFalseAlarm = 39
    /// The upstream `PURCHASENOTIFICATION` variant with raw value 44.
    case purchaseNotification = 44
    /// The upstream `POLLRESULT` variant with raw value 46.
    case pollResult = 46
}

/// Documented API v10 MessageActivityType values; RawValue preserves future values without claiming support.
public enum MessageActivityType: Int, Sendable {
    /// The upstream `JOIN` variant with raw value 1.
    case join = 1
    /// The upstream `SPECTATE` variant with raw value 2.
    case spectate = 2
    /// The upstream `LISTEN` variant with raw value 3.
    case listen = 3
    /// The upstream `JOINREQUEST` variant with raw value 5.
    case joinRequest = 5
    /// The upstream `STREAMREQUEST` variant with raw value 6.
    case streamRequest = 6
}

/// Documented API v10 MessageReferenceType values; RawValue preserves future values without claiming support.
public enum MessageReferenceType: Int, Sendable {
    /// The upstream `DEFAULT` variant with raw value 0.
    case `default` = 0
    /// The upstream `FORWARD` variant with raw value 1.
    case forward = 1
}

/// Documented API v10 MessageStickerFormatType values; RawValue preserves future values without claiming support.
public enum MessageStickerFormatType: Int, Sendable {
    /// The upstream `PNG` variant with raw value 1.
    case png = 1
    /// The upstream `APNG` variant with raw value 2.
    case apng = 2
    /// The upstream `LOTTIE` variant with raw value 3.
    case lottie = 3
    /// The upstream `GIF` variant with raw value 4.
    case gif = 4
}

/// Documented API v10 MessageBaseTheme values; RawValue preserves future values without claiming support.
public enum MessageBaseTheme: Int, Sendable {
    /// The upstream `UNSET` variant with raw value 0.
    case unset = 0
    /// The upstream `DARK` variant with raw value 1.
    case dark = 1
    /// The upstream `LIGHT` variant with raw value 2.
    case light = 2
    /// The upstream `DARKER` variant with raw value 3.
    case darker = 3
    /// The upstream `MIDNIGHT` variant with raw value 4.
    case midnight = 4
}

/// Documented API v10 MessageEmbedType values; RawValue preserves future values without claiming support.
public enum MessageEmbedType: String, Sendable {
    /// The upstream `RICH` variant with raw value "rich".
    case rich = "rich"
    /// The upstream `IMAGE` variant with raw value "image".
    case image = "image"
    /// The upstream `VIDEO` variant with raw value "video".
    case video = "video"
    /// The upstream `GIFV` variant with raw value "gifv".
    case gifv = "gifv"
    /// The upstream `ARTICLE` variant with raw value "article".
    case article = "article"
    /// The upstream `LINK` variant with raw value "link".
    case link = "link"
    /// The upstream `POLL_RESULT` variant with raw value "poll_result".
    case poll_result = "poll_result"
    /// The upstream `COMPONENTS` variant with raw value "components".
    case components = "components"
}

/// A message-specific user projection that accepts webhook authors without assuming a real Discord user. Missing discriminator/global_name remain absent; known user fields and original nested data survive.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageAuthor: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: UserID
    /// Required nonnull `username` wire field; original values and unknown sibling fields remain in rawFields.
    public let username: String
    /// Required nullable `avatar` wire field; original values and unknown sibling fields remain in rawFields.
    public let avatar: Nullable<String>
    /// Optional nonnull `discriminator` wire field; original values and unknown sibling fields remain in rawFields.
    public let discriminator: Field<String>
    /// Optional nullable `global_name` wire field; original values and unknown sibling fields remain in rawFields.
    public let globalName: Field<String>
    /// Optional nonnull `bot` wire field; original values and unknown sibling fields remain in rawFields.
    public let bot: Field<Bool>
    /// Optional nonnull `system` wire field; original values and unknown sibling fields remain in rawFields.
    public let system: Field<Bool>
    /// Optional nonnull `mfa_enabled` wire field; original values and unknown sibling fields remain in rawFields.
    public let mfaEnabled: Field<Bool>
    /// Optional nullable `banner` wire field; original values and unknown sibling fields remain in rawFields.
    public let banner: Field<String>
    /// Optional nullable `accent_color` wire field; original values and unknown sibling fields remain in rawFields.
    public let accentColor: Field<Int>
    /// Optional nonnull `locale` wire field; original values and unknown sibling fields remain in rawFields.
    public let locale: Field<String>
    /// Optional nonnull `verified` wire field; original values and unknown sibling fields remain in rawFields.
    public let verified: Field<Bool>
    /// Optional nullable `email` wire field; original values and unknown sibling fields remain in rawFields.
    public let email: Field<String>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `public_flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let publicFlags: Field<UInt64>
    /// Optional nonnull `premium_type` wire field; original values and unknown sibling fields remain in rawFields.
    public let premiumType: Field<RawValue<PremiumType>>
    /// Optional nullable `avatar_decoration_data` wire field; original values and unknown sibling fields remain in rawFields.
    public let avatarDecorationData: Field<MessageRelatedResource>
    /// Optional nullable `collectibles` wire field; original values and unknown sibling fields remain in rawFields.
    public let collectibles: Field<MessageRelatedResource>
    /// Optional nullable `primary_guild` wire field; original values and unknown sibling fields remain in rawFields.
    public let primaryGuild: Field<MessageRelatedResource>
    /// Optional nonnull `member` wire field; original values and unknown sibling fields remain in rawFields.
    public let member: Field<MessageRelatedResource>
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
        id = try object.required("id", UserID.self)
        username = try object.required("username", String.self)
        avatar = try object.required("avatar", Nullable<String>.self)
        discriminator = try object.field("discriminator", String.self)
        globalName = try object.field("global_name", String.self, nullable: true)
        bot = try object.field("bot", Bool.self)
        system = try object.field("system", Bool.self)
        mfaEnabled = try object.field("mfa_enabled", Bool.self)
        banner = try object.field("banner", String.self, nullable: true)
        accentColor = try object.field("accent_color", Int.self, nullable: true)
        locale = try object.field("locale", String.self)
        verified = try object.field("verified", Bool.self)
        email = try object.field("email", String.self, nullable: true)
        flags = try object.field("flags", UInt64.self)
        publicFlags = try object.field("public_flags", UInt64.self)
        premiumType = try object.field("premium_type", RawValue<PremiumType>.self)
        avatarDecorationData = try object.messageField("avatar_decoration_data", MessageRelatedResource.self, nullable: true)
        collectibles = try object.messageField("collectibles", MessageRelatedResource.self, nullable: true)
        primaryGuild = try object.messageField("primary_guild", MessageRelatedResource.self, nullable: true)
        member = try object.messageField("member", MessageRelatedResource.self)
        rawFields = object.resource.fields
    }
}

/// An explicit partial projection of a related Application, Channel, Sticker, Member or installation resource owned by another catalog batch. Every field remains exact in rawFields; this wrapper establishes no complete cross-family schema parity.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageRelatedResource: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: Field<String>
    /// Optional nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: Field<String>
    /// Optional nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: Field<Int>
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
        id = try object.field("id", String.self)
        name = try object.field("name", String.self)
        type = try object.field("type", Int.self)
        rawFields = object.resource.fields
    }
}

/// A complete message attachment response including signed asset destinations, Clips and voice media. URLs are retained as strings and are never fetched or authorized by decoding.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageAttachment: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: AttachmentID
    /// Required nonnull `filename` wire field; original values and unknown sibling fields remain in rawFields.
    public let filename: String
    /// Optional nonnull `title` wire field; original values and unknown sibling fields remain in rawFields.
    public let title: Field<String>
    /// Optional nonnull `description` wire field; original values and unknown sibling fields remain in rawFields.
    public let attachmentDescription: Field<String>
    /// Optional nonnull `content_type` wire field; original values and unknown sibling fields remain in rawFields.
    public let contentType: Field<String>
    /// Required nonnull `size` wire field; original values and unknown sibling fields remain in rawFields.
    public let size: Int
    /// Required nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: String
    /// Required nonnull `proxy_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let proxyURL: String
    /// Optional nullable `height` wire field; original values and unknown sibling fields remain in rawFields.
    public let height: Field<Int>
    /// Optional nullable `width` wire field; original values and unknown sibling fields remain in rawFields.
    public let width: Field<Int>
    /// Optional nonnull `placeholder` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholder: Field<String>
    /// Optional nonnull `placeholder_version` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholderVersion: Field<Int>
    /// Optional nonnull `ephemeral` wire field; original values and unknown sibling fields remain in rawFields.
    public let ephemeral: Field<Bool>
    /// Optional nonnull `duration_secs` wire field; original values and unknown sibling fields remain in rawFields.
    public let durationSeconds: Field<Double>
    /// Optional nonnull `waveform` wire field; original values and unknown sibling fields remain in rawFields.
    public let waveform: Field<String>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `clip_participants` wire field; original values and unknown sibling fields remain in rawFields.
    public let clipParticipants: Field<[MessageAuthor]>
    /// Optional nonnull `clip_created_at` wire field; original values and unknown sibling fields remain in rawFields.
    public let clipCreatedAt: Field<DiscordTimestamp>
    /// Optional nullable `application` wire field; original values and unknown sibling fields remain in rawFields.
    public let application: Field<MessageRelatedResource>
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
        id = try object.required("id", AttachmentID.self)
        filename = try object.required("filename", String.self)
        title = try object.field("title", String.self)
        attachmentDescription = try object.field("description", String.self)
        contentType = try object.field("content_type", String.self)
        size = try object.required("size", Int.self)
        url = try object.required("url", String.self)
        proxyURL = try object.required("proxy_url", String.self)
        height = try object.field("height", Int.self, nullable: true)
        width = try object.field("width", Int.self, nullable: true)
        placeholder = try object.field("placeholder", String.self)
        placeholderVersion = try object.field("placeholder_version", Int.self)
        ephemeral = try object.field("ephemeral", Bool.self)
        durationSeconds = try object.messageNumber("duration_secs")
        waveform = try object.field("waveform", String.self)
        flags = try object.field("flags", UInt64.self)
        clipParticipants = try object.messageArray("clip_participants", MessageAuthor.self)
        clipCreatedAt = try object.field("clip_created_at", DiscordTimestamp.self)
        application = try object.messageField("application", MessageRelatedResource.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Embed footer text and optional icon destinations; decoding does not fetch URLs.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedFooter: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `text` wire field; original values and unknown sibling fields remain in rawFields.
    public let text: String
    /// Optional nonnull `icon_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let iconURL: Field<String>
    /// Optional nonnull `proxy_icon_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let proxyIconURL: Field<String>
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
        text = try object.required("text", String.self)
        iconURL = try object.field("icon_url", String.self)
        proxyIconURL = try object.field("proxy_icon_url", String.self)
        rawFields = object.resource.fields
    }
}

/// Embed image including proxy/placeholder/accessibility and future media flags.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedImage: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: String
    /// Optional nonnull `proxy_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let proxyURL: Field<String>
    /// Optional nonnull `height` wire field; original values and unknown sibling fields remain in rawFields.
    public let height: Field<Int>
    /// Optional nonnull `width` wire field; original values and unknown sibling fields remain in rawFields.
    public let width: Field<Int>
    /// Optional nonnull `content_type` wire field; original values and unknown sibling fields remain in rawFields.
    public let contentType: Field<String>
    /// Optional nonnull `placeholder` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholder: Field<String>
    /// Optional nonnull `placeholder_version` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholderVersion: Field<Int>
    /// Optional nonnull `description` wire field; original values and unknown sibling fields remain in rawFields.
    public let mediaDescription: Field<String>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
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
        url = try object.required("url", String.self)
        proxyURL = try object.field("proxy_url", String.self)
        height = try object.field("height", Int.self)
        width = try object.field("width", Int.self)
        contentType = try object.field("content_type", String.self)
        placeholder = try object.field("placeholder", String.self)
        placeholderVersion = try object.field("placeholder_version", Int.self)
        mediaDescription = try object.field("description", String.self)
        flags = try object.field("flags", UInt64.self)
        rawFields = object.resource.fields
    }
}

/// Embed video media whose source URL may be omitted by Discord.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedVideo: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: Field<String>
    /// Optional nonnull `proxy_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let proxyURL: Field<String>
    /// Optional nonnull `height` wire field; original values and unknown sibling fields remain in rawFields.
    public let height: Field<Int>
    /// Optional nonnull `width` wire field; original values and unknown sibling fields remain in rawFields.
    public let width: Field<Int>
    /// Optional nonnull `content_type` wire field; original values and unknown sibling fields remain in rawFields.
    public let contentType: Field<String>
    /// Optional nonnull `placeholder` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholder: Field<String>
    /// Optional nonnull `placeholder_version` wire field; original values and unknown sibling fields remain in rawFields.
    public let placeholderVersion: Field<Int>
    /// Optional nonnull `description` wire field; original values and unknown sibling fields remain in rawFields.
    public let mediaDescription: Field<String>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
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
        url = try object.field("url", String.self)
        proxyURL = try object.field("proxy_url", String.self)
        height = try object.field("height", Int.self)
        width = try object.field("width", Int.self)
        contentType = try object.field("content_type", String.self)
        placeholder = try object.field("placeholder", String.self)
        placeholderVersion = try object.field("placeholder_version", Int.self)
        mediaDescription = try object.field("description", String.self)
        flags = try object.field("flags", UInt64.self)
        rawFields = object.resource.fields
    }
}

/// Optional provider identity and destination from an embed.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedProvider: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: Field<String>
    /// Optional nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: Field<String>
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
        name = try object.field("name", String.self)
        url = try object.field("url", String.self)
        rawFields = object.resource.fields
    }
}

/// Embed author identity, destination and original/proxy icon destinations.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedAuthor: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: String
    /// Optional nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: Field<String>
    /// Optional nonnull `icon_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let iconURL: Field<String>
    /// Optional nonnull `proxy_icon_url` wire field; original values and unknown sibling fields remain in rawFields.
    public let proxyIconURL: Field<String>
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
        name = try object.required("name", String.self)
        url = try object.field("url", String.self)
        iconURL = try object.field("icon_url", String.self)
        proxyIconURL = try object.field("proxy_icon_url", String.self)
        rawFields = object.resource.fields
    }
}

/// An embed text field; response decoding does not impose request creation character limits.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbedField: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: String
    /// Required nonnull `value` wire field; original values and unknown sibling fields remain in rawFields.
    public let value: String
    /// Optional nonnull `inline` wire field; original values and unknown sibling fields remain in rawFields.
    public let inline: Field<Bool>
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
        name = try object.required("name", String.self)
        self.value = try object.required("value", String.self)
        inline = try object.field("inline", Bool.self)
        rawFields = object.resource.fields
    }
}

/// A complete message embed projection including component-based link previews. Unknown types/flags remain available; outbound rich-embed restrictions belong to MessageCreate/MessageEdit.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageEmbed: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `title` wire field; original values and unknown sibling fields remain in rawFields.
    public let title: Field<String>
    /// Optional nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: Field<RawValue<MessageEmbedType>>
    /// Optional nonnull `description` wire field; original values and unknown sibling fields remain in rawFields.
    public let embedDescription: Field<String>
    /// Optional nonnull `url` wire field; original values and unknown sibling fields remain in rawFields.
    public let url: Field<String>
    /// Optional nonnull `timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let timestamp: Field<DiscordTimestamp>
    /// Optional nonnull `color` wire field; original values and unknown sibling fields remain in rawFields.
    public let color: Field<UInt64>
    /// Optional nonnull `footer` wire field; original values and unknown sibling fields remain in rawFields.
    public let footer: Field<MessageEmbedFooter>
    /// Optional nonnull `image` wire field; original values and unknown sibling fields remain in rawFields.
    public let image: Field<MessageEmbedImage>
    /// Optional nonnull `thumbnail` wire field; original values and unknown sibling fields remain in rawFields.
    public let thumbnail: Field<MessageEmbedImage>
    /// Optional nonnull `video` wire field; original values and unknown sibling fields remain in rawFields.
    public let video: Field<MessageEmbedVideo>
    /// Optional nonnull `provider` wire field; original values and unknown sibling fields remain in rawFields.
    public let provider: Field<MessageEmbedProvider>
    /// Optional nonnull `author` wire field; original values and unknown sibling fields remain in rawFields.
    public let author: Field<MessageEmbedAuthor>
    /// Optional nonnull `fields` wire field; original values and unknown sibling fields remain in rawFields.
    public let fields: Field<[MessageEmbedField]>
    /// Optional nonnull `components` wire field; original values and unknown sibling fields remain in rawFields.
    public let components: Field<[MessageComponent]>
    /// Optional nonnull `flags` wire field; original values and unknown sibling fields remain in rawFields.
    public let flags: Field<UInt64>
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
        title = try object.field("title", String.self)
        type = try object.field("type", RawValue<MessageEmbedType>.self)
        embedDescription = try object.field("description", String.self)
        url = try object.field("url", String.self)
        timestamp = try object.field("timestamp", DiscordTimestamp.self)
        color = try object.field("color", UInt64.self)
        footer = try object.messageField("footer", MessageEmbedFooter.self)
        image = try object.messageField("image", MessageEmbedImage.self)
        thumbnail = try object.messageField("thumbnail", MessageEmbedImage.self)
        video = try object.messageField("video", MessageEmbedVideo.self)
        provider = try object.messageField("provider", MessageEmbedProvider.self)
        author = try object.messageField("author", MessageEmbedAuthor.self)
        fields = try object.messageArray("fields", MessageEmbedField.self)
        components = try object.messageArray("components", MessageComponent.self)
        flags = try object.field("flags", UInt64.self)
        rawFields = object.resource.fields
    }
}

/// Rich Presence activity metadata; unknown integral activity variants are preserved.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageActivity: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: RawValue<MessageActivityType>
    /// Optional nonnull `party_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let partyID: Field<String>
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
        type = try object.required("type", RawValue<MessageActivityType>.self)
        partyID = try object.field("party_id", String.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly included public crosspost channel mention; absence elsewhere is not proof that content mentions no channel.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageChannelMention: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: ChannelID
    /// Required nonnull `guild_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: Int
    /// Required nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: String
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
        id = try object.required("id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        type = try object.required("type", Int.self)
        name = try object.required("name", String.self)
        rawFields = object.resource.fields
    }
}

/// Counts of normal and burst reactions; no equality between a potentially changing total and its components is inferred.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageReactionCounts: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `burst` wire field; original values and unknown sibling fields remain in rawFields.
    public let burst: Int
    /// Required nonnull `normal` wire field; original values and unknown sibling fields remain in rawFields.
    public let normal: Int
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
        burst = try object.required("burst", Int.self)
        normal = try object.required("normal", Int.self)
        rawFields = object.resource.fields
    }
}

/// A complete reaction response, retaining Unicode/custom emoji, burst counts and color strings.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageReaction: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `count` wire field; original values and unknown sibling fields remain in rawFields.
    public let count: Int
    /// Required nonnull `count_details` wire field; original values and unknown sibling fields remain in rawFields.
    public let countDetails: MessageReactionCounts
    /// Required nonnull `me` wire field; original values and unknown sibling fields remain in rawFields.
    public let me: Bool
    /// Required nonnull `me_burst` wire field; original values and unknown sibling fields remain in rawFields.
    public let meBurst: Bool
    /// Required nonnull `emoji` wire field; original values and unknown sibling fields remain in rawFields.
    public let emoji: PartialEmoji
    /// Required nonnull `burst_colors` wire field; original values and unknown sibling fields remain in rawFields.
    public let burstColors: [String]
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
        count = try object.required("count", Int.self)
        countDetails = try object.messageModel("count_details", MessageReactionCounts.self)
        me = try object.required("me", Bool.self)
        meBurst = try object.required("me_burst", Bool.self)
        emoji = try object.messageModel("emoji", PartialEmoji.self)
        burstColors = try object.required("burst_colors", [String].self)
        rawFields = object.resource.fields
    }
}

/// A reply or point-in-time forward reference. Omitted type retains Discord default semantics without being synthesized into a present field.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageReference: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: Field<RawValue<MessageReferenceType>>
    /// Optional nonnull `message_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let messageID: Field<MessageID>
    /// Optional nonnull `channel_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let channelID: Field<ChannelID>
    /// Optional nonnull `guild_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `fail_if_not_exists` wire field; original values and unknown sibling fields remain in rawFields.
    public let failIfNotExists: Field<Bool>
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
        type = try object.field("type", RawValue<MessageReferenceType>.self)
        messageID = try object.field("message_id", MessageID.self)
        channelID = try object.field("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        failIfNotExists = try object.field("fail_if_not_exists", Bool.self)
        rawFields = object.resource.fields
    }
}

/// Sticker identity, name and forward-compatible format carried by messages.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageStickerItem: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: StickerID
    /// Required nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: String
    /// Required nonnull `format_type` wire field; original values and unknown sibling fields remain in rawFields.
    public let formatType: RawValue<MessageStickerFormatType>
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
        id = try object.required("id", StickerID.self)
        name = try object.required("name", String.self)
        formatType = try object.required("format_type", RawValue<MessageStickerFormatType>.self)
        rawFields = object.resource.fields
    }
}

/// Purchase notification metadata; this snapshot establishes no current subscription entitlement.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageRoleSubscriptionData: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `role_subscription_listing_id` wire field; original values and unknown sibling fields remain in rawFields.
    public let roleSubscriptionListingID: RoleSubscriptionListingID
    /// Required nonnull `tier_name` wire field; original values and unknown sibling fields remain in rawFields.
    public let tierName: String
    /// Required nonnull `total_months_subscribed` wire field; original values and unknown sibling fields remain in rawFields.
    public let totalMonthsSubscribed: Int
    /// Required nonnull `is_renewal` wire field; original values and unknown sibling fields remain in rawFields.
    public let isRenewal: Bool
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
        roleSubscriptionListingID = try object.required("role_subscription_listing_id", RoleSubscriptionListingID.self)
        tierName = try object.required("tier_name", String.self)
        totalMonthsSubscribed = try object.required("total_months_subscribed", Int.self)
        isRenewal = try object.required("is_renewal", Bool.self)
        rawFields = object.resource.fields
    }
}

/// Private-channel call metadata with exact participants and nullable optional ending instant.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageCall: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `participants` wire field; original values and unknown sibling fields remain in rawFields.
    public let participants: [UserID]
    /// Optional nullable `ended_timestamp` wire field; original values and unknown sibling fields remain in rawFields.
    public let endedTimestamp: Field<DiscordTimestamp>
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
        participants = try object.required("participants", [UserID].self)
        endedTimestamp = try object.field("ended_timestamp", DiscordTimestamp.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Shared client theme metadata; unknown integral base themes and all original color spellings survive.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageSharedClientTheme: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `colors` wire field; original values and unknown sibling fields remain in rawFields.
    public let colors: [String]
    /// Required nonnull `gradient_angle` wire field; original values and unknown sibling fields remain in rawFields.
    public let gradientAngle: Int
    /// Required nonnull `base_mix` wire field; original values and unknown sibling fields remain in rawFields.
    public let baseMix: Int
    /// Optional nullable `base_theme` wire field; original values and unknown sibling fields remain in rawFields.
    public let baseTheme: Field<RawValue<MessageBaseTheme>>
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
        colors = try object.required("colors", [String].self)
        gradientAngle = try object.required("gradient_angle", Int.self)
        baseMix = try object.required("base_mix", Int.self)
        baseTheme = try object.field("base_theme", RawValue<MessageBaseTheme>.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Deprecated message interaction metadata retained for compatibility. New payloads prefer interaction_metadata.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessageLegacyInteraction: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire field; original values and unknown sibling fields remain in rawFields.
    public let id: MessageInteractionID
    /// Required nonnull `type` wire field; original values and unknown sibling fields remain in rawFields.
    public let type: Int
    /// Required nonnull `name` wire field; original values and unknown sibling fields remain in rawFields.
    public let name: String
    /// Required nonnull `user` wire field; original values and unknown sibling fields remain in rawFields.
    public let user: MessageAuthor
    /// Optional nonnull `member` wire field; original values and unknown sibling fields remain in rawFields.
    public let member: Field<MessageRelatedResource>
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
        id = try object.required("id", MessageInteractionID.self)
        type = try object.required("type", Int.self)
        name = try object.required("name", String.self)
        user = try object.messageModel("user", MessageAuthor.self)
        member = try object.messageField("member", MessageRelatedResource.self)
        rawFields = object.resource.fields
    }
}

/// A pinned message and the exact instant when the pin was created.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessagePin: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `pinned_at` wire field; original values and unknown sibling fields remain in rawFields.
    public let pinnedAt: DiscordTimestamp
    /// Required nonnull `message` wire field; original values and unknown sibling fields remain in rawFields.
    public let message: Message
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
        pinnedAt = try object.required("pinned_at", DiscordTimestamp.self)
        message = try object.messageModel("message", Message.self)
        rawFields = object.resource.fields
    }
}

/// Current paginated pin response; hasMore is authoritative and independent of item count.
/// API v10; reviewed against the official Message resource on 2026-10-16.
public struct MessagePins: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `items` wire field; original values and unknown sibling fields remain in rawFields.
    public let items: [MessagePin]
    /// Required nonnull `has_more` wire field; original values and unknown sibling fields remain in rawFields.
    public let hasMore: Bool
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
        items = try object.messageModels("items", MessagePin.self)
        hasMore = try object.required("has_more", Bool.self)
        rawFields = object.resource.fields
    }
}

extension MessageReference {
    /// Constructs reply or forward reference metadata without performing a request.
    /// - Parameters:
    ///   - type: Reference semantics, defaulting to a standard reply. Forward requests require message/channel IDs.
    ///   - messageID: Optional source message; operation-level builders validate required combinations.
    ///   - channelID: Optional source channel, required when forwarding across the source reference.
    ///   - guildID: Optional source guild; omission preserves Discord's inferred context.
    ///   - failIfNotExists: Optional reply failure behavior; omission retains Discord's true default.
    /// - Throws: Default JSON bound errors; request-specific compatibility remains in MessageCreate.
    public init(type: MessageReferenceType = .default, messageID: MessageID? = nil,
                channelID: ChannelID? = nil, guildID: GuildID? = nil, failIfNotExists: Bool? = nil) throws {
        var fields: [String: JSONValue] = ["type": .number(try JSONNumber(rawValue: String(type.rawValue)))]
        if let messageID { fields["message_id"] = .string(messageID.description) }
        if let channelID { fields["channel_id"] = .string(channelID.description) }
        if let guildID { fields["guild_id"] = .string(guildID.description) }
        if let failIfNotExists { fields["fail_if_not_exists"] = .bool(failIfNotExists) }
        let value = JSONValue.object(fields)
        _ = try value.serialized()
        try self.init(value: value, limits: .default)
    }
}

extension MessageEmbed {
    /// Constructs the rich embed request subset; MessageCreate/MessageEdit apply text and compatibility limits.
    /// - Parameters:
    ///   - title: Optional title, with no local response-normalization or truncation.
    ///   - description: Optional main text; aggregate Discord request bounds are validated by the request model.
    ///   - url: Optional destination string; no fetch or URL authorization occurs.
    ///   - timestamp: Optional valid ISO-8601 string in DiscordTimestamp's documented precision profile.
    ///   - color: Optional integer RGB color; request models require at most 0xFFFFFF.
    ///   - footer: Optional typed footer; response-only nested keys remain visible to request validation.
    ///   - image: Optional typed image whose URL can use an attachment reference.
    ///   - thumbnail: Optional typed thumbnail whose URL can use an attachment reference.
    ///   - author: Optional typed embed author.
    ///   - fields: Optional ordered field list; omission differs from an empty list.
    /// - Throws: JSON bounds, timestamp-schema or safe invalid-response errors. This initializer performs no I/O.
    public init(title: String? = nil, description: String? = nil, url: String? = nil,
                timestamp: String? = nil, color: UInt64? = nil, footer: MessageEmbedFooter? = nil,
                image: MessageEmbedImage? = nil, thumbnail: MessageEmbedImage? = nil,
                author: MessageEmbedAuthor? = nil, fields: [MessageEmbedField]? = nil) throws {
        var values: [String: JSONValue] = [:]
        if let title { values["title"] = .string(title) }
        if let description { values["description"] = .string(description) }
        if let url { values["url"] = .string(url) }
        if let timestamp { values["timestamp"] = .string(timestamp) }
        if let color { values["color"] = .number(try JSONNumber(rawValue: String(color))) }
        if let footer { values["footer"] = footer.jsonValue() }
        if let image { values["image"] = image.jsonValue() }
        if let thumbnail { values["thumbnail"] = thumbnail.jsonValue() }
        if let author { values["author"] = author.jsonValue() }
        if let fields { values["fields"] = .array(fields.map { $0.jsonValue() }) }
        let value = JSONValue.object(values)
        _ = try value.serialized()
        try self.init(value: value, limits: .default)
    }

    /// Counts Unicode scalars across all text fields subject to Discord's aggregate embed limit.
    /// The value is synchronous and does not apply limits or truncate content; request builders validate it.
    public var contentCharacterCount: Int {
        var total = 0
        if case .value(let value) = title { total += value.unicodeScalars.count }
        if case .value(let value) = embedDescription { total += value.unicodeScalars.count }
        if case .value(let value) = footer { total += value.text.unicodeScalars.count }
        if case .value(let value) = author { total += value.name.unicodeScalars.count }
        if case .value(let values) = fields {
            total += values.reduce(0) { $0 + $1.name.unicodeScalars.count + $1.value.unicodeScalars.count }
        }
        return total
    }
}
/// Named API v10 message response bits, including flags that cannot be set by outgoing requests.
///
/// Unknown bits survive `init(rawValue:)`, unions and membership checks. Response models retain
/// their exact `UInt64` wire property; wrap a present value with `MessageFlags(rawValue: raw)`.
/// These flags describe a snapshot and confer no permissions. Use the narrower
/// `MessageCreateFlags` and `MessageEditFlags` for operation-specific request validation.
/// The irreversible Components V2 flag's send/edit compatibility belongs to those request models.
/// Verified 2026-10-16 against https://docs.discord.com/developers/resources/message#message-object-message-flags.
///
/// ```swift
/// if case .value(let raw) = message.flags {
///     let flags = MessageFlags(rawValue: raw)
///     let isEphemeral = flags.contains(.ephemeral)
/// }
/// ```
public struct MessageFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned server bitfield, including every unrecognized bit.
    public let rawValue: UInt64

    /// Retains a complete response bitfield without rejecting or clearing future bits.
    /// - Parameter rawValue: Any unsigned 64-bit bitfield, including zero and unknown combinations.
    /// This synchronous value construction performs no I/O, allocation of owned resources,
    /// permission inference, or request-field validation. Individual response bits may be combined freely.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The message was published to subscribed channels through Channel Following.
    public static let crossposted = Self(rawValue: 1 << 0)
    /// The message originated in another channel through Channel Following.
    public static let isCrosspost = Self(rawValue: 1 << 1)
    /// Embeds are suppressed when Discord serializes this message.
    public static let suppressEmbeds = Self(rawValue: 1 << 2)
    /// The source of a crossposted message was deleted.
    public static let sourceMessageDeleted = Self(rawValue: 1 << 3)
    /// The message originated in Discord's urgent-message system.
    public static let urgent = Self(rawValue: 1 << 4)
    /// The message has an associated thread whose identifier matches the message identifier.
    public static let hasThread = Self(rawValue: 1 << 5)
    /// The interaction message is visible only to the invoking user.
    public static let ephemeral = Self(rawValue: 1 << 6)
    /// The interaction response represents the bot's pending or thinking state.
    public static let loading = Self(rawValue: 1 << 7)
    /// Some mentioned roles could not be added or mentioned in the thread.
    public static let failedToMentionSomeRolesInThread = Self(rawValue: 1 << 8)
    /// The message suppresses push and desktop notifications.
    public static let suppressNotifications = Self(rawValue: 1 << 12)
    /// The message contains voice-message audio and cannot be edited.
    public static let isVoiceMessage = Self(rawValue: 1 << 13)
    /// The message contains a point-in-time forwarded snapshot.
    public static let hasSnapshot = Self(rawValue: 1 << 14)
    /// The message uses Components V2; Discord does not permit this bit to be removed after sending.
    public static let isComponentsV2 = Self(rawValue: 1 << 15)
}
/// Documented embed response flags with unknown raw bits retained unchanged.
/// Wrap `MessageEmbed.flags` with this value for named membership checks; it does not
/// make a response-only flag valid in an outgoing rich-embed request.
public struct MessageEmbedFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned embed bitfield, including unrecognized future bits.
    public let rawValue: UInt64
    /// Retains any embed bitfield without I/O, mutation or permission inference.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown bits.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// The embed is a fallback representation of a reply to an activity card.
    public static let isContentInventoryEntry = Self(rawValue: 1 << 5)
}

/// Documented embed image/video response bits. Unknown bits remain available in rawValue.
/// Wrap a present `MessageEmbedImage.flags` or `MessageEmbedVideo.flags` value for named checks.
public struct MessageEmbedMediaFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned media bitfield, including future bits.
    public let rawValue: UInt64
    /// Retains an unsigned response bitfield synchronously without resources or side effects.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown bits.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// The embedded image is animated.
    public static let isAnimated = Self(rawValue: 1 << 5)
}

/// Documented message attachment response bits, including the deprecated mobile remix flag.
/// Wrap `MessageAttachment.flags` for named checks. Response flags do not grant media access,
/// preserve an expiring attachment, or authorize setting arbitrary outgoing attachment flags.
public struct MessageAttachmentFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned attachment bitfield, including all future bits.
    public let rawValue: UInt64
    /// Retains any attachment bitfield without I/O or normalization of future values.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown bits.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// The attachment is a captured Clip from a stream.
    public static let isClip = Self(rawValue: 1 << 0)
    /// The attachment is a media-channel thread thumbnail displayed in the grid instead of the message.
    public static let isThumbnail = Self(rawValue: 1 << 1)
    /// The attachment was edited by the deprecated mobile remix feature.
    @available(*, deprecated, message: "Discord deprecated the mobile remix feature; this response bit remains inspectable.")
    public static let isRemix = Self(rawValue: 1 << 2)
    /// The attachment is hidden behind spoiler blur until the viewer chooses to reveal it.
    public static let isSpoiler = Self(rawValue: 1 << 3)
    /// The attachment is an animated image.
    public static let isAnimated = Self(rawValue: 1 << 5)
}
