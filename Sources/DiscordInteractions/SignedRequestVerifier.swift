// File: Sources/DiscordInteractions/SignedRequestVerifier.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordTransport
import Foundation

/// Authentication/admission failures contain no body, signature, key or token values.
public enum SignedIngressFailure: Error, Sendable, Equatable {
    case invalidConfiguration, malformedHeaders, invalidSignature, staleTimestamp
    case replay, replayCapacity, bodyTooLarge
}

/// Exact-byte retry behavior; semantic event deduplication belongs to the durable consumer.
public enum SignedReplayPolicy: Sendable {
    /// Authenticate every retry and expose duplicates without blocking their acknowledgement.
    case allowIdenticalRetries
    /// Refuse a previously authenticated signature until its signed timestamp is too old.
    case rejectIdentical
}

/// Bytes authenticated by Ed25519 before any JSON decoding. Formatting conceals submitted data.
public struct VerifiedDiscordRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawBody: Data
    public let timestamp: Int64
    public let isReplay: Bool

    /// Stores authenticated bytes; only this module can manufacture an authentication result.
    /// - Parameters:
    ///   - rawBody: Exact original request bytes, within the verifier's body bound.
    ///   - timestamp: Signed, validated nonnegative Unix timestamp in seconds.
    ///   - isReplay: Whether the bounded local replay window already contains this signature.
    init(rawBody: Data, timestamp: Int64, isReplay: Bool) {
        self.rawBody = rawBody; self.timestamp = timestamp; self.isReplay = isReplay
    }

    /// Returns a constant safe marker without revealing signed request data.
    public var description: String { "VerifiedDiscordRequest(redacted)" }
    /// Uses the safe marker in debug output.
    public var debugDescription: String { description }
    /// Prevents reflective expansion of the retained request bytes.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Verifies Discord's timestamp + original-body signature with maintained Ed25519 primitives.
///
/// Timestamp/replay policy is local application policy, not an upstream retry guarantee.
/// Share one verifier per application key in a process. Fleet replay protection requires
/// an external authority; this bounded process-local window does not provide exactly-once delivery.
public actor SignedRequestVerifier {
    private let key: Curve25519.Signing.PublicKey
    private let maximumBodyBytes: Int
    private let maximumAge: Int64
    private let futureSkew: Int64
    private let maximumReplayEntries: Int
    private let replayPolicy: SignedReplayPolicy
    private let now: @Sendable () -> Int64
    private var replays: [Data: Int64] = [:]

    /// Validates policy and the application's public key without starting work.
    /// - Parameters:
    ///   - publicKey: Exactly 64 hexadecimal characters from the Developer Portal, case insensitive.
    ///   - maximumBodyBytes: Positive complete-body byte bound, default 1 MiB.
    ///   - maximumAgeSeconds: Accepted timestamp age, inclusive, in `0...86400`, default 300.
    ///   - maximumFutureSkewSeconds: Accepted positive clock skew in `0...86400`, default 30.
    ///   - maximumReplayEntries: Positive retained signature bound, default 4096; full windows fail closed.
    ///   - replayPolicy: Reject exact retries by default; webhook-event endpoints should allow retries
    ///     and use their durable admission authority to decide duplicate processing.
    ///   - now: Wall-clock Unix seconds; inject a deterministic clock in tests. Negative values fail closed.
    /// - Throws: `SignedIngressFailure.invalidConfiguration` for invalid policy or public-key encoding.
    public init(publicKey: String, maximumBodyBytes: Int = 1_048_576,
                maximumAgeSeconds: Int64 = 300, maximumFutureSkewSeconds: Int64 = 30,
                maximumReplayEntries: Int = 4_096, replayPolicy: SignedReplayPolicy = .rejectIdentical,
                now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        guard maximumBodyBytes > 0, (0...86_400).contains(maximumAgeSeconds),
              (0...86_400).contains(maximumFutureSkewSeconds), maximumReplayEntries > 0,
              let bytes = Self.hex(publicKey, count: 32),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes)
        else { throw SignedIngressFailure.invalidConfiguration }
        self.key = key; self.maximumBodyBytes = maximumBodyBytes
        maximumAge = maximumAgeSeconds; futureSkew = maximumFutureSkewSeconds
        self.maximumReplayEntries = maximumReplayEntries; self.replayPolicy = replayPolicy; self.now = now
    }

    /// Authenticates original bytes before allowing model decoding or application dispatch.
    ///
    /// Signature headers must each occur exactly once. Signature verification precedes replay
    /// insertion; invalid requests cannot poison the window. Expired entries are pruned on
    /// each valid signature. Allow-retry mode evicts the oldest timestamp at capacity, so
    /// `isReplay` is advisory; reject mode refuses new work instead of evicting protection.
    /// - Parameters:
    ///   - headers: Original ordered fields, including X-Signature-Ed25519 and X-Signature-Timestamp.
    ///   - body: Complete, unmodified bytes; whitespace and JSON key order are significant.
    /// - Returns: Authenticated bytes and advisory replay metadata.
    /// - Throws: Sanitized malformed header, invalid signature, stale timestamp, oversized body,
    ///   replay or capacity errors. This synchronous actor operation never suspends midway.
    public func verify(headers: [HTTPHeader], body: Data) throws -> VerifiedDiscordRequest {
        guard body.count <= maximumBodyBytes else { throw SignedIngressFailure.bodyTooLarge }
        let signatures = headers.filter { $0.name.lowercased() == "x-signature-ed25519" }
        let timestamps = headers.filter { $0.name.lowercased() == "x-signature-timestamp" }
        guard signatures.count == 1, timestamps.count == 1,
              let signature = Self.hex(signatures[0].value, count: 64),
              !timestamps[0].value.isEmpty, timestamps[0].value.utf8.count <= 19,
              timestamps[0].value.utf8.allSatisfy({ (48...57).contains($0) }),
              let timestamp = Int64(timestamps[0].value)
        else { throw SignedIngressFailure.malformedHeaders }
        let current = now()
        guard current >= 0,
              timestamp <= current ? current - timestamp <= maximumAge : timestamp - current <= futureSkew
        else { throw SignedIngressFailure.staleTimestamp }
        var message = Data(timestamps[0].value.utf8)
        message.append(body)
        guard key.isValidSignature(signature, for: message) else { throw SignedIngressFailure.invalidSignature }
        replays = replays.filter { $0.value >= current }
        let replay = replays[signature] != nil
        if replay, case .rejectIdentical = replayPolicy { throw SignedIngressFailure.replay }
        if !replay, replays.count >= maximumReplayEntries {
            if case .rejectIdentical = replayPolicy { throw SignedIngressFailure.replayCapacity }
            if let oldest = replays.min(by: { $0.value < $1.value }) { replays.removeValue(forKey: oldest.key) }
        }
        let (expiry, overflow) = timestamp.addingReportingOverflow(maximumAge)
        replays[signature] = overflow ? Int64.max : expiry
        return VerifiedDiscordRequest(rawBody: body, timestamp: timestamp, isReplay: replay)
    }

    /// Exposes only bounded replay entry count for diagnostics and tests.
    /// - Returns: The retained count, including entries pruned by the next verification.
    public func replayEntryCount() -> Int { replays.count }

    /// Decodes exact-length ASCII hexadecimal without accepting separators or whitespace.
    /// - Parameters:
    ///   - value: Original textual key or signature.
    ///   - count: Required decoded byte count.
    /// - Returns: Decoded bytes, or nil for any length/character mismatch. Length is checked before
    ///   allocating a byte array, so even oversized direct API input cannot create an unbounded copy.
    private static func hex(_ value: String, count: Int) -> Data? {
        guard value.utf8.count == count * 2 else { return nil }
        let bytes = Array(value.utf8)
        var output = Data(); output.reserveCapacity(count)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = nibble(bytes[index]), let low = nibble(bytes[index + 1]) else { return nil }
            output.append(high * 16 + low)
        }
        return output
    }

    /// Converts one ASCII hexadecimal character to its four-bit value.
    /// - Parameter byte: One UTF-8 byte, without normalization.
    /// - Returns: A value in 0...15, or nil for every other byte.
    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}
