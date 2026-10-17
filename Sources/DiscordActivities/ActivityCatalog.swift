import DiscordCore
import Foundation

/// Sanitized synchronous catalog validation failures; supplied values never appear in diagnostics.
public enum ActivityCatalogError: Error, Sendable, Equatable {
    /// A required response field was missing, null when forbidden, or had an incompatible JSON type.
    case invalidPayload
    /// An outgoing argument violated the pinned public SDK schema or a local resource bound.
    case invalidArguments
    /// A user access token was empty, too long, contained whitespace, or used an HTTP authorization prefix.
    case invalidAccessToken
}

/// Commands actually exported by Discord's Embedded App SDK 2.5.0, plus subscription controls.
/// The pinned upstream revision is `14264eccbf9e68d5d58c1aadbc7579e003e0dce6`.
/// These commands use an Activity message bridge and do not establish a local RPC connection.
public enum ActivityCommand: String, Sendable, CaseIterable {
    case authorize = "AUTHORIZE"
    case captureLog = "CAPTURE_LOG"
    case encourageHardwareAcceleration = "ENCOURAGE_HW_ACCELERATION"
    case getChannel = "GET_CHANNEL"
    case getChannelPermissions = "GET_CHANNEL_PERMISSIONS"
    case getEntitlements = "GET_ENTITLEMENTS_EMBEDDED"
    case getPlatformBehaviors = "GET_PLATFORM_BEHAVIORS"
    case getSkus = "GET_SKUS_EMBEDDED"
    case openExternalLink = "OPEN_EXTERNAL_LINK"
    case openInviteDialog = "OPEN_INVITE_DIALOG"
    case setActivity = "SET_ACTIVITY"
    case setConfig = "SET_CONFIG"
    case setOrientationLockState = "SET_ORIENTATION_LOCK_STATE"
    case startPurchase = "START_PURCHASE"
    case userSettingsGetLocale = "USER_SETTINGS_GET_LOCALE"
    case authenticate = "AUTHENTICATE"
    case getActivityInstanceConnectedParticipants = "GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS"
    case getQuest = "GET_QUEST"
    case getQuestEnrollmentStatus = "GET_QUEST_ENROLLMENT_STATUS"
    case getRelationships = "GET_RELATIONSHIPS"
    case getUser = "GET_USER"
    case initiateImageUpload = "INITIATE_IMAGE_UPLOAD"
    case inviteUserEmbedded = "INVITE_USER_EMBEDDED"
    case openShareMomentDialog = "OPEN_SHARE_MOMENT_DIALOG"
    case questStartTimer = "QUEST_START_TIMER"
    case requestProxyTicketRefresh = "REQUEST_PROXY_TICKET_REFRESH"
    case shareInteraction = "SHARE_INTERACTION"
    case shareLink = "SHARE_LINK"
    case subscribe = "SUBSCRIBE"
    case unsubscribe = "UNSUBSCRIBE"

    /// All 28 callable exports; subscription controls are transport operations, and the old participant name is an alias.
    public static let exported: [Self] = allCases.filter { $0 != .subscribe && $0 != .unsubscribe }

    /// Required scopes explicitly stated in the pinned source; the host remains authoritative for all other restrictions.
    public var requiredScopes: Set<String> {
        switch self {
        case .setActivity: ["rpc.activities.write"]
        case .getChannel: ["guilds"]
        case .getChannelPermissions: ["guilds.members.read"]
        case .getRelationships: ["relationships.read"]
        case .userSettingsGetLocale: ["identify"]
        default: []
        }
    }
}

/// Exact Activity event name. Unknown future names remain observable and retain their spelling.
public struct ActivityEventName: RawRepresentable, Sendable, Hashable {
    /// Original host spelling, without coercion or case normalization.
    public let rawValue: String

    /// Retains an event name without performing I/O or assuming host support.
    /// - Parameter rawValue: Exact name; subscription admission separately rejects empty/control-containing names.
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ready = Self(rawValue: "READY")
    public static let error = Self(rawValue: "ERROR")
    public static let voiceStateUpdate = Self(rawValue: "VOICE_STATE_UPDATE")
    public static let speakingStart = Self(rawValue: "SPEAKING_START")
    public static let speakingStop = Self(rawValue: "SPEAKING_STOP")
    public static let activityLayoutModeUpdate = Self(rawValue: "ACTIVITY_LAYOUT_MODE_UPDATE")
    public static let orientationUpdate = Self(rawValue: "ORIENTATION_UPDATE")
    public static let currentUserUpdate = Self(rawValue: "CURRENT_USER_UPDATE")
    public static let currentGuildMemberUpdate = Self(rawValue: "CURRENT_GUILD_MEMBER_UPDATE")
    public static let entitlementCreate = Self(rawValue: "ENTITLEMENT_CREATE")
    public static let thermalStateUpdate = Self(rawValue: "THERMAL_STATE_UPDATE")
    public static let activityInstanceParticipantsUpdate = Self(rawValue: "ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE")
    public static let relationshipUpdate = Self(rawValue: "RELATIONSHIP_UPDATE")
    public static let activityJoin = Self(rawValue: "ACTIVITY_JOIN")
    public static let questEnrollmentStatusUpdate = Self(rawValue: "QUEST_ENROLLMENT_STATUS_UPDATE")

    /// Fourteen exported dispatch names. ERROR is a correlated command failure, rather than a subscribable dispatch.
    public static let exported: [Self] = [
        .ready, .voiceStateUpdate, .speakingStart, .speakingStop, .activityLayoutModeUpdate,
        .orientationUpdate, .currentUserUpdate, .currentGuildMemberUpdate, .entitlementCreate,
        .thermalStateUpdate, .activityInstanceParticipantsUpdate, .relationshipUpdate,
        .activityJoin, .questEnrollmentStatusUpdate
    ]
}

/// A host category in the SDK's support matrix. Web includes the Discord desktop web host.
public enum ActivityHostPlatform: String, Sendable, CaseIterable { case web, iOS, android }

/// Source-bounded host availability; unknown means a claim has not been established.
public enum ActivityHostAvailability: String, Sendable {
    /// The pinned official SDK source explicitly documents support on this host.
    case documentedSupported
    /// The export exists in source, but no per-host support claim has been verified here.
    case sourceOnly
    /// Official documentation explicitly excludes this host.
    case unsupported
}

extension ActivityCommand {
    /// Reports support from the official reference verified 2026-10-17, distinguishing source-only exports.
    /// - Parameter platform: Discord host category to inspect.
    /// - Returns: Documented support/exclusion, or source-only when absent from the reference. Host smoke testing is separate.
    public func availability(on platform: ActivityHostPlatform) -> ActivityHostAvailability {
        switch self {
        case .encourageHardwareAcceleration, .openShareMomentDialog, .setConfig, .startPurchase:
            platform == .web ? .documentedSupported : .unsupported
        case .setOrientationLockState:
            platform == .web ? .unsupported : .documentedSupported
        case .getQuest, .getQuestEnrollmentStatus, .getUser, .inviteUserEmbedded, .questStartTimer,
             .requestProxyTicketRefresh, .shareInteraction: .sourceOnly
        default: .documentedSupported
        }
    }
}

/// Explicit user OAuth access token; ordinary diagnostics and reflection conceal its contents.
/// This type cannot prove issuer or token class. Obtain its value through the caller's trusted OAuth exchange.
public struct ActivityUserAccessToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let value: String

    /// Wraps a raw user token without exchanging or storing it outside this value.
    /// - Parameter oauthAccessToken: Nonempty visible ASCII token, at most 16 KiB, without HTTP prefixes or whitespace.
    /// - Throws: `ActivityCatalogError.invalidAccessToken`; the supplied credential is never attached to errors.
    public init(oauthAccessToken: String) throws {
        guard !oauthAccessToken.isEmpty, oauthAccessToken.utf8.count <= 16_384,
              oauthAccessToken.utf8.allSatisfy({ (33...126).contains($0) }),
              !oauthAccessToken.lowercased().hasPrefix("bot "),
              !oauthAccessToken.lowercased().hasPrefix("bearer ")
        else { throw ActivityCatalogError.invalidAccessToken }
        value = oauthAccessToken
    }

    /// Redacts credential contents from interpolation and collection diagnostics.
    public var description: String { "ActivityUserAccessToken(redacted)" }
    /// Redacts debugger-oriented output.
    public var debugDescription: String { description }
    /// Prevents dump and reflection from expanding credential storage.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Immutable typed Activity command descriptor. Creation starts no I/O, tasks, authentication or retries.
/// Arguments are explicit for bridge execution; diagnostics redact all argument contents.
public struct ActivityRequest<Response: Sendable>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let command: ActivityCommand
    public let arguments: [String: JSONValue]
    public let event: ActivityEventName?
    private let decoder: @Sendable (JSONValue) throws -> Response

    /// Constructs a bounded descriptor with an explicit response decoder, including future-compatible fields.
    /// - Parameters:
    ///   - command: Exported command or subscription control.
    ///   - arguments: Whole argument object; serialized once to enforce resource bounds.
    ///   - event: Required for subscribe/unsubscribe; prohibited otherwise. READY/ERROR are not subscribable.
    ///   - limits: Whole-object byte/depth/node bounds, defaulting to 1 MiB/64/100,000.
    ///   - decode: Pure synchronous decoder of the response data subtree; retained for later execution.
    /// - Throws: `ActivityCatalogError.invalidArguments` for invalid event use, or JSON serialization bound failures.
    /// This explicit low-level initializer does not validate each command's argument schema; use `ActivityRequests` factories.
    public init(command: ActivityCommand, arguments: [String: JSONValue] = [:], event: ActivityEventName? = nil,
                limits: JSONLimits = .default, decode: @escaping @Sendable (JSONValue) throws -> Response) throws {
        _ = try JSONValue.object(arguments).serialized(limits: limits)
        if command == .subscribe || command == .unsubscribe {
            guard let event, event != .ready, event != .error, !event.rawValue.isEmpty,
                  event.rawValue.utf8.count <= 128,
                  !event.rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw ActivityCatalogError.invalidArguments }
        } else if event != nil { throw ActivityCatalogError.invalidArguments }
        self.command = command
        self.arguments = arguments
        self.event = event
        self.decoder = decode
    }

    /// Projects an already-bounded response data subtree, without reading a frame or doing I/O.
    /// - Parameter value: Response `data`, retaining exact unknown numeric spellings.
    /// - Returns: The request's typed response.
    /// - Throws: The retained decoder's error; catalog factories sanitize validation failures, while custom decoder errors are caller-owned. Existing trees must be bounded by the caller.
    public func decode(_ value: JSONValue) throws -> Response { try decoder(value) }

    /// Parses complete response-data bytes before invoking the typed decoder.
    /// - Parameters:
    ///   - data: One complete UTF-8 response data document, rather than an envelope.
    ///   - limits: Whole-document bounds; duplicate keys and malformed JSON are always rejected.
    /// - Returns: The projected response, preserving unknown fields and omission/null distinctions.
    /// - Throws: JSON syntax/limit errors or typed projection errors. No partial response escapes on failure.
    public func decode(data: Data, limits: JSONLimits = .default) throws -> Response {
        try decode(JSONValue.parse(data, limits: limits))
    }

    /// Redacts arguments, event filters, OAuth secrets and decoder captures from interpolation.
    public var description: String { "ActivityRequest(\(command.rawValue), redacted)" }
    /// Uses the same constant redaction for debugger output.
    public var debugDescription: String { description }
    /// Prevents reflective expansion of credentials and other request contents.
    public var customMirror: Mirror { Mirror(self, children: ["command": command.rawValue, "redacted": true]) }
}

extension ActivityCommand {
    /// Whether the public reference specifies this command's scope requirements, including an explicitly empty set.
    /// Source-only exports retain unknown requirements rather than claiming that no scopes are needed.
    public var scopesAreDocumented: Bool {
        switch self {
        case .getQuest, .getQuestEnrollmentStatus, .getUser, .inviteUserEmbedded, .questStartTimer,
             .requestProxyTicketRefresh, .shareInteraction: false
        default: true
        }
    }

    /// Whether the current change log requires accepting Social SDK terms before using this surface.
    /// The 2026-01-21 update removed the earlier additional Discord approval requirement for relationships.read.
    public var requiresSocialSDKTerms: Bool { self == .getRelationships }
}

extension ActivityEventName {
    /// Required scopes stated by the current reference. Inspect scopesAreDocumented before treating an empty set as known.
    public var requiredScopes: Set<String> {
        switch self {
        case .voiceStateUpdate, .speakingStart, .speakingStop: ["rpc.voice.read"]
        case .currentUserUpdate: ["identify"]
        case .currentGuildMemberUpdate: ["identify", "guilds.members.read"]
        case .relationshipUpdate: ["relationships.read"]
        default: []
        }
    }

    /// Whether this event has verified scope requirements in the public reference.
    public var scopesAreDocumented: Bool {
        Self.exported.contains(self) && self != .activityJoin && self != .questEnrollmentStatusUpdate
            && self != .entitlementCreate || self == .error
    }

    /// Whether the public reference still marks this event unavailable during Developer Preview.
    /// An exported schema is not evidence that the host emits an event.
    public var unavailableDuringDeveloperPreview: Bool { self == .entitlementCreate }

    /// Reports only explicit event-host support; the subscribe method's matrix does not imply event parity.
    /// - Parameter platform: Host category, retained for matrix API consistency.
    /// - Returns: Documented support for READY on all hosts; source-only for other events, including unknown future names.
    public func availability(on platform: ActivityHostPlatform) -> ActivityHostAvailability {
        self == .ready ? .documentedSupported : .sourceOnly
    }
}
