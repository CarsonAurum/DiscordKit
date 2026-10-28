// File: Tests/DiscordCommandsTests/CommandLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordLogging
import DiscordTestSupport
import Testing
@testable import DiscordCommands

/// Captures semantic router stages on the caller's task without bootstrapping global logging.
@Suite struct CommandLoggingTests {
    /// Successful, rejected preparation and failed handler operations expose distinct stages and final zero admission.
    /// - Parameter variant: Zero succeeds, one fails during preparation, two fails inside the handler.
    /// - Throws: Unexpected fixture construction or routing failure.
    @Test(arguments: 0..<3) func routeTimelineAndRedaction(variant: Int) async throws {
        let recorder = LogRecorder()
        let name = "private-command"
        let route = CommandRoute(key: try .command(name: name), prepare: { _ in
            if variant == 1 { throw TestSupportFailure.scripted("private_preparation_error") }
            return {
                if variant == 2 { throw TestSupportFailure.scripted("private_handler_error") }
            }
        })
        let router = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        }
        #expect(recorder.entries.isEmpty)
        let input = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(name: name))
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            if variant == 0 {
                let matched = try await router.route(input)
                #expect(matched)
            }
            else {
                await #expect(throws: TestSupportFailure.self) { try await router.route(input) }
            }
        }
        var expected = ["commands.route.started", "commands.route.matched", "commands.route.admitted",
            "commands.route.preparing"]
        if variant == 1 { expected.append("commands.route.preparation_failed") }
        else { expected += ["commands.route.prepared", "commands.route.executing",
            variant == 0 ? "commands.route.completed" : "commands.route.failed"] }
        expected.append("commands.route.released")
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"]?.description } == expected)
        #expect(recorder.entries.last?.metadata["dk.active"]?.description == "0")
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.commands.router" })
        if variant == 2 {
            #expect(recorder.entries.contains { $0.level == .error && $0.metadata["dk.event"] == "commands.route.failed" })
        }
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        for privateValue in [name, "private_preparation_error", "private_handler_error", "synthetic-command-token", "18446744073709551614"] {
            #expect(!rendered.contains(privateValue))
        }
        #expect(await router.activeHandlerCount == 0)
    }

    /// Missing routes emit a bounded debug outcome without admitting or preparing any handler.
    /// - Throws: Unexpected synthetic context or empty-router construction failure.
    @Test func unmatchedRouteTimeline() async throws {
        let recorder = LogRecorder(), router = try CommandRouter()
        let input = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        let matched = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await router.route(input)
        }
        #expect(!matched)
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"]?.description } == [
            "commands.route.started", "commands.route.unmatched"])
        #expect(recorder.entries.allSatisfy { $0.level == .debug })
        #expect(await router.activeHandlerCount == 0)
    }
}
