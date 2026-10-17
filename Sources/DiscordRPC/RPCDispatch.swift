import DiscordCore
import Foundation

/// Typed data for every RPC v1 event documented on 2026-10-17, with an explicit future-event escape hatch.
/// Event-family cases preserve their exact name so update/delete and start/stop remain distinguishable.
/// All projections are immutable and retain complete original fields; descriptions conceal payload content.
public enum RPCEventPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case ready(RPCReady)
    case error(RPCErrorPayload)
    case guildStatus(RPCGuildStatus)
    case guildCreate(RPCGuild)
    case channelCreate(RPCChannel)
    case voiceChannelSelect(RPCChannelSelection)
    case voiceSettingsUpdate(RPCVoiceSettings)
    case voiceState(name: RPCEventName, value: RPCVoiceState)
    case voiceConnectionStatus(RPCVoiceConnectionStatus)
    case message(name: RPCEventName, value: RPCMessageEvent)
    case speaking(name: RPCEventName, value: RPCSpeaking)
    case notificationCreate(RPCNotification)
    case activityJoin(RPCActivitySecret)
    case activitySpectate(RPCActivitySecret)
    case activityJoinRequest(RPCActivityJoinRequest)
    case activityInvite(RPCActivityInvite)
    case currentUserUpdate(RPCUser)
    case relationshipUpdate(RPCRelationship)
    case entitlement(name: RPCEventName, value: RPCEntitlementEvent)
    case unknown(name: RPCEventName, data: JSONValue)

    /// Projects an event's already-bounded data without assuming subscription admission or authentication.
    /// - Parameters:
    ///   - name: Exact known or future event name from the RPC envelope.
    ///   - data: Immutable original data tree from the bounded envelope parser.
    /// - Returns: Typed known data or an unchanged future-event tree, including scalar/array variants.
    /// - Throws: Sanitized invalid-payload errors for malformed known data. Unknown names never invent
    ///   a schema. No I/O, suspension, hidden tasks, entitlement verification or mutation occurs.
    public static func decode(name: RPCEventName, data: JSONValue) throws -> Self {
        switch name {
        case .ready: .ready(try RPCReady(value: data))
        case .error: .error(try RPCErrorPayload(value: data))
        case .guildStatus: .guildStatus(try RPCGuildStatus(value: data))
        case .guildCreate: .guildCreate(try RPCGuild(value: data))
        case .channelCreate: .channelCreate(try RPCChannel(value: data))
        case .voiceChannelSelect: .voiceChannelSelect(try RPCChannelSelection(value: data))
        case .voiceSettingsUpdate: .voiceSettingsUpdate(try RPCVoiceSettings(value: data))
        case .voiceStateCreate, .voiceStateUpdate, .voiceStateDelete:
            .voiceState(name: name, value: try RPCVoiceState(value: data))
        case .voiceConnectionStatus: .voiceConnectionStatus(try RPCVoiceConnectionStatus(value: data))
        case .messageCreate, .messageUpdate, .messageDelete:
            .message(name: name, value: try RPCMessageEvent(value: data))
        case .speakingStart, .speakingStop: .speaking(name: name, value: try RPCSpeaking(value: data))
        case .notificationCreate: .notificationCreate(try RPCNotification(value: data))
        case .activityJoin: .activityJoin(try RPCActivitySecret(value: data))
        case .activitySpectate: .activitySpectate(try RPCActivitySecret(value: data))
        case .activityJoinRequest: .activityJoinRequest(try RPCActivityJoinRequest(value: data))
        case .activityInvite: .activityInvite(try RPCActivityInvite(value: data))
        case .currentUserUpdate: .currentUserUpdate(try RPCUser(value: data))
        case .relationshipUpdate: .relationshipUpdate(try RPCRelationship(value: data))
        case .entitlementCreate, .entitlementDelete: .entitlement(name: name, value: try RPCEntitlementEvent(value: data))
        default: .unknown(name: name, data: data)
        }
    }

    /// Parses and projects event data with complete JSON resource bounds before schema inspection.
    /// - Parameters:
    ///   - name: Exact event name; unknown names preserve arbitrary valid JSON.
    ///   - bytes: Complete UTF-8 data field JSON, without the outer RPC envelope.
    ///   - limits: Default 1 MiB/depth 64/100,000 nodes; applies to unknown fields too.
    /// - Returns: A typed projection or lossless unknown payload.
    /// - Throws: JSON syntax/bounds errors or sanitized known-schema validation errors.
    public static func decode(name: RPCEventName, bytes: Data, limits: JSONLimits = .default) throws -> Self {
        try decode(name: name, data: JSONValue.parse(bytes, limits: limits))
    }

    /// Conceals all personal data, server strings and activity secrets in interpolation.
    public var description: String { "RPCEventPayload(redacted)" }
    /// Uses the same redaction for debugger-oriented diagnostics.
    public var debugDescription: String { description }
    /// Prevents Mirror/dump from traversing known associated payloads or arbitrary future event data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Typed successful command results. Server error envelopes are decoded separately as RPCErrorPayload.
/// Commands whose response schema is unpublished preserve the original JSON without inventing structure.
public enum RPCResponsePayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case authorized(RPCAuthorization)
    case authenticated(RPCAuthentication)
    case guilds(RPCGuildList)
    case guild(RPCGuild)
    case channel(Nullable<RPCChannel>)
    case channels(RPCChannelList)
    case userVoiceSettings(RPCUserVoiceSettings)
    case voiceSettings(RPCVoiceSettings)
    case subscription(RPCSubscriptionAcknowledgement)
    case certifiedDevices
    case unmodeled(command: RPCCommand, data: JSONValue)

    /// Projects a successful command's already-bounded data field.
    /// - Parameters:
    ///   - command: Documented command associated with the matching nonce.
    ///   - data: Immutable original response data, including explicit null where documented.
    /// - Returns: A typed result, or exact unmodeled data for activity/invite response schemas.
    /// - Throws: Sanitized invalid-payload errors for malformed documented response shapes.
    /// The caller must first check envelope ERROR, nonce and command correlation; decoding alone does
    /// not establish operation success, permissions or current client state. No I/O or suspension occurs.
    public static func decode(command: RPCCommand, data: JSONValue) throws -> Self {
        return switch command {
        case .authorize: .authorized(try RPCAuthorization(value: data))
        case .authenticate: .authenticated(try RPCAuthentication(value: data))
        case .getGuilds: .guilds(try RPCGuildList(value: data))
        case .getGuild: .guild(try RPCGuild(value: data))
        case .getChannel: .channel(.value(try RPCChannel(value: data)))
        case .selectVoiceChannel, .selectTextChannel, .getSelectedVoiceChannel:
            .channel(data == .null ? .null : .value(try RPCChannel(value: data)))
        case .getChannels: .channels(try RPCChannelList(value: data))
        case .setUserVoiceSettings: .userVoiceSettings(try RPCUserVoiceSettings(value: data))
        case .getVoiceSettings, .setVoiceSettings: .voiceSettings(try RPCVoiceSettings(value: data))
        case .subscribe, .unsubscribe: .subscription(try RPCSubscriptionAcknowledgement(value: data))
        case .setCertifiedDevices:
            try certifiedDevicesAcknowledgement(data)
        case .setActivity, .sendActivityJoinInvite, .closeActivityRequest: .unmodeled(command: command, data: data)
        }
    }

    /// Conceals codes, credentials, profiles and unknown response data in ordinary diagnostics.
    public var description: String { "RPCResponsePayload(redacted)" }
    /// Uses the same redaction for debugger-oriented output.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing OAuth codes and unpublished response data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Requires the documented null certified-device acknowledgement without inventing a success object.
/// - Parameter data: Original successful response data from the matched command envelope.
/// - Returns: The typed acknowledgement only for explicit null.
/// - Throws: Sanitized invalid-payload error for any other value, including an empty object.
private func certifiedDevicesAcknowledgement(_ data: JSONValue) throws -> RPCResponsePayload {
    guard data == .null else { throw RPCCatalogError.invalidPayload }
    return .certifiedDevices
}
