import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// DAVE delivery vectors and competing pending creators use real owned MLS
/// structures and injected signing authorities, with no network or credentials.
@Suite struct MLSDeliveryTests {
    /// Builds authenticated external Remove proposals for deterministic framing
    /// tests. Signature bytes are random but are never used as expected answers.
    /// - Parameter index: Leaf index retained exactly in the resulting proposal.
    /// - Returns: A complete canonical external MLS PublicMessage.
    /// - Throws: Crypto or bounded encoder errors.
    private func proposal(_ index: UInt32) throws -> Data {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        return try MLSProposal.remove(index).externalMessage(groupID: Data([1]), epoch: UInt64.max,
                                                              signaturePrivateKey: key.rawRepresentation)
    }

    /// Empty and ordered multiple-message vectors preserve canonical message bytes;
    /// the maximum message budget is inclusive and no partial array escapes overflow.
    @Test func externalDeliveryBoundariesAndCanonicalRoundTrip() throws {
        #expect(try MLSProposal.splitExternalMessages(Data()).isEmpty)
        let first = try proposal(0); let second = try proposal(UInt32.max)
        #expect(try MLSProposal.splitExternalMessages(first, maximumMessages: 1) == [first])
        #expect(try MLSProposal.splitExternalMessages(first + second, maximumMessages: 2) == [first, second])
        #expect(throws: MLSError.capacityExceeded) {
            try MLSProposal.splitExternalMessages(first + second, maximumMessages: 1)
        }
        for limit in [0, -1, 1025] {
            #expect(throws: MLSError.invalidConfiguration) { try MLSProposal.splitExternalMessages(Data(), maximumMessages: limit) }
        }
        let maximum = Array(repeating: first, count: 1024).reduce(Data(), +)
        #expect(try MLSProposal.splitExternalMessages(maximum, maximumMessages: 1024).count == 1024)
        #expect(throws: MLSError.capacityExceeded) {
            try MLSProposal.splitExternalMessages(Data(repeating: 0, count: 1_048_577))
        }
        let owner = try MLSKeyPackageOwner(userID: UInt64.max)
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        let add = try MLSProposal.add(owner.keyPackage).externalMessage(groupID: Data([2]), epoch: 0,
                                                                        signaturePrivateKey: signing.rawRepresentation)
        #expect(try MLSProposal.splitExternalMessages(add + first) == [add, first])
    }

    /// Every incomplete message is rejected, including truncation after a complete
    /// prefix message. Noncanonical vector lengths and trailing junk are not ignored.
    @Test func truncatedAndNoncanonicalExternalDelivery() throws {
        let bytes = try proposal(1)
        for count in 1..<bytes.count {
            #expect(throws: (any Error).self) { try MLSProposal.splitExternalMessages(Data(bytes.prefix(count))) }
            #expect(throws: (any Error).self) { try MLSProposal.splitExternalMessages(bytes + Data(bytes.prefix(count))) }
        }
        var noncanonical = Data(bytes.prefix(4))
        noncanonical.append(contentsOf: [0x40, 0x01])
        noncanonical.append(bytes.dropFirst(5))
        #expect(throws: MLSError.malformedEncoding) { try MLSProposal.splitExternalMessages(noncanonical) }
        #expect(throws: MLSError.malformedEncoding) { try MLSProposal.splitExternalMessages(bytes + Data([0])) }
        var version = bytes; version[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSProposal.splitExternalMessages(version) }
        var wireFormat = bytes; wireFormat[3] = 2
        #expect(throws: MLSError.invalidCommit) { try MLSProposal.splitExternalMessages(wireFormat) }
    }

    /// Split framing accepts only external sender index zero and Add/Remove
    /// proposals. It never promotes a member proposal or Commit to a valid delivery.
    @Test func unsupportedSenderAndBodyAreRejected() throws {
        for sender in [MLSSender.member(0), .external(1)] {
            let message = MLSPublicMessage(groupID: Data([1]), epoch: 1, sender: sender, body: .proposal(.remove(0)))
            #expect(throws: MLSError.invalidProposal) { try MLSProposal.splitExternalMessages(message.encoded()) }
        }
        let commit = MLSPublicMessage(groupID: Data([1]), epoch: 1, sender: .external(0),
                                      body: .commit(MLSCommit(references: [], path: nil)))
        #expect(throws: MLSError.invalidProposal) { try MLSProposal.splitExternalMessages(commit.encoded()) }
        var writer = MLSWriter()
        writer.write(UInt16(1)); writer.write(UInt16(1)); try writer.writeVector(Data([1])); writer.write(UInt64(1))
        MLSSender.external(0).write(to: &writer); try writer.writeVector(Data())
        writer.write(UInt8(2)); writer.write(UInt16(2))
        #expect(throws: MLSError.invalidProposal) { try MLSProposal.splitExternalMessages(writer.data) }
    }

    /// Competing pending creators retain the original package for the winner's
    /// Welcome, while a second creation is prohibited. Established key projections
    /// agree exactly, and authenticated removal immediately removes access to them.
    @Test func losingPendingCreatorJoinsWinnerAndProjectsMembers() async throws {
        let external = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: external.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data("gateway".utf8)))
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, UInt64.max])
        let ownerA = try MLSKeyPackageOwner(userID: 1)
        let ownerB = try MLSKeyPackageOwner(userID: UInt64.max)
        let groupID = Data([1, 2, 3])
        let groupA = try await ownerA.createGroup(groupID: groupID, policy: policy, retainForWelcome: true)
        let losing = try await ownerB.createGroup(groupID: groupID, policy: policy, retainForWelcome: true)
        await #expect(throws: MLSError.closed) { try await ownerA.createGroup(groupID: groupID, policy: policy, retainForWelcome: true) }
        await #expect(throws: MLSError.closed) { try await ownerB.createGroup(groupID: groupID, policy: policy) }
        await #expect(throws: MLSError.wrongEpoch) { try await groupA.memberIdentities() }
        let addB = try MLSProposal.add(ownerB.keyPackage).externalMessage(groupID: groupID, epoch: 0,
                                                                         signaturePrivateKey: external.rawRepresentation)
        let addA = try MLSProposal.add(ownerA.keyPackage).externalMessage(groupID: groupID, epoch: 0,
                                                                         signaturePrivateKey: external.rawRepresentation)
        _ = try await groupA.cacheProposal(addB); _ = try await losing.cacheProposal(addA)
        let selected = try await groupA.prepareCommit(); _ = try await losing.prepareCommit()
        await losing.close()
        await #expect(throws: MLSError.closed) { try await losing.memberIdentities() }
        let welcome = try #require(selected.welcome)
        let groupB = try await ownerB.join(welcome: welcome, expectedGroupID: groupID, policy: policy)
        #expect(try await groupA.acceptCommit(selected.commit) == .advanced)
        await ownerA.close()
        await #expect(throws: MLSError.closed) { try await ownerA.join(welcome: welcome, expectedGroupID: groupID, policy: policy) }
        await #expect(throws: MLSError.closed) { try await ownerB.join(welcome: welcome, expectedGroupID: groupID, policy: policy) }
        let expected = [UInt64(1): ownerA.keyPackage.leafNode.signatureKey, UInt64.max: ownerB.keyPackage.leafNode.signatureKey]
        #expect(try await groupA.memberIdentities() == expected)
        #expect(try await groupB.memberIdentities() == expected)
        #expect(try await groupA.epochAuthenticator() == groupB.epochAuthenticator())
        let removal = try MLSProposal.remove(1).externalMessage(groupID: groupID, epoch: 1,
                                                                signaturePrivateKey: external.rawRepresentation)
        _ = try await groupA.cacheProposal(removal); _ = try await groupB.cacheProposal(removal)
        let candidate = try await groupA.prepareCommit()
        #expect(try await groupB.acceptCommit(candidate.commit) == .removed)
        #expect(try await groupA.acceptCommit(candidate.commit) == .advanced)
        #expect(try await groupA.memberIdentities() == [UInt64(1): ownerA.keyPackage.leafNode.signatureKey])
        await #expect(throws: MLSError.closed) { try await groupB.memberIdentities() }
        await groupA.close()
        await #expect(throws: MLSError.closed) { try await groupA.memberIdentities() }
    }

    /// Cancellation before pending creation and member projection preserves the
    /// package/group for a subsequent successful caller without sleeps or I/O.
    @Test func cancellationBeforeCreationAndProjectionPreservesOwnership() async throws {
        let external = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: external.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data([1])))
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1])
        let owner = try MLSKeyPackageOwner(userID: 1)
        let cancelledCreation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) {
                try await owner.createGroup(groupID: Data([1]), policy: policy, retainForWelcome: true)
            }
        }
        await cancelledCreation.value
        let group = try await owner.createGroup(groupID: Data([1]), policy: policy, retainForWelcome: true)
        let cancelledProjection = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await group.memberIdentities() }
        }
        await cancelledProjection.value
        #expect(await group.snapshot().epoch == 0)
        await #expect(throws: MLSError.wrongEpoch) { try await group.memberIdentities() }
        await group.close(); await owner.close()
    }
}
