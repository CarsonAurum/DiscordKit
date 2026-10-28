// File: Tests/DiscordCommandDSLTests/FamilyRegistrationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Full compiled catalogs reuse the existing explicit, change-only registration owner.
@Suite(.timeLimit(.minutes(1))) struct FamilyRegistrationTests {
    /// Builds three same-name command types with advanced global registration fields preserved.
    /// - Returns: Inert compiled slash/user/message catalog with exact application routes.
    /// - Throws: Invalid metadata, structural admission or catalog consistency errors.
    static func catalog() throws -> CompiledCommands {
        let definitions = try [
            CommandDefinition.slash(name: "inspect", description: "Inspect typed input",
                nameLocalizations: .value(["de": "ansehen"]),
                descriptionLocalizations: .value(["de": "Eingabe ansehen"]),
                defaultMemberPermissions: .value("0"), integrationTypes: [.guildInstall],
                contexts: [.guild], nsfw: true),
            CommandDefinition.contextMenu(name: "inspect", type: .user,
                nameLocalizations: .value(["de": "Ansehen"]),
                defaultMemberPermissions: .null, integrationTypes: [.userInstall], contexts: [.privateChannel]),
            CommandDefinition.contextMenu(name: "inspect", type: .message),
        ]
        let routes = try definitions.map { definition in
            CommandRoute(key: try .command(name: definition.request.name, type: definition.request.type)) { _ in
                Issue.record("Registration must never execute handlers")
            }
        }
        return try CommandCompilation.compile(ExistingCommandFamily(id: "catalog", definitions: definitions, routes: routes))
    }

    /// Adds server-owned IDs without changing writable payloads or explicit null/omission semantics.
    /// - Parameters:
    ///   - definition: Desired validated registration.
    ///   - identifier: Unique synthetic command ID.
    /// - Returns: Existing API response object for exact canonical comparison.
    static func snapshot(_ definition: CommandDefinition, identifier: Int) -> JSONValue {
        guard case .object(var fields) = definition.request.jsonValue() else { return .null }
        fields["id"] = .string(String(identifier))
        fields["application_id"] = .string("2")
        fields["version"] = .string("99")
        if fields["description"] == nil { fields["description"] = .string("") }
        if fields["name_localizations"] == nil { fields["name_localizations"] = .null }
        if fields["description_localizations"] == nil { fields["description_localizations"] = .null }
        if fields["default_member_permissions"] == nil { fields["default_member_permissions"] = .null }
        return .object(fields)
    }

    /// Creates a no-listener host whose constructors cannot access a registration transport.
    /// - Parameters:
    ///   - commands: Previously compiled catalog.
    ///   - guildID: Optional explicit guild scope; global settings must fail synchronously in guild scope.
    /// - Returns: Inert signed HTTP application retaining one router/reconciler.
    /// - Throws: Invalid scope/settings or synthetic verifier configuration.
    static func application(_ commands: CompiledCommands, guildID: GuildID? = nil) throws -> CommandApplication {
        try CommandApplication(applicationID: .init(rawValue: 2), commands: commands,
            ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: String(repeating: "09", count: 32), now: { 1000 })),
            admission: InteractionAcknowledgementAdmission(), guildID: guildID)
    }

    /// Produces one finite JSON response without sockets, credentials or shared mutable fixtures.
    /// - Parameters:
    ///   - value: Synthetic server response or bounded API error object.
    ///   - status: HTTP status, default successful 200.
    /// - Returns: Owned response stream consumed by the real REST client.
    /// - Throws: JSON serialization or stream validation errors.
    static func response(_ value: JSONValue, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [
            HTTPHeader(name: "X-RateLimit-Limit", value: "100"),
            HTTPHeader(name: "X-RateLimit-Remaining", value: "99"),
            HTTPHeader(name: "X-RateLimit-Reset-After", value: "1"),
        ], body: try RequestBody(bytes: value.serialized(), contentType: "application/json").makeStream())
    }

    /// Repeated explicit no-op synchronization fetches once each and preserves same-name namespaces and unmanaged commands.
    /// Advanced localization/context/permission fields survive exact lowering into the reconciliation catalog.
    /// - Throws: Any authoring, synthetic REST or canonical comparison error fails this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unchangedCatalogPreservesNamespaces() async throws {
        let commands = try Self.catalog(), app = try Self.application(commands), clock = ManualClock()
        let unmanaged = try CommandDefinition.contextMenu(name: "Unmanaged", type: .user)
        let list = JSONValue.array(commands.definitions.enumerated().map { Self.snapshot($0.element, identifier: $0.offset + 10) }
            + [Self.snapshot(unmanaged, identifier: 30)])
        let read: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == "GET")
            #expect(request.url.path == "/api/v10/applications/2/commands")
            #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "with_localizations", value: "true")])
            return try Self.response(list)
        }
        let transport = try ScriptedHTTPTransport(steps: [read, read])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        try await app.run(listener: ScriptedHTTPIngress(incoming: []), context: TransportContext(clock: clock))
        #expect(await transport.executionCount == 0)
        for _ in 0..<2 {
            let report = try await app.synchronize(using: client)
            #expect(report.unchangedCount == 3)
            #expect(report.written.isEmpty)
        }
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// A changed slash patches its stable ID, a missing user menu creates, and a failing message stops with exact partial progress.
    /// Unmanaged registrations are never deleted and server uncertainty does not trigger a replay.
    /// - Parameter status: Definitive permission rejection or submitted server uncertainty.
    /// - Throws: Unexpected setup/REST failures fail the test; the expected partial report is inspected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [403, 500]) func changedCatalogRetainsPartialProgress(status: Int) async throws {
        let commands = try Self.catalog(), app = try Self.application(commands), clock = ManualClock()
        guard case .object(var old) = Self.snapshot(commands.definitions[0], identifier: 10) else { return }
        old["description"] = .string("Earlier description")
        let earlier = JSONValue.object(old)
        let unmanaged = try CommandDefinition.contextMenu(name: "Unmanaged", type: .user)
        let transport = try ScriptedHTTPTransport(steps: [
            { request in
                #expect(request.method == "GET")
                return try Self.response(.array([earlier, Self.snapshot(unmanaged, identifier: 30)]))
            },
            { request in
                #expect(request.method == "PATCH")
                #expect(request.url.path == "/api/v10/applications/2/commands/10")
                return try Self.response(Self.snapshot(commands.definitions[0], identifier: 10))
            },
            { request in
                #expect(request.method == "POST")
                #expect(request.url.path == "/api/v10/applications/2/commands")
                return try Self.response(Self.snapshot(commands.definitions[1], identifier: 11), status: 201)
            },
            { request in
                #expect(request.method == "POST")
                return try Self.response(.object(["code": .number(try JSONNumber(rawValue: "50013")),
                    "message": .string("synthetic rejection")]), status: status)
            },
        ])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await app.synchronize(using: client); Issue.record("Expected partial failure") }
        catch let failure as CommandSyncFailure {
            #expect(failure.failedDefinitionIndex == 2)
            #expect(failure.completed.unchangedCount == 0)
            #expect(failure.completed.written.count == 2)
            #expect(failure.completed.written.map(\.id.rawValue) == [10, 11])
            if status == 500 { #expect(failure.underlyingError as? DiscordError == .unknownMutationOutcome(.serverErrorAfterSubmission)) }
            else { #expect((failure.underlyingError as? APIResponseError)?.status == status) }
        }
        #expect(await transport.executionCount == 4)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Global-only context/install fields are rejected for a guild catalog before any registration transport exists.
    /// - Throws: Unexpected catalog creation failure fails this test.
    @Test func guildScopeRejectsGlobalSettings() throws {
        let commands = try Self.catalog()
        #expect(throws: DiscordError.validation(.invalidValue)) { try Self.application(commands, guildID: .init(rawValue: 9)) }
    }
}
