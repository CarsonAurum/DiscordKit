import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordGateway

@Suite("Atomic Gateway startup")
struct GatewayStartupTests {
    /// A zero reset preserves partial/exhausted quota and never replenishes it as time advances.
    /// - Parameter remaining: Initial quota; total is deliberately larger to detect invented starts.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 2])
    func zeroResetQuota(remaining: Int) async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 3, remaining: remaining, resetAfter: .zero, maxConcurrency: 1)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        for index in 0..<remaining {
            #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
            #expect(await coordinator.remainingStarts() == remaining - index - 1)
            if index + 1 < remaining {
                #expect(try await coordinator.reserveIdentify(for: shard) == .wait(.seconds(5)))
            }
            try clock.advance(by: .seconds(5))
        }
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
        try clock.advance(by: .seconds(100))
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
        #expect(await coordinator.remainingStarts() == 0)
    }

    /// Repeated zero snapshots retain spent starts and bucket windows; positive reset refills only once.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func zeroResetRefresh() async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 3, remaining: 2, resetAfter: .zero, maxConcurrency: 1)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        try await coordinator.refresh(limit)
        #expect(await coordinator.remainingStarts() == 1)
        #expect(try await coordinator.reserveIdentify(for: shard) == .wait(.seconds(5)))
        let exhausted = try GatewaySessionStartLimit(total: 3, remaining: 0, resetAfter: .zero, maxConcurrency: 1)
        try await coordinator.refresh(exhausted)
        try await coordinator.refresh(limit)
        #expect(await coordinator.remainingStarts() == 0)
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
        let scheduled = try GatewaySessionStartLimit(total: 3, remaining: 3, resetAfter: .seconds(10), maxConcurrency: 1)
        try await coordinator.refresh(scheduled)
        #expect(await coordinator.remainingStarts() == 0)
        #expect(try await coordinator.reserveIdentify(for: shard) == .wait(.seconds(10)))
        try clock.advance(by: .seconds(10))
        for remaining in (0...2).reversed() {
            #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
            #expect(await coordinator.remainingStarts() == remaining)
            try clock.advance(by: .seconds(5))
        }
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
    }

    /// A newer zero reset cancels an old deadline without restoring previously reserved starts.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func zeroRefreshClearsPendingReset() async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 2, remaining: 1, resetAfter: .seconds(10), maxConcurrency: 1)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        let unscheduled = try GatewaySessionStartLimit(total: 2, remaining: 2, resetAfter: .zero, maxConcurrency: 1)
        try await coordinator.refresh(unscheduled)
        #expect(await coordinator.remainingStarts() == 0)
        try clock.advance(by: .seconds(10))
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
    }

    /// Fresh zero-reset discovery can replace quota after a known reset, preserving active bucket spacing.
    /// - Parameter consumeReset: Whether admission already consumed the known one-time refill before refresh.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func zeroRefreshAfterKnownReset(consumeReset: Bool) async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .seconds(10), maxConcurrency: 1)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        try clock.advance(by: .seconds(10))
        if consumeReset { #expect(try await coordinator.reserveIdentify(for: shard) == .admitted) }
        let unscheduled = try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .zero, maxConcurrency: 1)
        try await coordinator.refresh(unscheduled)
        #expect(await coordinator.remainingStarts() == 1)
        if consumeReset {
            #expect(try await coordinator.reserveIdentify(for: shard) == .wait(.seconds(5)))
            try clock.advance(by: .seconds(5))
        }
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        try await coordinator.refresh(unscheduled)
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
    }

    /// Confirms simultaneous workers and topology generations cannot multiply shared Identify quota.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func storm() async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 100, remaining: 2, resetAfter: .seconds(10), maxConcurrency: 2)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let admitted = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: UInt64(index),
                                                  index: index % 2, count: 2)
                    return try await coordinator.reserveIdentify(for: shard) == .admitted
                }
            }
            var count = 0
            for try await result in group { if result { count += 1 } }
            return count
        }
        #expect(admitted == 2)
        #expect(await coordinator.remainingStarts() == 0)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 200, index: 0, count: 2)
        #expect(try await coordinator.reserveIdentify(for: shard) == .wait(.seconds(10)))
        try clock.advance(by: .seconds(10))
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        #expect(await coordinator.remainingStarts() == 99)
    }

    /// Exercises bucket spacing, wrong identities, explicit refresh and one-time reset exhaustion.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bucketsAndRefresh() async throws {
        let clock = ManualClock()
        let limit = try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .seconds(10), maxConcurrency: 1)
        let coordinator = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: limit, clock: clock)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        try clock.advance(by: .seconds(10))
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        try clock.advance(by: .seconds(5))
        await #expect(throws: GatewayFailure.startupRefreshRequired) { try await coordinator.reserveIdentify(for: shard) }
        try await coordinator.refresh(limit)
        #expect(try await coordinator.reserveIdentify(for: shard) == .admitted)
        let other = try ShardIdentity(botID: UserID(rawValue: 2), topologyGeneration: 0, index: 0, count: 1)
        await #expect(throws: GatewayFailure.invalidConfiguration) { try await coordinator.reserveIdentify(for: other) }
        let incompatible = try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .seconds(1), maxConcurrency: 2)
        await #expect(throws: GatewayFailure.invalidConfiguration) { try await coordinator.refresh(incompatible) }
        let bucketClock = ManualClock()
        let available = try GatewaySessionStartLimit(total: 10, remaining: 10, resetAfter: .seconds(100), maxConcurrency: 1)
        let buckets = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: available, clock: bucketClock)
        #expect(try await buckets.reserveIdentify(for: shard) == .admitted)
        #expect(try await buckets.reserveIdentify(for: shard) == .wait(.seconds(5)))
        try bucketClock.advance(by: .seconds(5))
        #expect(try await buckets.reserveIdentify(for: shard) == .admitted)
        try await buckets.refresh(available)
        #expect(await buckets.remainingStarts() == 8)
        #expect(try await buckets.reserveIdentify(for: shard) == .wait(.seconds(5)))
    }
}
