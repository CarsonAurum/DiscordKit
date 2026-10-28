// File: Tests/DiscordTransportTests/ShardOwnershipTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Atomic, bounded shard tickets with virtual-time expiry and failover fencing.
@Suite("Shard ownership")
struct ShardOwnershipTests {
    /// Validates index/count boundaries and full unsigned guild routing without a session.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func assignmentsAndRouting() throws {
        for (index, count) in [(-1, 1), (0, 0), (1, 1), (0, -1)] {
            #expect(throws: ShardOwnershipFailure.invalidAssignment) {
                try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: index, count: count)
            }
        }
        for index in 0..<3 {
            let shard = try key(index: index, count: 3)
            #expect(shard.botID.rawValue == 1)
            #expect(shard.topologyGeneration == 0)
            for rawValue in [UInt64(0), 1 << 22, 2 << 22, UInt64.max] {
                #expect(shard.routes(GuildID(rawValue: rawValue)) == ((rawValue >> 22) % 3 == UInt64(index)))
            }
        }
    }

    /// Rejects invalid limits and lifetimes without retaining records or granting authority.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidLimits() async throws {
        #expect(throws: ShardOwnershipFailure.invalidLimit) {
            try InProcessShardLeaseStore(clock: ManualClock(), maximumLeases: 0)
        }
        let store = try InProcessShardLeaseStore(clock: ManualClock(), maximumLeases: 1)
        for duration in [Duration.zero, .seconds(-1)] {
            await #expect(throws: ShardOwnershipFailure.invalidLimit) {
                try await store.acquire(key(), owner: UUID(), lifetime: duration)
            }
        }
        #expect(await store.retainedLeaseCount() == 0)
    }

    /// Competing tasks atomically reserve exactly one owner; capacity does not queue.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentAcquisitionAndCapacity() async throws {
        let store = try InProcessShardLeaseStore(clock: ManualClock(), maximumLeases: 1)
        let shard = try key()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do { _ = try await store.acquire(shard, owner: UUID(), lifetime: .seconds(10)); return true }
                    catch { return false }
                }
            }
            var successes = 0
            for await succeeded in group { if succeeded { successes += 1 } }
            return successes
        }
        #expect(results == 1)
        #expect(await store.retainedLeaseCount() == 1)
        await #expect(throws: ShardOwnershipFailure.alreadyOwned) {
            try await store.acquire(shard, owner: UUID(), lifetime: .seconds(1))
        }
        await #expect(throws: ShardOwnershipFailure.capacityExceeded) {
            try await store.acquire(key(index: 1, count: 2), owner: UUID(), lifetime: .seconds(10))
        }
    }

    /// Inclusive expiry fences the old owner, permits recovery, and rejects late cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func expiryFailoverAndStaleCompletion() async throws {
        let clock = ManualClock()
        let store = try InProcessShardLeaseStore(clock: clock, maximumLeases: 1)
        let first = try await store.acquire(key(), owner: UUID(), lifetime: .seconds(2))
        try await store.validate(first)
        try clock.advance(by: .seconds(2))
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await store.validate(first) }
        await #expect(throws: ShardOwnershipFailure.staleLease) {
            try await store.renew(first, lifetime: .seconds(3))
        }
        let replacement = try await store.acquire(key(), owner: UUID(), lifetime: .seconds(2))
        #expect(replacement.generation > first.generation)
        await store.release(first)
        try await store.validate(replacement)
        await store.release(replacement)
        await store.release(replacement)
        #expect(await store.retainedLeaseCount() == 0)
    }

    /// Renewal replaces tickets, rejects forged identity/fences, and prunes expired keys.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func renewalAndPruning() async throws {
        let clock = ManualClock()
        let store = try InProcessShardLeaseStore(clock: clock, maximumLeases: 1)
        let first = try await store.acquire(key(), owner: UUID(), lifetime: .seconds(2))
        let initialRenewal = try await store.renew(first, lifetime: .seconds(5))
        let renewal = try await store.renew(initialRenewal, lifetime: .seconds(5))
        #expect(renewal.generation > initialRenewal.generation)
        #expect(renewal.expiresAt == initialRenewal.expiresAt)
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await store.validate(initialRenewal) }
        #expect(renewal.expiresAt == clock.now.advanced(by: .seconds(5)))
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await store.validate(first) }
        let forged = ShardLease<ManualClock>(shard: renewal.shard, owner: UUID(), generation: renewal.generation,
                                            expiresAt: renewal.expiresAt)
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await store.validate(forged) }
        let forgedGeneration = ShardLease<ManualClock>(shard: renewal.shard, owner: renewal.owner,
                                                      generation: renewal.generation + 1, expiresAt: renewal.expiresAt)
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await store.validate(forgedGeneration) }
        await #expect(throws: ShardOwnershipFailure.invalidLimit) { try await store.renew(renewal, lifetime: .zero) }
        try clock.advance(by: .seconds(5))
        _ = try await store.acquire(key(index: 1, count: 2), owner: UUID(), lifetime: .seconds(1))
        #expect(await store.retainedLeaseCount() == 1)
    }

    /// Cancelled admission/validation/renewal fail before mutation; cleanup still succeeds.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndCancelledRelease() async throws {
        let store = try InProcessShardLeaseStore(clock: ManualClock(), maximumLeases: 1)
        let lease = try await store.acquire(key(), owner: UUID(), lifetime: .seconds(3))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await store.validate(lease) }
            await #expect(throws: CancellationError.self) { try await store.renew(lease, lifetime: .seconds(1)) }
            await store.release(lease)
            await #expect(throws: CancellationError.self) {
                try await store.acquire(key(), owner: UUID(), lifetime: .seconds(1))
            }
        }
        await task.value
        #expect(await store.retainedLeaseCount() == 0)
    }

    /// Builds a small valid assignment shared by deterministic ownership scenarios.
    /// - Parameters:
    ///   - index: Zero-based index, default zero.
    ///   - count: Positive topology size, default one.
    /// - Returns: Bot one in topology zero with the requested shard index/count.
    /// - Throws: Assignment validation errors for invalid test inputs.
    private func key(index: Int = 0, count: Int = 1) throws -> ShardIdentity {
        try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: index, count: count)
    }
}
