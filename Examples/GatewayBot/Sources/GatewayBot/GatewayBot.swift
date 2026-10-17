import DiscordCache
import DiscordClient
import DiscordCore
import DiscordFoundationTransport
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import Foundation

/// Opt-in bot consumer: receive READY, execute a typed read, then await owned shutdown.
@main struct GatewayBotExample {
    /// Runs only with an explicit bot token and matching public bot user ID.
    /// Construction performs no network work. `run` discovers and supervises sessions;
    /// the consumer owns no heartbeat, reconnect or raw WebSocket work. Only the public
    /// bot ID is printed. Repository checks build this program without authenticated calls.
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["DISCORD_BOT_TOKEN"],
              let rawID = environment["DISCORD_BOT_ID"], let botID = UserID(rawID) else {
            print("Set DISCORD_BOT_TOKEN and its matching DISCORD_BOT_ID to run this example.")
            return
        }
        do {
            let token = try BotToken(value), clock = ContinuousClock()
            let http = FoundationHTTPTransport(configuration: try .init())
            let socket = FoundationWebSocketTransport(configuration: try .init())
            let rates = RateLimitCoordinator(clock: clock)
            let budget = try ClientResourceBudget()
            let authority = try ClientAuthority(botID: botID, clock: clock, budget: budget)
            let leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 256)
            let cache = try EntityCache(clock: clock, policy: .minimal)
            let projection = ClientCacheProjection(cache: cache,
                scope: CacheScope(identity: authority.cacheIdentity, intents: GatewayIntents.guilds.rawValue))
            let rest = RESTClient(credential: .bot(token), identity: RateLimitIdentity(),
                transport: http, coordinator: rates, clock: clock)
            let hub = GatewayEventHub(configuration: try .init())
            let client = DiscordClient(token: token, configuration: try ClientConfiguration(intents: [.guilds]),
                services: projection.services(rest: rest), transport: socket, clock: clock, leases: leases,
                authority: authority, events: hub, project: projection.observe,
                cleanup: { await cache.close(); await rates.close(); await http.close(); await socket.close() })
            do {
                let subscription = try await hub.subscribe()
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await client.run() }
                    group.addTask {
                        for try await event in subscription {
                            if event.name == "READY" {
                                let user = try await client.services.execute(DiscordEndpoints.currentUser())
                                print("Received READY and fetched bot \(user.id.rawValue).")
                                await client.shutdown()
                                return
                            }
                        }
                    }
                    defer { group.cancelAll() }
                    for try await _ in group {}
                }
            } catch {
                await client.shutdown()
                print("Bot stopped after a typed runtime failure; no payloads or credentials are printed.")
            }
        } catch {
            print("Bot configuration is invalid.")
        }
    }
}
