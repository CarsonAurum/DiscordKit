// File: Sources/DiscordGateway/GatewayStartup.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation

/// Server-reported Identify allowances from GET /gateway/bot, independent of topology.
public struct GatewaySessionStartLimit: Sendable, Equatable {
    public let total: Int
    public let remaining: Int
    public let resetAfter: Duration
    public let maxConcurrency: Int

    /// Validates a discovery snapshot; no allowance is inferred from shard count.
    /// - Parameters:
    ///   - total: Positive total starts in the server's current budget.
    ///   - remaining: Starts remaining in `0...total`, including zero.
    ///   - resetAfter: Nonnegative monotonic time until the server-reported reset, at most 30 days.
    ///     Zero preserves the reported remaining allowance without scheduling an automatic refill.
    ///     The upper implementation bound prevents unsafe arithmetic on untrusted discovery values.
    ///   - maxConcurrency: Positive number of independent five-second Identify buckets.
    /// - Throws: `invalidConfiguration` for inconsistent/unsafe values; bucket metadata is capped at 65,536.
    public init(total: Int, remaining: Int, resetAfter: Duration, maxConcurrency: Int) throws {
        guard total > 0, remaining >= 0, remaining <= total, resetAfter >= .zero,
              resetAfter <= .seconds(2_592_000),
              (1...65_536).contains(maxConcurrency) else { throw GatewayFailure.invalidConfiguration }
        self.total = total; self.remaining = remaining; self.resetAfter = resetAfter
        self.maxConcurrency = maxConcurrency
    }
}

/// The current authenticated discovery result, with strict operational field validation.
public struct GatewayDiscovery: Sendable {
    public let url: URL
    public let recommendedShardCount: Int
    public let sessionStartLimit: GatewaySessionStartLimit
    public let rawValue: JSONValue

    /// Decodes GET /gateway/bot through the lossless, bounded JSON path supplied by HTTP.
    /// Zero `reset_after` is accepted without inferring additional session starts or a reset period.
    /// - Parameter value: Response JSON, including unknown fields retained as `rawValue`.
    /// - Throws: `invalidPayload` or `invalidConfiguration` for missing/invalid operational fields,
    ///   including negative reset intervals and intervals above the 30-day implementation bound.
    public init(json value: JSONValue) throws {
        guard case .object(let root) = value, case .string(let url) = root["url"],
              case .number(let shards) = root["shards"], let count = Int(shards.rawValue), count > 0,
              case .object(let limits) = root["session_start_limit"],
              case .number(let total) = limits["total"], let totalValue = Int(total.rawValue),
              case .number(let remaining) = limits["remaining"], let remainingValue = Int(remaining.rawValue),
              case .number(let reset) = limits["reset_after"], let resetValue = Int64(reset.rawValue), resetValue >= 0,
              case .number(let concurrency) = limits["max_concurrency"], let concurrencyValue = Int(concurrency.rawValue)
        else { throw GatewayFailure.invalidPayload }
        self.url = try gatewayURL(url)
        recommendedShardCount = count
        sessionStartLimit = try GatewaySessionStartLimit(total: totalValue, remaining: remainingValue,
            resetAfter: .milliseconds(resetValue), maxConcurrency: concurrencyValue)
        rawValue = value
    }

    /// Creates a bounded fixed-topology shard subset from discovery's recommendation.
    /// - Parameters:
    ///   - botID: Public bot identity; the credential is held elsewhere.
    ///   - topologyGeneration: Explicit deployment generation; changing count requires controlled drain.
    ///   - indices: Unique selected indices, or `nil` for the complete recommended topology.
    ///   - maximumShards: Positive aggregate local active-shard limit; default 256.
    /// - Returns: Sorted shard identities; empty subsets are allowed and allocate no sessions.
    /// - Throws: `invalidConfiguration` for duplicates, out-of-range indices or exceeded local capacity.
    public func shards(botID: UserID, topologyGeneration: UInt64, indices: [Int]? = nil,
                       maximumShards: Int = 256) throws -> [ShardIdentity] {
        guard maximumShards > 0 else { throw GatewayFailure.invalidConfiguration }
        if indices == nil, recommendedShardCount > maximumShards { throw GatewayFailure.invalidConfiguration }
        let selected = indices ?? Array(0..<recommendedShardCount)
        guard selected.count <= maximumShards, Set(selected).count == selected.count,
              selected.allSatisfy({ $0 >= 0 && $0 < recommendedShardCount }) else {
            throw GatewayFailure.invalidConfiguration
        }
        return try selected.sorted().map {
            try ShardIdentity(botID: botID, topologyGeneration: topologyGeneration, index: $0,
                              count: recommendedShardCount)
        }
    }
}

/// Atomic admission result. Waiting does not reserve quota, retain tasks or enqueue callers.
public enum GatewayStartAdmission: Sendable, Equatable {
    case admitted
    case wait(Duration)
}

/// Shared per-credential Identify coordination, injected independently of shard ownership.
///
/// All processes sharing one bot credential must use the same logical coordinator.
/// Reservations consume quota before the socket write and are never refunded: ambiguous
/// sends may already have reached Discord. Resume never calls this boundary. External
/// stores must make admission atomic, bound metadata and fail closed during outages.
public protocol GatewayStartupCoordinator: Sendable {
    /// Reserves one immediate Identify or returns its earliest permitted retry delay.
    /// - Parameter shard: Fixed topology source; budgets must survive topology changes.
    /// - Returns: Immediate consumed allowance, or positive monotonic delay without admission.
    /// - Throws: Cancellation, unavailable coordination, wrong identity, or required discovery refresh.
    func reserveIdentify(for shard: ShardIdentity) async throws -> GatewayStartAdmission
}

/// Bounded in-process startup state for exactly one public bot identity.
///
/// One actor must be shared by all that bot's clients/workers/topologies. It cannot
/// coordinate separate processes or persist across restart; fleets inject durable stores.
/// A discovery reset replenishes once. Once that subsequent budget is exhausted a fresh
/// server snapshot is required, because reset_after does not specify a recurring period.
/// A zero delay schedules no reset and never replenishes the reported remaining starts.
public actor InProcessGatewayStartupCoordinator<C: Clock>: GatewayStartupCoordinator where C.Duration == Duration {
    private let clock: C
    private let botID: UserID
    private var limit: GatewaySessionStartLimit
    private var remaining: Int
    private var resetAt: C.Instant?
    private var buckets: [Int: C.Instant] = [:]

    /// Creates one startup ledger from a current discovery response without starting work.
    /// - Parameters:
    ///   - botID: Public identity corresponding to the shared bot credential.
    ///   - limit: Already validated server allowances; zero reset delay schedules no refill.
    ///     Construction must not be repeated to reset quota.
    ///   - clock: Shared monotonic clock defining all bucket/reset instants.
    public init(botID: UserID, limit: GatewaySessionStartLimit, clock: C) {
        self.botID = botID; self.limit = limit; self.clock = clock
        remaining = limit.remaining
        resetAt = limit.resetAfter > .zero ? clock.now.advanced(by: limit.resetAfter) : nil
    }

    /// Atomically checks quota and the shard-index modulo concurrency bucket.
    /// - Parameter shard: Source belonging to this bot; topology generation never changes quota.
    /// - Returns: Admission consuming one start, or delay until reset/bucket expiry.
    /// - Throws: Cancellation, wrong identity, or `startupRefreshRequired` when quota is exhausted
    ///   without a scheduled reset, including a zero-delay discovery snapshot.
    public func reserveIdentify(for shard: ShardIdentity) throws -> GatewayStartAdmission {
        try Task.checkCancellation()
        guard shard.botID == botID else { throw GatewayFailure.invalidConfiguration }
        let now = clock.now
        if let resetAt, now >= resetAt { remaining = limit.total; self.resetAt = nil }
        let bucket = shard.index % limit.maxConcurrency
        var delay = Duration.zero
        if remaining == 0 {
            guard let resetAt else { throw GatewayFailure.startupRefreshRequired }
            delay = now.duration(to: resetAt)
        }
        if let next = buckets[bucket], next > now { delay = max(delay, now.duration(to: next)) }
        if delay > .zero { return .wait(delay) }
        remaining -= 1
        buckets[bucket] = now.advanced(by: .seconds(5))
        return .admitted
    }

    /// Applies a fresh discovery snapshot conservatively without resetting active bucket windows.
    /// Replaces remaining quota only after a known positive reset; otherwise retains the lower
    /// local/server allowance. Zero clears the deadline, including a pending positive reset.
    /// A subsequent positive delay schedules a one-time refill without immediate replenishment.
    /// - Parameter snapshot: Current server allowances for this same credential.
    /// - Throws: `invalidConfiguration` if concurrency changes; explicitly replace the deployment
    ///   coordinator only after draining workers when changing bucket topology.
    public func refresh(_ snapshot: GatewaySessionStartLimit) throws {
        guard snapshot.maxConcurrency == limit.maxConcurrency else { throw GatewayFailure.invalidConfiguration }
        let now = clock.now
        // A nil deadline after a positive snapshot means its one known reset was already consumed.
        let knownResetElapsed = limit.resetAfter > .zero && (resetAt.map { now >= $0 } ?? true)
        if knownResetElapsed { remaining = snapshot.remaining }
        else { remaining = min(remaining, snapshot.remaining) }
        limit = snapshot
        if snapshot.resetAfter == .zero { resetAt = nil }
        else {
            let proposed = now.advanced(by: snapshot.resetAfter)
            // Extending an existing reset is conservative; shortening it could invent allowance.
            resetAt = resetAt.map { max($0, proposed) } ?? proposed
        }
    }

    /// Returns remaining local starts for diagnostics and deterministic tests, without refreshing time.
    /// - Returns: Nonnegative locally recorded remaining allowance.
    public func remainingStarts() -> Int { remaining }
}
