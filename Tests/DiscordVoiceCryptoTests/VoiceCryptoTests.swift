import Crypto
import Foundation
import Testing
@testable import DiscordVoiceCrypto

/// Deterministic, offline primitive tests; passing vectors is not cryptographic certification.
@Suite struct VoiceCryptoTests {
    /// Validates HChaCha separately against draft-irtf-cfrg-xchacha-03 section 2.2.1.
    /// The expected bytes verify the 20-round schedule, endianness and missing feed-forward.
    @Test func hChaChaKnownAnswer() throws {
        let key = Data(0...31)
        let nonce = hex("000000090000004a0000000031415927")
        #expect(try XChaCha20Poly1305.deriveSubkey(key: key, noncePrefix: nonce) == hex("82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc"))
        #expect(throws: VoiceCryptoError.invalidKeySize) { try XChaCha20Poly1305.deriveSubkey(key: key.dropLast(), noncePrefix: nonce) }
        #expect(throws: VoiceCryptoError.invalidNonceSize) { try XChaCha20Poly1305.deriveSubkey(key: key, noncePrefix: nonce.dropLast()) }
    }

    /// Verifies both directions against the draft's independent AEAD appendix A.1 vector.
    /// Reference: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#appendix-A.1
    @Test func xChaChaKnownAnswer() throws {
        let key = Data(0x80...0x9f)
        let nonce = Data(0x40...0x57)
        let aad = hex("50515253c0c1c2c3c4c5c6c7")
        let plaintext = Data("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let expected = hex("""
        bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb
        731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452
        2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9
        21f9664c97637da9768812f615c68b13b52ec0875924c1c7987947deafd8780acf49
        """)
        #expect(try XChaCha20Poly1305.seal(payload: plaintext, key: key, nonce: nonce, authenticatedData: aad) == expected)
        #expect(try XChaCha20Poly1305.open(sealedPayload: expected, key: key, nonce: nonce, authenticatedData: aad) == plaintext)
        for index in expected.indices {
            var changed = expected
            changed[index] ^= 1
            #expect(throws: VoiceCryptoError.authenticationFailed) { try XChaCha20Poly1305.open(sealedPayload: changed, key: key, nonce: nonce, authenticatedData: aad) }
        }
        #expect(throws: VoiceCryptoError.authenticationFailed) { try XChaCha20Poly1305.open(sealedPayload: expected, key: key, nonce: nonce, authenticatedData: Data()) }
        #expect(throws: VoiceCryptoError.authenticationFailed) { try XChaCha20Poly1305.open(sealedPayload: expected, key: Data(repeating: 0, count: 32), nonce: nonce, authenticatedData: aad) }
    }

    /// Covers primitive empty frames, sliced Data, length validation and independent allocation bounds.
    @Test func xChaChaBoundaries() throws {
        let key = Data(repeating: 7, count: 32)
        let nonce = Data(repeating: 5, count: 24)
        let sealed = try XChaCha20Poly1305.seal(payload: Data(), key: key, nonce: nonce)
        #expect(sealed.startIndex == 0)
        #expect(sealed.count == 16)
        #expect(try XChaCha20Poly1305.open(sealedPayload: sealed, key: key, nonce: nonce).isEmpty)
        let backed = Data([1, 2, 3]) + sealed
        #expect(try XChaCha20Poly1305.open(sealedPayload: backed.dropFirst(3), key: key, nonce: nonce).isEmpty)
        for count in [0, 15, 31, 33, 64] {
            #expect(throws: VoiceCryptoError.invalidKeySize) { try XChaCha20Poly1305.seal(payload: Data(), key: Data(count: count), nonce: nonce) }
            #expect(throws: VoiceCryptoError.invalidKeySize) { try XChaCha20Poly1305.open(sealedPayload: sealed, key: Data(count: count), nonce: nonce) }
        }
        for count in [0, 12, 23, 25] {
            #expect(throws: VoiceCryptoError.invalidNonceSize) { try XChaCha20Poly1305.seal(payload: Data(), key: key, nonce: Data(count: count)) }
            #expect(throws: VoiceCryptoError.invalidNonceSize) { try XChaCha20Poly1305.open(sealedPayload: sealed, key: key, nonce: Data(count: count)) }
        }
        for count in 0..<16 {
            #expect(throws: VoiceCryptoError.malformedPacket) { try XChaCha20Poly1305.open(sealedPayload: Data(count: count), key: key, nonce: nonce) }
        }
        let maximum = Data(repeating: 0x55, count: XChaCha20Poly1305.maximumPayloadBytes)
        let largest = try XChaCha20Poly1305.seal(payload: maximum, key: key, nonce: nonce)
        #expect(try XChaCha20Poly1305.open(sealedPayload: largest, key: key, nonce: nonce) == maximum)
        let oversized = maximum + Data([0])
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try XChaCha20Poly1305.seal(payload: oversized, key: key, nonce: nonce) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try XChaCha20Poly1305.seal(payload: Data(), key: key, nonce: nonce, authenticatedData: oversized) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try XChaCha20Poly1305.open(sealedPayload: oversized + Data(count: 16), key: key, nonce: nonce) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try XChaCha20Poly1305.open(sealedPayload: sealed, key: key, nonce: nonce, authenticatedData: oversized) }
    }

    /// Verifies truncated AES-GCM against NIST's AES_GCM.pdf examples 1, 2 and 5.
    /// Empty, full-block and partial-block plaintext plus associated data are independent KATs.
    /// Reference: https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/AES_GCM.pdf
    @Test func truncatedAESKnownAnswers() throws {
        let key = hex("feffe9928665731c6d6a8f9467308308")
        let nonce = hex("cafebabefacedbaddecaf888")
        let full = hex("""
        d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
        1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255
        """)
        let ciphertext = hex("""
        42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e
        21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985
        """)
        let aad = hex("3ad77bb40d7a3660a89ecaf32466ef97f5d3d585")
        let examples: [(Data, Data, Data)] = [
            (Data(), Data(), hex("3247184b3c4f69a4")),
            (full, Data(), ciphertext + hex("4d5c2af327cd64a6")),
            (Data(full.prefix(60)), aad, Data(ciphertext.prefix(60)) + hex("f07c2528eea2fca1")),
        ]
        for (plaintext, associated, expected) in examples {
            #expect(try TruncatedAESGCM.seal(payload: plaintext, key: key, nonce: nonce, authenticatedData: associated) == expected)
            #expect(try TruncatedAESGCM.open(sealedPayload: expected, key: key, nonce: nonce, authenticatedData: associated) == plaintext)
            let backed = Data([1, 2, 3]) + expected
            #expect(try TruncatedAESGCM.open(sealedPayload: backed.dropFirst(3), key: key, nonce: nonce, authenticatedData: associated) == plaintext)
        }
    }

    /// Checks ciphertext boundaries, every tag byte, nonce, key and AAD rejection for the adapter.
    /// Sizes straddling AES blocks compare with public full-tag GCM to test counter increments.
    /// - Parameter count: The deterministic plaintext byte count around AES block boundaries.
    @Test(arguments: [0, 1, 15, 16, 17, 31, 32, 33, 4_097])
    func truncatedAESTamperingAndBlocks(count: Int) throws {
        let key = Data(repeating: 7, count: 16)
        let nonce = Data(repeating: 0xa0, count: 12)
        let aad = Data([3, 2, 1])
        let plaintext = Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
        let sealed = try TruncatedAESGCM.seal(payload: plaintext, key: key, nonce: nonce, authenticatedData: aad)
        #expect(sealed.startIndex == 0)
        let baseline = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: aad)
        #expect(sealed == baseline.ciphertext + baseline.tag.prefix(8))
        #expect(try TruncatedAESGCM.open(sealedPayload: sealed, key: key, nonce: nonce, authenticatedData: aad) == plaintext)
        for index in Set([0, max(0, count - 1)] + Array(count..<count + 8)) {
            var changed = sealed
            changed[changed.startIndex + index] ^= 0x80
            #expect(throws: VoiceCryptoError.authenticationFailed) { try TruncatedAESGCM.open(sealedPayload: changed, key: key, nonce: nonce, authenticatedData: aad) }
        }
        #expect(throws: VoiceCryptoError.authenticationFailed) { try TruncatedAESGCM.open(sealedPayload: sealed, key: key, nonce: Data(count: 12), authenticatedData: aad) }
        #expect(throws: VoiceCryptoError.authenticationFailed) { try TruncatedAESGCM.open(sealedPayload: sealed, key: Data(count: 16), nonce: nonce, authenticatedData: aad) }
        #expect(throws: VoiceCryptoError.authenticationFailed) { try TruncatedAESGCM.open(sealedPayload: sealed, key: key, nonce: nonce, authenticatedData: Data()) }
    }

    /// Rejects wrong AES sizes, malformed frames and oversized plaintext/AAD in both directions.
    @Test func truncatedAESBoundaries() throws {
        let key = Data(count: 16)
        let nonce = Data(count: 12)
        let sealed = try TruncatedAESGCM.seal(payload: Data(), key: key, nonce: nonce)
        for count in [0, 15, 17, 24, 32] {
            #expect(throws: VoiceCryptoError.invalidKeySize) { try TruncatedAESGCM.seal(payload: Data(), key: Data(count: count), nonce: nonce) }
            #expect(throws: VoiceCryptoError.invalidKeySize) { try TruncatedAESGCM.open(sealedPayload: sealed, key: Data(count: count), nonce: nonce) }
        }
        for count in [0, 11, 13, 24] {
            #expect(throws: VoiceCryptoError.invalidNonceSize) { try TruncatedAESGCM.seal(payload: Data(), key: key, nonce: Data(count: count)) }
            #expect(throws: VoiceCryptoError.invalidNonceSize) { try TruncatedAESGCM.open(sealedPayload: sealed, key: key, nonce: Data(count: count)) }
        }
        for count in 0..<8 {
            #expect(throws: VoiceCryptoError.malformedPacket) { try TruncatedAESGCM.open(sealedPayload: Data(count: count), key: key, nonce: nonce) }
        }
        let oversized = Data(count: TruncatedAESGCM.maximumPayloadBytes + 1)
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try TruncatedAESGCM.seal(payload: oversized, key: key, nonce: nonce) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try TruncatedAESGCM.seal(payload: Data(), key: key, nonce: nonce, authenticatedData: oversized) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try TruncatedAESGCM.open(sealedPayload: oversized + Data(count: 8), key: key, nonce: nonce) }
        #expect(throws: VoiceCryptoError.payloadTooLarge) { try TruncatedAESGCM.open(sealedPayload: sealed, key: key, nonce: nonce, authenticatedData: oversized) }
        let maximum = Data(oversized.dropLast())
        let maximumSealed = try TruncatedAESGCM.seal(payload: maximum, key: key, nonce: nonce)
        #expect(try TruncatedAESGCM.open(sealedPayload: maximumSealed, key: key, nonce: nonce) == maximum)
    }
}

/// Decodes reviewed, whitespace-separated hexadecimal test fixtures without production dependencies.
/// - Parameter value: Valid ASCII hexadecimal pairs; invalid literals deliberately fail the test process.
/// - Returns: Exactly the represented fixture bytes; whitespace has no semantic meaning.
private func hex(_ value: String) -> Data {
    let bytes = Array(value.filter { !$0.isWhitespace })
    return Data(stride(from: 0, to: bytes.count, by: 2).map { UInt8(String(bytes[$0...$0 + 1]), radix: 16)! })
}
