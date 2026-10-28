// File: Sources/DiscordVoiceCrypto/TruncatedAESGCM.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import CryptoExtras
import Foundation

/// Narrow AES128-GCM support for DAVE's eight-byte authentication tags.
///
/// Swift Crypto's public GCM API requires a full 16-byte tag when opening a box.
/// This adapter obtains candidate plaintext with the public AES block permutation,
/// recomputes its full tag through public AES.GCM, then checks the eight-byte prefix
/// before returning plaintext. It owns no GHASH or AES implementation. Tag checking
/// visits all eight bytes without early exit; Swift compiler timing guarantees and
/// independent cryptographic review remain qualification gates. This primitive does
/// not implement MLS, sender ratchets, DAVE framing, nonce ownership or replay policy.
public enum TruncatedAESGCM {
    /// The per-frame plaintext/ciphertext ceiling, excluding the eight-byte tag.
    public static let maximumPayloadBytes = 1_048_576

    /// Encrypts a frame with AES128-GCM and truncates its authentication tag to eight bytes.
    /// - Parameters:
    ///   - payload: Plaintext, possibly empty, at most `maximumPayloadBytes` bytes.
    ///   - key: Exactly 16 secret bytes; nonce uniqueness under this key is required.
    ///   - nonce: Exactly 12 bytes, already derived by the caller's sender ratchet.
    ///   - authenticatedData: Associated bytes, bounded by the same allocation ceiling.
    /// - Returns: Zero-indexed ciphertext followed by the first eight bytes of the full GCM tag.
    /// - Throws: `VoiceCryptoError` for invalid sizes, bounds or underlying crypto failure.
    public static func seal(payload: Data, key: Data, nonce: Data, authenticatedData: Data = Data()) throws -> Data {
        try validate(payloadCount: payload.count, key: key, nonce: nonce, authenticatedData: authenticatedData)
        do {
            let box = try AES.GCM.seal(payload, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: authenticatedData)
            var result = Data()
            result.reserveCapacity(payload.count + 8)
            result.append(box.ciphertext)
            result.append(box.tag.prefix(8))
            return result
        } catch { throw VoiceCryptoError.authenticationFailed }
    }

    /// Opens a bounded AES128-GCM frame only after verifying its eight-byte tag prefix.
    /// Candidate plaintext stays local until authentication succeeds. Work is roughly
    /// two cipher passes; callers must bound admission of hostile packets separately.
    /// - Parameters:
    ///   - sealedPayload: Ciphertext followed by exactly the eight-byte tag, possibly no ciphertext.
    ///   - key: Exactly 16 matching secret bytes.
    ///   - nonce: Exactly 12 matching bytes; this method does not retain replay state.
    ///   - authenticatedData: The sender's exact associated bytes.
    /// - Returns: Authenticated plaintext, including empty frames.
    /// - Throws: `VoiceCryptoError` for malformed input, invalid sizes, bounds or failed authentication.
    public static func open(sealedPayload: Data, key: Data, nonce: Data, authenticatedData: Data = Data()) throws -> Data {
        guard sealedPayload.count >= 8 else { throw VoiceCryptoError.malformedPacket }
        try validate(payloadCount: sealedPayload.count - 8, key: key, nonce: nonce, authenticatedData: authenticatedData)
        do {
            let symmetricKey = SymmetricKey(data: key)
            let ciphertext = [UInt8](sealedPayload.dropLast(8))
            var plaintext = Data(count: ciphertext.count)
            let nonceBytes = [UInt8](nonce)
            for offset in stride(from: 0, to: ciphertext.count, by: 16) {
                // A 96-bit nonce has J0 = nonce || 1; GCTR starts at inc32(J0) = 2.
                // The 1 MiB ceiling ensures the counter cannot approach UInt32 exhaustion.
                let counter = UInt32(offset / 16 + 2)
                var block = nonceBytes + [UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16), UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter)]
                try AES.permute(&block, key: symmetricKey)
                for index in 0..<min(16, ciphertext.count - offset) {
                    plaintext[offset + index] = ciphertext[offset + index] ^ block[index]
                }
            }
            let recomputed = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: AES.GCM.Nonce(data: nonce), authenticating: authenticatedData)
            let expected = [UInt8](recomputed.tag.prefix(8))
            let supplied = [UInt8](sealedPayload.suffix(8))
            var difference: UInt8 = 0
            for index in 0..<8 { difference |= expected[index] ^ supplied[index] }
            guard difference == 0 else { throw VoiceCryptoError.authenticationFailed }
            return plaintext
        } catch { throw VoiceCryptoError.authenticationFailed }
    }

    /// Rejects unsupported AES sizes and allocations before processing secret-dependent bytes.
    /// - Parameters:
    ///   - payloadCount: The nonnegative ciphertext or plaintext count, excluding the tag.
    ///   - key: The required 16-byte AES128 key.
    ///   - nonce: The required 12-byte GCM nonce.
    ///   - authenticatedData: Associated bytes bounded independently of the frame body.
    /// - Throws: The matching size or allocation `VoiceCryptoError` without producing output.
    private static func validate(payloadCount: Int, key: Data, nonce: Data, authenticatedData: Data) throws {
        guard key.count == 16 else { throw VoiceCryptoError.invalidKeySize }
        guard nonce.count == 12 else { throw VoiceCryptoError.invalidNonceSize }
        guard payloadCount <= maximumPayloadBytes, authenticatedData.count <= maximumPayloadBytes else { throw VoiceCryptoError.payloadTooLarge }
    }
}
