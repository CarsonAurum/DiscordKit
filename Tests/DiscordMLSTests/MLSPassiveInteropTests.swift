// File: Tests/DiscordMLSTests/MLSPassiveInteropTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Published passive-client Welcome interoperability across the full lower-layer composition.
/// Generic vector identities and group extensions intentionally bypass the Discord-only
/// admission policy; these tests do not claim an authorized Discord service connection.
@Suite struct MLSPassiveInteropTests {
    /// Opens all four published suite-2 no-PSK Welcomes, including inline and separately
    /// supplied ratchet trees, then independently verifies key-package binding, tree/parent
    /// hashes, every leaf signature, GroupInfo signature, Welcome path derivation,
    /// confirmation MAC, and the upstream expected epoch authenticator.
    @Test func publishedPassiveWelcomes() throws {
        let url = try #require(Bundle.module.url(forResource: "passive-welcome-suite2-no-psk", withExtension: "json", subdirectory: "Fixtures"))
        let vectors = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(vectors.count == 4)
        for vector in vectors {
            let package = try MLSKeyPackage.decode(hex(try #require(vector["key_package"] as? String)), messageWrapped: true)
            try package.validate(now: 0, validateLifetime: false)
            let initKey = hex(try #require(vector["init_priv"] as? String))
            #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: initKey).publicKey.x963Representation == package.initKey)
            let leafKey = hex(try #require(vector["encryption_priv"] as? String))
            #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: leafKey).publicKey.x963Representation == package.leafNode.encryptionKey)
            let welcomeBytes = hex(try #require(vector["welcome"] as? String))
            let welcome = try MLSWelcome.decode(welcomeBytes); #expect(try welcome.encoded() == welcomeBytes)
            let reference = try package.reference()
            let entry = try #require(welcome.secrets.first { $0.reference == reference })
            let secrets = try MLSWelcomeSecrets.decode(MLSCipherSuite2.decryptWithLabel(privateKey: initKey,
                label: "Welcome", context: welcome.encryptedGroupInfo, encrypted: entry.encrypted))
            let memberSecret = MLSCipherSuite2.extract(salt: secrets.joinerSecret, ikm: Data(repeating: 0, count: 32))
            let welcomeSecret = try MLSCipherSuite2.deriveSecret(memberSecret, label: "welcome")
            let key = try MLSCipherSuite2.expandWithLabel(secret: welcomeSecret, label: "key", context: Data(), length: 16)
            let nonce = try MLSCipherSuite2.expandWithLabel(secret: welcomeSecret, label: "nonce", context: Data(), length: 12)
            let plaintext = try MLSCipherSuite2.open(key: key, nonce: nonce, ciphertext: welcome.encryptedGroupInfo, authenticatedData: Data())
            let info = try MLSGroupInfo.decode(plaintext); #expect(try info.encoded() == plaintext)
            let treeBytes: Data
            if let external = vector["ratchet_tree"] as? String { treeBytes = hex(external) }
            else { treeBytes = try #require(info.extensions.first { $0.type == 2 }).data }
            let tree = try MLSRatchetTree.decode(treeBytes)
            #expect(try tree.treeHash() == info.context.treeHash); try tree.validateParentHashes()
            for index in 0..<tree.leafCount {
                guard let leaf = tree.leaf(at: UInt32(index)) else { continue }
                try leaf.validate(now: 0, groupID: leaf.source == .keyPackage ? nil : info.context.groupID,
                    leafIndex: leaf.source == .keyPackage ? nil : UInt32(index), validateLifetime: false,
                    requiredCapabilities: info.context.extensions.first { $0.type == 3 }?.data)
            }
            let signer = try #require(tree.leaf(at: info.signer))
            #expect(try MLSCipherSuite2.verifyWithLabel(publicKey: signer.signatureKey, label: "GroupInfoTBS", content: info.signatureInput(), signature: info.signature))
            let matching = (0..<tree.leafCount).filter { tree.leaf(at: UInt32($0)) == package.leafNode }
            let ownLeaf = UInt32(try #require(matching.first)); #expect(matching.count == 1)
            if let path = secrets.pathSecret {
                let ancestor = try #require(try mlsCommonAncestor(tree: tree, sender: info.signer, recipient: ownLeaf))
                let derived = try tree.derivePathSecrets(path, from: ancestor, sender: info.signer)
                #expect(!derived.privateKeys.isEmpty)
                for (node, key) in derived.privateKeys {
                    #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: key).publicKey.x963Representation == tree.encryptionKey(at: node))
                }
            }
            let schedule = try MLSKeySchedule(joinerSecret: secrets.joinerSecret, groupContext: info.context.encoded())
            #expect(MLSCipherSuite2.verifyMAC(key: schedule.confirmationKey, content: info.context.confirmedTranscriptHash, tag: info.confirmationTag))
            #expect(schedule.epochAuthenticator == hex(try #require(vector["initial_epoch_authenticator"] as? String)))
            #expect(try mlsInterimTranscript(confirmed: info.context.confirmedTranscriptHash, confirmation: info.confirmationTag).count == 32)
        }
    }

    /// Decodes published hexadecimal without regenerating any expected cryptographic output.
    /// - Parameter value: Even-length hexadecimal string from the committed corpus.
    /// - Returns: Exact bytes, including empty data for an empty fixture string.
    private func hex(_ value: String) -> Data {
        let characters = Array(value.utf8); var result = Data()
        for offset in stride(from: 0, to: characters.count, by: 2) {
            result.append(UInt8(String(decoding: characters[offset...offset + 1], as: UTF8.self), radix: 16)!)
        }
        return result
    }
}
