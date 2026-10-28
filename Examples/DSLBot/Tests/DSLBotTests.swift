// File: Examples/DSLBot/Tests/DSLBotTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@testable import DSLBot
import DiscordBotDSL
import Testing

/// An independently compiled consumer of protocol modules and the actual supervised runtime.
@Suite("External supervised bot", .timeLimit(.minutes(1)))
struct DSLBotTests {
    /// Real client socket ingestion routes one command, one exact HTTP callback and two typed events.
    /// Joined accounting proves finite local cleanup; no authenticated Discord connection is attempted.
    @Test func externalModulesRunWithExactHTTPResponseAndCompleteCleanup() async throws {
        let result = try await DSLBot.runOffline()
        #expect(result.labels == ["ready", "ping", "stop"])
        #expect(result.callbackCount == 1)
        #expect(result.registrationCount == 0)
        #expect(result.callbacksBeforeRun == 0)
        #expect(result.ownedResources == 0)
        #expect(result.extensionAuthorizations == 1)
        #expect(result.extensionExecutions == 1)
    }

    /// The protocol's public default `main` invokes its explicit inert factory then joins the entire run.
    @Test func defaultApplicationEntryPointOwnsRun() async throws { try await DefaultBotApplication.main() }

    /// Pre-cancelled application startup cannot discover, invoke a command or retain a subscription.
    @Test func preCancelledApplicationIsObservable() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try await DefaultBotApplication.main()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Separate external conformer exercises the inherited entry point, not the executable's reporting method.
private struct DefaultBotApplication: BotApplication {
    /// Builds the same inert explicit dependencies as the executable consumer.
    /// - Returns: Finite offline host with no ambient environment or credentials.
    /// - Throws: Original declaration or host construction failures.
    static func makeRuntime() async throws -> BotRuntime { try await DSLBot.makeRuntime() }
}
