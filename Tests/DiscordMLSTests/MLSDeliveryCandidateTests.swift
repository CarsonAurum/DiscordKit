import Foundation
import Testing
@testable import DiscordMLS

/// Structural delivery splitting deliberately establishes no MLS authentication.
@Suite struct MLSDeliveryCandidateTests {
    /// Constructs structurally canonical, deliberately unauthenticated Commit/Welcome bytes.
    /// - Parameters:
    ///   - epoch: Pre-commit epoch, default seven; maximum exercises overflow rejection.
    ///   - member: True selects a member sender; false selects forbidden external sender.
    ///   - proposal: True replaces the Commit with a forbidden public proposal.
    /// - Returns: Public Commit and optional Welcome fixture bytes with their MLS wrappers.
    /// - Throws: Bounded MLS wire encoding failures.
    private func fixture(epoch: UInt64 = 7, member: Bool = true, proposal: Bool = false) throws -> (Data, Data) {
        var message = MLSPublicMessage(groupID: Data([1]), epoch: epoch,
            sender: member ? .member(0) : .external(0),
            body: proposal ? .proposal(.remove(0)) : .commit(MLSCommit(references: [], path: nil)))
        message.signature = Data([1]); message.confirmationTag = Data(count: 32); message.membershipTag = Data(count: 32)
        let welcome = MLSWelcome(secrets: [(Data(repeating: 1, count: 32),
            MLSHPKECiphertext(kemOutput: Data(repeating: 2, count: 65), ciphertext: Data(repeating: 3, count: 16)))],
            encryptedGroupInfo: Data([4]))
        return try (message.encoded(), welcome.encoded())
    }

    /// Complete Commit-only and Commit+bare-Welcome candidates split exactly, including
    /// normalized data slices; unauthenticated signatures are not falsely validated.
    /// - Throws: Fixture encoding or structural decoder errors.
    @Test func splitsCanonicalCandidateAndRestoresWelcomeWrapper() throws {
        let (commit, welcome) = try fixture()
        let standalone = try MLSTentativeCommit.decodeDAVECommitWelcome(commit)
        #expect(standalone.commit == commit && standalone.welcome == nil && standalone.epoch == 8)
        let wire = commit + welcome.dropFirst(4)
        let result = try MLSTentativeCommit.decodeDAVECommitWelcome(wire, maximumBytes: wire.count)
        #expect(result.commit == commit && result.welcome == welcome && result.epoch == 8)
        let backing = Data(repeating: 255, count: 1024) + wire
        let slice = try MLSTentativeCommit.decodeDAVECommitWelcome(backing.suffix(wire.count))
        #expect(slice.commit == commit && slice.welcome == welcome)
    }

    /// Size/configuration, sender/type, epoch-overflow and malformed/trailing Welcome
    /// boundaries fail before any candidate can be delivered as a valid structure.
    /// - Throws: Fixture encoding failures.
    @Test func rejectsConfigurationWrongTypesOverflowAndTrailingBytes() throws {
        let (commit, welcome) = try fixture()
        for limit in [Int.min, -1, 0, 1_048_577, Int.max] {
            #expect(throws: MLSError.invalidConfiguration) {
                try MLSTentativeCommit.decodeDAVECommitWelcome(commit, maximumBytes: limit)
            }
        }
        #expect(throws: MLSError.capacityExceeded) {
            try MLSTentativeCommit.decodeDAVECommitWelcome(commit, maximumBytes: commit.count - 1)
        }
        for bad in [try fixture(epoch: UInt64.max).0, try fixture(member: false).0, try fixture(proposal: true).0] {
            #expect(throws: MLSError.invalidCommit) { try MLSTentativeCommit.decodeDAVECommitWelcome(bad) }
        }
        let wire = commit + welcome.dropFirst(4)
        for end in 0..<wire.count where end != commit.count {
            #expect(throws: MLSError.self) { try MLSTentativeCommit.decodeDAVECommitWelcome(Data(wire.prefix(end))) }
        }
        #expect(throws: MLSError.self) { try MLSTentativeCommit.decodeDAVECommitWelcome(wire + Data([0])) }
        #expect(throws: MLSError.self) { try MLSTentativeCommit.decodeDAVECommitWelcome(commit + welcome) }
        var unsupported = commit; unsupported[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSTentativeCommit.decodeDAVECommitWelcome(unsupported) }
    }
}
