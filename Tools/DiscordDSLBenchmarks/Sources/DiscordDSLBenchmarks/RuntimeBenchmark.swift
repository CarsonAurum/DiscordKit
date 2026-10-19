import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import Foundation

/// Synchronous constant-size counters; the lock protects instrumentation, never application authority.
final class BenchmarkCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var values = CounterSnapshot()

    /// Records one schema capture during inert authoring; invocation must never call this method.
    func schema() { lock.withLock { values.schemas += 1 } }
    /// Records one successfully decoded handler execution without retaining the submitted value.
    func handler() { lock.withLock { values.handlers += 1 } }
    /// Records one exact validated offline initial callback without retaining response history.
    func callback() { lock.withLock { values.callbacks += 1 } }
    /// Admits one of the finite worker cohort and observes its active high-water mark.
    func enterWorker() { lock.withLock { values.activeWorkers += 1; values.peakWorkers = max(values.peakWorkers, values.activeWorkers) } }
    /// Releases worker ownership on success, cancellation and failure.
    func leaveWorker() { lock.withLock { values.activeWorkers -= 1 } }
    /// Copies bounded aggregate counters without exposing mutable instrumentation storage.
    /// - Returns: The exact synchronized current counters.
    func snapshot() -> CounterSnapshot { lock.withLock { values } }
}

/// Only aggregate counts are retained; there is no invocation-sized result or identity history.
struct CounterSnapshot: Codable, Sendable {
    var schemas = 0
    var handlers = 0
    var callbacks = 0
    var activeWorkers = 0
    var peakWorkers = 0
}

/// One required finite string exercises real typed decoding equally in the direct and lowered route.
struct BenchmarkArguments: CommandArguments {
    let payload: String
    static let captures = BenchmarkCounters()

    static var schema: CommandArgumentSchema<Self> {
        /// Captures one bounded schema during plan creation; the router retains this immutable value.
        /// - Throws: Existing descriptor/schema validation failures, propagated before runtime execution.
        get throws {
            captures.schema()
            let payload = try ArgumentOption<String>(name: "payload", description: "Fixed offline payload", maxLength: 1_024)
            return try CommandArgumentSchema(options: [payload.erased]) { decoder in
                try Self(payload: decoder.value(for: payload))
            }
        }
    }
}

/// The same manual-response handler is called by the handwritten route and the real DSL lowering.
struct BenchmarkHandler: ManualSlashCommandHandler {
    typealias Arguments = BenchmarkArguments
    let name: String
    let counters: BenchmarkCounters

    /// Returns deterministic author metadata without ambient credentials, tasks, registration or I/O.
    var command: SlashCommandMetadata { .init(name: name, description: "Fixed offline benchmark") }

    /// Replies once through the existing responder after complete typed argument preparation.
    /// - Parameters:
    ///   - context: Synthetic normalized HTTP context with a fresh response owner for this invocation.
    ///   - arguments: Fresh typed values decoded through the captured schema.
    /// - Throws: Existing payload, cancellation, response ownership or offline sink validation failure.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        counters.handler()
        try await context.responder.reply(InteractionMessageCreate(content: .value(arguments.payload)))
    }
}

/// Variable-size retained author/input storage is accounted separately from actual process memory.
struct AccountedState: Codable, Sendable {
    let declaredHandlers: Int
    let retainedSchemas: Int
    let fixedInteractionCount: Int
    let fixedInteractionJSONBytes: Int
    let registrationJSONBytes: Int
    let routeMetadataJSONBytes: Int
    let planDescriptionTextBytes: Int
    let maximumWorkers: Int
    let maximumLatencySamples: Int
    let maximumMemorySamples: Int
    let maximumPayloadBytes: Int
    let maximumActualInvocations: Int
}

/// Shared immutable route and fixture population; no work or network owner is created implicitly.
struct RuntimePlan: Sendable {
    let compilationMilliseconds: Double
    let router: CommandRouter
    let interactions: [Interaction]
    let registrations: [CommandDefinition]
    let admission: InteractionAcknowledgementAdmission
    let sink: InteractionResponseSink
    let accountedState: AccountedState
}

/// Final owned counters must be zero even though the OS allocator may retain process pages.
struct CleanupSnapshot: Codable, Sendable {
    let activeHandlers: Int
    let activeAcknowledgements: Int
    let acknowledgementBytes: Int
    let activeWorkers: Int
}

/// At most 121 monotonic process snapshots support a finite sustained-handler observation.
struct MemoryObservation: Codable, Sendable {
    let elapsedSeconds: Double
    let completedInvocations: Int
    let process: ProcessSample
}

/// One independent path's measurements; direct/DSL order and common process contamination are explicit.
struct WorkloadMeasurement: Codable, Sendable {
    let mode: String
    let handlerCount: Int
    let invocations: Int
    let planCompilationMilliseconds: Double
    let durationSeconds: Double
    let invocationsPerSecond: Double
    let latency: LatencySummary
    let schemaBuilds: Int
    let schemasAfterInvocations: Int
    let counters: CounterSnapshot
    let accountedState: AccountedState
    let beforePlan: ProcessSample
    let afterPlan: ProcessSample
    let afterInvocations: ProcessSample
    let afterCleanup: ProcessSample
    let memoryObservations: [MemoryObservation]
    let cleanup: CleanupSnapshot
    let implicitHydrationRequests: Int
    let implicitRegistrationRequests: Int
    let functionalGatesPassed: Bool
}

/// Independent offline runner composed from existing router, decoder, DSL lowering and response owners.
enum RuntimeBenchmark {
    /// Builds paired catalogs with equivalent registrations and runtime behavior, without invoking handlers.
    /// - Parameters:
    ///   - mode: Exact `direct` or `dsl` selection.
    ///   - handlerCount: One validated declared population, at most 1,000.
    ///   - configuration: Previously validated finite workload dimensions.
    ///   - counters: Constant-size invocation/callback instrumentation shared with the finite worker cohort.
    /// - Returns: Bounded inert routes, fixtures and independently shared acknowledgement authority.
    /// - Throws: Invalid mode/configuration, original authoring/model validation or compilation failure.
    static func makePlan(mode: String, handlerCount: Int, configuration: BenchmarkConfiguration,
        counters: BenchmarkCounters) throws -> RuntimePlan {
        try configuration.validate()
        guard ["direct", "dsl"].contains(mode), configuration.handlerCounts.contains(handlerCount) else {
            throw BenchmarkError.invalidConfiguration
        }
        let clock = ContinuousClock()
        let compileStart = clock.now
        let payload = String(repeating: "x", count: configuration.payloadBytes)
        var definitions: [CommandDefinition] = [], routes: [CommandRoute] = []
        var contributions: [SlashCommand<BenchmarkHandler>] = []
        for index in 0..<handlerCount {
            let handler = BenchmarkHandler(name: "bench\(index)", counters: counters)
            if mode == "dsl" {
                contributions.append(try SlashCommand(id: "handler\(index)", handler: handler,
                    source: .init(fileID: "DiscordDSLBenchmarks", line: 1)))
            } else {
                let schema = try BenchmarkArguments.schema
                definitions.append(try CommandDefinition.slash(name: handler.name, description: handler.command.description) { schema.options })
                routes.append(CommandRoute(key: try .command(name: handler.name), prepare: { context in
                    try Task.checkCancellation()
                    guard context.interaction.type.knownValue == .applicationCommand,
                          case .value(.command(let data)) = context.interaction.data,
                          data.name == handler.name, data.type.knownValue == .chatInput,
                          case .value(let options) = data.options else { throw BenchmarkError.functionalGate }
                    let arguments = try schema.decode(options: options, resolved: data.resolved, commandName: handler.name)
                    try Task.checkCancellation()
                    return { try await handler.execute(context, arguments: arguments) }
                }))
            }
        }
        var descriptionBytes = 0
        if mode == "dsl" {
            let compiled = try CommandCompilation.compile(Module(id: "benchmark") { contributions },
                limits: .init(maxModules: 1, maxDepth: 8, maxDeclarations: handlerCount,
                    maxTextBytes: 8 * 1_024 * 1_024, maxStructuralNodes: handlerCount + 8))
            definitions = compiled.definitions
            routes = compiled.routes
            descriptionBytes = compiled.description.textBytes
        }
        let registrationBytes = try definitions.reduce(0) { try $0 + $1.request.jsonValue().serialized().count }
        let routeBytes = try routes.reduce(0) { try $0 + $1.key.metadata.serialized().count }
        let router = try CommandRouter(routes: routes, maximumRoutes: handlerCount,
            maximumRouteTextBytes: max(1, routeBytes), maximumConcurrentHandlers: configuration.concurrency)
        let compilationMilliseconds = seconds(compileStart.duration(to: clock.now)) * 1_000
        var interactions: [Interaction] = [], interactionBytes = 0
        for index in 0..<handlerCount {
            let bytes = try JSONValue.object([
                "id": .string(String(index + 1)), "application_id": .string("2"),
                "type": .number(JSONNumber(rawValue: "2")), "token": .string("synthetic-offline"),
                "version": .number(JSONNumber(rawValue: "1")), "app_permissions": .string("0"),
                "entitlements": .array([]), "authorizing_integration_owners": .object([:]),
                "attachment_size_limit": .number(JSONNumber(rawValue: "1024")),
                "data": .object(["id": .string(String(index + 1)), "type": .number(JSONNumber(rawValue: "1")),
                    "name": .string("bench\(index)"), "options": .array([.object([
                        "name": .string("payload"), "type": .number(JSONNumber(rawValue: "3")), "value": .string(payload),
                    ])])]),
            ]).serialized()
            interactionBytes += bytes.count
            interactions.append(try Interaction(data: bytes))
        }
        let expected = try InteractionResponse.message(InteractionMessageCreate(content: .value(payload)))
            .jsonValue(interactionType: .applicationCommand)
        let admission = try InteractionAcknowledgementAdmission(maximumConcurrent: configuration.concurrency,
            maximumBytes: configuration.concurrency * 2_048)
        let sink = InteractionResponseSink(initial: { response, timeout in
            guard timeout > .zero, try response.jsonValue(interactionType: .applicationCommand) == expected else {
                throw BenchmarkError.functionalGate
            }
            counters.callback()
        })
        return RuntimePlan(compilationMilliseconds: compilationMilliseconds, router: router, interactions: interactions, registrations: definitions, admission: admission,
            sink: sink, accountedState: .init(declaredHandlers: handlerCount, retainedSchemas: handlerCount,
                fixedInteractionCount: interactions.count, fixedInteractionJSONBytes: interactionBytes,
                registrationJSONBytes: registrationBytes, routeMetadataJSONBytes: routeBytes,
                planDescriptionTextBytes: descriptionBytes, maximumWorkers: configuration.concurrency,
                maximumLatencySamples: configuration.sampleLimit, maximumMemorySamples: 121,
                maximumPayloadBytes: configuration.payloadBytes, maximumActualInvocations: BenchmarkConfiguration.maximumInvocations))
    }

    /// Executes one real route with a fresh exactly-once response owner and fixed-population input snapshot.
    /// - Parameters:
    ///   - plan: Shared fixed router/admission population, with no remote request provider installed.
    ///   - index: Deterministic round-robin fixture index, bounded by the declared population via modulo.
    /// - Throws: Cancellation, route/model failure or a callback ownership/parity violation.
    static func invoke(_ plan: RuntimePlan, index: Int) async throws {
        let interaction = plan.interactions[index % plan.interactions.count]
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .http,
            clock: InteractionClock(ContinuousClock()), sink: plan.sink, admission: plan.admission)
        let context = try InteractionContext(interaction: interaction, deliveryMode: .http, responder: responder)
        guard try await plan.router.route(context), await responder.snapshot() == .acknowledged(.channelMessageWithSource) else {
            throw BenchmarkError.functionalGate
        }
    }

    /// Runs one bounded cohort round, retaining at most the configured latency prefix and awaiting every child.
    /// - Parameters:
    ///   - plan: Shared immutable workload plan and finite aggregate authorities.
    ///   - start: Number of prior successful invocations, used for deterministic fixture/sample selection.
    ///   - count: Positive finite number of invocations assigned across at most configured concurrency workers.
    ///   - configuration: Explicit common payload, concurrency and sample bounds.
    ///   - counters: Synchronized worker and handler instrumentation; exit cleanup is unconditional.
    /// - Returns: At most sampleLimit prefix measurements across all workers and all rounds.
    /// - Throws: The first invocation/cancellation failure after group cancellation and child joining.
    static func runRound(_ plan: RuntimePlan, start: Int, count: Int, configuration: BenchmarkConfiguration,
        counters: BenchmarkCounters) async throws -> [Double] {
        try await withThrowingTaskGroup(of: [Double].self) { group in
            for worker in 0..<min(configuration.concurrency, count) {
                group.addTask {
                    counters.enterWorker()
                    defer { counters.leaveWorker() }
                    let clock = ContinuousClock()
                    var samples: [Double] = []
                    for offset in stride(from: worker, to: count, by: configuration.concurrency) {
                        try Task.checkCancellation()
                        let index = start + offset
                        if index < configuration.sampleLimit {
                            let begin = clock.now
                            try await invoke(plan, index: index)
                            samples.append(seconds(begin.duration(to: clock.now)) * 1_000)
                        } else { try await invoke(plan, index: index) }
                    }
                    return samples
                }
            }
            var samples: [Double] = []
            for try await result in group { samples.append(contentsOf: result) }
            return samples
        }
    }

    /// Measures one direct or DSL path with bounded prefix quantiles and fixed-population sustained execution.
    /// - Parameters:
    ///   - mode: Exact direct or DSL path; both use the same handler, schema decoder and response owner.
    ///   - handlerCount: One declared fixed working set from the validated matrix.
    ///   - configuration: Invocation floor, optional duration floor and finite payload/cohort/sample dimensions.
    /// - Returns: Reproducible measurements and successful hard gates; all owned counters are zero on return.
    /// - Throws: Invalid configuration, underlying route failure, cleanup/schema gate failure or invocation ceiling.
    static func run(mode: String, handlerCount: Int, configuration: BenchmarkConfiguration) async throws -> WorkloadMeasurement {
        try configuration.validate()
        let counters = BenchmarkCounters(), clock = ContinuousClock()
        let initialSchemas = BenchmarkArguments.captures.snapshot().schemas
        let before = ProcessSample.capture()
        var plan: RuntimePlan? = try makePlan(mode: mode, handlerCount: handlerCount, configuration: configuration, counters: counters)
        let compileMilliseconds = plan!.compilationMilliseconds
        let schemaBuilds = BenchmarkArguments.captures.snapshot().schemas - initialSchemas
        let afterPlan = ProcessSample.capture(), start = clock.now
        var total = 0, latencies: [Double] = [], observations: [MemoryObservation] = []
        let observationInterval = Double(max(1, configuration.minimumDurationSeconds / 120))
        var nextObservation = 0.0
        while total < configuration.invocations || seconds(start.duration(to: clock.now)) < Double(configuration.minimumDurationSeconds) {
            guard total < BenchmarkConfiguration.maximumInvocations else { throw BenchmarkError.invocationCeiling }
            let remaining = total < configuration.invocations ? configuration.invocations - total : 8_192
            let count = min(8_192, remaining, BenchmarkConfiguration.maximumInvocations - total)
            latencies.append(contentsOf: try await runRound(plan!, start: total, count: count, configuration: configuration, counters: counters))
            total += count
            let elapsed = seconds(start.duration(to: clock.now))
            if elapsed >= nextObservation, observations.count < 121 {
                observations.append(.init(elapsedSeconds: elapsed, completedInvocations: total, process: .capture()))
                nextObservation = elapsed + observationInterval
            }
        }
        let duration = seconds(start.duration(to: clock.now)), afterInvocations = ProcessSample.capture()
        let acknowledgement = await plan!.admission.snapshot()
        let activeHandlers = await plan!.router.activeHandlerCount
        let snapshot = counters.snapshot()
        let finalSchemas = BenchmarkArguments.captures.snapshot().schemas - initialSchemas
        let cleanup = CleanupSnapshot(activeHandlers: activeHandlers, activeAcknowledgements: acknowledgement.activeCount,
            acknowledgementBytes: acknowledgement.encodedBytes, activeWorkers: snapshot.activeWorkers)
        let accounting = plan!.accountedState
        guard schemaBuilds == handlerCount, finalSchemas == schemaBuilds, snapshot.handlers == total,
              snapshot.callbacks == total, snapshot.peakWorkers <= configuration.concurrency,
              latencies.count <= configuration.sampleLimit, observations.count <= 121,
              activeHandlers == 0, acknowledgement.activeCount == 0, acknowledgement.encodedBytes == 0,
              snapshot.activeWorkers == 0 else { throw BenchmarkError.functionalGate }
        plan = nil
        return WorkloadMeasurement(mode: mode, handlerCount: handlerCount, invocations: total,
            planCompilationMilliseconds: compileMilliseconds, durationSeconds: duration,
            invocationsPerSecond: Double(total) / max(duration, .leastNonzeroMagnitude), latency: .summarize(latencies),
            schemaBuilds: schemaBuilds, schemasAfterInvocations: finalSchemas, counters: snapshot, accountedState: accounting,
            beforePlan: before, afterPlan: afterPlan, afterInvocations: afterInvocations, afterCleanup: .capture(),
            memoryObservations: observations, cleanup: cleanup, implicitHydrationRequests: 0,
            implicitRegistrationRequests: 0, functionalGatesPassed: true)
    }
}
