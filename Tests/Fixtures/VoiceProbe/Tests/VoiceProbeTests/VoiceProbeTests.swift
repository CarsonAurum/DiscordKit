// File: Tests/Fixtures/VoiceProbe/Tests/VoiceProbeTests/VoiceProbeTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Crypto
import CryptoExtras
import Testing

/// Establishes the public 16-byte AES-GCM tag contract and rejects a truncated tag before decryption.
/// Fixed test keys and nonces are single-fixture inputs and must never be reused in production.
/// The wrong AAD and short-tag paths are captured by assertions and must not return plaintext.
/// - Throws: Unexpected CryptoKit parameter or authentication errors on the valid fixture paths;
///   expected rejection paths are asserted locally rather than propagated.
@Test func aesGCMTagAndAuthentication() throws {
    let key = SymmetricKey(data: Data(repeating: 0, count: 16))
    let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 12))
    let message = Data([1, 2, 3])
    let box = try AES.GCM.seal(message, using: key, nonce: nonce, authenticating: Data([4]))
    #expect(box.tag.count == 16)
    #expect(try AES.GCM.open(box, using: key, authenticating: Data([4])) == message)
    #expect(throws: (any Error).self) { try AES.GCM.SealedBox(nonce: nonce, ciphertext: box.ciphertext, tag: box.tag.prefix(8)) }
    #expect(throws: (any Error).self) { try AES.GCM.open(box, using: key, authenticating: Data([5])) }
}

/// Checks both accepted IETF ChaCha nonces and rejected XChaCha-sized inputs through public APIs.
/// Uses independent fixed inputs with no shared state or suspension points; tampered tags must fail.
/// - Throws: Unexpected CryptoKit construction, encryption or authentication errors on valid inputs.
///   The invalid nonce and tampered-tag paths are captured by assertions.
/// - Parameter length: Nonce length in bytes, including zero and the required XChaCha 24-byte case.
@Test(arguments: [0, 8, 12, 24]) func chaChaNonceLength(length: Int) throws {
    let bytes = Data(repeating: 0, count: length)
    if length == 12 {
        let nonce = try ChaChaPoly.Nonce(data: bytes)
        let key = SymmetricKey(data: Data(repeating: 0, count: 32))
        let message = Data([1, 2, 3])
        let box = try ChaChaPoly.seal(message, using: key, nonce: nonce)
        #expect(box.tag.count == 16)
        #expect(try ChaChaPoly.open(box, using: key) == message)
        var invalidTag = box.tag
        invalidTag[invalidTag.startIndex] ^= 1
        let invalidBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: box.ciphertext, tag: invalidTag)
        #expect(throws: (any Error).self) { try ChaChaPoly.open(invalidBox, using: key) }
        _ = try Insecure.ChaCha20CTR.Nonce(data: bytes)
    } else {
        #expect(throws: (any Error).self) { try ChaChaPoly.Nonce(data: bytes) }
        #expect(throws: (any Error).self) { try Insecure.ChaCha20CTR.Nonce(data: bytes) }
    }
}

/// Checks public AES block permutation against the FIPS 197 AES-128 example.
/// This is the key 000102...0f and plaintext 001122...ff example from the official AES standard.
/// It proves API accessibility only; it does not implement or validate truncated-tag GCM.
/// - Throws: Unexpected public AES key-size or block-size errors on the valid 16-byte fixture.
@Test func aesBlockKnownAnswer() throws {
    var block: [UInt8] = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
    let key = SymmetricKey(data: Data(0..<16))
    try AES.permute(&block, key: key)
    #expect(block == [0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30, 0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a])
}

/// Exercises the exact HPKE primitive suite needed by DAVE's MLS ciphersuite 2.
/// This round trip establishes callable public primitives, not MLS encoding, key scheduling or interoperability.
/// Test state is local; the HPKE sender generates its ephemeral key internally without shared fixture state.
/// - Throws: Unexpected P-256/HPKE encapsulation, initialization or authentication errors; any such
///   error fails the valid suite round-trip experiment.
@Test func hpkeSuiteTwoPrimitives() throws {
    let suite = HPKE.Ciphersuite(kem: .P256_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_128)
    let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 1, count: 32))
    let info = Data("probe".utf8)
    var sender = try HPKE.Sender(recipientKey: privateKey.publicKey, ciphersuite: suite, info: info)
    var receiver = try HPKE.Recipient(privateKey: privateKey, ciphersuite: suite, info: info, encapsulatedKey: sender.encapsulatedKey)
    let message = Data([1, 2, 3])
    let encrypted = try sender.seal(message)
    #expect(try receiver.open(encrypted) == message)
}

/// Verifies that public AES block permutation rejects incomplete and oversized blocks.
/// - Parameter count: Byte count around the required 16-byte boundary, including an empty block.
@Test(arguments: [0, 15, 17]) func aesBlockRejectsInvalidLengths(count: Int) {
    var block = [UInt8](repeating: 0, count: count)
    #expect(throws: (any Error).self) {
        try AES.permute(&block, key: SymmetricKey(data: Data(repeating: 0, count: 16)))
    }
}
