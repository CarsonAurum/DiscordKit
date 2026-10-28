// File: Examples/VoiceBot/Sources/VoiceBot/MLSExample.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordMLS

extension VoiceBot {
    /// Establishes an offline two-member MLS epoch using a synthetic trusted delivery
    /// service, then checks agreement of explicit exported key material. Its fixed
    /// public signing scalar is a test fixture, never a real gateway credential.
    /// Both actor owners close after success or failure; no network or device is used.
    /// - Throws: Any encoding, signature, membership, TreeKEM, Welcome or agreement error.
    static func demonstrateMLS() async throws {
        let alice = try MLSKeyPackageOwner(userID: 1)
        let bob = try MLSKeyPackageOwner(userID: 2)
        let externalPrivateKey = Data(repeating: 1, count: 32)
        let externalLeaf = try MLSLeafNode.generate(identity: Data("offline external sender".utf8),
            signaturePrivateKey: externalPrivateKey, encryptionKey: alice.keyPackage.leafNode.encryptionKey)
        let external = try MLSExternalSender(signatureKey: externalLeaf.signatureKey, credential: externalLeaf.credential)
        let policy = try MLSGroupPolicy(externalSender: external, expectedParticipants: [1, 2])
        let groupID = Data("offline-voicebot-mls-example".utf8)
        let first = try await alice.createGroup(groupID: groupID, policy: policy)
        var second: MLSGroup?
        do {
            let proposal = try MLSProposal.add(bob.keyPackage).externalMessage(groupID: groupID, epoch: 0,
                signaturePrivateKey: externalPrivateKey)
            _ = try await first.cacheProposal(proposal)
            let candidate = try await first.prepareCommit()
            guard let welcome = candidate.welcome else { throw MLSError.invalidCommit }
            let joined = try await bob.join(welcome: welcome, expectedGroupID: groupID, policy: policy)
            second = joined
            _ = try await first.acceptCommit(candidate.commit)
            let firstKey = try await first.export(label: "offline example", context: Data([0, 1]), length: 16)
            let secondKey = try await joined.export(label: "offline example", context: Data([0, 1]), length: 16)
            guard firstKey == secondKey, firstKey.count == 16 else { throw MLSError.confirmationFailed }
            print("Two synthetic MLS members agree after authenticated Add/Commit/Welcome.")
            await first.close(); await joined.close(); await bob.close()
        } catch {
            await first.close(); await second?.close(); await alice.close(); await bob.close(); throw error
        }
    }
}
