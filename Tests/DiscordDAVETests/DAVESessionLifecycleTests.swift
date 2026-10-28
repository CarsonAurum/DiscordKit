// File: Tests/DiscordDAVETests/DAVESessionLifecycleTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordDAVE
@testable import DiscordMLS
@testable import DiscordVoice

/// Complete multi-member signaling/media transitions through synthetic delivery.
/// Independent actors exercise real MLS and DAVE crypto without sockets or devices.
@Suite struct DAVESessionLifecycleTests {
    /// Creates a server JSON control without credentials or floating-point numeric conversion.
    /// - Parameters:
    ///   - opcode: Documented server JSON opcode.
    ///   - fields: Exact bounded control object.
    /// - Returns: Direction-validated Voice frame.
    /// - Throws: JSON or Voice structural errors.
    private func json(_ opcode: UInt8, _ fields: [String: JSONValue]) throws -> VoiceGatewayFrame {
        let value = try JSONValue.object(["op": .number(JSONNumber(rawValue: String(opcode))), "d": .object(fields)]).serialized()
        return try VoiceGatewayFrame(.text(String(decoding: value, as: UTF8.self)))
    }

    /// Constructs exact numeric transition fields for test-only server delivery.
    /// - Parameter id: Unsigned transition identifier, including initialization zero.
    /// - Returns: Exact integer data object.
    /// - Throws: JSON number grammar errors, impossible for an unsigned integer.
    private func transition(_ id: UInt16) throws -> [String: JSONValue] {
        ["transition_id": try .number(JSONNumber(rawValue: String(id)))]
    }

    /// Adds server sequence/opcode framing to a self-delimiting binary payload.
    /// - Parameters:
    ///   - opcode: Server binary opcode.
    ///   - body: Complete body, excluding sequence/opcode.
    /// - Returns: Direction-validated Voice frame with sequence one.
    /// - Throws: Voice framing/size errors.
    private func binary(_ opcode: UInt8, _ body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([0, 1, opcode]) + body))
    }

    /// Wraps external proposal messages in the documented operation/vector envelope.
    /// - Parameter messages: Complete signed MLSMessages in trusted delivery order.
    /// - Returns: Server opcode 27 append control.
    /// - Throws: Bounded MLS or Voice framing errors.
    private func proposals(_ messages: [Data]) throws -> VoiceGatewayFrame {
        var writer = MLSWriter(); writer.write(UInt8(0))
        try writer.writeVector(messages.reduce(Data(), +))
        return try binary(27, writer.data)
    }

    /// Creates one actor bound to a deterministic synthetic Voice identity.
    /// - Parameters:
    ///   - id: Nonzero local participant ID.
    ///   - sender: Trusted external sender shared with the other scenario actors.
    ///   - groupID: Authenticated common call ID bytes.
    /// - Returns: Inert session with independent ephemeral identity key.
    /// - Throws: Key or session configuration errors.
    private func session(_ id: UInt64, sender: MLSExternalSender, groupID: Data) throws -> DAVEProtocolSession {
        let credentials = VoiceConnectionCredentials(guildID: GuildID(rawValue: 5), userID: UserID(rawValue: id),
            channelID: ChannelID(rawValue: 6), sessionID: "offline-\(id)", token: "synthetic", endpoint: "voice.discord.media", generation: 1)
        return try DAVEProtocolSession(identity: credentials.identity, groupID: groupID,
            signaturePrivateKey: P256.Signing.PrivateKey(compactRepresentable: false).rawRepresentation, externalSender: sender)
    }

    /// Starts a local package and admits authenticated session membership and sender.
    /// - Parameters:
    ///   - session: Fresh inert actor.
    ///   - sender: Expected authenticated external sender.
    /// - Returns: Public package published by this pending member.
    /// - Throws: Session, package or frame errors.
    private func initialize(_ session: DAVEProtocolSession, sender: MLSExternalSender) async throws -> MLSKeyPackage {
        let commands = try await session.start(protocolVersion: 1)
        guard case .binary(let body) = try #require(commands.first).payload else { throw DAVESessionError.invalidMessage }
        let package = try MLSKeyPackage.decode(body, messageWrapped: false)
        _ = try await session.receive(json(11, ["user_ids": .array([.string("1"), .string("2"), .string("3")])]), now: 0)
        _ = try await session.receive(binary(25, sender.encoded()), now: 0)
        return package
    }

    /// Separates the complete commit and bare optional Welcome using MLS framing.
    /// - Parameter command: One client opcode 28 candidate from a real session.
    /// - Returns: Canonical commit and bare Welcome bytes; no invented length prefix.
    /// - Throws: Fixture shape or MLS parsing errors.
    private func candidate(_ command: VoiceGatewayFrame) throws -> (commit: Data, welcome: Data) {
        #expect(command.opcode == 28)
        guard case .binary(let data) = command.payload else { throw DAVESessionError.invalidMessage }
        var reader = try MLSReader(data)
        let message = try MLSPublicMessage.decode(&reader)
        return try (message.encoded(), reader.readRaw(count: reader.remainingCount))
    }

    /// Delivers the selected commit or Welcome and verifies ready admission precedes execute.
    /// - Parameters:
    ///   - session: Receiving group member or pending invitee.
    ///   - selection: Complete MLS commit or bare Welcome bytes.
    ///   - joining: True chooses Welcome opcode 30; false chooses selected commit 29.
    ///   - id: Server transition identifier.
    ///   - now: Monotonic synthetic time.
    /// - Throws: Session or frame errors and assertion failures.
    private func select(_ session: DAVEProtocolSession, selection: Data, joining: Bool, id: UInt16, now: TimeInterval) async throws {
        var prefix = MLSWriter(); prefix.write(id)
        let ready = try await session.receive(binary(joining ? 30 : 29, prefix.data + selection), now: now)
        #expect(ready.map(\.opcode) == [23])
        #expect(await session.snapshot().pendingTransition == id)
    }

    /// Initial groups keep only the newest tentative state across proposal append/revocation.
    /// Selection requires its exact public commit: a superseded candidate triggers bounded
    /// recovery with the same signing identity, while a current self-echo acknowledges Ready
    /// and retains the media gate until Execute. Welcome addresses only the unrevoked member.
    /// - Parameter selectStale: True selects the superseded commit to exercise recovery.
    /// - Throws: Unexpected synthetic protocol, MLS or authenticated frame errors.
    @Test(arguments: [false, true])
    func initialCandidateRevocationAndExactSelfEcho(selectStale: Bool) async throws {
        let external = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: external.publicKey.x963Representation,
            credential: MLSCredential(identity: Data("gateway".utf8)))
        let groupID = Data([0, 0, 0, 0, 0, 0, 0, 4])
        let a = try session(1, sender: sender, groupID: groupID)
        let b = try session(2, sender: sender, groupID: groupID)
        let c = try session(3, sender: sender, groupID: groupID)
        let alice = try await initialize(a, sender: sender)
        let bob = try await initialize(b, sender: sender)
        let carol = try await initialize(c, sender: sender)
        let addB = try MLSProposal.add(bob).externalMessage(groupID: groupID, epoch: 0,
            signaturePrivateKey: external.rawRepresentation)
        let addC = try MLSProposal.add(carol).externalMessage(groupID: groupID, epoch: 0,
            signaturePrivateKey: external.rawRepresentation)
        let first = try await a.receive(proposals([addB]), now: 0)
        let stale = try candidate(#require(first.first))
        _ = try await a.receive(proposals([addC]), now: 0)
        var reference = MLSWriter()
        try reference.writeVector(MLSCipherSuite2.refHash(label: "MLS 1.0 Proposal Reference", value: MLSPublicMessage.decode(addC).authenticatedContent()))
        var revoked = MLSWriter(); revoked.write(UInt8(1))
        try revoked.writeVector(reference.data)
        let replacement = try await a.receive(binary(27, revoked.data), now: 0)
        let current = try candidate(#require(replacement.first))
        #expect(current.commit != stale.commit)
        let message = try MLSPublicMessage.decode(current.commit)
        #expect(message.groupID == groupID && message.epoch == 0 && message.sender == .member(0))
        guard case .commit(let commit) = message.body else { throw DAVESessionError.invalidMessage }
        #expect(commit.references == [try MLSCipherSuite2.refHash(label: "MLS 1.0 Proposal Reference", value: MLSPublicMessage.decode(addB).authenticatedContent())])
        let path = try #require(commit.path)
        #expect(path.leafNode.credential == alice.leafNode.credential)
        #expect(path.leafNode.signatureKey == alice.leafNode.signatureKey)
        let welcome = try MLSWelcome.decode(Data([0, 1, 0, 3]) + current.welcome)
        #expect(welcome.secrets.map(\.reference) == [try bob.reference()])
        #expect(await a.snapshot().activeEpoch == nil)
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await a.seal(Data([0xF8, 1]), codec: .opus) }
        let selected = try await a.receive(binary(29, Data([0, 9]) + (selectStale ? stale.commit : current.commit)), now: 1)
        if selectStale {
            #expect(selected.map(\.opcode) == [31, 26])
            guard case .binary(let freshBytes) = try #require(selected.last).payload else { throw DAVESessionError.invalidMessage }
            let fresh = try MLSKeyPackage.decode(freshBytes, messageWrapped: false)
            #expect(fresh.leafNode.signatureKey == alice.leafNode.signatureKey)
            #expect(fresh.initKey != alice.initKey)
            #expect(await a.snapshot().pendingTransition == nil)
        } else {
            #expect(selected.map(\.opcode) == [23])
            #expect(await a.snapshot().pendingTransition == 9)
            #expect(await a.snapshot().activeEpoch == nil)
            await #expect(throws: DAVESessionError.mediaUnavailable) { try await a.seal(Data([0xF8, 1]), codec: .opus) }
            try await select(b, selection: current.welcome, joining: true, id: 9, now: 1)
            for owner in [a, b] { _ = try await owner.receive(json(22, transition(9)), now: 1) }
            let packet = try await a.seal(Data([0xF8, 1]), codec: .opus)
            #expect(try await b.open(packet, senderID: 1, mediaType: .audio, now: 1) == Data([0xF8, 1]))
        }
        for owner in [a, b, c] {
            try await owner.close()
            #expect(await owner.snapshot().isClosed)
            #expect(await owner.snapshot().retainedEpochCount == 0)
        }
    }

    /// Rejects every constructor policy/key boundary before work or secret ownership;
    /// account-scoped verification cannot accidentally be adopted by another local user.
    @Test func constructorBoundsAccountAndOwnedSliceAdmission() async throws {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: key.publicKey.x963Representation,
            credential: MLSCredential(identity: Data("gateway".utf8)))
        let credentials = VoiceConnectionCredentials(guildID: GuildID(rawValue: 1), userID: UserID(rawValue: 2),
            channelID: ChannelID(rawValue: 3), sessionID: "synthetic", token: "synthetic", endpoint: "voice.discord.media", generation: 1)
        for count in [0, 256] {
            #expect(throws: DAVESessionError.invalidConfiguration) {
                try DAVEProtocolSession(identity: credentials.identity, groupID: Data(count: count),
                    signaturePrivateKey: key.rawRepresentation, externalSender: sender)
            }
        }
        for count in [0, -1, 1025, Int.max] {
            #expect(throws: DAVESessionError.invalidConfiguration) {
                try DAVEProtocolSession(identity: credentials.identity, groupID: Data([1]),
                    signaturePrivateKey: key.rawRepresentation, externalSender: sender, maximumMembers: count)
            }
        }
        #expect(throws: DAVESessionError.invalidConfiguration) {
            try DAVEProtocolSession(identity: credentials.identity, groupID: Data([1]),
                signaturePrivateKey: key.rawRepresentation, externalSender: sender, verificationSessionID: 0)
        }
        let wrongStore = try DAVEVerificationStore(localUserID: 1)
        #expect(throws: DAVESessionError.invalidConfiguration) {
            try DAVEProtocolSession(identity: credentials.identity, groupID: Data([1]),
                signaturePrivateKey: key.rawRepresentation, externalSender: sender, verificationStore: wrongStore)
        }
        for invalid in [Data(), Data(count: 31), Data(count: 32), Data(repeating: 255, count: 32), Data(count: 33)] {
            #expect(throws: (any Error).self) {
                try DAVEProtocolSession(identity: credentials.identity, groupID: Data([1]),
                    signaturePrivateKey: invalid, externalSender: sender)
            }
        }
        let backing = Data(count: 1024) + key.rawRepresentation
        let groupBacking = Data(count: 1024) + Data([1])
        let admitted = try DAVEProtocolSession(identity: credentials.identity, groupID: groupBacking.suffix(1),
            signaturePrivateKey: backing.suffix(32), externalSender: sender, maximumMembers: 1,
            verificationStore: DAVEVerificationStore(localUserID: 2))
        #expect(await admitted.snapshot().expectedParticipantCount == 1)
        #expect(try await admitted.start(protocolVersion: 1).first?.opcode == 26)
        try await admitted.close()
        let maximum = try DAVEProtocolSession(identity: credentials.identity, groupID: Data(count: 255),
            signaturePrivateKey: key.rawRepresentation, externalSender: sender, maximumMembers: 1024)
        try await maximum.close()
    }

    /// Two pending creators converge, a third member joins through a remote winning
    /// commit, old/new nonce domains coexist until exact ten-second expiry, and a
    /// removal excludes future media. Every transition uses ready then explicit execute.
    @Test func membershipConcurrentCommitEpochExpiryAndRemoval() async throws {
        let externalKey = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: externalKey.publicKey.x963Representation,
            credential: MLSCredential(identity: Data("offline-gateway".utf8)))
        let groupID = Data([0, 0, 0, 0, 0, 0, 0, 6])
        let a = try session(1, sender: sender, groupID: groupID)
        let b = try session(2, sender: sender, groupID: groupID)
        let c = try session(3, sender: sender, groupID: groupID)
        _ = try await initialize(a, sender: sender)
        let bob = try await initialize(b, sender: sender)
        let carol = try await initialize(c, sender: sender)
        let addB = try MLSProposal.add(bob).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalKey.rawRepresentation)
        let first = try await a.receive(proposals([addB]), now: 1)
        let initial = try candidate(#require(first.first))
        try await select(a, selection: initial.commit, joining: false, id: 7, now: 1)
        try await select(b, selection: initial.welcome, joining: true, id: 7, now: 1)
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await a.seal(Data([0xF8, 1]), codec: .opus) }
        _ = try await a.receive(json(22, transition(7)), now: 1)
        let beforeBExecute = try await a.seal(Data([0xF8, 2]), codec: .opus)
        #expect(try await b.open(beforeBExecute, senderID: 1, mediaType: .audio, now: 1) == Data([0xF8, 2]))
        _ = try await b.receive(json(22, transition(7)), now: 1)
        let old1 = try await a.seal(Data([0xF8, 3]), codec: .opus)
        let old2 = try await a.seal(Data([0xF8, 4]), codec: .opus)
        let addC = try MLSProposal.add(carol).externalMessage(groupID: groupID, epoch: 1, signaturePrivateKey: externalKey.rawRepresentation)
        let aCommands = try await a.receive(proposals([addC]), now: 2)
        let bCommands = try await b.receive(proposals([addC]), now: 2)
        let loser = try candidate(#require(aCommands.first))
        let winner = try candidate(#require(bCommands.first))
        #expect(loser.commit != winner.commit)
        try await select(a, selection: winner.commit, joining: false, id: 8, now: 2)
        try await select(b, selection: winner.commit, joining: false, id: 8, now: 2)
        try await select(c, selection: winner.welcome, joining: true, id: 8, now: 2)
        for owner in [a, b, c] { _ = try await owner.receive(json(22, transition(8)), now: 2) }
        #expect(await a.snapshot().activeEpoch == 2)
        #expect(await b.snapshot().retainedEpochCount == 2)
        #expect(try await b.open(old1, senderID: 1, mediaType: .audio, now: 3) == Data([0xF8, 3]))
        // New members never receive epoch-one secrets.
        await #expect(throws: DAVEError.authenticationFailed) { try await c.open(old2, senderID: 1, mediaType: .audio, now: 3) }
        let frame = Data([1, 8, 9, 10])
        let newFrame = try await a.seal(frame, codec: .vp8)
        // Simulated complete-frame fragmentation/reassembly leaves the authenticated bytes exact.
        let pieces = stride(from: 0, to: newFrame.count, by: 3).map { newFrame.subdata(in: $0..<min($0 + 3, newFrame.count)) }
        #expect(try await b.open(pieces.reduce(Data(), +), senderID: 1, mediaType: .video, now: 4) == frame)
        #expect(try await c.open(newFrame, senderID: 1, mediaType: .video, now: 4) == frame)
        await #expect(throws: DAVEError.authenticationFailed) { try await b.open(old2, senderID: 1, mediaType: .audio, now: 12) }
        #expect(await b.snapshot().retainedEpochCount == 1)
        let removeC = try MLSProposal.remove(2).externalMessage(groupID: groupID, epoch: 2, signaturePrivateKey: externalKey.rawRepresentation)
        _ = try await c.receive(proposals([removeC]), now: 12)
        _ = try await b.receive(proposals([removeC]), now: 12)
        let removeCommands = try await a.receive(proposals([removeC]), now: 12)
        let removal = try candidate(#require(removeCommands.first))
        #expect(removal.welcome.isEmpty)
        try await select(a, selection: removal.commit, joining: false, id: 9, now: 12)
        try await select(b, selection: removal.commit, joining: false, id: 9, now: 12)
        let recovery = try await c.receive(binary(29, Data([0, 9]) + removal.commit), now: 12)
        #expect(recovery.map(\.opcode) == [26])
        for owner in [a, b] { _ = try await owner.receive(json(22, transition(9)), now: 12) }
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await c.seal(Data([1]), codec: .opus) }
        let future = try await a.seal(Data([0xF8, 5]), codec: .opus)
        #expect(try await b.open(future, senderID: 1, mediaType: .audio, now: 12) == Data([0xF8, 5]))
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await c.open(future, senderID: 1, mediaType: .audio, now: 12) }
        for owner in [a, b, c] {
            try await owner.close(); try await owner.close()
            #expect(await owner.snapshot().retainedEpochCount == 0)
            #expect(await owner.snapshot().isClosed)
        }
    }
}
