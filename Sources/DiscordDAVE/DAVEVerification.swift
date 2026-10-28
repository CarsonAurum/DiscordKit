// File: Sources/DiscordDAVE/DAVEVerification.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import CryptoExtras
import Foundation

/// Failures from DAVE's out-of-band identity comparison and bounded ephemeral state.
/// These failures never authenticate a key or perform a network request.
public enum DAVEVerificationError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidIdentity
    case invalidCode
    case capacityExceeded
    case unavailable
    case inconsistentIdentity
    case fingerprintMismatch
}

/// DAVE v1 identity-fingerprint and displayable-code algorithms.
///
/// Keys must be obtained from an authenticated established MLS group. Computing a
/// code does not establish that a user has compared it out of band. Version zero
/// fingerprints use scrypt with N=16384, r=8, p=2 and 64 output bytes. Derivation
/// is synchronous CPU work (about 16 MiB working memory), with no I/O or tasks.
/// See https://daveprotocol.com/#verification-fingerprint and #displayable-codes.
public enum DAVEVerification {
    /// Computes the symmetric version-zero fingerprint for two distinct identities.
    ///
    /// P-256 points must use MLS ciphersuite 2's 65-byte uncompressed X9.62
    /// representation. Validation rejects invalid points instead of deriving a
    /// convincing-looking fingerprint for malformed identity material. Inputs are
    /// sorted as unsigned byte buffers, preserving all 64 bits of both snowflakes.
    /// - Parameters:
    ///   - localUserID: Nonzero local Discord user ID.
    ///   - localPublicKey: Local MLS signing public key, uncompressed X9.62 bytes.
    ///   - remoteUserID: Nonzero remote Discord ID, distinct from the local ID.
    ///   - remotePublicKey: Remote MLS signing public key, uncompressed X9.62 bytes.
    /// - Returns: Exactly 64 public fingerprint bytes; reversing the pair is identical.
    /// - Throws: `invalidIdentity` for invalid IDs/keys, cancellation before or after
    ///   derivation, or a Swift Crypto scrypt error. No verification state is changed.
    public static func fingerprint(localUserID: UInt64, localPublicKey: Data,
                                   remoteUserID: UInt64, remotePublicKey: Data) throws -> Data {
        try Task.checkCancellation()
        guard localUserID != 0, remoteUserID != 0, localUserID != remoteUserID else {
            throw DAVEVerificationError.invalidIdentity
        }
        try validatePublicKey(localPublicKey); try validatePublicKey(remotePublicKey)
        let local = identityBuffer(userID: localUserID, publicKey: localPublicKey)
        let remote = identityBuffer(userID: remoteUserID, publicKey: remotePublicKey)
        let input = local.lexicographicallyPrecedes(remote) ? local + remote : remote + local
        let salt = Data([0x24, 0xca, 0xb1, 0x7a, 0x7a, 0xf8, 0xec, 0x2b,
                         0x82, 0xb4, 0x12, 0xb9, 0x2d, 0xab, 0x19, 0x2e])
        let derived = try KDF.Scrypt.deriveKey(from: input, salt: salt, outputByteCount: 64,
                                             rounds: 16_384, blockSize: 8, parallelism: 2)
        try Task.checkCancellation()
        return derived.withUnsafeBytes { Data($0) }
    }

    /// Formats a public value using DAVE's big-endian group/modulo algorithm.
    /// - Parameters:
    ///   - bytes: Input containing at least `length` bytes; trailing bytes are unused.
    ///   - length: Positive total decimal digits, at most 4096 and a multiple of group size.
    ///   - groupSize: Bytes consumed and decimal digits emitted per group, 1...7; default 5.
    /// - Returns: Exactly `length` ASCII decimal digits, including leading zeros,
    ///   without separators. Applications may add presentation spaces between groups.
    /// - Throws: `invalidCode` for invalid lengths, group sizes or insufficient input.
    public static func displayCode(_ bytes: Data, length: Int, groupSize: Int = 5) throws -> String {
        guard (1...7).contains(groupSize), (1...4096).contains(length),
              length.isMultiple(of: groupSize), bytes.count >= length else {
            throw DAVEVerificationError.invalidCode
        }
        var modulus: UInt64 = 1
        for _ in 0..<groupSize { modulus *= 10 }
        var result = ""
        result.reserveCapacity(length)
        let input = Array(bytes.prefix(length))
        for offset in stride(from: 0, to: length, by: groupSize) {
            var value: UInt64 = 0
            for index in offset..<(offset + groupSize) { value = (value << 8) | UInt64(input[index]) }
            let digits = String(value % modulus)
            result += String(repeating: "0", count: groupSize - digits.count) + digits
        }
        return result
    }

    /// Formats an exact 64-byte fingerprint as DAVE's 45-digit pairwise code.
    /// - Parameter fingerprint: The full version-zero pairwise fingerprint.
    /// - Returns: Nine contiguous groups of five decimal digits.
    /// - Throws: `invalidCode` unless the input contains exactly 64 bytes.
    public static func pairwiseCode(_ fingerprint: Data) throws -> String {
        guard fingerprint.count == 64 else { throw DAVEVerificationError.invalidCode }
        return try displayCode(fingerprint, length: 45)
    }

    /// Formats an exact 32-byte MLS epoch authenticator as a 30-digit code.
    /// - Parameter authenticator: Current established group's epoch authenticator.
    /// - Returns: Six contiguous groups of five decimal digits for out-of-band comparison.
    /// - Throws: `invalidCode` unless the input contains exactly 32 bytes.
    public static func epochCode(_ authenticator: Data) throws -> String {
        guard authenticator.count == 32 else { throw DAVEVerificationError.invalidCode }
        return try displayCode(authenticator, length: 30)
    }

    /// Rejects noncanonical points before they enter fingerprints or retained state.
    /// - Parameter bytes: Expected 65-byte uncompressed P-256 X9.62 point.
    /// - Throws: `invalidIdentity` for a wrong representation, invalid curve point or length.
    static func validatePublicKey(_ bytes: Data) throws {
        guard bytes.count == 65, bytes.first == 4,
              (try? P256.Signing.PublicKey(x963Representation: bytes)) != nil else {
            throw DAVEVerificationError.invalidIdentity
        }
    }

    /// Builds the version/key/identity buffer whose lexicographic order is normative.
    /// - Parameters:
    ///   - userID: Already validated nonzero unsigned snowflake.
    ///   - publicKey: Already validated uncompressed P-256 point.
    /// - Returns: 75 bytes: version zero, public key, and big-endian snowflake.
    private static func identityBuffer(userID: UInt64, publicKey: Data) -> Data {
        var result = Data([0, 0]); result.append(publicKey)
        for shift in stride(from: 56, through: 0, by: -8) {
            result.append(UInt8(truncatingIfNeeded: userID >> UInt64(shift)))
        }
        return result
    }
}

/// Verification of a remote identity across all admitted related media sessions.
public enum DAVEIdentityVerificationStatus: Sendable, Equatable {
    /// No current established session includes the requested user.
    case unavailable
    /// All current keys agree but have not been confirmed out of band.
    case unverified
    /// The previously confirmed public key matches every current session.
    case verified
    /// Current established sessions disagree on a local or remote identity key.
    case inconsistent
}

/// Bounded in-memory verification shared by related voice/Go Live MLS sessions.
///
/// Owners explicitly replace snapshots after authenticated MLS membership changes
/// and remove them immediately on disconnect, recovery or close. No persistent-key
/// discovery, trusted-user inference, key upload, storage or UI is provided. Only
/// `confirm` records an application's completed out-of-band comparison. Any key
/// change or disappearance clears that user's confirmation; conflicting local keys
/// clear all confirmations. Group epochs may advance with unchanged identities
/// without losing verification. A single actor serializes derivations/admission;
/// methods do not suspend, start tasks or perform I/O. Memory is bounded by
/// maximumSessions * maximumMembers 65-byte public keys plus bounded confirmations.
public actor DAVEVerificationStore: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private struct Session: Sendable {
        let identities: [UInt64: Data]
        let authenticator: Data
    }

    /// Immutable account binding used by same-module session owners before adopting this store.
    nonisolated let localUserID: UInt64
    private let maximumSessions: Int
    private let maximumMembers: Int
    private var sessions: [UInt64: Session] = [:]
    private var verifiedKeys: [UInt64: Data] = [:]

    /// Omits account identifiers, public keys and verification relationships from logs.
    public nonisolated var description: String { "DAVEVerificationStore([REDACTED])" }
    /// Uses the same bounded redaction for debug descriptions.
    public nonisolated var debugDescription: String { description }
    /// Prevents ordinary reflection from exposing retained identity relationships.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Creates inert verification state for one authenticated local account.
    /// - Parameters:
    ///   - localUserID: Nonzero authenticated local Discord user ID.
    ///   - maximumSessions: Concurrent established session snapshots, 1...64; default 8.
    ///   - maximumMembers: Members per session and aggregate distinct user budget,
    ///     including the local user, 1...1024; default 256.
    /// - Throws: `invalidConfiguration` for an invalid identity or capacity bound.
    public init(localUserID: UInt64, maximumSessions: Int = 8, maximumMembers: Int = 256) throws {
        guard localUserID != 0, (1...64).contains(maximumSessions), (1...1024).contains(maximumMembers) else {
            throw DAVEVerificationError.invalidConfiguration
        }
        self.localUserID = localUserID
        self.maximumSessions = maximumSessions; self.maximumMembers = maximumMembers
    }

    /// Atomically replaces one authenticated established group's public identity view.
    /// - Parameters:
    ///   - sessionID: Stable nonzero caller-owned identifier unique among active sessions.
    ///   - epoch: Authenticated MLS epoch; zero cannot provide group verification.
    ///   - identities: Complete member/user-to-signing-key map including the local user.
    ///     Every key must be uncompressed P-256 X9.62; user IDs must be nonzero.
    ///   - epochAuthenticator: Exact 32-byte MLS authenticator for this epoch.
    /// - Throws: `invalidIdentity` for malformed keys/IDs or a missing local identity;
    ///   `unavailable` for epoch zero; `capacityExceeded` for bounded-session/user
    ///   overflow; cancellation before admission. Failures preserve all prior state.
    ///   A successful changed/disappeared identity invalidates its prior confirmation.
    ///   Admitted bytes are copied into exact-size owned buffers so small slices
    ///   cannot retain a caller's arbitrarily large backing allocation.
    public func replaceSession(sessionID: UInt64, epoch: UInt64, identities: [UInt64: Data],
                               epochAuthenticator: Data) throws {
        try Task.checkCancellation()
        guard sessionID != 0, !identities.isEmpty, identities[localUserID] != nil,
              !identities.keys.contains(0), epochAuthenticator.count == 32 else {
            throw DAVEVerificationError.invalidIdentity
        }
        guard epoch > 0 else { throw DAVEVerificationError.unavailable }
        guard identities.count <= maximumMembers,
              sessions[sessionID] != nil || sessions.count < maximumSessions else {
            throw DAVEVerificationError.capacityExceeded
        }
        var allUsers = Set(identities.keys)
        for (otherID, session) in sessions where otherID != sessionID { allUsers.formUnion(session.identities.keys) }
        guard allUsers.count <= maximumMembers else { throw DAVEVerificationError.capacityExceeded }
        for key in identities.values { try DAVEVerification.validatePublicKey(key) }
        let ownedIdentities = identities.mapValues { key in key.withUnsafeBytes { Data($0) } }
        let ownedAuthenticator = epochAuthenticator.withUnsafeBytes { Data($0) }
        try Task.checkCancellation()
        if let previous = sessions[sessionID] {
            for (userID, key) in previous.identities where identities[userID] != key {
                if userID == localUserID { verifiedKeys.removeAll() } else { verifiedKeys.removeValue(forKey: userID) }
            }
        }
        sessions[sessionID] = Session(identities: ownedIdentities, authenticator: ownedAuthenticator)
        if keys(for: localUserID).count != 1 { verifiedKeys.removeAll() }
        for userID in Array(verifiedKeys.keys) {
            let current = keys(for: userID)
            if current.count != 1 || current.first != verifiedKeys[userID] { verifiedKeys.removeValue(forKey: userID) }
        }
    }

    /// Immediately invalidates the session's confirmations during disconnect/recovery.
    /// - Parameter sessionID: Previously admitted identifier; unknown/repeated removal is inert.
    ///   Removing a session invalidates all identities it contained, even if another
    ///   related session still contains them; explicit comparison restores verification.
    public func removeSession(sessionID: UInt64) {
        guard let removed = sessions.removeValue(forKey: sessionID) else { return }
        for userID in removed.identities.keys { verifiedKeys.removeValue(forKey: userID) }
    }

    /// Derives the current pairwise fingerprint only from a consistent established view.
    /// - Parameters:
    ///   - sessionID: Identifier of an admitted established media session.
    ///   - userID: Remote member ID distinct from this store's local identity.
    /// - Returns: Exact 64-byte DAVE version-zero fingerprint for out-of-band comparison.
    /// - Throws: `unavailable` for absent session/member or the local user;
    ///   `inconsistentIdentity` for cross-session local/remote key disagreement;
    ///   cancellation or derivation errors. No verification is recorded by this method.
    public func fingerprint(sessionID: UInt64, userID: UInt64) throws -> Data {
        guard userID != localUserID, let session = sessions[sessionID],
              let local = session.identities[localUserID], let remote = session.identities[userID] else {
            throw DAVEVerificationError.unavailable
        }
        guard keys(for: localUserID).count == 1, keys(for: userID).count == 1 else {
            throw DAVEVerificationError.inconsistentIdentity
        }
        return try DAVEVerification.fingerprint(localUserID: localUserID, localPublicKey: local,
                                               remoteUserID: userID, remotePublicKey: remote)
    }

    /// Records an application's completed full-fingerprint out-of-band comparison.
    /// - Parameters:
    ///   - sessionID: Currently established session used to obtain the displayed fingerprint.
    ///   - userID: Remote member whose comparison was completed by the application/user.
    ///   - fingerprint: Exact 64 bytes compared out of band. A stale or mismatching
    ///     value cannot confirm a replacement identity or a changed local identity.
    /// - Throws: `fingerprintMismatch` for unequal/incorrectly sized bytes, or the
    ///   current-view/cancellation/derivation errors documented by `fingerprint`.
    ///   Repeated confirmation is idempotent; errors retain existing state.
    public func confirm(sessionID: UInt64, userID: UInt64, fingerprint: Data) throws {
        guard fingerprint.count == 64 else { throw DAVEVerificationError.fingerprintMismatch }
        let expected = try self.fingerprint(sessionID: sessionID, userID: userID)
        guard expected == fingerprint, let key = sessions[sessionID]?.identities[userID] else {
            throw DAVEVerificationError.fingerprintMismatch
        }
        verifiedKeys[userID] = key
    }

    /// Queries remote-key consistency and current ephemeral verification.
    /// - Parameter userID: Remote user ID; querying the local user returns unavailable.
    /// - Returns: Unavailable, inconsistent, unverified or verified. A verified result
    ///   means the application confirmed this key out of band; it grants no API authority.
    public func status(userID: UInt64) -> DAVEIdentityVerificationStatus {
        let current = keys(for: userID)
        guard userID != localUserID, !current.isEmpty else { return .unavailable }
        guard current.count == 1, keys(for: localUserID).count == 1 else { return .inconsistent }
        return current.first == verifiedKeys[userID] ? .verified : .unverified
    }

    /// Retrieves the current established session's displayable group authenticator.
    /// - Parameter sessionID: Currently admitted session identifier.
    /// - Returns: Thirty contiguous decimal digits for the most recently admitted epoch.
    /// - Throws: `unavailable` if no established snapshot exists for this session.
    public func epochCode(sessionID: UInt64) throws -> String {
        guard let session = sessions[sessionID] else { throw DAVEVerificationError.unavailable }
        return try DAVEVerification.epochCode(session.authenticator)
    }

    /// Discards all public snapshots and ephemeral confirmations, for logout/owner close.
    /// Repeated calls are inert. No persistent identity or verification storage exists.
    public func clear() { sessions.removeAll(); verifiedKeys.removeAll() }

    /// Collects unique current public keys with no unbounded historical retention.
    /// - Parameter userID: Member ID whose active identities are being compared.
    /// - Returns: At most maximumSessions distinct keys; empty for an absent member.
    private func keys(for userID: UInt64) -> Set<Data> {
        Set(sessions.values.compactMap { $0.identities[userID] })
    }
}
