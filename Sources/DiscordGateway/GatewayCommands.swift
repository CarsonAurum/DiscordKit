import DiscordCore
import DiscordTransport
import Foundation

/// Gateway v10 opcode values, including unknown future values received from Discord.
/// Values do not authorize arbitrary outbound frames; `GatewayCommand` exposes only reviewed commands.
public struct GatewayOpcode: RawRepresentable, Sendable, Hashable {
    public let rawValue: Int

    /// Retains an exact opcode without interpreting unknown values or performing I/O.
    /// - Parameter rawValue: Wire integer; received-envelope validation rejects negative values separately.
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let dispatch = Self(rawValue: 0)
    public static let heartbeat = Self(rawValue: 1)
    public static let identify = Self(rawValue: 2)
    public static let presenceUpdate = Self(rawValue: 3)
    public static let voiceStateUpdate = Self(rawValue: 4)
    public static let resume = Self(rawValue: 6)
    public static let reconnect = Self(rawValue: 7)
    public static let requestGuildMembers = Self(rawValue: 8)
    public static let invalidSession = Self(rawValue: 9)
    public static let hello = Self(rawValue: 10)
    public static let heartbeatACK = Self(rawValue: 11)
    public static let requestSoundboardSounds = Self(rawValue: 31)
    public static let requestChannelInfo = Self(rawValue: 43)
}

/// Gateway Identify intent bits, verified against Discord's v10 documentation on 2026-10-16.
/// Unknown bits are retained for inspection; passing them to Discord can close a connection with 4013.
/// Privileged intent portal enablement and approval cannot be verified locally.
public struct GatewayIntents: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64

    /// Retains every intent bit without inferring portal enablement or application approval.
    /// - Parameter rawValue: Any unsigned bitfield, including zero and future bits.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let guilds = Self(rawValue: 1 << 0)
    public static let guildMembers = Self(rawValue: 1 << 1)
    public static let guildModeration = Self(rawValue: 1 << 2)
    public static let guildExpressions = Self(rawValue: 1 << 3)
    public static let guildIntegrations = Self(rawValue: 1 << 4)
    public static let guildWebhooks = Self(rawValue: 1 << 5)
    public static let guildInvites = Self(rawValue: 1 << 6)
    public static let guildVoiceStates = Self(rawValue: 1 << 7)
    public static let guildPresences = Self(rawValue: 1 << 8)
    public static let guildMessages = Self(rawValue: 1 << 9)
    public static let guildMessageReactions = Self(rawValue: 1 << 10)
    public static let guildMessageTyping = Self(rawValue: 1 << 11)
    public static let directMessages = Self(rawValue: 1 << 12)
    public static let directMessageReactions = Self(rawValue: 1 << 13)
    public static let directMessageTyping = Self(rawValue: 1 << 14)
    public static let messageContent = Self(rawValue: 1 << 15)
    public static let guildScheduledEvents = Self(rawValue: 1 << 16)
    public static let autoModerationConfiguration = Self(rawValue: 1 << 20)
    public static let autoModerationExecution = Self(rawValue: 1 << 21)
    public static let guildMessagePolls = Self(rawValue: 1 << 24)
    public static let directMessagePolls = Self(rawValue: 1 << 25)

    /// Current documented bits; deliberately omits undocumented gaps rather than assuming continuity.
    public static let known: Self = [
        .guilds, .guildMembers, .guildModeration, .guildExpressions, .guildIntegrations,
        .guildWebhooks, .guildInvites, .guildVoiceStates, .guildPresences, .guildMessages,
        .guildMessageReactions, .guildMessageTyping, .directMessages, .directMessageReactions,
        .directMessageTyping, .messageContent, .guildScheduledEvents,
        .autoModerationConfiguration, .autoModerationExecution, .guildMessagePolls, .directMessagePolls
    ]
    /// Bits requiring Discord portal enablement and, where applicable, approval.
    public static let privileged: Self = [.guildMembers, .guildPresences, .messageContent]
}

/// Identify behaviors independent of intents, preserving future bits without asserting their support.
public struct GatewayCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64

    /// Stores capabilities without enabling undocumented behaviors implicitly.
    /// - Parameter rawValue: Any unsigned combination, including zero and unknown future flags.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Temporary testing-only opt-in to obfuscated channel metadata; Discord plans to change this opt-in.
    public static let channelObfuscation = Self(rawValue: 1 << 15)
}

/// Writable v10 presence statuses; received unknown spellings remain in raw event data.
public enum GatewayPresenceStatus: String, Sendable, CaseIterable {
    case online, dnd, idle, invisible, offline
}

/// Documented bot activity types. Rich Presence-only fields cannot be sent by this API.
public enum GatewayActivityType: Int, Sendable, CaseIterable {
    case playing = 0, streaming = 1, listening = 2, watching = 3, custom = 4, competing = 5
}

/// A bot-writable activity containing only Discord's supported `name`, `state`, `type`, and `url` fields.
/// The enclosing command's 4096-byte limit bounds all text; no undocumented per-field limit is assumed.
public struct GatewayActivity: Sendable, Equatable {
    public let name: String
    public let type: GatewayActivityType
    public let state: String?
    public let url: String?

    /// Creates a bot activity without fetching metadata or changing presence.
    /// - Parameters:
    ///   - name: Displayed activity name, including an empty string if required by the caller.
    ///   - type: Documented activity type; defaults to playing.
    ///   - state: Optional custom-status or party-state text; `nil` omits the field.
    ///   - url: Optional stream link; `nil` omits it. When streaming, a provided link must use HTTPS Twitch or YouTube.
    ///     Discord validates this field only for streaming; other activity types retain the exact text.
    /// - Throws: `invalidPayload` if a provided streaming URL is malformed or outside the supported services.
    public init(name: String, type: GatewayActivityType = .playing, state: String? = nil,
                url: String? = nil) throws {
        if type == .streaming, let url {
            guard let components = URLComponents(string: url), components.scheme == "https",
                  components.host != nil, components.user == nil, components.password == nil else {
                throw GatewayFailure.invalidPayload
            }
            guard ["twitch.tv", "www.twitch.tv", "youtube.com", "www.youtube.com"]
                .contains(components.host!.lowercased()) else { throw GatewayFailure.invalidPayload }
        }
        self.name = name; self.type = type; self.state = state; self.url = url
    }

    /// Encodes only fields bot users can write, preserving omission of absent state and URL.
    /// - Returns: A synchronous immutable activity object with exact UTF-8 strings.
    public var json: JSONValue {
        var result: [String: JSONValue] = ["name": .string(name), "type": gatewayNumber(type.rawValue)]
        if let state { result["state"] = .string(state) }
        if let url { result["url"] = .string(url) }
        return .object(result)
    }
}

/// Complete outgoing presence state for Identify or opcode 3. Construction has no network side effects.
public struct GatewayPresence: Sendable, Equatable {
    public let since: Int64?
    public let activities: [GatewayActivity]
    public let status: GatewayPresenceStatus
    public let afk: Bool

    /// Validates an explicit replacement presence; absence of activities clears the previous activities.
    /// - Parameters:
    ///   - since: Nonnegative Unix milliseconds when idle began, or `nil` encoded as JSON null.
    ///   - activities: Ordered writable activities; defaults to empty. Final payload bytes provide the bound.
    ///   - status: New status; defaults to online. Discord controls the visible treatment of offline/invisible.
    ///   - afk: Explicit away flag; defaults to false and is always encoded.
    /// - Throws: `invalidPayload` for a negative idle timestamp.
    public init(since: Int64? = nil, activities: [GatewayActivity] = [],
                status: GatewayPresenceStatus = .online, afk: Bool = false) throws {
        guard since == nil || since! >= 0 else { throw GatewayFailure.invalidPayload }
        self.since = since; self.activities = activities; self.status = status; self.afk = afk
    }

    /// Encodes every required Update Presence field, including a null idle timestamp.
    /// - Returns: Exact replacement-state JSON, without acquiring rate admission or changing session state.
    public var json: JSONValue {
        .object(["since": since.map(gatewayNumber) ?? .null, "activities": .array(activities.map(\.json)),
                 "status": .string(status.rawValue), "afk": .bool(afk)])
    }
}

/// Optional Identify configuration for the existing uncompressed JSON v10 runtime.
/// Compression remains disabled because the runtime cannot decode compressed incoming packets.
public struct GatewayIdentifyConfiguration: Sendable {
    public let operatingSystem: String
    public let browser: String
    public let device: String
    public let largeThreshold: Int?
    public let presence: GatewayPresence?
    public let capabilities: GatewayCapabilities

    /// Existing portable DiscordKit identity with no optional fields or capability opt-ins.
    public static let `default` = Self()

    /// Stores Identify options; validation occurs when constructing the complete credential-bearing payload.
    /// - Parameters:
    ///   - operatingSystem: Nonempty connection `os`; defaults to portable and uses the nondeprecated field name.
    ///   - browser: Nonempty library `browser` name; defaults to DiscordKit.
    ///   - device: Nonempty library `device` name; defaults to DiscordKit.
    ///   - largeThreshold: Optional threshold in 50...250; `nil` lets Discord apply its default of 50.
    ///   - presence: Optional initial complete presence; `nil` omits it.
    ///   - capabilities: Explicit behavior opt-ins; defaults to none. Unknown bits are preserved for future compatibility.
    public init(operatingSystem: String = "portable", browser: String = "DiscordKit",
                device: String = "DiscordKit", largeThreshold: Int? = nil,
                presence: GatewayPresence? = nil, capabilities: GatewayCapabilities = []) {
        self.operatingSystem = operatingSystem; self.browser = browser; self.device = device
        self.largeThreshold = largeThreshold; self.presence = presence; self.capabilities = capabilities
    }

    /// Builds an origin-sensitive Identify data object and checks its complete opcode-2 envelope size.
    /// The returned JSON contains the token and must only be passed to the trusted Gateway send lane.
    /// This synchronous method does not reserve startup allowance, authenticate, or verify portal approval.
    /// - Parameters:
    ///   - token: Bot credential exposed only to populate the returned wire payload; never included in thrown errors.
    ///   - intents: Exact requested bitfield. Future bits pass through; Discord may reject unsupported bits with 4013.
    ///   - shard: Validated fixed-topology shard identity used to encode `[index, count]`.
    /// - Returns: Complete Identify `d`, with optional fields omitted when absent and compression false by omission.
    /// - Throws: `invalidPayload` for empty connection properties, thresholds outside 50...250, or an envelope above 4096 bytes.
    public func payload(token: BotToken, intents: UInt64, shard: ShardIdentity) throws -> JSONValue {
        guard !operatingSystem.isEmpty, !browser.isEmpty, !device.isEmpty,
              largeThreshold == nil || (50...250).contains(largeThreshold!) else {
            throw GatewayFailure.invalidPayload
        }
        var fields = token.withUnsafeValue { token in [
            "token": JSONValue.string(token), "intents": gatewayNumber(intents),
            "shard": .array([gatewayNumber(shard.index), gatewayNumber(shard.count)]),
            "properties": .object(["os": .string(operatingSystem), "browser": .string(browser),
                                    "device": .string(device)])
        ] }
        if let largeThreshold { fields["large_threshold"] = gatewayNumber(largeThreshold) }
        if let presence { fields["presence"] = presence.json }
        if !capabilities.isEmpty { fields["capabilities"] = gatewayNumber(capabilities.rawValue) }
        let data = JSONValue.object(fields)
        _ = try gatewayCommandText(opcode: .identify, data: data)
        return data
    }
}

/// Reviewed outgoing application-command families; control authentication and heartbeat remain runtime-owned.
public enum GatewayCommandKind: Sendable, Equatable {
    case presence, voiceState, members, soundboardSounds, channelInfo
}

/// Ephemeral channel fields currently accepted by Request Channel Info.
public enum GatewayChannelInfoField: String, Sendable, CaseIterable {
    case status
    case voiceStartTime = "voice_start_time"
}

/// An immutable, locally validated Gateway v10 application command with bounded serialized bytes.
/// Factories do not perform I/O or retry. Runtime admission, required intents, shard routing and response
/// correlation must be checked when sending; successful local validation does not establish Discord permissions.
/// Ordinary descriptions/reflection conceal user IDs, nonce values and presence content.
public struct GatewayCommand: Sendable, CustomStringConvertible, CustomReflectable {
    public let opcode: GatewayOpcode
    public let kind: GatewayCommandKind
    public let data: JSONValue
    public let guildIDs: [GuildID]
    public let nonce: String?
    public let requiredIntents: GatewayIntents
    public let requestsAllGuildMembers: Bool
    private let text: String

    /// Stores reviewed metadata after serializing the exact full frame with the Discord send limit.
    /// - Parameters:
    ///   - opcode: Reviewed send opcode corresponding to `kind`.
    ///   - kind: Runtime rate/correlation family.
    ///   - data: Complete command `d`, without lifecycle credentials.
    ///   - guildIDs: Distinct affected guilds in request order; empty for presence.
    ///   - nonce: Optional bounded member-response nonce; absent on commands without nonce support.
    ///   - requiredIntents: Locally checkable command preconditions; portal approval remains remote.
    ///   - requestsAllGuildMembers: Whether this is an empty-query, zero-limit request requiring full-list admission.
    /// - Throws: `invalidPayload` if the complete serialized envelope exceeds 4096 UTF-8 bytes.
    private init(opcode: GatewayOpcode, kind: GatewayCommandKind, data: JSONValue,
                 guildIDs: [GuildID] = [], nonce: String? = nil,
                 requiredIntents: GatewayIntents = [], requestsAllGuildMembers: Bool = false) throws {
        text = try gatewayCommandText(opcode: opcode, data: data)
        self.opcode = opcode; self.kind = kind; self.data = data; self.guildIDs = guildIDs
        self.nonce = nonce; self.requiredIntents = requiredIntents
        self.requestsAllGuildMembers = requestsAllGuildMembers
    }

    /// Creates opcode 3 without sending; Discord limits presence updates to five per 20 seconds.
    /// - Parameter presence: Complete replacement state, also usable as initial Identify presence.
    /// - Returns: A bounded command with no guild routing or response nonce.
    /// - Throws: `invalidPayload` if the serialized full command exceeds 4096 bytes.
    public static func updatePresence(_ presence: GatewayPresence) throws -> Self {
        try Self(opcode: .presenceUpdate, kind: .presence, data: presence.json)
    }

    /// Creates opcode 4 to join, move, or disconnect from a guild voice channel; no media socket is opened.
    /// - Parameters:
    ///   - guildID: Guild whose voice state changes; the runtime must route it to the owning shard.
    ///   - channelID: Voice channel to join or move to, or `nil` encoded as null to disconnect.
    ///   - selfMute: Explicit self-mute state, default false.
    ///   - selfDeaf: Explicit self-deafen state, default false.
    /// - Returns: A bounded voice-state command. Channel permissions and voice protocol setup remain separate.
    /// - Throws: `invalidPayload` if serialization exceeds Discord's 4096-byte send limit.
    public static func updateVoiceState(guildID: GuildID, channelID: ChannelID?,
                                        selfMute: Bool = false, selfDeaf: Bool = false) throws -> Self {
        try Self(opcode: .voiceStateUpdate, kind: .voiceState,
                 data: .object(["guild_id": .string(guildID.description),
                                "channel_id": channelID.map { .string($0.description) } ?? .null,
                                "self_mute": .bool(selfMute), "self_deaf": .bool(selfDeaf)]), guildIDs: [guildID])
    }

    /// Creates an opcode-8 prefix or full-member request for exactly one guild.
    /// The server emits `GUILD_MEMBERS_CHUNK` responses of up to 1000 members; only a nonnil nonce
    /// can unambiguously correlate chunks. Full-list requests require `GUILD_MEMBERS`; requesting
    /// presences additionally requires `GUILD_PRESENCES`, including portal approval when applicable.
    /// - Parameters:
    ///   - guildID: One target guild, routed by the runtime's shard topology.
    ///   - query: Username prefix; empty selects the full-list form and requires the member intent.
    ///   - limit: Nonnegative result bound; zero requires an empty query and requests all members.
    ///     Nonempty prefixes accept 1...100 because Discord returns at most 100 matches.
    ///   - presences: Whether matching presences are requested, default false; always encoded.
    ///   - nonce: Optional exact correlation text of at most 32 UTF-8 bytes; empty is accepted.
    /// - Returns: Validated command carrying required-intent and full-list rate-admission metadata.
    /// - Throws: `invalidPayload` for invalid limit/nonce combinations or a frame exceeding 4096 bytes.
    public static func requestGuildMembers(guildID: GuildID, query: String, limit: Int,
                                           presences: Bool = false, nonce: String? = nil) throws -> Self {
        guard limit >= 0, query.isEmpty || (1...100).contains(limit) else { throw GatewayFailure.invalidPayload }
        var fields: [String: JSONValue] = ["guild_id": .string(guildID.description), "query": .string(query),
                                            "limit": gatewayNumber(limit), "presences": .bool(presences)]
        try addGatewayNonce(nonce, to: &fields)
        var required: GatewayIntents = presences ? .guildPresences : []
        if query.isEmpty { required.insert(.guildMembers) }
        return try Self(opcode: .requestGuildMembers, kind: .members, data: .object(fields),
                        guildIDs: [guildID], nonce: nonce, requiredIntents: required,
                        requestsAllGuildMembers: query.isEmpty && limit == 0)
    }

    /// Creates an opcode-8 exact-user request, excluding the mutually exclusive query/limit fields.
    /// - Parameters:
    ///   - guildID: Exactly one guild to query.
    ///   - userIDs: One through 100 distinct users, encoded as an array even for one user.
    ///   - presences: Whether matching presences are requested; true requires `GUILD_PRESENCES`.
    ///   - nonce: Optional exact response correlation string of at most 32 UTF-8 bytes.
    /// - Returns: Bounded command; the member intent is not required for this targeted form.
    /// - Throws: `invalidPayload` for empty, duplicate or oversized user arrays, invalid nonce bytes,
    ///   or a serialized envelope above 4096 bytes. No requests are sent or retried on failure.
    public static func requestGuildMembers(guildID: GuildID, userIDs: [UserID],
                                           presences: Bool = false, nonce: String? = nil) throws -> Self {
        guard (1...100).contains(userIDs.count), Set(userIDs).count == userIDs.count else {
            throw GatewayFailure.invalidPayload
        }
        var fields: [String: JSONValue] = ["guild_id": .string(guildID.description),
                                            "user_ids": .array(userIDs.map { .string($0.description) }),
                                            "presences": .bool(presences)]
        try addGatewayNonce(nonce, to: &fields)
        return try Self(opcode: .requestGuildMembers, kind: .members, data: .object(fields),
                        guildIDs: [guildID], nonce: nonce, requiredIntents: presences ? .guildPresences : [])
    }

    /// Creates opcode 31; Discord responds once per requested guild with `SOUNDBOARD_SOUNDS`.
    /// This protocol has no nonce; runtime correlation must serialize overlapping guild requests.
    /// - Parameter guildIDs: Nonempty distinct guild IDs in request order; the full wire bound limits count.
    /// - Returns: A bounded request without an invented nonce or undocumented numeric guild-count limit.
    /// - Throws: `invalidPayload` for empty/duplicate guilds or a full frame above 4096 bytes.
    public static func requestSoundboardSounds(guildIDs: [GuildID]) throws -> Self {
        guard !guildIDs.isEmpty, Set(guildIDs).count == guildIDs.count else { throw GatewayFailure.invalidPayload }
        return try Self(opcode: .requestSoundboardSounds, kind: .soundboardSounds,
                        data: .object(["guild_ids": .array(guildIDs.map { .string($0.description) })]), guildIDs: guildIDs)
    }

    /// Creates opcode 43 for ephemeral channel data; the response event is `CHANNEL_INFO`.
    /// This protocol has no nonce; the runtime must serialize overlapping requests for the same guild.
    /// - Parameters:
    ///   - guildID: Guild whose channels are queried.
    ///   - fields: Nonempty distinct supported fields, defaulting to status and voice start time.
    /// - Returns: A bounded command retaining requested field order and no invented response nonce.
    /// - Throws: `invalidPayload` for empty/duplicate fields or an envelope above 4096 bytes.
    public static func requestChannelInfo(guildID: GuildID,
                                          fields: [GatewayChannelInfoField] = [.status, .voiceStartTime]) throws -> Self {
        guard !fields.isEmpty, Set(fields).count == fields.count else { throw GatewayFailure.invalidPayload }
        return try Self(opcode: .requestChannelInfo, kind: .channelInfo,
                        data: .object(["guild_id": .string(guildID.description),
                                       "fields": .array(fields.map { .string($0.rawValue) })]), guildIDs: [guildID])
    }

    /// Returns the exact prevalidated JSON envelope with no additional allocation, network work, or mutation.
    /// - Returns: Plain-text JSON with `op` and `d`, at most 4096 UTF-8 bytes including all escaping.
    public func serialized() -> String { text }

    /// Conceals potentially private command data in ordinary diagnostics.
    public var description: String { "GatewayCommand(redacted)" }

    /// Prevents generic reflection from disclosing IDs, presence contents, or nonce correlation values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Encodes a complete outgoing frame before any network send and maps parser errors to a closed failure.
/// - Parameters:
///   - opcode: Reviewed outgoing v10 opcode.
///   - data: Complete protocol data, possibly containing Identify credentials; never included in errors.
/// - Returns: The exact JSON text, within Discord's inclusive 4096-byte outbound limit.
/// - Throws: `invalidPayload` for encoding limits, without exposing data or parser descriptions.
func gatewayCommandText(opcode: GatewayOpcode, data: JSONValue) throws -> String {
    do {
        let bytes = try JSONValue.object(["op": gatewayNumber(opcode.rawValue), "d": data])
            .serialized(limits: JSONLimits(maximumBytes: 4_096))
        return String(decoding: bytes, as: UTF8.self)
    } catch { throw GatewayFailure.invalidPayload }
}

/// Adds a valid optional member-request nonce to an otherwise complete request object.
/// - Parameters:
///   - nonce: Exact text up to 32 UTF-8 bytes; `nil` omits it and empty strings remain explicit.
///   - fields: Inout data object; mutated only after successful nonce validation.
/// - Throws: `invalidPayload` when the nonce exceeds Discord's byte limit; no character-count approximation is used.
private func addGatewayNonce(_ nonce: String?, to fields: inout [String: JSONValue]) throws {
    guard let nonce else { return }
    guard nonce.utf8.count <= 32 else { throw GatewayFailure.invalidPayload }
    fields["nonce"] = .string(nonce)
}
