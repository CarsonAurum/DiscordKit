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
        #expect(recorder.entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "cache.closed" })
        let recorded = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        for privateValue in ["private_scope_identity", "private_entity_value", "private_loader_error"] {
            #expect(!recorded.contains(privateValue))
        }
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.cache" && $0.level != .info && $0.level != .notice })
        #expect(await cache.statistics().entries == 0)
    }
}
