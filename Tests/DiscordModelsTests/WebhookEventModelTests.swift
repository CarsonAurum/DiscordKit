import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises independent webhook envelopes, all written names and deliberately partial SDK payloads.
@Suite struct WebhookEventModelTests {
    /// Minimal PING uses type zero and preserves independent versioning, exact IDs and unknown numbers.
    /// - Throws: Unexpected parse errors fail the test.
    @Test func pingAndUnknownEnvelope() throws {
        let input = Data(#"{"version":1,"application_id":"18446744073709551615","type":0,"future":1.2300}"#.utf8)
        let ping = try WebhookEventEnvelope(data: input)
        #expect(ping.type.knownValue == .ping && ping.version == 1)
        #expect(ping.applicationID.rawValue == .max && ping.event == .absent)
        #expect(try ping.jsonValue() == JSONValue.parse(input))
        let future = try WebhookEventEnvelope(data: Data(#"{"version":99,"application_id":"1","type":99}"#.utf8))
        #expect(future.version == 99 && future.type.knownValue == nil && future.event == .absent)
        let futureBody = try WebhookEventEnvelope(data: Data(#"{"version":99,"application_id":"1","type":1,"event":["future"]}"#.utf8))
        #expect(futureBody.event == .absent && futureBody.rawFields["event"] == .array([.string("future")]))
        #expect(!String(reflecting: ping).contains("1.2300"))
        #expect(ping.customMirror.children.count == 1)
    }

    /// Every documented name selects its own schema, including unavailable Quest enrollment as unknown.
    /// - Parameter kind: A current written event type; no live Discord request is needed.
    /// - Throws: Unexpected fixture or schema errors fail the test.
    @Test(arguments: WebhookEventType.allCases) func everyWrittenEvent(_ kind: WebhookEventType) throws {
        let payload: JSONValue
        switch kind {
        case .applicationAuthorized:
            payload = .object(["user": try Self.user(), "scopes": .array([.string("applications.commands")]),
                "integration_type": .number(try JSONNumber(rawValue: "99")), "guild": .object(["id": .string("7")])])
        case .applicationDeauthorized: payload = .object(["user": try Self.user()])
        case .entitlementCreate, .entitlementUpdate, .entitlementDelete:
            payload = try JSONValue.parse(Data(#"{"id":"18446744073709551615","sku_id":"2","application_id":"1","type":99,"deleted":true,"consumed":false}"#.utf8))
        case .lobbyMessageCreate, .lobbyMessageUpdate, .lobbyMessageDelete:
            payload = .object(["id": .string("18446744073709551615"), "lobby_id": .string("9007199254740993")])
        case .gameDirectMessageCreate, .gameDirectMessageUpdate, .gameDirectMessageDelete:
            payload = .object(["id": .string("18446744073709551615"), "channel": .object(["recipients": .array([])])])
        case .questUserEnrollment: payload = .object(["future": .string("private")])
        }
        let event = try WebhookEvent(data: Self.event(kind.rawValue, payload: payload))
        #expect(event.type.knownValue == kind)
        #expect(event.timestamp == "2024-10-18T14:42:53.064834")
        guard case .value(let projected) = event.data else { Issue.record("Expected event data"); return }
        switch projected {
        case .applicationAuthorized(let value):
            #expect(value.user.id.rawValue == .max && value.integrationType == .value(.init(rawValue: 99)))
            #expect(value.scopes == .value(["applications.commands"]))
            #expect(value.guild != .absent)
        case .applicationDeauthorized(let value): #expect(value.scopes == .absent && value.user.id.rawValue == .max)
        case .entitlement(let value): #expect(value.id.rawValue == .max && value.deleted && value.type.knownValue == nil)
        case .lobbyMessage(let value):
            #expect(value.id.rawValue == .max && value.applicationID == .absent && value.content == .absent)
        case .gameDirectMessage(let value): #expect(value.id.rawValue == .max && value.channel != .absent)
        case .unknown(let value): #expect(value == payload)
        }
        #expect(!String(describing: projected).contains("private"))
        #expect(projected.debugDescription == projected.description && projected.customMirror.children.count == 1)
    }

    /// Rich social snapshots preserve optional/null fields, future message kinds and unknown child objects.
    /// - Throws: Unexpected fixture/projection errors fail the test.
    @Test func socialFieldsAndExactRoundTrip() throws {
        let bytes = Data(#"{"id":"18446744073709551615","type":99,"content":"secret","lobby_id":"2","channel_id":"3","author":{"id":"4","username":"u","discriminator":"0","global_name":null,"avatar":null},"flags":18446744073709551615,"application_id":"5","channel":{"id":"3","recipients":[]},"metadata":null,"timestamp":"2026-10-17T12:00:00Z","edited_timestamp":null,"activity":{"future":1.2300}}"#.utf8)
        let value = try WebhookMessageData(data: bytes)
        #expect(value.id.rawValue == .max && value.type == .value(.init(rawValue: 99)))
        #expect(value.content == .value("secret") && value.lobbyID == .value(.init(rawValue: 2)))
        #expect(value.channelID == .value(.init(rawValue: 3)) && value.author != .absent)
        #expect(value.flags == .value(.max) && value.applicationID == .value(.init(rawValue: 5)))
        #expect(value.channel != .absent && value.metadata == .null && value.editedTimestamp == .null)
        #expect(value.timestamp == .value("2026-10-17T12:00:00Z"))
        #expect(try value.jsonValue() == JSONValue.parse(bytes))
        #expect(!String(reflecting: value).contains("secret"))
        let metadata = try WebhookMessageData(data: Data(#"{"id":"1","metadata":{"key":"value"},"edited_timestamp":"x"}"#.utf8))
        #expect(metadata.metadata == .value(["key": "value"]) && metadata.editedTimestamp == .value("x"))
    }

    /// Unknown names retain exact arbitrary nested objects and omission, without inventing a known schema.
    /// - Throws: Unexpected fixture/projection errors fail the test.
    @Test func unknownEventsAndPresence() throws {
        let payload = try JSONValue.parse(Data(#"{"user":false,"number":12345678901234567890.123456789,"nested":[null]}"#.utf8))
        let event = try WebhookEvent(data: Self.event("FUTURE_EVENT", payload: payload))
        #expect(event.type.knownValue == nil && event.data == .value(.unknown(payload)))
        for kind in ["FUTURE_EVENT", "QUEST_USER_ENROLLMENT"] {
            let absent = try WebhookEvent(data: Self.event(kind, payload: nil))
            #expect(absent.data == .absent)
        }
        let envelope = try WebhookEventEnvelope(data: Data(#"{"version":1,"application_id":"1","type":1,"event":{"type":"FUTURE_EVENT","timestamp":"2026-10-17T00:00:00Z"}}"#.utf8))
        #expect(envelope.type.knownValue == .event && envelope.event != .absent)
    }

    /// Direct authorization projection preserves missing metadata and validates each optional known field.
    /// - Throws: Unexpected constant-fixture setup or valid projection errors fail the test.
    @Test func authorizationProjection() throws {
        let minimal = try WebhookApplicationAuthorization(data: JSONValue.object(["user": Self.user()]).serialized())
        #expect(minimal.scopes == .absent && minimal.integrationType == .absent && minimal.guild == .absent)
        for (key, invalid) in [("user", JSONValue.null), ("scopes", .null), ("scopes", .array([.bool(false)])),
                               ("integration_type", .string("0")), ("guild", .array([]))] {
            var fields: [String: JSONValue] = ["user": try Self.user()]
            fields[key] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try WebhookApplicationAuthorization(data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Required keys, exact discriminators, nonnull schemas and known child types fail without payload leakage.
    /// - Parameter input: Independently malformed envelope fixture.
    /// - Throws: Unexpected fixture setup errors fail the test.
    @Test(arguments: [#"{}"#, #"[]"#, #"{"version":1.0,"application_id":"1","type":0}"#,
        #"{"version":1,"application_id":"18446744073709551616","type":0}"#,
        #"{"version":1,"application_id":"1","type":1}"#,
        #"{"version":1,"application_id":"1","type":1,"event":null}"#])
    func invalidEnvelope(_ input: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookEventEnvelope(data: Data(input.utf8)) }
    }

    /// Event-specific malformed payloads reject before durable admission, while whole-document bounds include unknowns.
    /// - Throws: Unexpected fixture setup errors fail the test.
    @Test func invalidEventsAndLimits() throws {
        for (kind, payload) in [("APPLICATION_AUTHORIZED", JSONValue.object(["user": try Self.user()])),
             ("APPLICATION_DEAUTHORIZED", .object(["user": .null])), ("ENTITLEMENT_CREATE", .object([:])),
             ("LOBBY_MESSAGE_DELETE", .object(["id": .string("1")])),
             ("GAME_DIRECT_MESSAGE_UPDATE", .object(["id": .string("1"), "content": .bool(false)])),
             ("FUTURE_EVENT", .array([])), ("FUTURE_EVENT", .null)] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookEvent(data: Self.event(kind, payload: payload)) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookEvent(data: Self.event("ENTITLEMENT_UPDATE", payload: nil)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookEvent(data: Data(#"{"type":"FUTURE","timestamp":""}"#.utf8)) }
        let valid = try Self.event("FUTURE_EVENT", payload: .object(["nested": .array([.bool(true)])]))
        #expect(throws: JSONValueError.maximumBytesExceeded) { try WebhookEvent(data: valid, limits: .init(maximumBytes: 5)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try WebhookEvent(data: valid, limits: .init(maximumNodes: 2)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try WebhookEvent(data: valid, limits: .init(maximumDepth: 1)) }
        for data in [#"{"id":"1","flags":-1}"#, #"{"id":"1","author":{}}"#, #"{"id":"1","metadata":{"k":false}}"#,
                     #"{"id":"1","type":1.0}"#, #"{"id":"1","channel_id":null}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try WebhookMessageData(data: Data(data.utf8)) }
        }
    }

    /// Supplies an independently authored complete User required by authorization snapshots.
    /// - Returns: Exact JSON with maximum ID and explicit nullable baseline fields.
    /// - Throws: Unexpected constant-fixture syntax errors fail the caller.
    private static func user() throws -> JSONValue {
        try JSONValue.parse(Data(#"{"id":"18446744073709551615","username":"private","discriminator":"0","global_name":null,"avatar":null}"#.utf8))
    }

    /// Builds one event-body fixture independently of the production encoder/projector.
    /// - Parameters:
    ///   - kind: Exact known or future event name.
    ///   - payload: Optional object; nil intentionally omits data.
    /// - Returns: Complete event-body JSON, preserving the offset-free official example timestamp profile.
    /// - Throws: Safe fixture serialization errors fail the caller.
    private static func event(_ kind: String, payload: JSONValue?) throws -> Data {
        var fields: [String: JSONValue] = ["type": .string(kind), "timestamp": .string("2024-10-18T14:42:53.064834")]
        if let payload { fields["data"] = payload }
        return try JSONValue.object(fields).serialized()
    }
}
