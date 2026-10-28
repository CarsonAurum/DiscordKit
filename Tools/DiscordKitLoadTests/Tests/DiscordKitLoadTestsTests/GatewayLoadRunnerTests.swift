// File: Tools/DiscordKitLoadTests/Tests/DiscordKitLoadTestsTests/GatewayLoadRunnerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@testable import DiscordKitLoadTests
import Foundation
import Testing

/// Bounded scripted Gateway evidence separates logical users from owned sessions and verifies cleanup.
@Suite("Gateway load harness", .timeLimit(.minutes(1)))
struct GatewayLoadRunnerTests {
    /// Four sessions share two bot identities, survive two Resumes each and complete all typed request rounds.
    /// Baseline/burst change offered startup contention without increasing the actual session ceiling.
    @Test(arguments: [false, true])
    func boundedLifecycle(burst: Bool) async throws {
        let profile = try fixture(overrides: ["requests": 128, "shards": 4, "logicalAccounts": 1_000_000])
        let report = try await GatewayLoadRunner().run(profile: profile, burst: burst)
        #expect(report.logicalAccounts == 1_000_000)
        #expect(report.selectedBotIdentities == 2)
        #expect(report.selectedShards == 4)
        #expect(report.targetDispatches == 128)
        #expect(report.deliveredDispatches == 128)
        #expect(report.identifies == 4)
        #expect(report.resumes == 8)
        #expect(report.reconnects == 8)
        #expect(report.completedMemberRequests == 12)
        #expect(report.completedSoundboardRequests == 12)
        #expect(report.completedChannelInfoRequests == 12)
        #expect(report.typedResponseEvents == 48)
        #expect(report.applicationCommandWrites == 60)
        #expect(report.heartbeats > 0)
        #expect(report.heartbeatACKs > 0)
        #expect(report.heartbeatACKs <= report.heartbeats)
        #expect(report.startupStormOffered == 4 * (burst ? 10 : 2))
        #expect(report.startupStormAdmitted == 4)
        #expect(report.sampledPeakQueuedEvents <= 32)
        #expect(report.configuredMaximumQueuedEvents == 128)
        #expect(report.configuredMaximumQueuedBytes == 262_144)
        #expect(report.peakOwnedConnections <= 4)
        #expect(report.ownedConnectionsAfterShutdown == 0)
        #expect(report.leasesAfterShutdown == 0)
        #expect(report.pendingRequestsAfterShutdown == 0)
        #expect(report.applicationWritesAfterShutdown == 0)
        #expect(report.configuredMaximumPendingRequests == 16)
        #expect(report.configuredMaximumResponseEventsPerRequest == 8)
        #expect(report.configuredMaximumResponseBytes == 262_144)
        #expect(report.configuredMaximumRequestKeys == 128)
        #expect(report.controlDelay.sampleCount > 0)
        #expect(report.eventLag.sampleCount == 128)
        #expect(report.durationSeconds > 0)
        #expect(report.cpuSeconds >= 0)
        #expect(report.meanCPUPercentOfOneCore >= 0)
        #expect(report.afterShutdown.peakRSSBytes > 0)
        let text = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!text.contains("synthetic-local-only"))
        #expect(report.notes.contains { $0.contains("does not qualify") })
    }

    /// Uneven finite work distributes across sessions without losing READY/RESUMED ordering.
    @Test func unevenDistribution() async throws {
        let report = try await GatewayLoadRunner().run(profile: fixture(overrides: ["requests": 65, "shards": 4]), burst: false)
        #expect(report.deliveredDispatches == 65)
        #expect(report.eventLag.sampleCount == 65)
        #expect(report.resumes == 8)
        #expect(report.completedMemberRequests == 12)
        #expect(report.completedSoundboardRequests == 12)
        #expect(report.completedChannelInfoRequests == 12)
        #expect(report.leasesAfterShutdown == 0)
        #expect(report.ownedConnectionsAfterShutdown == 0)
    }

    /// A single credited raw event still executes every request round and both gated reconnects before shutdown.
    @Test func minimalRawWorkCompletesEveryGeneration() async throws {
        let report = try await GatewayLoadRunner().run(profile: fixture(overrides: ["requests": 1, "shards": 1]), burst: false)
        #expect(report.deliveredDispatches == 1)
        #expect(report.identifies == 1)
        #expect(report.resumes == 2)
        #expect(report.completedMemberRequests == 3)
        #expect(report.completedSoundboardRequests == 3)
        #expect(report.completedChannelInfoRequests == 3)
        #expect(report.typedResponseEvents == 12)
        #expect(report.applicationCommandWrites == 15)
        #expect(report.pendingRequestsAfterShutdown == 0)
        #expect(report.applicationWritesAfterShutdown == 0)
        #expect(report.ownedConnectionsAfterShutdown == 0)
        #expect(report.leasesAfterShutdown == 0)
    }

    /// Thousands of raw events keep synthetic heartbeat requests bounded so production command admission remains eligible.
    @Test func sustainedRawIngressPreservesCommandBudget() async throws {
        let report = try await GatewayLoadRunner().run(profile: fixture(overrides: ["requests": 4096, "shards": 1]), burst: true)
        #expect(report.deliveredDispatches == 4096)
        #expect(report.resumes == 2)
        #expect(report.applicationCommandWrites == 15)
        #expect(report.completedMemberRequests == 3)
        #expect(report.controlDelay.sampleCount == 3)
        #expect(report.pendingRequestsAfterShutdown == 0)
        #expect(report.applicationWritesAfterShutdown == 0)
        #expect(report.ownedConnectionsAfterShutdown == 0)
    }

    /// Unsafe profile names and unsupported bounded shapes fail before any connection or lease acquisition.
    @Test func validationAndPreCancellation() async throws {
        await #expect(throws: LoadFailure.invalidArguments) {
            try await GatewayLoadRunner().run(profileName: "../accounts-100", burst: false)
        }
        for overrides: [String: Any] in [["shards": 65], ["shards": 5], ["shards": 4, "requests": 3]] {
            let profile = try fixture(overrides: overrides)
            await #expect(throws: LoadFailure.invalidProfile) {
                try await GatewayLoadRunner().run(profile: profile, burst: false)
            }
        }
        let profile = try fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await GatewayLoadRunner().run(profile: profile, burst: false)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Reuses versioned profiles while replacing selected fields for small deterministic accounting tests.
    /// - Parameter overrides: JSON-compatible dimensions to replace, empty by default.
    /// - Returns: Decoded profile; production validation occurs inside the runner.
    /// - Throws: Fixture, JSON or profile decoding failure.
    private func fixture(overrides: [String: Any] = [:]) throws -> WorkloadProfile {
        let data = try Data(contentsOf: LoadPaths.packageDirectory.appendingPathComponent("Profiles/accounts-100.json"))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(WorkloadProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
