import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordVoice

/// Synthetic test verifier; it intentionally provides no MLS cryptography or production readiness.
private struct SyntheticVoiceReadiness: VoiceE2EEReadiness {
    let expectedVersion: UInt16
    let expectedIdentity: VoiceConnectionIdentity

    /// Checks the reducer's exact context arguments without performing I/O.
    /// - Parameters:
    ///   - protocolVersion: Negotiated version to compare with the synthetic fixture.
    ///   - identity: Complete session scope to compare with the synthetic fixture.
    /// - Throws: `e2eeUnavailable` when either supplied value differs from the fixture.
    func validateSession(protocolVersion: UInt16, identity: VoiceConnectionIdentity) throws {
        guard protocolVersion == expectedVersion, identity == expectedIdentity else {
            throw VoiceControlFailure.e2eeUnavailable
        }
    }
}

/// Exercises protocol transitions with synthetic complete frames and no sockets, clocks, or tasks.
@Suite("Voice protocol state")
struct VoiceStateMachineTests {
    /// Constructs a standard server JSON envelope through the public lossless parser.
    /// - Parameters:
    ///   - opcode: Server opcode, including future values.
    ///   - data: Exact synthetic body; null is retained.
    ///   - sequence: Optional sequence; zero explicitly tests wraparound.
    /// - Returns: A bounded complete frame.
    /// - Throws: Fixture serialization or frame parsing errors.
    private func frame(_ opcode: UInt8, _ data: JSONValue, sequence: UInt16? = nil) throws -> VoiceGatewayFrame {
        var object: [String: JSONValue] = ["op": voiceControlNumber(opcode), "d": data]
        if let sequence { object["seq"] = voiceControlNumber(sequence) }
        return try VoiceGatewayFrame(.text(String(decoding: JSONValue.object(object).serialized(), as: UTF8.self)))
    }

    /// Supplies bounded synthetic credentials with configurable exact identity for mismatch regressions.
    /// - Parameters:
    ///   - guildID: Guild scope, default the largest unsigned snowflake.
    ///   - userID: Account scope, default the largest unsigned snowflake minus one.
    ///   - channelID: Channel scope, default three.
    ///   - sessionID: Opaque synthetic session identifier, default synthetic-session.
    ///   - generation: Coordinator-local fence, default seven; it is not globally unique.
    /// - Returns: A bounded tuple containing no real Discord credential.
    private func credentials(guildID: UInt64 = UInt64.max, userID: UInt64 = UInt64.max - 1,
                             channelID: UInt64 = 3, sessionID: String = "synthetic-session",
                             generation: UInt64 = 7) -> VoiceConnectionCredentials {
        VoiceConnectionCredentials(guildID: GuildID(rawValue: guildID), userID: UserID(rawValue: userID),
            channelID: ChannelID(rawValue: channelID), sessionID: sessionID, token: "synthetic-token",
            endpoint: "voice.discord.media", generation: generation)
    }

    /// Constructs the authoritative 41,250-millisecond HELLO interval.
    /// - Returns: A complete server HELLO frame.
    /// - Throws: Fixture frame construction errors.
    private func hello() throws -> VoiceGatewayFrame {
        try frame(8, .object(["heartbeat_interval": voiceControlNumber(41_250)]))
    }

    /// Supplies valid UDP fields and an intentionally erroneous READY heartbeat interval.
    /// - Parameter modes: Advertised transport modes, default the required modern mode.
    /// - Returns: A maximum-width SSRC and sequence 65535 for wraparound coverage.
    /// - Throws: Fixture construction errors.
    private func ready(modes: [String] = ["aead_xchacha20_poly1305_rtpsize"]) throws -> VoiceGatewayFrame {
        try frame(2, .object(["ssrc": voiceControlNumber(UInt32.max), "ip": .string("127.0.0.1"),
            "port": voiceControlNumber(50_000), "modes": .array(modes.map(JSONValue.string)),
            "heartbeat_interval": voiceControlNumber(1)]), sequence: 65535)
    }

    /// Builds a configurable transport Session Description on wrapped sequence zero.
    /// - Parameters:
    ///   - version: DAVE version; zero is forbidden for media authorization.
    ///   - keyCount: Key-byte count, exactly 32 for a valid description.
    ///   - mode: Confirmed transport mode; it must match protocol selection.
    /// - Returns: A complete server frame with synthetic key bytes.
    /// - Throws: Fixture construction errors.
    private func description(version: UInt16 = 1, keyCount: Int = 32,
                             mode: String = "aead_xchacha20_poly1305_rtpsize") throws -> VoiceGatewayFrame {
        try frame(4, .object(["mode": .string(mode), "secret_key": .array((0..<keyCount).map(voiceControlNumber)),
            "dave_protocol_version": voiceControlNumber(version)]), sequence: 0)
    }

    /// Advances to protocol selection or suspended post-description state without authorizing media.
    /// - Parameter includeDescription: Whether to validate transport keys and DAVE version as well.
    /// - Returns: A reducer using synthetic version one and join generation seven.
    /// - Throws: Fixture or reducer failures before a test assertion.
    private func negotiated(includeDescription: Bool = true) throws -> VoiceGatewaySessionState {
        var state = try VoiceGatewaySessionState(credentials: credentials(), maximumDAVEProtocolVersion: 1)
        _ = try state.receive(hello()); _ = try state.receive(ready())
        _ = try state.selectProtocol(address: "203.0.113.1", port: 65_535)
        if includeDescription { _ = try state.receive(description()) }
        return state
    }

    /// Configuration rejects obsolete/duplicate/incomplete mode policies; initial APIs acquire no resources.
    @Test func configurationAndInitialState() throws {
        for modes in [[], ["xsalsa20_poly1305"], ["aead_aes256_gcm_rtpsize"],
            ["aead_xchacha20_poly1305_rtpsize", "aead_xchacha20_poly1305_rtpsize"]] {
            #expect(throws: VoiceControlFailure.invalidConfiguration) {
                try VoiceGatewaySessionState(credentials: credentials(), supportedModes: modes)
            }
        }
        var state = try VoiceGatewaySessionState(credentials: credentials())
        #expect(state.phase == .awaitingHello && state.lastSequence == nil && state.selectedMode == nil)
        #expect(state.heartbeatIntervalMilliseconds == nil)
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.heartbeat(nonce: 1) }
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.selectProtocol(address: "ip", port: 1) }
        #expect(throws: VoiceControlFailure.invalidTransition) {
            try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        }
        #expect(state.description == "VoiceGatewaySessionState(redacted)" && state.customMirror.children.count == 1)
        #expect(!String(reflecting: state).contains("synthetic-token"))
    }

    /// HELLO requests exact Identify data, explicitly advertises absent DAVE support, and forbids repetition.
    @Test func helloIdentify() throws {
        var state = try VoiceGatewaySessionState(credentials: credentials())
        guard case .send(let identify) = try state.receive(hello()), case .json(.object(let data)) = identify.payload else {
            Issue.record("HELLO must produce Identify"); return
        }
        #expect(identify.opcode == 0 && data["server_id"] == .string(String(UInt64.max)))
        #expect(data["user_id"] == .string(String(UInt64.max - 1)))
        #expect(data["session_id"] == .string("synthetic-session") && data["token"] == .string("synthetic-token"))
        #expect(data["max_dave_protocol_version"] == voiceControlNumber(0) && data["seq_ack"] == nil)
        #expect(state.phase == .identifying && state.heartbeatIntervalMilliseconds == 41_250)
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.receive(hello()) }
    }

    /// Full negotiation yields UDP/key effects, ignores READY's false interval, and verifies context generation.
    @Test func negotiationAndAuthorization() throws {
        var state = try VoiceGatewaySessionState(credentials: credentials(),
            supportedModes: ["aead_aes256_gcm_rtpsize", "aead_xchacha20_poly1305_rtpsize"], maximumDAVEProtocolVersion: 1)
        _ = try state.receive(hello())
        guard case .discoverUDP(let server) = try state.receive(ready(modes: ["future", "aead_aes256_gcm_rtpsize"])) else {
            Issue.record("READY must request UDP discovery"); return
        }
        #expect(server.ssrc == UInt32.max && server.ip == "127.0.0.1" && server.port == 50_000)
        #expect(server.modes == ["future", "aead_aes256_gcm_rtpsize"])
        #expect(server.description == "VoiceUDPServer(redacted)" && server.debugDescription == server.description)
        #expect(server.customMirror.children.count == 1 && !String(reflecting: server).contains("127.0.0.1"))
        #expect(!String(reflecting: VoiceGatewayEffect.discoverUDP(server)).contains("127.0.0.1"))
        #expect(state.heartbeatIntervalMilliseconds == 41_250 && state.lastSequence == 65535)
        let select = try state.selectProtocol(address: "203.0.113.1", port: 65_535)
        #expect(select.opcode == 1 && state.selectedMode == "aead_aes256_gcm_rtpsize")
        #expect(select.payload == .json(.object(["protocol": .string("udp"), "data": .object([
            "address": .string("203.0.113.1"), "port": voiceControlNumber(65_535), "mode": .string("aead_aes256_gcm_rtpsize")])])))
        guard case .configureMedia(let session) = try state.receive(description(mode: "aead_aes256_gcm_rtpsize")) else {
            Issue.record("Session Description must expose transport configuration"); return
        }
        #expect(session.secretKey == Data(0..<32) && session.daveProtocolVersion == 1)
        #expect(session.mode == "aead_aes256_gcm_rtpsize")
        #expect(session.description == "VoiceSessionDescription(redacted)" && session.customMirror.children.count == 1)
        #expect(state.phase == .awaitingE2EE && state.lastSequence == 0)
        #expect(throws: VoiceControlFailure.e2eeUnavailable) {
            try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials(generation: 8).identity))
        }
        #expect(state.phase == .awaitingE2EE)
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        #expect(state.phase == .ready)
    }

    /// Independent sessions can share a generation; every identity field must bind the E2EE backend.
    /// Mismatched guild, account, channel, session and generation contexts all preserve suspension.
    @Test func exactSessionIdentityAuthorization() throws {
        let identity = credentials().identity
        #expect(identity.guildID.rawValue == UInt64.max && identity.userID.rawValue == UInt64.max - 1)
        #expect(identity.channelID.rawValue == 3 && identity.sessionID == "synthetic-session" && identity.generation == 7)
        #expect(identity == credentials().identity && Set([identity, credentials().identity]).count == 1)
        #expect(identity.description == "VoiceConnectionIdentity(redacted)" && identity.debugDescription == identity.description)
        #expect(identity.customMirror.children.count == 1 && !String(reflecting: identity).contains("synthetic-session"))
        var state = try negotiated()
        let mismatches = [credentials(guildID: 4), credentials(userID: 4), credentials(channelID: 4),
            credentials(sessionID: "other-session"), credentials(generation: 8)]
        for other in mismatches {
            #expect(other.identity != identity)
            #expect(throws: VoiceControlFailure.e2eeUnavailable) {
                try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: other.identity))
            }
            #expect(state.phase == .awaitingE2EE)
        }
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: identity))
        #expect(state.phase == .ready)
    }

    /// Malformed/overflowing interval values never partially publish phase or sequence.
    /// - Parameter interval: Null, wrong-kind, zero, negative, overflow, fraction, or exponent value.
    @Test(arguments: [JSONValue.null, .bool(true), .string("1000"), voiceControlNumber(0), voiceControlNumber(-1),
        voiceControlNumber(UInt64.max), .number(try! JSONNumber(rawValue: "1.0")), .number(try! JSONNumber(rawValue: "1e3"))])
    func invalidHello(interval: JSONValue) throws {
        var state = try VoiceGatewaySessionState(credentials: credentials())
        #expect(throws: VoiceControlFailure.invalidPayload) {
            try state.receive(frame(8, .object(["heartbeat_interval": interval]), sequence: 99))
        }
        #expect(state.phase == .awaitingHello && state.lastSequence == nil && state.heartbeatIntervalMilliseconds == nil)
    }

    /// Invalid UDP/mode fields and discovered addresses preserve the last valid handshake phase.
    @Test func invalidReadyAndSelection() throws {
        var state = try VoiceGatewaySessionState(credentials: credentials())
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.receive(ready()) }
        _ = try state.receive(hello())
        #expect(throws: VoiceControlFailure.unsupportedEncryption) { try state.receive(ready(modes: ["xsalsa20_poly1305"])) }
        for data in [JSONValue.null, .object(["ssrc": voiceControlNumber(1)]),
            .object(["ssrc": voiceControlNumber(1), "port": voiceControlNumber(0), "ip": .string("ip"), "modes": .array([])]),
            .object(["ssrc": voiceControlNumber(1), "port": voiceControlNumber(1), "ip": .string("ip"), "modes": .array([.null])])] {
            #expect(throws: VoiceControlFailure.invalidPayload) { try state.receive(frame(2, data)) }
            #expect(state.phase == .identifying && state.lastSequence == nil)
        }
        _ = try state.receive(ready())
        #expect(throws: VoiceControlFailure.invalidPayload) { try state.selectProtocol(address: "", port: 1) }
        #expect(throws: VoiceControlFailure.invalidPayload) { try state.selectProtocol(address: "ip", port: 0) }
        #expect(throws: VoiceControlFailure.invalidPayload) { try state.selectProtocol(address: String(repeating: "a", count: 256), port: 1) }
        #expect(state.phase == .awaitingProtocolSelection)
        _ = try state.selectProtocol(address: String(repeating: "a", count: 255), port: 1)
        #expect(state.phase == .awaitingSessionDescription)
    }

    /// Session Description requires the selected mode, exactly 32 byte-valued keys, and supported nonzero DAVE.
    @Test func invalidSessionDescription() throws {
        var state = try negotiated(includeDescription: false)
        for invalid in [try description(keyCount: 31), try description(keyCount: 33), try description(mode: "aead_aes256_gcm_rtpsize"),
            try frame(4, .object(["mode": .string("aead_xchacha20_poly1305_rtpsize"),
                "secret_key": .array(Array(repeating: voiceControlNumber(256), count: 32)), "dave_protocol_version": voiceControlNumber(1)]))] {
            #expect(throws: VoiceControlFailure.invalidPayload) { try state.receive(invalid) }
            #expect(state.phase == .awaitingSessionDescription && state.negotiatedDAVEVersion == nil)
        }
        #expect(throws: VoiceControlFailure.e2eeRequired) { try state.receive(description(version: 0)) }
        #expect(throws: VoiceControlFailure.e2eeUnavailable) { try state.receive(description(version: 2)) }
        var unavailable = try VoiceGatewaySessionState(credentials: credentials())
        _ = try unavailable.receive(hello()); _ = try unavailable.receive(ready())
        _ = try unavailable.selectProtocol(address: "ip", port: 1)
        #expect(throws: VoiceControlFailure.e2eeUnavailable) { try unavailable.receive(description()) }
        #expect(unavailable.phase == .awaitingSessionDescription)
    }

    /// Heartbeats preserve UInt64 nonces, retain debt on invalid ACK, and acknowledge wrapped sequences.
    @Test func heartbeatACKAndSequenceWrap() throws {
        var initial = try VoiceGatewaySessionState(credentials: credentials())
        _ = try initial.receive(hello())
        #expect(try initial.heartbeat(nonce: UInt64.max).payload == .json(.object([
            "t": voiceControlNumber(UInt64.max), "seq_ack": voiceControlNumber(-1)])))
        #expect(throws: VoiceControlFailure.heartbeatPending) { try initial.heartbeat(nonce: 0) }
        #expect(throws: VoiceControlFailure.invalidHeartbeatACK) {
            try initial.receive(frame(6, .object(["t": voiceControlNumber(0)]), sequence: 99))
        }
        #expect(initial.pendingHeartbeatNonce == UInt64.max && initial.lastSequence == nil)
        #expect(try initial.receive(frame(6, .object(["t": voiceControlNumber(UInt64.max)]))) == .none)
        #expect(initial.pendingHeartbeatNonce == nil)
        #expect(throws: VoiceControlFailure.invalidHeartbeatACK) {
            try initial.receive(frame(6, .object(["t": voiceControlNumber(UInt64.max)])))
        }
        var state = try negotiated()
        #expect(try state.heartbeat(nonce: 0).payload == .json(.object([
            "t": voiceControlNumber(0), "seq_ack": voiceControlNumber(0)])))
        _ = try state.receive(frame(6, .object(["t": voiceControlNumber(0)])))
        let future = try frame(250, .null, sequence: 65535)
        #expect(try state.receive(future) == .event(future))
        _ = try state.receive(frame(250, .null, sequence: 0))
        #expect(state.lastSequence == 0)
    }

    /// Missing ACK clears debt and resumes using the last sequence; repeated resume loss preserves phase.
    @Test func deadlineAndBufferedResume() throws {
        var state = try negotiated()
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        try state.heartbeatDeadlineElapsed()
        #expect(state.phase == .ready)
        _ = try state.heartbeat(nonce: 10)
        #expect(throws: VoiceControlFailure.missedHeartbeatACK) { try state.heartbeatDeadlineElapsed() }
        #expect(state.phase == .reconnecting && state.pendingHeartbeatNonce == nil && state.heartbeatIntervalMilliseconds == nil)
        state.connectionLost()
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.heartbeat(nonce: 20) }
        guard case .send(let resume) = try state.receive(hello()), case .json(.object(let data)) = resume.payload else {
            Issue.record("Established session must request Resume"); return
        }
        #expect(resume.opcode == 7 && data["seq_ack"] == voiceControlNumber(0))
        #expect(data["user_id"] == nil && data["max_dave_protocol_version"] == nil)
        state.connectionLost(); _ = try state.receive(hello())
        #expect(try state.receive(frame(9, .null)) == .none)
        #expect(state.phase == .awaitingE2EE)
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        #expect(state.phase == .ready)
    }

    /// Incomplete handshakes reconnect through Identify and reset sequences before a new session.
    @Test func incompleteHandshakeCannotResume() throws {
        var state = try VoiceGatewaySessionState(credentials: credentials(), maximumDAVEProtocolVersion: 1)
        state.connectionLost()
        guard case .send(let first) = try state.receive(hello()) else { Issue.record("Expected Identify"); return }
        #expect(first.opcode == 0)
        _ = try state.receive(ready()); state.connectionLost()
        guard case .send(let second) = try state.receive(hello()) else { Issue.record("Expected Identify"); return }
        #expect(second.opcode == 0 && state.lastSequence == nil && state.selectedMode == nil)
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.receive(frame(9, .null)) }
    }

    /// Every server DAVE opcode suspends media and is surfaced unchanged to the external backend.
    /// - Parameter opcode: Each documented server JSON/binary DAVE opcode.
    @Test(arguments: [UInt8(21), 22, 24, 25, 27, 29, 30])
    func daveAlwaysSuspends(opcode: UInt8) throws {
        var state = try negotiated()
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        let control: VoiceGatewayFrame
        if (25...30).contains(opcode) { control = try VoiceGatewayFrame(.binary(Data([0, 1, opcode, 0xA5]))) }
        else { control = try frame(opcode, .object(["protocol_version": voiceControlNumber(1)]), sequence: 1) }
        #expect(try state.receive(control) == .processE2EE(control))
        #expect(state.phase == .awaitingE2EE && state.lastSequence == 1)
        #expect(throws: VoiceControlFailure.e2eeUnavailable) {
            try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 2, expectedIdentity: credentials().identity))
        }
        #expect(state.phase == .awaitingE2EE)
    }

    /// Failed DAVE downgrade/new/malformed versions revoke prior media authorization permanently.
    /// - Parameter version: Unsafe protocol-version field; the reducer must close on rejection.
    @Test(arguments: [JSONValue.null, .string("1"), voiceControlNumber(0), voiceControlNumber(2)])
    func daveFailureCloses(version: JSONValue) throws {
        var state = try negotiated()
        try state.authorizeMedia(using: SyntheticVoiceReadiness(expectedVersion: 1, expectedIdentity: credentials().identity))
        #expect(throws: (any Error).self) { try state.receive(frame(21, .object(["protocol_version": version]), sequence: 2)) }
        #expect(state.phase == .closed && state.lastSequence == nil && state.negotiatedDAVEVersion == nil)
    }

    /// Future events remain observable, client-only frames fail, and close is terminal/idempotent.
    @Test func futureEventsDirectionAndClose() throws {
        var state = try negotiated()
        let unknown = try frame(240, .object(["future": .null]))
        #expect(try state.receive(unknown) == .event(unknown))
        #expect(throws: VoiceControlFailure.invalidPayload) { try state.receive(VoiceGatewayFrame(opcode: 0, data: .null)) }
        _ = try state.heartbeat(nonce: 99)
        state.close(); state.close(); state.connectionLost()
        #expect(state.phase == .closed && state.lastSequence == nil && state.selectedMode == nil)
        #expect(state.pendingHeartbeatNonce == nil && state.heartbeatIntervalMilliseconds == nil)
        #expect(throws: VoiceControlFailure.closed) { try state.receive(unknown) }
        #expect(throws: VoiceControlFailure.invalidTransition) { try state.heartbeat(nonce: 1) }
    }
}
