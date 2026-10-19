import Foundation

/// Complete matrix artifact carries its configuration, local environment and explicit measurement boundaries.
struct BenchmarkReport: Encodable, Sendable {
    let schemaVersion = 1
    let configuration: BenchmarkConfiguration
    let environment: BenchmarkEnvironment
    let workloads: [WorkloadMeasurement]
    let qualification: [String]
}

/// Local offline authoring/handler measurements; the executable has no listener, credentials or remote adapter.
@main struct DiscordDSLBenchmarks {
    /// Executes deterministic direct-then-DSL pairs and emits one inspectable JSON artifact.
    /// - Throws: Configuration, original workload validation or hard functional gate failure; no partial success artifact is written.
    static func main() async throws {
        let parsed = try BenchmarkConfiguration.parse(Array(CommandLine.arguments.dropFirst()))
        let environment = BenchmarkEnvironment.capture()
        var workloads: [WorkloadMeasurement] = []
        for count in parsed.configuration.handlerCounts {
            for mode in ["direct", "dsl"] {
                workloads.append(try await RuntimeBenchmark.run(mode: mode, handlerCount: count, configuration: parsed.configuration))
            }
        }
        let report = BenchmarkReport(configuration: parsed.configuration, environment: environment, workloads: workloads,
            qualification: [
                "Local synthetic normalized HTTP contexts; no signature verification, network, Discord, Gateway host or fleet-capacity qualification.",
                "Each declared handler has one retained schema and one fixed interaction snapshot; each invocation creates a fresh response owner and typed arguments.",
                "Direct and DSL paths share the real typed decoder, handler, router and response ownership; the direct route is handwritten and the DSL route uses SlashCommand and CommandCompilation.",
                "Plan compilation includes authoring, schema capture, lowering and router admission; it excludes fixed input parsing, sink creation and consumer compiler time measured by the separate build script. Process snapshots include the fixture population.",
                "Latency is a bounded prefix of end-to-end route invocations including fresh responder construction and exact initial callback validation; throughput covers every invocation and joined worker round.",
                "The process runs direct then DSL for each declared count; allocator/runtime warmup, prior workloads and process peaks can affect later observations. RSS/malloc gauges are process-wide, not isolated retained-plan sizes or cumulative allocation events.",
                "Accounted state reports retained input/author JSON byte counts and configured cardinality caps, not exact heap allocation size. Current RSS and live allocation gauges are best-effort platform observations.",
                "No REST client, registration reconciler, hydration provider, transport or listener is constructed; only the initial offline callback sink is configured. Implicit REST request counts are structurally zero.",
                "Duration-floor runs repeat the fixed population up to a hard 100-million invocation ceiling; existing cache/broadcast soak and handler execution evidence remain separate.",
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let output = parsed.output { try data.write(to: URL(fileURLWithPath: output), options: .atomic) }
        else { print(String(decoding: data, as: UTF8.self)) }
    }
}
