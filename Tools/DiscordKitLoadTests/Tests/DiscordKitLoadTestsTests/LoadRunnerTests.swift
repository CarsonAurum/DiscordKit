@testable import DiscordKitLoadTests
import DiscordNIOTransport
import DiscordTransport
import Foundation
import Testing

/// Pure statistics, versioned profile limits and bounded scripted-workload ownership.
@Suite("Transport load harness")
struct LoadRunnerTests {
    /// All logical populations use bounded cohorts and explicitly identify served users.
    @Test func versionedProfiles() throws {
        for population in [100, 10_000, 1_000_000] {
            let value = try WorkloadProfile.load(name: "accounts-\(population)",
                                                 directory: LoadPaths.packageDirectory.appendingPathComponent("Profiles"))
            #expect(value.logicalAccounts == population)
            #expect(value.accountMeaning == "servedEndUsers")
            #expect(value.activeLogicalAccounts == (population == 100 ? 100 : 1_000))
            #expect(value.activeCohort <= 32)
            #expect(value.maximumConnections == value.activeCohort)
            #expect(value.requests <= 100_000)
            #expect(value.maximumQueuedBytes == 0)
            #expect(value.assignment(for: population + 1).account == 1)
            #expect(value.assignment(for: -1).worker == 0)
            #expect(value.assignment(for: 5).worker == 5 % value.simulatedWorkers)
        }
        for name in ["../accounts-100", "", "accounts/100", "ACCOUNTS-100"] {
            #expect(throws: LoadFailure.invalidArguments) {
                try WorkloadProfile.load(name: name, directory: LoadPaths.packageDirectory)
            }
        }
    }

    /// Rejects invalid numeric and semantic profile dimensions before runtime work.
    @Test func profileValidationFailures() throws {
        for (key, value) in [
            ("version", 2 as Any), ("logicalAccounts", 0), ("activeCohort", 257),
            ("maximumConnections", 0), ("maximumConnections", 9), ("payloadBytes", -1),
            ("requests", 0), ("activeFraction", 0), ("accountMeaning", "botCredentials"),
            ("maximumQueuedCount", 1), ("maximumLatencySamples", 100_001),
            ("requestMix", "POST:100%"), ("burstMultiplier", 11),
            ("maximumPeakRSSBytes", 0), ("maximumEndHeapBytes", 0), ("targetP99Milliseconds", -1), ("subscriberPolicy", "abandonBody"),
        ] {
            let value = try fixture(overrides: [key: value])
            #expect(throws: LoadFailure.invalidProfile) { try value.validate() }
        }
    }

    /// CLI flags are unambiguous and future scenarios are rejected explicitly.
    @Test func options() throws {
        #expect(try LoadOptions(arguments: []).profileName == "accounts-100")
        let options = try LoadOptions(arguments: ["--profile", "accounts-10000", "--scenario", "transport", "--burst"])
        #expect(options.profileName == "accounts-10000")
        #expect(options.burst)
        let diagnostic = try LoadOptions(arguments: ["--portable", "--without-deadline", "--settle-seconds", "12"])
        #expect(diagnostic.portable)
        #expect(diagnostic.withoutDeadline)
        #expect(diagnostic.settleSeconds == 12)
        for arguments in [["--settle-seconds"], ["--settle-seconds", "31"], ["--settle-seconds", "-1"], ["--profile"], ["--unknown"], ["--burst", "--burst"], ["--profile", ""]] {
            #expect(throws: LoadFailure.invalidArguments) { try LoadOptions(arguments: arguments) }
        }
        #expect(try LoadOptions(arguments: ["--scenario", "http"]).scenario == "http")
        #expect(try LoadOptions(arguments: ["--scenario", "gateway"]).scenario == "gateway")
        for scenario in ["cache", "soak"] {
            #expect(try LoadOptions(arguments: ["--scenario", scenario]).scenario == scenario)
        }
        #expect(throws: LoadFailure.unsupportedScenario) { try LoadOptions(arguments: ["--scenario", "unknown"]) }
    }

    /// Quantiles use nearest rank and filter nonfinite/negative values without inventing samples.
    @Test func latencyStatistics() {
        #expect(LatencySummary.summarize([]).p99Milliseconds == nil)
        let one = LatencySummary.summarize([3, -.infinity, .nan, -1])
        #expect(one.sampleCount == 1)
        #expect(one.p50Milliseconds == 3)
        let many = LatencySummary.summarize(Array((1...100).reversed()).map(Double.init))
        #expect(many.p50Milliseconds == 50)
        #expect(many.p95Milliseconds == 95)
        #expect(many.p99Milliseconds == 99)
        let durations = LatencySummary.summarizeDurations([.seconds(-1), .zero, .microseconds(500), .milliseconds(1), .seconds(2)])
        #expect(durations.sampleCount == 4)
        #expect(durations.p50Milliseconds == 0.5)
        #expect(durations.p95Milliseconds == 2_000)
        #expect(durations.p99Milliseconds == 2_000)
        #expect(LatencySummary.summarizeDurations([]).p99Milliseconds == nil)
    }

    /// A million-account dimension retains only two tasks and three successful latency samples.
    @Test func boundedCohortAndBodyCleanup() async throws {
        let profile = try fixture(overrides: ["logicalAccounts": 1_000_000, "requests": 20,
                                             "maximumLatencySamples": 3])
        let transport = ScriptedLoadTransport(mode: .success, payloadBytes: profile.payloadBytes)
        let value = try await LoadRunner().run(profile: profile, transport: transport,
                                               url: URL(string: "http://127.0.0.1:8080/payload")!, offeredConcurrency: 2)
        #expect(value.logicalAccounts == 1_000_000)
        #expect(value.offeredRequests == 20)
        #expect(value.admittedSuccesses == 20)
        #expect(value.capacityRefusals == 0)
        #expect(value.failedRequests == 0)
        #expect(value.receivedBytes == 20 * profile.payloadBytes)
        #expect(value.maximumHarnessTasks == 2)
        #expect(value.latency.sampleCount == 3)
        #expect(await transport.liveBodyCount() == 0)
        #expect(await transport.maximumLiveBodies() <= 2)
    }

    /// Capacity, peer faults, malformed/oversized bodies and cancellation remain distinct.
    @Test func failuresAndCleanup() async throws {
        let profile = try fixture(overrides: ["requests": 4])
        for mode in ScriptedLoadTransport.Mode.allCases where mode != .success {
            let transport = ScriptedLoadTransport(mode: mode, payloadBytes: profile.payloadBytes)
            let value = try await LoadRunner().run(profile: profile, transport: transport,
                                                   url: URL(string: "http://127.0.0.1:8080/")!, offeredConcurrency: 2)
            #expect(value.offeredRequests == 4)
            #expect(value.admittedSuccesses == 0)
            if mode == .capacity { #expect(value.capacityRefusals == 4) }
            else if mode == .cancelled { #expect(value.cancelledRequests == 4) }
            else { #expect(value.failedRequests == 4) }
            #expect(await transport.liveBodyCount() == 0)
        }
    }

    /// Remote/credential-bearing destinations and excessive cohorts fail before any exchange.
    @Test func validationAndPreCancellation() async throws {
        let profile = try fixture(overrides: ["requests": 20])
        let transport = ScriptedLoadTransport(mode: .success, payloadBytes: profile.payloadBytes)
        for text in ["https://127.0.0.1:8080/", "http://example.com/", "http://secret@127.0.0.1/"] {
            await #expect(throws: LoadFailure.invalidArguments) {
                try await LoadRunner().run(profile: profile, transport: transport,
                                           url: URL(string: text)!, offeredConcurrency: 1)
            }
        }
        for concurrency in [0, 81] {
            await #expect(throws: LoadFailure.invalidArguments) {
                try await LoadRunner().run(profile: profile, transport: transport,
                                           url: URL(string: "http://127.0.0.1/")!, offeredConcurrency: concurrency)
            }
        }
        for deadline in [Duration.zero, .seconds(-1), .seconds(61)] {
            await #expect(throws: LoadFailure.invalidArguments) {
                try await LoadRunner().run(profile: profile, transport: transport,
                    url: URL(string: "http://127.0.0.1/")!, offeredConcurrency: 1, requestDeadline: deadline)
            }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LoadRunner().run(profile: profile, transport: transport,
                                               url: URL(string: "http://127.0.0.1/")!, offeredConcurrency: 1)
        }
        let value = try await task.value
        #expect(value.offeredRequests == 0)
        #expect(value.maximumHarnessTasks == 0)
        #expect(await transport.callCount() == 0)
    }

    /// Portable diagnostics exercise the same bounded bodies with and without clock races.
    @Test func portableDeadlineDiagnostics() async throws {
        let profile = try fixture(overrides: ["requests": 8])
        for deadline in [Duration.seconds(10), nil] {
            let value = try await LoadRunner().run(profile: profile,
                transport: PortableLoadTransport(payloadBytes: profile.payloadBytes),
                url: URL(string: "http://127.0.0.1/")!, offeredConcurrency: 2, requestDeadline: deadline)
            #expect(value.admittedSuccesses == 8)
            #expect(value.receivedBytes == 8 * profile.payloadBytes)
            #expect(value.failedRequests == 0)
        }
    }

    /// Cancellation during suspended work cancels and awaits the entire bounded cohort.
    @Test func cancellationDuringWork() async throws {
        let profile = try fixture(overrides: ["requests": 20])
        let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let transport = SuspendedLoadTransport(entered: signal.continuation)
        let task = Task {
            try await LoadRunner().run(profile: profile, transport: transport,
                                       url: URL(string: "http://127.0.0.1/")!, offeredConcurrency: 2)
        }
        var iterator = signal.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let value = try await task.value
        signal.continuation.finish()
        #expect(value.offeredRequests == 2)
        #expect(value.cancelledRequests == 2)
        #expect(value.admittedSuccesses == 0)
        #expect(await transport.suspendedCount() == 0)
    }

    /// Samples process CPU/memory with nonnegative gauges and no fabricated cross-host data.
    @Test func processMeasurements() {
        let sample = ProcessSample.capture()
        #expect(sample.cpuSeconds >= 0)
        #expect(sample.peakRSSBytes > 0)
        #if canImport(Darwin)
        #expect(sample.residentBytes != nil)
        #expect(sample.liveAllocationBlocks != nil)
        #expect(sample.liveAllocationBytes != nil)
        #endif
    }

    /// Loads the small checked-in JSON and changes selected values for negative cases.
    /// - Parameter overrides: JSON-compatible fields to replace, empty by default.
    /// - Returns: Decoded profile without validation, allowing invalid-value assertions.
    /// - Throws: File, JSON serialization or decoding errors.
    private func fixture(overrides: [String: Any] = [:]) throws -> WorkloadProfile {
        let data = try Data(contentsOf: LoadPaths.packageDirectory.appendingPathComponent("Profiles/accounts-100.json"))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(WorkloadProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

/// A scripted adapter records response-body ownership without any real socket or sleep.
private actor ScriptedLoadTransport: HTTPTransport {
    enum Mode: CaseIterable, Sendable { case success, capacity, failure, malformed, oversized, badStatus, nilBody, cancelled }
    private let mode: Mode
    private let payloadBytes: Int
    private var calls = 0
    private var live = 0
    private var maximumLive = 0

    /// Stores one categorical response mode without starting work.
    /// - Parameters:
    ///   - mode: Response/failure injected for every exchange.
    ///   - payloadBytes: Expected normal response size in bytes.
    init(mode: Mode, payloadBytes: Int) { self.mode = mode; self.payloadBytes = payloadBytes }

    /// Produces one owned bounded body or the requested safe adapter failure.
    /// - Parameters:
    ///   - request: Ignored caller request metadata; no secrets are recorded.
    ///   - context: Cancellation/deadline checked before any ownership mutation.
    /// - Returns: Scripted response including intentionally malformed cases.
    /// - Throws: Injected capacity/cancellation/peer errors or body construction failures.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
    where C.Duration == Duration {
        try context.check()
        calls += 1
        switch mode {
        case .capacity: throw NIOAdapterFailure.capacityExceeded
        case .failure: throw LoadFailure.unexpectedResponse
        case .cancelled: throw CancellationError()
        case .nilBody: return HTTPResponse(status: 200)
        default: break
        }
        live += 1
        maximumLive = max(maximumLive, live)
        let source = TestLoadBody(bytes: payloadBytes + (mode == .oversized ? 1 : 0), malformed: mode == .malformed)
        let body = try BodyStream(maximumChunkBytes: payloadBytes + 1,
                                  next: { await source.next() }, close: { await self.releaseBody() })
        return HTTPResponse(status: mode == .badStatus ? 500 : 200, body: body)
    }

    /// Returns the number of response bodies still owned by workload operations.
    /// - Returns: Nonnegative body count, expected zero after every run.
    func liveBodyCount() -> Int { live }

    /// Reports peak retained response bodies to verify the structured cohort bound.
    /// - Returns: Maximum simultaneous body ownership observed by this script.
    func maximumLiveBodies() -> Int { maximumLive }

    /// Reports executed requests so validation failures can prove absence of I/O.
    /// - Returns: Number of `execute` calls passing initial context checks.
    func callCount() -> Int { calls }

    /// Releases exactly one response-body source through `BodyStream` cleanup.
    private func releaseBody() { live -= 1 }
}

/// A one-chunk body source; malformed data verifies content validation, not just length.
private actor TestLoadBody {
    private var pending: Data?

    /// Creates one exact body chunk without any upstream tasks or network resources.
    /// - Parameters:
    ///   - bytes: Nonnegative response chunk size.
    ///   - malformed: Emit a nonmatching byte when true; default payload is ASCII x.
    init(bytes: Int, malformed: Bool) { pending = Data(repeating: malformed ? 121 : 120, count: bytes) }

    /// Pulls the body once, then returns terminal EOF on every later call.
    /// - Returns: Stored chunk or nil after its first consumption.
    func next() -> Data? { defer { pending = nil }; return pending }
}

/// An adapter that suspends in a cancellation-aware stream until the workload is cancelled.
private actor SuspendedLoadTransport: HTTPTransport {
    private let entered: AsyncStream<Void>.Continuation
    private var suspended = 0

    /// Stores the test's entry notification without starting any child task.
    /// - Parameter entered: Bounded signal opened when an exchange is suspended.
    init(entered: AsyncStream<Void>.Continuation) { self.entered = entered }

    /// Suspends one request without timers and releases its waiter on cancellation.
    /// - Parameters:
    ///   - request: Ignored request metadata; no payload or credentials are retained.
    ///   - context: Cancellation checked before entering the suspended operation.
    /// - Returns: Never succeeds; only the cancellation path is exercised.
    /// - Throws: Cancellation after stream termination, or a safe fallback error.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
    where C.Duration == Duration {
        try context.check()
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        suspended += 1
        defer { suspended -= 1; channel.continuation.finish() }
        entered.yield(())
        var iterator = channel.stream.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
        throw LoadFailure.unexpectedResponse
    }

    /// Reports suspended owned operations after structured cancellation completes.
    /// - Returns: Zero after the load runner has awaited its task group.
    func suspendedCount() -> Int { suspended }
}
