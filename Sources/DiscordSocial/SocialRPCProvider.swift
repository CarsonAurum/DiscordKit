// File: Sources/DiscordSocial/SocialRPCProvider.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordRPC
import DiscordTransport

/// Narrow desktop RPC v1 equivalents; the caller owns connect/authenticate/subscription/close lifetimes.
/// Construction starts no I/O. These operations control the local Discord desktop account,
/// require approved/tester access and user OAuth scopes, and establish no native Social socket.
public struct SocialRPCProvider<C: Clock>: SocialPresenceProvider where C.Duration == Duration {
    public typealias ProviderClock = C
    private let client: RPCClient<C>
    private let processID: Int
    public let presenceRequirements = SocialProviderRequirements(host: .desktopRPC, scopes: ["rpc", "rpc.activities.write"])
    /// Read-only desktop voice-settings scopes; the desktop host also enforces application approval/tester access.
    public let voiceReadRequirements = SocialProviderRequirements(host: .desktopRPC, scopes: ["rpc", "rpc.voice.read"])
    /// Desktop voice mutation scopes; forced movement still requires separate user approval for that action.
    public let voiceWriteRequirements = SocialProviderRequirements(host: .desktopRPC, scopes: ["rpc", "rpc.voice.write"])
    /// Scopes for desktop channel enumeration and text selection; no REST or native Social authorization is implied.
    public let channelRequirements = SocialProviderRequirements(host: .desktopRPC, scopes: ["rpc"])

    /// Retains an independently owned desktop client and validates the publishing process identifier.
    /// - Parameters:
    ///   - client: Connected/authenticated RPC owner; construction never connects or acquires approval.
    ///   - processID: Positive OS process identifier used by SET_ACTIVITY; no process discovery occurs.
    /// - Throws: `RPCCatalogError.invalidArguments` for nonpositive process identifiers.
    public init(client: RPCClient<C>, processID: Int) throws {
        guard processID > 0 else { throw RPCCatalogError.invalidArguments }
        self.client = client; self.processID = processID
    }

    /// Publishes the neutral presence fields through documented desktop SET_ACTIVITY exactly once.
    /// - Parameters:
    ///   - presence: Validated name and optional details/state; nil fields are omitted.
    ///   - context: Cancellation and optional deadline in the RPC client's clock domain.
    /// - Throws: Invalid arguments, missing connection/authentication/approval/scopes, bounded overload,
    ///   cancellation, deadline, correlation or transport failures. An admitted mutation can be indeterminate.
    /// There is no automatic retry, presence clearing, Gateway bot update or Social-session equivalence.
    public func updatePresence(_ presence: SocialPresence, context: TransportContext<C>) async throws {
        var fields: [String: JSONValue] = ["name": .string(presence.name)]
        if let details = presence.details { fields["details"] = .string(details) }
        if let state = presence.state { fields["state"] = .string(state) }
        _ = try await setPresence(RPCActivity(fields: fields), context: context)
    }

    /// Executes a validated desktop Rich Presence update without inventing a clearing protocol.
    /// - Parameters:
    ///   - activity: RPC-specific validated activity, including explicitly chosen additional fields.
    ///   - context: Cancellation and optional RPC-clock deadline.
    /// - Returns: Original response data because the RPC reference does not publish its complete shape.
    /// - Throws: Validation, connection/auth/scope/approval, overload, cancellation, deadline or transport failures.
    /// Requires rpc and rpc.activities.write; no mutation is replayed after uncertain delivery.
    public func setPresence(_ activity: RPCActivity, context: TransportContext<C>) async throws -> JSONValue {
        try await client.request(RPCRequest.setActivity(processID: processID, activity: activity), context: context)
    }

    /// Reads channels visible to the authenticated desktop user for one guild.
    /// - Parameters:
    ///   - guildID: Nonzero exact guild identifier; rpc scope and approved/tester access remain upstream checks.
    ///   - context: Cancellation and optional RPC-clock deadline.
    /// - Returns: Typed RPC channels in host order; this shape is distinct from REST or Social SDK channels.
    /// - Throws: Validation, auth/connection/approval, API, cancellation, deadline or malformed-response failures.
    public func guildChannels(_ guildID: GuildID, context: TransportContext<C>) async throws -> RPCChannelList {
        try await RPCChannelList(value: client.request(RPCRequest.getChannels(guildID), context: context))
    }

    /// Reads desktop voice settings and available devices without opening local application audio hardware.
    /// - Parameter context: Cancellation and optional RPC-clock deadline; rpc and rpc.voice.read are required.
    /// - Returns: Typed settings preserving unknown fields and missing values without invented defaults.
    /// - Throws: Connection/auth/approval, overload, cancellation, deadline, transport or malformed-response failures.
    public func voiceSettings(context: TransportContext<C>) async throws -> RPCVoiceSettings {
        try await RPCVoiceSettings(value: client.request(RPCRequest.getVoiceSettings(), context: context))
    }

    /// Changes desktop-owned device selection, volume, mute/deafen or voice processing settings.
    /// - Parameters:
    ///   - update: Validated partial patch; omitted fields preserve state and read-only device arrays are rejected.
    ///   - context: Cancellation and optional RPC-clock deadline; rpc and rpc.voice.write are required.
    /// - Returns: Authoritative typed desktop settings, without asserting durable or global application settings.
    /// - Throws: Validation, auth/approval/single-app lock, overload, cancellation, deadline or transport failures.
    /// Discord can reset these settings when the controlling app disconnects. No native device I/O occurs here.
    public func updateVoiceSettings(_ update: RPCVoiceSettingsUpdate, context: TransportContext<C>) async throws -> RPCVoiceSettings {
        try await RPCVoiceSettings(value: client.request(RPCRequest.setVoiceSettings(update), context: context))
    }

    /// Applies another user's local desktop volume, stereo pan or mute under rpc.voice.write.
    /// - Parameters:
    ///   - userID: Exact nonzero user to adjust; this never changes the user's own device configuration.
    ///   - pan: Optional left/right levels in 0...1; nil preserves pan.
    ///   - volume: Optional integral 0...200 percent; nil preserves volume.
    ///   - mute: Optional local mute state; nil preserves it.
    ///   - context: Cancellation and optional RPC-clock deadline, also requiring rpc and approved/tester access.
    /// - Returns: Typed echoed controls without defaults for omitted fields.
    /// - Throws: Validation, authorization/lock, connection, overload, cancellation, deadline or transport failures.
    public func updateUserVoiceSettings(userID: UserID, pan: RPCPan? = nil, volume: Int? = nil,
                                        mute: Bool? = nil, context: TransportContext<C>) async throws -> RPCUserVoiceSettings {
        try await RPCUserVoiceSettings(value: client.request(RPCRequest.setUserVoiceSettings(userID: userID,
            pan: pan, volume: volume, mute: mute), context: context))
    }

    /// Selects a desktop text channel through public RPC, without changing voice membership.
    /// - Parameters:
    ///   - channelID: Exact nonzero channel, or nil to clear selection according to the RPC contract.
    ///   - context: Cancellation and optional RPC-clock deadline; rpc and approved/tester access are required.
    /// - Returns: Selected typed RPC channel or explicit null.
    /// - Throws: Validation, authorization, connection, overload, cancellation, deadline or malformed-response failures.
    public func selectTextChannel(_ channelID: ChannelID?, context: TransportContext<C>) async throws -> Nullable<RPCChannel> {
        let value = try await client.request(RPCRequest.selectTextChannel(channelID), context: context)
        return value == .null ? .null : .value(try RPCChannel(value: value))
    }

    /// Selects or leaves a desktop voice channel with explicit approval before any forced movement.
    /// - Parameters:
    ///   - channelID: Exact nonzero destination, or nil to leave; no SDK lobby-call signaling is inferred.
    ///   - force: Whether to move an already connected user; default false.
    ///   - userApprovedMove: Explicit caller attestation of consent; default false and required when force is true.
    ///   - context: Cancellation and optional RPC-clock deadline; rpc and rpc.voice.write are required.
    /// - Returns: Selected typed channel or explicit null.
    /// - Throws: Invalid/unapproved move before I/O, auth/approval, desktop 5003 conflicts, cancellation,
    ///   deadline, transport or uncertain submitted-mutation failures. There is no implicit retry with force.
    public func selectVoiceChannel(_ channelID: ChannelID?, force: Bool = false, userApprovedMove: Bool = false,
                                   context: TransportContext<C>) async throws -> Nullable<RPCChannel> {
        let value = try await client.request(RPCRequest.selectVoiceChannel(channelID, force: force,
            userApprovedMove: userApprovedMove), context: context)
        return value == .null ? .null : .value(try RPCChannel(value: value))
    }

    /// Accepts or rejects one observed Rich Presence Ask to Join request after caller-owned consent UI.
    /// - Parameters:
    ///   - userID: Nonzero requesting user selected from the caller's event stream.
    ///   - accept: True sends SEND_ACTIVITY_JOIN_INVITE; false sends CLOSE_ACTIVITY_REQUEST.
    ///   - context: Cancellation and optional RPC-clock deadline; rpc and rpc.activities.write are required.
    /// - Returns: Exact acknowledgement data because no complete response schema is published.
    /// - Throws: Validation, auth/approval, connection, overload, cancellation, deadline or uncertain delivery failures.
    /// This is not a generic friend request, unsolicited invite, voice join or Social-session operation.
    public func replyToJoinRequest(userID: UserID, accept: Bool, context: TransportContext<C>) async throws -> JSONValue {
        let request = try accept ? RPCRequest.sendActivityJoinInvite(to: userID) : RPCRequest.closeActivityRequest(from: userID)
        return try await client.request(request, context: context)
    }
}
