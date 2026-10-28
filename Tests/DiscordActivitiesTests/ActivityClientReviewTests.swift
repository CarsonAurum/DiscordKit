// File: Tests/DiscordActivitiesTests/ActivityClientReviewTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordActivities

/// Additional protocol-evidence regressions for envelope validation and terminal lifecycle ownership.
/// All frames come from an authenticated synthetic adapter; JavaScript tests exercise browser provenance.
@Suite("Activity protocol review regressions")
struct ActivityClientReviewTests {
    /// Rejects incomplete READY frames even when the opcode, command, and RPC version appear plausible.
    /// The pinned schema requires explicit null nonce and configuration API/environment string fields.
    /// - Parameter json: Adversarial complete tuple whose READY data or envelope violates that schema.
    @Test(arguments: [
        #"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1}}]"#,
        #"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{}}}]"#,
        #"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":1,"environment":"production"}}}]"#,
        #"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":null}}}]"#,
        #"[1,{"cmd":"DISPATCH","evt":"READY","data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":"production"}}}]"#,
    ])
    func incompleteReadyFails(json: String) async throws {
        let peer = ActivityPeer(autoReady: false)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(),
                                        transport: peer, clock: ContinuousClock())
        let startup = Task { try await client.start() }
        _ = await peer.nextSent()
        await peer.push(json)
        await #expect(throws: ActivityFailure.invalidFrame) { try await startup.value }
        await client.close()
        #expect(await peer.closes == 1)
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.events == 0)
    }

    /// Legacy HELLO carries no readiness authority; only the later schema-valid READY starts the client.
    /// Two back-to-back scripted tuples exercise the reader's ordered consumption without sleeps.
    @Test func helloThenValidReady() async throws {
        let peer = ActivityPeer(autoReady: false)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(),
                                        transport: peer, clock: ContinuousClock())
        let startup = Task { try await client.start() }
        _ = await peer.nextSent()
        await peer.push(#"[3,{"legacy":"hello"}]"#)
        await peer.push(#"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":"production"}}}]"#)
        try await startup.value
        #expect(await client.drainEvents().map(\.name.rawValue) == ["READY"])
        let request = Task { try await client.execute(ActivityClientTests.request()) }
        let frame = await peer.nextSent()
        try await peer.reply(frame, value: .string("ready"))
        #expect(try await request.value == .string("ready"))
        await client.close()
    }

    /// A correct nonce and command cannot turn an arbitrary event-bearing frame into successful data.
    /// Ordinary successful RPC replies require outer evt:null; subscription names belong in data.evt.
    @Test func successfulReplyRequiresNullEvent() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(),
                                        transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        let request = Task { try await client.execute(ActivityClientTests.request()) }
        let frame = await peer.nextSent()
        try await peer.reply(frame, value: .string("spoofed-success"), event: "FUTURE_EVENT")
        await #expect(throws: ActivityFailure.invalidFrame) { try await request.value }
        await client.close()
        #expect(await client.snapshot().pending == 0)
    }

    /// A host close need not contain a reason; every active request still terminates and cleanup is shared.
    @Test func hostCloseWithoutReason() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(),
                                        transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        let request = Task { try await client.execute(ActivityClientTests.request()) }
        _ = await peer.nextSent()
        await peer.push(#"[2,{"code":1000}]"#)
        await #expect(throws: ActivityFailure.closed) { try await request.value }
        await client.close()
        #expect(await peer.closes == 1)
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.events == 0 && snapshot.subscriptions == 0)
    }

    /// Never-ack subscription transitions expire under an injected monotonic clock and release all tokens.
    /// The test observes actual SUBSCRIBE admission before advancing time, avoiding timing-dependent sleeps.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func neverAcknowledgedSubscriptionTerminates() async throws {
        let peer = ActivityPeer()
        let clock = ManualClock()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(),
                                        transport: peer, clock: clock)
        try await client.start()
        _ = await peer.nextSent()
        let subscription = Task { try await client.subscribe(.init(rawValue: "FUTURE_EVENT"), timeout: .seconds(2)) }
        _ = await peer.nextSent()
        try clock.advance(by: .seconds(3))
        await #expect(throws: (any Error).self) { try await subscription.value }
        await client.close()
        let snapshot = await client.snapshot()
        #expect(snapshot.pending == 0 && snapshot.pendingBytes == 0 && snapshot.subscriptions == 0)
        #expect(await peer.closes == 1)
        #expect(clock.pendingSleepCount == 0)
    }
}
