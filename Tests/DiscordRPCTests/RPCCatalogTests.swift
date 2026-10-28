// File: Tests/DiscordRPCTests/RPCCatalogTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
@testable import DiscordRPC
import Foundation
import Testing

/// Offline RPC catalog validation. No test opens a desktop socket, acquires a credential or calls Discord.
@Suite struct RPCCatalogTests {
    /// Exercises every documented request factory and verifies exact command membership and wire identities.
    /// Optional fields, explicit leave-null, subscription identity and large snowflakes retain their semantics.
    @Test func everyCommandHasAConstructibleTypedRequest() throws {
        let maximum = UInt64.max
        let requests = try [
            RPCRequest.authorize(clientID: .init(rawValue: maximum), scopes: ["rpc", "identify"], rpcToken: "one-time", username: "Guest"),
            RPCRequest.authenticate(RPCUserAccessToken(oauthAccessToken: "oauth-secret")),
            RPCRequest.getGuilds(), RPCRequest.getGuild(.init(rawValue: maximum), timeout: 0),
            RPCRequest.getChannel(.init(rawValue: maximum)), RPCRequest.getChannels(.init(rawValue: maximum)),
            RPCRequest.setUserVoiceSettings(userID: .init(rawValue: maximum), pan: RPCPan(left: 0, right: 1), volume: 200, mute: true),
            RPCRequest.selectVoiceChannel(.init(rawValue: maximum), timeout: 1, force: true, userApprovedMove: true, navigate: false),
            RPCRequest.getSelectedVoiceChannel(), RPCRequest.selectTextChannel(nil, timeout: 0),
            RPCRequest.getVoiceSettings(), RPCRequest.setVoiceSettings(RPCVoiceSettingsUpdate()),
            RPCRequest.subscribe(.guildStatus, arguments: ["guild_id": .string(String(maximum))]),
            RPCRequest.unsubscribe(.guildStatus, arguments: ["guild_id": .string(String(maximum))]),
            RPCRequest.setCertifiedDevices([]), RPCRequest.setActivity(processID: 42, activity: RPCActivity(fields: [:])),
            RPCRequest.sendActivityJoinInvite(to: .init(rawValue: maximum)),
            RPCRequest.closeActivityRequest(from: .init(rawValue: maximum))
        ]
        #expect(requests.map(\.command) == RPCCommand.allCases)
        #expect(requests[0].arguments["client_id"] == .string("18446744073709551615"))
        #expect(requests[3].arguments["timeout"] == .number(try JSONNumber(rawValue: "0")))
        #expect(requests[9].arguments["channel_id"] == .null)
        #expect(requests[12].event == .guildStatus)
        #expect(requests[14].arguments == ["devices": .array([])])
        #expect(try RPCRequest.selectVoiceChannel(nil).arguments == ["channel_id": .null])
        #expect(try RPCRequest.getGuild(.init(rawValue: 1)).arguments == ["guild_id": .string("1")])
        #expect(try RPCRequest.setUserVoiceSettings(userID: .init(rawValue: 1)).arguments == ["user_id": .string("1")])
        for request in requests {
            #expect(String(describing: request).contains("redacted"))
            #expect(String(reflecting: request) == request.description)
            #expect(!request.description.contains("oauth-secret"))
            #expect(request.command.approvalRequired)
            #expect(request.command.requiresAuthentication == ![.authorize, .authenticate].contains(request.command))
        }
        #expect(RPCCommand.getVoiceSettings.requiredScopes == ["rpc", "rpc.voice.read"])
        #expect(RPCCommand.setVoiceSettings.requiredScopes == ["rpc", "rpc.voice.write"])
        #expect(RPCCommand.setActivity.requiredScopes == ["rpc", "rpc.activities.write"])
        #expect(RPCCommand.authorize.requiredScopes.isEmpty)
    }

    /// Rejects bot/header/empty credentials, unsafe authorization arguments, invalid exact IDs and bounds.
    /// Error values remain sanitized and credential diagnostics never expose the wrapped access token.
    @Test func authorizationAndRawArgumentsRejectMalformedInputs() throws {
        for token in ["", "Bot credential", "bOt credential", "Bearer secret", "line\nbreak", " space", "nul\u{0}", "del\u{7f}", "unicodeλ", String(repeating: "a", count: 16_385)] {
            #expect(throws: RPCCatalogError.invalidAccessToken) { try RPCUserAccessToken(oauthAccessToken: token) }
        }
        let token = try RPCUserAccessToken(oauthAccessToken: "opaque-oauth-token")
        #expect(token.description == token.debugDescription)
        #expect(!String(reflecting: token).contains("opaque-oauth-token"))
        for scopes in [[], ["bot"], ["rpc voice"], [""]] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.authorize(clientID: .init(rawValue: 1), scopes: scopes) }
        }
        #expect(throws: RPCCatalogError.invalidArguments) {
            try RPCRequest.authorize(clientID: .init(rawValue: 1), scopes: ["messages.read"], rpcToken: "token")
        }
        #expect(throws: RPCCatalogError.invalidArguments) {
            try RPCRequest.authorize(clientID: .init(rawValue: 1), scopes: ["rpc"], username: "")
        }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.authorize(clientID: .init(rawValue: 0), scopes: ["rpc"]) }
        for value in [JSONValue.null, .number(try JSONNumber(rawValue: "1")), .string("0"), .string("18446744073709551616"), .string("-1")] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest(command: .getChannel, arguments: ["channel_id": value]) }
        }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.getGuild(.init(rawValue: 1), timeout: -1) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.selectTextChannel(.init(rawValue: 0)) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.selectVoiceChannel(.init(rawValue: 2), force: true) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest(command: .selectVoiceChannel, arguments: ["channel_id": .string("2"), "force": .bool(true)]) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest(command: .getGuilds, event: .guildCreate) }
        #expect(throws: RPCCatalogError.invalidAccessToken) { try RPCRequest(command: .authenticate, arguments: ["access_token": .string("Bot secret")]) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try RPCRequest(command: .getGuilds, arguments: ["x": .string("oversized")], limits: .init(maximumBytes: 2)) }
    }

    /// Covers known channel/guild subscription requirements, unsolicited events and future-name compatibility.
    @Test func subscriptionIdentityAndMetadataRemainExplicit() throws {
        #expect(RPCEventName.documented.count == 25)
        #expect(Set(RPCEventName.documented).count == 25)
        #expect(RPCEventName.notificationCreate.requiredScopes == ["rpc.notifications.read"])
        #expect(RPCEventName.relationshipUpdate.requiredScopes == ["relationships.read"])
        #expect(RPCEventName.messageCreate.requiredScopes == ["messages.read"])
        #expect(RPCEventName.voiceStateUpdate.requiredScopes == ["rpc.voice.read"])
        #expect(RPCEventName.ready.requiredScopes.isEmpty)
        for event in [RPCEventName.ready, .error, .init(rawValue: ""), .init(rawValue: String(repeating: "A", count: 129)), .init(rawValue: "BAD\nEVENT")] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.subscribe(event) }
        }
        for event in [RPCEventName.voiceStateCreate, .voiceStateUpdate, .voiceStateDelete, .messageCreate, .messageUpdate, .messageDelete, .speakingStart, .speakingStop] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.subscribe(event) }
            let args: [String: JSONValue] = ["channel_id": .string("18446744073709551615")]
            #expect(try RPCRequest.subscribe(event, arguments: args).arguments == args)
            #expect(try RPCRequest.unsubscribe(event, arguments: args).event == event)
        }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.subscribe(.guildStatus) }
        let future = RPCEventName(rawValue: "FUTURE_EVENT")
        #expect(try RPCRequest.subscribe(future, arguments: ["future": .bool(true)]).event == future)
    }

    /// Exercises exact decimal range boundaries without silently rounding tiny overflows to valid values.
    /// Also covers nonfinite convenience inputs, partial voice updates and read-only device protection.
    @Test func voiceControlsValidateExactRangesAndReadOnlyFields() throws {
        for raw in ["0", "-0", "1.000000000000000000000000000", "1e-1000000", "0e999999999999999999999"] {
            let pan = try RPCPan(data: Data("{\"left\":\(raw),\"right\":1}".utf8))
            #expect(pan.left.rawValue == raw)
            #expect(pan.right.rawValue == "1")
        }
        for raw in ["-0.000000000000000000000001", "1.000000000000000000000001", "1e1000000", "1e999999999999999999999"] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCPan(data: Data("{\"left\":\(raw),\"right\":0}".utf8)) }
        }
        for input in [Double.infinity, -.infinity, .nan, -0.01, 1.01] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCPan(left: input, right: 0.5) }
        }
        for volume in [-1, 201] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.setUserVoiceSettings(userID: .init(rawValue: 1), volume: volume) }
        }
        let full = try catalogJSON(#"{"input":{"device_id":"default","volume":100},"output":{"volume":200},"mode":{"type":"PUSH_TO_TALK","auto_threshold":false,"threshold":-100,"delay":2000,"shortcut":[{"type":3,"code":2,"name":"button"}]},"automatic_gain_control":true,"echo_cancellation":true,"noise_suppression":false,"qos":true,"silence_warning":false,"mute":true,"deaf":false,"future":1e1000}"#)
        guard case .object(let fields) = full else { Issue.record("Expected object"); return }
        let patch = try RPCVoiceSettingsUpdate(fields: fields)
        #expect(patch.rawFields == fields)
        #expect(patch.description == patch.debugDescription)
        for text in [
            #"{"input":{"volume":100.00000000000000000001}}"#,
            #"{"output":{"volume":200.00000000000000000001}}"#,
            #"{"mode":{"threshold":-100.00000000000000001}}"#,
            #"{"mode":{"delay":2000.00000000000000001}}"#,
            #"{"mode":{"type":"FUTURE"}}"#, #"{"mode":{"shortcut":[{"type":4,"code":0,"name":"x"}]}}"#,
            #"{"input":{"available_devices":[]}}"#, #"{"mute":null}"#, #"{"output":{"device_id":42}}"#
        ] {
            guard case .object(let invalid) = try catalogJSON(text) else { continue }
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCVoiceSettingsUpdate(fields: invalid) }
        }
    }

    /// Validates outgoing activity compatibility and certified-device shape without acquiring hardware access.
    @Test func activityAndCertifiedDeviceArgumentsFollowDocumentedContracts() throws {
        for type in [0, 2, 3, 5] {
            let activity = try RPCActivity(fields: ["type": rpcNumber(type), "secrets": .object(["join": .string("secret")])])
            #expect(activity.description == activity.debugDescription)
            #expect(!activity.description.contains("secret"))
            #expect(try RPCRequest.setActivity(processID: 1, activity: activity).arguments["activity"] == .object(activity.rawFields))
        }
        for type in [-1, 1, 4, 6] {
            #expect(throws: RPCCatalogError.invalidArguments) { try RPCActivity(fields: ["type": rpcNumber(type)]) }
        }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCActivity(fields: ["party": .array([])]) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest.setActivity(processID: 0, activity: RPCActivity(fields: [:])) }
        #expect(throws: RPCCatalogError.invalidArguments) { try RPCRequest(command: .setActivity, arguments: ["pid": rpcNumber(1), "activity": .null]) }
        let device = try RPCCertifiedDevice(data: Data(#"{"type":"audioinput","id":"aafc2003-da0e-42a3-b982-6a17a2812510","vendor":{"name":"Vendor","url":"https://example.com"},"model":{"name":"Model","url":"https://example.com/model"},"related":["aafc2003-da0e-42a3-b982-6a17a2819999"],"echo_cancellation":true,"noise_suppression":false,"automatic_gain_control":true,"hardware_mute":false}"#.utf8))
        #expect(device.type == "audioinput")
        #expect(device.hardwareMute == .value(false))
        #expect(device.related.count == 1)
        #expect(try RPCRequest.setCertifiedDevices([device]).arguments["devices"] == .array([.object(device.rawFields)]))
        for nativeID in ["{0.0.1.00000000}.{6cff2b76-44a8-46b9-b528-262ad8609d9f}", "Built-in Microphone", "Microphone λ"] {
            var fields = device.rawFields
            fields["id"] = .string(nativeID)
            fields["related"] = .array([.string(nativeID)])
            let nativeDevice = try RPCCertifiedDevice(value: .object(fields))
            #expect(nativeDevice.id == nativeID)
            #expect(nativeDevice.related == [nativeID])
            #expect(try RPCRequest.setCertifiedDevices([nativeDevice]).arguments["devices"] == .array([.object(fields)]))
        }
        for (key, value) in [("type", JSONValue.string("audiooutput")), ("id", .string("")), ("id", .string("bad\nname")), ("id", .string(String(repeating: "a", count: 16_385))), ("related", .array([.string("")])), ("vendor", .object(["name": .string(""), "url": .string("x")]))] {
            var fields = device.rawFields
            fields[key] = value
            #expect(throws: (any Error).self) { try RPCCertifiedDevice(value: .object(fields)) }
        }
    }

    /// Decodes every documented event with realistic local fixtures, exact future numbers and sanitized output.
    /// Malformed known objects reject wrong types while unknown event schemas remain available verbatim.
    @Test func allDocumentedEventsHaveTypedProjections() throws {
        let fixtures = try catalogEventFixtures()
        #expect(Set(fixtures.keys) == Set(RPCEventName.documented))
        for (name, value) in fixtures {
            let first = try RPCEventPayload.decode(name: name, data: value)
            let second = try RPCEventPayload.decode(name: name, bytes: value.serialized())
            #expect(first == second)
            if case .unknown = first { Issue.record("Documented event used unknown fallback") }
            #expect(first.description == first.debugDescription)
            #expect(!first.description.contains("confidential"))
            #expect(throws: (any Error).self) { try RPCEventPayload.decode(name: name, data: .null) }
        }
        let unknown = try catalogJSON(#"[1.2300,1e1000,{"credential":"confidential"}]"#)
        let name = RPCEventName(rawValue: "FUTURE_EVENT")
        #expect(try RPCEventPayload.decode(name: name, data: unknown) == .unknown(name: name, data: unknown))
        if case .activityJoin(let event) = try RPCEventPayload.decode(name: .activityJoin, data: #require(fixtures[.activityJoin])) {
            #expect(event.secret == "confidential")
            #expect(event.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300e999")))
        } else { Issue.record("Expected typed activity join") }
        if case .voiceConnectionStatus(let status) = try RPCEventPayload.decode(name: .voiceConnectionStatus, data: #require(fixtures[.voiceConnectionStatus])) {
            #expect(status.pings.map(\.rawValue) == ["20", "13.3700"])
            #expect(status.averagePing.rawValue == "13.37")
            #expect(status.state == "FUTURE_STATE")
        } else { Issue.record("Expected voice telemetry") }
        if case .message(let eventName, let event) = try RPCEventPayload.decode(name: .messageDelete, data: #require(fixtures[.messageDelete])) {
            #expect(eventName == .messageDelete)
            #expect(event.message.id.rawValue == UInt64.max)
            #expect(event.message.content == .absent)
        } else { Issue.record("Expected deletion projection") }
    }

    /// Exercises the successful response decoder for every command and distinguishes documented nullable data.
    /// Unpublished activity/invite success schemas remain exact raw JSON, while ERROR is a separate envelope.
    @Test func successfulResponsesRetainSchemaAndNullableDistinctions() throws {
        let events = try catalogEventFixtures()
        let user = try catalogJSON(#"{"id":"18446744073709551615","avatar":null}"#)
        let application = try catalogJSON(#"{"id":"1","description":"app","icon":null,"rpc_origins":["https://localhost"],"name":"App"}"#)
        let authentication: JSONValue = .object(["user": user, "application": application, "scopes": .array([.string("rpc")]), "expires": .string("2026-10-18T00:00:00Z")])
        for command in RPCCommand.allCases {
            let value: JSONValue
            switch command {
            case .authorize: value = .object(["code": .string("confidential")])
            case .authenticate: value = authentication
            case .getGuilds: value = .object(["guilds": .array([try #require(events[.guildCreate])])])
            case .getGuild: value = try #require(events[.guildCreate])
            case .getChannel: value = try #require(events[.channelCreate])
            case .getChannels: value = .object(["channels": .array([try #require(events[.channelCreate])])])
            case .setUserVoiceSettings: value = try catalogJSON(#"{"user_id":"1","pan":{"left":0.5,"right":0.5},"volume":100,"mute":false}"#)
            case .getVoiceSettings, .setVoiceSettings: value = try #require(events[.voiceSettingsUpdate])
            case .subscribe, .unsubscribe: value = .object(["evt": .string("FUTURE")])
            default: value = .null
            }
            let decoded = try RPCResponsePayload.decode(command: command, data: value)
            #expect(decoded.description == decoded.debugDescription)
            #expect(!decoded.description.contains("confidential"))
            #expect(try RPCResponsePayload.decode(command: command, data: value) == decoded)
        }
        #expect(try RPCResponsePayload.decode(command: .selectTextChannel, data: .null) == .channel(.null))
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCResponsePayload.decode(command: .getChannel, data: .null) }
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCResponsePayload.decode(command: .setCertifiedDevices, data: .object([:])) }
        #expect(try RPCResponsePayload.decode(command: .getGuilds, data: .object(["guilds": .array([])])) == .guilds(RPCGuildList(value: .object(["guilds": .array([])]))))
        let futureResult = JSONValue.number(try JSONNumber(rawValue: "1e1000"))
        #expect(try RPCResponsePayload.decode(command: .setActivity, data: futureResult) == .unmodeled(command: .setActivity, data: futureResult))
    }

    /// Verifies missing/null/invalid field distinctions, exact snowflakes, nested payload validation and parser limits.
    @Test func projectionPresenceUnknownFieldsAndBoundsAreLossless() throws {
        let user = try RPCUser(data: Data(#"{"id":"18446744073709551615","global_name":null,"avatar":null,"flags":18446744073709551615,"future":1e1000}"#.utf8))
        #expect(user.id.rawValue == UInt64.max)
        #expect(user.username == .absent)
        #expect(user.globalName == .null)
        #expect(user.flags == .value(try JSONNumber(rawValue: "18446744073709551615")))
        #expect(user.rawFields["future"] == .number(try JSONNumber(rawValue: "1e1000")))
        #expect(user.description == user.debugDescription)
        for text in [#"{}"#, #"{"id":1}"#, #"{"id":"0"}"#, #"{"id":"18446744073709551616"}"#, #"{"id":"1","username":null}"#, #"{"id":"1","bot":1}"#, #"{"id":"1","premium_type":1.0}"#] {
            #expect(throws: RPCCatalogError.invalidPayload) { try RPCUser(data: Data(text.utf8)) }
        }
        #expect(try RPCChannelSelection(data: Data(#"{"channel_id":null,"guild_id":null}"#.utf8)).channelID == .null)
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCChannelSelection(data: Data(#"{"channel_id":null}"#.utf8)) }
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCMessage(data: Data(#"{"id":"1","mentions":[42]}"#.utf8)) }
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCUser(data: Data(#"{"id":"1","avatar_decoration_data":true}"#.utf8)) }
        #expect(throws: RPCCatalogError.invalidPayload) { try RPCVoiceSettings(data: Data(#"{"input":{"available_devices":[{"id":"default"}]}}"#.utf8)) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try RPCUser(data: Data(#"{"id":"1"}"#.utf8), limits: .init(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try RPCEventPayload.decode(name: .init(rawValue: "FUTURE"), bytes: Data("[1,2]".utf8), limits: .init(maximumNodes: 1)) }
        #expect(throws: (any Error).self) { try RPCUser(data: Data(#"{"id":"1","id":"2"}"#.utf8)) }
    }

    /// Verifies default protocol and standalone type mirrors prevent recursive diagnostic secret leakage.
    /// Raw credentials, authorization codes, nested activity secrets and future JSON remain explicitly
    /// accessible through their APIs, while String/debug/Mirror/dump expose only a constant redaction child.
    @Test func reflectiveDiagnosticsConcealSecretsAndPayloadTrees() throws {
        let secret = "catalog-reflection-confidential-sentinel"
        let token = try RPCUserAccessToken(oauthAccessToken: secret)
        let authorization = try RPCAuthorization(value: .object(["code": .string(secret)]))
        let request = try RPCRequest.authenticate(token)
        let rawRequest = try RPCRequest(command: .getGuilds, arguments: ["future_secret": .string(secret)])
        let activity = try RPCActivity(fields: ["secrets": .object(["join": .string(secret)])])
        let settings = try RPCVoiceSettingsUpdate(fields: ["input": .object(["device_id": .string(secret)])])
        let event = try RPCEventPayload.decode(name: .activityJoin, data: .object(["secret": .string(secret)]))
        let futureEvent = RPCEventPayload.unknown(name: .init(rawValue: "FUTURE"), data: .array([.string(secret)]))
        let response = RPCResponsePayload.authorized(authorization)
        let futureResponse = RPCResponsePayload.unmodeled(command: .setActivity, data: .string(secret))
        let values: [Any] = [token, authorization, request, rawRequest, activity, settings, event, futureEvent, response, futureResponse]
        for value in values {
            let mirror = Mirror(reflecting: value)
            #expect(mirror.children.map(\.label) == ["redacted"])
            #expect(mirror.children.first?.value as? Bool == true)
            #expect(mirror.descendant("rawFields") == nil)
            #expect(!String(describing: value).contains(secret))
            #expect(!String(reflecting: value).contains(secret))
            var output = ""
            dump(value, to: &output)
            #expect(!output.contains(secret))
            #expect(output.contains("redacted"))
        }
        #expect(authorization.code == secret)
        #expect(request.arguments["access_token"] == .string(secret))
        #expect(activity.rawFields["secrets"] == .object(["join": .string(secret)]))
    }
}

/// Parses bounded inline fixture data through the production exact-number path.
/// - Parameter text: Complete deterministic JSON fixture; never a credential or live-service response.
/// - Returns: Lossless JSON tree suitable for event and request assertions.
/// - Throws: JSON syntax or default-bound errors, which indicate an invalid local fixture.
private func catalogJSON(_ text: String) throws -> JSONValue { try JSONValue.parse(text) }

/// Builds one realistic deterministic fixture for every documented RPC event, including shared family schemas.
/// - Returns: Exact event-name map with large IDs, nullable values, future variants and unknown numeric lexemes.
/// - Throws: JSON fixture parsing errors; no time, network, desktop or hardware dependencies are used.
private func catalogEventFixtures() throws -> [RPCEventName: JSONValue] {
    let user = try catalogJSON(#"{"id":"18446744073709551615","username":"User","discriminator":"0","global_name":null,"avatar":null,"avatar_decoration_data":null,"bot":false,"flags":64,"premium_type":0}"#)
    let guild = try catalogJSON(#"{"id":"1","name":"Guild","icon_url":null,"members":[]}"#)
    let channel = try catalogJSON(#"{"id":"2","guild_id":"1","name":"Channel","type":99,"topic":null,"bitrate":64000,"user_limit":0,"position":0,"voice_states":[],"messages":[]}"#)
    let message: JSONValue = .object(["id": .string("18446744073709551615"), "content": .string("confidential"), "author": user,
        "blocked": .bool(false), "content_parsed": .array([]), "author_color": .null, "timestamp": .string("2026-10-17T00:00:00Z"),
        "edited_timestamp": .null, "tts": .bool(false), "mentions": .array([user]), "mention_roles": .array([.string("1")]),
        "mention_everyone": .bool(false), "embeds": .array([]), "attachments": .array([]), "type": try rpcNumber(0), "pinned": .bool(false)])
    let voiceState: JSONValue = .object(["voice_state": try catalogJSON(#"{"mute":false,"deaf":false,"self_mute":true,"self_deaf":false,"suppress":false}"#),
        "user": user, "nick": .null, "volume": try rpcNumber(110), "mute": .bool(false), "pan": try catalogJSON(#"{"left":1.0,"right":0.5}"#)])
    let settings = try catalogJSON(#"{"input":{"device_id":"default","volume":49.803921580314636,"available_devices":[{"id":"default","name":"Default"}]},"output":{"device_id":"default","volume":93.00000071525574,"available_devices":[]},"mode":{"type":"FUTURE_MODE","auto_threshold":true,"threshold":-46.92622950819673,"shortcut":[{"type":99,"code":12,"name":"key"}],"delay":98.36065573770492},"automatic_gain_control":false,"echo_cancellation":false,"noise_suppression":true,"qos":true,"silence_warning":false,"mute":true,"deaf":false}"#)
    let activity = try catalogJSON(#"{"application_id":"1","name":"Game","type":99,"state":"State","state_url":"https://example.com","details":"Details","details_url":"https://example.com","timestamps":{},"assets":{},"party":{"size":[1,2]},"secrets":{"join":"confidential"},"instance":true,"buttons":[]}"#)
    let entitlement = try catalogJSON(#"{"entitlement":{"id":"1","sku_id":"2","application_id":"3","user_id":"18446744073709551615","type":99,"deleted":false,"starts_at":null,"ends_at":"2026-10-18T00:00:00Z","guild_id":null,"consumed":false}}"#)
    var result: [RPCEventName: JSONValue] = [
        .ready: .object(["v": try rpcNumber(1), "config": try catalogJSON(#"{"cdn_host":"cdn.discordapp.com","api_endpoint":"//discord.com/api","environment":"production"}"#), "user": user]),
        .error: try catalogJSON(#"{"code":4006,"message":"confidential"}"#),
        .guildStatus: .object(["guild": guild, "online": try rpcNumber(0)]), .guildCreate: guild, .channelCreate: channel,
        .voiceChannelSelect: try catalogJSON(#"{"channel_id":null,"guild_id":null}"#), .voiceSettingsUpdate: settings,
        .voiceConnectionStatus: try catalogJSON(#"{"state":"FUTURE_STATE","hostname":"voice.example.com","pings":[20,13.3700],"average_ping":13.37,"last_ping":20}"#),
        .notificationCreate: .object(["channel_id": .string("2"), "message": message, "icon_url": .string("https://example.com"), "title": .string("Title"), "body": .string("confidential")]),
        .activityJoin: .object(["secret": .string("confidential")]), .activitySpectate: .object(["secret": .string("confidential")]),
        .activityJoinRequest: .object(["user": user]), .activityInvite: .object(["type": try rpcNumber(99), "user": user, "activity": activity, "channel_id": .string("2"), "message_id": .string("3")]),
        .currentUserUpdate: user, .relationshipUpdate: .object(["type": try rpcNumber(99), "user": user, "presence": .object(["status": .string("FUTURE_STATUS"), "activity": activity])]),
        .entitlementCreate: entitlement, .entitlementDelete: entitlement
    ]
    for event in [RPCEventName.voiceStateCreate, .voiceStateUpdate, .voiceStateDelete] { result[event] = voiceState }
    for event in [RPCEventName.messageCreate, .messageUpdate] { result[event] = .object(["channel_id": .string("2"), "message": message]) }
    result[.messageDelete] = .object(["channel_id": .string("2"), "message": .object(["id": .string("18446744073709551615")])])
    for event in [RPCEventName.speakingStart, .speakingStop] { result[event] = .object(["user_id": .string("18446744073709551615")]) }
    for (event, value) in result {
        guard case .object(var fields) = value else { continue }
        fields["future"] = .number(try JSONNumber(rawValue: "1.2300e999"))
        result[event] = .object(fields)
    }
    return result
}
