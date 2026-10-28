// File: Packages/DiscordDSLExtensions/Tests/DiscordCommandExtensionsTests/ExtensionTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommandExtensions
import DiscordCore
import DiscordDSL
import DiscordModels
import Foundation
import Testing

/// These tests use only public imports from the independent extension and runtime packages.
@Suite struct ExtensionTests {
    /// The custom codec preserves omitted/null/kind failures and bounds exact ASCII domain values.
    /// - Throws: Unexpected failure admitting a valid fixed codec or existing scalar model.
    @Test func customCodecRetainsPresenceAndDomainValidation() throws {
        #expect(try UppercaseCode.decodeArgument(.value(.string("ABC")), resolved: .absent).text == "ABC")
        #expect(throws: ArgumentValueError.missing) { try UppercaseCode.decodeArgument(.absent, resolved: .absent) }
        #expect(throws: ArgumentValueError.nullValue) { try UppercaseCode.decodeArgument(.null, resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try UppercaseCode.decodeArgument(.value(.bool(true)), resolved: .absent) }
        for invalid in ["", "abc", "ABCDEFGHI", "ÁBC", "ABC\n"] {
            #expect(throws: ExtensionError.invalidCode) { try UppercaseCode(invalid) }
        }
        #expect(try UppercaseCode("ABC").argumentValue == .value(.string("ABC")))
    }

    /// Compilation retains typed/raw routes while executing none of the shared actor's service work.
    /// - Throws: Unexpected dependency, schema, structural compilation or policy validation failure.
    @Test func moduleCompilesPublicContributionsWithoutExecution() async throws {
        let counter = ExtensionCounter()
        let dependencies = ExtensionDependencies(counter: counter)
        let module = try ExtensionCommands(id: "commands", dependencies: dependencies)
        let commands = try CommandCompilation.compile(ModuleNamespace(id: "external") { module })
            .applying(ExtensionCommands.policies(dependencies: dependencies))
        #expect(commands.definitions.map(\.request.name) == ["extension", "raw-extension"])
        #expect(commands.routes.count == 2)
        let before = await counter.snapshot()
        #expect(before.authorizations == 0)
        #expect(before.executions == 0)
    }

    /// Required typed configuration is checked during compilation before dependent declarations escape.
    /// - Throws: Unexpected authoring failure constructing otherwise valid public contributions.
    @Test func invalidInjectedConfigurationFailsCompilation() throws {
        let dependencies = ExtensionDependencies(counter: ExtensionCounter(), configurationName: "")
        let module = try ExtensionCommands(id: "commands", dependencies: dependencies)
        do {
            _ = try CommandCompilation.compile(module)
            Issue.record("Invalid dependency configuration unexpectedly compiled")
        } catch let error as DefinitionDiagnostic {
            #expect(error.code == .invalidDependencies)
        }
    }

    /// Full invocation schemas admit custom codecs and sanitize invalid domain text before user execution.
    /// - Throws: Unexpected descriptor or fixed valid invocation-model failure.
    @Test func customCodecIsUsedByCompleteSchema() throws {
        let schema = try ExtensionArguments.schema
        let valid = try InteractionCommandOption(data: Data(#"{"name":"code","type":3,"value":"ABC"}"#.utf8))
        #expect(try schema.decode(options: [valid], commandName: "extension").code.text == "ABC")
        let invalid = try InteractionCommandOption(data: Data(#"{"name":"code","type":3,"value":"abc"}"#.utf8))
        do {
            _ = try schema.decode(options: [invalid], commandName: "extension")
            Issue.record("Lowercase domain input unexpectedly decoded")
        } catch let error as ArgumentDiagnostic {
            #expect(error.code == .invalidValue)
        }
    }

    /// The example service stores fixed counters and rejects the ninth call without increasing them.
    /// - Throws: Unexpected failure during one of the exact eight admitted fixed observations.
    @Test func actorServiceHasFiniteCounts() async throws {
        let counter = ExtensionCounter()
        for _ in 0..<8 { #expect(try await counter.authorize()); try await counter.executed() }
        await #expect(throws: ExtensionError.limitExceeded) { try await counter.authorize() }
        await #expect(throws: ExtensionError.limitExceeded) { try await counter.executed() }
        let snapshot = await counter.snapshot()
        #expect(snapshot.authorizations == 8)
        #expect(snapshot.executions == 8)
    }

    /// Cancelled service calls leave both counters untouched before any admission or application effect.
    @Test func actorServiceCancellationHasNoEffects() async {
        let counter = ExtensionCounter()
        let authorization = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await counter.authorize()
        }
        let execution = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await counter.executed()
        }
        await #expect(throws: CancellationError.self) { try await authorization.value }
        await #expect(throws: CancellationError.self) { try await execution.value }
        let snapshot = await counter.snapshot()
        #expect(snapshot.authorizations == 0)
        #expect(snapshot.executions == 0)
    }
}
