// File: Tests/DiscordCommandsTests/CommandsTestFixtures.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommands
import DiscordCore
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation

/// Local deterministic fixtures shared by command tests; synthetic tokens never reach a network adapter.
enum CommandsTestFixtures {
    static let applicationID = ApplicationID(rawValue: UInt64.max)
    static let guildID = GuildID(rawValue: 3)

    /// Creates a complete command response from an independently validated desired request.
    /// - Parameters:
    ///   - definition: Desired typed fields; optional writable response fields may be added by each test.
    ///   - id: Exact response ID, default one; supports values above 2^53.
    ///   - guild: True adds the test guild scope; false produces the independent global catalog.
    /// - Returns: Complete parseable command fields with full localization dictionaries and required server metadata.
    static func snapshot(_ definition: CommandDefinition, id: UInt64 = 1, guild: Bool = true) -> [String: JSONValue] {
        guard case .object(var fields) = definition.request.jsonValue() else { preconditionFailure("Validated command must be object") }
        fields["id"] = .string(String(id)); fields["application_id"] = .string(applicationID.description)
        fields["version"] = .string("18446744073709551614")
        if guild { fields["guild_id"] = .string(guildID.description) }
        if fields["description"] == nil { fields["description"] = .string("") }
        if fields["name_localizations"] == nil { fields["name_localizations"] = .null }
        if fields["description_localizations"] == nil { fields["description_localizations"] = .null }
        if fields["default_member_permissions"] == nil { fields["default_member_permissions"] = .null }
        return fields
    }

    /// Encodes a finite command response array without Foundation number conversion.
    /// - Parameter snapshots: Complete bounded command field dictionaries.
    /// - Returns: Exact JSON fixture bytes.
    /// - Throws: Serialization bounds errors for intentionally oversized fixtures.
    static func list(_ snapshots: [[String: JSONValue]]) throws -> Data { try JSONValue.array(snapshots.map { .object($0) }).serialized() }

    /// Returns a finite HTTP fixture with generous deterministic per-route rate headers.
    /// - Parameters:
    ///   - bytes: Success or error JSON bytes; empty produces no response stream.
    ///   - status: Explicit status, default 200; no real HTTP operation occurs.
    /// - Returns: Scripted response transferring bounded body ownership to RESTClient.
    /// - Throws: Body validation failures for invalid fixture sizes.
    static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [
            .init(name: "X-RateLimit-Limit", value: "100"), .init(name: "X-RateLimit-Remaining", value: "99"),
            .init(name: "X-RateLimit-Reset-After", value: "1")
        ], body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }

    /// Builds an authenticated-origin normalized context without executing a response or starting timers.
    /// - Parameters:
    ///   - type: Incoming interaction kind; unknown values are retained for unhandled-routing tests.
    ///   - data: Variant-specific exact JSON; nil omits the data field for PING/future kinds.
    ///   - mode: Configured receipt channel, default HTTP; both modes carry the same typed interaction.
    /// - Returns: A context with idle response ownership and inert initial callback mechanics.
    /// - Throws: JSON/schema, admission configuration or context ownership errors.
    static func context(type: Int, data: JSONValue? = nil, mode: InteractionDeliveryMode = .http) throws -> InteractionContext {
        var fields: [String: JSONValue] = ["id": .string("18446744073709551614"),
            "application_id": .string(applicationID.description), "type": .number(try JSONNumber(rawValue: String(type))),
            "token": .string("synthetic-command-token"), "version": .number(try JSONNumber(rawValue: "1")),
            "app_permissions": .string("18446744073709551616"), "entitlements": .array([]),
            "authorizing_integration_owners": .object([:]), "attachment_size_limit": .number(try JSONNumber(rawValue: "10485760"))]
        fields["data"] = data
        let interaction = try Interaction(data: JSONValue.object(fields).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode,
            clock: InteractionClock(ContinuousClock()), sink: InteractionResponseSink(initial: { _, _ in }),
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }

    /// Supplies exact command interaction data with optional nested arguments and a selectable command kind.
    /// - Parameters:
    ///   - name: Command name, default ping; tests can deliberately supply malformed naming/path combinations.
    ///   - type: Exact command type, default slash; future values remain uninterpreted.
    ///   - options: Optional exact argument trees; nil omits the field rather than inventing complete arguments.
    /// - Returns: Complete required command-data fields preserving the supplied trees.
    /// - Throws: Numeric lexeme validation errors for the fixture discriminator.
    static func commandData(name: String = "ping", type: Int = 1, options: [JSONValue]? = nil) throws -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string("18446744073709551615"), "name": .string(name),
            "type": .number(try JSONNumber(rawValue: String(type)))]
        if let options { fields["options"] = .array(options) }
        return .object(fields)
    }
}

/// Independently owned deterministic REST stack; no shared authority, credentials or sockets cross tests.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
struct CommandsRESTHarness {
    let clock: ManualClock
    let transport: ScriptedHTTPTransport
    let coordinator: RateLimitCoordinator<ManualClock>
    let client: RESTClient<ManualClock>

    /// Wires a finite scripted transport to one-attempt REST policy and virtual-clock rate admission.
    /// - Parameter steps: Scripted request inspections and responses consumed in submission order.
    /// - Throws: Script-capacity errors; construction starts no tasks, sleeps or requests.
    init(steps: [ScriptedHTTPTransport.Step]) throws {
        let clock = ManualClock(), transport = try ScriptedHTTPTransport(steps: steps)
        let coordinator = RateLimitCoordinator(clock: clock)
        self.clock = clock; self.transport = transport; self.coordinator = coordinator
        client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
    }
}
