import DiscordCache
import DiscordCore
import DiscordGateway
import DiscordModels
import DiscordTransport
import Foundation
import Synchronization

/// Local fixed-working-set evidence, separating logical population from actual retained objects.
struct CacheLoadReport: Codable, Sendable {
    let scenario: String
    let profile: String
    let logicalAccounts: Int
    let selectedScopes: Int
    let configuredRounds: Int
    let completedRounds: Int
    let configuredDurationSeconds: Int?
    let checkpoints: [CacheProcessCheckpoint]
    let workingSetKeysPerScope: Int
    let offeredRefreshCalls: Int
    let completedRefreshCalls: Int
    let actualLoaderCalls: Int
    let capacityRefusals: Int
    let coalescedReads: UInt64
    let evictions: UInt64
    let expirations: UInt64
    let recoveryReads: Int
    let healthyBroadcastDeliveries: Int
    let slowSubscriberResynchronizations: Int
    let maximumEntries: Int
    let maximumAccountedBytes: Int
    let peakEntries: Int
    let peakAccountedBytes: Int
    let peakRefreshes: Int
    let peakWaiters: Int
    let peakBufferedEvents: Int
    let entriesAfterShutdown: Int
    let refreshesAfterShutdown: Int
    let waitersAfterShutdown: Int
    let subscriptionsAfterShutdown: Int
    let bufferedEventsAfterShutdown: Int
    let durationSeconds: Double
    let cpuSeconds: Double
    let before: ProcessSample
    let afterShutdown: ProcessSample
    let notes: [String]
}

/// One bounded process/accounted-cache sample during a real-time fixed-working-set run.
struct CacheProcessCheckpoint: Codable, Sendable {
    let completedRounds: Int
    let elapsedSeconds: Double
    let entries: Int
    let accountedBytes: Int
    let process: ProcessSample
}

/// A controllable clock used only by the local TTL workload; cache operations never sleep.
@available(macOS 15, *)
final class CacheLoadClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    private let state: Mutex<Instant>

    /// Creates one process-local time domain without background work or timers.
    init() { state = Mutex(ContinuousClock().now) }

    /// Reads explicitly advanced monotonic time under a compiler-checked mutex.
    var now: Instant { state.withLock { $0 } }
    /// Reports nanosecond resolution without reading wall time.
    var minimumResolution: Duration { .nanoseconds(1) }

    /// Advances this deterministic freshness domain without waiting in real time.
    /// - Parameter duration: Nonnegative finite internal workload step; negative values are ignored.
    func advance(by duration: Duration) {
        guard duration >= .zero else { return }
        state.withLock { $0 = $0.advanced(by: duration) }
    }

    /// Satisfies Clock for read-only cache use while refusing unsupported future sleeps.
    /// - Parameters:
    ///   - deadline: Clock-local deadline; present/past deadlines return immediately.
    ///   - tolerance: Ignored because no asynchronous timers are supported.
    /// - Throws: Cancellation or `unsupportedScenario` for a future deadline.
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        guard deadline <= now else { throw LoadFailure.unsupportedScenario }
    }
}

/// One bounded refresh barrier makes admission, coalescing and overload counts reproducible.
actor CacheLoadGate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var released = false
    private var cancelled = false
    private var loaderCalls = 0
    private var refusals = 0
    private var failures = 0

    /// Counts the sole admitted loader and holds it until all finite offers have registered.
    /// - Parameter snapshot: Exact complete local response to return when released.
    /// - Returns: The supplied snapshot without I/O or additional tasks.
    /// - Throws: Cancellation, including cancellation before continuation registration.
    func load(_ snapshot: EntitySnapshot) async throws -> EntitySnapshot {
        loaderCalls += 1
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, any Error>) in
                if cancelled { pending.resume(throwing: CancellationError()) }
                else if released { pending.resume() }
                else { continuation = pending }
            }
        } onCancel: { Task { await self.cancel() } }
        try Task.checkCancellation()
        return snapshot
    }

    /// Counts one fail-fast refresh refusal; no rejected task is retained.
    func recordRefusal() { refusals += 1 }

    /// Signals an unexpected child error so the finite admission barrier cannot wait forever.
    func recordFailure() { failures += 1 }

    /// Captures scalar progress needed to release the loader deterministically.
    /// - Returns: Exact loader-start, capacity-refusal and unexpected-error counts for this storm.
    func counts() -> (calls: Int, refusals: Int, failures: Int) { (loaderCalls, refusals, failures) }

    /// Releases the single pending loader, or makes a later registration complete immediately.
    func release() { released = true; continuation?.resume(); continuation = nil }

    /// Resumes owned pending work with cancellation, including a pre-registration race.
    private func cancel() {
        cancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

/// Fixed-size, credential-free cache/broadcast recovery exercise; no sockets or population-sized arrays.
@available(macOS 15, *)
struct CacheLoadRunner: Sendable {
    /// Loads a repository logical profile and executes exact bounded recovery rounds.
    /// - Parameters:
    ///   - profileName: Safe existing accounts-100/accounts-10000/accounts-1000000 profile basename.
    ///   - burst: Offers 64 rather than 16 callers to eight bounded refresh waiter slots.
    ///   - rounds: Exact number of rounds in 1...1,000,000, default eight.
    ///   - scenario: `cache` or `soak`, retained as a descriptive report label.
    ///   - durationSeconds: Optional soak-only minimum real duration in 1...3,600;
    ///     nil runs exact rounds. When supplied, rounds also set minimum work.
    /// - Returns: Encodable local process CPU/RSS, accounted-cache and cleanup evidence.
    /// - Throws: Profile/argument errors, cancellation, or a violated scripted invariant.
    func run(profileName: String, burst: Bool, rounds: Int = 8, scenario: String = "cache",
             durationSeconds: Int? = nil) async throws -> CacheLoadReport {
        let profile = try WorkloadProfile.load(name: profileName,
            directory: LoadPaths.packageDirectory.appendingPathComponent("Profiles"))
        return try await run(profile: profile, burst: burst, rounds: rounds, scenario: scenario, durationSeconds: durationSeconds)
    }

    /// Exercises finite misses, coalescing, overload, eviction, TTL and recovery in one shared authority.
    /// - Parameters:
    ///   - profile: Valid served-end-user profile; selected scopes are 1/2/4 by logical scale.
    ///   - burst: Whether each storm offers 64 callers instead of 16; both admit exactly eight.
    ///   - rounds: Exact positive round count, capped at one million.
    ///   - scenario: Cache or soak label; duration is measured, never inferred from the label.
    ///   - durationSeconds: Soak-only minimum real duration in 1...3,600; nil means exact rounds.
    /// - Returns: Exact work counts and sampled resource peaks after owned cache/hub cleanup.
    /// - Throws: Validation, cancellation, cache/hub errors, or `unexpectedResponse` for any invariant failure.
    /// Every round uses the same 20 keys per scope and a 16-entry-per-identity cap.
    /// Manual TTL advances do not simulate wall-time soaking. A million logical users
    /// creates four scopes and at most 64 child refresh callers, never a million tasks.
    func run(profile: WorkloadProfile, burst: Bool, rounds: Int, scenario: String = "cache",
             durationSeconds: Int? = nil) async throws -> CacheLoadReport {
        try profile.validate()
        guard (1...1_000_000).contains(rounds), scenario == "cache" || scenario == "soak" else { throw LoadFailure.invalidArguments }
        if let durationSeconds {
            guard scenario == "soak", (1...3_600).contains(durationSeconds) else { throw LoadFailure.invalidArguments }
        }
        try Task.checkCancellation()
        let selected = profile.logicalAccounts < 10_000 ? 1 : profile.logicalAccounts < 1_000_000 ? 2 : 4
        let scopes = (0..<selected).map { CacheScope(identity: "local-scope-\($0)", intents: 1 << 15) }
        let clock = CacheLoadClock(), wall = ContinuousClock(), before = ProcessSample.capture(), start = wall.now
        let maximumEntries = selected * 16, maximumBytes = selected * 65_536
        let cache = try EntityCache(clock: clock, policy: .bounded(.init(
            maximumEntries: maximumEntries, maximumBytes: maximumBytes,
            maximumEntriesPerIdentity: 16, maximumBytesPerIdentity: 65_536,
            maximumTimeToLive: .seconds(1), maximumRefreshes: 1,
            maximumRefreshesPerIdentity: 1, maximumWaiters: 8, maximumWaitersPerRefresh: 8)))
        let hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 2, maximumBufferedEvents: 2,
            maximumBufferedBytes: 8_192, maximumEventsPerSubscription: 1, maximumBytesPerSubscription: 4_096))
        let snapshot = EntitySnapshot(fields: ["id": .string("1"), "payload": .string(String(repeating: "x", count: min(1_024, profile.payloadBytes)))], completeness: .complete, provenance: .rest)
        let key = EntityKey(kind: .user, id: 1)
        let offered = burst ? 64 : 16
        var successes = 0, loaders = 0, refusals = 0, recovery = 0, healthy = 0, resyncs = 0
        var peakEntries = 0, peakBytes = 0, peakRefreshes = 0, peakWaiters = 0, peakEvents = 0
        var completedRounds = 0
        var checkpoints = [CacheProcessCheckpoint(completedRounds: 0, elapsedSeconds: 0, entries: 0, accountedBytes: 0, process: before)]
        let sampleInterval = durationSeconds.map { Double($0) / 120 } ?? 0
        var nextSample = sampleInterval
        do {
            while completedRounds < rounds || elapsedSeconds(start, until: wall.now) < Double(durationSeconds ?? 0) {
                try Task.checkCancellation()
                for scope in scopes {
                    await cache.invalidate(scope: scope)
                    let storm = try await refreshStorm(cache: cache, scope: scope, key: key, snapshot: snapshot, offered: offered)
                    successes += storm.successes; loaders += storm.calls; refusals += storm.refusals
                    peakRefreshes = max(peakRefreshes, storm.refreshes); peakWaiters = max(peakWaiters, storm.waiters)
                    for index in 0..<20 {
                        try await cache.apply(snapshot, for: EntityKey(kind: .user, id: UInt64(index + 1)), scope: scope)
                        let value = await cache.statistics()
                        peakEntries = max(peakEntries, value.entries); peakBytes = max(peakBytes, value.bytes)
                        guard value.entries <= maximumEntries, value.bytes <= maximumBytes else { throw LoadFailure.unexpectedResponse }
                    }
                }
                clock.advance(by: .seconds(1))
                for scope in scopes {
                    guard await cache.value(for: key, scope: scope) == nil else { throw LoadFailure.unexpectedResponse }
                    try await cache.apply(snapshot, for: key, scope: scope)
                    await cache.invalidateLocalWrite(keys: [key], scope: scope)
                    guard await cache.value(for: key, scope: scope) == nil else { throw LoadFailure.unexpectedResponse }
                    try await cache.apply(snapshot, for: key, scope: scope)
                    guard await cache.value(for: key, scope: scope) == snapshot else { throw LoadFailure.unexpectedResponse }
                    recovery += 1
                }
                let delivery = try await broadcastRound(hub: hub, sequence: Int64(completedRounds * 3))
                healthy += delivery.healthy; resyncs += delivery.resyncs; peakEvents = max(peakEvents, delivery.peak)
                completedRounds += 1
                let elapsed = elapsedSeconds(start, until: wall.now)
                if elapsed >= nextSample {
                    let usage = await cache.statistics()
                    appendCheckpoint(.init(completedRounds: completedRounds, elapsedSeconds: elapsed,
                        entries: usage.entries, accountedBytes: usage.bytes, process: .capture()), to: &checkpoints)
                    nextSample = elapsed + sampleInterval
                }
            }
            let end = await cache.statistics()
            await cache.close(); await hub.finish()
            let cleaned = await cache.statistics(), broadcast = await hub.snapshot(), after = ProcessSample.capture()
            let seconds = elapsedSeconds(start, until: wall.now)
            appendCheckpoint(.init(completedRounds: completedRounds, elapsedSeconds: seconds,
                entries: cleaned.entries, accountedBytes: cleaned.bytes, process: after), to: &checkpoints)
            return CacheLoadReport(scenario: scenario, profile: profile.name, logicalAccounts: profile.logicalAccounts,
                selectedScopes: selected, configuredRounds: rounds, completedRounds: completedRounds,
                configuredDurationSeconds: durationSeconds, checkpoints: checkpoints, workingSetKeysPerScope: 20,
                offeredRefreshCalls: offered * selected * completedRounds, completedRefreshCalls: successes,
                actualLoaderCalls: loaders, capacityRefusals: refusals, coalescedReads: end.coalescedReads,
                evictions: end.evictions, expirations: end.expirations, recoveryReads: recovery,
                healthyBroadcastDeliveries: healthy, slowSubscriberResynchronizations: resyncs,
                maximumEntries: maximumEntries, maximumAccountedBytes: maximumBytes,
                peakEntries: peakEntries, peakAccountedBytes: peakBytes, peakRefreshes: peakRefreshes,
                peakWaiters: peakWaiters, peakBufferedEvents: peakEvents,
                entriesAfterShutdown: cleaned.entries, refreshesAfterShutdown: cleaned.refreshes,
                waitersAfterShutdown: cleaned.waiters, subscriptionsAfterShutdown: broadcast.subscriptions,
                bufferedEventsAfterShutdown: broadcast.bufferedEvents, durationSeconds: seconds,
                cpuSeconds: max(0, after.cpuSeconds - before.cpuSeconds), before: before, afterShutdown: after,
                notes: ["Logical accounts are served end users; 1/2/4 selected opaque scopes share one local cache authority.",
                        "Fixed 20 keys per scope, at most 64 offered child tasks, zero sockets, credentials or distributed workers.",
                        "Accounted cache bytes exclude allocator/index/task overhead; ProcessSample reports actual process RSS separately.",
                        "Exact finite rounds exercise eviction, refresh overload, TTL, invalidation, recovery and isolated slow-subscriber overflow.",
                        "TTL uses explicitly advanced test time; measured wall duration alone describes soak length. No fleet or 30-minute qualification is inferred.",
                        "At most 121 process/accounted-cache checkpoints expose actual RSS and live heap history; duration mode runs minimum rounds and minimum actual wall time."])
        } catch {
            await cache.close(); await hub.finish()
            throw error
        }
    }

    /// Converts monotonic elapsed duration without loss of fractional seconds.
    /// - Parameters:
    ///   - start: Earlier instant from this run's continuous clock.
    ///   - end: Present instant from the same clock.
    /// - Returns: Signed elapsed seconds, including subsecond fractions.
    private func elapsedSeconds(_ start: ContinuousClock.Instant, until end: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: end)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Retains initial/progress/final process evidence with a strict 121-record memory bound.
    /// - Parameters:
    ///   - value: Latest observation, already detached from runtime ownership.
    ///   - samples: Owned fixed-cap history; its last record is replaced when full.
    /// No histories grow with task count, round count, logical population or duration.
    private func appendCheckpoint(_ value: CacheProcessCheckpoint, to samples: inout [CacheProcessCheckpoint]) {
        if samples.count < 121 { samples.append(value) }
        else { samples[samples.count - 1] = value }
    }

    /// Holds one loader until every finite storm caller is either admitted or refused.
    /// - Parameters:
    ///   - cache: Shared authority with one loader/eight waiter slots.
    ///   - scope: Exact opaque identity/visibility partition.
    ///   - key: Known missing entity key.
    ///   - snapshot: Complete local loader response.
    ///   - offered: Positive finite task count, always 16 or 64.
    /// - Returns: Exact successes/starts/refusals and observed admitted resource peaks.
    /// - Throws: Cancellation or unexpected admission/response errors; group cancellation
    ///   propagates to the owned loader barrier and the cache awaits its cleanup.
    private func refreshStorm(cache: EntityCache<CacheLoadClock>, scope: CacheScope, key: EntityKey,
                              snapshot: EntitySnapshot, offered: Int) async throws
        -> (successes: Int, calls: Int, refusals: Int, refreshes: Int, waiters: Int) {
        let gate = CacheLoadGate()
        return try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<offered {
                group.addTask {
                    do {
                        let value = try await cache.refresh(key: key, scope: scope, requireComplete: true) { try await gate.load(snapshot) }
                        guard value == snapshot else { throw LoadFailure.unexpectedResponse }
                        return 1
                    } catch EntityCacheFailure.capacityExceeded {
                        await gate.recordRefusal()
                        return 0
                    } catch {
                        await gate.recordFailure()
                        throw error
                    }
                }
            }
            var progress = await cache.statistics(), counts = await gate.counts()
            while progress.waiters + counts.refusals + counts.failures < offered || (counts.calls == 0 && counts.failures == 0) {
                try Task.checkCancellation()
                await Task.yield()
                progress = await cache.statistics(); counts = await gate.counts()
            }
            guard progress.waiters == 8, progress.refreshes == 1, counts.calls == 1, counts.failures == 0 else {
                await gate.release()
                throw LoadFailure.unexpectedResponse
            }
            await gate.release()
            var successes = 0
            for try await count in group { successes += count }
            return (successes, counts.calls, counts.refusals, progress.refreshes, progress.waiters)
        }
    }

    /// Overflows one deliberately unconsumed queue while draining a healthy subscriber after every publication.
    /// - Parameters:
    ///   - hub: Two-subscription bounded hub, reused only after prior round cancellation.
    ///   - sequence: Nonnegative first event sequence, increasing by three per round.
    /// - Returns: Three healthy deliveries, one explicit resynchronization, and sampled queued peak.
    /// - Throws: Event/subscription/cancellation errors or any continuity/cleanup invariant failure.
    private func broadcastRound(hub: GatewayEventHub, sequence: Int64) async throws -> (healthy: Int, resyncs: Int, peak: Int) {
        let slow = try await hub.subscribe(), healthy = try await hub.subscribe()
        var healthyIterator = healthy.makeAsyncIterator(), slowIterator = slow.makeAsyncIterator(), peak = 0
        for index in 0..<3 {
            let event = try GatewayEvent(shard: .init(botID: .init(rawValue: 1), topologyGeneration: 0, index: 0, count: 1),
                                         name: "LOCAL_CACHE_LOAD", sequence: sequence + Int64(index), data: .object([:]))
            await hub.publish(event)
            let queued = await hub.snapshot()
            peak = max(peak, queued.bufferedEvents)
            guard queued.bufferedEvents <= 2, queued.bufferedBytes <= 8_192,
                  try await healthyIterator.next()?.sequence == event.sequence else { throw LoadFailure.unexpectedResponse }
        }
        do { _ = try await slowIterator.next(); throw LoadFailure.unexpectedResponse }
        catch GatewayEventDeliveryFailure.resynchronizationRequired { }
        await slow.cancel(); await healthy.cancel()
        guard await hub.snapshot().subscriptions == 0 else { throw LoadFailure.unexpectedResponse }
        return (3, 1, peak)
    }
}
