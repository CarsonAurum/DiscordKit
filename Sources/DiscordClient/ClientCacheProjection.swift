import DiscordCache
import DiscordCore
import DiscordGateway
import DiscordHTTP

/// Explicit bridge between optional JSON entity state and independently adopted Gateway/HTTP.
/// The cache itself imports neither transport nor Gateway. Share one cache across scopes to
/// enforce aggregate retention/refresh limits; rotate the scope on credential/visibility changes.
public struct ClientCacheProjection<C: Clock>: Sendable where C.Duration == Duration {
    public let cache: EntityCache<C>
    public let scope: CacheScope

    /// Binds an opt-in cache to this credential, intents and visibility generation.
    /// - Parameters:
    ///   - cache: Shared bounded entity projection owner, separate from HTTP byte reuse.
    ///   - scope: Nonsecret identity/intents/visibility scope, never a token. Create a new
    ///     visibility generation after a fresh client session to avoid reusing old sequence domains.
    public init(cache: EntityCache<C>, scope: CacheScope) { self.cache = cache; self.scope = scope }

    /// Applies documented entity dispatches before broadcast publication without fetching.
    /// - Parameter event: Ordered event with local socket generation and exact sparse data.
    /// - Throws: Cache validation/capacity/closed failures; unknown dispatches do nothing.
    public func observe(_ event: GatewayEvent) async throws {
        guard event.opcode == 0, let name = event.name else { return }
        _ = try await cache.observeGateway(name: name, data: event.data, scope: scope,
            shard: event.shard.index, generation: event.socketGeneration, sequence: event.sequence)
    }

    /// Creates typed REST access with conservative pre/post local-mutation identity invalidation.
    /// - Parameter rest: Authenticated executor sharing the same credential/intents visibility.
    /// - Returns: Sendable services; HTTP rate/retry and response reuse remain independently owned.
    public func services(rest: RESTClient<C>) -> ServiceContext<C> {
        ServiceContext(rest: rest) { await cache.invalidateVisibility(identity: scope.identity) }
    }
}
