// File: Tests/DiscordMLSTests/MLSRemoteCommitTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Known synthetic epoch state isolates remote commit authentication and failure atomicity.
/// Private setup uses existing internal initializers; no production visibility is widened.
@Suite struct MLSRemoteCommitTests {
    /// Exercises a remote winner after a local tentative commit, including attacks that
    /// recompute the old-epoch membership MAC so signature, confirmation and path checks
    /// are reached independently. Every failed remote candidate preserves the local one.
    @Test func remoteWinnerAndAuthenticatedFailures() async throws {
        let setup = try fixture(memberCount: 2)
        let a = setup.group(0); let b = setup.group(1)
        let proposal = try MLSProposal.add(setup.packages[2]).externalMessage(groupID: setup.context.groupID,
            epoch: 1, signaturePrivateKey: setup.externalPrivate)
        _ = try await a.cacheProposal(proposal); _ = try await b.cacheProposal(proposal)
        let local = try await a.prepareCommit(); let remote = try await b.prepareCommit()
        let before = await a.snapshot()
        let original = try MLSPublicMessage.decode(remote.commit)
        var badSignature = original; badSignature.signature[0] ^= 1
        let signatureBytes = try authenticated(badSignature, setup: setup)
        await #expect(throws: MLSError.invalidSignature) { try await a.acceptCommit(signatureBytes) }
        #expect(await a.snapshot() == before); #expect(try await a.prepareCommit().commit == local.commit)
        var badConfirmation = original; badConfirmation.confirmationTag[0] ^= 1
        let confirmationBytes = try authenticated(badConfirmation, setup: setup)
        await #expect(throws: MLSError.confirmationFailed) { try await a.acceptCommit(confirmationBytes) }
        #expect(await a.snapshot() == before)
        guard case .commit(let commit) = original.body else { Issue.record("expected Commit"); return }
        let path = try #require(commit.path)
        let malformedPath = MLSUpdatePath(leafNode: path.leafNode, nodes: Array(path.nodes.dropLast()))
        var badPath = MLSPublicMessage(groupID: original.groupID, epoch: original.epoch, sender: original.sender,
            body: .commit(MLSCommit(references: commit.references, path: malformedPath)))
        badPath.confirmationTag = original.confirmationTag
        badPath.signature = try MLSCipherSuite2.signWithLabel(privateKey: setup.signingPrivate[1], label: "FramedContentTBS",
            content: badPath.signatureInput(context: setup.context))
        let pathBytes = try authenticated(badPath, setup: setup)
        await #expect(throws: MLSError.invalidTree) { try await a.acceptCommit(pathBytes) }
        #expect(await a.snapshot() == before)
        #expect(try await a.acceptCommit(remote.commit) == .advanced)
        #expect(try await b.acceptCommit(remote.commit) == .advanced)
        #expect(await a.snapshot().epoch == 2); #expect(await a.snapshot().hasTentativeCommit == false)
        #expect(try await a.epochAuthenticator() == b.epochAuthenticator())
        #expect(try await a.export(label: "remote", context: Data([1]), length: 32) == b.export(label: "remote", context: Data([1]), length: 32))
        await #expect(throws: MLSError.wrongEpoch) { try await a.acceptCommit(local.commit) }
    }

    /// Builds a separately signed Add-only Commit without UpdatePath, using the RFC
    /// all-zero commit secret and independently constructed transcript/context. Confirms
    /// that this permitted branch advances with the expected exporter/authenticator.
    @Test func remoteAddWithoutPath() async throws {
        let setup = try fixture(memberCount: 2); let group = setup.group(0)
        let proposal = try MLSProposal.add(setup.packages[2]).externalMessage(groupID: setup.context.groupID,
            epoch: 1, signaturePrivateKey: setup.externalPrivate)
        let reference = try await group.cacheProposal(proposal)
        var tree = setup.tree; #expect(try tree.add(setup.packages[2].leafNode) == 2)
        var message = MLSPublicMessage(groupID: setup.context.groupID, epoch: 1, sender: .member(1),
            body: .commit(MLSCommit(references: [reference], path: nil)))
        message.signature = try MLSCipherSuite2.signWithLabel(privateKey: setup.signingPrivate[1], label: "FramedContentTBS",
            content: message.signatureInput(context: setup.context))
        let confirmed = try MLSCipherSuite2.hash(setup.interim + message.transcriptInput())
        let context = try MLSGroupContext(groupID: setup.context.groupID, epoch: 2, treeHash: tree.treeHash(),
            confirmedTranscriptHash: confirmed, extensions: setup.context.extensions)
        let schedule = try MLSKeySchedule(initSecret: setup.schedule.initSecret, commitSecret: Data(count: 32), groupContext: context.encoded())
        message.confirmationTag = MLSCipherSuite2.mac(key: schedule.confirmationKey, content: confirmed)
        let bytes = try authenticated(message, setup: setup)
        #expect(try await group.acceptCommit(bytes) == .advanced)
        #expect(await group.snapshot().epoch == 2); #expect(await group.snapshot().memberCount == 3)
        #expect(try await group.epochAuthenticator() == schedule.epochAuthenticator)
        let expected = try schedule.export(label: "no-path", context: Data([2]), length: 32)
        #expect(try await group.export(label: "no-path", context: Data([2]), length: 32) == expected)
    }

    /// Removes only members, shrinking capacity from four leaves to two and then one.
    /// Remote surviving members agree, removed owners close before releasing new keys,
    /// and the final singleton sender handles an empty filtered UpdatePath correctly.
    @Test func removalOnlyShrinksToSingleton() async throws {
        let setup = try fixture(memberCount: 3)
        let a = setup.group(0); let b = setup.group(1); let c = setup.group(2)
        let removeC = try MLSProposal.remove(2).externalMessage(groupID: setup.context.groupID, epoch: 1, signaturePrivateKey: setup.externalPrivate)
        for group in [a, b, c] { _ = try await group.cacheProposal(removeC) }
        let first = try await b.prepareCommit(); #expect(first.welcome == nil)
        #expect(try await a.acceptCommit(first.commit) == .advanced)
        #expect(try await c.acceptCommit(first.commit) == .removed)
        #expect(try await b.acceptCommit(first.commit) == .advanced)
        #expect(await c.snapshot().isClosed); #expect(await a.snapshot().memberCount == 2)
        #expect(try await a.epochAuthenticator() == b.epochAuthenticator())
        let removeB = try MLSProposal.remove(1).externalMessage(groupID: setup.context.groupID, epoch: 2, signaturePrivateKey: setup.externalPrivate)
        for group in [a, b] { _ = try await group.cacheProposal(removeB) }
        let second = try await a.prepareCommit(); let message = try MLSPublicMessage.decode(second.commit)
        guard case .commit(let commit) = message.body else { Issue.record("expected Commit"); return }
        #expect(commit.path?.nodes.isEmpty == true)
        #expect(try await b.acceptCommit(second.commit) == .removed)
        #expect(try await a.acceptCommit(second.commit) == .advanced)
        #expect(await a.snapshot().memberCount == 1); #expect(await a.snapshot().epoch == 3)
        await #expect(throws: MLSError.closed) { try await b.export(label: "removed", context: Data(), length: 32) }
    }

    /// Replaces only the membership MAC using independently known prior epoch keys.
    /// - Parameters:
    ///   - message: Signed or deliberately malformed signature/confirmation candidate.
    ///   - setup: Prior authenticated context and membership key shared by members.
    /// - Returns: Canonical public message reaching checks after membership authentication.
    /// - Throws: Encoding or sender/context errors.
    private func authenticated(_ message: MLSPublicMessage, setup: Fixture) throws -> Data {
        var result = message
        result.membershipTag = try MLSCipherSuite2.mac(key: setup.schedule.membershipKey, content: result.membershipInput(context: setup.context))
        return try result.encoded()
    }

    /// Creates deterministic keys and a shared synthetic epoch-one state with blank parents.
    /// - Parameter memberCount: Two or three current members; a third package is always available.
    /// - Returns: Fully signed leaves, shared key schedule and participant-authorized policy.
    /// - Throws: Key, signature, credential, context or tree construction errors.
    private func fixture(memberCount: Int) throws -> Fixture {
        var packages: [MLSKeyPackage] = []; var signing: [Data] = []; var encryption: [Data] = []
        for id in UInt8(1)...3 {
            let sign = Data(repeating: 0, count: 31) + Data([id + 10])
            let leaf = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: id, count: 32))
            let initial = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: id + 64, count: 32))
            packages.append(try MLSKeyPackage.generate(identity: MLSCredential.discord(userID: UInt64(id)).identity,
                signaturePrivateKey: sign, leafEncryptionKey: leaf.publicKey, initKey: initial.publicKey))
            signing.append(sign); encryption.append(leaf.privateKey)
        }
        let external = Data(repeating: 0, count: 31) + Data([90])
        let sender = try MLSExternalSender(signatureKey: P256.Signing.PrivateKey(rawRepresentation: external).publicKey.x963Representation,
            credential: MLSCredential(identity: Data("known-gateway".utf8)))
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2, 3])
        var tree = try MLSRatchetTree(leaf: packages[0].leafNode)
        for index in 1..<memberCount { try tree.add(packages[index].leafNode) }
        let confirmed = MLSCipherSuite2.hash(Data("known-epoch-one".utf8))
        let context = try MLSGroupContext(groupID: Data("known-remote-group".utf8), epoch: 1, treeHash: tree.treeHash(),
            confirmedTranscriptHash: confirmed, extensions: [sender.groupExtension()])
        let schedule = try MLSKeySchedule(epochSecret: Data(repeating: 42, count: 32))
        let interim = try mlsInterimTranscript(confirmed: confirmed,
            confirmation: MLSCipherSuite2.mac(key: schedule.confirmationKey, content: confirmed))
        return Fixture(packages: packages, signingPrivate: signing, encryptionPrivate: encryption,
            externalPrivate: external, policy: policy, tree: tree, context: context, schedule: schedule, interim: interim)
    }

    /// Known test-only material copied into distinct actor owners at the same epoch.
    private struct Fixture {
        let packages: [MLSKeyPackage]
        let signingPrivate: [Data]
        let encryptionPrivate: [Data]
        let externalPrivate: Data
        let policy: MLSGroupPolicy
        let tree: MLSRatchetTree
        let context: MLSGroupContext
        let schedule: MLSKeySchedule
        let interim: Data

        /// Creates one owner holding only its own leaf key and shared epoch branches.
        /// - Parameter index: Existing leaf index in this synthetic two/three-member tree.
        /// - Returns: Independent group actor with no tasks or I/O.
        func group(_ index: UInt32) -> MLSGroup {
            let state = MLSEpochState(context: context, tree: tree, ownLeaf: index,
                privateKeys: [index * 2: encryptionPrivate[Int(index)]], keys: MLSEpochKeys(schedule), interimTranscript: interim)
            return MLSGroup(state: state, signingKey: signingPrivate[Int(index)], userID: UInt64(index) + 1, policy: policy)
        }
    }
}
