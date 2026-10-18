import DiscordCore
import Foundation

/// Explicit phases of the deterministic Voice v8 protocol reducer; no phase owns a task/socket.
public enum VoiceGatewayPhase: Sendable, Equatable {
    case awaitingHello, identifying, awaitingProtocolSelection, awaitingSessionDescription
    case awaitingE2EE, ready, reconnecting, resuming, closed
}

/// An injected DAVE backend's synchronous authorization boundary, not an MLS implementation.
/// A conformer must verify active epoch, expected membership/external sender, exact session identity,
/// supported protocol version, and completed transitions before authorizing media. Checking only
/// a nonempty key, marker byte, boolean, or advertised protocol version is insufficient.
/// No conforming production backend is shipped with this initial protocol slice.
public protocol VoiceE2EEReadiness: Sendable {
    /// Verifies that an actual DAVE context can currently protect media for this exact session.
    /// - Parameters:
    ///   - protocolVersion: Nonzero negotiated DAVE version; transport-only version zero is forbidden.
    ///   - identity: Exact guild/account/channel/session/generation scope of the matched join.
    ///     Compare the entire value with the backend's current context; generations alone can
    ///     coincide across independent joins. This value deliberately excludes tokens/endpoints.
    /// - Throws: A sanitized error if epoch, membership, external sender, version, transition,
    ///   key validity, or exact identity cannot be established. Implementations must not perform
    ///   blocking I/O or log cryptographic/session material. Success does not itself send media.
    func validateSession(protocolVersion: UInt16, identity: VoiceConnectionIdentity) throws
}

/// Validated Voice Ready fields needed by an injected UDP discovery/transport owner.
public struct VoiceUDPServer: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public let ssrc: UInt32
    public let ip: String
    public let port: UInt16
    public let modes: [String]

    /// Redacts the server's network address and associated negotiated transport fields.
    public var description: String { "VoiceUDPServer(redacted)" }

    /// Uses redacted formatting for explicit debug interpolation of a discovery effect.
    public var debugDescription: String { description }

    /// Prevents reflective diagnostics from expanding the server's IP address.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated transport Session Description; the key must never be logged or persisted here.
/// DAVE frame encryption is separate and remains required before media authorization.
public struct VoiceSessionDescription: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public let mode: String
    public let secretKey: Data
    public let daveProtocolVersion: UInt16

    /// Redacts transport keys and all session description fields in generic diagnostics.
    public var description: String { "VoiceSessionDescription(redacted)" }

    /// Prevents reflection from exposing transport encryption material.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Effects requested by the pure reducer; the caller owns execution, scheduling, and cleanup.
/// Incoming DAVE bytes are surfaced without MLS interpretation and always suspend media first.
public enum VoiceGatewayEffect: Sendable, Equatable {
    case none
    case send(VoiceGatewayFrame)
    case discoverUDP(VoiceUDPServer)
    case configureMedia(VoiceSessionDescription)
    case processE2EE(VoiceGatewayFrame)
    case event(VoiceGatewayFrame)
}

/// Pure bounded Voice Gateway v8 handshake, heartbeat, and buffered-resume bookkeeping.
/// This reducer never connects, schedules heartbeats, encrypts media, processes MLS, or retries.
/// Callers serialize inputs in socket order and use their own bounded clock/transport ownership.
/// Required transport XChaCha20-Poly1305 and preferred AES256-GCM RTP-size modes are the only
/// selectable modes. Version zero DAVE and unverified E2EE contexts fail closed.
/// https://docs.discord.com/developers/topics/voice-connections (verified 2026-10-17).
public struct VoiceGatewaySessionState: Sendable, CustomStringConvertible, CustomReflectable {
    public private(set) var phase: VoiceGatewayPhase = .awaitingHello
    /// HELLO's authoritative interval, in milliseconds; erroneous READY intervals are ignored.
    public private(set) var heartbeatIntervalMilliseconds: UInt32?
    /// Last server sequence in delivery order, including wrap to zero; nil before the first.
    public private(set) var lastSequence: UInt16?
    public private(set) var selectedMode: String?
    public private(set) var negotiatedDAVEVersion: UInt16?
    public private(set) var pendingHeartbeatNonce: UInt64?
    private let credentials: VoiceConnectionCredentials
    private let supportedModes: [String]
    private let maximumDAVEProtocolVersion: UInt16
    private var offeredModes: [String] = []
    private var retainedPhase: VoiceGatewayPhase?

    /// Creates an idle protocol reducer from freshly matched credentials without any I/O.
    /// - Parameters:
    ///   - credentials: Current join result; discard this reducer on channel/server replacement.
    ///   - supportedModes: Implemented transport modes in preference order, default XChaCha20.
    ///     Only current RTP-size AEAD modes are accepted; duplicates and an empty list are invalid.
    ///     Discord's required XChaCha20-Poly1305 mode must be present, even when AES is preferred.
    ///   - maximumDAVEProtocolVersion: Highest version genuinely supported by the injected backend,
    ///     default zero when absent; advertising a positive value does not implement DAVE.
    /// - Throws: `invalidConfiguration` for empty, duplicate, or obsolete transport-mode policies.
    public init(credentials: VoiceConnectionCredentials,
                supportedModes: [String] = ["aead_xchacha20_poly1305_rtpsize"],
                maximumDAVEProtocolVersion: UInt16 = 0) throws {
        let current = Set(["aead_aes256_gcm_rtpsize", "aead_xchacha20_poly1305_rtpsize"])
        guard supportedModes.contains("aead_xchacha20_poly1305_rtpsize"),
              Set(supportedModes).count == supportedModes.count,
              supportedModes.allSatisfy(current.contains) else { throw VoiceControlFailure.invalidConfiguration }
        self.credentials = credentials; self.supportedModes = supportedModes
        self.maximumDAVEProtocolVersion = maximumDAVEProtocolVersion
    }

    /// Processes one validated server frame atomically on ordinary payload failures.
    /// - Parameter frame: Server-to-client frame delivered in socket order. Client-only opcodes,
    ///   malformed control fields, and invalid phase edges are rejected without state mutation.
    /// - Returns: A transport-neutral effect. HELLO requests Identify/Resume; READY requests UDP
    ///   discovery; Session Description requests key installation but does not authorize media.
    /// - Throws: `VoiceControlFailure` for invalid fields/edges/modes/E2EE. A malformed present
    ///   DAVE protocol-version field, downgrade to zero, or version change closes the reducer.
    ///   Callers must terminate or rejoin on errors rather than silently passing through audio.
    /// Sequence values replace the last observation in arrival order, never numeric-max order.
    public mutating func receive(_ frame: VoiceGatewayFrame) throws -> VoiceGatewayEffect {
        guard phase != .closed else { throw VoiceControlFailure.closed }
        if let opcode = VoiceGatewayOpcode(rawValue: frame.opcode), !opcode.isServerSent {
            throw VoiceControlFailure.invalidPayload
        }
        var next = self
        let result: VoiceGatewayEffect
        do { result = try next.consume(frame) }
        catch {
            // Even a malformed/unsupported transition invalidates previously authorized media.
            if (21...31).contains(frame.opcode) { close() }
            throw error
        }
        if let sequence = frame.sequence { next.lastSequence = sequence }
        self = next
        return result
    }

    /// Selects an implemented current transport mode after injected UDP discovery completes.
    /// - Parameters:
    ///   - address: Nonempty public IP discovered by the UDP owner; at most 255 UTF-8 bytes.
    ///     Syntax/authenticity validation is the injected transport owner's responsibility.
    ///   - port: Nonzero externally discovered UDP port, in host byte order.
    /// - Returns: Voice opcode 1 with exact UDP address/port and the first mutually supported mode.
    /// - Throws: `invalidTransition` outside post-READY selection, `invalidPayload` for an empty/
    ///   oversized address or zero port, `unsupportedEncryption` when no modern mode intersects.
    public mutating func selectProtocol(address: String, port: UInt16) throws -> VoiceGatewayFrame {
        guard phase == .awaitingProtocolSelection else { throw VoiceControlFailure.invalidTransition }
        guard !address.isEmpty, address.utf8.count <= 255, port > 0 else { throw VoiceControlFailure.invalidPayload }
        guard let mode = supportedModes.first(where: offeredModes.contains) else {
            throw VoiceControlFailure.unsupportedEncryption
        }
        let frame = try VoiceGatewayFrame(opcode: 1, data: .object(["protocol": .string("udp"),
            "data": .object(["address": .string(address), "port": voiceControlNumber(port), "mode": .string(mode)])]))
        selectedMode = mode; phase = .awaitingSessionDescription
        return frame
    }

    /// Builds one v8 heartbeat after HELLO; the owner schedules it at the advertised interval.
    /// - Parameter nonce: Owner-generated integer echoed by ACK; no wall-clock assumption is made.
    /// - Returns: Opcode 3 containing exact `t` and `seq_ack`, using -1 before any numbered frame.
    /// - Throws: `invalidTransition` before HELLO, while disconnected, or after close;
    ///   `heartbeatPending` when the preceding heartbeat lacks a matching ACK. No queue is created.
    public mutating func heartbeat(nonce: UInt64) throws -> VoiceGatewayFrame {
        guard heartbeatIntervalMilliseconds != nil, phase != .closed, phase != .reconnecting,
              phase != .awaitingHello else { throw VoiceControlFailure.invalidTransition }
        guard pendingHeartbeatNonce == nil else { throw VoiceControlFailure.heartbeatPending }
        let frame = try VoiceGatewayFrame(opcode: 3, data: .object([
            "t": voiceControlNumber(nonce), "seq_ack": sequenceAcknowledgement()]))
        pendingHeartbeatNonce = nonce
        return frame
    }

    /// Detects an owner's elapsed ACK deadline without reading a real clock or sleeping.
    /// - Throws: `missedHeartbeatACK` and enters reconnecting when a nonce remains pending;
    ///   returns unchanged when no heartbeat is outstanding. The caller decides retry limits.
    public mutating func heartbeatDeadlineElapsed() throws {
        guard pendingHeartbeatNonce != nil else { return }
        connectionLost()
        throw VoiceControlFailure.missedHeartbeatACK
    }

    /// Suspends media and retains handshake state/sequence for an explicitly resumable socket loss.
    /// Repeated loss notifications preserve the original phase. ACK debt and HELLO interval are
    /// cleared; the next HELLO requests Resume. A closed reducer remains closed. The owner must
    /// discard this value if the peer invalidated its session or the adapter cannot retain resume.
    public mutating func connectionLost() {
        guard phase != .closed, phase != .reconnecting else { return }
        if phase != .resuming { retainedPhase = phase }
        phase = .reconnecting
        pendingHeartbeatNonce = nil; heartbeatIntervalMilliseconds = nil
    }

    /// Revokes media authorization on an authenticated membership change without losing transport state.
    /// Calling this while already suspended or during initial handshake is harmless. A closed or
    /// reconnecting owner remains in its current phase; it never becomes ready through this method.
    /// Heartbeat debt, server sequence, transport selection and negotiated version are retained.
    /// The actual DAVE owner must revalidate membership/epoch before `authorizeMedia(using:)` succeeds.
    /// - Throws: `closed` after terminal cleanup; no other phase or counter is modified on failure.
    public mutating func suspendMedia() throws {
        guard phase != .closed else { throw VoiceControlFailure.closed }
        if phase == .ready { phase = .awaitingE2EE }
    }

    /// Merges a backend-authorized copy without overwriting control state advanced during suspension.
    /// - Parameter authorized: Same exact session/version reducer returned by the injected backend.
    /// - Throws: `e2eeUnavailable` for a wrong identity, version, mode or nonready copy;
    ///   `invalidTransition` unless this current reducer is still awaiting E2EE. Success changes
    ///   only phase, preserving current heartbeat debt, interval and last-arrival sequence.
    mutating func acceptAuthorization(from authorized: Self) throws {
        guard phase == .awaitingE2EE else { throw VoiceControlFailure.invalidTransition }
        guard authorized.phase == .ready, authorized.credentials.identity == credentials.identity,
              authorized.negotiatedDAVEVersion == negotiatedDAVEVersion,
              authorized.selectedMode == selectedMode else { throw VoiceControlFailure.e2eeUnavailable }
        phase = .ready
    }

    /// Authorizes media only after an injected backend verifies real DAVE epoch/membership state.
    /// - Parameter context: A backend matching this exact guild/account/channel/session/generation
    ///   identity and negotiated protocol context. A matching generation alone is insufficient.
    /// - Throws: `invalidTransition` unless media is suspended awaiting E2EE; `e2eeUnavailable`
    ///   for a missing supported version; or the backend's sanitized validation error. Failure
    ///   preserves suspension. This initial reducer supports reauthorization of the negotiated
    ///   version only; a protocol-version change requires replacing the session reducer.
    public mutating func authorizeMedia(using context: any VoiceE2EEReadiness) throws {
        guard phase == .awaitingE2EE else { throw VoiceControlFailure.invalidTransition }
        guard let version = negotiatedDAVEVersion, version > 0,
              version <= maximumDAVEProtocolVersion else { throw VoiceControlFailure.e2eeUnavailable }
        try context.validateSession(protocolVersion: version, identity: credentials.identity)
        phase = .ready
    }

    /// Ends this reducer idempotently and discards control state; no socket or backend is owned.
    /// The immutable credentials remain retained until this value is released by its owner.
    public mutating func close() {
        phase = .closed; pendingHeartbeatNonce = nil; heartbeatIntervalMilliseconds = nil
        lastSequence = nil; selectedMode = nil; negotiatedDAVEVersion = nil
        offeredModes = []; retainedPhase = nil
    }

    /// Redacts retained credentials and control payloads during ordinary diagnostics.
    public var description: String { "VoiceGatewaySessionState(redacted)" }

    /// Prevents reflective traversal of retained credentials.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Reduces validated server controls on a temporary value before atomic publication.
    /// - Parameter frame: Direction-checked frame; raw future messages become an event effect.
    /// - Returns: Exactly one owner effect without executing it or allocating an event queue.
    /// - Throws: Sanitized control/transition failures; a rejected frame never updates sequence.
    private mutating func consume(_ frame: VoiceGatewayFrame) throws -> VoiceGatewayEffect {
        if (21...31).contains(frame.opcode) {
            guard phase == .ready || phase == .awaitingE2EE || phase == .identifying ||
                  phase == .awaitingProtocolSelection || phase == .awaitingSessionDescription else {
                throw VoiceControlFailure.invalidTransition
            }
            if phase == .ready { phase = .awaitingE2EE }
            if case .json(.object(let object)) = frame.payload, let value = object["protocol_version"] {
                guard case .number(let number) = value, let version = UInt16(number.rawValue),
                      version > 0 else { throw VoiceControlFailure.e2eeRequired }
                guard version <= maximumDAVEProtocolVersion,
                      negotiatedDAVEVersion == nil || version == negotiatedDAVEVersion else { throw VoiceControlFailure.e2eeUnavailable }
            }
            return .processE2EE(frame)
        }
        switch frame.opcode {
        case 8:
            guard phase == .awaitingHello || phase == .reconnecting else { throw VoiceControlFailure.invalidTransition }
            let object = try jsonObject(frame)
            let interval: UInt32 = try integer(object["heartbeat_interval"])
            guard interval > 0 else { throw VoiceControlFailure.invalidPayload }
            heartbeatIntervalMilliseconds = interval
            let resuming = phase == .reconnecting && (retainedPhase == .ready || retainedPhase == .awaitingE2EE)
            phase = resuming ? .resuming : .identifying
            if !resuming {
                lastSequence = nil; selectedMode = nil; negotiatedDAVEVersion = nil
                offeredModes = []; retainedPhase = nil
            }
            var data: [String: JSONValue] = ["server_id": .string(credentials.guildID.description),
                "session_id": .string(credentials.sessionID), "token": .string(credentials.token)]
            if resuming { data["seq_ack"] = sequenceAcknowledgement() }
            else {
                data["user_id"] = .string(credentials.userID.description)
                data["max_dave_protocol_version"] = voiceControlNumber(maximumDAVEProtocolVersion)
            }
            return .send(try VoiceGatewayFrame(opcode: resuming ? 7 : 0, data: .object(data)))
        case 6:
            let object = try jsonObject(frame)
            let nonce: UInt64 = try integer(object["t"])
            guard nonce == pendingHeartbeatNonce else { throw VoiceControlFailure.invalidHeartbeatACK }
            pendingHeartbeatNonce = nil
            return .none
        case 2:
            guard phase == .identifying else { throw VoiceControlFailure.invalidTransition }
            let object = try jsonObject(frame)
            let ssrc: UInt32 = try integer(object["ssrc"])
            let port: UInt16 = try integer(object["port"])
            guard case .string(let ip) = object["ip"], !ip.isEmpty, ip.utf8.count <= 255,
                  port > 0, case .array(let values) = object["modes"], values.count <= 32 else {
                throw VoiceControlFailure.invalidPayload
            }
            let modes = try values.map { value -> String in
                guard case .string(let mode) = value, !mode.isEmpty, mode.utf8.count <= 128 else {
                    throw VoiceControlFailure.invalidPayload
                }
                return mode
            }
            guard supportedModes.contains(where: modes.contains) else { throw VoiceControlFailure.unsupportedEncryption }
            offeredModes = modes; phase = .awaitingProtocolSelection
            return .discoverUDP(VoiceUDPServer(ssrc: ssrc, ip: ip, port: port, modes: modes))
        case 4:
            guard phase == .awaitingSessionDescription else { throw VoiceControlFailure.invalidTransition }
            let object = try jsonObject(frame)
            guard case .string(let mode) = object["mode"], mode == selectedMode,
                  case .array(let values) = object["secret_key"], values.count == 32 else {
                throw VoiceControlFailure.invalidPayload
            }
            let key = try Data(values.map { value -> UInt8 in try integer(value) })
            let version: UInt16 = try integer(object["dave_protocol_version"])
            guard version > 0 else { throw VoiceControlFailure.e2eeRequired }
            guard version <= maximumDAVEProtocolVersion else { throw VoiceControlFailure.e2eeUnavailable }
            negotiatedDAVEVersion = version; phase = .awaitingE2EE
            return .configureMedia(VoiceSessionDescription(mode: mode, secretKey: key, daveProtocolVersion: version))
        case 9:
            guard phase == .resuming, let retainedPhase else { throw VoiceControlFailure.invalidTransition }
            // Resumption never restores prior authorization without revalidating the E2EE backend.
            phase = retainedPhase == .ready ? .awaitingE2EE : retainedPhase
            self.retainedPhase = nil
            return .none
        default: return .event(frame)
        }
    }

    /// Reads an object body without converting exact JSON number lexemes.
    /// - Parameter frame: Control frame whose documented `d` must be an object.
    /// - Returns: The immutable object sharing the frame's bounded storage.
    /// - Throws: `invalidPayload` for binary, scalar, null, or array data.
    private func jsonObject(_ frame: VoiceGatewayFrame) throws -> [String: JSONValue] {
        guard case .json(.object(let object)) = frame.payload else { throw VoiceControlFailure.invalidPayload }
        return object
    }

    /// Projects a bounded unsigned control integer, rejecting fraction/exponent/null spellings.
    /// - Parameter value: Present exact JSON integer number, never a numeric string or boolean.
    /// - Returns: A value representable by the inferred unsigned integer type.
    /// - Throws: `invalidPayload` for missing, wrong-kind, fractional, negative, or overflowing values.
    private func integer<T: FixedWidthInteger & UnsignedInteger>(_ value: JSONValue?) throws -> T {
        guard case .number(let number) = value, let result = T(number.rawValue) else {
            throw VoiceControlFailure.invalidPayload
        }
        return result
    }

    /// Encodes the last server sequence verbatim, using Discord's -1 sentinel before any message.
    /// - Returns: Exact numeric `seq_ack`, preserving sequence wrap rather than a numeric maximum.
    private func sequenceAcknowledgement() -> JSONValue {
        lastSequence.map(voiceControlNumber) ?? voiceControlNumber(-1)
    }
}
