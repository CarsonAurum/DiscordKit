// File: Sources/DiscordVoiceCrypto/VoiceTransportCipher.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation

/// Owns one session key's transmit counter and bounded per-SSRC replay windows.
///
/// Actor identity prevents accidental value copies from reusing a transmit nonce.
/// A session must share this owner for every sender using this key; creating a new
/// owner with the same key resets its counter and is forbidden. Session replacement
/// requires fresh key material. This local owner cannot enforce cross-process reuse.
/// Encryption is synchronous inside actor isolation and introduces no tasks or I/O.
/// Diagnostic redaction does not promise erasure of Swift or underlying crypto memory.
public actor VoiceTransportCipher: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Negotiated current transport mode, immutable across the key's lifetime.
    public nonisolated let mode: VoiceEncryptionMode
    private var key: SymmetricKey?
    private var nextNonce: UInt64 = 0
    private let maximumPackets: UInt64
    private let maximumPacketBytes: Int
    private let maximumReceiveStreams: Int
    private var receiveWindows: [UInt32: ReplayWindow] = [:]

    /// Creates an inert session cipher with a zero-based, nonwrapping transmit counter.
    /// - Parameters:
    ///   - mode: A mode already accepted by the voice server; no negotiation occurs here.
    ///   - key: Exactly 32 fresh bytes from the session description, owned by this session.
    ///   - maximumPacketBytes: Maximum combined RTP header and encrypted payload, 32...65,507 bytes.
    ///   - maximumReceiveStreams: Retained authenticated SSRC windows, 1...65,536; no eviction occurs.
    ///   - maximumPackets: Optional smaller transmit lifetime, 1...2^32 packets; exhaustion needs a fresh key.
    /// - Throws: `invalidKeySize` or `invalidConfiguration`; starts no background work.
    public init(mode: VoiceEncryptionMode, key: Data, maximumPacketBytes: Int = 65_507, maximumReceiveStreams: Int = 256, maximumPackets: UInt64 = 4_294_967_296) throws {
        guard key.count == 32 else { throw VoiceCryptoError.invalidKeySize }
        guard (32...65_507).contains(maximumPacketBytes), (1...65_536).contains(maximumReceiveStreams), (1...4_294_967_296).contains(maximumPackets) else { throw VoiceCryptoError.invalidConfiguration }
        self.mode = mode
        self.key = SymmetricKey(data: key)
        self.maximumPacketBytes = maximumPacketBytes
        self.maximumReceiveStreams = maximumReceiveStreams
        self.maximumPackets = maximumPackets
    }

    /// Encrypts a packet body under a unique counter and authenticates its complete clear RTP header.
    /// The counter is reserved before cryptography, so failure never permits nonce reuse.
    /// Actor calls serialize without suspension; cancellation is checked before reservation.
    /// - Parameters:
    ///   - payload: Encoded media or E2EE frame; may be empty within the combined packet bound.
    ///   - authenticatedHeader: Exact clear RTP header, at least 12 bytes, including any clear extensions.
    /// - Returns: Zero-indexed ciphertext, 16-byte tag, then the 4-byte big-endian counter.
    ///   The header is excluded; CryptoKit's internal nonce-relative slice indices are normalized.
    /// - Throws: `VoiceCryptoError` for invalid bounds or closed/exhausted state; `CancellationError`
    ///   before reserving state. Cryptographic errors become `authenticationFailed`.
    public func seal(payload: Data, authenticatedHeader: Data) throws -> Data {
        try Task.checkCancellation()
        try validate(payloadCount: payload.count, header: authenticatedHeader)
        guard let key, nextNonce < maximumPackets else { throw VoiceCryptoError.nonceExhausted }
        let suffix = Self.counterBytes(UInt32(nextNonce))
        nextNonce += 1
        do {
            var sealed = Data()
            switch mode {
            case .aeadAES256GCMRTPSize:
                let nonce = try AES.GCM.Nonce(data: suffix + Data(repeating: 0, count: 8))
                let box = try AES.GCM.seal(payload, using: key, nonce: nonce, authenticating: authenticatedHeader)
                sealed.reserveCapacity(payload.count + 20)
                sealed.append(box.ciphertext)
                sealed.append(box.tag)
            case .aeadXChaCha20Poly1305RTPSize:
                let keyData = key.withUnsafeBytes { Data($0) }
                sealed = try XChaCha20Poly1305.seal(payload: payload, key: keyData, nonce: suffix + Data(repeating: 0, count: 20), authenticatedData: authenticatedHeader)
            }
            return sealed + suffix
        } catch { throw VoiceCryptoError.authenticationFailed }
    }

    /// Authenticates a packet before atomically committing its SSRC's replay window.
    /// Receive windows allow a displacement of 63 counters and never wrap. Duplicate,
    /// old, invalid and unauthenticated packets cannot advance or allocate replay state.
    /// - Parameters:
    ///   - sealedPayload: Ciphertext, 16-byte authentication tag and 4-byte counter suffix.
    ///   - authenticatedHeader: Exact clear RTP header; bytes 8...11 identify the SSRC.
    /// - Returns: Authenticated plaintext; no plaintext is returned for rejected packets.
    /// - Throws: `VoiceCryptoError` for malformed, oversized, replayed, unauthenticated,
    ///   closed or over-capacity packets; `CancellationError` before any processing.
    public func open(sealedPayload: Data, authenticatedHeader: Data) throws -> Data {
        try Task.checkCancellation()
        guard sealedPayload.count >= 20 else { throw VoiceCryptoError.malformedPacket }
        try validate(payloadCount: sealedPayload.count - 20, header: authenticatedHeader)
        guard let key else { throw VoiceCryptoError.nonceExhausted }
        let header = [UInt8](authenticatedHeader)
        let stream = Self.readCounter(Array(header[8..<12]))
        let suffix = Data(sealedPayload.suffix(4))
        let counter = Self.readCounter([UInt8](suffix))
        if let window = receiveWindows[stream], !window.accepts(counter) { throw VoiceCryptoError.replayedPacket }
        let plaintext: Data
        do {
            switch mode {
            case .aeadAES256GCMRTPSize:
                let nonce = try AES.GCM.Nonce(data: suffix + Data(repeating: 0, count: 8))
                let body = sealedPayload.dropLast(4)
                let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body.dropLast(16), tag: body.suffix(16))
                plaintext = try AES.GCM.open(box, using: key, authenticating: authenticatedHeader)
            case .aeadXChaCha20Poly1305RTPSize:
                let keyData = key.withUnsafeBytes { Data($0) }
                plaintext = try XChaCha20Poly1305.open(sealedPayload: Data(sealedPayload.dropLast(4)), key: keyData, nonce: suffix + Data(repeating: 0, count: 20), authenticatedData: authenticatedHeader)
            }
        } catch { throw VoiceCryptoError.authenticationFailed }
        guard receiveWindows[stream] != nil || receiveWindows.count < maximumReceiveStreams else { throw VoiceCryptoError.receiveStreamLimit }
        var window = receiveWindows[stream] ?? ReplayWindow()
        window.record(counter)
        receiveWindows[stream] = window
        return plaintext
    }

    /// Permanently rejects future work and releases the retained key and receive metadata.
    /// Idempotent and synchronous within actor isolation; no secure erasure is promised.
    public func close() {
        key = nil
        receiveWindows.removeAll(keepingCapacity: false)
        nextNonce = maximumPackets
    }

    /// A fixed diagnostic description which never exposes session keys or stream identifiers.
    public nonisolated var description: String { "VoiceTransportCipher([REDACTED])" }
    /// The same fixed marker used for debug interpolation.
    public nonisolated var debugDescription: String { description }
    /// A redacted mirror exposing no actor-isolated state or cryptographic material.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["key": "[REDACTED]"]) }

    /// Checks header and aggregate UDP payload bounds without overflow-prone additions.
    /// - Parameters:
    ///   - payloadCount: Plaintext byte count, excluding encryption overhead.
    ///   - header: Clear authenticated header, including its SSRC.
    /// - Throws: `invalidHeader` or `payloadTooLarge` without changing actor state.
    private func validate(payloadCount: Int, header: Data) throws {
        guard header.count >= 12 else { throw VoiceCryptoError.invalidHeader }
        guard header.count <= maximumPacketBytes - 20, payloadCount <= maximumPacketBytes - 20 - header.count else { throw VoiceCryptoError.payloadTooLarge }
    }

    /// Serializes one transport counter as four bytes in network order.
    /// - Parameter counter: A nonce value already checked against the nonwrapping budget.
    /// - Returns: Exactly four bytes, including leading zeros.
    private static func counterBytes(_ counter: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16), UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter)])
    }

    /// Reads exactly four network-order bytes without alignment-dependent loads.
    /// - Parameter bytes: Four bytes established by the caller's header or suffix validation.
    /// - Returns: The corresponding unsigned counter or SSRC.
    private static func readCounter(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}

/// A fixed 64-bit replay bitmap; never evicts a stream or treats wrap-around as a new epoch.
private struct ReplayWindow {
    private var highest: UInt32?
    private var bitmap: UInt64 = 0

    /// Checks whether a nonce is new and lies within the retained displacement window.
    /// - Parameter counter: An untrusted counter; checking never mutates the window.
    /// - Returns: True for a new counter or an unseen counter at most 63 below the highest.
    func accepts(_ counter: UInt32) -> Bool {
        guard let highest else { return true }
        if counter > highest { return true }
        let distance = highest - counter
        return distance < 64 && bitmap & (UInt64(1) << distance) == 0
    }

    /// Commits an authenticated counter previously accepted by `accepts`.
    /// - Parameter counter: A verified nonduplicate counter; callers preserve this invariant.
    /// Shift distances are checked before use, preventing oversized-shift ambiguity.
    mutating func record(_ counter: UInt32) {
        guard let highest else { self.highest = counter; bitmap = 1; return }
        if counter > highest {
            let distance = counter - highest
            bitmap = distance >= 64 ? 1 : (bitmap << distance) | 1
            self.highest = counter
        } else {
            bitmap |= UInt64(1) << (highest - counter)
        }
    }
}
