// File: Tests/DiscordActivitiesTests/ActivityClientExtraTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Synchronization
import Testing
@testable import DiscordActivities

/// Observes virtual-clock deadline admission with explicit continuation barriers rather than elapsed sleeps.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class ActivitySleepBarrier: Sendable {
    private struct State {
        var count = 0
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())

    /// Returns the synchronized number of deadlines ever registered, including cancelled historical deadlines.
    var count: Int { state.withLock { $0.count } }

    /// Records registration and resumes every reached count threshold outside the lock.
    func signal() {
        let ready = state.withLock { state in
            state.count += 1
            let count = state.count
            let ready = state.waiters.filter { $0.0 <= count }
            state.waiters.removeAll { $0.0 <= count }
            return ready
        }
        for waiter in ready { waiter.1.resume() }
    }

    /// Waits for a threshold, handling both registration-before-wait and wait-before-registration races.
    /// - Parameter threshold: Absolute positive registration count expected from explicit operation admission.
    func wait(until threshold: Int) async {
        await withCheckedContinuation { continuation in
            let immediate = state.withLock { state in
                if state.count >= threshold { return true }
                state.waiters.append((threshold, continuation))
                return false
            }
            if immediate { continuation.resume() }
        }
    }
}

/// Additional deterministic coverage for cancellation sharing, migration fallback and bounded API admission.
@Suite("Activity additional lifecycle coverage")
struct ActivityClientExtraTests {
    /// Validates shared in-flight admission before cancelling one duplicate, proving the other retains ownership.
    /// Clock-registration barriers prove both local deadline owners and the upstream command are admitted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func duplicatePendingSubscriptionCancellationIsIndependent() async throws {
        let barrier = ActivitySleepBarrier()
        let clock = ManualClock(onSleepScheduled: { barrier.signal() })
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: clock)
        try await client.start()
        _ = await peer.nextSent()
        let baseline = barrier.count
        let first = Task { try await client.subscribe(.init(rawValue: "SPEAKING_START"), arguments: ["channel_id": .string("1")]) }
        let subscriptionFrame = await peer.nextSent()
        await barrier.wait(until: baseline + 2)
        let second = Task { try await client.subscribe(.init(rawValue: "SPEAKING_START"), arguments: ["channel_id": .string("1")]) }
        await barrier.wait(until: baseline + 3)
        #expect(await client.snapshot().subscriptions == 2)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await client.snapshot().subscriptions == 1)
        try await peer.reply(subscriptionFrame)
        let remaining = try await second.value
        #expect(await client.snapshot().subscriptions == 1)
        let release = Task { try await client.unsubscribe(remaining) }
        let removal = await peer.nextSent()
        #expect(try Self.fields(removal)["cmd"] == .string("UNSUBSCRIBE"))
        try await peer.reply(removal)
        try await release.value
        #expect(await client.snapshot().subscriptions == 0)
        await client.close()
        #expect(clock.pendingSleepCount == 0)
    }

    /// A subscription acknowledgement for another event fails closed and rejects the original waiter.
    @Test func mismatchedSubscriptionAcknowledgementCloses() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        let subscription = Task { try await client.subscribe(.init(rawValue: "SPEAKING_START"), arguments: ["channel_id": .string("1")]) }
        let frame = await peer.nextSent()
        try await peer.reply(frame, value: .object(["evt": .string("SPEAKING_STOP")]))
        await #expect(throws: ActivityFailure.commandMismatch) { try await subscription.value }
        await client.close()
        #expect(await peer.closes == 1)
        #expect(await client.snapshot().subscriptions == 0)
    }

    /// INVALID_PAYLOAD on orientation grid locking retries once without only the migration field and a fresh nonce.
    /// A second INVALID_PAYLOAD terminates that command; it never loops or retries unrelated failures.
    @Test func orientationInvalidPayloadFallbackHappensOnce() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        let operation = Task { try await client.execute(Self.orientationRequest()) }
        let initial = await peer.nextSent()
        let initialFields = try Self.fields(initial)
        try await peer.reply(initial, value: Self.error(4000), event: "ERROR")
        let fallback = await peer.nextSent()
        let fallbackFields = try Self.fields(fallback)
        #expect(initialFields["nonce"] != fallbackFields["nonce"])
        #expect(initialFields["cmd"] == fallbackFields["cmd"])
        guard case .object(var expected) = initialFields["args"] else { Issue.record("Missing orientation args"); await client.close(); return }
        expected.removeValue(forKey: "grid_lock_state")
        #expect(fallbackFields["args"] == .object(expected))
        try await peer.reply(fallback, value: Self.error(4000), event: "ERROR")
        await #expect(throws: ActivityCommandFailure(code: 4000)) { try await operation.value }
        let marker = Task { try await client.execute(ActivityClientTests.request()) }
        let markerFrame = await peer.nextSent()
        #expect(try Self.fields(markerFrame)["cmd"] == .string("GET_CHANNEL"))
        try await peer.reply(markerFrame, value: .string("marker"))
        #expect(try await marker.value == .string("marker"))
        await client.close()
    }

    /// Orientation failures other than INVALID_PAYLOAD are surfaced once, preserving mutation retry boundaries.
    @Test func orientationOtherErrorDoesNotRetry() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        let operation = Task { try await client.execute(Self.orientationRequest()) }
        let initial = await peer.nextSent()
        try await peer.reply(initial, value: Self.error(4006), event: "ERROR")
        await #expect(throws: ActivityCommandFailure(code: 4006)) { try await operation.value }
        let marker = Task { try await client.execute(ActivityClientTests.request()) }
        let markerFrame = await peer.nextSent()
        #expect(try Self.fields(markerFrame)["cmd"] == .string("GET_CHANNEL"))
        try await peer.reply(markerFrame, value: .null)
        #expect(try await marker.value == .null)
        await client.close()
    }

    /// Uncorrelated host ERROR becomes an ordered event and cannot consume an ordinary command's nonce.
    @Test func generalHostErrorIsQueued() async throws {
        let peer = ActivityPeer()
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock())
        try await client.start()
        _ = await peer.nextSent()
        _ = await client.drainEvents()
        let marker = Task { try await client.execute(ActivityClientTests.request()) }
        let frame = await peer.nextSent()
        await peer.push(#"[1,{"cmd":"GET_CHANNEL","evt":"ERROR","nonce":null,"data":{"code":4006,"message":"private host detail"}}]"#)
        try await peer.reply(frame, value: .string("after-error"))
        #expect(try await marker.value == .string("after-error"))
        let events = await client.drainEvents()
        #expect(events.count == 1)
        #expect(events.first?.name.rawValue == "ERROR")
        #expect(events.first?.data == Self.error(4006, message: "private host detail"))
        #expect(String(reflecting: try #require(events.first)) == "ActivityClientEvent(redacted)")
        await client.close()
    }

    /// Invalid operation budgets/names fail before sending, and the token cap includes duplicate owners.
    @Test func operationValidationAndSubscriptionTokenLimit() async throws {
        let peer = ActivityPeer()
        let limits = try ActivityClientLimits(maximumSubscriptions: 1)
        let client = try ActivityClient(applicationID: .init(rawValue: 1), host: ActivityClientTests.host(), transport: peer, clock: ContinuousClock(), limits: limits)
        await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.start(timeout: .zero) }
        try await client.start()
        _ = await peer.nextSent()
        await #expect(throws: ActivityFailure.notReady) { try await client.start() }
        await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.execute(ActivityClientTests.request(), timeout: .zero) }
        await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.subscribe(.ready, timeout: .zero) }
        for event in ["", "bad\nname", String(repeating: "a", count: 257)] {
            await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.subscribe(.init(rawValue: event)) }
        }
        let ready = try await client.subscribe(.ready)
        await #expect(throws: ActivityFailure.overloaded) { try await client.subscribe(.ready) }
        await #expect(throws: ActivityFailure.invalidConfiguration) { try await client.unsubscribe(ready, timeout: .zero) }
        #expect(await client.snapshot().subscriptions == 1)
        try await client.unsubscribe(ready)
        #expect(await client.snapshot().subscriptions == 0)
        await client.close()
    }

    /// Creates raw orientation arguments to isolate lifecycle compatibility behavior from catalog projections.
    /// - Returns: A SET_ORIENTATION_LOCK_STATE descriptor with the documented migration-only grid field.
    /// - Throws: Descriptor validation failure for the static protocol fixture.
    private static func orientationRequest() throws -> ActivityRequest<JSONValue> {
        try ActivityRequest(command: .setOrientationLockState, arguments: [
            "lock_state": .number(JSONNumber(rawValue: "1")),
            "picture_in_picture_lock_state": .number(JSONNumber(rawValue: "2")),
            "grid_lock_state": .number(JSONNumber(rawValue: "1")),
        ], decode: { $0 })
    }

    /// Constructs a schema-valid remote ERROR payload without exposing its text through public errors.
    /// - Parameters:
    ///   - code: Protocol error code, including INVALID_PAYLOAD 4000.
    ///   - message: Synthetic private host reason; defaults to a fixed string.
    /// - Returns: Complete code/message data for the peer's correlated or general ERROR frame.
    private static func error(_ code: Int, message: String = "Synthetic host error") -> JSONValue {
        .object(["code": .number(try! JSONNumber(rawValue: String(code))), "message": .string(message)])
    }

    /// Parses one observed outgoing tuple for command/nonce/argument assertions without mutating it.
    /// - Parameter data: Complete bytes already captured by the authenticated test peer.
    /// - Returns: The tuple's object payload.
    /// - Throws: Malformed fixture or a Swift Testing requirement failure.
    private static func fields(_ data: Data) throws -> [String: JSONValue] {
        guard case .array(let tuple) = try JSONValue.parse(data), tuple.count == 2,
              case .object(let fields) = tuple[1] else { throw ActivityFailure.invalidFrame }
        return fields
    }
}
