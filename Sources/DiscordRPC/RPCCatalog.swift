import DiscordCore
import Foundation

/// Sanitized local catalog failures; payload values and credentials are never included.
public enum RPCCatalogError: Error, Sendable, Equatable {
    /// A required field was absent or a modeled field had an incompatible type.
    case invalidPayload
    /// An outgoing field violates a documented range or request invariant.
    case invalidArguments
    /// Only a raw OAuth2 access token is accepted; bot credentials and header values are rejected.
    case invalidAccessToken
}

/// Every documented client command in RPC v1, verified against the official RPC reference 2026-10-17.
/// `DISPATCH` is a server envelope command and cannot be submitted through this catalog.
/// Reference: https://docs.discord.com/developers/topics/rpc#commands-and-events.
public enum RPCCommand: String, Sendable, CaseIterable {
    case authorize = "AUTHORIZE"
    case authenticate = "AUTHENTICATE"
    case getGuilds = "GET_GUILDS"
    case getGuild = "GET_GUILD"
    case getChannel = "GET_CHANNEL"
    case getChannels = "GET_CHANNELS"
    case setUserVoiceSettings = "SET_USER_VOICE_SETTINGS"
    case selectVoiceChannel = "SELECT_VOICE_CHANNEL"
    case getSelectedVoiceChannel = "GET_SELECTED_VOICE_CHANNEL"
    case selectTextChannel = "SELECT_TEXT_CHANNEL"
    case getVoiceSettings = "GET_VOICE_SETTINGS"
    case setVoiceSettings = "SET_VOICE_SETTINGS"
    case subscribe = "SUBSCRIBE"
    case unsubscribe = "UNSUBSCRIBE"
    case setCertifiedDevices = "SET_CERTIFIED_DEVICES"
    case setActivity = "SET_ACTIVITY"
    case sendActivityJoinInvite = "SEND_ACTIVITY_JOIN_INVITE"
    case closeActivityRequest = "CLOSE_ACTIVITY_REQUEST"

    /// Advisory scope categories, not a proof of server permission or an exhaustive authorization policy.
    /// Runtime admission must let the desktop client decide actual approval, tester and scope access.
    public var requiredScopes: Set<String> {
        switch self {
        case .authorize, .authenticate: []
        case .getVoiceSettings, .getSelectedVoiceChannel: ["rpc", "rpc.voice.read"]
        case .setUserVoiceSettings, .selectVoiceChannel, .setVoiceSettings: ["rpc", "rpc.voice.write"]
        case .setActivity, .sendActivityJoinInvite, .closeActivityRequest: ["rpc", "rpc.activities.write"]
        default: ["rpc"]
        }
    }

    /// Whether the reference describes an authenticated RPC operation. No authentication is performed here.
    /// Rich Presence availability can differ in SDK transports; this catalog records the RPC reference contract.
    public var requiresAuthentication: Bool { self != .authorize && self != .authenticate }

    /// Whether RPC application approval or placement on the developer tester list controls access.
    /// A true value is advisory and never substitutes for Discord's current server decision.
    public var approvalRequired: Bool { true }
}

/// Unknown-preserving RPC dispatch name; new events remain observable without a library update.
public struct RPCEventName: RawRepresentable, Sendable, Hashable {
    /// Exact server spelling, including names introduced after this catalog was verified.
    public let rawValue: String

    /// Retains an event name without network activity or a known-case restriction.
    /// - Parameter rawValue: Exact event spelling. Request builders validate nonempty bounded names.
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ready = Self(rawValue: "READY")
    public static let error = Self(rawValue: "ERROR")
    public static let guildStatus = Self(rawValue: "GUILD_STATUS")
    public static let guildCreate = Self(rawValue: "GUILD_CREATE")
    public static let channelCreate = Self(rawValue: "CHANNEL_CREATE")
    public static let voiceChannelSelect = Self(rawValue: "VOICE_CHANNEL_SELECT")
    public static let voiceSettingsUpdate = Self(rawValue: "VOICE_SETTINGS_UPDATE")
    public static let voiceStateCreate = Self(rawValue: "VOICE_STATE_CREATE")
    public static let voiceStateUpdate = Self(rawValue: "VOICE_STATE_UPDATE")
    public static let voiceStateDelete = Self(rawValue: "VOICE_STATE_DELETE")
    public static let voiceConnectionStatus = Self(rawValue: "VOICE_CONNECTION_STATUS")
    public static let messageCreate = Self(rawValue: "MESSAGE_CREATE")
    public static let messageUpdate = Self(rawValue: "MESSAGE_UPDATE")
    public static let messageDelete = Self(rawValue: "MESSAGE_DELETE")
    public static let speakingStart = Self(rawValue: "SPEAKING_START")
    public static let speakingStop = Self(rawValue: "SPEAKING_STOP")
    public static let notificationCreate = Self(rawValue: "NOTIFICATION_CREATE")
    public static let activityJoin = Self(rawValue: "ACTIVITY_JOIN")
    public static let activitySpectate = Self(rawValue: "ACTIVITY_SPECTATE")
    public static let activityJoinRequest = Self(rawValue: "ACTIVITY_JOIN_REQUEST")
    public static let activityInvite = Self(rawValue: "ACTIVITY_INVITE")
    public static let currentUserUpdate = Self(rawValue: "CURRENT_USER_UPDATE")
    public static let relationshipUpdate = Self(rawValue: "RELATIONSHIP_UPDATE")
    public static let entitlementCreate = Self(rawValue: "ENTITLEMENT_CREATE")
    public static let entitlementDelete = Self(rawValue: "ENTITLEMENT_DELETE")

    /// All 25 dispatch names documented on 2026-10-17; order follows the catalog's event families.
    public static let documented: [Self] = [
        .ready, .error, .guildStatus, .guildCreate, .channelCreate, .voiceChannelSelect,
        .voiceSettingsUpdate, .voiceStateCreate, .voiceStateUpdate, .voiceStateDelete,
        .voiceConnectionStatus, .messageCreate, .messageUpdate, .messageDelete,
        .speakingStart, .speakingStop, .notificationCreate, .activityJoin, .activitySpectate,
        .activityJoinRequest, .activityInvite, .currentUserUpdate, .relationshipUpdate,
        .entitlementCreate, .entitlementDelete
    ]

    /// Additional advisory OAuth scopes described for this event family; the server remains authoritative.
    /// The RPC page spells the relationship scope `relationships_read`; the current OAuth scope table
    /// spells it `relationships.read`, which is retained here. Unknown events have no invented scope.
    public var requiredScopes: Set<String> {
        switch self {
        case .notificationCreate: ["rpc.notifications.read"]
        case .relationshipUpdate: ["relationships.read"]
        case .voiceSettingsUpdate, .voiceStateCreate, .voiceStateUpdate, .voiceStateDelete,
             .voiceConnectionStatus, .speakingStart, .speakingStop, .voiceChannelSelect: ["rpc.voice.read"]
        case .messageCreate, .messageUpdate, .messageDelete: ["messages.read"]
        default: []
        }
    }
}

/// Explicit user OAuth2 access token for RPC AUTHENTICATE; this type never accepts a bot-token API value.
/// Raw strings cannot prove issuer or token class. Obtain this value from a trusted user OAuth2 exchange.
public struct RPCUserAccessToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    package let value: String

    /// Wraps a raw user OAuth2 token, rejecting empty, control/whitespace-containing and header-form credentials.
    /// - Parameter oauthAccessToken: Trusted visible-ASCII OAuth2 access token, at most 16 KiB;
    ///   never an HTTP header or bot token. Non-ASCII strings are rejected rather than transformed.
    /// - Throws: `RPCCatalogError.invalidAccessToken` without including supplied credentials.
    public init(oauthAccessToken: String) throws {
        guard !oauthAccessToken.isEmpty, oauthAccessToken.utf8.count <= 16_384,
              oauthAccessToken.utf8.allSatisfy({ (33...126).contains($0) }),
              !oauthAccessToken.lowercased().hasPrefix("bot "), !oauthAccessToken.lowercased().hasPrefix("bearer ")
        else { throw RPCCatalogError.invalidAccessToken }
        value = oauthAccessToken
    }

    /// Conceals the credential in interpolation and collection diagnostics.
    public var description: String { "RPCUserAccessToken(redacted)" }
    /// Conceals the credential in debugger-oriented string output.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing the stored user OAuth2 credential.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Immutable bounded RPC v1 request descriptor. Construction performs no I/O or task creation.
/// Arguments are intentionally explicit for wire execution; ordinary descriptions redact their contents.
/// Request execution, nonce correlation, cancellation, transport ownership and bounded timeouts belong
/// to the separately adopted RPC client. There is no automatic retry or pagination in these descriptors.
/// Scope references: https://docs.discord.com/developers/topics/oauth2#oauth2-scopes.
public struct RPCRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let command: RPCCommand
    public let arguments: [String: JSONValue]
    public let event: RPCEventName?

    /// Creates a validated descriptor from a documented command and explicit future-compatible arguments.
    /// - Parameters:
    ///   - command: Client command; server DISPATCH cannot be expressed.
    ///   - arguments: Object members, limited to 1 MiB, depth 64 and 100,000 nodes by default.
    ///   - event: Required for subscriptions, prohibited for other commands; READY/ERROR cannot be subscribed.
    ///   - userApprovedForcedMove: Defaults to false; explicit caller attestation required if force is true
    ///     for SELECT_VOICE_CHANNEL, after the user has approved movement from their current channel.
    ///   - limits: Whole-arguments JSON serialization limits, including unknown fields.
    /// - Throws: `RPCCatalogError.invalidArguments` for event misuse or invalid documented arguments,
    ///   `RPCCatalogError.invalidAccessToken` for invalid AUTHENTICATE tokens, or JSON bounds errors.
    /// Raw credential contents cannot establish provenance; AUTHENTICATE must contain a user OAuth2 token.
    public init(command: RPCCommand, arguments: [String: JSONValue] = [:], event: RPCEventName? = nil,
                userApprovedForcedMove: Bool = false,
                limits: JSONLimits = .default) throws {
        _ = try JSONValue.object(arguments).serialized(limits: limits)
        if command == .subscribe || command == .unsubscribe {
            guard let event, !event.rawValue.isEmpty, event.rawValue.utf8.count <= 128,
                  event != .ready, event != .error,
                  !event.rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw RPCCatalogError.invalidArguments }
            do { try rpcValidateSubscription(event, arguments: arguments) }
            catch { throw RPCCatalogError.invalidArguments }
        } else if event != nil { throw RPCCatalogError.invalidArguments }
        if command == .selectVoiceChannel, arguments["force"] == .bool(true), !userApprovedForcedMove {
            throw RPCCatalogError.invalidArguments
        }
        try rpcValidateArguments(command, arguments)
        self.command = command
        self.arguments = arguments
        self.event = event
    }

    /// Creates AUTHORIZE; user approval/testing restrictions remain controlled by the Discord client.
    /// - Parameters:
    ///   - clientID: Exact application snowflake; zero is rejected.
    ///   - scopes: Nonempty OAuth scope spellings; bot scope is rejected, order and future scopes retained.
    ///   - rpcToken: Optional one-time RPC token. Incompatible with messages.read as documented by Discord.
    ///   - username: Optional guest-account name, retained verbatim when nonempty.
    /// - Returns: A redacted descriptor whose response contains an authorization code for external exchange.
    /// - Throws: Catalog validation or JSON bounds errors. Token exchange and secure storage are caller-owned.
    public static func authorize(clientID: ApplicationID, scopes: [String], rpcToken: String? = nil,
                                 username: String? = nil) throws -> Self {
        var args: [String: JSONValue] = ["client_id": .string(clientID.description), "scopes": .array(scopes.map(JSONValue.string))]
        if let rpcToken { args["rpc_token"] = .string(rpcToken) }
        if let username { args["username"] = .string(username) }
        return try Self(command: .authorize, arguments: args)
    }

    /// Creates AUTHENTICATE without acquiring, refreshing or storing the user OAuth2 credential.
    /// - Parameter token: Explicit trusted user OAuth2 access token, never a bot credential.
    /// - Returns: A request with a redacted description; the transport must also redact encoded frames.
    /// - Throws: JSON argument bounds errors.
    public static func authenticate(_ token: RPCUserAccessToken) throws -> Self {
        try Self(command: .authenticate, arguments: ["access_token": .string(token.value)])
    }

    /// Creates GET_GUILDS with empty arguments; the result is the desktop client's guild projection.
    /// - Returns: An authenticated read descriptor; no pagination or hidden REST requests occur.
    /// - Throws: JSON bounds errors.
    public static func getGuilds() throws -> Self { try Self(command: .getGuilds) }

    /// Creates GET_GUILD for one exact identity.
    /// - Parameters:
    ///   - guildID: Nonzero guild snowflake.
    ///   - timeout: Optional nonnegative desktop wait value; the official RPC reference does not specify units.
    /// - Returns: A guild read descriptor. Deprecated members are returned as the server supplies them.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func getGuild(_ guildID: GuildID, timeout: Int? = nil) throws -> Self {
        var args: [String: JSONValue] = ["guild_id": .string(guildID.description)]
        if let timeout { args["timeout"] = try rpcNumber(timeout) }
        return try Self(command: .getGuild, arguments: args)
    }

    /// Creates GET_CHANNEL without fetching REST data or assuming that RPC matches REST channel shape.
    /// - Parameter channelID: Nonzero exact channel snowflake.
    /// - Returns: A channel read descriptor.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func getChannel(_ channelID: ChannelID) throws -> Self {
        try Self(command: .getChannel, arguments: ["channel_id": .string(channelID.description)])
    }

    /// Creates GET_CHANNELS for a guild visible to the local desktop client.
    /// - Parameter guildID: Nonzero exact guild snowflake.
    /// - Returns: A channel-list descriptor; no implicit pagination or additional calls occur.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func getChannels(_ guildID: GuildID) throws -> Self {
        try Self(command: .getChannels, arguments: ["guild_id": .string(guildID.description)])
    }

    /// Changes another user's local voice controls. Discord currently permits only one controlling app;
    /// settings can reset when that app disconnects, so callers must not infer durable global state.
    /// - Parameters:
    ///   - userID: Nonzero exact user snowflake.
    ///   - pan: Optional stereo levels in 0...1; omission preserves the setting.
    ///   - volume: Optional integral percent in 0...200; omission preserves the setting (Discord default 100).
    ///   - mute: Optional local mute state; omission preserves the setting.
    /// - Returns: SET_USER_VOICE_SETTINGS descriptor; no work is performed until runtime execution.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func setUserVoiceSettings(userID: UserID, pan: RPCPan? = nil, volume: Int? = nil,
                                           mute: Bool? = nil) throws -> Self {
        var args: [String: JSONValue] = ["user_id": .string(userID.description)]
        if let pan { args["pan"] = .object(pan.rawFields) }
        if let volume { args["volume"] = try rpcNumber(volume) }
        if let mute { args["mute"] = .bool(mute) }
        return try Self(command: .setUserVoiceSettings, arguments: args)
    }

    /// Creates SELECT_VOICE_CHANNEL. A 5003 server error means the user is already connected elsewhere.
    /// - Parameters:
    ///   - channelID: Nonzero channel to join, or nil to explicitly leave.
    ///   - timeout: Optional nonnegative desktop wait value; upstream units are undocumented.
    ///   - force: Default false. True is allowed only after explicit user approval to move channels.
    ///   - userApprovedMove: Caller attestation to that approval; true alone does not set force.
    ///   - navigate: Optional instruction to navigate the Discord UI after joining.
    /// - Returns: A descriptor; a successful response can be null when no channel is selected.
    /// - Throws: Catalog validation for unapproved forced movement, invalid IDs/ranges or JSON bounds errors.
    public static func selectVoiceChannel(_ channelID: ChannelID?, timeout: Int? = nil, force: Bool = false,
                                          userApprovedMove: Bool = false, navigate: Bool? = nil) throws -> Self {
        guard !force || userApprovedMove else { throw RPCCatalogError.invalidArguments }
        var args: [String: JSONValue] = ["channel_id": channelID.map { .string($0.description) } ?? .null]
        if let timeout { args["timeout"] = try rpcNumber(timeout) }
        if force { args["force"] = .bool(true) }
        if let navigate { args["navigate"] = .bool(navigate) }
        return try Self(command: .selectVoiceChannel, arguments: args, userApprovedForcedMove: userApprovedMove)
    }

    /// Creates GET_SELECTED_VOICE_CHANNEL; the response is a channel object or explicit null.
    /// - Returns: A read-only descriptor with no arguments.
    /// - Throws: JSON bounds errors.
    public static func getSelectedVoiceChannel() throws -> Self { try Self(command: .getSelectedVoiceChannel) }

    /// Creates SELECT_TEXT_CHANNEL without implying voice membership.
    /// - Parameters:
    ///   - channelID: Nonzero channel to select, or nil to explicitly leave.
    ///   - timeout: Optional nonnegative desktop wait value; upstream units are undocumented.
    /// - Returns: A descriptor whose response is a channel or explicit null.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func selectTextChannel(_ channelID: ChannelID?, timeout: Int? = nil) throws -> Self {
        var args: [String: JSONValue] = ["channel_id": channelID.map { .string($0.description) } ?? .null]
        if let timeout { args["timeout"] = try rpcNumber(timeout) }
        return try Self(command: .selectTextChannel, arguments: args)
    }

    /// Creates GET_VOICE_SETTINGS without touching local devices.
    /// - Returns: A settings read descriptor; the desktop server owns the actual hardware state.
    /// - Throws: JSON bounds errors.
    public static func getVoiceSettings() throws -> Self { try Self(command: .getVoiceSettings) }

    /// Creates a partial SET_VOICE_SETTINGS update; absent fields retain their current values.
    /// - Parameter update: Validated writable fields; available_devices is read-only and rejected.
    /// - Returns: A settings mutation descriptor. Discord's single-app settings lock/reset behavior applies.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func setVoiceSettings(_ update: RPCVoiceSettingsUpdate) throws -> Self {
        try Self(command: .setVoiceSettings, arguments: update.rawFields)
    }

    /// Creates SUBSCRIBE with event-specific channel/guild arguments.
    /// - Parameters:
    ///   - event: Known or future event; READY and ERROR are non-subscription events and rejected.
    ///   - arguments: Exact subscription identity. Known scoped events require a valid channel_id or guild_id.
    /// - Returns: A descriptor; success must be acknowledged before treating a subscription as active.
    /// - Throws: Catalog validation or JSON bounds errors. Unknown event support is server-authoritative.
    public static func subscribe(_ event: RPCEventName, arguments: [String: JSONValue] = [:]) throws -> Self {
        try Self(command: .subscribe, arguments: arguments, event: event)
    }

    /// Creates UNSUBSCRIBE using the same event and argument identity as the original subscription.
    /// - Parameters:
    ///   - event: Event to remove; non-subscription READY/ERROR are rejected.
    ///   - arguments: Original channel/guild arguments; caller owns matching and reconnect policy.
    /// - Returns: A descriptor; no local subscription state changes during construction.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func unsubscribe(_ event: RPCEventName, arguments: [String: JSONValue] = [:]) throws -> Self {
        try Self(command: .unsubscribe, arguments: arguments, event: event)
    }

    /// Creates SET_CERTIFIED_DEVICES for a manufacturer-controlled priority list.
    /// - Parameter devices: Ordered validated certified devices; empty explicitly clears the list.
    /// - Returns: A descriptor; certification/manufacturer authorization is determined by Discord.
    /// - Throws: Catalog validation or JSON bounds errors. No device discovery or hardware access occurs.
    public static func setCertifiedDevices(_ devices: [RPCCertifiedDevice]) throws -> Self {
        try Self(command: .setCertifiedDevices, arguments: ["devices": .array(devices.map { .object($0.rawFields) })])
    }

    /// Creates SET_ACTIVITY for Rich Presence without changing a bot's Gateway presence.
    /// - Parameters:
    ///   - processID: Positive process ID for the application publishing the presence.
    ///   - activity: Validated presence object. The reference does not document null clearing.
    /// - Returns: A descriptor. Discord controls permission, activity availability and rate limits.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func setActivity(processID: Int, activity: RPCActivity) throws -> Self {
        try Self(command: .setActivity, arguments: ["pid": try rpcNumber(processID),
                                                  "activity": .object(activity.rawFields)])
    }

    /// Consents to a specific Rich Presence Ask to Join request.
    /// - Parameter userID: Nonzero exact identity of the requesting user; caller owns consent UI.
    /// - Returns: SEND_ACTIVITY_JOIN_INVITE descriptor; it does not itself join a voice channel.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func sendActivityJoinInvite(to userID: UserID) throws -> Self {
        try Self(command: .sendActivityJoinInvite, arguments: ["user_id": .string(userID.description)])
    }

    /// Rejects a specific Rich Presence Ask to Join request.
    /// - Parameter userID: Nonzero exact identity of the requesting user.
    /// - Returns: CLOSE_ACTIVITY_REQUEST descriptor; retries are an explicit caller decision.
    /// - Throws: Catalog validation or JSON bounds errors.
    public static func closeActivityRequest(from userID: UserID) throws -> Self {
        try Self(command: .closeActivityRequest, arguments: ["user_id": .string(userID.description)])
    }

    /// Conceals argument contents, including tokens, message data and activity secrets.
    public var description: String { "RPCRequest(\(command.rawValue), arguments: redacted)" }
    /// Uses the same redaction in debugging-oriented diagnostics.
    public var debugDescription: String { description }
    /// Prevents Mirror/dump from recursively exposing encoded tokens, payloads and future arguments.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Converts a bounded native integer to an exact JSON lexeme without floating-point conversion.
/// - Parameter value: Any native integer; command validators enforce operation-specific ranges.
/// - Returns: An exact integral JSON number.
/// - Throws: JSON number grammar errors; native integer spellings are always valid.
func rpcNumber(_ value: Int) throws -> JSONValue { .number(try JSONNumber(rawValue: String(value))) }

/// Validates known subscription scope arguments without rejecting future event names or fields.
/// - Parameters:
///   - event: Event whose identity determines required scope keys.
///   - arguments: Immutable event-specific arguments.
/// - Throws: Sanitized invalid-argument errors for missing/malformed exact IDs.
private func rpcValidateSubscription(_ event: RPCEventName, arguments: [String: JSONValue]) throws {
    let object = try RPCObject(.object(arguments))
    switch event {
    case .guildStatus: let _: GuildID = try object.id("guild_id")
    case .voiceStateCreate, .voiceStateUpdate, .voiceStateDelete, .messageCreate, .messageUpdate,
         .messageDelete, .speakingStart, .speakingStop:
        let _: ChannelID = try object.id("channel_id")
    default: break
    }
}

/// Checks documented command invariants even when callers use the future-compatible raw initializer.
/// - Parameters:
///   - command: Documented outgoing RPC command.
///   - fields: Arguments already checked against complete JSON limits.
/// - Throws: Sanitized invalid arguments/access-token errors; no contents are included in diagnostics.
private func rpcValidateArguments(_ command: RPCCommand, _ fields: [String: JSONValue]) throws {
    do {
        let object = try RPCObject(.object(fields))
        switch command {
        case .authorize:
            let _: ApplicationID = try object.id("client_id")
            let scopes = try object.array("scopes").map { try RPCObject.string($0) }
            guard !scopes.isEmpty, scopes.allSatisfy({ !$0.isEmpty && !$0.contains(where: { $0.isWhitespace }) && $0 != "bot" })
            else { throw RPCCatalogError.invalidArguments }
            if let token = fields["rpc_token"] {
                guard !(try RPCObject.string(token)).isEmpty, !scopes.contains("messages.read") else {
                    throw RPCCatalogError.invalidArguments
                }
            }
            if let username = fields["username"], try RPCObject.string(username).isEmpty { throw RPCCatalogError.invalidArguments }
        case .authenticate:
            _ = try RPCUserAccessToken(oauthAccessToken: object.string("access_token"))
        case .getGuild, .getChannels: let _: GuildID = try object.id("guild_id")
        case .getChannel: let _: ChannelID = try object.id("channel_id")
        case .selectTextChannel, .selectVoiceChannel:
            guard let value = fields["channel_id"] else { throw RPCCatalogError.invalidArguments }
            if value != .null { let _: ChannelID = try object.id("channel_id") }
            if let force = fields["force"] { _ = try RPCObject.bool(force) }
            if let navigate = fields["navigate"] { _ = try RPCObject.bool(navigate) }
        case .setUserVoiceSettings:
            let _: UserID = try object.id("user_id")
            if let pan = fields["pan"] { _ = try RPCPan(value: pan) }
            if let volume = fields["volume"], !(0...200).contains(try RPCObject.integer(volume)) {
                throw RPCCatalogError.invalidArguments
            }
            if let mute = fields["mute"] { _ = try RPCObject.bool(mute) }
        case .setVoiceSettings: _ = try RPCVoiceSettingsUpdate(fields: fields)
        case .setCertifiedDevices:
            for device in try object.array("devices") { _ = try RPCCertifiedDevice(value: device) }
        case .setActivity:
            guard try object.integer("pid") > 0, let activity = fields["activity"] else {
                throw RPCCatalogError.invalidArguments
            }
            _ = try RPCActivity(fields: RPCObject(activity).fields)
        case .sendActivityJoinInvite, .closeActivityRequest: let _: UserID = try object.id("user_id")
        default: break
        }
        if let timeout = fields["timeout"], try RPCObject.integer(timeout) < 0 { throw RPCCatalogError.invalidArguments }
    } catch RPCCatalogError.invalidAccessToken { throw RPCCatalogError.invalidAccessToken }
    catch { throw RPCCatalogError.invalidArguments }
}
