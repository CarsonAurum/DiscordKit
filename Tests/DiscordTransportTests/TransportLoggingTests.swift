// File: Tests/DiscordTransportTests/TransportLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
import DiscordCore
import DiscordLogging
import DiscordTestSupport
import DiscordTransport

/// Confirms authority diagnostics carry counts, never authority-bearing ticket values.
struct TransportLoggingTests {
    /// Exercises acquire, renewal, stale cleanup and inclusive deadline diagnostics.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func leaseAndDeadlineEvents() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let clock = ManualClock()
            let store = try InProcessShardLeaseStore(clock: clock, maximumLeases: 1)
            #expect(recorder.entries.isEmpty)
            let shard = try ShardIdentity(botID: UserID(rawValue: 987654321), topologyGeneration: 456,
                                          index: 0, count: 1)
            let first = try await store.acquire(shard, owner: UUID(), lifetime: .seconds(2))
            let renewed = try await store.renew(first, lifetime: .seconds(2))
            await store.release(first)
            await store.release(renewed)
            await store.release(renewed)
            #expect(await store.retainedLeaseCount() == 0)
            let context = TransportContext(clock: clock, deadline: clock.now)
            #expect(throws: TransportFailure.deadlineExceeded) { try context.check() }
        }
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"] } == [
            "transport.leases.acquired", "transport.leases.renewed", "transport.leases.released",
            "transport.deadline.expired",
        ])
        #expect(recorder.entries.allSatisfy { $0.level == .trace })
        #expect(!String(describing: recorder.entries).contains("987654321"))
    }
}
