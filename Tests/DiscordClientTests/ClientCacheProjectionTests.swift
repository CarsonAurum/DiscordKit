import DiscordCache
import DiscordClient
import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing

/// Tests the optional bridge without coupling the cache product to Gateway or HTTP.
@Suite struct ClientCacheProjectionTests {
    /// Ordered dispatches project sparse state while control/unknown observations remain raw-only.
    @Test func projectsOnlyEntityDispatches() async throws {
        let cache = try EntityCache(clock: ContinuousClock())
        let scope = CacheScope(identity: "bot-scope", intents: 1)
        let bridge = ClientCacheProjection(cache: cache, scope: scope)
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        let key = EntityKey(kind: .channel, id: 9)
        try await bridge.observe(GatewayEvent(shard: shard, name: "CHANNEL_CREATE", sequence: 1,
            data: .object(["id": .string("9"), "name": .string("general")]), socketGeneration: 4))
        let snapshot = try #require(await cache.value(for: key, scope: scope))
        #expect(snapshot.fields["name"] == .string("general"))
        #expect(snapshot.order == CacheObservationOrder(shard: 0, generation: 4, sequence: 1))
        try await bridge.observe(GatewayEvent(shard: shard, name: "CHANNEL_UPDATE", sequence: 2,
            data: .object(["id": .string("9"), "topic": .null]), socketGeneration: 4))
        #expect(await cache.value(for: key, scope: scope)?.fields["name"] == .string("general"))
        #expect(await cache.value(for: key, scope: scope)?.fields["topic"] == .null)
        try await bridge.observe(GatewayEvent(shard: shard, opcode: 99, name: nil, sequence: nil, data: .null))
        try await bridge.observe(GatewayEvent(shard: shard, name: "FUTURE", sequence: 3, data: .null))
        #expect(await cache.statistics().entries == 1)
        #expect(bridge.scope == scope)
        await #expect(throws: EntityCacheFailure.malformedEvent) {
            try await bridge.observe(GatewayEvent(shard: shard, name: "CHANNEL_UPDATE", sequence: 4, data: .null))
        }
        await cache.close()
    }

    /// Service writes conservatively invalidate every intent partition for the credential,
    /// retaining unrelated identities and keeping HTTP response caching independently owned.
    @Test func serviceBridgeInvalidatesAllIdentityPartitions() async throws {
        let clock = ContinuousClock()
        let cache = try EntityCache(clock: clock)
        let scope = CacheScope(identity: "one", intents: 1)
        let alternate = CacheScope(identity: "one", intents: 2)
        let other = CacheScope(identity: "two", intents: 1)
        let key = EntityKey(kind: .user, id: 9)
        for partition in [scope, alternate, other] {
            try await cache.apply(EntitySnapshot(fields: ["id": .string("9")]), for: key, scope: partition)
        }
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 204) }])
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let services = ClientCacheProjection(cache: cache, scope: scope).services(rest: rest)
        let endpoint = try Endpoint(method: "DELETE", path: ["projected"], authentication: .none,
            successStatuses: [204]) { try EmptyResponse(data: $0) }
        _ = try await services.execute(endpoint)
        #expect(await cache.value(for: key, scope: scope) == nil)
        #expect(await cache.value(for: key, scope: alternate) == nil)
        #expect(await cache.value(for: key, scope: other) != nil)
        #expect(await transport.executionCount == 1)
        await cache.close()
    }
}
