// File: Tools/DiscordKitLoadTests/Tests/DiscordKitLoadTestsTests/CacheLoadRunnerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@testable import DiscordKitLoadTests
import DiscordCache
import DiscordModels
import Foundation
import Testing

/// Fixed-working-set cache and broadcast evidence has exact counters and bounded ownership.
@Suite("Cache recovery load harness")
struct CacheLoadRunnerTests {
    /// Cache/soak CLI accepts exact positive rounds and rejects irrelevant or malformed combinations.
    /// - Throws: Unexpected CLI validation errors for valid inputs.
    @Test func cacheAndSoakRoundOptions() throws {
        for scenario in ["cache", "soak"] {
            let options = try LoadOptions(arguments: ["--scenario", scenario, "--rounds", "2", "--burst"])
            #expect(options.scenario == scenario && options.rounds == 2 && options.burst)
            #expect(try LoadOptions(arguments: ["--scenario", scenario]).rounds == nil)
        }
        for arguments in [["--rounds", "2"], ["--scenario", "http", "--rounds", "2"],
                          ["--scenario", "cache", "--rounds"], ["--scenario", "cache", "--rounds", "0"],
                          ["--scenario", "soak", "--rounds", "1000001"], ["--scenario", "cache", "--rounds", "invalid"],
                          ["--scenario", "cache", "--rounds", "2", "--rounds", "3"]] {
            #expect(throws: LoadFailure.invalidArguments) { try LoadOptions(arguments: arguments) }
        }
        #expect(try LoadOptions(arguments: ["--scenario", "soak", "--duration-seconds", "1800"]).durationSeconds == 1_800)
        for arguments in [["--scenario", "cache", "--duration-seconds", "1"],
                          ["--scenario", "soak", "--duration-seconds", "0"],
                          ["--scenario", "soak", "--duration-seconds", "3601"], ["--duration-seconds"]] {
            #expect(throws: LoadFailure.invalidArguments) { try LoadOptions(arguments: arguments) }
        }
    }

    /// Logical scale selects only 1/2/4 scopes while exact rounds retain fixed key/task bounds.
    /// - Parameter population: All three repository-owned served-end-user profiles.
    /// - Throws: Profile, cache, event or invariant errors for a valid local scenario.
    @available(macOS 15, *)
    @Test(arguments: [100, 10_000, 1_000_000]) func profilesKeepBoundedWorkingSets(population: Int) async throws {
        let value = try await CacheLoadRunner().run(profileName: "accounts-\(population)", burst: false, rounds: 2)
        let scopes = population == 100 ? 1 : population == 10_000 ? 2 : 4
        #expect(value.logicalAccounts == population && value.selectedScopes == scopes)
        #expect(value.configuredRounds == 2 && value.completedRounds == 2)
        #expect(value.workingSetKeysPerScope == 20)
        #expect(value.offeredRefreshCalls == 32 * scopes)
        #expect(value.completedRefreshCalls == 16 * scopes)
        #expect(value.actualLoaderCalls == 2 * scopes)
        #expect(value.capacityRefusals == 16 * scopes)
        #expect(value.coalescedReads == UInt64(14 * scopes))
        #expect(value.evictions == UInt64(8 * scopes))
        #expect(value.expirations == UInt64(32 * scopes))
        #expect(value.recoveryReads == 2 * scopes)
        #expect(value.healthyBroadcastDeliveries == 6 && value.slowSubscriberResynchronizations == 2)
        #expect(value.peakEntries == 16 * scopes && value.maximumEntries == 16 * scopes)
        #expect(value.peakAccountedBytes > 0 && value.peakAccountedBytes <= value.maximumAccountedBytes)
        #expect(value.peakRefreshes == 1 && value.peakWaiters == 8 && value.peakBufferedEvents == 2)
        #expect(value.entriesAfterShutdown == 0 && value.refreshesAfterShutdown == 0 && value.waitersAfterShutdown == 0)
        #expect(value.subscriptionsAfterShutdown == 0 && value.bufferedEventsAfterShutdown == 0)
        #expect(value.durationSeconds > 0 && value.cpuSeconds >= 0)
        #expect(value.afterShutdown.peakRSSBytes > 0)
        #expect(value.configuredDurationSeconds == nil)
        #expect(value.checkpoints.count == 4)
        #expect(value.checkpoints.first?.completedRounds == 0)
        #expect(value.checkpoints.last?.completedRounds == 2 && value.checkpoints.last?.entries == 0)
    }

    /// Burst increases only refused callers; admitted loaders, retained entities and recovery stay bounded.
    /// - Throws: Local scenario or JSON encoding/decoding errors.
    @available(macOS 15, *)
    @Test func burstAndSoakReportsRemainExplicit() async throws {
        let normal = try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 1)
        let burst = try await CacheLoadRunner().run(profileName: "accounts-100", burst: true, rounds: 1, scenario: "soak")
        #expect(burst.scenario == "soak" && burst.completedRounds == 1)
        #expect(burst.offeredRefreshCalls == 64 && burst.capacityRefusals == 56)
        #expect(normal.offeredRefreshCalls == 16 && normal.capacityRefusals == 8)
        #expect(burst.completedRefreshCalls == normal.completedRefreshCalls)
        #expect(burst.actualLoaderCalls == 1 && burst.actualLoaderCalls == normal.actualLoaderCalls)
        #expect(burst.peakEntries == normal.peakEntries && burst.peakWaiters == normal.peakWaiters)
        let encoded = try JSONEncoder().encode(burst)
        let decoded = try JSONDecoder().decode(CacheLoadReport.self, from: encoded)
        #expect(decoded.actualLoaderCalls == burst.actualLoaderCalls)
        #expect(decoded.afterShutdown.peakRSSBytes == burst.afterShutdown.peakRSSBytes)
        #expect(decoded.notes.contains { $0.contains("No fleet or 30-minute qualification") })
    }

    /// Invalid rounds/labels and pre-cancellation fail before resource acquisition.
    /// - Throws: Profile setup errors or failures other than the expected cancellation.
    @available(macOS 15, *)
    @Test func validationAndPreCancellation() async throws {
        for rounds in [-1, 0, 1_000_001, Int.max] {
            await #expect(throws: LoadFailure.invalidArguments) {
                try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: rounds)
            }
        }
        await #expect(throws: LoadFailure.invalidArguments) {
            try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 1, scenario: "transport")
        }
        for duration in [0, 3_601] {
            await #expect(throws: LoadFailure.invalidArguments) {
                try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 1,
                                                scenario: "soak", durationSeconds: duration)
            }
        }
        await #expect(throws: LoadFailure.invalidArguments) {
            try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 1, durationSeconds: 1)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 1)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    /// Bounded progress retention keeps initial/final samples even after more than 121 rounds.
    /// - Throws: Unexpected local cache/broadcast or fixture errors.
    @available(macOS 15, *)
    @Test func checkpointHistoryStaysBounded() async throws {
        let report = try await CacheLoadRunner().run(profileName: "accounts-100", burst: false, rounds: 122)
        #expect(report.completedRounds == 122 && report.checkpoints.count == 121)
        #expect(report.checkpoints.first?.completedRounds == 0)
        #expect(report.checkpoints.last?.completedRounds == 122)
        #expect(report.checkpoints.last?.entries == 0)
        #expect(report.checkpoints.allSatisfy { $0.entries <= report.maximumEntries && $0.accountedBytes <= report.maximumAccountedBytes })
    }

    /// Explicit duration keeps the same working set running for real monotonic time, without timed sleeps.
    /// - Throws: Unexpected local workload or report invariant errors.
    @available(macOS 15, *)
    @Test func requestedWallDurationIsActuallyMeasured() async throws {
        let report = try await CacheLoadRunner().run(profileName: "accounts-100", burst: false,
            rounds: 1, scenario: "soak", durationSeconds: 1)
        #expect(report.configuredDurationSeconds == 1 && report.durationSeconds >= 1)
        #expect(report.completedRounds >= report.configuredRounds)
        #expect(report.checkpoints.count <= 121 && report.checkpoints.count >= 2)
        #expect(report.checkpoints.first?.elapsedSeconds == 0)
        #expect(report.checkpoints.last?.elapsedSeconds == report.durationSeconds)
        #expect(report.completedRefreshCalls == report.completedRounds * 8)
        #expect(report.actualLoaderCalls == report.completedRounds)
        #expect(report.entriesAfterShutdown == 0 && report.refreshesAfterShutdown == 0)
    }

    /// Explicit TTL advancement is inclusive, ignores negative steps and never sleeps in real time.
    /// - Throws: Unexpected clock errors for present/past deadlines.
    @available(macOS 15, *)
    @Test func manualTTLClockSemantics() async throws {
        let clock = CacheLoadClock(), initial = clock.now
        #expect(clock.minimumResolution == .nanoseconds(1))
        clock.advance(by: .seconds(-1))
        #expect(clock.now == initial)
        clock.advance(by: .seconds(1))
        #expect(initial.duration(to: clock.now) == .seconds(1))
        try await clock.sleep(until: clock.now, tolerance: nil)
        try await clock.sleep(until: initial, tolerance: .milliseconds(1))
        await #expect(throws: LoadFailure.unsupportedScenario) {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(1)), tolerance: nil)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(until: initial, tolerance: nil)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    /// Refresh barriers release once, accept prerelease and wake cancellation without leaking suspended work.
    /// - Throws: Unexpected barrier failures outside the explicitly cancelled invocation.
    @Test func refreshGateCancellationAndPrerelease() async throws {
        let snapshot = EntitySnapshot(fields: ["id": .string("1")], completeness: .complete)
        let immediate = CacheLoadGate()
        await immediate.release()
        #expect(try await immediate.load(snapshot) == snapshot)
        await immediate.release()
        await immediate.recordRefusal(); await immediate.recordFailure()
        let counts = await immediate.counts()
        #expect(counts.calls == 1 && counts.refusals == 1 && counts.failures == 1)
        let pending = CacheLoadGate()
        let task = Task { try await pending.load(snapshot) }
        while await pending.counts().calls == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await pending.release()
        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CacheLoadGate().load(snapshot)
        }
        await #expect(throws: CancellationError.self) { try await preCancelled.value }
    }
}
