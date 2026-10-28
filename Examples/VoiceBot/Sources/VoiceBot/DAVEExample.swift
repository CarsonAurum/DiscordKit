// File: Examples/VoiceBot/Sources/VoiceBot/DAVEExample.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordDAVE
import DiscordMLS
import DiscordModels
import DiscordVoice
import Foundation

extension VoiceBot {
    /// Exercises a complete local DAVE v1 transition with an independent owned MLS peer.
    ///
    /// A synthetic delivery service supplies membership, trusted external sender and
    /// external proposals. Both members produce candidates; the remote candidate wins,
    /// and its addressed Welcome prepares receive keys before Ready/Execute enables
    /// sending. Complete Opus and video frames then round-trip in both directions,
    /// including explicit local reassembly, tamper/replay rejection and actor cleanup.
    /// Fixed private signing scalars are public fixtures, never service credentials.
    /// This starts no network, hardware, timer or background producer and establishes
    /// no independent-client, live Discord, perceptual or ten-minute duplex evidence.
    /// - Throws: Signaling, MLS, media or deterministic invariant failures after cleanup.
    static func demonstrateDAVE() async throws {
        let remoteOwner = try MLSKeyPackageOwner(userID: 2)
        let externalKey = Data(repeating: 1, count: 32)
        let leaf = try MLSLeafNode.generate(identity: Data("offline DAVE gateway".utf8),
            signaturePrivateKey: externalKey, encryptionKey: remoteOwner.keyPackage.leafNode.encryptionKey)
        let external = try MLSExternalSender(signatureKey: leaf.signatureKey, credential: leaf.credential)
        var join = try VoiceJoinRendezvous(guildID: .init(rawValue: 3), userID: .init(rawValue: 1), channelID: .init(rawValue: 4))
        let state = try VoiceState(data: Data(#"{"guild_id":"3","channel_id":"4","user_id":"1","session_id":"offline-dave-session","deaf":false,"mute":false,"self_deaf":false,"self_mute":false,"self_video":false,"suppress":false,"request_to_speak_timestamp":null}"#.utf8))
        _ = try join.receive(state: state, generation: join.generation)
        let server = try GatewayVoiceServerUpdate(data: Data(#"{"guild_id":"3","token":"public-fixture-token","endpoint":"offline.invalid"}"#.utf8))
        guard let credentials = try join.receive(server: server, generation: join.generation) else { throw ExampleFailure.invalidInvariant }
        let groupID = Data([0, 0, 0, 0, 0, 0, 0, 4])
        let session = try DAVEProtocolSession(identity: credentials.identity, groupID: groupID,
            signaturePrivateKey: Data(repeating: 2, count: 32), externalSender: external, maximumMembers: 2)
        var remoteGroup: MLSGroup?
        var remoteSender: DAVEFrameCipher?
        var remoteReceiver: DAVEFrameCipher?
        do {
            let startup = try await session.start(protocolVersion: 1)
            guard startup.count == 1, startup[0].opcode == 26, case .binary(let packageBytes) = startup[0].payload else {
                throw ExampleFailure.invalidInvariant
            }
            let localPackage = try MLSKeyPackage.decode(packageBytes, messageWrapped: false)
            let connected = try VoiceGatewayFrame(.text(#"{"op":11,"d":{"user_ids":["2"]}}"#))
            _ = try await session.receive(connected, now: 0)
            _ = try await session.receive(daveServerBinary(opcode: 25, body: external.encoded()), now: 0)

            let remoteAdd = try MLSProposal.add(remoteOwner.keyPackage).externalMessage(groupID: groupID,
                epoch: 0, signaturePrivateKey: externalKey)
            var proposals = MLSWriter(); try proposals.writeVector(remoteAdd)
            let localCandidates = try await session.receive(daveServerBinary(opcode: 27, body: Data([0]) + proposals.data), now: 0)
            guard localCandidates.count == 1, localCandidates[0].opcode == 28 else { throw ExampleFailure.invalidInvariant }

            let policy = try MLSGroupPolicy(externalSender: external, expectedParticipants: [1, 2], maximumMembers: 2)
            let group = try await remoteOwner.createGroup(groupID: groupID, policy: policy)
            remoteGroup = group
            let localAdd = try MLSProposal.add(localPackage).externalMessage(groupID: groupID,
                epoch: 0, signaturePrivateKey: externalKey)
            _ = try await group.cacheProposal(localAdd)
            let selected = try await group.prepareCommit()
            guard let welcome = selected.welcome, try await group.acceptCommit(selected.commit) == .advanced else {
                throw ExampleFailure.invalidInvariant
            }
            let ready = try await session.receive(daveServerBinary(opcode: 30, body: Data([0, 7]) + welcome.dropFirst(4)), now: 1)
            guard ready.count == 1, ready[0].opcode == 23, await session.snapshot().activeEpoch == nil else {
                throw ExampleFailure.invalidInvariant
            }
            _ = try await session.receive(VoiceGatewayFrame(.text(#"{"op":22,"d":{"transition_id":7}}"#)), now: 1)
            guard await session.snapshot().activeEpoch == 1 else { throw ExampleFailure.invalidInvariant }

            let localSecret = try await group.export(label: "Discord Secure Frames v0", context: Data([1, 0, 0, 0, 0, 0, 0, 0]), length: 16)
            let peerSecret = try await group.export(label: "Discord Secure Frames v0", context: Data([2, 0, 0, 0, 0, 0, 0, 0]), length: 16)
            let sender = try DAVEFrameCipher(baseSecret: peerSecret)
            let receiver = try DAVEFrameCipher(baseSecret: localSecret)
            remoteSender = sender; remoteReceiver = receiver
            // Exactly one sender per domain: session sends user 1, sender sends user 2.
            let opus = Data([0xF8, 0xFF, 0xFE])
            let localAudio = try await session.seal(opus, codec: .opus)
            guard try await receiver.open(localAudio, mediaType: .audio, now: 1) == opus else { throw ExampleFailure.invalidInvariant }
            let remoteAudio = try await sender.seal(opus, codec: .opus)
            var tampered = remoteAudio; tampered[0] ^= 1
            do {
                _ = try await session.open(tampered, senderID: 2, mediaType: .audio, now: 1)
                throw ExampleFailure.invalidInvariant
            } catch DAVEError.authenticationFailed { }
            guard try await session.open(remoteAudio, senderID: 2, mediaType: .audio, now: 1) == opus else { throw ExampleFailure.invalidInvariant }
            do {
                _ = try await session.open(remoteAudio, senderID: 2, mediaType: .audio, now: 1)
                throw ExampleFailure.invalidInvariant
            } catch DAVEError.replayedFrame { }

            let video = Data([0, 0, 1, 2, 1, 0xAA, 0xBB, 0xCC])
            let normalizedVideo = try DAVECodecTransform.prepare(video, codec: .h265).bytes
            let protectedVideo = try await session.seal(video, codec: .h265)
            // Synthetic depacketization only: retain every byte and restore frame order.
            let split = protectedVideo.count / 2
            let reassembled = Data(protectedVideo.prefix(split)) + Data(protectedVideo.dropFirst(split))
            guard try await receiver.open(reassembled, mediaType: .video, now: 2) == normalizedVideo else { throw ExampleFailure.invalidInvariant }
            let incomingVideo = Data([1, 0x31, 0x41, 0x59])
            let protectedIncoming = try await sender.seal(incomingVideo, codec: .vp8)
            guard try await session.open(protectedIncoming, senderID: 2, mediaType: .video, now: 2) == incomingVideo else { throw ExampleFailure.invalidInvariant }
            try await session.close(); await group.close(); await remoteOwner.close()
            await sender.close(); await receiver.close()
            guard await session.snapshot().isClosed else { throw ExampleFailure.invalidInvariant }
            print("Synthetic DAVE v1 membership/proposal/Welcome/Ready/Execute protected Opus, H265 and VP8; tamper/replay rejected and keys closed.")
        } catch {
            try? await session.close(); await remoteGroup?.close(); await remoteOwner.close()
            await remoteSender?.close(); await remoteReceiver?.close(); throw error
        }
    }

    /// Creates one synthetic authenticated server binary frame without socket ownership.
    /// - Parameters:
    ///   - opcode: Server DAVE opcode 25, 27 or 30 used by this example.
    ///   - body: Exact MLS/control bytes without server sequence or opcode.
    /// - Returns: Voice v8 binary envelope using synthetic sequence one.
    /// - Throws: Bounded Voice framing failures; no bytes are transmitted.
    private static func daveServerBinary(opcode: UInt8, body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([0, 1, opcode]) + body))
    }
}
