// File: Tests/DiscordMLSTests/MLSCredentialsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Signed credential/key-package tests with caller-owned deterministic P-256 keys and injected time.
@Suite struct MLSCredentialsTests {
    /// Produces distinct fixed private scalars for signing, leaf HPKE and invitation HPKE.
    /// - Returns: Reproducible signing scalar and two uncompressed public keys.
    /// - Throws: Crypto errors if the fixed nonzero scalars fail key import.
    private func keys() throws -> (signing: Data, leaf: Data, initial: Data) {
        let signing = Data(repeating: 1, count: 32)
        let leaf = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 2, count: 32)).publicKey.x963Representation
        let initial = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 3, count: 32)).publicKey.x963Representation
        return (signing, leaf, initial)
    }

    /// Creates a fully signed package with the largest possible valid snowflake identity.
    /// - Returns: A deterministic-identity package valid at Unix seconds 10...20.
    /// - Throws: Key/credential/signature errors from fixture construction.
    private func package() throws -> MLSKeyPackage {
        let key = try keys(); let credential = try MLSCredential.discord(userID: .max)
        return try MLSKeyPackage.generate(identity: credential.identity, signaturePrivateKey: key.signing,
                                          leafEncryptionKey: key.leaf, initKey: key.initial,
                                          lifetime: MLSLifetime(notBefore: 10, notAfter: 20))
    }

    /// Parses trusted fixture hexadecimal without truncating malformed input.
    /// - Parameter value: Even-length, lowercase ASCII hexadecimal fixture string.
    /// - Returns: Decoded bytes.
    /// - Throws: A failed requirement if fixture contents are malformed.
    private func hex(_ value: String) throws -> Data {
        let chars = Array(value); try #require(chars.count.isMultiple(of: 2))
        return try Data(stride(from: 0, to: chars.count, by: 2).map {
            try #require(UInt8(String(chars[$0...($0 + 1)]), radix: 16))
        })
    }

    /// Preserves exact-byte generic identities and big-endian Discord snowflakes, rejecting invalid credentials.
    @Test func credentialEncodingAndIdentity() throws {
        let credential = try MLSCredential.discord(userID: 0xfedcba9876543210)
        #expect(credential.identity == Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10]))
        var reader = try MLSReader(credential.encoded()); #expect(try MLSCredential.decode(&reader) == credential)
        try reader.requireEnd()
        #expect(throws: MLSError.invalidCredential) { try MLSCredential(identity: Data()) }
        #expect(throws: MLSError.invalidCredential) { try MLSCredential(identity: Data(count: 1025)) }
        #expect(throws: MLSError.invalidCredential) { try MLSCredential.discord(userID: 0) }
        let maximum = try MLSCredential(identity: Data(count: 1024)); #expect(maximum.identity.count == 1024)
        var unsupported = try MLSReader(Data([0, 2, 0]))
        #expect(throws: MLSError.invalidCredential) { try MLSCredential.decode(&unsupported) }
    }

    /// Covers capability advertisements, GREASE preservation, default-type prohibitions and malformed vectors.
    @Test func capabilitiesValidation() throws {
        let capabilities = try MLSCapabilities(cipherSuites: [2, 0xfafa], extensions: [0xfafa], proposals: [0xfafa])
        var reader = try MLSReader(capabilities.encoded()); #expect(try MLSCapabilities.decode(&reader) == capabilities)
        try reader.requireEnd()
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(versions: []) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(cipherSuites: [1]) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(credentials: []) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(cipherSuites: [2, 2]) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(extensions: [1]) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(proposals: [7]) }
        #expect(throws: MLSError.invalidConfiguration) { try MLSCapabilities(extensions: Array(100...228)) }
        var malformed = try MLSReader(Data([1, 0]))
        #expect(throws: MLSError.malformedEncoding) { try MLSCapabilities.decode(&malformed) }
        var excessive = MLSWriter(); try excessive.writeVector(Data(count: 258))
        var oversized = try MLSReader(excessive.data)
        #expect(throws: MLSError.malformedEncoding) { try MLSCapabilities.decode(&oversized) }
    }

    /// Enforces required capabilities, treating default proposals/extensions as implicit and credentials as explicit.
    @Test func requiredCapabilities() throws {
        let capabilities = try MLSCapabilities(extensions: [0xfafa], proposals: [0xfafa])
        var encoded = MLSWriter(); var extensionList = MLSWriter(); extensionList.write(UInt16(1)); extensionList.write(UInt16(0xfafa))
        try encoded.writeVector(extensionList.data)
        var proposalList = MLSWriter(); proposalList.write(UInt16(7)); proposalList.write(UInt16(0xfafa))
        try encoded.writeVector(proposalList.data); try encoded.writeVector(Data([0, 1]))
        try capabilities.validateRequired(encoded.data)
        #expect(throws: MLSError.malformedEncoding) { try capabilities.validateRequired(encoded.data + Data([0])) }
        var unsupported = MLSWriter(); try unsupported.writeVector(Data()); try unsupported.writeVector(Data())
        try unsupported.writeVector(Data([0, 2]))
        #expect(throws: MLSError.invalidCredential) { try capabilities.validateRequired(unsupported.data) }
        var malformed = MLSWriter(); try malformed.writeVector(Data([0])); try malformed.writeVector(Data()); try malformed.writeVector(Data())
        #expect(throws: MLSError.malformedEncoding) { try capabilities.validateRequired(malformed.data) }
    }

    /// Verifies both signatures and identity through independent key-package and MLSMessage round trips.
    @Test func packageRoundTripAndReference() throws {
        let package = try package(); let encoded = try package.encoded()
        let decoded = try MLSKeyPackage.decode(encoded)
        #expect(decoded == package)
        try decoded.validate(now: 10, expectedIdentity: Data(repeating: 0xff, count: 8))
        try decoded.validate(now: 20)
        let wrapped = try package.encoded(messageWrapped: true)
        #expect(wrapped.prefix(4) == Data([0, 1, 0, 5]))
        #expect(try MLSKeyPackage.decode(wrapped, messageWrapped: true) == package)
        #expect(try MLSLeafNode.decode(package.leafNode.encoded()) == package.leafNode)
        #expect(try package.reference() == MLSCipherSuite2.refHash(label: "MLS 1.0 KeyPackage Reference", value: encoded))
        #expect(try package.reference().count == 32)
        #expect(throws: MLSError.invalidCredential) { try package.validate(now: 10, expectedIdentity: Data([1])) }
    }

    /// Rejects before/after expiry and excessive lifetime while allowing the explicit DAVE full-range policy.
    @Test func lifetimePolicies() throws {
        let package = try package()
        #expect(throws: MLSError.invalidCredential) { try package.validate(now: 9) }
        #expect(throws: MLSError.invalidCredential) { try package.validate(now: 21) }
        #expect(throws: MLSError.invalidCredential) { try package.validate(now: 15, maximumLifetime: 9) }
        try package.validate(now: 15, maximumLifetime: 10)
        let key = try keys()
        let dave = try MLSKeyPackage.generate(identity: Data([1]), signaturePrivateKey: key.signing,
                                              leafEncryptionKey: key.leaf, initKey: key.initial)
        #expect(throws: MLSError.invalidCredential) { try dave.validate(now: 15) }
        try dave.validate(now: .max, validateLifetime: false)
    }

    /// Binds update/commit leaf signatures to both group and leaf position, with no key-package context leakage.
    @Test func sourceSignatureBinding() throws {
        let key = try keys(); let group = Data("voice-group".utf8)
        for source in [MLSLeafNodeSource.update, .commit] {
            let leaf = try MLSLeafNode.generate(identity: Data([1]), signaturePrivateKey: key.signing,
                                                encryptionKey: key.leaf, source: source, lifetime: nil,
                                                parentHash: source == .commit ? Data(count: 32) : nil, groupID: group, leafIndex: 7)
            try leaf.validate(now: 0, groupID: group, leafIndex: 7)
            #expect(try MLSLeafNode.decode(leaf.encoded()) == leaf)
            #expect(throws: MLSError.invalidSignature) { try leaf.validate(now: 0, groupID: Data([2]), leafIndex: 7) }
            #expect(throws: MLSError.invalidSignature) { try leaf.validate(now: 0, groupID: group, leafIndex: 8) }
            #expect(throws: MLSError.invalidCredential) { try leaf.validate(now: 0) }
        }
        let package = try package()
        #expect(throws: MLSError.invalidCredential) { try package.leafNode.signatureInput(groupID: group, leafIndex: 0) }
    }

    /// Rejects invalid P-256 keys, mismatched signing ownership and forbidden source-specific fields.
    @Test func leafStructuralFailures() throws {
        let key = try keys(); let good = try package().leafNode
        for bytes in [Data(), Data(count: 65), Data([4]) + Data(count: 64)] {
            #expect(throws: MLSError.invalidCredential) {
                try MLSLeafNode(encryptionKey: bytes, signatureKey: good.signatureKey, credential: good.credential,
                                lifetime: good.lifetime)
            }
            #expect(throws: MLSError.invalidCredential) {
                try MLSLeafNode(encryptionKey: key.leaf, signatureKey: bytes, credential: good.credential,
                                lifetime: good.lifetime)
            }
        }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential)
        }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential,
                            lifetime: MLSLifetime(notBefore: 2, notAfter: 1))
        }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential,
                            source: .update, lifetime: good.lifetime)
        }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential, source: .commit)
        }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential,
                            source: .commit, parentHash: Data([1]))
        }
        #expect(throws: MLSError.invalidCredential) { try good.signed(privateKey: Data(repeating: 4, count: 32)) }
        #expect(throws: MLSError.invalidCredential) { try good.signed(privateKey: Data()) }
        let extensionValue = try MLSExtension(type: 0xfafa, data: Data([1]))
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential,
                            lifetime: good.lifetime, extensions: [extensionValue])
        }
    }

    /// Preserves advertised unknown extensions through signed leaves/packages and rejects unadvertised package extensions.
    @Test func signedExtensionCapabilities() throws {
        let key = try keys(); let good = try package().leafNode
        let extensionValue = try MLSExtension(type: 0xfafa, data: Data([9]))
        let leaf = try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey, credential: good.credential,
                                  capabilities: MLSCapabilities(extensions: [0xfafa]), lifetime: good.lifetime,
                                  extensions: [extensionValue]).signed(privateKey: key.signing)
        let package = try MLSKeyPackage(initKey: key.initial, leafNode: leaf, extensions: [extensionValue]).signed(privateKey: key.signing)
        try package.validate(now: 15)
        #expect(try MLSKeyPackage.decode(package.encoded()) == package)
        #expect(throws: MLSError.invalidKeyPackage) {
            try MLSKeyPackage(initKey: key.initial, leafNode: good, extensions: [extensionValue])
        }
        var requirements = MLSWriter(); try requirements.writeVector(Data([0xfa, 0xfa]))
        try requirements.writeVector(Data()); try requirements.writeVector(Data([0, 1]))
        try leaf.validate(now: 15, requiredCapabilities: requirements.data)
        #expect(throws: MLSError.invalidCredential) { try good.validate(now: 15, requiredCapabilities: requirements.data) }
    }

    /// Rejects malformed source selectors and unsigned leaves, while allowing the one-member commit's empty parent hash.
    @Test func leafSourceAndSignatureBoundaries() throws {
        let key = try keys(); let good = try package().leafNode
        let bytes = try good.encoded(); var reader = try MLSReader(bytes)
        _ = try reader.readVector(); _ = try reader.readVector()
        _ = try MLSCredential.decode(&reader); _ = try MLSCapabilities.decode(&reader)
        var invalidSource = bytes; invalidSource[bytes.count - reader.remainingCount] = 255
        #expect(throws: MLSError.malformedEncoding) { try MLSLeafNode.decode(invalidSource) }
        let unsigned = try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey,
                                      credential: good.credential, lifetime: good.lifetime)
        #expect(throws: MLSError.invalidSignature) { try unsigned.validate(now: 15) }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode(encryptionKey: key.leaf, signatureKey: good.signatureKey,
                            credential: good.credential, lifetime: good.lifetime, signature: Data(count: 81))
        }
        let commit = try MLSLeafNode.generate(identity: Data([1]), signaturePrivateKey: key.signing,
                                              encryptionKey: key.leaf, source: .commit, lifetime: nil,
                                              parentHash: Data(), groupID: Data([1]), leafIndex: 0)
        try commit.validate(now: 0, groupID: Data([1]), leafIndex: 0)
        #expect(try MLSLeafNode.decode(commit.encoded()) == commit)
        #expect(throws: MLSError.invalidKeyPackage) { try MLSKeyPackage(initKey: key.initial, leafNode: commit) }
        #expect(throws: MLSError.invalidCredential) {
            try MLSLeafNode.generate(identity: Data([1]), signaturePrivateKey: Data(), encryptionKey: key.leaf)
        }
    }

    /// Demonstrates that altered signed fields or signatures fail admission without modifying the original package.
    @Test func signatureTampering() throws {
        let good = try package(); let key = try keys(); let leaf = good.leafNode
        var signature = good.signature; signature[signature.count - 1] ^= 1
        let changedSignature = try MLSKeyPackage(initKey: good.initKey, leafNode: leaf, signature: signature)
        #expect(throws: MLSError.invalidSignature) { try changedSignature.validate(now: 15) }
        let changedLeaf = try MLSLeafNode(encryptionKey: leaf.encryptionKey, signatureKey: leaf.signatureKey,
                                          credential: MLSCredential(identity: Data([2])), lifetime: leaf.lifetime, signature: leaf.signature)
        #expect(throws: MLSError.invalidSignature) { try changedLeaf.validate(now: 15) }
        let changedInit = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 5, count: 32)).publicKey.x963Representation
        let changedPackage = try MLSKeyPackage(initKey: changedInit, leafNode: leaf, signature: good.signature)
        #expect(throws: MLSError.invalidSignature) { try changedPackage.validate(now: 15) }
        #expect(throws: MLSError.invalidCredential) { try good.signed(privateKey: Data(repeating: 5, count: 32)) }
        #expect(throws: MLSError.invalidKeyPackage) { try MLSKeyPackage(initKey: key.leaf, leafNode: leaf) }
        #expect(throws: MLSError.invalidKeyPackage) { try MLSKeyPackage(initKey: Data(count: 65), leafNode: leaf) }
        #expect(throws: MLSError.invalidKeyPackage) { try MLSKeyPackage(initKey: key.initial, leafNode: leaf, signature: Data(count: 81)) }
        let unsigned = try MLSKeyPackage(initKey: good.initKey, leafNode: good.leafNode)
        #expect(throws: MLSError.invalidSignature) { try unsigned.validate(now: 15) }
        try good.validate(now: 15)
    }

    /// Rejects every truncation and all unsupported wrappers/version/suite or trailing-byte encodings.
    @Test func packageMalformedAndTruncated() throws {
        let good = try package(); let bytes = try good.encoded()
        for count in 0..<bytes.count {
            #expect(throws: (any Error).self) { try MLSKeyPackage.decode(bytes.prefix(count)) }
        }
        #expect(throws: MLSError.malformedEncoding) { try MLSKeyPackage.decode(bytes + Data([0])) }
        var version = bytes; version[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSKeyPackage.decode(version) }
        var suite = bytes; suite[3] = 1
        #expect(throws: MLSError.unsupportedCipherSuite) { try MLSKeyPackage.decode(suite) }
        var wrapper = try good.encoded(messageWrapped: true); wrapper[3] = 4
        #expect(throws: MLSError.malformedEncoding) { try MLSKeyPackage.decode(wrapper, messageWrapped: true) }
        wrapper[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSKeyPackage.decode(wrapper, messageWrapped: true) }
        #expect(throws: MLSError.malformedEncoding) { try MLSLeafNode.decode(good.leafNode.encoded() + Data([0])) }
    }

    /// Validates eight independent MLS working-group suite-2 packages, including both P-256 signatures.
    /// Fixtures retain only public signed bytes from passive-client-welcome.json at the pinned commit.
    /// This establishes bounded object/signature interoperability, not complete MLS group qualification.
    @Test func publishedWorkingGroupKeyPackages() throws {
        let url = try #require(Bundle.module.url(forResource: "mlswg-key-packages-suite2", withExtension: "json", subdirectory: "Fixtures"))
        let rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        #expect(rows.count == 8)
        for row in rows {
            let bytes = try hex(#require(row["key_package"]))
            let package = try MLSKeyPackage.decode(bytes, messageWrapped: true)
            try package.validate(now: 0, validateLifetime: false)
            #expect(try package.encoded(messageWrapped: true) == bytes)
            #expect(!package.leafNode.credential.identity.isEmpty)
            #expect(try package.reference().count == 32)
        }
    }

    /// Verifies context fields and exact bytes extracted independently from published GroupInfo messages.
    /// The fixture records full UInt64 epochs as strings to avoid JSON's floating-point range limit.
    @Test func publishedWorkingGroupContexts() throws {
        let url = try #require(Bundle.module.url(forResource: "mlswg-contexts-suite2", withExtension: "json", subdirectory: "Fixtures"))
        let rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
        #expect(rows.count == 4)
        for row in rows {
            let encoded = try hex(#require(row["group_context"])); let context = try MLSGroupContext.decode(encoded)
            #expect(context.groupID == (try hex(#require(row["group_id"]))))
            #expect(context.treeHash == (try hex(#require(row["tree_hash"]))))
            #expect(context.confirmedTranscriptHash == (try hex(#require(row["confirmed_transcript_hash"]))))
            let epochString = try #require(row["epoch"])
            let epoch = try #require(UInt64(epochString))
            #expect(context.epoch == epoch)
            #expect(try context.encoded() == encoded)
        }
    }

    /// Preserves trusted external sender framing and produces exactly one sender in extension type 5.
    @Test func externalSenderEncoding() throws {
        let key = try keys(); let publicKey = try P256.Signing.PrivateKey(rawRepresentation: key.signing).publicKey.x963Representation
        let sender = try MLSExternalSender(signatureKey: publicKey, credential: MLSCredential(identity: Data("delivery-service".utf8)))
        #expect(try MLSExternalSender.decode(sender.encoded()) == sender)
        let extensionValue = try sender.groupExtension(); #expect(extensionValue.type == 5)
        var reader = try MLSReader(extensionValue.data); var body = try MLSReader(reader.readVector())
        #expect(try MLSExternalSender.decode(&body) == sender); try body.requireEnd(); try reader.requireEnd()
        #expect(throws: MLSError.malformedEncoding) { try MLSExternalSender.decode(sender.encoded() + Data([0])) }
        #expect(throws: MLSError.invalidCredential) { try MLSExternalSender(signatureKey: Data(count: 65), credential: sender.credential) }
    }
}
