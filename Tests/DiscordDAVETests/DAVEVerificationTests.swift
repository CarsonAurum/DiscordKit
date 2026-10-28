// File: Tests/DiscordDAVETests/DAVEVerificationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation
import Testing
@testable import DiscordDAVE

/// Deterministic identity comparison, malformed-input and actor-state regressions.
/// P-256 public points are the published curve generator and twice the generator;
/// expected fingerprints were independently derived with Python hashlib.scrypt
/// using DAVE's documented algorithm, not produced by the implementation under test.
/// Source verified 2026-10-18: https://daveprotocol.com/#verification-fingerprint
/// and https://github.com/discord/libdave/blob/main/js/src/PairwiseFingerprint.ts.
/// Reference invocation used hashlib.scrypt(sortedBuffers, salt=bytes.fromhex(
/// "24cab17a7af8ec2b82b412b92dab192e"), n=16384, r=8, p=2, dklen=64).
@Suite struct DAVEVerificationTests {
    private let keyA = Data([4]) + Data([
        0x6b, 0x17, 0xd1, 0xf2, 0xe1, 0x2c, 0x42, 0x47, 0xf8, 0xbc, 0xe6, 0xe5, 0x63, 0xa4, 0x40, 0xf2,
        0x77, 0x03, 0x7d, 0x81, 0x2d, 0xeb, 0x33, 0xa0, 0xf4, 0xa1, 0x39, 0x45, 0xd8, 0x98, 0xc2, 0x96,
        0x4f, 0xe3, 0x42, 0xe2, 0xfe, 0x1a, 0x7f, 0x9b, 0x8e, 0xe7, 0xeb, 0x4a, 0x7c, 0x0f, 0x9e, 0x16,
        0x2b, 0xce, 0x33, 0x57, 0x6b, 0x31, 0x5e, 0xce, 0xcb, 0xb6, 0x40, 0x68, 0x37, 0xbf, 0x51, 0xf5])
    private let keyB = Data([4]) + Data([
        0x7c, 0xf2, 0x7b, 0x18, 0x8d, 0x03, 0x4f, 0x7e, 0x8a, 0x52, 0x38, 0x03, 0x04, 0xb5, 0x1a, 0xc3,
        0xc0, 0x89, 0x69, 0xe2, 0x77, 0xf2, 0x1b, 0x35, 0xa6, 0x0b, 0x48, 0xfc, 0x47, 0x66, 0x99, 0x78,
        0x07, 0x77, 0x55, 0x10, 0xdb, 0x8e, 0xd0, 0x40, 0x29, 0x3d, 0x9a, 0xc6, 0x9f, 0x74, 0x30, 0xdb,
        0xba, 0x7d, 0xad, 0xe6, 0x3c, 0xe9, 0x82, 0x29, 0x9e, 0x04, 0xb7, 0x9d, 0x22, 0x78, 0x73, 0xd1])
    private let authenticator = Data(0..<32)

    /// Independent scrypt fixture fixes buffer sorting, version/snowflake byte
    /// order, full-width IDs, cost/salt/output parameters and display formatting.
    @Test func fingerprintMatchesIndependentReferenceAndReverses() throws {
        let actual = try DAVEVerification.fingerprint(localUserID: 123, localPublicKey: keyA,
                                                       remoteUserID: UInt64.max, remotePublicKey: keyB)
        let expected = Data([
            0x79, 0xd6, 0xaa, 0x30, 0x05, 0x14, 0x3d, 0x9c, 0x98, 0x45, 0x7f, 0x55, 0xce, 0x1e, 0x79, 0x38,
            0x9a, 0x66, 0xa3, 0x25, 0x5f, 0xc4, 0xf8, 0x44, 0xf8, 0x0a, 0x93, 0xfa, 0xa6, 0x18, 0x91, 0x4e,
            0xf2, 0xab, 0x06, 0xba, 0x5f, 0xf3, 0xdc, 0xea, 0x32, 0xfe, 0xd9, 0xbc, 0xd2, 0xc4, 0x48, 0x0b,
            0x20, 0x00, 0x4e, 0xbc, 0x49, 0x5c, 0xda, 0xd7, 0x13, 0xb3, 0x53, 0x80, 0xb8, 0xa7, 0x95, 0x47])
        #expect(actual == expected)
        #expect(try DAVEVerification.fingerprint(localUserID: UInt64.max, localPublicKey: keyB,
                                                  remoteUserID: 123, remotePublicKey: keyA) == actual)
        #expect(try DAVEVerification.pairwiseCode(actual) == "204531869318169862779804050232842623437847314")
        #expect(try DAVEVerification.epochCode(authenticator) == "090606058512110636351516066685")
        #expect(try DAVEVerification.fingerprint(localUserID: 124, localPublicKey: keyA,
                                                  remoteUserID: UInt64.max, remotePublicKey: keyB) != actual)
    }

    /// Public comparison never accepts zero/equal users, malformed points or
    /// compressed/non-MLS representations. Both public-key positions are checked.
    @Test func fingerprintsRejectInvalidIdentities() throws {
        for (local, remote) in [(UInt64(0), UInt64(2)), (1, 0), (1, 1)] {
            #expect(throws: DAVEVerificationError.invalidIdentity) {
                try DAVEVerification.fingerprint(localUserID: local, localPublicKey: keyA,
                                                  remoteUserID: remote, remotePublicKey: keyB)
            }
        }
        for malformed in [Data(), Data(repeating: 0, count: 65), Data([4]) + Data(repeating: 0, count: 64),
                          Data(keyA.dropFirst()), Data([2]) + Data(keyA.dropFirst().prefix(32))] {
            #expect(throws: DAVEVerificationError.invalidIdentity) {
                try DAVEVerification.fingerprint(localUserID: 1, localPublicKey: malformed,
                                                  remoteUserID: 2, remotePublicKey: keyB)
            }
            #expect(throws: DAVEVerificationError.invalidIdentity) {
                try DAVEVerification.fingerprint(localUserID: 1, localPublicKey: keyA,
                                                  remoteUserID: 2, remotePublicKey: malformed)
            }
        }
    }

    /// All supported group sizes retain leading zeros and trailing-byte exclusion;
    /// invalid sizes, divisibility, upper bounds and short inputs fail explicitly.
    @Test func displayCodeBoundsAndPadding() throws {
        for groupSize in 1...7 {
            #expect(try DAVEVerification.displayCode(Data(repeating: 0, count: 14), length: groupSize,
                                                     groupSize: groupSize) == String(repeating: "0", count: groupSize))
        }
        #expect(try DAVEVerification.displayCode(Data([255]), length: 1, groupSize: 1) == "5")
        #expect(try DAVEVerification.displayCode(Data([0, 1, 2, 3, 4, 255]), length: 5) == "09060")
        for (length, groupSize) in [(0, 5), (-5, 5), (5, 0), (8, 8), (5, -1), (4, 5), (4097, 1)] {
            #expect(throws: DAVEVerificationError.invalidCode) {
                try DAVEVerification.displayCode(Data(repeating: 0, count: 4096), length: length, groupSize: groupSize)
            }
        }
        #expect(throws: DAVEVerificationError.invalidCode) { try DAVEVerification.displayCode(Data(), length: 5) }
        for length in [0, 31, 33, 64] {
            #expect(throws: DAVEVerificationError.invalidCode) { try DAVEVerification.epochCode(Data(repeating: 0, count: length)) }
        }
        for length in [0, 32, 63, 65] {
            #expect(throws: DAVEVerificationError.invalidCode) { try DAVEVerification.pairwiseCode(Data(repeating: 0, count: length)) }
        }
    }

    /// Verification is explicit, idempotent and stable across ordinary epochs.
    /// A wrong comparison cannot establish trust; a changed key rejects stale proof.
    @Test func explicitConfirmationEpochStabilityAndReplacement() async throws {
        let store = try DAVEVerificationStore(localUserID: 123)
        #expect(store.description == "DAVEVerificationStore([REDACTED])")
        #expect(store.debugDescription == store.description)
        #expect(String(reflecting: store) == store.description)
        #expect(Mirror(reflecting: store).children.count == 1)
        #expect(await store.status(userID: UInt64.max) == .unavailable)
        #expect(await store.status(userID: 123) == .unavailable)
        try await store.replaceSession(sessionID: 1, epoch: 1, identities: [123: keyA, UInt64.max: keyB], epochAuthenticator: authenticator)
        #expect(await store.status(userID: UInt64.max) == .unverified)
        let fingerprint = try await store.fingerprint(sessionID: 1, userID: UInt64.max)
        #expect(try await store.epochCode(sessionID: 1) == "090606058512110636351516066685")
        for bad in [Data(), Data(repeating: 0, count: 64)] {
            await #expect(throws: DAVEVerificationError.fingerprintMismatch) {
                try await store.confirm(sessionID: 1, userID: UInt64.max, fingerprint: bad)
            }
            #expect(await store.status(userID: UInt64.max) == .unverified)
        }
        try await store.confirm(sessionID: 1, userID: UInt64.max, fingerprint: fingerprint)
        try await store.confirm(sessionID: 1, userID: UInt64.max, fingerprint: fingerprint)
        #expect(await store.status(userID: UInt64.max) == .verified)
        try await store.replaceSession(sessionID: 1, epoch: 2, identities: [123: keyA, UInt64.max: keyB],
                                       epochAuthenticator: Data(repeating: 0, count: 32))
        #expect(await store.status(userID: UInt64.max) == .verified)
        #expect(try await store.epochCode(sessionID: 1) == String(repeating: "0", count: 30))
        try await store.replaceSession(sessionID: 1, epoch: 3, identities: [123: keyA, UInt64.max: keyA], epochAuthenticator: authenticator)
        #expect(await store.status(userID: UInt64.max) == .unverified)
        await #expect(throws: DAVEVerificationError.fingerprintMismatch) {
            try await store.confirm(sessionID: 1, userID: UInt64.max, fingerprint: fingerprint)
        }
        await store.removeSession(sessionID: 1); await store.removeSession(sessionID: 1)
        #expect(await store.status(userID: UInt64.max) == .unavailable)
        await #expect(throws: DAVEVerificationError.unavailable) { try await store.fingerprint(sessionID: 1, userID: UInt64.max) }
        await #expect(throws: DAVEVerificationError.unavailable) { try await store.epochCode(sessionID: 1) }
    }

    /// A shared store detects remote and local signing-key conflicts across
    /// simultaneous call/stream groups and destroys confirmations on conflict.
    @Test func crossSessionIdentityConflictsAndRecovery() async throws {
        let store = try DAVEVerificationStore(localUserID: 1)
        try await store.replaceSession(sessionID: 1, epoch: 1, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        let fingerprint = try await store.fingerprint(sessionID: 1, userID: 2)
        try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        try await store.replaceSession(sessionID: 2, epoch: 1, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .verified)
        try await store.replaceSession(sessionID: 2, epoch: 2, identities: [1: keyA, 2: keyA], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .inconsistent)
        await #expect(throws: DAVEVerificationError.inconsistentIdentity) { try await store.fingerprint(sessionID: 1, userID: 2) }
        await #expect(throws: DAVEVerificationError.inconsistentIdentity) {
            try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        }
        await store.removeSession(sessionID: 2)
        #expect(await store.status(userID: 2) == .unverified)
        try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        try await store.replaceSession(sessionID: 2, epoch: 1, identities: [1: keyB, 2: keyB], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .inconsistent)
        await store.removeSession(sessionID: 2)
        #expect(await store.status(userID: 2) == .unverified)
        try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        try await store.replaceSession(sessionID: 1, epoch: 3, identities: [1: keyB, 2: keyB], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .unverified)
        await store.clear(); await store.clear()
        #expect(await store.status(userID: 2) == .unavailable)
    }

    /// Admission validates complete snapshots before replacing any retained state;
    /// session, aggregate-user and per-session budgets apply to replacements too.
    @Test func boundedAdmissionAndAtomicValidation() async throws {
        for (user, sessions, members) in [(UInt64(0), 1, 1), (1, 0, 1), (1, 65, 1), (1, 1, 0), (1, 1, 1025)] {
            #expect(throws: DAVEVerificationError.invalidConfiguration) {
                try DAVEVerificationStore(localUserID: user, maximumSessions: sessions, maximumMembers: members)
            }
        }
        let store = try DAVEVerificationStore(localUserID: 1, maximumSessions: 1, maximumMembers: 2)
        try await store.replaceSession(sessionID: 1, epoch: 1, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        let fingerprint = try await store.fingerprint(sessionID: 1, userID: 2)
        try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        for identities in [[2: keyB], [UInt64(0): keyA, 1: keyA], [1: Data(repeating: 0, count: 65)]] {
            await #expect(throws: DAVEVerificationError.invalidIdentity) {
                try await store.replaceSession(sessionID: 1, epoch: 2, identities: identities, epochAuthenticator: authenticator)
            }
        }
        await #expect(throws: DAVEVerificationError.unavailable) {
            try await store.replaceSession(sessionID: 1, epoch: 0, identities: [1: keyA], epochAuthenticator: authenticator)
        }
        await #expect(throws: DAVEVerificationError.invalidIdentity) {
            try await store.replaceSession(sessionID: 0, epoch: 1, identities: [1: keyA], epochAuthenticator: authenticator)
        }
        await #expect(throws: DAVEVerificationError.invalidIdentity) {
            try await store.replaceSession(sessionID: 1, epoch: 1, identities: [1: keyA], epochAuthenticator: Data())
        }
        for (sessionID, identities) in [(UInt64(2), [UInt64(1): keyA]), (1, [1: keyA, 2: keyB, 3: keyB])] {
            await #expect(throws: DAVEVerificationError.capacityExceeded) {
                try await store.replaceSession(sessionID: sessionID, epoch: 1, identities: identities, epochAuthenticator: authenticator)
            }
        }
        #expect(await store.status(userID: 2) == .verified)
        await #expect(throws: DAVEVerificationError.unavailable) { try await store.fingerprint(sessionID: 1, userID: 1) }
        await #expect(throws: DAVEVerificationError.unavailable) { try await store.fingerprint(sessionID: 1, userID: 3) }
        let aggregate = try DAVEVerificationStore(localUserID: 1, maximumSessions: 2, maximumMembers: 2)
        try await aggregate.replaceSession(sessionID: 1, epoch: 1, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        await #expect(throws: DAVEVerificationError.capacityExceeded) {
            try await aggregate.replaceSession(sessionID: 2, epoch: 1, identities: [1: keyA, 3: keyB], epochAuthenticator: authenticator)
        }
        try await store.replaceSession(sessionID: 1, epoch: 2, identities: [1: keyA], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .unavailable)
        try await store.replaceSession(sessionID: 1, epoch: 3, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        #expect(await store.status(userID: 2) == .unverified)
    }

    /// Slice-backed public identities/authenticators admit only their visible
    /// bytes. Later caller mutations cannot affect fingerprints or current codes.
    @Test func slicedAdmissionOwnsOnlyVisibleBytes() async throws {
        var backing = Data(repeating: 0, count: 1_048_576)
        backing.replaceSubrange(100..<165, with: keyA)
        backing.replaceSubrange(200..<265, with: keyB)
        backing.replaceSubrange(300..<332, with: authenticator)
        let store = try DAVEVerificationStore(localUserID: 123)
        try await store.replaceSession(sessionID: 1, epoch: 1,
                                       identities: [123: backing[100..<165], UInt64.max: backing[200..<265]],
                                       epochAuthenticator: backing[300..<332])
        backing.replaceSubrange(100..<332, with: Data(repeating: 255, count: 232))
        #expect(try await store.epochCode(sessionID: 1) == "090606058512110636351516066685")
        #expect(try DAVEVerification.pairwiseCode(await store.fingerprint(sessionID: 1, userID: UInt64.max))
                == "204531869318169862779804050232842623437847314")
    }

    /// Cancellation before derivation/admission does not mutate trust; concurrent
    /// queries see complete actor-owned snapshots without worker tasks or timing sleeps.
    @Test func cancellationAndConcurrentQueries() async throws {
        let store = try DAVEVerificationStore(localUserID: 1)
        try await store.replaceSession(sessionID: 1, epoch: 1, identities: [1: keyA, 2: keyB], epochAuthenticator: authenticator)
        let keyA = self.keyA; let keyB = self.keyB; let authenticator = self.authenticator
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try DAVEVerification.fingerprint(localUserID: 1, localPublicKey: keyA, remoteUserID: 2, remotePublicKey: keyB)
            }
            await #expect(throws: CancellationError.self) {
                try await store.replaceSession(sessionID: 1, epoch: 2, identities: [1: keyB], epochAuthenticator: authenticator)
            }
            await #expect(throws: CancellationError.self) { try await store.fingerprint(sessionID: 1, userID: 2) }
            await #expect(throws: CancellationError.self) {
                try await store.confirm(sessionID: 1, userID: 2, fingerprint: Data(repeating: 0, count: 64))
            }
        }
        await cancelled.value
        await withTaskGroup(of: DAVEIdentityVerificationStatus.self) { group in
            for _ in 0..<16 { group.addTask { await store.status(userID: 2) } }
            for await status in group { #expect(status == .unverified) }
        }
        #expect(try await store.epochCode(sessionID: 1) == "090606058512110636351516066685")
    }
}
