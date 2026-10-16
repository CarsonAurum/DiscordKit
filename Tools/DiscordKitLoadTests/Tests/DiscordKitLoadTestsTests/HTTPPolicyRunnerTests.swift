import DiscordHTTP
import Foundation
import Testing
@testable import DiscordKitLoadTests

/// Verifies offline HTTP policy workloads, numeric profile validation and bounded cleanup.
@Suite("HTTP policy load harness")
struct HTTPPolicyRunnerTests {
    /// Three logical populations keep actual identities, task cohorts and all owner budgets finite.
    @Test func profiles() throws {
        let directory = LoadPaths.packageDirectory.appendingPathComponent("HTTPProfiles")
        for population in [100, 10_000, 1_000_000] {
            let profile = try HTTPWorkloadProfile.load(name: "accounts-\(population)", directory: directory)
            #expect(profile.logicalAccounts == population)
            #expect(profile.botIdentities <= 16)
            #expect(profile.cohort <= 32)
            #expect(profile.maximumQueuedRequests == profile.cohort * 2)
            #expect(profile.maximumConcurrentRequests == profile.cohort)
            #expect(profile.requests <= 20_000)
        }
        for name in ["", "../accounts-100", "ACCOUNTS-100", "accounts/100"] {
            #expect(throws: LoadFailure.invalidArguments) { try HTTPWorkloadProfile.load(name: name, directory: directory) }
        }
    }

    /// Rejects invalid numeric budgets before actors, task cohorts or producer metadata are created.
    @Test func invalidProfiles() throws {
        for (key, value) in [
            ("version", 2), ("logicalAccounts", 0), ("botIdentities", 65), ("requests", 0),
            ("cohort", 129), ("maximumQueuedRequests", 0), ("maximumQueuedBytes", 0),
            ("maximumConcurrentRequests", 9), ("maximumCacheEntries", 0), ("maximumCacheBytes", 0),
            ("maximumMetadata", 1), ("maximumLatencySamples", 0), ("targetP99Milliseconds", 0), ("maximumPeakRSSBytes", 0),
        ] {
            let profile = try fixture(overrides: [key: value])
            #expect(throws: LoadFailure.invalidProfile) { try profile.validate() }
        }
    }

    /// A finite request mix retries explicit rejections, reduces wire work and releases every injected owner.
    /// Artificial wire latency is disabled; assertions cover counts and bounds, not timing or throughput.
    @Test func mixedWorkloadAndCleanup() async throws {
        let profile = try fixture(overrides: ["requests": 100, "maximumLatencySamples": 3])
        let report = try await HTTPPolicyRunner().run(profile: profile, simulatedLatency: .zero)
        #expect(report.scenario == "offlineHTTPPolicy")
        #expect(report.offeredRequests == 100)
        #expect(report.successfulRequests == 100)
        #expect(report.failedRequests == 0)
        #expect(report.refusedRequests == 0)
        #expect(report.cancelledRequests == 0)
        #expect(report.retryResponses == 10)
        #expect(report.cacheWireExchanges == profile.botIdentities)
        #expect(report.coalescedStormWireExchanges <= 30)
        #expect(report.avoidedExchanges >= 38)
        #expect(report.minimumIdentitySuccesses == 50)
        #expect(report.maximumIdentitySuccesses == 50)
        #expect(report.latency.sampleCount == 3)
        #expect(report.sampledResourceBudgetsMet)
        #expect(report.activeAfterShutdown == 0)
        #expect(report.queuedAfterShutdown == 0)
        #expect(report.flightsAfterShutdown == 0)
        #expect(report.cacheEntriesAfterShutdown == 0)
        #expect(report.peakTransportExchanges <= profile.maximumConcurrentRequests)
        #expect(report.peakRetryMetadata <= profile.cohort)
        #expect(report.cpuSeconds >= 0)
        #expect(report.afterShutdown.peakRSSBytes > 0)
        #expect(!report.notes.isEmpty)
        #expect(try JSONEncoder().encode(report).count > 0)
    }

    /// Tenfold offered cohorts retain configured owner caps even when they refuse excess work.
    @Test func burstRetainsBudgets() async throws {
        let profile = try fixture(overrides: ["requests": 100])
        let report = try await HTTPPolicyRunner().run(profile: profile, burst: true, simulatedLatency: .zero)
        #expect(report.burst)
        #expect(report.offeredConcurrency == profile.cohort * 10)
        #expect(report.offeredRequests == 100)
        #expect(report.successfulRequests + report.refusedRequests + report.failedRequests + report.cancelledRequests == 100)
        #expect(report.failedRequests == 0)
        #expect(report.sampledResourceBudgetsMet)
        #expect(report.activeAfterShutdown == 0)
        #expect(report.queuedAfterShutdown == 0)
        #expect(report.flightsAfterShutdown == 0)
    }

    /// Pre-cancellation stops replenishment and closes owners with zero wire work; invalid settings perform no workload.
    @Test func cancellationAndValidation() async throws {
        let profile = try fixture(overrides: ["requests": 100])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HTTPPolicyRunner().run(profile: profile, simulatedLatency: .zero)
        }
        let report = try await task.value
        #expect(report.successfulRequests == 0)
        #expect(report.wireExchanges == 0)
        #expect(report.cancelledRequests == profile.cohort)
        #expect(report.offeredRequests == profile.cohort)
        #expect(report.activeAfterShutdown == 0)
        await #expect(throws: LoadFailure.invalidArguments) { try await HTTPPolicyRunner().run(profile: profile, simulatedLatency: .seconds(-1)) }
        await #expect(throws: LoadFailure.invalidArguments) { try await LoadCommand.run(arguments: ["--scenario", "http", "--portable"]) }
        await #expect(throws: LoadFailure.invalidArguments) { try await LoadCommand.run(arguments: ["--scenario", "http", "--without-deadline"]) }
        await #expect(throws: LoadFailure.invalidArguments) { try await LoadCommand.run(arguments: ["--scenario", "http", "--settle-seconds", "1"]) }
    }

    /// Loads one profile and replaces exact JSON fields to exercise invalid budgets and small workloads.
    /// - Parameter overrides: JSON-compatible replacement members, empty by default.
    /// - Returns: Decoded profile without validation, permitting negative validation tests.
    /// - Throws: File, JSON serialization or decoding errors for malformed fixture setup.
    private func fixture(overrides: [String: Any] = [:]) throws -> HTTPWorkloadProfile {
        let data = try Data(contentsOf: LoadPaths.packageDirectory.appendingPathComponent("HTTPProfiles/accounts-100.json"))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(HTTPWorkloadProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
