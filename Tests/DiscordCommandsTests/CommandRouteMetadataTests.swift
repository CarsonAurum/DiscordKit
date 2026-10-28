// File: Tests/DiscordCommandsTests/CommandRouteMetadataTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommands
import DiscordCore
import DiscordModels
import Testing

/// Regression coverage for catalog metadata and omitted zero-argument subcommand option arrays.
@Suite(.timeLimit(.minutes(1))) struct CommandRouteMetadataTests {
    /// Metadata contains exact validated keys and retains independent namespaces without submitted values.
    /// - Throws: Unexpected route-key validation errors fail this test.
    @Test func completeIdentityMetadata() throws {
        let key = try CommandRouteKey.autocomplete(name: "search", path: ["tools", "query"], focusedOption: "text")
        #expect(key.metadata == .object(["kind": .string("4"), "command_type": .string("1"),
            "name": .string("search"), "path": .array([.string("tools"), .string("query")]), "focused_option": .string("text")]))
        let root = try CommandRouteKey.command(name: "Inspect User", type: .user)
        #expect(root.metadata == .object(["kind": .string("2"), "command_type": .string("2"),
            "name": .string("Inspect User"), "path": .array([])]))
        #expect(try CommandRouteKey.component(customID: "same").metadata != CommandRouteKey.modal(customID: "same").metadata)
    }

    /// Discord may omit options for a zero-argument subcommand; both direct and grouped paths route once.
    /// Null option arrays, container focus and values remain unhandled or fail model admission.
    /// - Parameter grouped: Selects one-level or grouped zero-input subcommand paths.
    /// - Throws: Unexpected valid fixture or handler errors fail the test.
    @Test(arguments: [false, true]) func omittedSubcommandOptions(grouped: Bool) async throws {
        let subcommand = JSONValue.object(["name": .string("empty"), "type": .number(try JSONNumber(rawValue: "1"))])
        let options = grouped ? [JSONValue.object(["name": .string("group"),
            "type": .number(try JSONNumber(rawValue: "2")), "options": .array([subcommand])])] : [subcommand]
        let key = try CommandRouteKey.command(name: "ping", path: grouped ? ["group", "empty"] : ["empty"])
        let recorder = RouteMetadataRecorder()
        let router = try CommandRouter(routes: [CommandRoute(key: key) { _ in await recorder.record() }])
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: options))
        #expect(try await router.route(context))
        #expect(await recorder.count == 1)
        for invalid: [String: JSONValue] in [
            ["name": .string("empty"), "type": .number(try JSONNumber(rawValue: "1")), "focused": .bool(false)],
            ["name": .string("empty"), "type": .number(try JSONNumber(rawValue: "1")), "focused": .null]
        ] {
            let badOptions = grouped ? [JSONValue.object(["name": .string("group"),
                "type": .number(try JSONNumber(rawValue: "2")), "options": .array([.object(invalid)])])] : [.object(invalid)]
            if invalid["focused"] == .null {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: badOptions))
                }
            } else {
                let badContext = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData(options: badOptions))
                #expect(try await router.route(badContext) == false)
            }
        }
        #expect(await recorder.count == 1)
        #expect(await router.activeHandlerCount == 0)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try CommandsTestFixtures.context(type: 2, data: .object(["id": .string("8"), "name": .string("ping"),
                "type": .number(JSONNumber(rawValue: "1")), "options": .null]))
        }
    }
}

/// Test-local actor counts exact route execution without response or network work.
private actor RouteMetadataRecorder {
    var count = 0
    /// Records one successfully admitted handler call.
    func record() { count += 1 }
}
