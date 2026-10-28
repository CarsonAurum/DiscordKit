// File: Tools/DiscordKitLoadTests/Sources/DiscordKitLoadTests/WorkloadProfile.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Versioned logical-population dimensions and concrete local resource budgets.
///
/// Logical accounts mean served end users, never credentials or live connections.
/// Only `requests` active samples perform local I/O. Worker assignments are arithmetic
/// simulation inside one process; they do not qualify a distributed fleet.
struct WorkloadProfile: Codable, Equatable, Sendable {
    let version: Int
    let name: String
    let logicalAccounts: Int
    let accountMeaning: String
    let botIdentities: Int
    let simulatedWorkers: Int
    let guilds: Int
    let shards: Int
    let activeFraction: Double
    let requests: Int
    let activeCohort: Int
    let maximumConnections: Int
    let payloadBytes: Int
    let requestMix: String
    let burstMultiplier: Int
    let maximumQueuedCount: Int
    let maximumQueuedBytes: Int
    let maximumCacheCount: Int
    let maximumCacheBytes: Int
    let maximumMetadataEntries: Int
    let maximumQueueAgeMilliseconds: Int
    let maximumLatencySamples: Int
    let targetP99Milliseconds: Double
    let minimumSuccessesPerSecond: Double
    let subscriberPolicy: String
    let maximumPeakRSSBytes: UInt64
    let maximumEndHeapBytes: UInt64

    /// Validates all profile invariants before sockets, subprocesses or tasks are created.
    /// Limits protect the development host even when a profile is edited incorrectly.
    /// - Throws: `LoadFailure.invalidProfile` for inconsistent or unsupported dimensions.
    func validate() throws {
        guard version == 1, !name.isEmpty, logicalAccounts > 0, logicalAccounts <= 1_000_000_000, accountMeaning == "servedEndUsers",
              botIdentities > 0, simulatedWorkers > 0, guilds >= 0, shards > 0,
              activeFraction.isFinite, activeFraction > 0, activeFraction <= 1,
              requests > 0, requests <= 10_000_000,
              activeCohort > 0, activeCohort <= 256,
              maximumConnections > 0, maximumConnections <= activeCohort,
              payloadBytes >= 0, payloadBytes <= 1_048_576,
              requestMix == "GET:100%", burstMultiplier >= 1, burstMultiplier <= 10,
              maximumQueuedCount == 0, maximumQueuedBytes == 0,
              maximumCacheCount == 0, maximumCacheBytes == 0,
              maximumMetadataEntries >= maximumConnections,
              maximumQueueAgeMilliseconds == 0,
              maximumLatencySamples > 0, maximumLatencySamples <= 100_000,
              targetP99Milliseconds.isFinite, targetP99Milliseconds > 0,
              minimumSuccessesPerSecond.isFinite, minimumSuccessesPerSecond > 0,
              subscriberPolicy == "consumeBodyToEOF", maximumPeakRSSBytes > 0, maximumEndHeapBytes > 0 else { throw LoadFailure.invalidProfile }
    }

    /// The active logical cohort implied by the population and fraction.
    /// Fractional populations round down, retaining at least one active user. This
    /// arithmetic dimension allocates no account objects and is distinct from tasks.
    /// - Returns: Active user count in one through the validated logical population.
    var activeLogicalAccounts: Int { max(1, Int(Double(logicalAccounts) * activeFraction)) }

    /// Maps a request ordinal onto the logical population without allocating its accounts.
    /// - Parameter request: Nonnegative ordinal below the profile's request count.
    /// - Returns: Stable end-user and simulated-worker indices; no identities or tokens
    ///   are retained as diagnostic labels. Negative ordinals map safely to zero.
    func assignment(for request: Int) -> (account: Int, worker: Int) {
        let ordinal = max(0, request)
        return (ordinal % activeLogicalAccounts, ordinal % simulatedWorkers)
    }

    /// Loads one repository-owned profile by a safe basename.
    /// - Parameters:
    ///   - name: Profile basename such as `accounts-100`; traversal is rejected.
    ///   - directory: Existing profiles directory, injectable for unit tests.
    /// - Returns: Decoded and validated immutable profile.
    /// - Throws: `LoadFailure.invalidArguments`, file/JSON errors, or invalid-profile errors.
    static func load(name: String, directory: URL) throws -> WorkloadProfile {
        guard !name.isEmpty, name.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) || $0 == 45 })
        else { throw LoadFailure.invalidArguments }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        try value.validate()
        return value
    }
}

/// Closed harness errors exclude arbitrary peer text and credentials.
enum LoadFailure: Error, Equatable, Sendable {
    case invalidProfile
    case invalidArguments
    case unsupportedScenario
    case unexpectedResponse
    case peerStartup
    case unsupportedHost
}
