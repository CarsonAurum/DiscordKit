import DiscordCore
import DiscordModels
import Foundation

/// Exact local identity of one matched voice session, excluding its token and endpoint.
/// Join generations are scoped to a coordinator, so a generation alone cannot distinguish
/// different guilds, accounts, channels or session replacements. Injected E2EE backends
/// compare this entire value with the context whose epoch and membership they validate.
public struct VoiceConnectionIdentity: Sendable, Equatable, Hashable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let guildID: GuildID
    public let userID: UserID
    public let channelID: ChannelID
    public let sessionID: String
    public let generation: UInt64

    /// Captures complete scope from a bounded rendezvous result without copying its token/endpoint.
    /// - Parameter credentials: Current matched voice session; the opaque session ID remains sensitive.
    /// Construction performs no I/O, authenticates no membership, and starts no work.
    init(credentials: VoiceConnectionCredentials) {
        guildID = credentials.guildID; userID = credentials.userID; channelID = credentials.channelID
        sessionID = credentials.sessionID; generation = credentials.generation
    }

    /// Redacts the session identifier and all associated account/channel scope.
    public var description: String { "VoiceConnectionIdentity(redacted)" }

    /// Uses the same redacted representation during explicit debug interpolation.
    public var debugDescription: String { description }

    /// Prevents generic diagnostic reflection from traversing the sensitive session identifier.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// One ephemeral result of the two main-Gateway events required before opening Voice v8.
/// These credentials must not be cached across channel changes or written to diagnostics.
/// Construction performs no I/O and proves neither current permissions nor endpoint authenticity.
public struct VoiceConnectionCredentials: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public let guildID: GuildID
    public let userID: UserID
    public let channelID: ChannelID
    public let sessionID: String
    public let token: String
    public let endpoint: String
    public let generation: UInt64

    /// Complete session scope for exact E2EE-context binding, with no token or endpoint disclosure.
    /// This synchronous projection starts no work and retains the already-bounded session string.
    public var identity: VoiceConnectionIdentity { VoiceConnectionIdentity(credentials: self) }

    /// Captures a fully matched join result; only the scoped rendezvous constructs credentials.
    /// - Parameters:
    ///   - guildID: Guild matched by both main-Gateway events.
    ///   - userID: The joining account, matched against its own voice-state event.
    ///   - channelID: Requested channel, matched against the voice-state event.
    ///   - sessionID: Nonempty current voice-state session identifier.
    ///   - token: Nonempty current voice-server token; independent from the bot credential.
    ///   - endpoint: Nonempty scheme-free voice endpoint; adapters must validate its origin.
    ///   - generation: Local join fence asserted by the event owner, never an upstream correlation ID.
    init(guildID: GuildID, userID: UserID, channelID: ChannelID, sessionID: String,
         token: String, endpoint: String, generation: UInt64) {
        self.guildID = guildID; self.userID = userID; self.channelID = channelID
        self.sessionID = sessionID; self.token = token; self.endpoint = endpoint; self.generation = generation
    }

    /// Keeps all credentials out of ordinary interpolation and debug descriptions.
    public var description: String { "VoiceConnectionCredentials(redacted)" }

    /// Hides session-bearing properties from generic reflective diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Bounded join rendezvous for one guild/account/channel, accepting either Gateway event order.
/// The caller must send main-Gateway opcode 4 with the required permissions and supply
/// `GUILD_VOICE_STATES` dispatches. This value never sends that request or starts a task.
/// It retains at most one state and one server tuple; other users/guilds are ignored.
/// Discord provides no request nonce on these events: the local generation prevents
/// owner-known stale delivery but cannot authenticate or correlate arbitrary delayed events.
/// https://docs.discord.com/developers/topics/voice-connections#retrieving-voice-server-information
public struct VoiceJoinRendezvous: Sendable, CustomStringConvertible, CustomReflectable {
    public let guildID: GuildID
    public let userID: UserID
    public private(set) var channelID: ChannelID
    public private(set) var generation: UInt64 = 0
    /// Whether a self leave, unsolicited channel move, or explicit invalidation ended this join.
    public private(set) var isInvalidated = false
    private var sessionID: String?
    private var server: Server?
    private var lastEmission: VoiceConnectionCredentials?
    private let maximumCredentialFieldBytes: Int

    /// Minimal server tuple; raw unknown event fields are not retained in the coordinator.
    private struct Server: Sendable, Equatable {
        let token: String
        let endpoint: String
    }

    /// Begins a fresh local join generation without issuing the main-Gateway voice request.
    /// - Parameters:
    ///   - guildID: Guild for both required events; zero has no special wildcard meaning.
    ///   - userID: Joining bot/account; unrelated members never complete or invalidate this join.
    ///   - channelID: Requested channel; a different channel for this account invalidates the join.
    ///   - maximumCredentialFieldBytes: Positive local UTF-8 bound for each session/token/endpoint,
    ///     default 4,096 bytes; this is a retention policy rather than an upstream field limit.
    /// - Throws: `invalidConfiguration` for a nonpositive credential-field bound.
    public init(guildID: GuildID, userID: UserID, channelID: ChannelID,
                maximumCredentialFieldBytes: Int = 4_096) throws {
        guard maximumCredentialFieldBytes > 0 else { throw VoiceControlFailure.invalidConfiguration }
        self.guildID = guildID; self.userID = userID; self.channelID = channelID
        self.maximumCredentialFieldBytes = maximumCredentialFieldBytes
    }

    /// Replaces an outstanding/completed join, clearing both halves before accepting fresh events.
    /// - Parameter channelID: New requested channel, including the same channel for an explicit retry.
    /// - Returns: Strictly increased local generation to attach to owner-routed future inputs.
    /// - Throws: `invalidConfiguration` if the generation is exhausted; state remains unchanged.
    /// Old credentials are never reused, even when Discord returns the same endpoint.
    @discardableResult
    public mutating func replace(channelID: ChannelID) throws -> UInt64 {
        guard generation < UInt64.max else { throw VoiceControlFailure.invalidConfiguration }
        generation += 1; self.channelID = channelID; isInvalidated = false
        clear()
        return generation
    }

    /// Admits this account's voice-state half, or invalidates on self leave/unsolicited move.
    /// - Parameters:
    ///   - state: Typed main-Gateway `VOICE_STATE_UPDATE`; absent guild or unrelated scope is ignored.
    ///   - generation: Owner-captured local join fence, equal to this rendezvous's current generation.
    /// - Returns: Newly completed credentials once per distinct matched pair, otherwise nil.
    /// - Throws: `staleGeneration` before mutation for an old fence; `closed` for an invalidated
    ///   join; `invalidPayload` for an empty/oversized self session. Matching leave/move clears all secrets.
    /// A changed session after completion requires a fresh server event to prevent mixed pairs.
    public mutating func receive(state: VoiceState, generation: UInt64) throws -> VoiceConnectionCredentials? {
        try validate(generation)
        guard state.guildID == .value(guildID), state.userID == userID else { return nil }
        guard state.channelID == .value(channelID) else { invalidate(); return nil }
        guard !state.sessionID.isEmpty, state.sessionID.utf8.count <= maximumCredentialFieldBytes else {
            throw VoiceControlFailure.invalidPayload
        }
        if let previous = sessionID, previous != state.sessionID, lastEmission != nil {
            server = nil; lastEmission = nil
        }
        sessionID = state.sessionID
        return completed()
    }

    /// Admits the server half without caching a previous channel's credentials.
    /// - Parameters:
    ///   - update: Typed main-Gateway `VOICE_SERVER_UPDATE`; unrelated guilds are ignored.
    ///   - generation: Owner-captured current local join fence.
    /// - Returns: Newly completed credentials once per distinct matched pair, otherwise nil.
    /// - Throws: `staleGeneration`/`closed` before mutation, or `invalidPayload` for empty/oversized token/endpoint.
    /// Null endpoints immediately clear both halves and require two fresh events. Replacing a
    /// completed server tuple also requires a fresh state, preventing stale-session reuse.
    public mutating func receive(server update: GatewayVoiceServerUpdate, generation: UInt64) throws
        -> VoiceConnectionCredentials? {
        try validate(generation)
        guard update.guildID == guildID else { return nil }
        guard case .value(let endpoint) = update.endpoint else { clear(); return nil }
        guard !endpoint.isEmpty, !update.token.isEmpty,
              endpoint.utf8.count <= maximumCredentialFieldBytes,
              update.token.utf8.count <= maximumCredentialFieldBytes else { throw VoiceControlFailure.invalidPayload }
        let value = Server(token: update.token, endpoint: endpoint)
        if let previous = server, previous != value, lastEmission != nil {
            sessionID = nil; lastEmission = nil
        }
        server = value
        return completed()
    }

    /// Ends this join and immediately releases both event halves and the duplicate-suppression tuple.
    /// Repeated calls are harmless; `replace(channelID:)` is required before further admission.
    public mutating func invalidate() { clear(); isInvalidated = true }

    /// Conceals credentials in ordinary diagnostics while exposing the type identity.
    public var description: String { "VoiceJoinRendezvous(redacted)" }

    /// Prevents reflection from disclosing pending or completed credentials.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Checks the generation fence and local validity before inspecting a payload.
    /// - Parameter generation: Owner-known join generation captured before routing the event.
    /// - Throws: `staleGeneration` for a mismatch, otherwise `closed` after invalidation.
    private func validate(_ generation: UInt64) throws {
        guard generation == self.generation else { throw VoiceControlFailure.staleGeneration }
        guard !isInvalidated else { throw VoiceControlFailure.closed }
    }

    /// Drops all session-bearing storage while retaining public scope and generation.
    private mutating func clear() { sessionID = nil; server = nil; lastEmission = nil }

    /// Emits a complete matching pair once, retaining a single tuple for duplicate suppression.
    /// - Returns: New credentials when both halves exist and changed since emission, otherwise nil.
    /// This synchronous helper performs no credential validation beyond prior admission.
    private mutating func completed() -> VoiceConnectionCredentials? {
        guard let sessionID, let server else { return nil }
        let result = VoiceConnectionCredentials(guildID: guildID, userID: userID, channelID: channelID,
            sessionID: sessionID, token: server.token, endpoint: server.endpoint, generation: generation)
        guard result != lastEmission else { return nil }
        lastEmission = result
        return result
    }
}
