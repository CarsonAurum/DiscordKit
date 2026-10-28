// File: Tests/DiscordMLSTests/MLSTreeTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Independent MLSWG suite-2 tree and TreeKEM conformance plus malformed-state regressions.
@Suite struct MLSTreeTests {
    /// Verifies every relationship in the published perfect-tree arithmetic corpus,
    /// then rejects leaves-as-parents, root-as-child, excessive and non-perfect sizes.
    @Test func publishedTreeMath() throws {
        for vector in try fixture("tree-math") {
            let count = try #require(vector["n_leaves"] as? Int)
            let root = try #require(vector["root"] as? Int)
            #expect(try MLSTreeMath.root(leafCount: count) == UInt32(root))
            let left = try #require(vector["left"] as? [Any]); let right = try #require(vector["right"] as? [Any])
            let parent = try #require(vector["parent"] as? [Any]); let sibling = try #require(vector["sibling"] as? [Any])
            for node in left.indices {
                if let expected = left[node] as? Int { #expect(try MLSTreeMath.left(UInt32(node)) == UInt32(expected)) }
                else { #expect(throws: MLSError.invalidTree) { try MLSTreeMath.left(UInt32(node)) } }
                if let expected = right[node] as? Int { #expect(try MLSTreeMath.right(UInt32(node)) == UInt32(expected)) }
                else { #expect(throws: MLSError.invalidTree) { try MLSTreeMath.right(UInt32(node)) } }
                if let expected = parent[node] as? Int { #expect(try MLSTreeMath.parent(UInt32(node), leafCount: count) == UInt32(expected)) }
                else { #expect(throws: MLSError.invalidTree) { try MLSTreeMath.parent(UInt32(node), leafCount: count) } }
                if let expected = sibling[node] as? Int { #expect(try MLSTreeMath.sibling(UInt32(node), leafCount: count) == UInt32(expected)) }
                else { #expect(throws: MLSError.invalidTree) { try MLSTreeMath.sibling(UInt32(node), leafCount: count) } }
                let path = try MLSTreeMath.directPath(UInt32(node), leafCount: count)
                let copath = try MLSTreeMath.copath(UInt32(node), leafCount: count)
                #expect(path.count == copath.count)
                for ancestor in path { #expect(MLSTreeMath.contains(UInt32(node), under: ancestor)) }
            }
        }
        for count in [-1, 0, 3, 65_537, Int.max] { #expect(throws: MLSError.invalidTree) { try MLSTreeMath.root(leafCount: count) } }
        #expect(throws: MLSError.invalidTree) { try MLSTreeMath.directPath(7, leafCount: 4) }
        #expect(throws: MLSError.invalidTree) { try MLSTreeMath.right(.max) }
        #expect(!MLSTreeMath.contains(.max, under: 1))
    }

    /// Authenticates published trees containing trailing/internal blanks, unmerged leaves,
    /// and parent-hash chains skipping blank ancestors. Every subtree hash/resolution and
    /// every signed leaf is checked independently of this implementation's encoders.
    @Test func publishedTreeValidation() throws {
        for vector in try fixture("tree-validation") {
            let bytes = hex(try #require(vector["tree"] as? String))
            let tree = try MLSRatchetTree.decode(bytes)
            #expect(try tree.encoded() == bytes)
            let hashes = try #require(vector["tree_hashes"] as? [String])
            let resolutions = try #require(vector["resolutions"] as? [[UInt32]])
            #expect(tree.nodes.count == hashes.count)
            for node in hashes.indices {
                #expect(try tree.treeHash(at: UInt32(node)) == hex(hashes[node]))
                #expect(try tree.resolution(UInt32(node)) == resolutions[node])
            }
            try tree.validateParentHashes()
            for index in 0..<tree.leafCount {
                if let leaf = tree.leaf(at: UInt32(index)) {
                    let group = hex(try #require(vector["group_id"] as? String))
                    try leaf.validate(now: 1, groupID: leaf.source == .keyPackage ? nil : group,
                                      leafIndex: leaf.source == .keyPackage ? nil : UInt32(index), validateLifetime: false)
                }
            }
        }
    }

    /// Decrypts every published suite-2 UpdatePath for every eligible existing receiver.
    /// Checks independent parent/tree hashes, path secrets, derived HPKE keys, commit
    /// secrets, and canonical serialization; none of these expected bytes are self-generated.
    @Test func publishedTreeKEM() throws {
        for vector in try fixture("treekem") {
            let original = try MLSRatchetTree.decode(hex(try #require(vector["ratchet_tree"] as? String)))
            let leaves = try #require(vector["leaves_private"] as? [[String: Any]])
            var receiverKeys: [UInt32: [UInt32: Data]] = [:]
            for leaf in leaves {
                let index = try #require(leaf["index"] as? UInt32)
                let key = hex(try #require(leaf["encryption_priv"] as? String))
                var keys: [UInt32: Data] = [2 * index: key]
                #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: key).publicKey.x963Representation == original.encryptionKey(at: 2 * index))
                for path in try #require(leaf["path_secrets"] as? [[String: Any]]) {
                    let node = try #require(path["node"] as? UInt32)
                    let pair = try MLSCipherSuite2.deriveHPKEKeyPair(MLSCipherSuite2.deriveSecret(hex(try #require(path["path_secret"] as? String)), label: "node"))
                    #expect(pair.publicKey == original.encryptionKey(at: node)); keys[node] = pair.privateKey
                }
                receiverKeys[index] = keys
            }
            for update in try #require(vector["update_paths"] as? [[String: Any]]) {
                let sender = try #require(update["sender"] as? UInt32)
                let encoded = hex(try #require(update["update_path"] as? String))
                let path = try MLSUpdatePath.decode(encoded); #expect(try path.encoded() == encoded)
                var tree = original; try tree.mergeUpdatePath(path, sender: sender)
                #expect(try tree.treeHash() == hex(try #require(update["tree_hash_after"] as? String)))
                try tree.validateParentHashes()
                let context = try MLSGroupContext(groupID: hex(try #require(vector["group_id"] as? String)),
                    epoch: try #require(vector["epoch"] as? UInt64), treeHash: tree.treeHash(),
                    confirmedTranscriptHash: hex(try #require(vector["confirmed_transcript_hash"] as? String))).encoded()
                let expectedSecrets = try #require(update["path_secrets"] as? [Any])
                for (index, keys) in receiverKeys where index != sender {
                    let secrets = try tree.decryptUpdatePath(path, sender: sender, groupContext: context, privateKeys: keys)
                    #expect(secrets.commitSecret == hex(try #require(update["commit_secret"] as? String)))
                    let expected = hex(try #require(expectedSecrets[Int(index)] as? String))
                    #expect(secrets.pathSecrets.values.contains(expected))
                    for (node, key) in secrets.privateKeys {
                        #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: key).publicKey.x963Representation == tree.encryptionKey(at: node))
                    }
                }
            }
        }
    }

    /// Exercises ordered Add, Update, Remove, growth/truncation, unique-key and live-member
    /// budgets, then checks failures leave the prior value-semantic public tree unchanged.
    @Test func proposalOperationsAndBounds() throws {
        let a = try leaf(1); let b = try leaf(2); let c = try leaf(3)
        var tree = try MLSRatchetTree(leaf: a, maximumMembers: 3)
        #expect(tree.leafCount == 1); #expect(tree.memberCount == 1)
        #expect(try tree.add(b) == 1); #expect(tree.leafCount == 2)
        #expect(try tree.add(c) == 2); #expect(tree.leafCount == 4)
        let full = tree
        #expect(throws: MLSError.capacityExceeded) { try tree.add(leaf(4)) }; #expect(tree == full)
        try tree.remove(at: 2); #expect(tree.leafCount == 2); #expect(tree.memberCount == 2)
        let before = tree
        #expect(throws: MLSError.invalidTree) { try tree.add(a) }; #expect(tree == before)
        #expect(throws: MLSError.invalidTree) { try tree.remove(at: 7) }; #expect(tree == before)
        let replacement = try leaf(4, source: .update)
        try tree.update(at: 1, leaf: replacement); #expect(tree.leaf(at: 1) == replacement)
        #expect(throws: MLSError.invalidTree) { try tree.update(at: 1, leaf: replacement) }
        try tree.remove(at: 0); #expect(try tree.add(a) == 0)
        #expect(tree.leaf(at: 0) == a); #expect(tree.leaf(at: .max) == nil)
        #expect(throws: MLSError.invalidConfiguration) { try MLSRatchetTree(leaf: a, maximumMembers: 0) }
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: [nil]) }
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: [.leaf(a), .leaf(b)]) }
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: [.leaf(a), nil, .leaf(a)]) }
        var single = try MLSRatchetTree(leaf: a)
        #expect(throws: MLSError.invalidTree) { try single.remove(at: 0) }
        #expect(try single.filteredDirectPath(for: 0).isEmpty)
        #expect(throws: MLSError.invalidTree) { try single.filteredDirectPath(for: 1) }
        #expect(throws: MLSError.invalidTree) { try single.resolution(1) }
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree.decode(Data([1, 0])) }
        #expect(throws: MLSError.malformedEncoding) { try MLSRatchetTree.decode(Data([1, 2])) }
        let parentKey = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: 99, count: 32)).publicKey
        let orphan = try MLSParentNode(encryptionKey: parentKey)
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: [.leaf(a), .parent(orphan), .leaf(b)]).validateParentHashes() }
        let outside = try MLSParentNode(encryptionKey: parentKey, unmergedLeaves: [2])
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: [.leaf(a), .parent(outside), .leaf(b)]) }
    }

    /// Generates a four-member update with an excluded new member, verifies receiver and
    /// Welcome derivation agreement, and rejects parent tampering, wrong HPKE context,
    /// wrong derived secrets, malformed paths and ciphertext authentication failures.
    @Test func generatedUpdateAndTampering() throws {
        let a = try leaf(1); let b = try leaf(2); let c = try leaf(3)
        var original = try MLSRatchetTree(leaf: a); try original.add(b); try original.add(c)
        var sender = original; let group = Data("tree-tests".utf8)
        let fresh = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: 9, count: 32))
        let generated = try sender.prepareUpdate(leafIndex: 0, leafEncryptionKey: fresh.publicKey, signaturePrivateKey: signingKey(1),
                                                groupID: group, initialPathSecret: Data(repeating: 7, count: 32))
        #expect(generated.description == "MLSGeneratedUpdate(<redacted>)")
        #expect(generated.debugDescription == generated.description)
        #expect(generated.customMirror.children.first?.value as? String == "<redacted>")
        #expect(generated.customMirror.children.count == 1)
        try sender.validateParentHashes()
        try generated.leafNode.validate(now: 1, groupID: group, leafIndex: 0)
        let context = try MLSGroupContext(groupID: group, epoch: 1, treeHash: sender.treeHash(), confirmedTranscriptHash: Data(repeating: 0, count: 32)).encoded()
        let path = try sender.encryptUpdatePath(generated, sender: 0, groupContext: context, excluding: [2])
        var receiver = original; try receiver.mergeUpdatePath(path, sender: 0, excluding: [2]); #expect(receiver == sender)
        let keys = [UInt32(2): try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: 2, count: 32)).privateKey]
        let received = try receiver.decryptUpdatePath(path, sender: 0, groupContext: context, privateKeys: keys, excluding: [2])
        #expect(received.commitSecret == generated.commitSecret); #expect(received.privateKeys == generated.privateKeys)
        #expect(received.description == "MLSPathSecrets(<redacted>)")
        #expect(received.debugDescription == received.description)
        #expect(received.customMirror.children.first?.value as? String == "<redacted>")
        #expect(received.customMirror.children.count == 1)
        let root = try MLSTreeMath.root(leafCount: sender.leafCount)
        let welcome = try sender.derivePathSecrets(#require(generated.pathSecrets[root]), from: root, sender: 0)
        #expect(welcome.commitSecret == generated.commitSecret)
        #expect(throws: MLSError.authenticationFailed) { try receiver.decryptUpdatePath(path, sender: 0, groupContext: Data(), privateKeys: keys, excluding: [2]) }
        #expect(throws: MLSError.authenticationFailed) { try receiver.decryptUpdatePath(path, sender: 0, groupContext: context, privateKeys: [:], excluding: [2]) }
        #expect(throws: MLSError.invalidTree) { try receiver.derivePathSecrets(Data(repeating: 0, count: 32), from: root, sender: 0) }
        #expect(throws: MLSError.invalidTree) { try receiver.derivePathSecrets(Data(count: 31), from: root, sender: 0) }
        #expect(throws: MLSError.invalidTree) { try receiver.derivePathSecrets(Data(count: 32), from: 0, sender: 0) }
        let before = original
        let missing = MLSUpdatePath(leafNode: path.leafNode, nodes: Array(path.nodes.dropLast()))
        #expect(throws: MLSError.invalidTree) { try original.mergeUpdatePath(missing, sender: 0, excluding: [2]) }; #expect(original == before)
        let alteredLeaf = try MLSLeafNode(encryptionKey: path.leafNode.encryptionKey, signatureKey: path.leafNode.signatureKey,
            credential: path.leafNode.credential, capabilities: path.leafNode.capabilities, source: .commit, parentHash: Data(repeating: 0, count: 32))
        #expect(throws: MLSError.invalidTree) { try original.mergeUpdatePath(MLSUpdatePath(leafNode: alteredLeaf, nodes: path.nodes), sender: 0, excluding: [2]) }
        #expect(original == before)
        #expect(throws: MLSError.invalidTree) {
            try original.prepareUpdate(leafIndex: 0, leafEncryptionKey: fresh.publicKey, signaturePrivateKey: signingKey(1),
                                       groupID: group, initialPathSecret: Data(count: 31))
        }
        #expect(original == before)
        #expect(throws: MLSError.invalidCredential) {
            try original.prepareUpdate(leafIndex: 0, leafEncryptionKey: fresh.publicKey, signaturePrivateKey: signingKey(2),
                                       groupID: group, initialPathSecret: Data(count: 32))
        }
        #expect(original == before)
        var changed = path.nodes
        let encrypted = try #require(changed[0].encryptedPathSecrets.first)
        var ciphertext = encrypted.ciphertext; ciphertext[0] ^= 1
        changed[0] = MLSUpdatePathNode(encryptionKey: changed[0].encryptionKey, encryptedPathSecrets: [MLSHPKECiphertext(kemOutput: encrypted.kemOutput, ciphertext: ciphertext)])
        #expect(throws: MLSError.authenticationFailed) { try receiver.decryptUpdatePath(MLSUpdatePath(leafNode: path.leafNode, nodes: changed), sender: 0, groupContext: context, privateKeys: keys, excluding: [2]) }
        var unmerged = sender; try unmerged.add(leaf(4)); try unmerged.validateParentHashes()
        if case .parent(let parent) = unmerged.nodes[Int(root)] { #expect(parent.unmergedLeaves == [3]) } else { Issue.record("missing root") }
        var malformed = unmerged.nodes
        if case .parent(let parent) = malformed[Int(root)] {
            malformed[Int(root)] = .parent(try MLSParentNode(encryptionKey: parent.encryptionKey, parentHash: Data(repeating: 0, count: 32), unmergedLeaves: parent.unmergedLeaves))
        }
        #expect(throws: MLSError.invalidTree) { try MLSRatchetTree(nodes: malformed).validateParentHashes() }
        #expect(throws: MLSError.invalidTree) { try MLSParentNode(encryptionKey: fresh.publicKey, unmergedLeaves: [1, 1]) }
        #expect(throws: MLSError.invalidTree) { try MLSParentNode(encryptionKey: fresh.publicKey, unmergedLeaves: [2, 1]) }
        #expect(throws: MLSError.invalidTree) { try MLSParentNode(encryptionKey: Data(count: 65)) }
        #expect(throws: MLSError.invalidTree) { try MLSParentNode(encryptionKey: fresh.publicKey, parentHash: Data(count: 31)) }
        let updated = sender
        let nextLeaf = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: 17, count: 32))
        #expect(throws: MLSError.invalidTree) {
            try sender.prepareUpdate(leafIndex: 0, leafEncryptionKey: nextLeaf.publicKey, signaturePrivateKey: signingKey(1),
                                     groupID: group, initialPathSecret: Data(repeating: 7, count: 32))
        }
        #expect(sender == updated)
        let replacement = try MLSLeafNode(encryptionKey: nextLeaf.publicKey, signatureKey: generated.leafNode.signatureKey,
            credential: generated.leafNode.credential, capabilities: generated.leafNode.capabilities, source: .commit,
            parentHash: generated.leafNode.parentHash)
        let repeated = MLSUpdatePath(leafNode: replacement, nodes: path.nodes)
        #expect(throws: MLSError.invalidTree) { try sender.mergeUpdatePath(repeated, sender: 0, excluding: [2]) }
        #expect(sender == updated)
    }

    /// Rejects truncated/noncanonical UpdatePath and parent vectors before publication,
    /// and preserves subsequent enclosing fields when streaming a valid path.
    @Test func pathWireAndSingletonBoundaries() throws {
        var tree = try MLSRatchetTree(leaf: leaf(1)); let fresh = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: 8, count: 32))
        let seed = Data(repeating: 11, count: 32)
        let staged = try tree.prepareUpdate(leafIndex: 0, leafEncryptionKey: fresh.publicKey, signaturePrivateKey: signingKey(1),
                                            groupID: Data([1]), initialPathSecret: seed)
        #expect(staged.commitSecret == seed); #expect(staged.privateKeys.isEmpty); #expect(staged.pathSecrets.isEmpty)
        #expect(staged.leafNode.parentHash == Data()); try tree.validateParentHashes()
        let path = try tree.encryptUpdatePath(staged, sender: 0, groupContext: Data())
        #expect(path.nodes.isEmpty)
        let encoded = try path.encoded()
        for count in [0, 1, encoded.count - 1] { #expect(throws: (any Error).self) { try MLSUpdatePath.decode(Data(encoded.prefix(count))) } }
        #expect(throws: MLSError.malformedEncoding) { try MLSUpdatePath.decode(encoded + Data([0])) }
        var cursor = try MLSReader(encoded + Data([17])); #expect(try MLSUpdatePath.read(from: &cursor) == path)
        #expect(try cursor.readUInt8() == 17)
        let excessive = MLSUpdatePath(leafNode: path.leafNode, nodes: Array(repeating: MLSUpdatePathNode(encryptionKey: fresh.publicKey, encryptedPathSecrets: []), count: 17))
        #expect(throws: MLSError.capacityExceeded) { try excessive.encoded() }
        var body = MLSWriter(); try body.writeVector(fresh.publicKey); try body.writeVector(Data()); try body.writeVector(Data([1]))
        var malformed = try MLSReader(body.data)
        #expect(throws: MLSError.malformedEncoding) { try MLSParentNode.decode(&malformed) }
        #expect(tree.encryptionKey(at: .max) == nil)
    }

    /// Loads a compact, committed copy of the public MLSWG corpus from package resources.
    /// - Parameter name: Fixture base name without the JSON suffix.
    /// - Returns: Ordered vector objects.
    /// - Throws: Missing resource, malformed JSON, or Swift Testing requirement failures.
    private func fixture(_ name: String) throws -> [[String: Any]] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    /// Decodes fixture hexadecimal bytes; published corpus strings are assumed well formed.
    /// - Parameter value: Even-length hexadecimal string containing no separators.
    /// - Returns: Exact represented bytes, including empty data for an empty string.
    private func hex(_ value: String) -> Data {
        let bytes = Array(value.utf8); var result = Data()
        for index in stride(from: 0, to: bytes.count, by: 2) { result.append(UInt8(String(decoding: bytes[index...index + 1], as: UTF8.self), radix: 16)!) }
        return result
    }

    /// Creates a reproducible suite-2 leaf; only its backend-owned ECDSA nonce varies.
    /// - Parameters:
    ///   - id: Distinct test identity, encryption derivation seed, and signing scalar byte.
    ///   - source: Source-keyPackage by default, or source-update without a lifetime.
    /// - Returns: Signed leaf with deterministic keys and a full-range fixture lifetime.
    /// - Throws: Credential/key-generation or signing failures.
    private func leaf(_ id: UInt8, source: MLSLeafNodeSource = .keyPackage) throws -> MLSLeafNode {
        let key = try MLSCipherSuite2.deriveHPKEKeyPair(Data(repeating: id, count: 32))
        return try MLSLeafNode(encryptionKey: key.publicKey,
            signatureKey: P256.Signing.PrivateKey(rawRepresentation: signingKey(id)).publicKey.x963Representation,
            credential: MLSCredential(identity: Data([id])), source: source,
            lifetime: source == .keyPackage ? MLSLifetime(notBefore: 0, notAfter: .max) : nil)
            .signed(privateKey: signingKey(id), groupID: source == .update ? Data("tree-tests".utf8) : nil, leafIndex: source == .update ? 1 : nil)
    }

    /// Returns a valid reproducible nonzero P-256 private scalar for a fixture identity.
    /// - Parameter id: Nonzero small test identifier.
    /// - Returns: Thirty-one zero octets followed by the identity byte.
    private func signingKey(_ id: UInt8) -> Data { Data(repeating: 0, count: 31) + Data([id]) }
}
