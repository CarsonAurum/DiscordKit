import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Untrusted Welcome framing, secret diagnostics and authenticated join-path consistency.
@Suite struct MLSWelcomeTests {
    /// Creates a fresh signed fixture package with its private signer/leaf scalar.
    /// - Parameter userID: Nonzero Discord identity for the fixture participant.
    /// - Returns: Fresh package and matching test-only signing and leaf keys.
    /// - Throws: Credential, key or signature errors; never performs network access.
    private func package(_ userID: UInt64) throws -> (value: MLSKeyPackage, signing: Data, leaf: Data) {
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        let leaf = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let initial = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        return try (MLSKeyPackage.generate(identity: MLSCredential.discord(userID: userID).identity,
            signaturePrivateKey: signing.rawRepresentation, leafEncryptionKey: leaf.publicKey.x963Representation,
            initKey: initial.publicKey.x963Representation), signing.rawRepresentation, leaf.rawRepresentation)
    }

    /// Builds received GroupSecrets bytes independently of the validating constructor.
    /// - Parameters:
    ///   - joiner: Arbitrary untrusted joiner bytes.
    ///   - present: Optional-value discriminator, including deliberately invalid values.
    ///   - path: Raw path value, encoded only for discriminator one.
    ///   - psks: Raw PSK-list body; this profile requires empty bytes.
    /// - Returns: Canonical vector framing around the supplied malformed or valid fields.
    /// - Throws: Encoding capacity errors.
    private func secretsBytes(joiner: Data, present: UInt8, path: Data = Data(), psks: Data = Data()) throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(joiner); writer.write(present)
        if present == 1 { try writer.writeVector(path) }
        try writer.writeVector(psks); return writer.data
    }

    /// Rejects truncation, suffixes, wrong wrappers, duplicate references, and malformed
    /// recipient fields before treating any structurally received Welcome as authentic.
    @Test func welcomeStructuralBoundaries() throws {
        let encrypted = MLSHPKECiphertext(kemOutput: Data([4]) + Data(repeating: 1, count: 64), ciphertext: Data(repeating: 2, count: 16))
        let reference = Data(repeating: 3, count: 32)
        let message = MLSWelcome(secrets: [(reference, encrypted)], encryptedGroupInfo: Data(repeating: 4, count: 16))
        let encoded = try message.encoded(); let decoded = try MLSWelcome.decode(encoded)
        #expect(decoded.secrets.count == 1 && decoded.secrets[0].reference == reference)
        #expect(decoded.secrets[0].encrypted == encrypted && decoded.encryptedGroupInfo == message.encryptedGroupInfo)
        for count in 0..<encoded.count {
            #expect(throws: (any Error).self) { try MLSWelcome.decode(Data(encoded.prefix(count))) }
        }
        #expect(throws: MLSError.malformedEncoding) { try MLSWelcome.decode(encoded + Data([0])) }
        for (offset, expected) in [(1, MLSError.unsupportedVersion), (3, .invalidCommit), (5, .unsupportedCipherSuite)] {
            var changed = encoded; changed[offset] = 0
            #expect(throws: expected) { try MLSWelcome.decode(changed) }
        }
        #expect(throws: MLSError.capacityExceeded) { try MLSWelcome(secrets: [], encryptedGroupInfo: Data()).encoded() }
        #expect(throws: MLSError.capacityExceeded) { try MLSWelcome(secrets: Array(repeating: (reference, encrypted), count: 1025), encryptedGroupInfo: Data()).encoded() }
        let duplicate = MLSWelcome(secrets: [(reference, encrypted), (reference, encrypted)], encryptedGroupInfo: Data())
        #expect(throws: MLSError.malformedEncoding) { try MLSWelcome.decode(duplicate.encoded()) }
        for malformed in [MLSHPKECiphertext(kemOutput: Data(), ciphertext: encrypted.ciphertext), MLSHPKECiphertext(kemOutput: encrypted.kemOutput, ciphertext: Data())] {
            #expect(throws: MLSError.malformedEncoding) { try MLSWelcome.decode(MLSWelcome(secrets: [(reference, malformed)], encryptedGroupInfo: Data()).encoded()) }
        }
    }

    /// Checks no-PSK profile enforcement, optional tags, secret lengths, trailing bytes
    /// and redacted reflection so parsed private material cannot leak through `dump`.
    @Test func welcomeSecretsBoundariesAndRedaction() throws {
        let secret = Data(repeating: 5, count: 32)
        for path in [nil, secret] {
            let original = MLSWelcomeSecrets(joinerSecret: secret, pathSecret: path)
            let encoded = try original.encoded(); let decoded = try MLSWelcomeSecrets.decode(encoded)
            #expect(decoded.joinerSecret == secret && decoded.pathSecret == path)
            #expect(String(reflecting: decoded) == "MLSWelcomeSecrets([REDACTED])")
            #expect(Mirror(reflecting: decoded).children.first?.value as? String == "[REDACTED]")
            for count in 0..<encoded.count {
                #expect(throws: (any Error).self) { try MLSWelcomeSecrets.decode(Data(encoded.prefix(count))) }
            }
            #expect(throws: MLSError.malformedEncoding) { try MLSWelcomeSecrets.decode(encoded + Data([0])) }
        }
        #expect(throws: MLSError.malformedEncoding) { try MLSWelcomeSecrets.decode(secretsBytes(joiner: secret, present: 2)) }
        #expect(throws: MLSError.invalidCommit) { try MLSWelcomeSecrets.decode(secretsBytes(joiner: Data(), present: 0)) }
        #expect(throws: MLSError.invalidCommit) { try MLSWelcomeSecrets.decode(secretsBytes(joiner: secret, present: 1, path: Data(repeating: 0, count: 31))) }
        #expect(throws: MLSError.invalidCommit) { try MLSWelcomeSecrets.decode(secretsBytes(joiner: secret, present: 0, psks: Data([0]))) }
        #expect(throws: MLSError.invalidCommit) { try MLSWelcomeSecrets(joinerSecret: Data(), pathSecret: nil).encoded() }
        #expect(throws: MLSError.invalidCommit) { try MLSWelcomeSecrets(joinerSecret: secret, pathSecret: Data()).encoded() }
        let keys = try MLSEpochKeys(MLSKeySchedule(epochSecret: secret))
        #expect(String(reflecting: keys) == "MLSEpochKeys([REDACTED])")
        #expect(Mirror(reflecting: keys).children.first?.value as? String == "[REDACTED]")
    }

    /// Checks complete GroupInfo parse boundaries independently of signature validation.
    /// Unknown information extensions survive, while empty/wrong-size MACs and signatures fail.
    @Test func groupInfoStructuralBoundaries() throws {
        let context = try MLSGroupContext(groupID: Data([1]), epoch: 1, treeHash: Data(repeating: 2, count: 32), confirmedTranscriptHash: Data(repeating: 3, count: 32))
        let info = try MLSGroupInfo(context: context, extensions: [MLSExtension(type: 0xf001, data: Data([4]))], confirmationTag: Data(repeating: 5, count: 32), signer: .max, signature: Data([6]))
        let encoded = try info.encoded(); let decoded = try MLSGroupInfo.decode(encoded)
        #expect(decoded.context == context && decoded.extensions == info.extensions && decoded.signer == .max)
        #expect(decoded.confirmationTag == info.confirmationTag && decoded.signature == info.signature)
        for count in 0..<encoded.count {
            #expect(throws: (any Error).self) { try MLSGroupInfo.decode(Data(encoded.prefix(count))) }
        }
        #expect(throws: MLSError.malformedEncoding) { try MLSGroupInfo.decode(encoded + Data([0])) }
        for tag in [Data(), Data(repeating: 0, count: 31), Data(repeating: 0, count: 33)] {
            #expect(throws: MLSError.malformedEncoding) { try MLSGroupInfo.decode(MLSGroupInfo(context: context, extensions: [], confirmationTag: tag, signer: 0, signature: Data([1])).encoded()) }
        }
        for signature in [Data(), Data(repeating: 0, count: 81)] {
            #expect(throws: MLSError.malformedEncoding) { try MLSGroupInfo.decode(MLSGroupInfo(context: context, extensions: [], confirmationTag: info.confirmationTag, signer: 0, signature: signature).encoded()) }
        }
        let missingTranscript = try MLSGroupContext(groupID: Data([1]), epoch: 1, treeHash: context.treeHash, confirmedTranscriptHash: Data())
        #expect(throws: MLSError.malformedEncoding) { try MLSGroupInfo.decode(MLSGroupInfo(context: missingTranscript, extensions: [], confirmationTag: info.confirmationTag, signer: 0, signature: Data([1])).encoded()) }
    }

    /// Verifies missing/incorrect merged-parent keys fail, unmerged parents need no key,
    /// and ancestor index validation rejects UInt32.max without overflow or traps.
    @Test func privatePathCoverageAndAncestorBounds() throws {
        let creator = try package(1), joiner = try package(2)
        var tree = try MLSRatchetTree(leaf: creator.value.leafNode)
        _ = try tree.add(joiner.value.leafNode)
        #expect(try mlsCommonAncestor(tree: tree, sender: 0, recipient: 1) == nil)
        let freshLeaf = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let generated = try tree.prepareUpdate(leafIndex: 0, leafEncryptionKey: freshLeaf.publicKey.x963Representation,
            signaturePrivateKey: creator.signing, groupID: Data([7]), initialPathSecret: Data(repeating: 8, count: 32))
        #expect(try mlsCommonAncestor(tree: tree, sender: 0, recipient: 1) == 1)
        let leafOnly: [UInt32: Data] = [2: joiner.leaf]
        #expect(throws: MLSError.invalidTree) { try MLSGroup.validatePrivatePath(leafOnly, tree: tree, ownLeaf: 1) }
        var correct = leafOnly; correct.merge(generated.privateKeys) { _, new in new }
        try MLSGroup.validatePrivatePath(correct, tree: tree, ownLeaf: 1)
        var wrong = leafOnly; wrong[1] = creator.leaf
        #expect(throws: MLSError.invalidTree) { try MLSGroup.validatePrivatePath(wrong, tree: tree, ownLeaf: 1) }
        #expect(throws: MLSError.invalidTree) { try MLSGroup.validatePrivatePath([:], tree: tree, ownLeaf: 1) }
        #expect(throws: MLSError.invalidTree) { try MLSGroup.validatePrivatePath(correct, tree: tree, ownLeaf: .max) }
        for pair: (UInt32, UInt32) in [(0, 0), (0, .max), (.max, 0), (0, 2)] {
            #expect(throws: MLSError.invalidTree) { try mlsCommonAncestor(tree: tree, sender: pair.0, recipient: pair.1) }
        }
        let parentKey = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let unmerged = try MLSRatchetTree(nodes: [.leaf(creator.value.leafNode), .parent(MLSParentNode(encryptionKey: parentKey.publicKey.x963Representation, unmergedLeaves: [1])), .leaf(joiner.value.leafNode)])
        try MLSGroup.validatePrivatePath(leafOnly, tree: unmerged, ownLeaf: 1)
        let context = try MLSGroupContext(groupID: Data([7]), epoch: 1, treeHash: tree.treeHash(), confirmedTranscriptHash: Data(repeating: 9, count: 32))
        let state = MLSEpochState(context: context, tree: tree, ownLeaf: 1, privateKeys: correct,
            keys: try MLSEpochKeys(MLSKeySchedule(epochSecret: Data(repeating: 10, count: 32))), interimTranscript: Data())
        #expect(String(reflecting: state) == "MLSEpochState([REDACTED])")
        #expect(Mirror(reflecting: state).children.first?.value as? String == "[REDACTED]")
    }

    /// Builds a fully signed/confirmed synthetic Welcome, controlling only its optional
    /// path-secret field to exercise authenticated consistency rather than byte corruption.
    /// - Parameters:
    ///   - tree: Authenticated staged public tree with signer zero.
    ///   - context: Final epoch-one context matching that tree.
    ///   - signing: Creator's matching signing scalar.
    ///   - joining: Fresh recipient package whose init key protects GroupSecrets.
    ///   - path: Optional required common-ancestor secret; nil deliberately omits it.
    /// - Returns: Complete validly encrypted Welcome, otherwise identical across the test pair.
    /// - Throws: Fixture signing, key derivation or bounded encoding failures.
    private func welcome(tree: MLSRatchetTree, context: MLSGroupContext, signing: Data, joining: MLSKeyPackage, path: Data?) throws -> Data {
        let joiner = Data(repeating: 11, count: 32)
        let schedule = try MLSKeySchedule(joinerSecret: joiner, groupContext: context.encoded())
        var info = try MLSGroupInfo(context: context, extensions: [MLSExtension(type: 2, data: tree.encoded())],
            confirmationTag: MLSCipherSuite2.mac(key: schedule.confirmationKey, content: context.confirmedTranscriptHash), signer: 0)
        info.signature = try MLSCipherSuite2.signWithLabel(privateKey: signing, label: "GroupInfoTBS", content: info.signatureInput())
        let key = try MLSCipherSuite2.expandWithLabel(secret: schedule.welcomeSecret, label: "key", context: Data(), length: 16)
        let nonce = try MLSCipherSuite2.expandWithLabel(secret: schedule.welcomeSecret, label: "nonce", context: Data(), length: 12)
        let encryptedInfo = try MLSCipherSuite2.seal(key: key, nonce: nonce, plaintext: info.encoded(), authenticatedData: Data())
        let encrypted = try MLSCipherSuite2.encryptWithLabel(publicKey: joining.initKey, label: "Welcome", context: encryptedInfo,
            plaintext: MLSWelcomeSecrets(joinerSecret: joiner, pathSecret: path).encoded())
        return try MLSWelcome(secrets: [(joining.reference(), encrypted)], encryptedGroupInfo: encryptedInfo).encoded()
    }

    /// A validly signed/confirmed Welcome omitting a required merged-parent secret fails
    /// before package consumption. Supplying the correct secret then successfully joins.
    @Test func missingWelcomePathPreservesPackage() async throws {
        let creator = try package(1), owner = try MLSKeyPackageOwner(userID: 2)
        let externalKey = P256.Signing.PrivateKey(compactRepresentable: false)
        let external = try MLSExternalSender(signatureKey: externalKey.publicKey.x963Representation, credential: MLSCredential(identity: Data("delivery".utf8)))
        let policy = try MLSGroupPolicy(externalSender: external, expectedParticipants: [1, 2])
        var tree = try MLSRatchetTree(leaf: creator.value.leafNode)
        _ = try tree.add(owner.keyPackage.leafNode)
        let leafKey = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let generated = try tree.prepareUpdate(leafIndex: 0, leafEncryptionKey: leafKey.publicKey.x963Representation,
            signaturePrivateKey: creator.signing, groupID: Data([12]), initialPathSecret: Data(repeating: 13, count: 32))
        let context = try MLSGroupContext(groupID: Data([12]), epoch: 1, treeHash: tree.treeHash(), confirmedTranscriptHash: Data(repeating: 14, count: 32), extensions: [external.groupExtension()])
        let missing = try welcome(tree: tree, context: context, signing: creator.signing, joining: owner.keyPackage, path: nil)
        await #expect(throws: MLSError.invalidTree) { try await owner.join(welcome: missing, expectedGroupID: context.groupID, policy: policy) }
        let path = try #require(generated.pathSecrets[1])
        let complete = try welcome(tree: tree, context: context, signing: creator.signing, joining: owner.keyPackage, path: path)
        let group = try await owner.join(welcome: complete, expectedGroupID: context.groupID, policy: policy)
        #expect(await group.snapshot().epoch == 1)
        await #expect(throws: MLSError.closed) { try await owner.join(welcome: complete, expectedGroupID: context.groupID, policy: policy) }
        await group.close()
    }
}
