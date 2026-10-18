import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// End-to-end offline DAVE-profile MLS lifecycle. No transport, device, Discord
/// credentials, clocks or sleeps are used; random keys are not expected answers.
@Suite struct MLSGroupTests {
    /// Creates independent package owners sharing an authenticated external-sender policy.
    /// - Parameters:
    ///   - ids: Distinct nonzero participant identities authorized for the scenario.
    ///   - maximumProposals: Cache budget used to exercise bounded admission.
    /// - Returns: Isolated signing authority, policy, package owners and unique group ID.
    /// - Throws: Key/credential/policy construction errors.
    private func fixture(_ ids: [UInt64], maximumProposals: Int = 256) throws -> (external: Data, policy: MLSGroupPolicy, owners: [MLSKeyPackageOwner], groupID: Data) {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: key.publicKey.x963Representation, credential: MLSCredential(identity: Data("gateway".utf8)))
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: Set(ids), maximumProposals: maximumProposals)
        return try (key.rawRepresentation, policy, ids.map { try MLSKeyPackageOwner(userID: $0) }, Data(UUID().uuidString.utf8))
    }

    /// Signs a synthetic trusted Add and delivers exactly the same reference to each owner.
    /// - Parameters:
    ///   - package: Package whose user ID belongs to the scenario's authorized set.
    ///   - epoch: Exact current epoch for every receiving group.
    ///   - groups: Distinct group actors at a shared authenticated state.
    ///   - external: Test-only external signing key.
    ///   - groupID: Exact scenario group ID.
    /// - Returns: The common RFC proposal reference.
    /// - Throws: Authentication/admission errors or a reference mismatch assertion.
    private func add(_ package: MLSKeyPackage, epoch: UInt64, groups: [MLSGroup], external: Data, groupID: Data) async throws -> Data {
        let bytes = try MLSProposal.add(package).externalMessage(groupID: groupID, epoch: epoch, signaturePrivateKey: external)
        var reference = Data()
        for group in groups {
            let accepted = try await group.cacheProposal(bytes)
            if reference.isEmpty { reference = accepted } else { #expect(reference == accepted) }
        }
        return reference
    }

    /// Compares explicit exporters and authenticators across the currently admitted members.
    /// - Parameters:
    ///   - groups: Nonempty current-epoch owners expected to share secrets.
    ///   - epoch: Expected epoch after the last selected commit.
    /// - Throws: Closed/derivation errors or failed consistency assertions.
    private func expectAgreement(_ groups: [MLSGroup], epoch: UInt64) async throws {
        let first = try #require(groups.first)
        let exported = try await first.export(label: "test-only", context: Data([1, 2, 3]), length: 32)
        let authenticator = try await first.epochAuthenticator()
        #expect(exported.count == 32); #expect(authenticator.count == 32)
        for group in groups {
            #expect(try await group.export(label: "test-only", context: Data([1, 2, 3]), length: 32) == exported)
            #expect(try await group.epochAuthenticator() == authenticator)
            #expect(await group.snapshot().epoch == epoch)
            #expect(await group.snapshot().pendingProposalCount == 0)
            #expect(await group.snapshot().hasTentativeCommit == false)
        }
    }

    /// Exercises four independent members, two initial additions, concurrent candidate
    /// selection, old-owner removal with same-index same-identity replacement, tampered
    /// Welcome rejection without package consumption, and explicit resource cleanup.
    /// All admitted members must agree on exporters/authenticators after every epoch.
    @Test func membershipEpochsConcurrentSelectionAndReplacement() async throws {
        let setup = try fixture([UInt64.max, 2, 3, 4])
        let a = try await setup.owners[0].createGroup(groupID: setup.groupID, policy: setup.policy)
        _ = try await add(setup.owners[1].keyPackage, epoch: 0, groups: [a], external: setup.external, groupID: setup.groupID)
        let first = try await a.prepareCommit()
        #expect(await a.snapshot().epoch == 0)
        #expect(try await a.prepareCommit().commit == first.commit)
        let welcome = try #require(first.welcome)
        var damaged = welcome; damaged[damaged.index(before: damaged.endIndex)] ^= 1
        await #expect(throws: MLSError.self) { try await setup.owners[1].join(welcome: damaged, expectedGroupID: setup.groupID, policy: setup.policy) }
        let b = try await setup.owners[1].join(welcome: welcome, expectedGroupID: setup.groupID, policy: setup.policy)
        #expect(try await a.acceptCommit(first.commit) == .advanced)
        await #expect(throws: MLSError.closed) { try await setup.owners[1].join(welcome: welcome, expectedGroupID: setup.groupID, policy: setup.policy) }
        try await expectAgreement([a, b], epoch: 1)
        let previous = try await a.export(label: "test-only", context: Data([1, 2, 3]), length: 32)

        _ = try await add(setup.owners[2].keyPackage, epoch: 1, groups: [a, b], external: setup.external, groupID: setup.groupID)
        _ = try await add(setup.owners[3].keyPackage, epoch: 1, groups: [a, b], external: setup.external, groupID: setup.groupID)
        async let aCandidate = a.prepareCommit(); async let bCandidate = b.prepareCommit()
        let (winner, loser) = try await (aCandidate, bCandidate)
        let secondWelcome = try #require(winner.welcome)
        let c = try await setup.owners[2].join(welcome: secondWelcome, expectedGroupID: setup.groupID, policy: setup.policy)
        let d = try await setup.owners[3].join(welcome: secondWelcome, expectedGroupID: setup.groupID, policy: setup.policy)
        #expect(try await a.acceptCommit(winner.commit) == .advanced)
        #expect(try await b.acceptCommit(winner.commit) == .advanced)
        await #expect(throws: MLSError.wrongEpoch) { try await b.acceptCommit(loser.commit) }
        try await expectAgreement([a, b, c, d], epoch: 2)
        #expect(try await a.export(label: "test-only", context: Data([1, 2, 3]), length: 32) != previous)

        let replacement = try MLSKeyPackageOwner(userID: UInt64.max)
        let removal = try MLSProposal.remove(0).externalMessage(groupID: setup.groupID, epoch: 2, signaturePrivateKey: setup.external)
        for group in [a, b, c, d] { _ = try await group.cacheProposal(removal) }
        _ = try await add(replacement.keyPackage, epoch: 2, groups: [a, b, c, d], external: setup.external, groupID: setup.groupID)
        await #expect(throws: MLSError.invalidProposal) { try await a.prepareCommit() }
        let third = try await b.prepareCommit()
        let fresh = try await replacement.join(welcome: #require(third.welcome), expectedGroupID: setup.groupID, policy: setup.policy)
        #expect(try await a.acceptCommit(third.commit) == .removed)
        for group in [b, c, d] { #expect(try await group.acceptCommit(third.commit) == .advanced) }
        #expect(await a.snapshot().isClosed)
        await #expect(throws: MLSError.closed) { try await a.epochAuthenticator() }
        try await expectAgreement([fresh, b, c, d], epoch: 3)
        for group in [a, fresh, b, c, d] { await group.close(); await group.close(); #expect(await group.snapshot().memberCount == 0) }
    }

    /// Checks exact external-sender signatures, participant binding, epoch scopes,
    /// duplicate/revoked references, aggregate admission and rollback on malformed input.
    @Test func authenticatedProposalAdmissionRevocationAndBounds() async throws {
        let setup = try fixture([1, 2, 3], maximumProposals: 1)
        let group = try await setup.owners[0].createGroup(groupID: setup.groupID, policy: setup.policy)
        let bytes = try MLSProposal.add(setup.owners[1].keyPackage).externalMessage(groupID: setup.groupID, epoch: 0, signaturePrivateKey: setup.external)
        let wrong = P256.Signing.PrivateKey(compactRepresentable: false)
        let forged = try MLSProposal.add(setup.owners[1].keyPackage).externalMessage(groupID: setup.groupID, epoch: 0, signaturePrivateKey: wrong.rawRepresentation)
        await #expect(throws: MLSError.invalidSignature) { try await group.cacheProposal(forged) }
        let outsider = try MLSKeyPackageOwner(userID: 999)
        let unexpected = try MLSProposal.add(outsider.keyPackage).externalMessage(groupID: setup.groupID, epoch: 0, signaturePrivateKey: setup.external)
        await #expect(throws: MLSError.invalidCredential) { try await group.cacheProposal(unexpected) }
        let future = try MLSProposal.add(setup.owners[1].keyPackage).externalMessage(groupID: setup.groupID, epoch: 1, signaturePrivateKey: setup.external)
        await #expect(throws: MLSError.wrongEpoch) { try await group.cacheProposal(future) }
        let reference = try await group.cacheProposal(bytes)
        #expect(try await group.cacheProposal(bytes) == reference)
        #expect(await group.snapshot().pendingProposalCount == 1)
        #expect(await group.snapshot().pendingProposalBytes == bytes.count)
        _ = try await group.prepareCommit()
        let another = try MLSProposal.add(setup.owners[2].keyPackage).externalMessage(groupID: setup.groupID, epoch: 0, signaturePrivateKey: setup.external)
        await #expect(throws: MLSError.capacityExceeded) { try await group.cacheProposal(another) }
        #expect(await group.snapshot().hasTentativeCommit)
        try await group.revokeProposal(Data(repeating: 1, count: 32))
        #expect(await group.snapshot().hasTentativeCommit)
        try await group.revokeProposal(reference)
        #expect(await group.snapshot().pendingProposalBytes == 0)
        #expect(await group.snapshot().hasTentativeCommit == false)
        await #expect(throws: MLSError.invalidCommit) { try await group.prepareCommit() }
        try await group.setExpectedParticipants([1])
        await #expect(throws: MLSError.invalidCredential) { try await group.cacheProposal(bytes) }
        #expect(await group.snapshot().epoch == 0)
        await group.close()
        #expect(String(reflecting: group).contains("REDACTED"))
        #expect(Mirror(reflecting: group).children.count == 1)
    }

    /// Duplicate identities/packages cannot enter a candidate; initial local groups
    /// cannot accept another creator's winning commit, and malformed remote commits
    /// preserve the current epoch and its exact exporter.
    @Test func duplicateMembersInitialIsolationAndRemoteTampering() async throws {
        let setup = try fixture([1, 2, 3])
        let a = try await setup.owners[0].createGroup(groupID: setup.groupID, policy: setup.policy)
        _ = try await add(setup.owners[1].keyPackage, epoch: 0, groups: [a], external: setup.external, groupID: setup.groupID)
        let initial = try await a.prepareCommit()
        let b = try await setup.owners[1].join(welcome: #require(initial.welcome), expectedGroupID: setup.groupID, policy: setup.policy)
        #expect(try await a.acceptCommit(initial.commit) == .advanced)
        let duplicate = try MLSKeyPackageOwner(userID: 2)
        _ = try await add(duplicate.keyPackage, epoch: 1, groups: [a], external: setup.external, groupID: setup.groupID)
        await #expect(throws: MLSError.invalidCredential) { try await a.prepareCommit() }
        await a.close()
        _ = try await add(setup.owners[2].keyPackage, epoch: 1, groups: [b], external: setup.external, groupID: setup.groupID)
        let selected = try await b.prepareCommit()
        let prior = try await b.epochAuthenticator(); let before = await b.snapshot()
        var tampered = selected.commit; tampered[tampered.index(before: tampered.endIndex)] ^= 1
        await #expect(throws: MLSError.self) { try await b.acceptCommit(tampered) }
        #expect(try await b.epochAuthenticator() == prior); #expect(await b.snapshot() == before)
        let otherOwner = try MLSKeyPackageOwner(userID: 1)
        let initialOther = try await otherOwner.createGroup(groupID: setup.groupID, policy: setup.policy)
        await #expect(throws: MLSError.invalidCommit) { try await initialOther.acceptCommit(initial.commit) }
        await b.close(); await initialOther.close()
    }
}
