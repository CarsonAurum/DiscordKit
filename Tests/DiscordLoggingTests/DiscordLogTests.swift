// File: Tests/DiscordLoggingTests/DiscordLogTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Testing
import DiscordLogging
import DiscordTestSupport

/// Exercises scoped native SwiftLog injection without mutating process-global state.
struct DiscordLogTests {
    /// Verifies labels, metadata, semantic severity levels and threshold ownership.
    @Test func nativeLevelsAndValueSemantics() {
        let recorder = LogRecorder()
        DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let logger = DiscordLog.makeLogger("test")
            var copy = logger
            copy.logLevel = .error
            copy[metadataKey: "copy"] = "yes"
            for level in Logger.Level.allCases {
                logger.log(level: level, "event", metadata: ["dk.event": "test.event"])
            }
            copy.debug("filtered")
            copy.error("copy")
            #expect(logger.logLevel == .trace)
            #expect(logger[metadataKey: "copy"] == nil)
        }
        #expect(recorder.entries.count == 8)
        #expect(recorder.entries.prefix(7).map(\.level) == Logger.Level.allCases)
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.test" && $0.metadata["dk.subsystem"] == "test" })
    }

    /// Ensures structured children inherit factories while nested overrides restore them.
    @Test func scopedFactoriesAndConcurrency() async {
        let outer = LogRecorder()
        let inner = LogRecorder()
        await DiscordLog.$loggerFactory.withValue({ outer.makeLogger($0) }) {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask { DiscordLog.makeLogger("child").trace("child") }
                }
            }
            DiscordLog.$loggerFactory.withValue({ inner.makeLogger($0) }) {
                DiscordLog.makeLogger("inner").debug("inner")
            }
            DiscordLog.makeLogger("outer").debug("restored")
        }
        #expect(outer.entries.count == 17)
        #expect(inner.entries.map(\.label) == ["discordkit.inner"])
    }

    /// Checks finite recording and SwiftLog's lazy metadata/message evaluation.
    @Test func boundedCaptureAndLazyFiltering() {
        let recorder = LogRecorder(maximumEntries: 1)
        var logger = recorder.makeLogger("test")
        logger.logLevel = .error
        var evaluated = false
        logger.trace("\({ evaluated = true; return "secret" }())")
        #expect(!evaluated)
        logger.error("one")
        logger.critical("two")
        #expect(recorder.entries.map(\.message) == ["one"])
    }

    /// Resolves nested overrides at exact dotted boundaries and preserves factory thresholds
    /// outside the scope, including overlapping, empty, unknown and similarly named categories.
    @Test func hierarchicalThresholds() {
        let policy = DiscordLogConfiguration(defaultLevel: .warning, overrides: [
            "": .critical, "http": .debug, "http.execution": .trace,
            "http.execution.decode": .error,
        ])
        #expect(DiscordLogConfiguration().level(for: "voice") == .info)
        #expect(policy.level(for: "http") == .debug)
        #expect(policy.level(for: "http.ratelimit") == .debug)
        #expect(policy.level(for: "http.execution.send") == .trace)
        #expect(policy.level(for: "http.execution.decode") == .error)
        #expect(policy.level(for: "http.execution2") == .debug)
        #expect(policy.level(for: "http2") == .warning)
        #expect(policy.level(for: "") == .warning)
        let recorder = LogRecorder()
        DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            DiscordLog.$configuration.withValue(policy) {
                DiscordLog.makeLogger("http.execution").trace("detailed")
                DiscordLog.makeLogger("http.ratelimit").trace("filtered")
                DiscordLog.makeLogger("voice").info("filtered")
                DiscordLog.makeLogger("voice").warning("retained")
            }
            #expect(DiscordLog.makeLogger("voice").logLevel == .trace)
        }
        #expect(recorder.entries.map(\.message) == ["detailed", "retained"])
        #expect(recorder.entries.first?.metadata["dk.module"] == "http")
    }

    /// Confirms scoped context overrides factory metadata, cannot mislabel the component,
    /// is copied into logger values and is restored after nested scopes finish.
    @Test func scopedContextValueSemantics() {
        let recorder = LogRecorder()
        DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            DiscordLog.$context.withValue(["deployment": "outer", "dk.subsystem": "invalid"]) {
                let outer = DiscordLog.makeLogger("test.scope")
                DiscordLog.$context.withValue(["deployment": "inner"]) {
                    DiscordLog.makeLogger("test.scope").info("inner")
                    outer.info("saved outer")
                }
                DiscordLog.makeLogger("test.scope").notice("restored")
            }
            DiscordLog.makeLogger("test.scope").debug("outside")
        }
        #expect(recorder.entries.map { $0.metadata["deployment"] } == ["inner", "outer", "outer", nil])
        #expect(recorder.entries.allSatisfy { $0.metadata["dk.subsystem"] == "test.scope" })
    }

    /// Verifies unchanged return values, exactly one terminal event, finite timing,
    /// unchanged errors and cancellation categorization without disclosing error text.
    @Test func synchronousOperationOutcomes() throws {
        let recorder = LogRecorder()
        try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let answer = DiscordLog.withOperation("test.operation", event: "test.success") { 42 }
            #expect(answer == 42)
            do {
                try DiscordLog.withOperation("test.operation", event: "test.failure") {
                    throw SensitiveFailure()
                }
                Issue.record("Expected the original error")
            } catch is SensitiveFailure {}
            #expect(throws: CancellationError.self) {
                try DiscordLog.withOperation("test.operation", event: "test.cancel") { throw CancellationError() }
            }
            #expect(DiscordLog.context.isEmpty)
        }
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"] } == [
            "test.success.started", "test.success.completed", "test.failure.started",
            "test.failure.failed", "test.cancel.started", "test.cancel.cancelled",
        ])
        #expect(recorder.entries.map(\.level) == [.trace, .trace, .trace, .debug, .trace, .trace])
        for entry in recorder.entries where entry.metadata["dk.outcome"] != nil {
            let duration = try #require(entry.metadata["dk.duration_ns"])
            #expect(UInt64(duration.description) != nil)
        }
        #expect(!String(describing: recorder.entries).contains("sensitive-error-marker"))
    }

    /// Confirms nested asynchronous scopes preserve trace identity, distinguish concurrent
    /// child spans, restore parent context and remain callable from an isolated actor.
    @Test func asynchronousNestedOperations() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await DiscordLog.withOperation("test.parent", event: "test.parent") {
                let parentSpan = try #require(DiscordLog.context["dk.span_id"])
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<4 {
                        group.addTask {
                            await DiscordLog.withOperation("test.child", event: "test.child") {
                                await Task.yield()
                                #expect(DiscordLog.context["dk.parent_span_id"] == parentSpan)
                                DiscordLog.makeLogger("test.leaf").trace("child step")
                            }
                        }
                    }
                }
                #expect(DiscordLog.context["dk.span_id"] == parentSpan)
                await LoggingActor().run()
            }
            #expect(DiscordLog.context.isEmpty)
        }
        let entries = recorder.entries
        #expect(entries.count == 16)
        #expect(Set(entries.compactMap { $0.metadata["dk.trace_id"]?.description }).count == 1)
        let starts = entries.filter { $0.metadata["dk.event"]?.description.hasSuffix(".started") == true }
        #expect(Set(starts.compactMap { $0.metadata["dk.span_id"]?.description }).count == 6)
        #expect(entries.first?.metadata["dk.parent_span_id"] == nil)
    }

    /// Exercises asynchronous thrown errors and cancellation without wrapper replacement.
    @Test func asynchronousFailureAndCancellation() async {
        let recorder = LogRecorder()
        await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            do {
                try await DiscordLog.withOperation("test.async", event: "test.async.failure") {
                    await Task.yield()
                    throw SensitiveFailure()
                }
                Issue.record("Expected the original error")
            } catch is SensitiveFailure {} catch { Issue.record("Unexpected error type") }
            do {
                try await DiscordLog.withOperation("test.async", event: "test.async.cancel") {
                    await Task.yield()
                    throw CancellationError()
                }
            } catch is CancellationError {} catch { Issue.record("Unexpected error type") }
        }
        #expect(recorder.entries.compactMap { $0.metadata["dk.outcome"] } == ["failure", "cancelled"])
        #expect(!String(describing: recorder.entries).contains("sensitive-error-marker"))
    }
}

/// Error carrying a marker which must never be interpolated into diagnostics.
private struct SensitiveFailure: Error, CustomStringConvertible {
    /// Returns a sentinel which the logging wrapper must never inspect or render.
    var description: String { "sensitive-error-marker" }
}

/// Exercises inherited actor isolation without Sendable workarounds or detached tasks.
private actor LoggingActor {
    private var count = 0

    /// Mutates isolated state across a suspension within an operation scope.
    func run() async {
        await DiscordLog.withOperation("test.actor", event: "test.actor") {
            count += 1
            await Task.yield()
            #expect(count == 1)
        }
    }
}
