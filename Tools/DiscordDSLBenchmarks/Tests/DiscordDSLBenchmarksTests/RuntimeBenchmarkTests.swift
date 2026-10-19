import DiscordCommandDSL
import DiscordCore
import DiscordInteractions
import Foundation
import Testing
@testable import DiscordDSLBenchmarks

/// Schema instrumentation is process-global; serialize this independent suite to preserve exact deltas.
@Suite(.serialized) struct RuntimeBenchmarkTests {
    /// Default qualification selects the complete million-invocation paired population and finite dimensions.
    /// - Throws: Unexpected configuration validation failure.
    @Test func defaultMatrix() throws {
        let parsed = try BenchmarkConfiguration.parse([])
        #expect(parsed.configuration.invocations == 1_000_000)
        #expect(parsed.configuration.handlerCounts == [10, 100, 1_000])
        #expect(parsed.configuration.concurrency == 8)
        #expect(parsed.configuration.sampleLimit == 10_000)
        #expect(parsed.output == nil)
    }

    /// Invalid, repeated, unbounded and incomplete CLI values are rejected before building plans.
    /// - Throws: Only expected parse errors, captured by the assertions.
    @Test func configurationBounds() throws {
        let invalid = [
            ["--invocations", "0"], ["--invocations", "10000001"],
            ["--handlers", "10,10"], ["--handlers", "1001"], ["--handlers", "10,"],
            ["--concurrency", "65"], ["--sample-limit", "100001"], ["--payload-bytes", "1025"],
            ["--minimum-duration-seconds", "1801"], ["--unknown", "1"],
            ["--concurrency", "1", "--concurrency", "2"], ["--output"],
        ]
        for arguments in invalid { #expect(throws: BenchmarkError.self) { try BenchmarkConfiguration.parse(arguments) } }
        let parsed = try BenchmarkConfiguration.parse(["--invocations", "9", "--handlers", "10", "--concurrency", "3", "--output", "result.json"])
        #expect(parsed.configuration.invocations == 9)
        #expect(parsed.configuration.handlerCounts == [10])
        #expect(parsed.configuration.concurrency == 3)
        #expect(parsed.output == "result.json")
    }

    /// Every inclusive configuration edge is valid without materializing its potentially large workload.
    /// - Throws: Unexpected rejection of a documented inclusive bound.
    @Test func inclusiveConfigurationEdges() throws {
        var configuration = BenchmarkConfiguration()
        configuration.invocations = 1
        configuration.concurrency = 1
        configuration.sampleLimit = 1
        configuration.payloadBytes = 1
        try configuration.validate()
        configuration.invocations = 10_000_000
        configuration.concurrency = 64
        configuration.sampleLimit = 100_000
        configuration.payloadBytes = 1_024
        configuration.minimumDurationSeconds = 1_800
        try configuration.validate()
    }

    /// Internal runner APIs enforce the same mode/population admission as the CLI before building schemas.
    /// - Throws: Expected configuration failures are asserted; unexpected errors fail the test.
    @Test func invalidPlanSelectionIsInert() throws {
        var configuration = BenchmarkConfiguration()
        configuration.handlerCounts = [10]
        let counters = BenchmarkCounters()
        let initialSchemas = BenchmarkArguments.captures.snapshot().schemas
        #expect(throws: BenchmarkError.self) {
            try RuntimeBenchmark.makePlan(mode: "unknown", handlerCount: 10, configuration: configuration, counters: counters)
        }
        #expect(throws: BenchmarkError.self) {
            try RuntimeBenchmark.makePlan(mode: "dsl", handlerCount: 100, configuration: configuration, counters: counters)
        }
        #expect(BenchmarkArguments.captures.snapshot().schemas == initialSchemas)
        #expect(counters.snapshot().handlers == 0)
    }

    /// Real direct and DSL authoring produce exactly the same model registration payloads and fresh response behavior.
    /// - Throws: Original authoring, decoding, response ownership or functional gate failures.
    @Test func directDSLParityAndCleanup() async throws {
        var configuration = BenchmarkConfiguration()
        configuration.invocations = 120
        configuration.handlerCounts = [10]
        configuration.concurrency = 3
        configuration.sampleLimit = 17
        let directCounters = BenchmarkCounters(), dslCounters = BenchmarkCounters()
        let directPlan = try RuntimeBenchmark.makePlan(mode: "direct", handlerCount: 10, configuration: configuration, counters: directCounters)
        let dslPlan = try RuntimeBenchmark.makePlan(mode: "dsl", handlerCount: 10, configuration: configuration, counters: dslCounters)
        #expect(directPlan.registrations.map { $0.request.jsonValue() } == dslPlan.registrations.map { $0.request.jsonValue() })
        #expect(directCounters.snapshot().handlers == 0)
        #expect(dslCounters.snapshot().handlers == 0)
        for index in 0..<10 {
            try await RuntimeBenchmark.invoke(directPlan, index: index)
            try await RuntimeBenchmark.invoke(dslPlan, index: index)
        }
        #expect(directCounters.snapshot().callbacks == 10)
        #expect(dslCounters.snapshot().callbacks == 10)
        for mode in ["direct", "dsl"] {
            let result = try await RuntimeBenchmark.run(mode: mode, handlerCount: 10, configuration: configuration)
            #expect(result.invocations == 120)
            #expect(result.counters.handlers == 120)
            #expect(result.counters.callbacks == 120)
            #expect(result.schemaBuilds == 10)
            #expect(result.schemasAfterInvocations == 10)
            #expect(result.latency.sampleCount == 17)
            #expect(result.counters.peakWorkers <= 3)
            #expect(result.accountedState.fixedInteractionCount == 10)
            #expect(result.accountedState.fixedInteractionJSONBytes > 0)
            #expect(result.cleanup.activeHandlers == 0)
            #expect(result.cleanup.activeAcknowledgements == 0)
            #expect(result.cleanup.acknowledgementBytes == 0)
            #expect(result.cleanup.activeWorkers == 0)
            #expect(result.implicitHydrationRequests == 0)
            #expect(result.implicitRegistrationRequests == 0)
            #expect(result.functionalGatesPassed)
        }
    }

    /// A failing real callback releases the router, acknowledgement reservation and every finite worker.
    /// - Throws: Unexpected plan construction or ownership errors; expected sink failure is asserted.
    @Test func failureReleasesOwnership() async throws {
        var configuration = BenchmarkConfiguration()
        configuration.handlerCounts = [10]
        configuration.concurrency = 2
        let counters = BenchmarkCounters()
        let original = try RuntimeBenchmark.makePlan(mode: "dsl", handlerCount: 10, configuration: configuration, counters: counters)
        let plan = RuntimePlan(compilationMilliseconds: original.compilationMilliseconds, router: original.router, interactions: original.interactions, registrations: original.registrations,
            admission: original.admission, sink: .init(initial: { _, _ in throw BenchmarkError.functionalGate }),
            accountedState: original.accountedState)
        await #expect(throws: BenchmarkError.self) {
            try await RuntimeBenchmark.runRound(plan, start: 0, count: 12, configuration: configuration, counters: counters)
        }
        #expect(await plan.router.activeHandlerCount == 0)
        let admission = await plan.admission.snapshot()
        #expect(admission.activeCount == 0)
        #expect(admission.encodedBytes == 0)
        #expect(counters.snapshot().activeWorkers == 0)
    }

    /// Cancellation during a real suspended callback closes/join workers and releases all admission.
    /// - Throws: Unexpected setup/callback errors; the expected cancellation is asserted.
    @Test func cancellationReleasesOwnership() async throws {
        var configuration = BenchmarkConfiguration()
        configuration.handlerCounts = [10]
        configuration.concurrency = 1
        let counters = BenchmarkCounters(), entered = CallbackSignal()
        let original = try RuntimeBenchmark.makePlan(mode: "dsl", handlerCount: 10, configuration: configuration, counters: counters)
        let plan = RuntimePlan(compilationMilliseconds: original.compilationMilliseconds, router: original.router, interactions: original.interactions, registrations: original.registrations,
            admission: original.admission, sink: .init(initial: { _, _ in
                await entered.signal()
                try await Task.sleep(for: .seconds(30))
            }), accountedState: original.accountedState)
        let task = Task { try await RuntimeBenchmark.runRound(plan, start: 0, count: 12, configuration: configuration, counters: counters) }
        await entered.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plan.router.activeHandlerCount == 0)
        let admission = await plan.admission.snapshot()
        #expect(admission.activeCount == 0)
        #expect(admission.encodedBytes == 0)
        #expect(counters.snapshot().activeWorkers == 0)
    }

    /// A caller cancelled before worker admission cannot execute handlers or reserve acknowledgements.
    /// - Throws: Unexpected setup errors; expected cooperative cancellation is asserted.
    @Test func cancellationBeforeRoundIsInert() async throws {
        var configuration = BenchmarkConfiguration()
        configuration.handlerCounts = [10]
        let counters = BenchmarkCounters(), gate = CallbackSignal()
        let plan = try RuntimeBenchmark.makePlan(mode: "dsl", handlerCount: 10, configuration: configuration, counters: counters)
        let task = Task {
            await gate.wait()
            return try await RuntimeBenchmark.runRound(plan, start: 0, count: 12, configuration: configuration, counters: counters)
        }
        task.cancel()
        await gate.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(counters.snapshot().handlers == 0)
        #expect(counters.snapshot().callbacks == 0)
        #expect(counters.snapshot().activeWorkers == 0)
        #expect(await plan.router.activeHandlerCount == 0)
        #expect(await plan.admission.snapshot().activeCount == 0)
    }

    /// Quantiles use bounded nearest-rank observations and exclude invalid or negative samples.
    @Test func quantiles() {
        let summary = LatencySummary.summarize([1, 2, 3, 4, .nan, .infinity, -1])
        #expect(summary.sampleCount == 4)
        #expect(summary.p50Milliseconds == 2)
        #expect(summary.p95Milliseconds == 4)
        #expect(summary.p99Milliseconds == 4)
        #expect(LatencySummary.summarize([]).p50Milliseconds == nil)
    }
}

/// Deterministic test rendezvous avoids sleep-based assumptions about callback/cleanup ordering.
private actor CallbackSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Records callback entry and releases the one test waiter.
    func signal() { signalled = true; waiter?.resume(); waiter = nil }

    /// Awaits callback entry without starting timers or creating an unbounded waiter collection.
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
