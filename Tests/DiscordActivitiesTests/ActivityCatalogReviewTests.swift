// File: Tests/DiscordActivitiesTests/ActivityCatalogReviewTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordActivities

/// Cancellation-aware synthetic adapter that keeps one command send suspended until its owner cancels or closes.
/// The handshake remains synchronous and READY is authenticated by construction; no real browser or timer sleeps are used.
private actor ActivityReviewBlockedWriter: ActivityTransport {
    private var input: [Data] = []
    private var reader: CheckedContinuation<Data?, Never>?
    private var writeWaiter: CheckedContinuation<Void, any Error>?
    private var sent: [Data] = []
    private var observed: CheckedContinuation<Data?, Never>?
    private var ended = false
    private(set) var closes = 0
    private(set) var opcodes: [String] = []

    /// Records a tuple, delivers READY for the handshake and suspends command writes with cooperative cancellation.
    /// - Parameter data: Client-owned complete bounded tuple.
    /// - Throws: Cancellation for an interrupted command, closure, or a malformed synthetic fixture.
    func send(_ data: Data) async throws {
        guard !ended else { throw ActivityFailure.closed }
        guard case .array(let tuple) = try JSONValue.parse(data), case .number(let opcode) = tuple.first else {
            throw ActivityFailure.invalidFrame
        }
        opcodes.append(opcode.rawValue)
        if let observed { self.observed = nil; observed.resume(returning: data) }
        else { sent.append(data) }
        if opcode.rawValue == "0" {
            push(Data(#"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":"production"}}}]"#.utf8))
        } else if opcode.rawValue == "1" {
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { writeWaiter = $0 }
            } onCancel: { Task { await self.cancelWrite() } }
        }
    }

    /// Returns an authenticated queued tuple or transfers the sole pending read to close/input ownership.
    /// - Returns: Complete trusted frame, or nil after close.
    func receive() async throws -> Data? {
        if !input.isEmpty { return input.removeFirst() }
        if ended { return nil }
        return await withCheckedContinuation { reader = $0 }
    }

    /// Waits for an actual write, handling both write-before-observe and observe-before-write ordering.
    /// - Returns: Next tuple, or nil after close when no tuples remain.
    func nextSent() async -> Data? {
        if !sent.isEmpty { return sent.removeFirst() }
        if ended { return nil }
        return await withCheckedContinuation { observed = $0 }
    }

    /// Supplies synthetic trusted input without suspending the reader actor on a callback.
    /// - Parameter data: Complete deterministic READY data.
    private func push(_ data: Data) {
        if let reader { self.reader = nil; reader.resume(returning: data) }
        else { input.append(data) }
    }

    /// Completes one cancelled send exactly once; subsequent adapter disposal is harmless.
    private func cancelWrite() {
        writeWaiter?.resume(throwing: CancellationError()); writeWaiter = nil
    }

    /// Reserves terminal adapter state and resumes every retained send, receive and observer continuation exactly once.
    func close() async {
        guard !ended else { return }
        ended = true; closes += 1
        writeWaiter?.resume(throwing: ActivityFailure.closed); writeWaiter = nil
        reader?.resume(returning: nil); reader = nil
        observed?.resume(returning: nil); observed = nil
        input.removeAll()
    }
}

/// Independent review regressions for local admission, terminal write ownership and legacy frame variants.
@Suite("Activity catalog and ownership review")
struct ActivityCatalogReviewTests {
    /// Invalid subscription names fail before allocating group ownership and preserve an otherwise healthy client.
    /// Previously ERROR and 129-byte names reached asynchronous catalog validation and closed the entire session.
    @Test func rejectedSubscriptionInputPreservesSession() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        for event in [ActivityEventName.error, ActivityEventName(rawValue: String(repeating: "a", count: 129)), ActivityEventName(rawValue: "EVENT\u{85}")] {
            await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.subscribe(event) }
            let snapshot = await client.snapshot()
            #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.subscriptions == 0)
            #expect(await peer.closes == 0)
        }
        let marker = Task { try await client.execute(ActivityClientTests.request()) }
        let frame = await peer.nextSent(); try await peer.reply(frame, value: .string("still-ready"))
        #expect(try await marker.value == .string("still-ready"))
        await client.close()
    }

    /// Explicit close must not await a writer that is itself awaiting the same shared cleanup task.
    /// A cancellation-aware suspended command send exposes that cycle without timing-dependent sleeps.
    @Test(.timeLimit(.minutes(1))) func closeDuringBlockedWriteCompletesAndNotifiesOnce() async throws {
        let peer = ActivityReviewBlockedWriter()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = try #require(await peer.nextSent())
        let pending = Task { try await client.execute(ActivityClientTests.request()) }
        _ = try #require(await peer.nextSent())
        async let firstClose: Void = client.close()
        async let repeatedClose: Void = client.close()
        _ = await (firstClose, repeatedClose)
        await #expect(throws: ActivityFailure.closed) { try await pending.value }
        #expect(await peer.closes == 1)
        #expect(await peer.opcodes == ["0", "1", "2"])
        let notice = try JSONValue.parse(#require(await peer.nextSent()))
        guard case .array(let tuple) = notice, case .object(let fields) = tuple[1] else {
            Issue.record("Expected close tuple"); return
        }
        #expect(tuple[0] == .number(try JSONNumber(rawValue: "2")))
        #expect(fields["code"] == .number(try JSONNumber(rawValue: "1000")))
        #expect(fields["message"] == .string(""))
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.subscriptions == 0)
    }

    /// Optional host ERROR messages remain optional, while generated empty responses may omit data entirely.
    /// Both supported empty commands are normalized to null without weakening ordinary response envelope validation.
    @Test func omittedErrorMessageAndGeneratedEmptyData() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let rejected = Task { try await client.execute(ActivityClientTests.request()) }
        let rejectedFrame = await peer.nextSent()
        try await peer.reply(rejectedFrame, value: .object(["code": .number(JSONNumber(rawValue: "4006"))]), event: "ERROR")
        await #expect(throws: ActivityCommandFailure(code: 4006)) { try await rejected.value }
        let invite = Task { try await client.execute(ActivityRequests.inviteUserEmbedded(userID: "user")) }
        let inviteFrame = await peer.nextSent()
        try await Self.replyWithoutData(inviteFrame, peer: peer)
        #expect(try await invite.value.value == .null)
        let moment = Task { try await client.execute(ActivityRequests.openShareMomentDialog(mediaURL: "https://cdn.discordapp.com/image")) }
        let momentFrame = await peer.nextSent()
        try await Self.replyWithoutData(momentFrame, peer: peer)
        #expect(try await moment.value.value == .null)
        let ordinary = Task { try await client.execute(ActivityClientTests.request()) }
        let ordinaryFrame = await peer.nextSent()
        try await Self.replyWithoutData(ordinaryFrame, peer: peer)
        await #expect(throws: ActivityFailure.invalidFrame) { try await ordinary.value }
        await client.close(); #expect(await peer.closes == 1)
    }

    /// Creates an otherwise valid correlated acknowledgement with its JSON data field omitted.
    /// - Parameters:
    ///   - request: Previously observed request tuple with a fresh command and nonce.
    ///   - peer: Authenticated synthetic adapter receiving the complete reply.
    /// - Throws: Malformed fixture or JSON serialization failure; no live service is involved.
    private static func replyWithoutData(_ request: Data, peer: ActivityPeer) async throws {
        guard case .array(let tuple) = try JSONValue.parse(request), case .object(let fields) = tuple[1],
              let command = fields["cmd"], let nonce = fields["nonce"] else { throw ActivityFailure.invalidFrame }
        let response: JSONValue = .array([.number(try JSONNumber(rawValue: "1")), .object(["cmd": command, "nonce": nonce, "evt": .null])])
        await peer.push(String(decoding: try response.serialized(), as: UTF8.self))
    }
}

extension ActivityCatalogReviewTests {
    /// A caller cancelled before unsubscribe admission retains its token and leaves the healthy session unchanged.
    /// Cancellation is set on the current task before the actor call, making the pre-admission order deterministic.
    @Test func preCancelledUnsubscribePreservesOwnership() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let admitted = Task { try await client.subscribe(.speakingStart, arguments: ["channel_id": .string("channel")]) }
        let frame = await peer.nextSent(); try await peer.reply(frame)
        let subscription = try await admitted.value
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await client.unsubscribe(subscription)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.subscriptions == 1)
        #expect(await peer.closes == 0)
        guard snapshot.subscriptions == 1 else { await client.close(); return }
        let release = Task { try await client.unsubscribe(subscription) }
        let removal = await peer.nextSent(); try await peer.reply(removal)
        try await release.value
        #expect(await client.snapshot().subscriptions == 0)
        await client.close(); #expect(await peer.closes == 1)
    }
}

extension ActivityCatalogReviewTests {
    /// A cancelled command caller is rejected before pending state or wire admission and does not disturb later commands.
    @Test func preCancelledExecutionPreservesSession() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start(); _ = await peer.nextSent()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(ActivityClientTests.request())
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0)
        #expect(await peer.closes == 0)
        let marker = Task { try await client.execute(ActivityClientTests.request()) }
        let frame = await peer.nextSent(); try await peer.reply(frame, value: .bool(true))
        #expect(try await marker.value == .bool(true))
        await client.close()
    }
}

extension ActivityCatalogReviewTests {
    /// Network URL fields require an actual host while preserving WHATWG slash normalization and custom schemes.
    /// Validation leaves the supplied spelling unchanged and performs no navigation, request or credential handling.
    @Test func networkURLValidationRejectsMissingHosts() throws {
        for invalid in ["https://", "https:", "https://?query", "http://#fragment", "ws://", "ftp://", "https://example.com:65536"] {
            #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityPresenceUpdate(stateURL: .value(invalid)) }
            #expect(throws: ActivityCatalogError.invalidArguments) { try ActivityPresenceUpdate(detailsURL: .value(invalid)) }
            #expect(throws: ActivityCatalogError.invalidPayload) { try ActivityAssets(value: .object(["large_url": .string(invalid)])) }
        }
        for valid in ["https://example.com", "https:///path", "https:example.com/path", "https://user:password@example.com", "https://[::1]:443", "custom:payload", "mailto:person@example.com"] {
            let update = try ActivityPresenceUpdate(stateURL: .value(valid), detailsURL: .value(valid))
            #expect(update.rawFields["state_url"] == .string(valid))
            #expect(update.rawFields["details_url"] == .string(valid))
            let assets = try ActivityAssets(value: .object(["large_url": .string(valid)]))
            #expect(assets.largeURL == .value(valid))
        }
    }

    /// Readiness rejects malformed optional user projections as strictly as required version/configuration data.
    /// - Parameter user: Complete optional user subtree with an invalid type or missing required identity fields.
    @Test(arguments: ["null", "false", "{}", "{\"id\":1,\"username\":\"name\",\"discriminator\":\"0\"}", "{\"id\":\"id\",\"username\":\"name\"}"])
    func malformedOptionalReadyUserFails(user: String) async throws {
        let peer = ActivityPeer(autoReady: false)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        let startup = Task { try await client.start() }
        _ = await peer.nextSent()
        await peer.push("[1,{\"cmd\":\"DISPATCH\",\"evt\":\"READY\",\"nonce\":null,\"data\":{\"v\":1,\"config\":{\"api_endpoint\":\"//discord.com/api\",\"environment\":\"production\"},\"user\":" + user + "}}]")
        await #expect(throws: ActivityFailure.invalidFrame) { try await startup.value }
        await client.close(); #expect(await peer.closes == 1)
    }
}
