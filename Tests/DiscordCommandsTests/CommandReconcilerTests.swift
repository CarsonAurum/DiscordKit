// File: Tests/DiscordCommandsTests/CommandReconcilerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordLogging
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordCommands

/// Explicit registration tests exercise real HTTP policy using bounded synthetic scripts and virtual time.
@Suite(.timeLimit(.minutes(1))) struct CommandReconcilerTests {
    /// Cancellation during an explicit mutation preserves partial progress and releases reconciliation without an error-severity event.
    /// - Throws: Unexpected synthetic definition, transport, barrier or configuration failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledMutationLogsDiagnosticSeverity() async throws {
        let entered = TestBarrier(), release = TestBarrier(), logs = LogRecorder()
        let definition = try CommandDefinition.slash(name: "private-command", description: "private-description")
        let harness = try CommandsRESTHarness(steps: [
            { _ in try CommandsTestFixtures.response(Data("[]".utf8)) },
            { _ in entered.open(); try await release.wait(); throw CancellationError() },
        ])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID, definitions: [definition])
        await DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) {
            let task = Task { try await reconciler.synchronize(using: harness.client) }
            do { try await entered.wait() }
            catch { Issue.record("Mutation admission barrier failed") }
            task.cancel()
            do { _ = try await task.value; Issue.record("Expected partial cancellation failure") }
            catch let failure as CommandSyncFailure {
                #expect(failure.completed.written.isEmpty)
                #expect(failure.failedDefinitionIndex == 0)
            } catch { Issue.record("Expected CommandSyncFailure") }
        }
        let partial = try #require(logs.entries.first { $0.metadata["dk.event"] == "commands.sync.partial" })
        #expect(partial.level == .debug && partial.metadata["dk.cancelled"]?.description == "true")
        #expect(logs.entries.last?.metadata["dk.event"] == "commands.sync.released")
        #expect(!logs.entries.contains { $0.label == "discordkit.commands.reconciliation" && $0.level >= .warning })
        #expect(!String(describing: logs.entries.map { ($0.message, $0.metadata) }).contains("private-"))
        #expect(await harness.coordinator.snapshot().activeCount == 0)
        await harness.coordinator.close()
    }

    /// Two identical reconciliations each fetch once and send zero writes, leaving unrelated registrations untouched.
    /// Server-only metadata, nested explicit defaults, localization singulars and set order are canonicalized.
    /// - Parameters:
    ///   - global: Selects independent global or guild scope.
    ///   - explicitSettings: Global variants manage context/install fields explicitly or leave them application-owned.
    /// - Throws: Unexpected definition, response or reconciliation failures fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func identicalSyncIsReadOnly(global: Bool, explicitSettings: Bool) async throws {
        let option = try ApplicationCommandOptionCreate(type: .string, name: "query", description: "Search", autocomplete: false)
        let definition = try CommandDefinition.slash(name: "ping", description: "Description",
            integrationTypes: global && explicitSettings ? [.guildInstall, .userInstall] : nil,
            contexts: global && explicitSettings ? [.guild, .botDM] : nil) { option }
        let unrelated = try CommandDefinition.contextMenu(name: "Unmanaged", type: .message)
        var managed = CommandsTestFixtures.snapshot(definition, guild: !global)
        managed["future_server_metadata"] = .string("ignored")
        managed["name_localized"] = .string("translated")
        if global {
            managed["integration_types"] = .array([.number(try JSONNumber(rawValue: "1")), .number(try JSONNumber(rawValue: "0"))])
            managed["contexts"] = .array([.number(try JSONNumber(rawValue: "1")), .number(try JSONNumber(rawValue: "0"))])
        }
        guard case .object(var leaf) = option.jsonValue() else { Issue.record("Expected option object"); return }
        leaf["required"] = .bool(false); leaf["name_localizations"] = .object([:])
        leaf["description_localizations"] = .null; leaf["name_localized"] = .string("translated leaf")
        leaf["future_read_only"] = .bool(true)
        managed["options"] = .array([.object(leaf)])
        let bytes = try CommandsTestFixtures.list([CommandsTestFixtures.snapshot(unrelated, id: 2, guild: !global), managed])
        let read: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == "GET")
            #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "with_localizations", value: "true")])
            #expect(request.url.path.contains("/guilds/") == !global)
            return try CommandsTestFixtures.response(bytes)
        }
        let harness = try CommandsRESTHarness(steps: [read, read])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID,
            guildID: global ? nil : CommandsTestFixtures.guildID, definitions: [definition])
        for _ in 0..<2 {
            let report = try await reconciler.synchronize(using: harness.client)
            #expect(report.unchangedCount == 1 && report.written.isEmpty)
        }
        #expect(await harness.transport.executionCount == 2)
        #expect(await harness.coordinator.snapshot().activeCount == 0)
        #expect(harness.clock.pendingSleepCount == 0)
        await harness.coordinator.close()
    }

    /// A changed managed definition causes one stable-ID edit; unchanged and unmanaged entries cause no writes.
    /// A later explicit reconciliation fetches fresh state and acknowledges both definitions as no-ops.
    /// - Throws: Unexpected descriptor, encoding or REST-policy errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func appliesOnlyChangedAndRetainsUnmanaged() async throws {
        let first = try CommandDefinition.slash(name: "first", description: "Same")
        let second = try CommandDefinition.slash(name: "second", description: "New")
        let oldSecond = try CommandDefinition.slash(name: "second", description: "Old")
        let unmanaged = try CommandDefinition.slash(name: "unmanaged", description: "Retained")
        let initial = try CommandsTestFixtures.list([CommandsTestFixtures.snapshot(unmanaged, id: 3),
            CommandsTestFixtures.snapshot(oldSecond, id: 2), CommandsTestFixtures.snapshot(first)])
        let updatedSecond = CommandsTestFixtures.snapshot(second, id: 2)
        let updated = try CommandsTestFixtures.list([CommandsTestFixtures.snapshot(first), updatedSecond,
            CommandsTestFixtures.snapshot(unmanaged, id: 3)])
        let harness = try CommandsRESTHarness(steps: [
            { request in #expect(request.method == "GET"); return try CommandsTestFixtures.response(initial) },
            { request in
                #expect(request.method == "PATCH")
                #expect(request.url.path == "/api/v10/applications/18446744073709551615/guilds/3/commands/2")
                #expect(try JSONValue.parse(await ResponseBody.collect(request.body, maximumBytes: 1_048_576)) == second.request.replacementChanges().jsonValue())
                return try CommandsTestFixtures.response(JSONValue.object(updatedSecond).serialized(), status: 200)
            },
            { request in #expect(request.method == "GET"); return try CommandsTestFixtures.response(updated) }
        ])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID,
            guildID: CommandsTestFixtures.guildID, definitions: [first, second])
        let applied = try await reconciler.synchronize(using: harness.client)
        #expect(applied.unchangedCount == 1 && applied.written.map(\.id) == [.init(rawValue: 2)])
        let repeated = try await reconciler.synchronize(using: harness.client)
        #expect(repeated.unchangedCount == 2 && repeated.written.isEmpty)
        #expect(await harness.transport.executionCount == 3)
        await harness.coordinator.close()
    }

    /// Empty desired catalogs are deliberately read-only; they never become destructive empty bulk replacements.
    /// - Throws: Unexpected local setup or list execution errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func emptyDesiredRetainsEverything() async throws {
        let definition = try CommandDefinition.slash(name: "existing", description: "Retained")
        let bytes = try CommandsTestFixtures.list([CommandsTestFixtures.snapshot(definition, guild: false)])
        let harness = try CommandsRESTHarness(steps: [{ request in
            #expect(request.method == "GET"); return try CommandsTestFixtures.response(bytes)
        }])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID, definitions: [])
        let report = try await reconciler.synchronize(using: harness.client)
        #expect(report.unchangedCount == 0 && report.written.isEmpty)
        #expect(await harness.transport.executionCount == 1)
        await harness.coordinator.close()
    }

    /// The complete desired catalog is rejected before transmission for duplicate names, type limits, scope or bytes.
    /// Distinct types may use the same display name and boundary budgets accept exact encoded body lengths.
    /// - Throws: Unexpected valid setup errors fail the test; each invalid initialization is explicitly asserted.
    @Test func completeCatalogPreflight() throws {
        let slash = try CommandDefinition.slash(name: "same", description: "Description")
        let menu = try CommandDefinition.contextMenu(name: "same", type: .user)
        _ = try CommandReconciler(applicationID: .init(rawValue: 1), definitions: [slash, menu])
        #expect(throws: (any Error).self) { try CommandReconciler(applicationID: .init(rawValue: 1), definitions: [slash, slash]) }
        for bytes in [0, -1] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandReconciler(applicationID: .init(rawValue: 1), definitions: [], maximumDefinitionBytes: bytes) }
        }
        let count = try slash.request.jsonValue().serialized().count
        _ = try CommandReconciler(applicationID: .init(rawValue: 1), definitions: [slash], maximumDefinitionBytes: count)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try CommandReconciler(applicationID: .init(rawValue: 1), definitions: [slash], maximumDefinitionBytes: count - 1) }
        let global = try CommandDefinition.slash(name: "global", description: "d", contexts: [.guild])
        let entry = try CommandDefinition.entryPoint(name: "Launch", description: "d", handler: .appHandler)
        for definition in [global, entry] {
            #expect(throws: (any Error).self) { try CommandReconciler(applicationID: .init(rawValue: 1), guildID: .init(rawValue: 2), definitions: [definition]) }
        }
        for type in ApplicationCommandType.allCases {
            let cap = type == .chatInput ? 100 : (type == .primaryEntryPoint ? 1 : 15)
            let definitions = try (0...cap).map { index in
                CommandDefinition(try ApplicationCommandCreate(name: "command\(index)", type: type,
                    description: type == .chatInput || type == .primaryEntryPoint ? "d" : nil))
            }
            #expect(throws: (any Error).self) { try CommandReconciler(applicationID: .init(rawValue: 1), definitions: definitions) }
        }
    }

    /// Invalid server scopes, duplicate IDs/identities and oversized catalogs fail after the read and before any mutation.
    /// - Parameter variant: Wrong owner, wrong guild, duplicate ID, duplicate identity, missing guild or oversized catalog.
    /// - Throws: Unexpected fixture and HTTP setup errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<6) func invalidSnapshots(variant: Int) async throws {
        let definition = try CommandDefinition.slash(name: "ping", description: "d")
        var fields = CommandsTestFixtures.snapshot(definition), list: [[String: JSONValue]]
        switch variant {
        case 0: fields["application_id"] = .string("9"); list = [fields]
        case 1: fields["guild_id"] = .string("9"); list = [fields]
        case 2: var other = fields; other["name"] = .string("other"); list = [fields, other]
        case 3: var other = fields; other["id"] = .string("9"); list = [fields, other]
        case 4: fields.removeValue(forKey: "guild_id"); list = [fields]
        default: list = (1...131).map { index in
            var item = fields; item["id"] = .string(String(index)); item["name"] = .string("name\(index)"); return item
        }
        }
        let bytes = try CommandsTestFixtures.list(list)
        let harness = try CommandsRESTHarness(steps: [{ _ in try CommandsTestFixtures.response(bytes) }])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID,
            guildID: CommandsTestFixtures.guildID, definitions: [definition])
        await #expect(throws: variant == 5 ? DiscordError.validation(.limitExceeded) : .transport(.invalidResponse)) {
            try await reconciler.synchronize(using: harness.client)
        }
        #expect(await harness.transport.executionCount == 1)
        await harness.coordinator.close()
    }

    /// Stopped writes retain earlier acknowledged progress and the original rate/API/indeterminate outcome.
    /// No later definition is attempted and ordinary diagnostics conceal server error content.
    /// - Parameter status: Explicit authorization, permission, rejection, rate-limit or submitted server failure.
    /// - Throws: Unexpected fixture/REST setup errors fail the test; expected CommandSyncFailure is inspected directly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [400, 401, 403, 429, 500]) func partialMutationFailure(status: Int) async throws {
        let first = try CommandDefinition.slash(name: "first", description: "d")
        let second = try CommandDefinition.slash(name: "second", description: "d")
        let third = try CommandDefinition.slash(name: "third", description: "d")
        let success = try JSONValue.object(CommandsTestFixtures.snapshot(first)).serialized()
        let harness = try CommandsRESTHarness(steps: [
            { _ in try CommandsTestFixtures.response(Data("[]".utf8)) },
            { request in #expect(request.method == "POST"); return try CommandsTestFixtures.response(success, status: 201) },
            { request in
                #expect(request.method == "POST")
                return try CommandsTestFixtures.response(Data(#"{"code":50035,"message":"private-token","retry_after":0.25,"global":false}"#.utf8), status: status)
            }
        ])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID,
            guildID: CommandsTestFixtures.guildID, definitions: [first, second, third])
        do { _ = try await reconciler.synchronize(using: harness.client); Issue.record("Expected stopped reconciliation") }
        catch let failure as CommandSyncFailure {
            #expect(failure.failedDefinitionIndex == 1)
            #expect(failure.completed.unchangedCount == 0 && failure.completed.written.map(\.name) == ["first"])
            if status == 500 { #expect(failure.underlyingError as? DiscordError == .unknownMutationOutcome(.serverErrorAfterSubmission)) }
            else { #expect((failure.underlyingError as? APIResponseError)?.status == status) }
            #expect(!String(reflecting: failure).contains("private-token"))
            #expect(!String(describing: Mirror(reflecting: failure).children).contains("private-token"))
        }
        #expect(await harness.transport.executionCount == 3)
        #expect(await harness.coordinator.snapshot().activeCount == 0)
        await harness.coordinator.close()
    }

    /// Concurrent reconciliation is rejected immediately; cancellation releases the gate and a later call can proceed.
    /// Pre-cancellation and an inclusive expired deadline perform zero transmission. The cancelled request's
    /// consumed unknown-route quota is retained until its one-second provisional window expires in virtual time.
    /// - Throws: Unexpected setup or subsequent successful reconciliation failures fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrencyCancellationAndDeadline() async throws {
        let entered = TestBarrier(), release = TestBarrier()
        let harness = try CommandsRESTHarness(steps: [
            { _ in entered.open(); try await release.wait(); return try CommandsTestFixtures.response(Data("[]".utf8)) },
            { _ in try CommandsTestFixtures.response(Data("[]".utf8)) }
        ])
        let reconciler = try CommandReconciler(applicationID: CommandsTestFixtures.applicationID, definitions: [])
        let task = Task { try await reconciler.synchronize(using: harness.client) }
        try await entered.wait()
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await reconciler.synchronize(using: harness.client) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError || error as? DiscordError == .cancelled) }
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await reconciler.synchronize(using: harness.client) }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        await #expect(throws: (any Error).self) { try await reconciler.synchronize(using: harness.client, deadline: harness.clock.now) }
        #expect(await harness.transport.executionCount == 1)
        #expect(await harness.coordinator.snapshot().activeCount == 0)
        // Cancellation releases ownership, but correctly does not refund the already consumed request budget.
        try harness.clock.advance(by: .seconds(1))
        let report = try await reconciler.synchronize(using: harness.client)
        #expect(report.written.isEmpty)
        #expect(await harness.transport.executionCount == 2)
        #expect(harness.clock.pendingSleepCount == 0)
        await harness.coordinator.close()
    }
}
