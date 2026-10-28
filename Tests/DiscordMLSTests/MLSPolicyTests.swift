// File: Tests/DiscordMLSTests/MLSPolicyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Deterministic policy, actor ownership and cancellation boundaries without network or timers.
@Suite struct MLSPolicyTests {
    private let groupID = Data("policy-group".utf8)
    private let externalPrivateKey = Data(repeating: 9, count: 32)

    /// Constructs a trusted synthetic delivery-service declaration with a fixed signing scalar.
    /// - Parameter identity: External-service credential assertion; never a participant user ID.
    /// - Returns: Valid P-256 sender whose private key is controlled only by these tests.
    /// - Throws: Credential/key import errors if fixture data is invalid.
    private func externalSender(identity: Data = Data("trusted-delivery".utf8)) throws -> MLSExternalSender {
        let key = try P256.Signing.PrivateKey(rawRepresentation: externalPrivateKey)
        return try MLSExternalSender(signatureKey: key.publicKey.x963Representation, credential: MLSCredential(identity: identity))
    }

    /// Creates an independently signed package for malformed/profile identity tests.
    /// - Parameters:
    ///   - identity: Opaque basic identity bytes, including deliberately invalid DAVE identities.
    ///   - lifetime: Structurally ordered lifetime; DAVE admission deliberately ignores expiry.
    ///   - leafExtensions: Leaf extension list; forbidden by DAVE even when structurally valid.
    ///   - packageExtensions: Package extensions; unknown types are explicitly advertised.
    /// - Returns: Fully signed generic suite-2 package with independent HPKE keys.
    /// - Throws: Generic wire/credential/crypto errors during fixture construction.
    private func package(identity: Data, lifetime: MLSLifetime = MLSLifetime(notBefore: 0, notAfter: .max),
                         leafExtensions: [MLSExtension] = [], packageExtensions: [MLSExtension] = []) throws -> MLSKeyPackage {
        let signing = Data(repeating: 20, count: 32)
        let publicSigning = try P256.Signing.PrivateKey(rawRepresentation: signing).publicKey.x963Representation
        let encryption = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 21, count: 32)).publicKey.x963Representation
        let initial = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 22, count: 32)).publicKey.x963Representation
        let advertised = Set((leafExtensions + packageExtensions).map(\.type).filter { !(1...5).contains($0) })
        let capabilities = try MLSCapabilities(extensions: advertised.sorted())
        let leaf = try MLSLeafNode(encryptionKey: encryption, signatureKey: publicSigning,
                                  credential: MLSCredential(identity: identity), capabilities: capabilities, lifetime: lifetime,
                                  extensions: leafExtensions).signed(privateKey: signing)
        return try MLSKeyPackage(initKey: initial, leafNode: leaf, extensions: packageExtensions).signed(privateKey: signing)
    }

    /// Exercises both ends of every policy range, participant authorization and default budgets.
    @Test func policyResourceBounds() throws {
        let sender = try externalSender(); let defaults = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1])
        #expect(defaults.maximumMembers == 256); #expect(defaults.maximumProposals == 256)
        #expect(defaults.maximumProposalBytes == 1_048_576); #expect(defaults.maximumMessageBytes == 1_048_576)
        for value in [0, 1025] {
            #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1], maximumMembers: value) }
            #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1], maximumProposals: value) }
        }
        for value in [1023, 16_777_217] {
            #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1], maximumProposalBytes: value) }
        }
        for value in [1023, 1_048_577] {
            #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1], maximumMessageBytes: value) }
        }
        #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [0]) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2], maximumMembers: 1) }
        let minimum = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1], maximumMembers: 1,
                                         maximumProposals: 1, maximumProposalBytes: 1024, maximumMessageBytes: 1024)
        #expect(minimum.maximumMembers == 1)
        let maximum = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [], maximumMembers: 1024,
                                         maximumProposals: 1024, maximumProposalBytes: 16_777_216, maximumMessageBytes: 1_048_576)
        #expect(maximum.maximumProposals == 1024)
    }

    /// Requires the exact authenticated external sender and a single group extension, including exact credential bytes.
    @Test func exactExternalSenderContext() throws {
        let sender = try externalSender(); let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1])
        let expected = try sender.groupExtension()
        let good = try MLSGroupContext(groupID: groupID, epoch: 0, treeHash: Data(count: 32),
                                       confirmedTranscriptHash: Data(), extensions: [expected])
        try MLSGroup.validateContext(good, policy: policy)
        let otherIdentity = try externalSender(identity: Data("other-service".utf8))
        let otherKey = try P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 10, count: 32))
        let otherSender = try MLSExternalSender(signatureKey: otherKey.publicKey.x963Representation, credential: sender.credential)
        var multiple = MLSWriter(); try multiple.writeVector(sender.encoded() + otherSender.encoded())
        let duplicateSenders = try MLSExtension(type: 5, data: multiple.data)
        let extra = try MLSExtension(type: 0xfafa, data: Data())
        for extensions in [[], [expected, extra], [try otherIdentity.groupExtension()], [try otherSender.groupExtension()], [duplicateSenders]] {
            let context = try MLSGroupContext(groupID: groupID, epoch: 0, treeHash: Data(count: 32),
                                              confirmedTranscriptHash: Data(), extensions: extensions)
            #expect(throws: MLSError.invalidCredential) { try MLSGroup.validateContext(context, policy: policy) }
        }
    }

    /// Rejects non-Discord identities, zero snowflakes, leaf extensions and unreachable Update-source leaves.
    /// DAVE peers deliberately ignore key-package expiry, while owners emit the specified full lifetime.
    @Test func strictDAVELeafPolicy() throws {
        let identity = try MLSCredential.discord(userID: .max).identity
        #expect(try MLSGroup.participantID(MLSCredential(identity: identity)) == .max)
        for bytes in [Data([1]), Data(count: 7), Data(count: 8), Data(count: 9)] {
            #expect(throws: MLSError.invalidCredential) { try MLSGroup.participantID(MLSCredential(identity: bytes)) }
        }
        let memberID = try MLSCredential.discord(userID: 2).identity
        let valid = try package(identity: memberID)
        let context = try MLSGroupContext(groupID: groupID, epoch: 0, treeHash: Data(count: 32), confirmedTranscriptHash: Data())
        let validTree = try MLSRatchetTree(leaf: valid.leafNode)
        try MLSGroup.validateTree(validTree, context: context, participants: [2])
        #expect(throws: MLSError.invalidCredential) { try MLSGroup.validateTree(validTree, context: context, participants: [1]) }
        let expired = try package(identity: memberID, lifetime: MLSLifetime(notBefore: 1, notAfter: 2))
        try MLSGroup.validateTree(MLSRatchetTree(leaf: expired.leafNode), context: context, participants: [2])
        let extensionValue = try MLSExtension(type: 1, data: Data([0]))
        let extended = try package(identity: memberID, leafExtensions: [extensionValue])
        #expect(throws: MLSError.invalidCredential) {
            try MLSGroup.validateTree(MLSRatchetTree(leaf: extended.leafNode), context: context, participants: [2])
        }
        let update = try MLSLeafNode.generate(identity: memberID, signaturePrivateKey: Data(repeating: 20, count: 32),
                                              encryptionKey: valid.leafNode.encryptionKey, source: .update, lifetime: nil,
                                              groupID: groupID, leafIndex: 0)
        #expect(throws: MLSError.invalidCredential) {
            try MLSGroup.validateTree(MLSRatchetTree(leaf: update), context: context, participants: [2])
        }
    }

    /// Preserves a key-package owner across failed creation, then consumes it exactly once and closes groups idempotently.
    @Test func ownerConsumptionAndClosure() async throws {
        #expect(throws: MLSError.invalidCredential) { try MLSKeyPackageOwner(userID: 0) }
        let owner = try MLSKeyPackageOwner(userID: 1); let sender = try externalSender()
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1])
        let denied = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [2])
        await #expect(throws: MLSError.invalidCredential) { try await owner.createGroup(groupID: groupID, policy: denied) }
        await #expect(throws: MLSError.invalidConfiguration) { try await owner.createGroup(groupID: Data(), policy: policy) }
        let group = try await owner.createGroup(groupID: groupID, policy: policy)
        let initial = await group.snapshot(); #expect(initial.epoch == 0); #expect(initial.memberCount == 1)
        #expect(!initial.isClosed); #expect(!initial.hasTentativeCommit)
        await #expect(throws: MLSError.closed) { try await owner.createGroup(groupID: groupID, policy: policy) }
        await #expect(throws: MLSError.closed) { try await owner.join(welcome: Data(), expectedGroupID: groupID, policy: policy) }
        await owner.close(); await owner.close(); await group.close(); await group.close()
        let closed = await group.snapshot(); #expect(closed.isClosed); #expect(closed.epoch == nil)
        #expect(closed.memberCount == 0); #expect(closed.pendingProposalCount == 0); #expect(closed.pendingProposalBytes == 0)
        await #expect(throws: MLSError.closed) { try await group.export(label: "test", context: Data(), length: 32) }
        await #expect(throws: MLSError.closed) { try await group.epochAuthenticator() }
        await #expect(throws: MLSError.closed) { try await group.setExpectedParticipants([1]) }
        await #expect(throws: MLSError.closed) { try await group.cacheProposal(Data()) }
        await #expect(throws: MLSError.closed) { try await group.revokeProposal(Data(count: 32)) }
        await #expect(throws: MLSError.closed) { try await group.prepareCommit() }
        await #expect(throws: MLSError.closed) { try await group.acceptCommit(Data()) }
        #expect(String(describing: owner) == "MLSKeyPackageOwner([REDACTED])")
        #expect(String(reflecting: group) == "MLSGroup([REDACTED])")
        #expect(Mirror(reflecting: owner).children.count == 1); #expect(Mirror(reflecting: group).children.count == 1)
    }

    /// Cancels each mutation/read before actor admission and proves current state and single-use keys remain usable.
    /// Cancellation is self-signaled synchronously; no timing-dependent sleep or external scheduler assumption is needed.
    @Test func cancellationBeforeAdmission() async throws {
        let sender = try externalSender(); let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2])
        let owner = try MLSKeyPackageOwner(userID: 1)
        let cancelledCreation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await owner.createGroup(groupID: groupID, policy: policy)
        }
        await #expect(throws: CancellationError.self) { try await cancelledCreation.value }
        let group = try await owner.createGroup(groupID: groupID, policy: policy); let before = await group.snapshot()
        let operations: [@Sendable () async throws -> Void] = [
            { try await group.setExpectedParticipants([0]) },
            { _ = try await group.cacheProposal(Data()) },
            { try await group.revokeProposal(Data()) },
            { _ = try await group.prepareCommit() },
            { _ = try await group.acceptCommit(Data()) },
            { _ = try await group.export(label: "test", context: Data(), length: -1) },
            { _ = try await group.epochAuthenticator() },
        ]
        for operation in operations {
            let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; try await operation() }
            await #expect(throws: CancellationError.self) { try await cancelled.value }
        }
        #expect(await group.snapshot() == before)
        #expect(try await group.export(label: "test", context: Data(), length: 32).count == 32)
        #expect(try await group.epochAuthenticator().count == 32)
        let joinOwner = try MLSKeyPackageOwner(userID: 2)
        let cancelledJoin = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await joinOwner.join(welcome: Data(), expectedGroupID: groupID, policy: policy)
        }
        await #expect(throws: CancellationError.self) { try await cancelledJoin.value }
        let alternate = try await joinOwner.createGroup(groupID: Data([2]), policy: policy)
        #expect(await alternate.snapshot().epoch == 0)
        await alternate.close(); await group.close()
    }

    /// Rejects wrong delivery signatures, destinations and participant assertions before mutating proposal storage.
    @Test func proposalAuthenticationAndIdentity() async throws {
        let policy = try MLSGroupPolicy(externalSender: externalSender(), expectedParticipants: [1, 2])
        let creator = try MLSKeyPackageOwner(userID: 1)
        let group = try await creator.createGroup(groupID: groupID, policy: policy); let before = await group.snapshot()
        let identity = try MLSCredential.discord(userID: 2).identity
        let validPackage = try package(identity: identity)
        let wrongKey = try MLSProposal.add(validPackage).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: Data(repeating: 10, count: 32))
        await #expect(throws: MLSError.invalidSignature) { try await group.cacheProposal(wrongKey) }
        for (id, epoch) in [(Data([0]), UInt64(0)), (groupID, UInt64(1))] {
            let bytes = try MLSProposal.add(validPackage).externalMessage(groupID: id, epoch: epoch, signaturePrivateKey: externalPrivateKey)
            await #expect(throws: MLSError.wrongEpoch) { try await group.cacheProposal(bytes) }
        }
        let extensionValue = try MLSExtension(type: 1, data: Data())
        let invalidPackages = [
            try package(identity: Data(count: 7)), try package(identity: Data(count: 8)),
            try package(identity: MLSCredential.discord(userID: 3).identity),
            try package(identity: identity, leafExtensions: [extensionValue]),
        ]
        for package in invalidPackages {
            let bytes = try MLSProposal.add(package).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
            await #expect(throws: MLSError.invalidCredential) { try await group.cacheProposal(bytes) }
        }
        #expect(await group.snapshot() == before)
        let expired = try package(identity: identity, lifetime: MLSLifetime(notBefore: 1, notAfter: 2))
        let accepted = try MLSProposal.add(expired).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        #expect(try await group.cacheProposal(accepted).count == 32)
        #expect(await group.snapshot().pendingProposalCount == 1)
        let grease = try MLSExtension(type: 0xfafa, data: Data([7]))
        let extensible = try package(identity: identity, packageExtensions: [grease])
        let extensibleBytes = try MLSProposal.add(extensible).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        #expect(try await group.cacheProposal(extensibleBytes).count == 32)
        #expect(await group.snapshot().pendingProposalCount == 2)
        await group.close()
    }

    /// Enforces proposal count, per-message bytes and aggregate byte budgets without eviction, including idempotent duplicates.
    @Test func proposalCapacityWithoutEviction() async throws {
        let sender = try externalSender(); let second = try MLSKeyPackageOwner(userID: 2); let third = try MLSKeyPackageOwner(userID: 3)
        let firstBytes = try MLSProposal.add(second.keyPackage).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        let thirdBytes = try MLSProposal.add(third.keyPackage).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2, 3], maximumProposals: 1, maximumMessageBytes: 1024)
        let creator = try MLSKeyPackageOwner(userID: 1); let group = try await creator.createGroup(groupID: groupID, policy: policy)
        let reference = try await group.cacheProposal(firstBytes); let full = await group.snapshot()
        #expect(try await group.cacheProposal(firstBytes) == reference); #expect(await group.snapshot() == full)
        await #expect(throws: MLSError.capacityExceeded) { try await group.cacheProposal(thirdBytes) }
        await #expect(throws: MLSError.capacityExceeded) { try await group.cacheProposal(Data(count: 1025)) }
        #expect(await group.snapshot() == full)
        try await group.revokeProposal(reference); #expect(await group.snapshot().pendingProposalBytes == 0)
        _ = try await group.cacheProposal(thirdBytes); #expect(await group.snapshot().pendingProposalCount == 1)
        await group.close()

        let largerThird = try MLSProposal.add(third.keyPackage).externalMessage(groupID: groupID, epoch: 0,
            signaturePrivateKey: externalPrivateKey, authenticatedData: Data(count: 600))
        let byteBudget = firstBytes.count + largerThird.count - 1
        #expect(byteBudget >= 1024); #expect(firstBytes.count < byteBudget); #expect(largerThird.count < byteBudget)
        let bytePolicy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2, 3],
                                            maximumProposalBytes: byteBudget, maximumMessageBytes: 4096)
        let byteCreator = try MLSKeyPackageOwner(userID: 1); let byteGroup = try await byteCreator.createGroup(groupID: groupID, policy: bytePolicy)
        _ = try await byteGroup.cacheProposal(firstBytes); let retained = await byteGroup.snapshot()
        await #expect(throws: MLSError.capacityExceeded) { try await byteGroup.cacheProposal(largerThird) }
        #expect(await byteGroup.snapshot() == retained); #expect(retained.pendingProposalBytes == firstBytes.count)
        await byteGroup.close(); await second.close(); await third.close()
    }

    /// Revalidates cached identities after trusted participant changes, preserves unchanged candidates, and invalidates real revocations.
    @Test func participantAndRevocationFences() async throws {
        let policy = try MLSGroupPolicy(externalSender: externalSender(), expectedParticipants: [1, 2], maximumMembers: 2)
        let owner = try MLSKeyPackageOwner(userID: 1); let joining = try MLSKeyPackageOwner(userID: 2)
        let group = try await owner.createGroup(groupID: groupID, policy: policy)
        let bytes = try MLSProposal.add(joining.keyPackage).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        let reference = try await group.cacheProposal(bytes); let candidate = try await group.prepareCommit()
        try await group.setExpectedParticipants([1, 2]); #expect(try await group.prepareCommit().commit == candidate.commit)
        try await group.revokeProposal(Data(repeating: 0xff, count: 32)); #expect(await group.snapshot().hasTentativeCommit)
        await #expect(throws: MLSError.invalidProposal) { try await group.revokeProposal(Data(count: 31)) }
        await #expect(throws: MLSError.invalidConfiguration) { try await group.setExpectedParticipants([0]) }
        await #expect(throws: MLSError.invalidConfiguration) { try await group.setExpectedParticipants([1, 2, 3]) }
        #expect(await group.snapshot().hasTentativeCommit)
        try await group.setExpectedParticipants([1]); #expect(await group.snapshot().hasTentativeCommit == false)
        await #expect(throws: MLSError.invalidCredential) { try await group.prepareCommit() }
        #expect(await group.snapshot().epoch == 0); #expect(await group.snapshot().pendingProposalCount == 1)
        try await group.setExpectedParticipants([1, 2]); _ = try await group.prepareCommit()
        try await group.revokeProposal(reference); let revoked = await group.snapshot()
        #expect(!revoked.hasTentativeCommit); #expect(revoked.pendingProposalCount == 0); #expect(revoked.pendingProposalBytes == 0)
        await #expect(throws: MLSError.invalidCommit) { try await group.prepareCommit() }
        await group.close(); await joining.close()
    }

    /// Bounds exporter work before hashing/derivation and keeps invalid requests independent of authenticated epoch state.
    @Test func exporterBoundsAndOwnership() async throws {
        let policy = try MLSGroupPolicy(externalSender: externalSender(), expectedParticipants: [1], maximumMessageBytes: 1024)
        let owner = try MLSKeyPackageOwner(userID: 1); let group = try await owner.createGroup(groupID: groupID, policy: policy)
        let before = await group.snapshot()
        #expect(try await group.export(label: "test", context: Data(), length: 0).isEmpty)
        let first = try await group.export(label: "test", context: Data([1]), length: 32)
        #expect(first.count == 32); #expect(try await group.export(label: "test", context: Data([1]), length: 32) == first)
        #expect(try await group.export(label: "other", context: Data([1]), length: 32) != first)
        #expect(try await group.export(label: "test", context: Data([2]), length: 32) != first)
        #expect(try await group.export(label: String(repeating: "a", count: 1024), context: Data(count: 1024), length: 1).count == 1)
        await #expect(throws: MLSError.capacityExceeded) { try await group.export(label: "test", context: Data(count: 1025), length: 32) }
        await #expect(throws: MLSError.capacityExceeded) { try await group.export(label: String(repeating: "a", count: 1025), context: Data(), length: 32) }
        for length in [-1, 8161, 65_536] {
            await #expect(throws: MLSError.invalidConfiguration) { try await group.export(label: "test", context: Data(), length: length) }
        }
        #expect(await group.snapshot() == before); await group.close()
    }

    /// Rejects invalid Welcomes without consuming init keys, then recovers a closed member with a fresh package authorized by Remove+Add.
    @Test func correctedWelcomeAndFreshPackageRecovery() async throws {
        let policy = try MLSGroupPolicy(externalSender: externalSender(), expectedParticipants: [1, 2])
        let owner = try MLSKeyPackageOwner(userID: 1); let joining = try MLSKeyPackageOwner(userID: 2)
        let group = try await owner.createGroup(groupID: groupID, policy: policy)
        let add = try MLSProposal.add(joining.keyPackage).externalMessage(groupID: groupID, epoch: 0, signaturePrivateKey: externalPrivateKey)
        _ = try await group.cacheProposal(add); let candidate = try await group.prepareCommit()
        let welcome = try #require(candidate.welcome)
        await #expect(throws: MLSError.malformedEncoding) { try await joining.join(welcome: welcome + Data([0]), expectedGroupID: groupID, policy: policy) }
        await #expect(throws: MLSError.invalidCommit) { try await joining.join(welcome: welcome, expectedGroupID: Data([2]), policy: policy) }
        #expect(try await group.acceptCommit(candidate.commit) == .advanced)
        let member = try await joining.join(welcome: welcome, expectedGroupID: groupID, policy: policy)
        #expect(await member.snapshot().epoch == 1)
        #expect(try await member.epochAuthenticator() == group.epochAuthenticator())
        await #expect(throws: MLSError.closed) { try await joining.join(welcome: welcome, expectedGroupID: groupID, policy: policy) }
        await member.close()

        let fresh = try MLSKeyPackageOwner(userID: 2)
        let remove = try MLSProposal.remove(1).externalMessage(groupID: groupID, epoch: 1, signaturePrivateKey: externalPrivateKey)
        let replacement = try MLSProposal.add(fresh.keyPackage).externalMessage(groupID: groupID, epoch: 1, signaturePrivateKey: externalPrivateKey)
        _ = try await group.cacheProposal(remove); _ = try await group.cacheProposal(replacement)
        let recovery = try await group.prepareCommit(); let recoveryWelcome = try #require(recovery.welcome)
        #expect(try await group.acceptCommit(recovery.commit) == .advanced)
        let recovered = try await fresh.join(welcome: recoveryWelcome, expectedGroupID: groupID, policy: policy)
        #expect(await recovered.snapshot().epoch == 2); #expect(await recovered.snapshot().memberCount == 2)
        #expect(try await recovered.epochAuthenticator() == group.epochAuthenticator())
        await #expect(throws: MLSError.closed) { try await member.acceptCommit(recovery.commit) }
        await #expect(throws: MLSError.closed) { try await fresh.join(welcome: recoveryWelcome, expectedGroupID: groupID, policy: policy) }
        await recovered.close(); await group.close()
    }
}
