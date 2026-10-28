// File: Tests/DiscordActivitiesTests/ActivityClientTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordActivities

/// Authenticated simulated adapter with explicit frame/write barriers and no live browser or Discord calls.
actor ActivityPeer: ActivityTransport {
    private var incoming: [Data] = []
    private var received: CheckedContinuation<Data?, Never>?
    private var sent: [Data] = []
    private var observer: CheckedContinuation<Data, Never>?
    private var ended = false
    private var holdingWrites = false
    private var heldWrite: CheckedContinuation<Void, Never>?
    private let autoReady: Bool
    private let failSend: Bool
    private(set) var closes = 0

    /// Creates an inert test adapter with configurable handshake response/write failure.
    /// - Parameters:
    ///   - autoReady: Injects a valid READY only after observing the explicit handshake.
    ///   - failSend: Throws a sanitized failure on any write.
    init(autoReady: Bool = true, failSend: Bool = false) { self.autoReady = autoReady; self.failSend = failSend }

    /// Records one complete tuple and optionally simulates host READY, preserving actual admission order.
    /// - Parameter data: Client's complete outgoing bytes.
    /// - Throws: Configured failure, closure, or malformed fixture tuple.
    func send(_ data: Data) async throws {
        guard !ended, !failSend else { throw ActivityFailure.closed }
        let kind: String
        if case .array(let tuple) = try? JSONValue.parse(data), tuple.first == .number(try JSONNumber(rawValue: "1")) {
            kind = "command"
        } else { kind = "control" }
        DiscordLog.makeLogger("activities.test_transport").trace("Synthetic transport send entered", metadata: [
            "dk.event": "test.activities.transport.send", "test.kind": .string(kind)])
        if let observer { self.observer = nil; observer.resume(returning: data) } else { sent.append(data) }
        if holdingWrites { await withCheckedContinuation { heldWrite = $0 } }
        if autoReady, case .array(let tuple) = try JSONValue.parse(data), tuple[0] == .number(try JSONNumber(rawValue: "0")) {
            push("[1,{\"cmd\":\"DISPATCH\",\"evt\":\"READY\",\"nonce\":null,\"data\":{\"v\":1,\"config\":{\"api_endpoint\":\"//discord.com/api\",\"environment\":\"production\"}}}]")
        }
    }

    /// Parks command writes after observation so requests share one existing ordered writer.
    func holdWrites() { holdingWrites = true }

    /// Releases the one parked writer and stops parking subsequent sends.
    func releaseWrites() { holdingWrites = false; heldWrite?.resume(); heldWrite = nil }

    /// Returns one scripted tuple or waits for explicit input/close; the client owns the sole reader.
    /// - Returns: Scripted data, or nil on terminal close.
    func receive() async throws -> Data? {
        if !incoming.isEmpty { return incoming.removeFirst() }
        if ended { return nil }
        return await withCheckedContinuation { received = $0 }
    }

    /// Supplies one trusted-origin/source tuple after adapter authentication has already occurred.
    /// - Parameter json: Complete synthetic host wire text; malformed variants exercise the client parser.
    func push(_ json: String) {
        let data = Data(json.utf8)
        if let received { self.received = nil; received.resume(returning: data) } else { incoming.append(data) }
    }

    /// Waits for one actual client write without a timing sleep.
    /// - Returns: Next complete outgoing tuple.
    func nextSent() async -> Data {
        if !sent.isEmpty { return sent.removeFirst() }
        return await withCheckedContinuation { observer = $0 }
    }

    /// Echoes one request's nonce/command with explicit data or an optional malicious mismatch/error.
    /// - Parameters:
    ///   - request: Previously observed tuple bytes.
    ///   - value: Response data; defaults to an empty object.
    ///   - command: Optional alternate command for strict correlation regression tests.
    ///   - event: Optional ERROR or event correlation field.
    /// - Throws: Malformed fixture or JSON serialization failure.
    func reply(_ request: Data, value: JSONValue = .object([:]), command: String? = nil, event: String? = nil) throws {
        guard case .array(let tuple) = try JSONValue.parse(request), case .object(let fields) = tuple[1] else { throw ActivityFailure.invalidFrame }
        var response: [String: JSONValue] = ["cmd": command.map(JSONValue.string) ?? fields["cmd"]!, "nonce": fields["nonce"]!, "data": value, "evt": .null]
        if value == .object([:]), let eventName = fields["evt"] { response["data"] = .object(["evt": eventName]) }
        if let event { response["evt"] = .string(event) }
        let bytes = try JSONValue.array([.number(JSONNumber(rawValue: "1")), .object(response)]).serialized()
        push(String(decoding: bytes, as: UTF8.self))
    }

    /// Releases read ownership exactly once and records cleanup for repeated-close assertions.
    func close() async {
        guard !ended else { return }; ended = true; closes += 1
        received?.resume(returning: nil); received = nil; incoming.removeAll()
    }
}

/// Deterministic Activity protocol, capacity, lifecycle, independent-cancellation and subscription tests.
@Suite("Activity client lifecycle")
struct ActivityClientTests {
    /// Constructs fixed host context with a deliberately large application identifier and no network activity.
    /// - Returns: Validated iframe parameters with all optional context omitted.
    /// - Throws: Fixture validation failure.
    static func host() throws -> ActivityHostParameters {
        try ActivityHostParameters(url: #require(URL(string: "https://123.discordsays.com/?frame_id=f&instance_id=i&platform=desktop")))
    }

    /// Produces a raw extension request so lifecycle tests remain independent from specialized catalog fixtures.
    /// - Returns: GET_CHANNEL descriptor whose lossless data is asserted directly.
    /// - Throws: Catalog validation failure for an invalid local fixture.
    static func request() throws -> ActivityRequest<JSONValue> {
        try ActivityRequest(command: .getChannel, arguments: ["channel_id": .string("18446744073709551615")], decode: { $0 })
    }

    /// Verifies inert construction, v1 handshake fields, ordered unknown events, raw fidelity and terminal cleanup.
    @Test func handshakeCommandsAndEvents() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: ApplicationID(rawValue: .max), host: Self.host(), transport: peer, clock: ContinuousClock())
        #expect(await peer.closes == 0)
        await #expect(throws: ActivityFailure.notReady) { try await client.execute(Self.request()) }
        try await client.start()
        let handshake = try JSONValue.parse(await peer.nextSent())
        guard case .array(let tuple) = handshake, case .object(let fields) = tuple[1] else { Issue.record("Missing handshake"); return }
        #expect(fields["client_id"] == .string("18446744073709551615")); #expect(fields["v"] == .number(try JSONNumber(rawValue: "1")))
        #expect(fields["sdk_version"] == nil)
        let operation = Task { try await client.execute(Self.request()) }
        let request = await peer.nextSent()
        await peer.push("[1,{\"cmd\":\"DISPATCH\",\"evt\":\"FUTURE_EVENT\",\"data\":{\"huge\":18446744073709551616000}}]")
        let expected = try JSONValue.parse(Data("{\"huge\":18446744073709551616000,\"nil\":null}".utf8))
        try await peer.reply(request, value: expected)
        #expect(try await operation.value == expected)
        let events = await client.drainEvents(); #expect(events.map(\.name.rawValue) == ["READY", "FUTURE_EVENT"])
        #expect(events[1].data == .object(["huge": .number(try JSONNumber(rawValue: "18446744073709551616000"))]))
        #expect(String(reflecting: events[1]) == "ActivityClientEvent(redacted)")
        #expect(await client.drainEvents().isEmpty)
        await client.close(); await client.close()
        #expect(await peer.closes == 1)
        let snapshot = await client.snapshot(); #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.eventBytes == 0)
        await #expect(throws: ActivityFailure.closed) { try await client.start() }
    }

    /// Ensures nonce replies cannot cross concurrent callers; late cancelled replies are ignored independently.
    @Test func concurrentCorrelationAndCancellation() async throws {
        let peer = ActivityPeer(); let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let first = Task { try await client.execute(Self.request()) }; let frame1 = await peer.nextSent()
        let second = Task { try await client.execute(Self.request()) }; let frame2 = await peer.nextSent()
        first.cancel(); await #expect(throws: CancellationError.self) { try await first.value }
        try await peer.reply(frame1, value: .string("late")); try await peer.reply(frame2, value: .string("second"))
        #expect(try await second.value == .string("second"))
        #expect(await client.snapshot().pending == 0)
        await client.close()
    }

    /// Exercises malformed opcodes/schema, mismatched commands and close-before-READY without hanging waiters.
    /// - Parameter malformed: Untrusted authenticated tuple; origin rejection is covered by JavaScript adapter tests.
    @Test(arguments: ["[9,{}]", "[1,{}]", "[1,{\"cmd\":\"DISPATCH\",\"evt\":\"NO_READY\",\"data\":{}}]", "[2,{}]", "[1.0,{}]"])
    func malformedStartup(malformed: String) async throws {
        let peer = ActivityPeer(autoReady: false)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
        let startup = Task { try await client.start() }; _ = await peer.nextSent(); await peer.push(malformed)
        await #expect(throws: (any Error).self) { try await startup.value }
        await client.close(); #expect(await peer.closes == 1)
    }

    /// Verifies correlation mismatch fails every pending operation and host ERROR only rejects its own caller.
    @Test func mismatchAndHostError() async throws {
        let peer = ActivityPeer(); let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let error = Task { try await client.execute(Self.request()) }; let errorFrame = await peer.nextSent()
        try await peer.reply(errorFrame, value: .object(["code": .number(try JSONNumber(rawValue: "4000")), "message": .string("secret")]), event: "ERROR")
        await #expect(throws: ActivityCommandFailure(code: 4000)) { try await error.value }
        let mismatch = Task { try await client.execute(Self.request()) }; let frame = await peer.nextSent()
        try await peer.reply(frame, command: "AUTHORIZE")
        await #expect(throws: ActivityFailure.commandMismatch) { try await mismatch.value }
        await client.close(); #expect(await peer.closes == 1)
    }

    /// Uses a virtual monotonic clock to expire pending work without sleeps or real timer dependence.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deadlineAndStartupCancellation() async throws {
        let peer = ActivityPeer(); let clock = ManualClock()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: clock)
        try await client.start(); _ = await peer.nextSent()
        let operation = Task { try await client.execute(Self.request(), timeout: .seconds(2)) }; _ = await peer.nextSent()
        try clock.advance(by: .seconds(3))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await operation.value }
        #expect(await client.snapshot().pending == 0); await client.close(); #expect(clock.pendingSleepCount == 0)
        let waitingPeer = ActivityPeer(autoReady: false)
        let waiting = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: waitingPeer, clock: ContinuousClock())
        let startup = Task { try await waiting.start() }; _ = await waitingPeer.nextSent(); startup.cancel()
        await #expect(throws: CancellationError.self) { try await startup.value }
        #expect(await waitingPeer.closes == 1)
    }

    /// Checks finite pending/event budgets and zero retained ownership after overload or explicit close.
    @Test func capacityAndClose() async throws {
        let peer = ActivityPeer(); let limits = try ActivityClientLimits(maximumPending: 1, maximumEvents: 1)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock(), limits: limits)
        try await client.start(); _ = await peer.nextSent()
        let operation = Task { try await client.execute(Self.request()) }; _ = await peer.nextSent()
        await #expect(throws: ActivityFailure.overloaded) { try await client.execute(Self.request()) }
        await peer.push("[1,{\"cmd\":\"DISPATCH\",\"evt\":\"UNKNOWN\",\"data\":{}}]")
        await #expect(throws: ActivityFailure.overloaded) { try await operation.value }
        await client.close(); let snapshot = await client.snapshot()
        #expect(snapshot.events == 0 && snapshot.pending == 0 && snapshot.subscriptions == 0)
    }

    /// Verifies identical subscriptions use one upstream admission and only the last token removes it.
    @Test func subscriptionReferenceCounting() async throws {
        let peer = ActivityPeer(); let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let first = Task { try await client.subscribe(.init(rawValue: "SPEAKING_START"), arguments: ["channel_id": .string("1")]) }
        let frame = await peer.nextSent()
        try await peer.reply(frame)
        let token1 = try await first.value
        let token2 = try await client.subscribe(.init(rawValue: "SPEAKING_START"), arguments: ["channel_id": .string("1")])
        #expect(await client.snapshot().subscriptions == 2)
        try await client.unsubscribe(token1); #expect(await client.snapshot().subscriptions == 1)
        let last = Task { try await client.unsubscribe(token2) }; let removal = await peer.nextSent(); try await peer.reply(removal)
        try await last.value; try await client.unsubscribe(token2)
        #expect(await client.snapshot().subscriptions == 0)
        let ready = try await client.subscribe(.ready); try await client.unsubscribe(ready)
        let other = try ActivityClient(applicationID: .init(rawValue: 2), host: Self.host(), transport: ActivityPeer(), clock: ContinuousClock())
        await #expect(throws: ActivityFailure.invalidConfiguration) { try await other.unsubscribe(token1) }
        await other.close(); await client.close()
    }

    /// Validates constructor/parameter boundaries, duplicate keys, optional context and reflective redaction.
    @Test func configurationAndHostContext() async throws {
        #expect(throws: ActivityFailure.invalidConfiguration) { try ActivityClientLimits(maximumPending: 0) }
        #expect(throws: ActivityFailure.invalidConfiguration) { try ActivityClientLimits(maximumFrameBytes: .max) }
        for query in ["frame_id=f&instance_id=i", "frame_id=&instance_id=i&platform=mobile", "frame_id=f&frame_id=f&instance_id=i&platform=desktop", "frame_id=f&instance_id=i&platform=tv", "frame_id=f&instance_id=i&platform=mobile&custom_id=%00"] {
            let url = try #require(URL(string: "https://1.discordsays.com/?" + query))
            #expect(throws: ActivityFailure.invalidHostParameters) { try ActivityHostParameters(url: url) }
        }
        let context = try ActivityHostParameters(url: #require(URL(string: "https://1.discordsays.com/?frame_id=f&instance_id=i&platform=mobile&guild_id=1&channel_id=2&location_id=l&custom_id=c&referrer_id=r&mobile_app_version=250.1")))
        #expect(context.guildID == "1" && context.channelID == "2" && context.locationID == "l")
        #expect(context.customID == "c" && context.referrerID == "r" && context.mobileAppVersion == "250.1")
        #expect(String(reflecting: context) == "ActivityHostParameters(redacted)")
        #expect(Mirror(reflecting: context).children.count == 1)
        #expect(throws: ActivityFailure.invalidConfiguration) { try ActivityClient(applicationID: .init(rawValue: 0), host: Self.host(), transport: ActivityPeer(), clock: ContinuousClock()) }
    }

    /// Ensures writer failures and close during startup release the same adapter exactly once.
    @Test func writerFailureAndCloseBeforeReady() async throws {
        let failed = ActivityPeer(failSend: true)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: failed, clock: ContinuousClock())
        await #expect(throws: ActivityFailure.closed) { try await client.start() }
        await client.close(); #expect(await failed.closes == 1)
        let peer = ActivityPeer(autoReady: false)
        let waiting = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
        let startup = Task { try await waiting.start() }; _ = await peer.nextSent(); await waiting.close()
        await #expect(throws: ActivityFailure.closed) { try await startup.value }
        #expect(await peer.closes == 1)
    }
}

extension ActivityClientTests {
    /// Captures inert construction and explicit host handshake/command/close events while excluding
    /// correlation IDs, host URL fields, command arguments and response bodies from SwiftLog.
    /// - Throws: Unexpected valid simulated Activity exchange behavior.
    @Test func structuredLoggingExcludesHostAndCommandPayloads() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let peer = ActivityPeer()
            let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
            #expect(recorder.entries.isEmpty)
            try await client.start()
            _ = await peer.nextSent()
            let operation = Task { try await client.execute(Self.request()) }
            let request = await peer.nextSent()
            try await peer.reply(request, value: .string("private-activity-payload"))
            #expect(try await operation.value == .string("private-activity-payload"))
            await client.close()
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.activities.client" }
        #expect(entries.contains { $0.level == .info && $0.metadata["dk.event"] == "activities.handshake.completed" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "activities.command.completed" })
        #expect(entries.contains { $0.metadata["dk.event"] == "activities.client.closing" })
        let events = entries.compactMap { $0.metadata["dk.event"]?.description }
        let ready = try #require(events.firstIndex(of: "activities.handshake.ready.validated"))
        let admitted = try #require(events.firstIndex(of: "activities.command.admitted"))
        let reply = try #require(events.firstIndex(of: "activities.reply.correlated"))
        let closed = try #require(events.firstIndex(of: "activities.client.closed"))
        #expect(ready < admitted && admitted < reply && reply < closed)
        #expect(entries.contains { $0.metadata["dk.event"] == "activities.command.admitted" && $0.metadata["dk.pending"]?.description == "1" })
        #expect(entries.contains { $0.metadata["dk.event"] == "activities.reply.correlated" && $0.metadata["dk.pending_bytes"]?.description == "0" })
        #expect(entries.allSatisfy { $0.metadata["dk.module"] == "activities" })
        let rendered = entries.map { $0.message + String(describing: $0.metadata) }.joined()
        for secret in ["private-activity-payload", "frame_id", "instance_id", String(UInt64.max)] {
            #expect(!rendered.contains(secret))
        }
    }
}

extension ActivityClientTests {
    /// Keeps request spans distinct across one ordered writer and reverse-ordered host replies.
    /// - Throws: Unexpected simulated exchange or missing diagnostic continuity.
    @Test func queuedCommandsKeepIndependentDiagnosticSpans() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let peer = ActivityPeer()
            let client = try ActivityClient(applicationID: .init(rawValue: 1), host: Self.host(), transport: peer, clock: ContinuousClock())
            try await client.start()
            _ = await peer.nextSent()
            await peer.holdWrites()
            let first = Task { try await client.execute(Self.request()) }
            let firstWire = await peer.nextSent()
            let second = Task { try await client.execute(Self.request()) }
            for _ in 0..<10_000 {
                if await client.snapshot().pending == 2 { break }
                await Task.yield()
            }
            let pending = await client.snapshot().pending
            await peer.releaseWrites()
            #expect(pending == 2)
            let secondWire = await peer.nextSent()
            try await peer.reply(secondWire, value: .null)
            _ = try await second.value
            try await peer.reply(firstWire, value: .null)
            _ = try await first.value
            await client.close()
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.activities.client" }
        let nested = recorder.entries.filter { $0.label == "discordkit.activities.test_transport" && $0.metadata["dk.event"] == "test.activities.transport.send" && $0.metadata["test.kind"] == "command" }
        let admitted = entries.filter { $0.metadata["dk.event"] == "activities.command.admitted" }
        let writes = entries.filter { $0.metadata["dk.event"] == "activities.write.started" }.dropFirst()
        let replies = entries.filter { $0.metadata["dk.event"] == "activities.reply.correlated" }
        #expect(admitted.count == 2 && writes.count == 2 && replies.count == 2)
        #expect(Set(admitted.compactMap { $0.metadata["dk.span_id"]?.description }).count == 2)
        #expect(writes.map { $0.metadata["dk.span_id"] } == admitted.map { $0.metadata["dk.span_id"] })
        #expect(nested.count == 2)
        #expect(nested.map { $0.metadata["dk.span_id"] } == admitted.map { $0.metadata["dk.span_id"] })
        #expect(nested.map { $0.metadata["dk.trace_id"] } == admitted.map { $0.metadata["dk.trace_id"] })
        #expect(replies.map { $0.metadata["dk.span_id"] } == admitted.reversed().map { $0.metadata["dk.span_id"] })
        #expect(replies.map { $0.metadata["dk.trace_id"] } == admitted.reversed().map { $0.metadata["dk.trace_id"] })
    }
}
