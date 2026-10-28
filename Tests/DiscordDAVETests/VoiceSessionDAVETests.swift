// File: Tests/DiscordDAVETests/VoiceSessionDAVETests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordCore
import DiscordMLS
import DiscordMedia
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import DiscordVoiceCodecs
import DiscordVoiceCrypto
import Foundation
import Testing
@testable import DiscordDAVE
@testable import DiscordVoice

/// Supervised adapter composition over real MLS/DAVE peers and synthetic Voice controls.
/// No Discord connection, audio hardware, native codec interoperability, or audit is claimed.
@Suite struct VoiceSessionDAVETests {
    private struct Pair: Sendable {
        let first: DAVEVoiceSession
        let second: DAVEVoiceSession
        let firstCredentials: VoiceConnectionCredentials
        let secondCredentials: VoiceConnectionCredentials
    }

    private enum Outcome: Sendable {
        case frame(Data), failure(DAVESessionError), cancelled, unexpected
    }

    /// Creates one exact synthetic account/guild/channel/session/generation tuple.
    /// - Parameter userID: Nonzero participant identifier.
    /// - Returns: Test-only Voice credentials; no authenticated request occurs.
    private func credentials(_ userID: UInt64) -> VoiceConnectionCredentials {
        .init(guildID: GuildID(rawValue: 5), userID: UserID(rawValue: userID), channelID: ChannelID(rawValue: 6),
              sessionID: "synthetic-\(userID)", token: "synthetic-token", endpoint: "voice.discord.media", generation: 1)
    }

    /// Builds a complete server JSON control using exact unsigned numeric spellings.
    /// - Parameters:
    ///   - opcode: Documented Voice server opcode.
    ///   - fields: Bounded data object for that opcode.
    /// - Returns: Direction-validated Voice control.
    /// - Throws: JSON or Voice structural failures.
    private func json(_ opcode: UInt8, _ fields: [String: JSONValue]) throws -> VoiceGatewayFrame {
        let value = try JSONValue.object(["op": .number(JSONNumber(rawValue: String(opcode))), "d": .object(fields)]).serialized()
        return try VoiceGatewayFrame(.text(String(decoding: value, as: UTF8.self)))
    }

    /// Adds exact server sequence/opcode framing around an MLS/DAVE payload.
    /// - Parameters:
    ///   - opcode: Server binary opcode.
    ///   - body: Complete body excluding the sequence and opcode.
    /// - Returns: Server-direction parsed frame with a synthetic sequence of one.
    /// - Throws: Voice framing failures.
    private func binary(_ opcode: UInt8, _ body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([0, 1, opcode]) + body))
    }

    /// Creates an inert adapter with a real independent signing key and synthetic clock.
    /// - Parameters:
    ///   - userID: Participant account used by the exact Voice identity.
    ///   - sender: Trusted external sender shared by peers in this fixture.
    ///   - maximumParticipants: Member/source budget, default four.
    ///   - maximumPendingOperations: Suspended-operation budget, default 64.
    /// - Returns: An inert owner; the clock always returns monotonic time ten.
    /// - Throws: Key or adapter configuration failures.
    private func owner(_ userID: UInt64, sender: MLSExternalSender, maximumParticipants: Int = 4,
                       maximumPendingOperations: Int = 64) throws -> DAVEVoiceSession {
        try DAVEVoiceSession(identity: credentials(userID).identity, groupID: Data([0, 0, 0, 0, 0, 0, 0, 6]),
            signaturePrivateKey: P256.Signing.PrivateKey(compactRepresentable: false).rawRepresentation,
            externalSender: sender, maximumParticipants: maximumParticipants,
            maximumPendingOperations: maximumPendingOperations, now: { 10 })
    }

    /// Starts one adapter and supplies authenticated membership/external-sender controls.
    /// - Parameters:
    ///   - owner: Inert owner to start once.
    ///   - sender: Expected trusted external sender.
    /// - Returns: The public signed KeyPackage, with private keys retained by the owner.
    /// - Throws: Signaling, key-package, or fixture assertion failures.
    private func initialize(_ owner: DAVEVoiceSession, sender: MLSExternalSender) async throws -> MLSKeyPackage {
        let result = try await owner.start(protocolVersion: 1)
        #expect(result.map(\.opcode) == [26])
        guard case .binary(let bytes) = try #require(result.first).payload else { throw DAVESessionError.invalidMessage }
        let package = try MLSKeyPackage.decode(bytes, messageWrapped: false)
        #expect(try await owner.receive(json(11, ["user_ids": .array([.string("1"), .string("2")])]), now: 0).isEmpty)
        #expect(try await owner.receive(binary(25, sender.encoded()), now: 0).isEmpty)
        return package
    }

    /// Establishes two real MLS members through the production supervised adapter.
    /// Both sides select a real commit/Welcome, acknowledge, explicitly execute,
    /// then install authenticated local/remote audio SSRC bindings.
    /// - Parameter maximumPendingOperations: Queue budget used to exercise saturation.
    /// - Returns: Established independently owned peers and their exact Voice credentials.
    /// - Throws: MLS, signaling, adapter, or fixture assertion failures; owners close on error.
    private func established(maximumPendingOperations: Int = 64) async throws -> Pair {
        let externalKey = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: externalKey.publicKey.x963Representation,
            credential: MLSCredential(identity: Data("synthetic-external-sender".utf8)))
        let first = try owner(1, sender: sender, maximumPendingOperations: maximumPendingOperations)
        let second = try owner(2, sender: sender, maximumPendingOperations: maximumPendingOperations)
        do {
            _ = try await initialize(first, sender: sender)
            let package = try await initialize(second, sender: sender)
            let proposal = try MLSProposal.add(package).externalMessage(groupID: Data([0, 0, 0, 0, 0, 0, 0, 6]),
                epoch: 0, signaturePrivateKey: externalKey.rawRepresentation)
            var envelope = MLSWriter(); envelope.write(UInt8(0)); try envelope.writeVector(proposal)
            let commands = try await first.receive(binary(27, envelope.data), now: 1)
            #expect(commands.map(\.opcode) == [28])
            guard case .binary(let bytes) = try #require(commands.first).payload else { throw DAVESessionError.invalidMessage }
            let candidate = try MLSTentativeCommit.decodeDAVECommitWelcome(bytes)
            let welcome = try #require(candidate.welcome)
            #expect(try await first.receive(binary(29, Data([0, 7]) + candidate.commit), now: 1).map(\.opcode) == [23])
            #expect(try await second.receive(binary(30, Data([0, 7]) + welcome.dropFirst(4)), now: 1).map(\.opcode) == [23])
            for peer in [first, second] {
                #expect(try await peer.receive(json(22, ["transition_id": .number(JSONNumber(rawValue: "7"))]), now: 1).isEmpty)
                try await peer.bindSSRC(111, userID: UserID(rawValue: 1))
                try await peer.bindSSRC(222, userID: UserID(rawValue: 2))
            }
            return .init(first: first, second: second, firstCredentials: credentials(1), secondCredentials: credentials(2))
        } catch { await first.close(); await second.close(); throw error }
    }

    /// Creates the real deterministic Voice reducer awaiting exact DAVE authorization.
    /// - Parameter credentials: Exact adapter identity, or deliberately mismatched scope.
    /// - Returns: A reducer in awaitingE2EE, after transport Session Description.
    /// - Throws: JSON, framing, or Voice-state failures.
    private func suspended(_ credentials: VoiceConnectionCredentials) throws -> VoiceGatewaySessionState {
        var state = try VoiceGatewaySessionState(credentials: credentials, maximumDAVEProtocolVersion: 1)
        _ = try state.receive(json(8, ["heartbeat_interval": .number(JSONNumber(rawValue: "1000"))]))
        _ = try state.receive(json(2, ["ssrc": .number(JSONNumber(rawValue: "111")), "ip": .string("127.0.0.1"),
            "port": .number(JSONNumber(rawValue: "50000")), "modes": .array([.string("aead_xchacha20_poly1305_rtpsize")])]))
        _ = try state.selectProtocol(address: "127.0.0.1", port: 50000)
        _ = try state.receive(json(4, ["mode": .string("aead_xchacha20_poly1305_rtpsize"),
            "secret_key": .array(Array(repeating: .number(JSONNumber(rawValue: "1")), count: 32)),
            "dave_protocol_version": .number(JSONNumber(rawValue: "1"))]))
        #expect(state.phase == .awaitingE2EE)
        return state
    }

    /// Real two-member epoch authorization and both media directions authenticate;
    /// mismatched identities/sources, replay, tampering and plaintext silence fail.
    /// - Throws: Fixture construction or an unexpected cryptographic/adapter failure.
    @Test func epochAuthorizationAndDuplexFramesFailClosed() async throws {
        let pair = try await established()
        do {
            let waiting = try suspended(pair.firstCredentials)
            let ready = try await pair.first.authorizeGateway(waiting)
            #expect(ready.phase == .ready)
            #expect(waiting.phase == .awaitingE2EE)
            await #expect(throws: VoiceControlFailure.e2eeUnavailable) {
                try await pair.first.authorizeGateway(suspended(pair.secondCredentials))
            }
            let opus = Data([0xF8, 1, 2, 3])
            let first = try await pair.first.seal(opus, ssrc: 111)
            let second = try await pair.second.seal(opus, ssrc: 222)
            #expect(first != opus && second != opus && first != second)
            #expect(try await pair.second.open(first, ssrc: 111) == opus)
            #expect(try await pair.first.open(second, ssrc: 222) == opus)
            await #expect(throws: DAVEError.replayedFrame) { try await pair.second.open(first, ssrc: 111) }
            await #expect(throws: DAVESessionError.mediaUnavailable) { try await pair.first.seal(opus, ssrc: 222) }
            await #expect(throws: DAVESessionError.mediaUnavailable) { try await pair.second.open(first, ssrc: 999) }
            var tampered = try await pair.first.seal(opus, ssrc: 111); tampered[0] ^= 1
            await #expect(throws: DAVEError.authenticationFailed) { try await pair.second.open(tampered, ssrc: 111) }
            await #expect(throws: DAVEError.malformedFrame) {
                try await pair.second.open(Data([0xF8, 0xFF, 0xFE]), ssrc: 111)
            }
            #expect(await pair.first.snapshot().sourceCount == 2)
            await pair.second.removeParticipant(UserID(rawValue: 1))
            let later = try await pair.first.seal(opus, ssrc: 111)
            await #expect(throws: DAVESessionError.mediaUnavailable) { try await pair.second.open(later, ssrc: 111) }
        } catch { await pair.first.close(); await pair.second.close(); throw error }
        await pair.first.close(); await pair.second.close()
        #expect(await pair.first.snapshot().isClosed)
        #expect(await pair.first.snapshot().sourceCount == 0)
    }

    /// Source count remains bounded; collisions, zero accounts and rejected updates
    /// leave existing mappings intact. Same-user source replacement releases the old SSRC.
    /// - Throws: Key, source-binding, or fixture assertion failures.
    @Test func sourceBoundsReplacementAndIdempotentRemoval() async throws {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: key.publicKey.x963Representation,
            credential: MLSCredential(identity: Data([1])))
        let owner = try owner(1, sender: sender, maximumParticipants: 2)
        #expect(await owner.snapshot().sourceCount == 0)
        try await owner.bindSSRC(0, userID: UserID(rawValue: 1))
        try await owner.bindSSRC(0, userID: UserID(rawValue: 1))
        try await owner.bindSSRC(UInt32.max, userID: UserID(rawValue: 2))
        await #expect(throws: DAVESessionError.invalidMessage) { try await owner.bindSSRC(0, userID: UserID(rawValue: 2)) }
        await #expect(throws: DAVESessionError.invalidMessage) { try await owner.bindSSRC(3, userID: UserID(rawValue: 0)) }
        await #expect(throws: DAVESessionError.capacityExceeded) { try await owner.bindSSRC(3, userID: UserID(rawValue: 3)) }
        #expect(await owner.snapshot().sourceCount == 2)
        try await owner.bindSSRC(7, userID: UserID(rawValue: 1))
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await owner.seal(Data([0xF8, 1]), ssrc: 0) }
        await owner.removeParticipant(UserID(rawValue: 2)); await owner.removeParticipant(UserID(rawValue: 2))
        await owner.removeParticipant(UserID(rawValue: 99))
        try await owner.bindSSRC(0, userID: UserID(rawValue: 3))
        #expect(await owner.snapshot().sourceCount == 2)
        await owner.close()
        #expect(await owner.snapshot().sourceCount == 0)
        await #expect(throws: DAVESessionError.closed) { try await owner.bindSSRC(1, userID: UserID(rawValue: 1)) }
        await owner.removeParticipant(UserID(rawValue: 1))
        #expect(await owner.snapshot().sourceCount == 0)
    }

    /// Invalid adapter limits reject before clock work; version-zero and premature
    /// authorization/media remain fail-closed, and ordinary diagnostics hide scope.
    /// - Throws: Key or fixture setup failures.
    @Test func configurationInertConstructionAndUnavailableMedia() async throws {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: key.publicKey.x963Representation,
            credential: MLSCredential(identity: Data([1])))
        for limit in [Int.min, -1, 0, 1025, Int.max] {
            #expect(throws: DAVESessionError.invalidConfiguration) {
                try owner(1, sender: sender, maximumParticipants: limit)
            }
        }
        for limit in [Int.min, -1, 0, 1, 1025, Int.max] {
            #expect(throws: DAVESessionError.invalidConfiguration) {
                try owner(1, sender: sender, maximumPendingOperations: limit)
            }
        }
        let owner = try DAVEVoiceSession(identity: credentials(1).identity, groupID: Data([1]),
            signaturePrivateKey: key.rawRepresentation, externalSender: sender, now: {
                Issue.record("An inert adapter must not consult its media clock")
                return 0
            })
        let initial = await owner.snapshot()
        #expect(initial.sourceCount == 0 && initial.pendingOperationCount == 0 && !initial.operationIsActive && !initial.isClosed)
        #expect(String(describing: owner) == "DAVEVoiceSession([REDACTED])")
        #expect(String(reflecting: owner) == "DAVEVoiceSession([REDACTED])")
        #expect(Mirror(reflecting: owner).children.count == 1)
        try await owner.bindSSRC(1, userID: UserID(rawValue: 1))
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await owner.seal(Data([0xF8, 1]), ssrc: 1) }
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await owner.authorizeGateway(suspended(credentials(1))) }
        await #expect(throws: DAVESessionError.downgradeRejected) { try await owner.start(protocolVersion: 0) }
        async let first: Void = owner.close()
        async let second: Void = owner.close()
        _ = await (first, second)
        await owner.close()
        await #expect(throws: DAVESessionError.closed) { try await owner.start(protocolVersion: 1) }
    }

    /// Concurrent media serializes without exposing the protocol actor's overlap error;
    /// every admitted nonce is unique and cancellation leaves no retained admissions.
    /// Saturation is a bounded rejection rather than unbounded task retention.
    /// - Throws: Real MLS setup or unexpected cryptographic/adapter failures.
    @Test func concurrentMediaCancellationAndSharedCleanup() async throws {
        let pair = try await established(maximumPendingOperations: 2)
        let opus = Data([0xF8, 7, 8])
        var frames: [Data] = []
        let outcomes = await withTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            for _ in 0..<128 {
                group.addTask {
                    do { return .frame(try await pair.first.seal(opus, ssrc: 111)) }
                    catch let error as DAVESessionError { return .failure(error) }
                    catch is CancellationError { return .cancelled }
                    catch { return .unexpected }
                }
            }
            var result: [Outcome] = []
            for await outcome in group { result.append(outcome) }
            return result
        }
        #expect(outcomes.count == 128)
        for result in outcomes {
            switch result {
            case .frame(let frame): frames.append(frame)
            case .failure(let error): #expect(error == .capacityExceeded)
            case .cancelled, .unexpected: Issue.record("Uncancelled healthy media failed unexpectedly")
            }
        }
        #expect(!frames.isEmpty)
        #expect(Set(frames).count == frames.count)
        for frame in frames { #expect(try await pair.second.open(frame, ssrc: 111) == opus) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pair.first.seal(opus, ssrc: 111)
        }
        do { _ = try await cancelled.value; Issue.record("Expected cancellation before media admission") }
        catch { #expect(error is CancellationError) }
        let snapshot = await pair.first.snapshot()
        #expect(snapshot.pendingOperationCount == 0 && !snapshot.operationIsActive)
        let sends = (0..<64).map { _ in Task { try await pair.first.seal(opus, ssrc: 111) } }
        for send in sends { send.cancel() }
        for send in sends {
            do { _ = try await send.value }
            catch is CancellationError {}
            catch let error as DAVESessionError { #expect(error == .capacityExceeded) }
            catch { Issue.record("Unexpected cancelled media failure") }
        }
        let closingSends = (0..<64).map { _ in Task { try await pair.first.seal(opus, ssrc: 111) } }
        async let closeA: Void = pair.first.close()
        async let closeB: Void = pair.first.close()
        _ = await (closeA, closeB)
        for send in closingSends {
            do { _ = try await send.value }
            catch let error as DAVESessionError { #expect(error == .closed || error == .capacityExceeded) }
            catch { Issue.record("Unexpected failure while closure joined admitted media") }
        }
        await pair.second.close()
        let closed = await pair.first.snapshot()
        #expect(closed.isClosed && closed.sourceCount == 0 && closed.pendingOperationCount == 0 && !closed.operationIsActive)
        await #expect(throws: DAVESessionError.closed) { try await pair.first.open(Data(), ssrc: 111) }
    }

    /// Synthetic PCM traverses real Opus, DAVE, RTP and outer AEAD in both directions,
    /// then returns through authenticated jitter/decoder playout. Virtual 20ms steps
    /// validate composition and accounting; they do not qualify ten-minute hardware,
    /// acoustic quality, real-time pacing, Discord interoperability or network loss.
    /// - Throws: MLS, media, codec, transport-crypto, or fixture assertion failures.
    @Test func virtualDuplexPCMTraversesBothEncryptionLayers() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let pair = try await established()
        let clock = ManualClock()
        let packets = 32
        let firstUDP = try ScriptedDatagramTransport(incoming: [], maximumDatagrams: packets)
        let secondUDP = try ScriptedDatagramTransport(incoming: [], maximumDatagrams: packets)
        let firstAddress = DatagramAddress(host: "127.0.0.1", port: 1111)
        let secondAddress = DatagramAddress(host: "127.0.0.1", port: 2222)
        let key = Data(repeating: 19, count: 32)
        let transportCipher = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize, key: key)
        let first = try VoiceMediaPipeline(clock: clock, transport: firstUDP, peer: secondAddress,
            cipher: transportCipher, transformer: pair.first, ssrc: 111, encoder: OpusAudioEncoder(),
            initialSequence: UInt16.max - 7, initialTimestamp: UInt32.max - 1_000)
        let second = try VoiceMediaPipeline(clock: clock, transport: secondUDP, peer: firstAddress,
            cipher: transportCipher, transformer: pair.second, ssrc: 222, encoder: OpusAudioEncoder(),
            initialSequence: UInt16.max - 7, initialTimestamp: UInt32.max - 1_000)
        try await first.registerReceiveStream(ssrc: 222)
        try await second.registerReceiveStream(ssrc: 111)
        #expect(try await pair.first.authorizeGateway(suspended(pair.firstCredentials)).phase == .ready)
        #expect(try await pair.second.authorizeGateway(suspended(pair.secondCredentials)).phase == .ready)
        await first.setAuthorized(true); await second.setAuthorized(true)
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let samples = (0..<960).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000) * 0.2) }
        let pcm = try PCMBuffer(format: format, samples: samples)
        var played = 0
        do {
            for index in 0..<packets {
                try clock.advance(by: .milliseconds(20))
                let context = TransportContext(clock: clock)
                async let firstSent = first.send(pcm, context: context)
                async let secondSent = second.send(pcm, context: context)
                let sends = try await (firstSent, secondSent)
                #expect(sends.0 && sends.1)
                let firstPacket = try #require(await firstUDP.sent.last)
                let secondPacket = try #require(await secondUDP.sent.last)
                try await first.receive(.init(bytes: secondPacket.bytes, peer: secondAddress))
                try await second.receive(.init(bytes: firstPacket.bytes, peer: firstAddress))
                let firstPCM = try #require(try await first.playout(ssrc: 222))
                let secondPCM = try #require(try await second.playout(ssrc: 111))
                let sequence = (UInt16.max - 7) &+ UInt16(index)
                for output in [firstPCM, secondPCM] {
                    #expect(!output.concealed && output.sequence == sequence)
                    #expect(output.encodedOpus != nil && output.pcm.frameCount == 960)
                    #expect(output.pcm.format == format && output.pcm.samples.allSatisfy(\.isFinite))
                    #expect(output.pcm.samples.contains { abs($0) > 0.00001 })
                    played += output.pcm.frameCount
                }
            }
            let firstSnapshot = await first.snapshot()
            let secondSnapshot = await second.snapshot()
            for snapshot in [firstSnapshot, secondSnapshot] {
                #expect(snapshot.sentPackets == UInt64(packets) && snapshot.receivedPackets == UInt64(packets))
                #expect(snapshot.concealedPackets == 0 && snapshot.bufferedBytes == 0)
            }
            #expect(played == packets * 960 * 2)
            #expect(clock.now.offset == .milliseconds(640) && clock.pendingSleepCount == 0)
            await first.setAuthorized(false)
            await #expect(throws: VoiceMediaPipelineError.unauthorized) { try await first.send(pcm, context: .init(clock: clock)) }
        } catch {
            await first.close(); await second.close()
            await firstUDP.close(); await secondUDP.close()
            await transportCipher.close()
            await pair.first.close(); await pair.second.close()
            throw error
        }
        await first.close(); await second.close()
        await firstUDP.close(); await secondUDP.close()
        await transportCipher.close()
        await pair.first.close(); await pair.second.close()
    }
}
