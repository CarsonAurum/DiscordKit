// File: Tests/DiscordDSLTests/PolicyLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordDSL
import DiscordLogging
import DiscordTestSupport
import Testing

/// Confirms native diagnostics preserve pure authoring and never inspect generic invocation values.
@Suite struct PolicyLoggingTests {
    /// Construction, validation and empty compilation emit nothing; explicit execution emits fixed events.
    /// - Throws: Unexpected structural admission or predicate execution failure.
    @Test func pureAuthoringAndRedactedEvaluation() async throws {
        let recorder = LogRecorder()
        let policy = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let policy = InvocationPolicy<String> { !$0.isEmpty }
            try policy.validate(limits: .init())
            _ = try DefinitionPlan.compile(EmptyBotDefinition())
            return policy
        }
        #expect(recorder.entries.isEmpty)
        let allowed = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await policy.evaluate("private_invocation_value", limits: .init())
        }
        #expect(allowed)
        #expect(recorder.entries.map { $0.metadata["dk.event"]?.description } == ["dsl.policy.evaluating",
            "dsl.policy.leaf_entered", "dsl.policy.leaf_decided", "dsl.policy.leaf_exited", "dsl.policy.evaluated"])
        #expect(recorder.entries.allSatisfy { $0.level == .trace && $0.label == "discordkit.dsl.policy" })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_invocation_value"))
    }

    /// Short circuit decisions and failed leaves retain an ordered trace without evaluating skipped input or rendering errors.
    /// - Parameter fails: Whether the first leaf throws rather than denying.
    /// - Throws: Unexpected policy configuration or execution errors.
    @Test(arguments: [false, true]) func shortCircuitAndFailureAreDistinguishable(fails: Bool) async throws {
        let recorder = LogRecorder()
        let left = InvocationPolicy<String> { _ in
            if fails { throw TestSupportFailure.scripted("private_predicate_error") }
            return false
        }
        let policy = left && InvocationPolicy { (_: String) in
            Issue.record("Denied left predicate evaluated right predicate")
            return true
        }
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            if fails {
                await #expect(throws: TestSupportFailure.self) {
                    try await policy.evaluate("private_input", limits: .init())
                }
            } else {
                let allowed = try await policy.evaluate("private_input", limits: .init())
                #expect(!allowed)
            }
        }
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        #expect(events.filter { $0 == "dsl.policy.leaf_entered" }.count == 1)
        #expect(events.contains(fails ? "dsl.policy.failed" : "dsl.policy.short_circuited"))
        #expect(recorder.entries.last?.level == (fails ? .debug : .trace))
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_"))
    }

    /// Nested middleware traces wrapper entry, terminal work and reverse cleanup on both success and failure.
    /// - Parameter fails: Whether the terminal throws a confidential application error.
    /// - Throws: Unexpected middleware configuration or execution errors.
    @Test(arguments: [false, true]) func middlewareUnwindTimeline(fails: Bool) async throws {
        let recorder = LogRecorder()
        let middleware = InvocationMiddleware<String, Int> { input, next in try await next(input) }
            .then(InvocationMiddleware { input, next in try await next(input) })
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            if fails {
                await #expect(throws: TestSupportFailure.self) {
                    try await middleware.run("private_input", limits: .init()) { _ in
                        throw TestSupportFailure.scripted("private_terminal_error")
                    }
                }
            } else {
                let value = try await middleware.run("private_input", limits: .init()) { _ in 7 }
                #expect(value == 7)
            }
        }
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"]?.description } == [
            "dsl.middleware.started", "dsl.middleware.wrapper_entered", "dsl.middleware.wrapper_entered",
            "dsl.middleware.terminal_entered", "dsl.middleware.terminal_exited", "dsl.middleware.wrapper_exited",
            "dsl.middleware.wrapper_exited", fails ? "dsl.middleware.failed" : "dsl.middleware.completed"])
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.dsl.middleware" })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_"))
    }
}
