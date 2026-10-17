import Foundation
import Testing
import DiscordCore
import DiscordModels
import DiscordTestSupport
@testable import DiscordCache

/// Deterministic coverage for bounded projections, source evidence, refresh races and cleanup.
@Suite struct DiscordCacheTests {
    /// Rejects invalid budgets before starting work; zero retention remains a valid policy.
    @Test func policyValidation() throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        for invalid in [CacheLimits(maximumEntries: -1), CacheLimits(maximumBytes: -1),
                        CacheLimits(maximumEntriesPerIdentity: -1), CacheLimits(maximumBytesPerIdentity: -1),
                        CacheLimits(maximumTimeToLive: .zero), CacheLimits(maximumTimeToLive: .seconds(Int64.max)),
                        CacheLimits(maximumTimeToLive: .seconds(2_592_001)), CacheLimits(maximumRefreshes: 0),
                        CacheLimits(maximumRefreshesPerIdentity: 0), CacheLimits(maximumWaiters: 0),
                        CacheLimits(maximumWaitersPerRefresh: 0)] {
            #expect(throws: EntityCacheFailure.invalidLimits) { try EntityCache(clock: ManualClock(), policy: .bounded(invalid)) }
        }
        _ = try EntityCache(clock: ManualClock(), policy: .noCache)
        _ = try EntityCache(clock: ManualClock(), policy: .minimal)
        _ = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumEntries: 0)))
        _ = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumTimeToLive: .seconds(2_592_000))))
    }

    /// Sparse omission preserves old data, valid null clears and complete replacement removes omissions.
    @Test func sparseMergeNullAndReplacement() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .channel, id: UInt64.max)
        let scope = cacheScope()
        let initial = EntitySnapshot(fields: ["name": .string("general"), "topic": .string("old")], completeness: .complete)
        #expect(try await cache.apply(initial, for: key, scope: scope) == .stored)
        try await cache.apply(EntitySnapshot(fields: ["topic": .null], nullableFields: ["topic"]), for: key, scope: scope)
        let merged = try #require(await cache.value(for: key, scope: scope))
        #expect(merged.fields["name"] == .string("general"))
        #expect(merged.fields["topic"] == .null)
        #expect(merged.completeness == .complete)
        await #expect(throws: EntityCacheFailure.invalidNullField) {
            try await cache.apply(EntitySnapshot(fields: ["name": .null]), for: key, scope: scope)
        }
        #expect(await cache.value(for: key, scope: scope) == merged)
        try await cache.apply(EntitySnapshot(fields: ["name": .string("new")], completeness: .complete), for: key, scope: scope)
        #expect(await cache.value(for: key, scope: scope)?.fields["topic"] == nil)
    }

    /// Redaction erases old private contents; a later explicit accessible field clears that redaction.
    @Test func redactionAndProvenance() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .message, id: 7)
        let scope = cacheScope()
        try await cache.apply(EntitySnapshot(fields: ["content": .string("private"), "id": .string("7")]), for: key, scope: scope)
        try await cache.apply(EntitySnapshot(fields: [:], redactedFields: ["content"], provenance: .local), for: key, scope: scope)
        let redacted = try #require(await cache.value(for: key, scope: scope))
        #expect(redacted.fields["content"] == nil)
        #expect(redacted.redactedFields == ["content"])
        #expect(redacted.provenance == .local)
        try await cache.apply(EntitySnapshot(fields: ["content": .string("visible")], provenance: .interaction), for: key, scope: scope)
        #expect(await cache.value(for: key, scope: scope)?.redactedFields.isEmpty == true)
        #expect(await cache.value(for: key, scope: scope)?.provenance == .interaction)
    }

    /// Identity, intent and observed visibility revisions each form an independent cache partition.
    @Test func visibilityIsolationAndRedactedDiagnostics() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .user, id: 7)
        let scope = cacheScope()
        try await cache.apply(EntitySnapshot(fields: ["name": .string("private")]), for: key, scope: scope)
        for isolated in [cacheScope(identity: "other"), cacheScope(intents: 0),
                         CacheScope(identity: scope.identity, intents: scope.intents, visibilityGeneration: 1)] {
            #expect(await cache.value(for: key, scope: isolated) == nil)
        }
        #expect(!String(describing: scope).contains(scope.identity))
        #expect(!String(reflecting: scope).contains(scope.identity))
        #expect(Mirror(reflecting: scope).children.count == 1)
        for invalid in [CacheScope(identity: "", intents: 0), CacheScope(identity: String(repeating: "a", count: 257), intents: 0)] {
            await #expect(throws: EntityCacheFailure.invalidScope) { try await cache.apply(EntitySnapshot(fields: [:]), for: key, scope: invalid) }
            #expect(await cache.value(for: key, scope: invalid) == nil)
            await #expect(throws: EntityCacheFailure.invalidScope) { try await cache.refresh(key: key, scope: invalid) { EntitySnapshot(fields: [:]) } }
        }
    }

    /// Inclusive virtual-time expiry is capped by policy and nonpositive TTL removes old state.
    @Test func ttlAndNoCache() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let cache = try EntityCache(clock: clock, policy: .bounded(.init(maximumTimeToLive: .seconds(5))))
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        let value = EntitySnapshot(fields: ["id": .string("7")])
        try await cache.apply(value, for: key, scope: scope, timeToLive: .seconds(500))
        try clock.advance(by: .seconds(4))
        #expect(await cache.value(for: key, scope: scope) != nil)
        try clock.advance(by: .seconds(1))
        #expect(await cache.value(for: key, scope: scope) == nil)
        #expect(await cache.statistics().expirations == 1)
        try await cache.apply(value, for: key, scope: scope)
        #expect(try await cache.apply(value, for: key, scope: scope, timeToLive: .zero) == .notRetained)
        #expect(await cache.value(for: key, scope: scope) == nil)
        let disabled = try EntityCache(clock: clock, policy: .noCache)
        #expect(try await disabled.apply(value, for: key, scope: scope) == .notRetained)
        #expect(await disabled.statistics().entries == 0)
        let fetched = try await disabled.refresh(key: key, scope: scope) { value }
        #expect(fetched.fields == value.fields)
        #expect(fetched.provenance == .rest)
        #expect(await disabled.statistics().entries == 0)
    }

    /// Per-identity quotas aggregate different intent partitions; global LRU bounds all clients.
    @Test func aggregateEntriesLRUAndIdentityCaps() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumEntries: 3, maximumEntriesPerIdentity: 2)))
        let first = cacheScope()
        let alternate = cacheScope(intents: 0)
        let other = cacheScope(identity: "other")
        for (id, scope) in [(UInt64(1), first), (2, alternate), (3, other)] {
            try await cache.apply(EntitySnapshot(fields: ["id": .string(String(id))]), for: EntityKey(kind: .user, id: id), scope: scope)
        }
        #expect(await cache.value(for: EntityKey(kind: .user, id: 1), scope: first) != nil)
        try await cache.apply(EntitySnapshot(fields: [:]), for: EntityKey(kind: .user, id: 4), scope: first)
        #expect(await cache.value(for: EntityKey(kind: .user, id: 2), scope: alternate) == nil)
        #expect(await cache.value(for: EntityKey(kind: .user, id: 1), scope: first) != nil)
        try await cache.apply(EntitySnapshot(fields: [:]), for: EntityKey(kind: .user, id: 5), scope: cacheScope(identity: "third"))
        #expect(await cache.value(for: EntityKey(kind: .user, id: 3), scope: other) == nil)
        #expect(await cache.statistics().entries == 3)
        #expect(await cache.statistics().evictions == 2)
    }

    /// Payload/metadata oversize never exceeds budgets or leaves a previously stale projection.
    @Test func byteAndMetadataBounds() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumBytes: 512, maximumBytesPerIdentity: 400)))
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        try await cache.apply(EntitySnapshot(fields: ["name": .string("short")]), for: key, scope: scope)
        #expect(try await cache.apply(EntitySnapshot(fields: ["name": .string(String(repeating: "x", count: 500))]), for: key, scope: scope) == .notRetained)
        #expect(await cache.value(for: key, scope: scope) == nil)
        for fields in [Dictionary(uniqueKeysWithValues: (0..<257).map { (String($0), JSONValue.bool(true)) }),
                       [String(repeating: "k", count: 257): .bool(true)]] {
            #expect(try await cache.apply(EntitySnapshot(fields: fields), for: key, scope: scope) == .notRetained)
        }
        for id in UInt64(0)..<20 {
            try await cache.apply(EntitySnapshot(fields: ["name": .string(String(repeating: "x", count: 90))]),
                                  for: EntityKey(kind: .user, id: id), scope: cacheScope(identity: String(id % 3)))
            let stats = await cache.statistics()
            #expect(stats.bytes <= 512)
        }
        await cache.close()
        #expect(await cache.statistics().bytes == 0)
    }

    /// Byte quotas aggregate one identity's intent partitions without evicting another identity prematurely.
    @Test func identityByteBudgetAcrossIntentPartitions() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumBytes: 4_096, maximumBytesPerIdentity: 400)))
        let snapshot = EntitySnapshot(fields: ["name": .string(String(repeating: "x", count: 120))])
        let first = EntityKey(kind: .user, id: 1), second = EntityKey(kind: .user, id: 2)
        try await cache.apply(snapshot, for: first, scope: cacheScope())
        try await cache.apply(snapshot, for: first, scope: cacheScope(identity: "other"))
        try await cache.apply(snapshot, for: second, scope: cacheScope(intents: 0))
        #expect(await cache.value(for: first, scope: cacheScope()) == nil)
        #expect(await cache.value(for: first, scope: cacheScope(identity: "other")) != nil)
        #expect(await cache.value(for: second, scope: cacheScope(intents: 0)) != nil)
        #expect(await cache.statistics().entries == 2)
        #expect(await cache.statistics().evictions == 1)
    }

    /// Duplicate and old same-shard observations are ignored while a newer session can replace them.
    @Test func duplicateAndGenerationOrdering() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let key = EntityKey(kind: .message, id: 7)
        let first = EntitySnapshot(fields: ["content": .string("new")], order: .init(shard: 0, generation: 2, sequence: 8))
        try await cache.apply(first, for: key, scope: scope)
        for order in [CacheObservationOrder(shard: 0, generation: 2, sequence: 8), .init(shard: 0, generation: 2, sequence: 7),
                      .init(shard: 0, generation: 1, sequence: 100)] {
            #expect(try await cache.apply(EntitySnapshot(fields: ["content": .string("old")], order: order), for: key, scope: scope) == .ignoredStale)
        }
        #expect(await cache.value(for: key, scope: scope)?.fields == first.fields)
        #expect(try await cache.apply(EntitySnapshot(fields: [:], order: .init(shard: 0, generation: 3, sequence: 0)), for: key, scope: scope) == .stored)
        #expect(try await cache.apply(EntitySnapshot(fields: [:], order: .init(shard: 1, generation: 0, sequence: 0)), for: key, scope: scope) == .stored)
        for order in [CacheObservationOrder(shard: -1, generation: 0, sequence: 0), .init(shard: 0, generation: 0, sequence: -1)] {
            await #expect(throws: EntityCacheFailure.invalidOrder) { try await cache.apply(EntitySnapshot(fields: [:], order: order), for: key, scope: scope) }
        }
    }

    /// One hundred equivalent eligible misses produce one loader and fresh event data produces zero.
    @Test func refreshSingleflightAndEventRequestReduction() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init()))
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        let loader = CacheTestLoader()
        let snapshot = EntitySnapshot(fields: ["username": .string("new")], completeness: .complete)
        let readers = (0..<100).map { _ in Task { try await cache.refresh(key: key, scope: scope, requiredFields: ["username"]) { try await loader.load(snapshot) } } }
        try await waitForCache(cache, waiters: 100)
        try await loader.started.wait()
        #expect(await loader.calls == 1)
        loader.release.open()
        for reader in readers { #expect(try await reader.value.fields == snapshot.fields) }
        #expect(await cache.statistics().coalescedReads == 99)
        _ = try await cache.refresh(key: key, scope: scope, requiredFields: ["username"], requireComplete: true) {
            Issue.record("A sufficiently complete cached snapshot must avoid another REST request")
            return snapshot
        }
        #expect(await cache.statistics().refreshStarts == 1)
        #expect(await cache.statistics().waiters == 0)
        #expect(await cache.statistics().refreshes == 0)
    }

    /// Independent scoped reads do not coalesce and both successful fetches may complete.
    @Test func refreshIsolationAndConcurrentSuccess() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .user, id: 7)
        let scopes = [cacheScope(), cacheScope(identity: "other"), cacheScope(intents: 0)]
        let loader = CacheTestLoader()
        let tasks = scopes.map { scope in Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: ["name": .string(scope.identity)])) } } }
        try await waitForCache(cache, waiters: 3)
        try await waitForCacheLoader(loader, calls: 3)
        #expect(await loader.calls == 3)
        loader.release.open()
        for (index, task) in tasks.enumerated() { #expect(try await task.value.fields["name"] == .string(scopes[index].identity)) }
        #expect(await cache.statistics().entries == 3)
    }

    /// New Gateway data supersedes a suspended REST fetch and is returned in place of its old result.
    @Test func staleRESTCannotOverwriteGateway() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .message, id: 7)
        let scope = cacheScope()
        let loader = CacheTestLoader()
        let read = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: ["content": .string("old")])) } }
        try await loader.started.wait()
        try await cache.apply(EntitySnapshot(fields: ["content": .string("event")], order: .init(shard: 0, generation: 1, sequence: 7)), for: key, scope: scope)
        loader.release.open()
        #expect(try await read.value.fields["content"] == .string("event"))
        #expect(await cache.value(for: key, scope: scope)?.fields["content"] == .string("event"))
        #expect(await cache.statistics().staleCompletions == 1)
    }

    /// Observed permission changes or local writes fence fetches even after entry eviction/removal.
    @Test(arguments: [0, 1, 2, 3]) func invalidationFencesREST(mode: Int) async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .message, id: 7, guildID: GuildID(rawValue: 1))
        let scope = cacheScope()
        let loader = CacheTestLoader()
        let read = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: ["content": .string("old")])) } }
        try await loader.started.wait()
        switch mode {
        case 0: await cache.invalidate(scope: scope)
        case 1: await cache.invalidateVisibility(identity: scope.identity)
        case 2: await cache.invalidateLocalWrite(keys: [key], scope: scope)
        default: await cache.invalidateGuild(GuildID(rawValue: 1), scope: scope)
        }
        loader.release.open()
        await #expect(throws: EntityCacheFailure.superseded) { try await read.value }
        #expect(await cache.value(for: key, scope: scope) == nil)
    }

    /// Auth/transient loader failures are delivered and never cached as absent resources.
    @Test func refreshErrorsAndInsufficientData() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .user, id: 7)
        let scope = cacheScope()
        await #expect(throws: CacheTestFailure.network) {
            try await cache.refresh(key: key, scope: scope) { throw CacheTestFailure.network }
        }
        #expect(await cache.value(for: key, scope: scope) == nil)
        await #expect(throws: EntityCacheFailure.insufficientSnapshot) {
            try await cache.refresh(key: key, scope: scope, requiredFields: ["username"], requireComplete: true) { EntitySnapshot(fields: [:]) }
        }
        await #expect(throws: EntityCacheFailure.capacityExceeded) {
            try await cache.refresh(key: key, scope: scope, requiredFields: [String(repeating: "x", count: 257)]) { EntitySnapshot(fields: [:]) }
        }
    }

    /// One canceled subscriber leaves another intact, and the final subscriber awaits loader cleanup.
    @Test func independentAndFinalWaiterCancellation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        let loader = CacheTestLoader()
        let first = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: [:])) } }
        let second = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: [:])) } }
        try await waitForCache(cache, waiters: 2)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await cache.statistics().refreshes == 1)
        #expect(await cache.statistics().waiters == 1)
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await cache.statistics().refreshes == 0)
        #expect(await cache.statistics().waiters == 0)
        #expect(loader.release.waitingCount == 0)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.refresh(key: key, scope: scope) { EntitySnapshot(fields: [:]) }
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
    }

    /// Aggregate and per-identity refresh/waiter caps reject excess offered work without extra tasks.
    @Test func refreshAndWaiterBounds() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumRefreshes: 2,
            maximumRefreshesPerIdentity: 1, maximumWaiters: 3, maximumWaitersPerRefresh: 2)))
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        let loader = CacheTestLoader()
        let first = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: [:])) } }
        try await loader.started.wait()
        await #expect(throws: EntityCacheFailure.capacityExceeded) {
            try await cache.refresh(key: EntityKey(kind: .user, id: 8), scope: cacheScope(intents: 0)) { EntitySnapshot(fields: [:]) }
        }
        let second = Task { try await cache.refresh(key: key, scope: scope) { EntitySnapshot(fields: [:]) } }
        try await waitForCache(cache, waiters: 2)
        await #expect(throws: EntityCacheFailure.capacityExceeded) {
            try await cache.refresh(key: key, scope: scope) { EntitySnapshot(fields: [:]) }
        }
        let third = Task { try await cache.refresh(key: key, scope: cacheScope(identity: "other")) { try await loader.load(EntitySnapshot(fields: [:])) } }
        try await waitForCache(cache, waiters: 3)
        await #expect(throws: EntityCacheFailure.capacityExceeded) {
            try await cache.refresh(key: key, scope: cacheScope(identity: "third")) { EntitySnapshot(fields: [:]) }
        }
        #expect(await cache.statistics().refreshes == 2)
        loader.release.open()
        _ = try await first.value
        _ = try await second.value
        _ = try await third.value
    }

    /// Aggregate refresh admission refuses another identity even when subscriber capacity remains available.
    @Test func aggregateRefreshLimitWithSpareWaiterCapacity() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumRefreshes: 1, maximumWaiters: 10)))
        let key = EntityKey(kind: .user, id: 7)
        let loader = CacheTestLoader()
        let first = Task { try await cache.refresh(key: key, scope: cacheScope()) { try await loader.load(EntitySnapshot(fields: [:])) } }
        try await loader.started.wait()
        await #expect(throws: EntityCacheFailure.capacityExceeded) {
            try await cache.refresh(key: key, scope: cacheScope(identity: "other")) { EntitySnapshot(fields: [:]) }
        }
        #expect(await cache.statistics().waiters == 1)
        #expect(await cache.statistics().refreshes == 1)
        loader.release.open()
        _ = try await first.value
    }

    /// Shutdown is repeatable, awaits active loader cleanup, clears bytes and rejects new work.
    @Test func closeOwnsRefreshCleanup() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let key = EntityKey(kind: .user, id: 7)
        let loader = CacheTestLoader()
        let read = Task { try await cache.refresh(key: key, scope: scope) { try await loader.load(EntitySnapshot(fields: [:])) } }
        try await loader.started.wait()
        async let first: Void = cache.close()
        async let second: Void = cache.close()
        _ = await (first, second)
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(await cache.statistics().refreshes == 0)
        #expect(await cache.statistics().waiters == 0)
        #expect(await cache.statistics().bytes == 0)
        #expect(await cache.value(for: key, scope: scope) == nil)
        await #expect(throws: EntityCacheFailure.closed) { try await cache.apply(EntitySnapshot(fields: [:]), for: key, scope: scope) }
        await #expect(throws: EntityCacheFailure.closed) { try await cache.refresh(key: key, scope: scope) { EntitySnapshot(fields: [:]) } }
    }

    /// Observed destructive visibility changes purge every partition of the same credential,
    /// preserve other credentials and retain the new tombstone only in its observing partition.
    /// - Parameter name: Guild removal/unavailability, channel deletion or member removal dispatch.
    @Test(arguments: ["GUILD_DELETE", "GUILD_UNAVAILABLE", "GUILD_CREATE_UNAVAILABLE", "CHANNEL_DELETE", "GUILD_MEMBER_REMOVE"])
    func destructiveEventsInvalidateIdentityPartitions(name: String) async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let observer = cacheScope()
        let alternate = CacheScope(identity: observer.identity, intents: 0, visibilityGeneration: 1)
        let other = cacheScope(identity: "independent-credential")
        let previous = EntityKey(kind: .message, id: 77, guildID: GuildID(rawValue: 1))
        for scope in [observer, alternate, other] {
            try await cache.apply(EntitySnapshot(fields: ["content": .string("old")]), for: previous, scope: scope)
        }
        let event: String
        let data: JSONValue
        let key: EntityKey
        switch name {
        case "GUILD_MEMBER_REMOVE":
            event = name
            data = .object(["guild_id": .string("1"), "user": .object(["id": .string("2")])])
            key = EntityKey(kind: .member, id: 2, guildID: GuildID(rawValue: 1))
        case "CHANNEL_DELETE":
            event = name
            data = .object(["id": .string("2"), "guild_id": .string("1")])
            key = EntityKey(kind: .channel, id: 2, guildID: GuildID(rawValue: 1))
        default:
            event = name == "GUILD_CREATE_UNAVAILABLE" ? "GUILD_CREATE" : "GUILD_DELETE"
            var fields: [String: JSONValue] = ["id": .string("1")]
            if name != "GUILD_DELETE" { fields["unavailable"] = .bool(true) }
            data = .object(fields)
            key = EntityKey(kind: .guild, id: 1)
        }
        #expect(try await cache.observeGateway(name: event, data: data, scope: observer,
            shard: 0, generation: 1, sequence: 1) == .stored)
        #expect(await cache.value(for: previous, scope: observer) == nil)
        #expect(await cache.value(for: previous, scope: alternate) == nil)
        #expect(await cache.value(for: previous, scope: other)?.fields["content"] == .string("old"))
        #expect(await cache.value(for: key, scope: observer)?.availability ==
            (name.contains("UNAVAILABLE") ? .unavailable : .deleted))
        #expect(await cache.value(for: key, scope: alternate) == nil)
    }

    /// Invalid interaction guild context fails atomically instead of creating a context-free
    /// message or partially applying its accompanying user. Missing context remains valid for DMs.
    @Test func interactionGuildContextValidation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let user = EntityKey(kind: .user, id: 7)
        let message = EntityKey(kind: .message, id: 8)
        try await cache.apply(EntitySnapshot(fields: ["username": .string("previous")]), for: user, scope: scope)
        var fields: [String: JSONValue] = ["user": .object(["id": .string("7"), "username": .string("new")]),
                                         "message": .object(["id": .string("8"), "content": .string("component")])]
        for invalid in [JSONValue.null, .bool(false), .string(""), .string("invalid"), .string("18446744073709551616")] {
            fields["guild_id"] = invalid
            await #expect(throws: EntityCacheFailure.malformedEvent) {
                try await cache.observeGateway(name: "INTERACTION_CREATE", data: .object(fields), scope: scope,
                    shard: 0, generation: 1, sequence: 1)
            }
            #expect(await cache.value(for: user, scope: scope)?.fields["username"] == .string("previous"))
            #expect(await cache.value(for: message, scope: scope) == nil)
        }
        fields.removeValue(forKey: "guild_id")
        #expect(try await cache.observeGateway(name: "INTERACTION_CREATE", data: .object(fields), scope: scope,
            shard: 0, generation: 1, sequence: 2) == .stored)
        #expect(await cache.value(for: message, scope: scope)?.provenance == .interaction)
        fields["guild_id"] = .string(String(UInt64.max))
        #expect(try await cache.observeGateway(name: "INTERACTION_CREATE", data: .object(fields), scope: scope,
            shard: 0, generation: 1, sequence: 3) == .stored)
        #expect(await cache.value(for: EntityKey(kind: .message, id: 8, guildID: GuildID(rawValue: UInt64.max)), scope: scope) != nil)
    }

    /// Unavailable guilds purge children; duplicate delete events cannot erase a newer recreated guild.
    @Test func guildUnavailableDeleteAndRecreate() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let guild = EntityKey(kind: .guild, id: 1)
        let child = EntityKey(kind: .channel, id: 2, guildID: GuildID(rawValue: 1))
        try await cache.observeGateway(name: "GUILD_CREATE", data: .object(["id": .string("1"), "name": .string("guild"), "channels": .array([])]), scope: scope, shard: 0, generation: 1, sequence: 1)
        try await cache.apply(EntitySnapshot(fields: ["id": .string("2")]), for: child, scope: scope)
        try await cache.observeGateway(name: "GUILD_DELETE", data: .object(["id": .string("1"), "unavailable": .bool(true)]), scope: scope, shard: 0, generation: 1, sequence: 2)
        #expect(await cache.value(for: child, scope: scope) == nil)
        #expect(await cache.value(for: guild, scope: scope)?.availability == .unavailable)
        #expect(await cache.value(for: guild, scope: scope)?.fields["name"] == nil)
        try await cache.observeGateway(name: "GUILD_CREATE", data: .object(["id": .string("1"), "name": .string("back")]), scope: scope, shard: 0, generation: 1, sequence: 3)
        #expect(try await cache.observeGateway(name: "GUILD_DELETE", data: .object(["id": .string("1")]), scope: scope, shard: 0, generation: 1, sequence: 2) == .ignoredStale)
        #expect(await cache.value(for: guild, scope: scope)?.availability == .available)
        try await cache.observeGateway(name: "GUILD_DELETE", data: .object(["id": .string("1")]), scope: scope, shard: 0, generation: 1, sequence: 4)
        #expect(await cache.value(for: guild, scope: scope)?.availability == .deleted)
    }

    /// READY begins guilds unavailable, discards only old same-shard/unassigned state and never retains session data.
    @Test func readyInitialUnavailableGuildsAndShardIsolation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let oldChild = EntityKey(kind: .channel, id: 2, guildID: GuildID(rawValue: 1))
        let otherShard = EntityKey(kind: .channel, id: 3, guildID: GuildID(rawValue: 4))
        let unassigned = EntityKey(kind: .user, id: 5)
        try await cache.apply(EntitySnapshot(fields: [:], order: .init(shard: 0, generation: 0, sequence: 9)), for: oldChild, scope: scope)
        try await cache.apply(EntitySnapshot(fields: [:], order: .init(shard: 1, generation: 0, sequence: 9)), for: otherShard, scope: scope)
        try await cache.apply(EntitySnapshot(fields: [:], provenance: .rest), for: unassigned, scope: scope)
        let ready = JSONValue.object([
            "guilds": .array([.object(["id": .string("1")])]),
            "user": .object(["id": .string("42"), "username": .string("bot")]),
            "session_id": .string("session-sentinel"), "resume_gateway_url": .string("wss://sentinel.invalid"),
        ])
        #expect(try await cache.observeGateway(name: "READY", data: ready, scope: scope, shard: 0, generation: 1, sequence: 1) == .stored)
        let guild = EntityKey(kind: .guild, id: 1)
        let initial = try #require(await cache.value(for: guild, scope: scope))
        #expect(initial.availability == .unavailable)
        #expect(initial.completeness == .partial)
        #expect(initial.fields == ["id": .string("1"), "unavailable": .bool(true)])
        #expect(await cache.value(for: oldChild, scope: scope) == nil)
        #expect(await cache.value(for: unassigned, scope: scope) == nil)
        #expect(await cache.value(for: otherShard, scope: scope) != nil)
        let user = try #require(await cache.value(for: EntityKey(kind: .user, id: 42), scope: scope))
        #expect(user.fields["session_id"] == nil && user.fields["resume_gateway_url"] == nil)
        try await cache.observeGateway(name: "GUILD_CREATE", data: .object(["id": .string("1"), "name": .string("available")]), scope: scope, shard: 0, generation: 1, sequence: 2)
        try await cache.apply(EntitySnapshot(fields: [:], order: .init(shard: 0, generation: 1, sequence: 3)), for: oldChild, scope: scope)
        #expect(try await cache.observeGateway(name: "READY", data: ready, scope: scope, shard: 0, generation: 1, sequence: 1) == .ignoredStale)
        #expect(await cache.value(for: oldChild, scope: scope) != nil)
        #expect(await cache.value(for: guild, scope: scope)?.availability == .available)
        try await cache.observeGateway(name: "GUILD_CREATE", data: .object(["id": .string("1"), "unavailable": .bool(true)]), scope: scope, shard: 0, generation: 1, sequence: 4)
        #expect(await cache.value(for: guild, scope: scope)?.availability == .unavailable)
        #expect(await cache.value(for: oldChild, scope: scope) == nil)
        #expect(await cache.value(for: guild, scope: scope)?.fields["name"] == nil)
    }

    /// Oversized initial guild lists retain only the explicit bounded projection slice and report nonretention.
    @Test func readyGuildProjectionLimit() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock(), policy: .bounded(.init(maximumEntries: 512, maximumEntriesPerIdentity: 512)))
        let guilds = (0..<257).map { JSONValue.object(["id": .string(String($0))]) }
        #expect(try await cache.observeGateway(name: "READY", data: .object(["guilds": .array(guilds)]), scope: cacheScope(), shard: 0, generation: 1, sequence: 1) == .notRetained)
        #expect(await cache.statistics().entries == 256)
        #expect(await cache.value(for: EntityKey(kind: .guild, id: 256), scope: cacheScope()) == nil)
        #expect(await cache.value(for: EntityKey(kind: .guild, id: 255), scope: cacheScope())?.availability == .unavailable)
    }

    /// READY validates all supplied identifiers and uncertainty fields before purging any previous session state.
    @Test func malformedReadyPreservesExistingState() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let key = EntityKey(kind: .user, id: 7)
        try await cache.apply(EntitySnapshot(fields: ["username": .string("retained")]), for: key, scope: cacheScope())
        let invalid: [JSONValue] = [
            .object(["user": .null]), .object(["guilds": .null]),
            .object(["guilds": .array([.object(["id": .string("bad")])])]),
            .object(["guilds": .array([.object(["id": .string("1"), "unavailable": .null])])]),
        ]
        for data in invalid {
            await #expect(throws: EntityCacheFailure.malformedEvent) {
                try await cache.observeGateway(name: "READY", data: data, scope: cacheScope(), shard: 0, generation: 1, sequence: 1)
            }
            #expect(await cache.value(for: key, scope: cacheScope())?.fields["username"] == .string("retained"))
        }
        await #expect(throws: EntityCacheFailure.malformedEvent) {
            try await cache.observeGateway(name: "GUILD_CREATE", data: .object(["id": .string("1"), "unavailable": .null]),
                                           scope: cacheScope(), shard: 0, generation: 1, sequence: 1)
        }
    }

    /// Message updates preserve omitted fields, redact suppressed content and retain legitimate null timestamps.
    @Test func gatewaySparseMessagesRedactionAndDeletion() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope(intents: 0)
        let key = EntityKey(kind: .message, id: UInt64.max)
        try await cache.observeGateway(name: "MESSAGE_CREATE", data: .object(["id": .string(String(UInt64.max)), "content": .string("mention exception"), "channel_id": .string("2")]), scope: scope, shard: 0, generation: 1, sequence: 1)
        #expect(await cache.value(for: key, scope: scope)?.fields["content"] == .string("mention exception"))
        try await cache.observeGateway(name: "MESSAGE_UPDATE", data: .object(["id": .string(String(UInt64.max)), "content": .string(""), "edited_timestamp": .null]), scope: scope, shard: 0, generation: 1, sequence: 2)
        let updated = try #require(await cache.value(for: key, scope: scope))
        #expect(updated.fields["content"] == nil)
        #expect(updated.redactedFields.contains("content"))
        #expect(updated.fields["channel_id"] == .string("2"))
        #expect(updated.fields["edited_timestamp"] == .null)
        try await cache.observeGateway(name: "MESSAGE_DELETE", data: .object(["id": .string(String(UInt64.max)), "channel_id": .string("2")]), scope: scope, shard: 0, generation: 1, sequence: 3)
        #expect(await cache.value(for: key, scope: scope)?.availability == .deleted)
        #expect(await cache.value(for: key, scope: scope)?.fields["content"] == nil)
    }

    /// Sparse update/deletion without guild_id still targets the retained guild resource and preserves omission semantics.
    @Test func sparseEventsRecoverKnownGuildContext() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let key = EntityKey(kind: .message, id: 7, guildID: GuildID(rawValue: 1))
        try await cache.observeGateway(name: "MESSAGE_CREATE", data: .object([
            "id": .string("7"), "guild_id": .string("1"), "channel_id": .string("2"), "content": .string("old"),
        ]), scope: scope, shard: 0, generation: 1, sequence: 1)
        try await cache.observeGateway(name: "MESSAGE_UPDATE", data: .object([
            "id": .string("7"), "content": .string("new"),
        ]), scope: scope, shard: 0, generation: 1, sequence: 2)
        #expect(await cache.value(for: key, scope: scope)?.fields["content"] == .string("new"))
        #expect(await cache.value(for: key, scope: scope)?.fields["guild_id"] == .string("1"))
        #expect(await cache.value(for: EntityKey(kind: .message, id: 7), scope: scope) == nil)
        try await cache.observeGateway(name: "MESSAGE_DELETE", data: .object(["id": .string("7")]), scope: scope, shard: 0, generation: 1, sequence: 3)
        #expect(await cache.value(for: key, scope: scope)?.availability == .deleted)
        #expect(await cache.statistics().entries == 1)
        // A different credential cannot infer this guild association from private state.
        try await cache.observeGateway(name: "MESSAGE_UPDATE", data: .object(["id": .string("7"), "content": .string("isolated")]),
                                       scope: cacheScope(identity: "other"), shard: 0, generation: 1, sequence: 1)
        #expect(await cache.value(for: key, scope: cacheScope(identity: "other")) == nil)
        #expect(await cache.value(for: EntityKey(kind: .message, id: 7), scope: cacheScope(identity: "other")) != nil)
    }

    /// Channel deletion invalidates cached child messages and bulk removal retains separate tombstones.
    @Test func channelChildrenAndBulkDeletion() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        for id in UInt64(7)...8 {
            try await cache.observeGateway(name: "MESSAGE_CREATE", data: .object(["id": .string(String(id)), "channel_id": .string("2")]), scope: scope, shard: 0, generation: 1, sequence: Int64(id))
        }
        try await cache.observeGateway(name: "CHANNEL_DELETE", data: .object(["id": .string("2")]), scope: scope, shard: 0, generation: 1, sequence: 9)
        #expect(await cache.value(for: EntityKey(kind: .message, id: 7), scope: scope) == nil)
        try await cache.observeGateway(name: "MESSAGE_DELETE_BULK", data: .object(["ids": .array([.string("7"), .string("8")]), "channel_id": .string("2")]), scope: scope, shard: 0, generation: 1, sequence: 10)
        for id in UInt64(7)...8 { #expect(await cache.value(for: EntityKey(kind: .message, id: id), scope: scope)?.availability == .deleted) }
        #expect(try await cache.observeGateway(name: "MESSAGE_DELETE_BULK", data: .object(["ids": .array((0..<257).map { .string(String($0)) })]), scope: scope, shard: 0, generation: 1, sequence: 11) == .notRetained)
        #expect(await cache.statistics().entries == 0)
    }

    /// Member/role/thread and interaction adapters derive IDs without erasing JSON presence.
    @Test func gatewayOtherProjectionFamilies() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let guild = GuildID(rawValue: 1)
        let events: [(String, JSONValue, EntityKey)] = [
            ("GUILD_MEMBER_ADD", .object(["guild_id": .string("1"), "user": .object(["id": .string("7")]), "nick": .null]), EntityKey(kind: .member, id: 7, guildID: guild)),
            ("GUILD_ROLE_CREATE", .object(["guild_id": .string("1"), "role": .object(["id": .string("8"), "name": .string("role")])]), EntityKey(kind: .role, id: 8, guildID: guild)),
            ("THREAD_CREATE", .object(["guild_id": .string("1"), "id": .string("9"), "parent_id": .string("2")]), EntityKey(kind: .channel, id: 9, guildID: guild)),
            ("USER_UPDATE", .object(["id": .string("10"), "avatar": .null]), EntityKey(kind: .user, id: 10)),
        ]
        for (offset, event) in events.enumerated() {
            try await cache.observeGateway(name: event.0, data: event.1, scope: scope, shard: 0, generation: 1, sequence: Int64(offset))
            #expect(await cache.value(for: event.2, scope: scope) != nil)
        }
        try await cache.observeGateway(name: "GUILD_ROLE_DELETE", data: .object(["guild_id": .string("1"), "role_id": .string("8")]), scope: scope, shard: 0, generation: 1, sequence: 8)
        #expect(await cache.value(for: events[1].2, scope: scope)?.availability == .deleted)
        try await cache.observeGateway(name: "GUILD_MEMBER_REMOVE", data: .object(["guild_id": .string("1"), "user": .object(["id": .string("7")])]), scope: scope, shard: 0, generation: 1, sequence: 9)
        #expect(await cache.value(for: events[0].2, scope: scope)?.availability == .deleted)
        try await cache.observeGateway(name: "INTERACTION_CREATE", data: .object(["user": .object(["id": .string("11")]), "message": .object(["id": .string("12"), "content": .string("component")])]), scope: scope, shard: 0, generation: 1, sequence: 10)
        #expect(await cache.value(for: EntityKey(kind: .message, id: 12), scope: scope)?.provenance == .interaction)
        #expect(await cache.value(for: EntityKey(kind: .user, id: 11), scope: scope) != nil)
    }

    /// Unknown dispatches are ignored and malformed recognized events fail before creating projections.
    @Test func malformedAndUnknownGatewayEvents() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        #expect(try await cache.observeGateway(name: "FUTURE_EVENT", data: .null, scope: scope, shard: 0, generation: 0, sequence: nil) == .ignoredEvent)
        let malformed: [(String, JSONValue)] = [
            ("MESSAGE_CREATE", .null), ("MESSAGE_CREATE", .object([:])),
            ("MESSAGE_CREATE", .object(["id": .string("18446744073709551616")])),
            ("MESSAGE_CREATE", .object(["id": .string("7"), "guild_id": .null])),
            ("GUILD_ROLE_CREATE", .object(["guild_id": .string("1")])),
            ("GUILD_MEMBER_ADD", .object(["user": .object(["id": .string("7")])])),
            ("MESSAGE_DELETE_BULK", .object(["ids": .array([.string("7"), .bool(false)])])),
            ("INTERACTION_CREATE", .object(["user": .null])),
        ]
        for event in malformed {
            await #expect(throws: EntityCacheFailure.malformedEvent) { try await cache.observeGateway(name: event.0, data: event.1, scope: scope, shard: 0, generation: 0, sequence: nil) }
        }
        await #expect(throws: EntityCacheFailure.invalidOrder) { try await cache.observeGateway(name: "MESSAGE_CREATE", data: .object([:]), scope: scope, shard: -1, generation: 0, sequence: nil) }
        await #expect(throws: EntityCacheFailure.invalidNullField) { try await cache.observeGateway(name: "MESSAGE_UPDATE", data: .object(["id": .string("7"), "content": .null]), scope: scope, shard: 0, generation: 0, sequence: nil) }
        #expect(await cache.statistics().entries == 0)
    }

    /// Explicit local invalidation preserves unrelated scopes and supports broad conservative fallback.
    @Test func localWriteAndVisibilityInvalidation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let alternate = cacheScope(intents: 0)
        let other = cacheScope(identity: "other")
        let keys = [EntityKey(kind: .user, id: 7), EntityKey(kind: .user, id: 8)]
        for partition in [scope, alternate, other] {
            for key in keys { try await cache.apply(EntitySnapshot(fields: [:]), for: key, scope: partition) }
        }
        await cache.invalidateLocalWrite(keys: [keys[0]], scope: scope)
        #expect(await cache.value(for: keys[0], scope: scope) == nil)
        #expect(await cache.value(for: keys[1], scope: scope) != nil)
        await cache.invalidateLocalWrite(keys: [], scope: scope)
        #expect(await cache.value(for: keys[1], scope: scope) == nil)
        #expect(await cache.value(for: keys[0], scope: alternate) != nil)
        await cache.invalidateVisibility(identity: scope.identity)
        #expect(await cache.value(for: keys[0], scope: alternate) == nil)
        #expect(await cache.value(for: keys[0], scope: other) != nil)
        await cache.invalidateLocalWrite(keys: Array(repeating: keys[0], count: 257), scope: other)
        #expect(await cache.statistics().entries == 0)
    }

    /// Permission observations purge all old intent partitions before reuse; stale duplicates cannot erase newer data.
    @Test func gatewayPermissionChangesInvalidateAllIdentityPartitions() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let alternate = cacheScope(intents: 0)
        let other = cacheScope(identity: "other")
        let key = EntityKey(kind: .message, id: 7)
        for partition in [scope, alternate, other] {
            try await cache.apply(EntitySnapshot(fields: ["content": .string("previously visible")]), for: key, scope: partition)
        }
        let payload = JSONValue.object(["guild_id": .string("1"), "role": .object(["id": .string("8"), "permissions": .string("1024")])])
        try await cache.observeGateway(name: "GUILD_ROLE_UPDATE", data: payload, scope: scope, shard: 0, generation: 1, sequence: 10)
        #expect(await cache.value(for: key, scope: scope) == nil)
        #expect(await cache.value(for: key, scope: alternate) == nil)
        #expect(await cache.value(for: key, scope: other) != nil)
        try await cache.apply(EntitySnapshot(fields: ["content": .string("revalidated")]), for: key, scope: alternate)
        #expect(try await cache.observeGateway(name: "GUILD_ROLE_UPDATE", data: payload, scope: scope, shard: 0, generation: 1, sequence: 10) == .ignoredStale)
        #expect(await cache.value(for: key, scope: alternate)?.fields["content"] == .string("revalidated"))
    }

    /// Invalid destructive updates leave existing children untouched rather than partially invalidating before error.
    @Test func malformedDestructiveUpdateIsAtomic() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let message = EntityKey(kind: .message, id: 7)
        try await cache.apply(EntitySnapshot(fields: ["channel_id": .string("2")]), for: message, scope: scope)
        await #expect(throws: EntityCacheFailure.invalidNullField) {
            try await cache.observeGateway(name: "CHANNEL_DELETE", data: .object(["id": .string("2"), "type": .null]),
                                           scope: scope, shard: 0, generation: 1, sequence: 1)
        }
        #expect(await cache.value(for: message, scope: scope) != nil)
        await #expect(throws: EntityCacheFailure.invalidNullField) {
            try await cache.observeGateway(name: "INTERACTION_CREATE", data: .object([
                "user": .object(["id": .string("8"), "username": .null]),
                "message": .object(["id": .string("9"), "content": .string("visible")]),
            ]), scope: scope, shard: 0, generation: 1, sequence: 2)
        }
        #expect(await cache.value(for: EntityKey(kind: .message, id: 9), scope: scope) == nil)
    }

    /// Invalid null errors expose only a closed category, even when a field name contains sensitive input.
    @Test func invalidNullDiagnosticsArePayloadFree() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let sentinel = "private-field-sentinel-do-not-log"
        do {
            try await cache.apply(EntitySnapshot(fields: [sentinel: .null]),
                                  for: EntityKey(kind: .user, id: 7), scope: cacheScope())
            Issue.record("Expected invalid null rejection")
        } catch {
            #expect(error as? EntityCacheFailure == .invalidNullField)
            #expect(!String(describing: error).contains(sentinel))
            #expect(!String(reflecting: error).contains(sentinel))
            #expect(Mirror(reflecting: error).children.isEmpty)
        }
    }

    /// Optional nonnullable fields reject explicit null; reviewed nullable guild/member fields preserve it.
    @Test func reviewedTopLevelNullability() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        for (event, invalid) in [("CHANNEL_UPDATE", "owner_id"), ("MESSAGE_UPDATE", "webhook_id"),
                                 ("MESSAGE_UPDATE", "nonce"), ("MESSAGE_UPDATE", "poll"),
                                 ("GUILD_UPDATE", "max_members"), ("GUILD_UPDATE", "max_video_channel_users")] {
            await #expect(throws: EntityCacheFailure.invalidNullField) {
                try await cache.observeGateway(name: event, data: .object(["id": .string("7"), invalid: .null]),
                                               scope: cacheScope(), shard: 0, generation: 1, sequence: nil)
            }
        }
        try await cache.observeGateway(name: "GUILD_UPDATE", data: .object(["id": .string("7"), "region": .null]),
                                       scope: cacheScope(), shard: 0, generation: 1, sequence: 1)
        #expect(await cache.value(for: EntityKey(kind: .guild, id: 7), scope: cacheScope())?.fields["region"] == .null)
        try await cache.observeGateway(name: "GUILD_MEMBER_UPDATE", data: .object([
            "guild_id": .string("7"), "user": .object(["id": .string("8")]), "joined_at": .null, "collectibles": .null,
        ]), scope: cacheScope(), shard: 0, generation: 1, sequence: 2)
        let member = await cache.value(for: EntityKey(kind: .member, id: 8, guildID: GuildID(rawValue: 7)), scope: cacheScope())
        #expect(member?.fields["joined_at"] == .null && member?.fields["collectibles"] == .null)
    }

    /// Obfuscation erases older private channel data across visibility partitions while preserving bounded routing evidence.
    @Test func obfuscatedChannelRedactsPriorVisibility() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let cache = try EntityCache(clock: ManualClock())
        let scope = cacheScope()
        let alternate = cacheScope(intents: 0)
        let other = cacheScope(identity: "other")
        let key = EntityKey(kind: .channel, id: 7, guildID: GuildID(rawValue: 1))
        let old = EntitySnapshot(fields: ["name": .string("private"), "topic": .string("secret"), "custom_private": .string("hidden")])
        for partition in [scope, alternate, other] { try await cache.apply(old, for: key, scope: partition) }
        let flags = JSONValue.number(try JSONNumber(rawValue: "131072"))
        try await cache.observeGateway(name: "CHANNEL_UPDATE", data: .object([
            "id": .string("7"), "guild_id": .string("1"), "flags": flags,
            "type": .number(try JSONNumber(rawValue: "0")), "name": .string("placeholder"),
        ]), scope: scope, shard: 0, generation: 1, sequence: 1)
        let hidden = try #require(await cache.value(for: key, scope: scope))
        #expect(hidden.fields["name"] == nil && hidden.fields["topic"] == nil && hidden.fields["custom_private"] == nil)
        #expect(hidden.fields["flags"] == flags && hidden.fields["type"] != nil)
        #expect(hidden.redactedFields.isSuperset(of: ["name", "topic", "custom_private", "permission_overwrites"]))
        #expect(await cache.value(for: key, scope: alternate) == nil)
        #expect(await cache.value(for: key, scope: other)?.fields["topic"] == .string("secret"))
        try await cache.observeGateway(name: "CHANNEL_UPDATE", data: .object(["id": .string("7"), "topic": .string("unreliable")]),
                                       scope: scope, shard: 0, generation: 1, sequence: 2)
        #expect(await cache.value(for: key, scope: scope)?.fields["topic"] == nil)
        #expect(await cache.value(for: key, scope: scope)?.fields["flags"] == flags)
        await #expect(throws: EntityCacheFailure.malformedEvent) {
            try await cache.observeGateway(name: "CHANNEL_UPDATE", data: .object(["id": .string("7"), "flags": .string("131072")]),
                                           scope: scope, shard: 0, generation: 1, sequence: 3)
        }
        #expect(await cache.value(for: key, scope: scope)?.fields["flags"] == flags)
        try await cache.observeGateway(name: "CHANNEL_UPDATE", data: .object([
            "id": .string("7"), "flags": .number(try JSONNumber(rawValue: "0")), "name": .string("visible"),
        ]), scope: scope, shard: 0, generation: 1, sequence: 4)
        #expect(await cache.value(for: key, scope: scope)?.fields["name"] == .string("visible"))
        #expect(await cache.value(for: key, scope: scope)?.redactedFields.contains("name") == false)
    }
}

/// Distinguishes injected network failures from deterministic synchronization failures.
private enum CacheTestFailure: Error { case network, waiterDeadline }

/// Constructs the opaque test partition with explicit message-content intent by default.
/// - Parameters:
///   - identity: Opaque noncredential label, default credential-a.
///   - intents: Exact intent bits, default MESSAGE_CONTENT.
/// - Returns: A zero-generation partition independent of real credentials.
private func cacheScope(identity: String = "credential-a", intents: UInt64 = 1 << 15) -> CacheScope {
    CacheScope(identity: identity, intents: intents)
}

/// Controls loader completion/cancellation without wall-clock sleeps or live requests.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor CacheTestLoader {
    nonisolated let started = TestBarrier()
    nonisolated let release = TestBarrier()
    private(set) var calls = 0

    /// Records one request and suspends until explicitly released or canceled.
    /// - Parameter snapshot: Successful result returned after the release gate opens.
    /// - Returns: The supplied snapshot without network I/O.
    /// - Throws: Cancellation or bounded test-gate capacity failure.
    func load(_ snapshot: EntitySnapshot) async throws -> EntitySnapshot {
        calls += 1
        started.open()
        try await release.wait()
        return snapshot
    }
}

/// Waits for deterministic actor admission while yielding execution to spawned callers.
/// - Parameters:
///   - cache: Test-owned shared authority using a manual clock.
///   - waiters: Exact number of admitted refresh subscribers expected.
/// - Throws: A finite iteration-budget failure if the expected admission never occurs.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private func waitForCache(_ cache: EntityCache<ManualClock>, waiters: Int) async throws {
    for _ in 0..<100_000 {
        if await cache.statistics().waiters == waiters { return }
        await Task.yield()
    }
    throw CacheTestFailure.waiterDeadline
}

/// Yields until every independently admitted loader records its deterministic start.
/// - Parameters:
///   - loader: Shared test probe used by independently scoped refreshes.
///   - calls: Exact expected loader-start count.
/// - Throws: Finite iteration-budget failure if a loader never begins.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private func waitForCacheLoader(_ loader: CacheTestLoader, calls: Int) async throws {
    for _ in 0..<100_000 {
        if await loader.calls == calls { return }
        await Task.yield()
    }
    throw CacheTestFailure.waiterDeadline
}
