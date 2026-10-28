// File: Tests/DiscordCommandsTests/CommandRouteExecutionTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordInteractions
import DiscordTestSupport
import Synchronization
import Testing
@testable import DiscordCommands

/// Pre-execution interception retains deterministic admission, caller-task cancellation and original
/// response ownership. Synchronous observations use a compiler-checked mutex; no network or sleeps occur.
@Suite(.timeLimit(.minutes(1))) struct CommandRouteExecutionTests {
    /// Complete preparation runs once before nested wrappers; construction performs no injected work.
    /// Later wrapping forms the outer scope and normal completion unwinds in reverse entry order.
    /// - Throws: Unexpected route/context construction or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func preparationAndWrapperOrder() async throws {
        let trace = RouteExecutionTrace()
        let base = CommandRoute(key: try .command(name: "ping"), prepare: { _ in
            trace.record("prepare")
            return { trace.record("handler") }
        })
        let route = base.wrappingExecution { _, next in
            trace.record("inner enter")
            defer { trace.record("inner exit") }
            try await next()
        }.wrappingExecution { _, next in
            trace.record("outer enter")
            defer { trace.record("outer exit") }
            try await next()
        }
        let router = try CommandRouter(routes: [route])
        #expect(route.key == base.key)
        #expect(trace.values.isEmpty)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        #expect(try await router.route(context))
        #expect(trace.values == ["prepare", "outer enter", "inner enter", "handler", "inner exit", "outer exit"])
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// A wrapper can reject by omitting continuation execution while preparation and matched routing
    /// still occur exactly once. No implicit response, background task or handler invocation appears.
    /// - Throws: Unexpected route/context construction or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rejectionSkipsExecution() async throws {
        let trace = RouteExecutionTrace()
        let route = CommandRoute(key: try .command(name: "ping"), prepare: { _ in
            trace.record("prepare")
            return { trace.record("handler") }
        }).wrappingExecution { _, _ in trace.record("reject") }
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        #expect(try await router.route(context))
        #expect(trace.values == ["prepare", "reject"])
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Preparation failures bypass every wrapper and release router capacity for subsequent callers.
    /// The exact original error propagates, leaving the response owner pending with no handler effects.
    /// - Throws: Unexpected route/context construction errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func failedPreparationBypassesWrappers() async throws {
        let trace = RouteExecutionTrace()
        let route = CommandRoute(key: try .command(name: "ping"), prepare: { _ in
            trace.record("prepare")
            throw DiscordError.validation(.invalidValue)
        }).wrappingExecution { _, next in
            trace.record("wrapper")
            try await next()
        }
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        for _ in 0..<2 {
            await #expect(throws: DiscordError.validation(.invalidValue)) { try await router.route(context) }
            #expect(await router.activeHandlerCount == 0)
        }
        #expect(trace.values == ["prepare", "prepare"])
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Handler failure and cooperative cancellation unwind wrappers and release aggregate capacity.
    /// A deterministic barrier proves cancellation occurs during admitted work rather than before it.
    /// - Parameter cancelled: True blocks then cancels; false throws a known handler error directly.
    /// - Throws: Unexpected setup or barrier failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func failedExecutionUnwinds(cancelled: Bool) async throws {
        let trace = RouteExecutionTrace(), entered = TestBarrier(), release = TestBarrier()
        let route = CommandRoute(key: try .command(name: "ping"), prepare: { _ in
            trace.record("prepare")
            return {
                trace.record("handler")
                if cancelled { entered.open(); try await release.wait() }
                throw DiscordError.cancelled
            }
        }).wrappingExecution { _, next in
            trace.record("wrapper enter")
            defer { trace.record("wrapper exit") }
            try await next()
        }
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        let task = Task { try await router.route(context) }
        if cancelled {
            try await entered.wait()
            #expect(await router.activeHandlerCount == 1)
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await #expect(throws: DiscordError.cancelled) { try await task.value }
        }
        #expect(trace.values == ["prepare", "wrapper enter", "handler", "wrapper exit"])
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }
}

/// Finite invocation-order observations shared safely by synchronous preparation and async wrappers.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class RouteExecutionTrace: Sendable {
    private let storage = Mutex<[String]>([])

    /// Reads an independent immutable snapshot under the mutex without starting asynchronous work.
    var values: [String] { storage.withLock { $0 } }

    /// Appends one fixed test marker without retaining contexts, interaction values or credentials.
    /// - Parameter value: A bounded compile-time test marker identifying one observed step.
    func record(_ value: String) { storage.withLock { $0.append(value) } }
}
