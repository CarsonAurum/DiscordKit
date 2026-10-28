// File: Tests/DiscordCommandsTests/CommandRouterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordCommands

/// Fixed exact routing tests use inert normalized contexts and deterministic gates, never Discord requests.
@Suite(.timeLimit(.minutes(1))) struct CommandRouterTests {
    /// All command types, nested paths, focused autocomplete, components and modals retain independent namespaces.
    /// HTTP and Gateway modes deliver the exact same typed context and never acknowledge implicitly.
    /// - Parameter gateway: True selects Gateway receipt; false selects HTTP receipt.
    /// - Throws: Unexpected key/context or handler errors fail the test.
    @Test(arguments: [false, true]) func completeRouting(gateway: Bool) async throws {
        let mode: InteractionDeliveryMode = gateway ? .gateway : .http
        let recorder = RouterRecorder()
        let cases: [(CommandRouteKey, InteractionContext)] = try [
            (.command(name: "ping"), CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(), mode: mode)),
            (.command(name: "Inspect User", type: .user), CommandsTestFixtures.context(type: 2,
                data: CommandsTestFixtures.commandData(name: "Inspect User", type: 2), mode: mode)),
            (.command(name: "Inspect Message", type: .message), CommandsTestFixtures.context(type: 2,
                data: CommandsTestFixtures.commandData(name: "Inspect Message", type: 3), mode: mode)),
            (.command(name: "Launch", type: .primaryEntryPoint), CommandsTestFixtures.context(type: 2,
                data: CommandsTestFixtures.commandData(name: "Launch", type: 4), mode: mode)),
            (.command(name: "ping", path: ["sub"]), CommandsTestFixtures.context(type: 2,
                data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"sub","type":1,"options":[]}"#)]), mode: mode)),
            (.command(name: "ping", path: ["group", "sub"]), CommandsTestFixtures.context(type: 2,
                data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"group","type":2,"options":[{"name":"sub","type":1,"options":[]}]}"#)]), mode: mode)),
            (.autocomplete(name: "ping", focusedOption: "query"), CommandsTestFixtures.context(type: 4,
                data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"query","type":3,"focused":true,"value":"prefix"}"#)]), mode: mode)),
            (.autocomplete(name: "ping", path: ["group", "sub"], focusedOption: "count"), CommandsTestFixtures.context(type: 4,
                data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"group","type":2,"options":[{"name":"sub","type":1,"options":[{"name":"count","type":4,"focused":true,"value":1}]}]}"#)]), mode: mode)),
            (.component(customID: "shared"), CommandsTestFixtures.context(type: 3,
                data: Self.option(#"{"custom_id":"shared","component_type":2}"#), mode: mode)),
            (.modal(customID: "shared"), CommandsTestFixtures.context(type: 5,
                data: Self.option(#"{"custom_id":"shared","components":[]}"#), mode: mode))
        ]
        let routes = cases.map { key, _ in CommandRoute(key: key) { context in
            #expect(context.deliveryMode == mode)
            #expect(await context.responder.snapshot() == .pending)
            await recorder.record(context.interaction.type.rawValue)
        } }
        let router = try CommandRouter(routes: routes)
        for (_, context) in cases { #expect(try await router.route(context)) }
        #expect(await recorder.values.count == cases.count)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Unknown kinds, unregistered identities and malformed ambiguous argument paths remain unhandled without callbacks.
    /// No submitted values become route keys and no fallback invokes a root handler for a nested command.
    /// - Parameter variant: Independent malformed or unsupported route shape.
    /// - Throws: Unexpected parser/setup failures fail this test; unhandled routing is explicitly asserted.
    @Test(arguments: 0..<15) func unsupportedAndAmbiguous(variant: Int) async throws {
        let recorder = RouterRecorder()
        let route = CommandRoute(key: try .command(name: "ping")) { _ in await recorder.record(2) }
        let router = try CommandRouter(routes: [route])
        let context: InteractionContext
        switch variant {
        case 0: context = try CommandsTestFixtures.context(type: 1)
        case 1: context = try CommandsTestFixtures.context(type: 99, data: .object(["future": .bool(true)]))
        case 2: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(name: "other"))
        case 3: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(type: 99))
        case 4: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(name: "INVALID"))
        case 5: context = try CommandsTestFixtures.context(type: 4, data: CommandsTestFixtures.commandData())
        case 6: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"sub","type":1,"options":[]}"#)]))
        case 7: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"sub","type":1}"#)]))
        case 8: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [
            Self.option(#"{"name":"sub","type":1,"options":[]}"#), Self.option(#"{"name":"leaf","type":3,"value":"x"}"#)]))
        case 9: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [
            Self.option(#"{"name":"duplicate","type":3,"value":"a"}"#), Self.option(#"{"name":"duplicate","type":3,"value":"b"}"#)]))
        case 10: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"group","type":2,"options":[{"name":"leaf","type":3,"value":"x"}]}"#)]))
        case 11: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"sub","type":1,"options":[{"name":"nested","type":1,"options":[]}]}"#)]))
        case 12: context = try CommandsTestFixtures.context(type: 4, data: CommandsTestFixtures.commandData(options: [
            Self.option(#"{"name":"first","type":3,"focused":true}"#), Self.option(#"{"name":"second","type":4,"focused":true}"#)]))
        case 13: context = try CommandsTestFixtures.context(type: 4, data: CommandsTestFixtures.commandData(options: [Self.option(#"{"name":"future","type":99,"focused":true}"#)]))
        default: context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: (0..<26).map { index in
            .object(["name": .string("value\(index)"), "type": .number(try JSONNumber(rawValue: "3")), "value": .string("ignored")])
        }))
        }
        #expect(try await !router.route(context))
        #expect(await recorder.values.isEmpty)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Keys validate kind-specific naming, path depth and custom-ID scalar boundaries before handlers are adopted.
    /// Fixed route count/text budgets reject duplicates and overload without allocating queues or invoking closures.
    /// - Throws: Unexpected valid boundary construction errors fail the test.
    @Test func keyAndRouterBounds() throws {
        for name in ["", "INVALID", String(repeating: "a", count: 33)] {
            #expect(throws: (any Error).self) { try CommandRouteKey.command(name: name) }
        }
        #expect(throws: (any Error).self) { try CommandRouteKey.command(name: "ping", path: ["a", "b", "c"]) }
        #expect(throws: (any Error).self) { try CommandRouteKey.command(name: "Inspect", type: .user, path: ["sub"]) }
        #expect(throws: (any Error).self) { try CommandRouteKey.command(name: "ping", path: ["INVALID"]) }
        #expect(throws: (any Error).self) { try CommandRouteKey.autocomplete(name: "ping", focusedOption: "INVALID") }
        #expect(throws: (any Error).self) { try CommandRouteKey.autocomplete(name: "ping", path: ["a", "b", "c"], focusedOption: "query") }
        for id in ["", String(repeating: "a", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouteKey.component(customID: id) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouteKey.modal(customID: id) }
        }
        let key = try CommandRouteKey.component(customID: String(repeating: "🙂", count: 100))
        let route = CommandRoute(key: key) { _ in Issue.record("Construction must not execute handlers") }
        _ = try CommandRouter(routes: [route], maximumRoutes: 1, maximumRouteTextBytes: 400, maximumConcurrentHandlers: 1)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try CommandRouter(routes: [route], maximumRouteTextBytes: 399) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouter(routes: [route, route]) }
        for bound in [0, -1] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouter(maximumRoutes: bound) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouter(maximumRouteTextBytes: bound) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandRouter(maximumConcurrentHandlers: bound) }
        }
        let other = CommandRoute(key: try .modal(customID: "other")) { _ in }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try CommandRouter(routes: [route, other], maximumRoutes: 1) }
        #expect(try CommandRouteKey.component(customID: "same") != .modal(customID: "same"))
        #expect(try CommandRouteKey.command(name: "same") != .command(name: "same", type: .user))
    }

    /// Suspended handlers consume the aggregate slot; overload fails immediately and cancellation releases the slot.
    /// Unmatched calls remain unhandled even while busy, and pre-cancellation never executes a handler.
    /// - Throws: Unexpected setup or deterministic gate errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func boundedAdmissionAndCancellation() async throws {
        let entered = TestBarrier(), release = TestBarrier(), recorder = RouterRecorder()
        let key = try CommandRouteKey.command(name: "ping")
        let router = try CommandRouter(routes: [CommandRoute(key: key) { _ in
            await recorder.record(2); entered.open(); try await release.wait()
        }], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        let first = Task { try await router.route(context) }
        try await entered.wait()
        #expect(await router.activeHandlerCount == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await router.route(context) }
        let other = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(name: "other"))
        #expect(try await !router.route(other))
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await router.activeHandlerCount == 0)
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await router.route(context) }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await recorder.values == [2])
        release.open()
        #expect(try await router.route(context))
        #expect(await router.activeHandlerCount == 0)
    }

    /// Handler errors propagate unchanged and always release admission without automatic response side effects.
    /// - Throws: Unexpected normalized context or router construction errors fail the test.
    @Test func handlerFailureReleasesAdmission() async throws {
        let router = try CommandRouter(routes: [CommandRoute(key: try .command(name: "ping")) { _ in throw DiscordError.cancelled }], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        for _ in 0..<2 {
            await #expect(throws: DiscordError.cancelled) { try await router.route(context) }
            #expect(await router.activeHandlerCount == 0)
            #expect(await context.responder.snapshot() == .pending)
        }
    }

    /// Parses bounded exact argument/custom-ID fixture objects without Foundation numeric coercion.
    /// - Parameter json: Complete trusted synthetic JSON object used by one test.
    /// - Returns: Exact JSON tree for a normalized interaction fixture.
    /// - Throws: JSON syntax or fixture-bound errors.
    private static func option(_ json: String) throws -> JSONValue { try JSONValue.parse(Data(json.utf8)) }
}

/// Actor-isolated test observations demonstrate routed contexts without sharing mutable state between tests.
private actor RouterRecorder {
    private(set) var values: [Int] = []

    /// Records one safely bounded interaction kind from an admitted handler.
    /// - Parameter value: Synthetic kind discriminator; no submitted values or credentials are retained.
    func record(_ value: Int) { values.append(value) }
}
