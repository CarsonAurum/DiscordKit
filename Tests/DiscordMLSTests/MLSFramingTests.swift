import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Exact public framing, signature and membership-MAC boundaries independent of group acceptance policy.
@Suite struct MLSFramingTests {
    /// Decodes a fixed hexadecimal literal, failing malformed fixture data before comparisons.
    /// - Parameter value: Even-length ASCII hexadecimal.
    /// - Returns: Exact literal bytes.
    /// - Throws: A failed requirement for malformed fixture bytes.
    private func hex(_ value: String) throws -> Data {
        let chars = Array(value); try #require(chars.count.isMultiple(of: 2))
        return try Data(stride(from: 0, to: chars.count, by: 2).map {
            try #require(UInt8(String(chars[$0...($0 + 1)]), radix: 16))
        })
    }

    /// Creates a deterministic current-epoch context for member authentication checks.
    /// - Returns: Epoch-five context with SHA-256 sized public fields.
    /// - Throws: Structural context errors if fixture data becomes invalid.
    private func context() throws -> MLSGroupContext {
        try MLSGroupContext(groupID: Data([1]), epoch: 5, treeHash: Data(repeating: 2, count: 32),
                            confirmedTranscriptHash: Data(repeating: 3, count: 32))
    }

    /// Constructs a synthetic member commit with separately owned signature, confirmation and membership fields.
    /// - Returns: Signed/MACed message, signing public key and current membership secret.
    /// - Throws: Key/signing/context/wire errors during fixture construction.
    private func memberCommit() throws -> (message: MLSPublicMessage, key: Data, membership: Data) {
        let privateKey = Data(repeating: 6, count: 32)
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.x963Representation
        let membership = Data(repeating: 7, count: 32)
        let commit = MLSCommit(references: [Data(repeating: 1, count: 32)], path: nil)
        var message = MLSPublicMessage(groupID: Data([1]), epoch: 5, sender: .member(7),
                                       authenticatedData: Data([9]), body: .commit(commit))
        message.signature = try MLSCipherSuite2.signWithLabel(privateKey: privateKey, label: "FramedContentTBS",
                                                              content: message.signatureInput(context: context()))
        message.confirmationTag = Data(0...31)
        message.membershipTag = try MLSCipherSuite2.mac(key: membership, content: message.membershipInput(context: context()))
        return (message, publicKey, membership)
    }

    /// Checks external-remove bytes and proposal reference against a separately computed SHA-256 known answer.
    @Test func canonicalProposalReferenceBytes() throws {
        var message = MLSPublicMessage(groupID: Data([1, 2, 3]), epoch: .max, sender: .external(0),
                                       authenticatedData: Data([0xa1, 0xa2]), body: .proposal(.remove(7)))
        message.signature = Data([9, 8])
        let content = try hex("03010203ffffffffffffffff020000000002a1a202000300000007")
        #expect(try message.framedContent() == content)
        #expect(try message.signatureInput(context: nil) == Data([0, 1, 0, 1]) + content)
        #expect(try message.authData() == Data([2, 9, 8]))
        let authenticated = Data([0, 1]) + content + Data([2, 9, 8])
        #expect(try message.authenticatedContent() == authenticated)
        #expect(try message.transcriptInput() == authenticated)
        #expect(try message.encoded() == Data([0, 1, 0, 1]) + content + Data([2, 9, 8]))
        let reference = try MLSCipherSuite2.refHash(label: "MLS 1.0 Proposal Reference", value: message.authenticatedContent())
        #expect(reference == (try hex("15f8b0d6ca4f1882296ff9b17a8cdce8add47a9c5f937fbf43126bdf3bd46ee2")))
        let decoded = try MLSPublicMessage.decode(message.encoded())
        #expect(decoded.sender == .external(0)); #expect(decoded.epoch == .max)
        #expect(decoded.groupID == message.groupID); #expect(decoded.authenticatedData == message.authenticatedData)
        if case .proposal(let proposal) = decoded.body { #expect(proposal == .remove(7)) }
        else { Issue.record("A remove proposal decoded as a commit") }
        #expect(decoded.membershipTag.isEmpty); #expect(decoded.confirmationTag.isEmpty)
        #expect(try decoded.encoded() == message.encoded())
    }

    /// Verifies external proposals bind frame fields, exclude GroupContext and carry no member MAC.
    @Test func externalProposalAuthentication() throws {
        let privateKey = Data(repeating: 8, count: 32)
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.x963Representation
        let bytes = try MLSProposal.remove(.max).externalMessage(groupID: Data([1]), epoch: .max,
                                                                  signaturePrivateKey: privateKey, authenticatedData: Data([2]))
        let message = try MLSPublicMessage.decode(bytes)
        #expect(try MLSCipherSuite2.verifyWithLabel(publicKey: publicKey, label: "FramedContentTBS",
                                                   content: message.signatureInput(context: nil), signature: message.signature))
        #expect(message.membershipTag.isEmpty)
        #expect(throws: MLSError.invalidProposal) { try message.signatureInput(context: context()) }
        #expect(throws: MLSError.invalidProposal) { try message.membershipInput(context: context()) }
        var changed = message; changed.authenticatedData = Data([3])
        #expect(try !MLSCipherSuite2.verifyWithLabel(publicKey: publicKey, label: "FramedContentTBS",
                                                    content: changed.signatureInput(context: nil), signature: changed.signature))
        #expect(throws: MLSError.invalidConfiguration) {
            try MLSProposal.remove(0).externalMessage(groupID: Data(), epoch: 0, signaturePrivateKey: privateKey)
        }
        #expect(throws: MLSError.invalidConfiguration) {
            try MLSProposal.remove(0).externalMessage(groupID: Data(count: 256), epoch: 0, signaturePrivateKey: privateKey)
        }
        #expect(throws: MLSError.invalidConfiguration) {
            try MLSProposal.remove(0).externalMessage(groupID: Data([1]), epoch: 0, signaturePrivateKey: Data())
        }
    }

    /// Preserves allowed sender index widths and rejects reserved, new-member and unsupported proposal selectors.
    @Test func senderAndProposalSelectors() throws {
        for sender in [MLSSender.member(0), .member(.max), .external(0), .external(.max)] {
            var writer = MLSWriter(); sender.write(to: &writer); #expect(writer.data.count == 5)
            var reader = try MLSReader(writer.data); #expect(try MLSSender.decode(&reader) == sender); try reader.requireEnd()
        }
        for value: UInt8 in [0, 3, 4, 255] {
            var reader = try MLSReader(Data([value])); #expect(throws: MLSError.invalidCommit) { try MLSSender.decode(&reader) }
        }
        var removeReader = try MLSReader(MLSProposal.remove(.max).encoded())
        #expect(try MLSProposal.decode(&removeReader) == .remove(.max)); try removeReader.requireEnd()
        for value: UInt16 in [0, 2, 4, 5, 6, 7, .max] {
            var writer = MLSWriter(); writer.write(value); var reader = try MLSReader(writer.data)
            #expect(throws: MLSError.invalidProposal) { try MLSProposal.decode(&reader) }
        }
    }

    /// Checks reference-only commit bytes and rejects duplicate, inline and incorrectly sized references.
    @Test func commitReferenceEncodingAndValidation() throws {
        let references = [Data(repeating: 1, count: 32), Data(repeating: 2, count: 32)]
        let commit = MLSCommit(references: references, path: nil)
        let expected = Data([0x40, 0x44, 2, 32]) + references[0] + Data([2, 32]) + references[1] + Data([0])
        #expect(try commit.encoded() == expected)
        var reader = try MLSReader(expected); let decoded = try MLSCommit.decode(&reader)
        #expect(decoded.references == references); #expect(decoded.path == nil); try reader.requireEnd()
        var empty = try MLSReader(MLSCommit(references: [], path: nil).encoded())
        #expect(try MLSCommit.decode(&empty).references.isEmpty); try empty.requireEnd()
        #expect(throws: MLSError.invalidCommit) { try MLSCommit(references: [Data()], path: nil).encoded() }
        #expect(throws: MLSError.invalidCommit) { try MLSCommit(references: [references[0], references[0]], path: nil).encoded() }
        #expect(throws: MLSError.invalidCommit) { try MLSCommit(references: Array(repeating: references[0], count: 1025), path: nil).encoded() }
        for list in [Data([1, 0, 3, 0, 0, 0, 1]), Data([2, 0]),
                     Data([2, 32]) + references[0] + Data([2, 32]) + references[0]] {
            var writer = MLSWriter(); try writer.writeVector(list); writer.write(UInt8(0))
            var bad = try MLSReader(writer.data)
            #expect(throws: MLSError.invalidCommit) { try MLSCommit.decode(&bad) }
        }
        var invalidPresence = try MLSReader(Data([0, 2]))
        #expect(throws: MLSError.malformedEncoding) { try MLSCommit.decode(&invalidPresence) }
    }

    /// Verifies signature, membership MAC and confirmed transcript cover distinct exact RFC field sets.
    @Test func memberSignatureMACAndTranscriptBoundaries() throws {
        let fixture = try memberCommit(); let message = fixture.message
        let signatureInput = try message.signatureInput(context: context())
        #expect(try MLSCipherSuite2.verifyWithLabel(publicKey: fixture.key, label: "FramedContentTBS",
                                                   content: signatureInput, signature: message.signature))
        #expect(try MLSCipherSuite2.verifyMAC(key: fixture.membership, content: message.membershipInput(context: context()), tag: message.membershipTag))
        #expect(try message.membershipInput(context: context()) == signatureInput + message.authData())
        #expect(throws: MLSError.invalidCommit) { try message.signatureInput(context: nil) }
        let decoded = try MLSPublicMessage.decode(message.encoded()); #expect(try decoded.encoded() == message.encoded())
        #expect(decoded.signature == message.signature); #expect(decoded.confirmationTag == message.confirmationTag)
        #expect(decoded.membershipTag == message.membershipTag)
        var changedConfirmation = message; changedConfirmation.confirmationTag[0] ^= 1
        #expect(try changedConfirmation.signatureInput(context: context()) == signatureInput)
        #expect(try changedConfirmation.transcriptInput() == message.transcriptInput())
        #expect(try changedConfirmation.authenticatedContent() != message.authenticatedContent())
        #expect(try !MLSCipherSuite2.verifyMAC(key: fixture.membership, content: changedConfirmation.membershipInput(context: context()), tag: message.membershipTag))
        var changedMembership = message; changedMembership.membershipTag[0] ^= 1
        #expect(try changedMembership.authenticatedContent() == message.authenticatedContent())
        #expect(try changedMembership.transcriptInput() == message.transcriptInput())
        #expect(try changedMembership.encoded() != message.encoded())
        let wrongContext = try MLSGroupContext(groupID: Data([2]), epoch: 5, treeHash: Data(repeating: 2, count: 32),
                                               confirmedTranscriptHash: Data(repeating: 3, count: 32))
        #expect(try !MLSCipherSuite2.verifyWithLabel(publicKey: fixture.key, label: "FramedContentTBS",
                                                    content: message.signatureInput(context: wrongContext), signature: message.signature))
    }

    /// Rejects every representative truncation, suffix and unsupported wire/content selector before authentication.
    @Test func malformedPublicFrames() throws {
        let fixture = try memberCommit(); let bytes = try fixture.message.encoded()
        for count in 0..<bytes.count { #expect(throws: (any Error).self) { try MLSPublicMessage.decode(bytes.prefix(count)) } }
        #expect(throws: MLSError.malformedEncoding) { try MLSPublicMessage.decode(bytes + Data([0])) }
        var version = bytes; version[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSPublicMessage.decode(version) }
        var wireFormat = bytes; wireFormat[3] = 2
        #expect(throws: MLSError.invalidCommit) { try MLSPublicMessage.decode(wireFormat) }
        var fields = try MLSReader(bytes); _ = try fields.readUInt16(); _ = try fields.readUInt16()
        _ = try fields.readVector(); _ = try fields.readUInt64(); _ = try MLSSender.decode(&fields); _ = try fields.readVector()
        let typeIndex = bytes.count - fields.remainingCount
        for type: UInt8 in [0, 1, 4, 255] {
            var invalid = bytes; invalid[typeIndex] = type
            #expect(throws: MLSError.invalidCommit) { try MLSPublicMessage.decode(invalid) }
        }
        var signature = fixture.message; signature.signature = Data(count: 81)
        #expect(throws: MLSError.malformedEncoding) { try MLSPublicMessage.decode(signature.encoded()) }
        var confirmation = fixture.message; confirmation.confirmationTag = Data(count: 33)
        #expect(throws: MLSError.malformedEncoding) { try MLSPublicMessage.decode(confirmation.encoded()) }
        var membership = fixture.message; membership.membershipTag = Data(count: 33)
        #expect(throws: MLSError.malformedEncoding) { try MLSPublicMessage.decode(membership.encoded()) }
    }
}
