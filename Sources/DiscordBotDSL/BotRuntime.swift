// File: Sources/DiscordBotDSL/BotRuntime.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordClient
import DiscordGateway
import DiscordTransport

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
    /// Safe per-entry provenance in primary/additional order, bounded to three observations.
    public let diagnostics: [BotFailureDiagnostic]

    /// Retains the finite failures produced by this runtime's fixed child set.
    /// - Parameters:
    ///   - primary: First observed non-cancellation failure.
    ///   - additional: Later child failures, in observation order; at most two are retained.
    ///   - diagnostics: Original-boundary safe projections, default empty for uncaptured errors.
    internal init(primary: any Error, additional: [any Error], diagnostics: [BotFailureDiagnostic] = []) {
        self.primary = primary
        self.additional = Array(additional.prefix(2))
        self.diagnostics = Array(diagnostics.prefix(3))
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
    private let failureObserver: BotFailureObserver?
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
    ///   - failureObserver: Optional synchronous nonthrowing safe diagnostic observer. Receives no original
    ///     error or interaction; the observer must be finite, fast and concurrency-safe.
    /// - Throws: `EventCompilationDiagnostic.missingIntents` when a catalog was compiled for a
    ///   broader intent selection than the actual client. No partial ownership escapes on failure.
    public init<C, L>(client: DiscordClient<C, L>, events: CompiledEvents,
        handlerConfiguration: GatewayEventHandlerConfiguration,
        handlerAuthority: GatewayHandlerAuthority? = nil,
        interactions: GatewayInteractionAdapter<C>? = nil, failureObserver: BotFailureObserver? = nil) throws {
        let missing = events.requiredIntents.subtracting(client.configuration.intents)
        guard missing.isEmpty else {
            throw EventCompilationDiagnostic(code: .missingIntents,
                source: .init(fileID: "<host>", line: 0, column: 0), missingIntents: missing)
        }
        hub = client.events
        self.events = events
        configuration = handlerConfiguration
        authority = handlerAuthority
        self.failureObserver = failureObserver
        clientRun = {
            try Task.checkCancellation()
            do {
                try await RuntimeCleanupFailureScope.$capturesFailures.withValue(true) { try await client.run() }
            }
            catch ClientFailure.stopped where Task.isCancelled {
                // Stop can close an idle client before this child crosses its actor hop.
                // Only that cancelled startup race is cancellation, rather than a new failure.
                throw CancellationError()
            }
        }
        clientShutdown = { await client.shutdown() }
        if let interactions {
            prepareInteractions = { try await interactions.prepare(client: client) }
            runInteractions = { try await interactions.run(reportingStage: true) }
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
    /// Diagnostics inherit one ephemeral operation trace through setup, child execution and cleanup.
    /// - Throws: `alreadyRunning` for concurrent invocation, `stopped` after any terminal lifetime,
    ///   cancellation, original setup/child errors, or `BotRuntimeFailures` for multiple failures.
    ///   Callbacks/transports must cooperate with cancellation; effects are never rolled back/replayed.
    public func run() async throws {
        guard phase == .idle else {
            throw phase == .stopped || phase == .failed ? BotRuntimeFailure.stopped : .alreadyRunning
        }
        try await DiscordLog.withOperation("bot.lifecycle", event: "bot_dsl.runtime.operation") {
            phase = .starting
            DiscordLog.makeLogger("bot.lifecycle").info("Bot runtime started", metadata: ["dk.event": "bot_dsl.runtime.started"])
            let task = Task { try await self.execute() }
            completion = task
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
        }
    }

    /// Requests an idempotent stop without joining the caller's own callback.
    /// Safe from event/command handlers. Before `run`, permanently stops the runtime and starts
    /// client cleanup. The application owner must still await `run` or `shutdown` to join work.
    public func requestStop() {
        guard phase != .stopped && phase != .failed else { return }
        stopRequested = true
        DiscordLog.makeLogger("bot.lifecycle").debug("Bot runtime stop requested", metadata: ["dk.event": "bot_dsl.runtime.stop_requested", "dk.phase": .string(phase.rawValue)])
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
        DiscordLog.makeLogger("bot.lifecycle").trace("Bot runtime shutdown joined owner completion", metadata: ["dk.event": "bot_dsl.runtime.shutdown_joined"])
    }

    /// Closes inert ownership after a stop requested before subscription or client startup.
    /// All concurrent shutdown callers await this same task, including cancelled callers.
    private func closeBeforeRun() async {
        DiscordLog.makeLogger("bot.lifecycle").trace("Closing bot ownership before startup", metadata: ["dk.event": "bot_dsl.runtime.closing_before_run"])
        await cancelInteractions?()
        await clientShutdown()
        stop.continuation.finish()
        phase = .stopped
        DiscordLog.makeLogger("bot.lifecycle").info("Bot runtime stopped before startup", metadata: ["dk.event": "bot_dsl.runtime.stopped_before_run"])
    }

    /// Performs bounded setup and supervises a fixed set of result-reporting children.
    /// - Throws: Original non-cancellation errors (aggregated if necessary), or owner cancellation,
    ///   only after every subscription, client and structured child has completed cleanup.
    private func execute() async throws {
        var pipelines: GatewayEventPipelines?
        var failures: [any Error] = []
        var diagnostics: [BotFailureDiagnostic] = []
        var cancelled = false
        do {
            try Task.checkCancellation()
            if !stopRequested {
                DiscordLog.makeLogger("bot.lifecycle").trace("Preparing trusted Gateway interaction admission", metadata: ["dk.event": "bot_dsl.runtime.interactions_preparing", "dk.enabled": .stringConvertible(prepareInteractions != nil)])
                try await prepareInteractions?()
                DiscordLog.makeLogger("bot.lifecycle").trace("Trusted interaction preparation completed", metadata: ["dk.event": "bot_dsl.runtime.interactions_prepared"])
            }
            if !stopRequested {
                pipelines = try await events.subscribe(to: hub, configuration: configuration, authority: authority)
            }
            try Task.checkCancellation()
            if !stopRequested {
                phase = .running
                DiscordLog.makeLogger("bot.lifecycle").info("Bot runtime subscriptions prepared", metadata: ["dk.event": "bot_dsl.runtime.running"])
                let prepared = pipelines
                await withTaskGroup(of: ChildResult.self) { children in
                    DiscordLog.makeLogger("bot.lifecycle").trace("Launching supervised bot children after subscriptions", metadata: ["dk.event": "bot_dsl.runtime.children_starting"])
                    children.addTask { await Self.result(stage: .client, self.clientRun) }
                    if let prepared, prepared.subscriptionCount > 0 {
                        children.addTask { await Self.result(stage: .events) { try await prepared.run() } }
                    }
                    if let runInteractions {
                        children.addTask { await Self.result(stage: .interactions, runInteractions) }
                    }
                    children.addTask {
                        for await _ in self.stop.stream { break }
                        return ChildResult(stage: .cleanup, result: .success(()))
                    }
                    if let first = await children.next(), case .failure(let error) = first.result {
                        if Self.original(error) is CancellationError { cancelled = true }
                        else { collect(error, stage: first.stage, failures: &failures, diagnostics: &diagnostics) }
                    }
                    DiscordLog.makeLogger("bot.lifecycle").trace("Bot child completion observed; cancelling siblings", metadata: ["dk.event": "bot_dsl.runtime.children_cancelling"])
                    children.cancelAll()
                    await prepared?.cancel()
                    await cancelInteractions?()
                    await clientShutdown()
                    DiscordLog.makeLogger("bot.lifecycle").trace("Bot input owners closed; joining supervised children", metadata: ["dk.event": "bot_dsl.runtime.children_joining"])
                    while let result = await children.next() {
                        if case .failure(let error) = result.result, !(Self.original(error) is CancellationError) {
                            collect(error, stage: result.stage, failures: &failures, diagnostics: &diagnostics)
                        }
                    }
                    DiscordLog.makeLogger("bot.lifecycle").trace("Every supervised bot child joined", metadata: ["dk.event": "bot_dsl.runtime.children_joined"])
                }
            }
        } catch {
            if Self.original(error) is CancellationError { cancelled = true }
            else { collect(error, stage: .setup, failures: &failures, diagnostics: &diagnostics) }
        }
        // Setup may fail before a task group exists. These idempotent calls also cover that path.
        DiscordLog.makeLogger("bot.lifecycle").trace("Closing bot pipelines and client after setup or execution", metadata: ["dk.event": "bot_dsl.runtime.cleanup_started"])
        await pipelines?.cancel()
        await cancelInteractions?()
        await clientShutdown()
        DiscordLog.makeLogger("bot.lifecycle").trace("Bot pipeline and client cleanup completed", metadata: ["dk.event": "bot_dsl.runtime.cleanup_completed"])
        stop.continuation.finish()
        phase = failures.isEmpty ? .stopped : .failed
        if let first = failures.first {
            DiscordLog.makeLogger("bot.lifecycle").error("Bot runtime failed after cleanup", metadata: ["dk.event": "bot_dsl.runtime.failed", "dk.failures": .stringConvertible(failures.count)])
            if failures.count == 1 { throw first }
            throw BotRuntimeFailures(primary: first, additional: Array(failures.dropFirst()), diagnostics: diagnostics)
        }
        try Task.checkCancellation()
        if cancelled && !stopRequested {
            DiscordLog.makeLogger("bot.lifecycle").debug("Bot runtime cancelled", metadata: ["dk.event": "bot_dsl.runtime.cancelled"])
            throw CancellationError()
        }
        DiscordLog.makeLogger("bot.lifecycle").info("Bot runtime stopped", metadata: ["dk.event": "bot_dsl.runtime.stopped"])
    }

    /// An original child result paired with the exact supervised boundary that observed it.
    private struct ChildResult: Sendable {
        let stage: BotFailureStage
        let result: Result<Void, any Error>
    }

    /// Records safe individual evidence before throwing original failures after cleanup.
    /// - Parameters:
    ///   - error: Original child or internal operation-provenance carrier; never logged directly.
    ///   - stage: Observing supervised boundary, overridden only by captured operation provenance.
    ///   - failures: Original errors retained by this fixed child set for explicit application handling.
    ///   - diagnostics: Safe observations, bounded across the lifetime to at most three entries.
    private func collect(_ error: any Error, stage: BotFailureStage,
        failures: inout [any Error], diagnostics: inout [BotFailureDiagnostic]) {
        let original = Self.original(error)
        failures.append(original)
        if diagnostics.count < 3 {
            let diagnostic = BotFailureDiagnostic(classifying: error, stage: stage)
            diagnostics.append(diagnostic)
            var metadata = diagnostic.logMetadata
            metadata["dk.event"] = "bot_dsl.runtime.operation_failed"
            DiscordLog.makeLogger("bot.lifecycle").error("Bot runtime operation failed", metadata: metadata)
            failureObserver?(diagnostic)
        }
    }

    /// Removes only the package's fixed provenance carriers before public error handling.
    /// - Parameter error: One child error, optionally carrying exact interaction or cleanup provenance.
    /// - Returns: Original error; arbitrary injected values are never traversed or reflected.
    private nonisolated static func original(_ error: any Error) -> any Error {
        let operation = (error as? BotFailureObservationError)?.original ?? error
        return (operation as? RuntimeCleanupFailure)?.original ?? operation
    }

    /// Converts one owned child's terminal result without swallowing dependency failures.
    /// - Parameters:
    ///   - stage: Exact supervised child boundary; never guessed from an arbitrary error.
    ///   - operation: Cooperative client or pipeline work; never retried.
    /// - Returns: Original success/failure and stage for finite aggregation after sibling cleanup.
    private nonisolated static func result(stage: BotFailureStage,
        _ operation: @Sendable () async throws -> Void) async -> ChildResult {
        DiscordLog.makeLogger("bot.lifecycle").trace("Supervised bot child entered", metadata: ["dk.event": "bot_dsl.runtime.child_entered", "dk.stage": .string(stage.rawValue)])
        defer { DiscordLog.makeLogger("bot.lifecycle").trace("Supervised bot child exited", metadata: ["dk.event": "bot_dsl.runtime.child_exited", "dk.stage": .string(stage.rawValue)]) }
        do { try await operation(); return ChildResult(stage: stage, result: .success(())) }
        catch { return ChildResult(stage: stage, result: .failure(error)) }
    }
}
