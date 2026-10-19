import DiscordClient
import DiscordGateway

/// Single-use application lifetime, independent of individual shard reconnect states.
public enum BotRuntimePhase: String, Sendable {
    case idle, starting, running, stopping, stopped, failed
}

/// Closed lifecycle admission failures without credentials or submitted event data.
public enum BotRuntimeFailure: Error, Sendable, Equatable {
    case alreadyRunning, stopped
}

/// Multiple original child failures retained after complete supervised cleanup.
/// Explicit error access is for application handling; ordinary diagnostics redact dependency text.
public struct BotRuntimeFailures: Error, Sendable, CustomStringConvertible, CustomReflectable {
    public let primary: any Error
    public let additional: [any Error]

    /// Retains the finite failures produced by this runtime's fixed child set.
    /// - Parameters:
    ///   - primary: First observed non-cancellation failure.
    ///   - additional: Later child failures, in observation order; at most two are retained.
    internal init(primary: any Error, additional: [any Error]) {
        self.primary = primary
        self.additional = Array(additional.prefix(2))
    }

    /// Conceals arbitrary dependency diagnostics while allowing explicit error inspection.
    public var description: String { "BotRuntimeFailures(redacted)" }
    /// Prevents reflection from traversing potentially credential-bearing errors.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Owns one existing client and its declared bounded event/interaction pipelines.
/// Construction starts no tasks, subscriptions, registration, discovery or I/O. All
/// authorities remain the explicitly injected client/handler/REST authorities; modules
/// never receive a private replacement budget. Raw shard ingestion stays with the client.
public actor BotRuntime {
    public private(set) var phase: BotRuntimePhase = .idle
    private let hub: GatewayEventHub
    private let events: CompiledEvents
    private let configuration: GatewayEventHandlerConfiguration
    private let authority: GatewayHandlerAuthority?
    private let clientRun: @Sendable () async throws -> Void
    private let clientShutdown: @Sendable () async -> Void
    private let prepareInteractions: (@Sendable () async throws -> Void)?
    private let runInteractions: (@Sendable () async throws -> Void)?
    private let cancelInteractions: (@Sendable () async -> Void)?
    private let stop = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var stopRequested = false
    private var completion: Task<Void, any Error>?

    /// Binds an explicitly built client and inert catalogs without acquiring runtime resources.
    /// - Parameters:
    ///   - client: Single-use client exclusively owned by this runtime; do not run/shut it down
    ///     elsewhere. Its credential, startup, lease, event and aggregate authorities stay shared.
    ///   - events: Validated event declarations. Required intents must fit the actual client selection.
    ///   - handlerConfiguration: Finite per-group dispatch/task/event/byte bounds.
    ///   - handlerAuthority: Optional shared aggregate callback admission across all host pipelines.
    ///   - interactions: Optional bounded trusted Gateway command bridge, using HTTP responses and
    ///     the same host's explicit services/clock. No command synchronization is implicit.
    /// - Throws: `EventCompilationDiagnostic.missingIntents` when a catalog was compiled for a
    ///   broader intent selection than the actual client. No partial ownership escapes on failure.
    public init<C, L>(client: DiscordClient<C, L>, events: CompiledEvents,
        handlerConfiguration: GatewayEventHandlerConfiguration,
        handlerAuthority: GatewayHandlerAuthority? = nil,
        interactions: GatewayInteractionAdapter<C>? = nil) throws {
        let missing = events.requiredIntents.subtracting(client.configuration.intents)
        guard missing.isEmpty else {
            throw EventCompilationDiagnostic(code: .missingIntents,
                source: .init(fileID: "<host>", line: 0, column: 0), missingIntents: missing)
        }
        hub = client.events
        self.events = events
        configuration = handlerConfiguration
        authority = handlerAuthority
        clientRun = {
            try Task.checkCancellation()
            do { try await client.run() }
            catch ClientFailure.stopped where Task.isCancelled {
                // Stop can close an idle client before this child crosses its actor hop.
                // Only that cancelled startup race is cancellation, rather than a new failure.
                throw CancellationError()
            }
        }
        clientShutdown = { await client.shutdown() }
        if let interactions {
            prepareInteractions = { try await interactions.prepare(client: client) }
            runInteractions = { try await interactions.run() }
            cancelInteractions = { await interactions.cancel() }
        } else {
            prepareInteractions = nil
            runInteractions = nil
            cancelInteractions = nil
        }
    }

    /// Acquires all subscriptions before starting the client, then supervises every declared child.
    /// The first child completion/failure or stop signal cancels siblings, shuts down the client and
    /// joins all owned work. Handler/lease-release failures survive cancellation during cleanup.
    /// - Throws: `alreadyRunning` for concurrent invocation, `stopped` after any terminal lifetime,
    ///   cancellation, original setup/child errors, or `BotRuntimeFailures` for multiple failures.
    ///   Callbacks/transports must cooperate with cancellation; effects are never rolled back/replayed.
    public func run() async throws {
        guard phase == .idle else {
            throw phase == .stopped || phase == .failed ? BotRuntimeFailure.stopped : .alreadyRunning
        }
        phase = .starting
        let task = Task { try await self.execute() }
        completion = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    /// Requests an idempotent stop without joining the caller's own callback.
    /// Safe from event/command handlers. Before `run`, permanently stops the runtime and starts
    /// client cleanup. The application owner must still await `run` or `shutdown` to join work.
    public func requestStop() {
        guard phase != .stopped && phase != .failed else { return }
        stopRequested = true
        if phase == .idle {
            phase = .stopping
            completion = Task { await self.closeBeforeRun() }
        } else {
            phase = .stopping
            stop.continuation.yield(())
        }
    }

    /// Requests stop and joins the shared completion even when this particular waiter is cancelled.
    /// Repeated/concurrent waiters observe the same terminal result. Handlers must use `requestStop`
    /// instead: joining from an owned callback would wait for that same callback to return.
    /// - Throws: The original owning run's terminal error, including lease-release failures. A
    ///   cancelled shutdown waiter does not cancel shared cleanup or hide its result.
    public func shutdown() async throws {
        requestStop()
        try await completion?.value
    }

    /// Closes inert ownership after a stop requested before subscription or client startup.
    /// All concurrent shutdown callers await this same task, including cancelled callers.
    private func closeBeforeRun() async {
        await cancelInteractions?()
        await clientShutdown()
        stop.continuation.finish()
        phase = .stopped
    }

    /// Performs bounded setup and supervises a fixed set of result-reporting children.
    /// - Throws: Original non-cancellation errors (aggregated if necessary), or owner cancellation,
    ///   only after every subscription, client and structured child has completed cleanup.
    private func execute() async throws {
        var pipelines: GatewayEventPipelines?
        var failures: [any Error] = []
        var cancelled = false
        do {
            try Task.checkCancellation()
            if !stopRequested { try await prepareInteractions?() }
            if !stopRequested {
                pipelines = try await events.subscribe(to: hub, configuration: configuration, authority: authority)
            }
            try Task.checkCancellation()
            if !stopRequested {
                phase = .running
                let prepared = pipelines
                await withTaskGroup(of: Result<Void, any Error>.self) { children in
                    children.addTask { await Self.result(self.clientRun) }
                    if let prepared, prepared.subscriptionCount > 0 {
                        children.addTask { await Self.result { try await prepared.run() } }
                    }
                    if let runInteractions {
                        children.addTask { await Self.result(runInteractions) }
                    }
                    children.addTask {
                        for await _ in self.stop.stream { break }
                        return .success(())
                    }
                    if let first = await children.next(), case .failure(let error) = first {
                        if error is CancellationError { cancelled = true }
                        else { failures.append(error) }
                    }
                    children.cancelAll()
                    await prepared?.cancel()
                    await cancelInteractions?()
                    await clientShutdown()
                    while let result = await children.next() {
                        if case .failure(let error) = result, !(error is CancellationError) {
                            failures.append(error)
                        }
                    }
                }
            }
        } catch {
            if error is CancellationError { cancelled = true }
            else { failures.append(error) }
        }
        // Setup may fail before a task group exists. These idempotent calls also cover that path.
        await pipelines?.cancel()
        await cancelInteractions?()
        await clientShutdown()
        stop.continuation.finish()
        phase = failures.isEmpty ? .stopped : .failed
        if let first = failures.first {
            if failures.count == 1 { throw first }
            throw BotRuntimeFailures(primary: first, additional: Array(failures.dropFirst()))
        }
        try Task.checkCancellation()
        if cancelled && !stopRequested { throw CancellationError() }
    }

    /// Converts one owned child's terminal result without swallowing dependency failures.
    /// - Parameter operation: Cooperative client or pipeline work; never retried.
    /// - Returns: Original success/failure for bounded aggregation after sibling cleanup.
    private nonisolated static func result(_ operation: @Sendable () async throws -> Void) async -> Result<Void, any Error> {
        do { try await operation(); return .success(()) }
        catch { return .failure(error) }
    }
}
