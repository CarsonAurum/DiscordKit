// File: Sources/DiscordVoiceCrypto/VoiceCrypto.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation

/// Currently documented Discord voice transport modes; deprecated XSalsa modes are excluded.
public enum VoiceEncryptionMode: String, Sendable, CaseIterable, Codable {
    /// Preferred AES256-GCM with the RTP header authenticated as additional data.
    case aeadAES256GCMRTPSize = "aead_aes256_gcm_rtpsize"
    /// Required XChaCha20-Poly1305 with the RTP header authenticated as additional data.
    case aeadXChaCha20Poly1305RTPSize = "aead_xchacha20_poly1305_rtpsize"
}

/// Bounded, credential-free failures from voice cryptographic operations.
public enum VoiceCryptoError: Error, Sendable, Equatable {
    /// The supplied key does not match the selected primitive's exact size.
    case invalidKeySize
    /// The supplied nonce does not match the primitive's exact size.
    case invalidNonceSize
    /// A configured byte, stream or packet budget lies outside its supported range.
    case invalidConfiguration
    /// The supplied RTP header cannot provide the authenticated stream identifier.
    case invalidHeader
    /// The wire payload is shorter than its authentication tag and nonce suffix.
    case malformedPacket
    /// Input exceeds the configured byte bound; no cryptographic state was consumed.
    case payloadTooLarge
    /// Authentication failed; no plaintext was returned and replay state was unchanged.
    case authenticationFailed
    /// The transmit nonce budget is exhausted; the session needs a fresh key.
    case nonceExhausted
    /// The packet was already accepted or is outside the 64-packet receive window.
    case replayedPacket
    /// A new authenticated SSRC exceeds the configured retained stream bound.
    case receiveStreamLimit
}

/// XChaCha20-Poly1305 using owned HChaCha20 and Swift Crypto's public ChaChaPoly.
///
/// Implements the construction in draft-irtf-cfrg-xchacha-03 section 2.3, with
/// 32-byte keys, 24-byte nonces and 16-byte authentication tags. This expired
/// IETF draft is an algorithm reference, not an adopted RFC or an audit claim.
/// Callers must guarantee nonce uniqueness for every key across all uses.
public enum XChaCha20Poly1305 {
    /// A conservative per-operation allocation ceiling for this media-oriented primitive.
    public static let maximumPayloadBytes = 1_048_576

    /// Encrypts bytes and authenticates associated bytes without retaining a key.
    /// - Parameters:
    ///   - payload: Plaintext, including empty data, at most `maximumPayloadBytes` bytes.
    ///   - key: Exactly 32 secret bytes; memory erasure is not guaranteed by Swift Data.
    ///   - nonce: Exactly 24 bytes, unique for this key; uniqueness is the caller's duty.
    ///   - authenticatedData: Unencrypted associated data, at most the payload ceiling.
    /// - Returns: Zero-indexed ciphertext followed by its 16-byte authentication tag; no nonce is included.
    /// - Throws: `VoiceCryptoError` for invalid sizes, bounds or cryptographic failure.
    public static func seal(payload: Data, key: Data, nonce: Data, authenticatedData: Data = Data()) throws -> Data {
        try validate(payloadCount: payload.count, key: key, nonce: nonce, authenticatedData: authenticatedData)
        let subkey = try deriveSubkey(key: key, noncePrefix: Data(nonce.prefix(16)))
        let shortNonce = Data(repeating: 0, count: 4) + nonce.suffix(8)
        do {
            let box = try ChaChaPoly.seal(payload, using: SymmetricKey(data: subkey), nonce: ChaChaPoly.Nonce(data: shortNonce), authenticating: authenticatedData)
            var result = Data()
            result.reserveCapacity(payload.count + 16)
            result.append(box.ciphertext)
            result.append(box.tag)
            return result
        } catch { throw VoiceCryptoError.authenticationFailed }
    }

    /// Authenticates and decrypts an XChaCha sealed payload without retaining receive state.
    /// - Parameters:
    ///   - sealedPayload: Ciphertext followed by the complete 16-byte tag.
    ///   - key: Exactly 32 bytes, matching the sender's secret key.
    ///   - nonce: Exactly 24 bytes, matching the sender's nonce.
    ///   - authenticatedData: The sender's exact unencrypted associated bytes.
    /// - Returns: Authenticated plaintext, possibly empty; unauthenticated data never escapes.
    /// - Throws: `VoiceCryptoError` for malformed input, bounds or authentication failure.
    public static func open(sealedPayload: Data, key: Data, nonce: Data, authenticatedData: Data = Data()) throws -> Data {
        guard sealedPayload.count >= 16 else { throw VoiceCryptoError.malformedPacket }
        try validate(payloadCount: sealedPayload.count - 16, key: key, nonce: nonce, authenticatedData: authenticatedData)
        let subkey = try deriveSubkey(key: key, noncePrefix: Data(nonce.prefix(16)))
        let shortNonce = Data(repeating: 0, count: 4) + nonce.suffix(8)
        do {
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: shortNonce), ciphertext: sealedPayload.dropLast(16), tag: sealedPayload.suffix(16))
            return try ChaChaPoly.open(box, using: SymmetricKey(data: subkey), authenticating: authenticatedData)
        } catch { throw VoiceCryptoError.authenticationFailed }
    }

    /// Checks exact primitive sizes and media allocation bounds before allocating cipher state.
    /// - Parameters:
    ///   - payloadCount: Nonnegative plaintext or ciphertext byte count, excluding its tag.
    ///   - key: The required 32-byte key.
    ///   - nonce: The required 24-byte extended nonce.
    ///   - authenticatedData: Associated bytes bounded independently of the payload.
    /// - Throws: The matching size or byte-budget `VoiceCryptoError`.
    private static func validate(payloadCount: Int, key: Data, nonce: Data, authenticatedData: Data) throws {
        guard key.count == 32 else { throw VoiceCryptoError.invalidKeySize }
        guard nonce.count == 24 else { throw VoiceCryptoError.invalidNonceSize }
        guard payloadCount <= maximumPayloadBytes, authenticatedData.count <= maximumPayloadBytes else { throw VoiceCryptoError.payloadTooLarge }
    }

    /// Derives the HChaCha20 subkey using 20 rounds without feed-forward addition.
    /// Internal visibility permits the independent draft known-answer regression test.
    /// - Parameters:
    ///   - key: Exactly 32 bytes, interpreted as eight little-endian words.
    ///   - noncePrefix: Exactly 16 bytes, interpreted as four little-endian words.
    /// - Returns: State words 0...3 and 12...15 serialized little-endian as 32 bytes.
    /// - Throws: `invalidKeySize` or `invalidNonceSize` for incorrect lengths.
    static func deriveSubkey(key: Data, noncePrefix: Data) throws -> Data {
        guard key.count == 32 else { throw VoiceCryptoError.invalidKeySize }
        guard noncePrefix.count == 16 else { throw VoiceCryptoError.invalidNonceSize }
        let input = [UInt8](key + noncePrefix)
        var words: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
        for offset in stride(from: 0, to: input.count, by: 4) {
            words.append(UInt32(input[offset]) | UInt32(input[offset + 1]) << 8 | UInt32(input[offset + 2]) << 16 | UInt32(input[offset + 3]) << 24)
        }
        for _ in 0..<10 {
            quarterRound(&words, 0, 4, 8, 12)
            quarterRound(&words, 1, 5, 9, 13)
            quarterRound(&words, 2, 6, 10, 14)
            quarterRound(&words, 3, 7, 11, 15)
            quarterRound(&words, 0, 5, 10, 15)
            quarterRound(&words, 1, 6, 11, 12)
            quarterRound(&words, 2, 7, 8, 13)
            quarterRound(&words, 3, 4, 9, 14)
        }
        var result = Data()
        for index in [0, 1, 2, 3, 12, 13, 14, 15] {
            let word = words[index]
            result.append(contentsOf: [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)])
        }
        return result
    }

    /// Applies one ChaCha quarter-round with wrapping additions and fixed rotations.
    /// - Parameters:
    ///   - words: The mutable 16-word state; the four indices must be distinct and valid.
    ///   - a: First state-word index.
    ///   - b: Second state-word index.
    ///   - c: Third state-word index.
    ///   - d: Fourth state-word index.
    private static func quarterRound(_ words: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        words[a] &+= words[b]; words[d] ^= words[a]; words[d] = (words[d] << 16) | (words[d] >> 16)
        words[c] &+= words[d]; words[b] ^= words[c]; words[b] = (words[b] << 12) | (words[b] >> 20)
        words[a] &+= words[b]; words[d] ^= words[a]; words[d] = (words[d] << 8) | (words[d] >> 24)
        words[c] &+= words[d]; words[b] ^= words[c]; words[b] = (words[b] << 7) | (words[b] >> 25)
    }
}
