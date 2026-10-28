// File: Tests/DiscordCacheTests/CacheLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCache
import DiscordCore
import DiscordLogging
import DiscordTestSupport
import Testing

/// Verifies native cache diagnostics preserve scope and entity payload confidentiality.
@Suite struct CacheLoggingTests {
    /// Explicit writes/reads/close disclose count-only events; injected refresh failures retain no error text.
    /// - Throws: Unexpected cache policy, write, refresh or ownership failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func payloadScopeAndLoaderErrorsAreRedacted() async throws {
        let recorder = LogRecorder()
        let cache = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try EntityCache(clock: ManualClock())
        }
        #expect(recorder.entries.isEmpty)
        let scope = CacheScope(identity: "private_scope_identity", intents: 0)
        let key = EntityKey(kind: .user, id: 173)
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await cache.apply(.init(fields: ["name": .string("private_entity_value")]), for: key, scope: scope)
            #expect(await cache.value(for: key, scope: scope) != nil)
            await #expect(throws: TestSupportFailure.self) {
                try await cache.refresh(key: EntityKey(kind: .user, id: 174), scope: scope) {
                    throw TestSupportFailure.scripted("private_loader_error")
                }
            }
            await cache.close()
        }
        #expect(recorder.entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "cache.refresh.failed" })
        #expect(recorder.entries.contains { $0.level == .info && $0.metadata["dk.event"] == "cache.closed" })
        let refreshEvents = recorder.entries.filter { $0.label == "discordkit.cache.refresh" }
            .compactMap { $0.metadata["dk.event"]?.description }
        #expect(refreshEvents == ["cache.refresh.requested", "cache.refresh.admitted",
            "cache.refresh.loader_started", "cache.refresh.failed", "cache.refresh.released"])
        #expect(recorder.entries.last?.metadata["dk.refreshes"]?.description == "0")
        #expect(recorder.entries.last?.metadata["dk.waiters"]?.description == "0")
        let recorded = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        for privateValue in ["private_scope_identity", "private_entity_value", "private_loader_error"] {
            #expect(!recorded.contains(privateValue))
        }
        #expect(recorder.entries.allSatisfy { $0.label.hasPrefix("discordkit.cache.") })
        #expect(await cache.statistics().entries == 0)
    }

    /// Count-bound eviction, missing entries, successful refresh reuse and inclusive TTL expiry have distinct trace steps.
    /// - Throws: Unexpected synthetic cache, clock or loader failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func retentionAndRefreshTimeline() async throws {
        let recorder = LogRecorder(), clock = ManualClock()
        let cache = try EntityCache(clock: clock, policy: .bounded(.init(maximumEntries: 1,
            maximumBytes: 4096, maximumEntriesPerIdentity: 1, maximumBytesPerIdentity: 4096,
            maximumTimeToLive: .seconds(1))))
        let scope = CacheScope(identity: "private_identity", intents: 0)
        let first = EntityKey(kind: .user, id: 173), second = EntityKey(kind: .user, id: 174)
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            #expect(await cache.value(for: first, scope: scope) == nil)
            try await cache.apply(.init(fields: ["secret": .string("private_entity")]), for: first, scope: scope)
            try await cache.apply(.init(fields: [:]), for: second, scope: scope)
            #expect(await cache.value(for: first, scope: scope) == nil)
            let loaded = try await cache.refresh(key: first, scope: scope) { .init(fields: [:]) }
            let reused = try await cache.refresh(key: first, scope: scope) {
                Issue.record("Fresh retained snapshot invoked loader")
                return .init(fields: [:])
            }
            #expect(loaded.fields == reused.fields)
            try clock.advance(by: .seconds(1))
            #expect(await cache.value(for: first, scope: scope) == nil)
            await cache.close()
        }
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        for event in ["cache.read.miss", "cache.entry.evicted", "cache.refresh.loader_completed",
            "cache.refresh.released", "cache.refresh.completed", "cache.refresh.reused", "cache.entry.expired"] {
            #expect(events.contains(event))
        }
        #expect(events.filter { $0 == "cache.refresh.admitted" }.count == 1)
        #expect(recorder.entries.filter { $0.metadata["dk.event"] == "cache.entry.evicted" }
            .allSatisfy { $0.level == .trace && $0.metadata["dk.budget"] == "identity" })
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("private_identity") && !rendered.contains("private_entity"))
    }
}
