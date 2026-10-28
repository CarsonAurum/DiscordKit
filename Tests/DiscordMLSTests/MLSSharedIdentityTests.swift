// File: Tests/DiscordMLSTests/MLSSharedIdentityTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordMLS

/// Shared DAVE signing identities preserve verification across related media
/// sessions and fresh recovery packages without reusing HPKE encryption keys.
@Suite struct MLSSharedIdentityTests {
    /// A caller-owned signing key is reused exactly, while every independently
    /// generated package gets fresh init/leaf keys and valid package signatures.
    @Test func sharedIdentityKeepsSigningKeyAndRefreshesEncryptionKeys() throws {
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        let first = try MLSKeyPackageOwner(userID: UInt64.max, signaturePrivateKey: signing.rawRepresentation)
        let second = try MLSKeyPackageOwner(userID: UInt64.max, signaturePrivateKey: signing.rawRepresentation)
        #expect(first.keyPackage.leafNode.signatureKey == signing.publicKey.x963Representation)
        #expect(second.keyPackage.leafNode.signatureKey == first.keyPackage.leafNode.signatureKey)
        #expect(first.keyPackage.leafNode.credential.identity == Data(repeating: 255, count: 8))
        #expect(first.keyPackage.initKey != second.keyPackage.initKey)
        #expect(first.keyPackage.leafNode.encryptionKey != second.keyPackage.leafNode.encryptionKey)
        try first.keyPackage.validate(now: 0, maximumLifetime: UInt64.max, validateLifetime: false)
        try second.keyPackage.validate(now: UInt64.max, maximumLifetime: UInt64.max, validateLifetime: false)
    }

    /// The backwards-compatible nil default generates independent identities;
    /// callers must opt into stable signing identity ownership deliberately.
    @Test func omittedIdentityStillGeneratesFreshSigningKeys() throws {
        let first = try MLSKeyPackageOwner(userID: 1)
        let second = try MLSKeyPackageOwner(userID: 1, signaturePrivateKey: nil)
        #expect(first.keyPackage.leafNode.signatureKey != second.keyPackage.leafNode.signatureKey)
    }

    /// Invalid-length, zero and out-of-range scalars cannot produce a signed
    /// package; invalid local identities remain rejected with a supplied key.
    @Test func invalidSharedIdentityMaterialIsRejected() throws {
        for bytes in [Data(), Data(repeating: 1, count: 31), Data(repeating: 1, count: 33),
                      Data(repeating: 0, count: 32), Data(repeating: 255, count: 32)] {
            #expect(throws: (any Error).self) { try MLSKeyPackageOwner(userID: 1, signaturePrivateKey: bytes) }
        }
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        #expect(throws: MLSError.invalidCredential) {
            try MLSKeyPackageOwner(userID: 0, signaturePrivateKey: signing.rawRepresentation)
        }
    }

    /// Closing one package owner cannot invalidate another package that was
    /// independently constructed from the same application-owned signing identity.
    @Test func independentOwnerCleanupAndCreation() async throws {
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        let first = try MLSKeyPackageOwner(userID: 1, signaturePrivateKey: signing.rawRepresentation)
        let second = try MLSKeyPackageOwner(userID: 1, signaturePrivateKey: signing.rawRepresentation)
        let externalKey = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: externalKey.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data([1])))
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1])
        await first.close()
        await #expect(throws: MLSError.closed) { try await first.createGroup(groupID: Data([1]), policy: policy) }
        let group = try await second.createGroup(groupID: Data([2]), policy: policy)
        #expect(await group.snapshot().memberCount == 1)
        #expect(await group.snapshot().epoch == 0)
        await group.close()
    }
}
