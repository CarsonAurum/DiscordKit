// File: Sources/DiscordMLS/MLSSecretTree.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// A single-use RFC 9420 sender-ratchet key and provisional nonce.
///
/// The caller must apply a fresh four-byte reuse guard to the nonce before content
/// encryption and discard these bytes after use. Copying this value duplicates secrets.
public struct MLSRatchetKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// AES-128 key bytes; never log or reuse them to encrypt another message.
    public let key: Data
    /// Provisional 12-byte nonce before application of a reuse guard.
    public let nonce: Data
    /// Generation from which both values were derived.
    public let generation: UInt32
    /// Constructs a key container produced by a bounded secret-tree ratchet.
    /// - Parameters:
    ///   - key: Derived 16-byte AES key.
    ///   - nonce: Derived 12-byte provisional nonce.
    ///   - generation: Generation whose key ownership is transferred to this container.
    internal init(key: Data, nonce: Data, generation: UInt32) { self.key = key; self.nonce = nonce; self.generation = generation }
    /// Redacted diagnostics containing the public generation only.
    public var description: String { "MLSRatchetKey(generation: \(generation), <redacted>)" }
    /// Redacted debug diagnostics containing no key or nonce bytes.
    public var debugDescription: String { description }
    /// Redacted reflection excludes every retained secret from `dump` and mirror diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }

    /// Applies the RFC 9420 section 6.3.1 reuse guard to the nonce's first four bytes.
    /// - Parameter reuseGuard: Exactly four random bytes, freshly generated for each encryption.
    /// - Returns: The guarded 12-byte nonce; neither the source nonce nor key is modified.
    /// - Throws: `MLSError.invalidConfiguration` if the guard is not exactly four bytes.
    public func guardedNonce(reuseGuard: Data) throws -> Data {
        guard reuseGuard.count == 4 else { throw MLSError.invalidConfiguration }
        var result = Data(nonce)
        for (index, byte) in reuseGuard.enumerated() { result[index] ^= byte }
        return result
    }
}

/// A bounded, lazy RFC 9420 section 9 secret tree with independent sender ratchets.
///
/// Tree ancestors are logically discarded when split; sender secrets are replaced when
/// advanced, with only bounded skipped message keys retained. This value is transactionally
/// copyable so callers can authenticate a message before accepting advancement. Copies must
/// not be used by independent encryptors: that would reuse keys. `Data` does not guarantee
/// physical memory erasure. The enclosing owner must serialize access and discard old epochs.
public struct MLSSecretTree: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The independent protocol uses of a sender's leaf secret.
    public enum RatchetKind: String, Sendable, Hashable {
        /// Proposal and Commit content encryption.
        case handshake
        /// Application content encryption.
        case application
    }
    private struct RatchetID: Sendable, Hashable { let leaf: Int; let kind: RatchetKind }
    private struct Ratchet: Sendable { var secret: Data; var next: UInt64; var skipped: [UInt32: MLSRatchetKey] }
    /// Number of allocated leaves, including blank leaves in the perfect binary tree.
    public let leafCount: Int
    /// Maximum allowed skipped generations in a single forward request.
    public let maximumForwardDistance: Int
    /// Aggregate retained skipped-key count across all senders and ratchet kinds.
    public let maximumSkippedKeys: Int
    /// Last permitted generation for each sender ratchet; defaults to the full uint32 space.
    public let maximumGeneration: UInt32
    private var nodeSecrets: [Int: Data]
    private var ratchets: [RatchetID: Ratchet] = [:]
    private var skippedCount = 0

    /// Initializes a perfect binary secret tree without deriving any leaf values yet.
    /// - Parameters:
    ///   - encryptionSecret: Exactly 32 bytes from the current epoch's key schedule.
    ///   - leafCount: Power-of-two leaf capacity in 1...65536, including blank leaves.
    ///   - maximumForwardDistance: Per-call skip bound in 0...65536; defaults to 1024.
    ///   - maximumSkippedKeys: Aggregate skipped-key retention bound in 0...65536; defaults to 256.
    ///   - maximumGeneration: Inclusive per-ratchet lifetime cap; defaults to `UInt32.max`.
    ///     Smaller caps permit application cryptoperiod policies without changing wire format.
    /// - Throws: `MLSError.invalidConfiguration` if any bound or secret length is invalid.
    /// - Note: Membership/nonblank-leaf validation belongs to the authenticated group owner.
    public init(encryptionSecret: Data, leafCount: Int, maximumForwardDistance: Int = 1024, maximumSkippedKeys: Int = 256, maximumGeneration: UInt32 = .max) throws {
        guard encryptionSecret.count == 32, (1...65536).contains(leafCount), leafCount.nonzeroBitCount == 1,
              (0...65536).contains(maximumForwardDistance), (0...65536).contains(maximumSkippedKeys) else {
            throw MLSError.invalidConfiguration
        }
        self.leafCount = leafCount; self.maximumForwardDistance = maximumForwardDistance; self.maximumSkippedKeys = maximumSkippedKeys
        self.maximumGeneration = maximumGeneration
        nodeSecrets = [1: encryptionSecret]
    }

    /// Consumes exactly one generation, retaining bounded skipped keys for reordering.
    /// - Parameters:
    ///   - leaf: Sender leaf index in `0..<leafCount`; caller verifies nonblank membership.
    ///   - kind: Handshake or application ratchet, independent for every sender.
    ///   - generation: Requested uint32 generation; each generation can be returned only once.
    /// - Returns: Owned message key and provisional nonce. The ratchet advances past this key;
    ///   skipped prior keys can still be consumed once until their configured capacity is reached.
    /// - Throws: `MLSError.invalidConfiguration` for an invalid leaf, `staleGeneration` for
    ///   consumed/unavailable keys, or `capacityExceeded` for forward or aggregate skip bounds.
    ///   Any failure leaves this tree unchanged. Authentication must finish before the caller
    ///   publishes a successful candidate tree as its canonical state.
    public mutating func consume(leaf: Int, kind: RatchetKind, generation: UInt32) throws -> MLSRatchetKey {
        var candidate = self
        let result = try candidate.consumeUnchecked(leaf: leaf, kind: kind, generation: generation)
        self = candidate
        return result
    }

    /// Consumes the next sequential generation for one sender and content kind.
    /// - Parameters:
    ///   - leaf: Sender leaf index in `0..<leafCount`.
    ///   - kind: Independent sender ratchet to advance.
    /// - Returns: The next unused sequential key, beginning with generation zero.
    /// - Throws: Invalid-leaf, exhausted-generation, or capacity errors without state changes.
    public mutating func next(leaf: Int, kind: RatchetKind) throws -> MLSRatchetKey {
        let id = RatchetID(leaf: leaf, kind: kind)
        let generation = ratchets[id]?.next ?? 0
        guard generation <= UInt64(maximumGeneration) else { throw MLSError.staleGeneration }
        return try consume(leaf: leaf, kind: kind, generation: UInt32(generation))
    }

    /// Reports retained skipped keys for bounded-resource accounting; contains no secret bytes.
    public var retainedSkippedKeyCount: Int { skippedCount }
    /// Redacted diagnostic state including only public leaf and skipped-key counts.
    public var description: String { "MLSSecretTree(leaves: \(leafCount), skipped: \(skippedCount), <redacted>)" }
    /// Redacted debug diagnostics containing no root, leaf, ratchet, or key bytes.
    public var debugDescription: String { description }
    /// Redacted reflection excludes every retained secret from `dump` and mirror diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }

    /// Advances a candidate tree after checking every externally controlled resource bound.
    /// - Parameters:
    ///   - leaf: Validated below before any tree derivation.
    ///   - kind: Independent ratchet identifier.
    ///   - generation: Requested generation, consumed once if available.
    /// - Returns: Derived or previously retained message key.
    /// - Throws: Invalid-leaf, stale-generation, capacity, or cryptographic framing errors.
    private mutating func consumeUnchecked(leaf: Int, kind: RatchetKind, generation: UInt32) throws -> MLSRatchetKey {
        guard (0..<leafCount).contains(leaf) else { throw MLSError.invalidConfiguration }
        guard generation <= maximumGeneration else { throw MLSError.staleGeneration }
        let id = RatchetID(leaf: leaf, kind: kind)
        let next = ratchets[id]?.next ?? 0
        if UInt64(generation) < next {
            guard let retained = ratchets[id]?.skipped.removeValue(forKey: generation) else { throw MLSError.staleGeneration }
            skippedCount -= 1
            return retained
        }
        let gap = UInt64(generation) - next
        guard gap <= maximumForwardDistance, gap <= maximumSkippedKeys - skippedCount else { throw MLSError.capacityExceeded }
        if ratchets[id] == nil { try initializeLeaf(leaf) }
        guard var ratchet = ratchets[id] else { throw MLSError.invalidConfiguration }
        var result: MLSRatchetKey?
        while ratchet.next <= UInt64(generation) {
            let current = UInt32(ratchet.next)
            let key = try MLSCipherSuite2.deriveTreeSecret(ratchet.secret, label: "key", generation: current, length: 16)
            let nonce = try MLSCipherSuite2.deriveTreeSecret(ratchet.secret, label: "nonce", generation: current, length: 12)
            let output = MLSRatchetKey(key: key, nonce: nonce, generation: current)
            ratchet.secret = try MLSCipherSuite2.deriveTreeSecret(ratchet.secret, label: "secret", generation: current, length: 32)
            ratchet.next += 1
            if current == generation { result = output }
            else { ratchet.skipped[current] = output; skippedCount += 1 }
        }
        if ratchet.next > UInt64(maximumGeneration) { ratchet.secret = Data() }
        ratchets[id] = ratchet
        guard let result else { throw MLSError.invalidConfiguration }
        return result
    }

    /// Splits the nearest retained ancestor and initializes both leaf ratchets exactly once.
    /// - Parameter leaf: An in-range leaf index whose ratchets have not been initialized.
    /// - Throws: Invalid retained-tree state or cryptographic derivation errors.
    /// - Note: This removes parent and leaf secrets from the candidate's dictionaries; physical
    ///   memory wiping and copies outside this owner are not guaranteed by Swift values.
    private mutating func initializeLeaf(_ leaf: Int) throws {
        let target = leafCount + leaf
        var ancestor = target
        while nodeSecrets[ancestor] == nil, ancestor > 1 { ancestor /= 2 }
        guard nodeSecrets[ancestor] != nil else { throw MLSError.invalidConfiguration }
        var path: [Int] = []
        var cursor = target
        while cursor != ancestor { path.append(cursor); cursor /= 2 }
        for child in path.reversed() {
            guard let secret = nodeSecrets.removeValue(forKey: ancestor) else { throw MLSError.invalidConfiguration }
            nodeSecrets[ancestor * 2] = try MLSCipherSuite2.expandWithLabel(secret: secret, label: "tree", context: Data("left".utf8), length: 32)
            nodeSecrets[ancestor * 2 + 1] = try MLSCipherSuite2.expandWithLabel(secret: secret, label: "tree", context: Data("right".utf8), length: 32)
            ancestor = child
        }
        guard let secret = nodeSecrets.removeValue(forKey: target) else { throw MLSError.invalidConfiguration }
        for kind in [RatchetKind.handshake, .application] {
            ratchets[RatchetID(leaf: leaf, kind: kind)] = Ratchet(secret: try MLSCipherSuite2.deriveSecret(secret, label: kind.rawValue), next: 0, skipped: [:])
        }
    }
}
