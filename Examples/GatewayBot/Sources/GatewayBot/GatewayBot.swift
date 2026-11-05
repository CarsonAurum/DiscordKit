// File: Examples/GatewayBot/Sources/GatewayBot/GatewayBot.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCache
import DiscordClient
import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import Foundation
#if os(Linux)
import DiscordNIOTransport
#else
import DiscordFoundationTransport
#endif

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
            let configuration = try ClientConfiguration(intents: [.guilds])
            let budget = try ClientResourceBudget()
            let authority = try ClientAuthority(botID: botID, clock: clock, budget: budget)
            let leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 256)
            let cache = try EntityCache(clock: clock, policy: .minimal)
            let projection = ClientCacheProjection(cache: cache,
                scope: CacheScope(identity: authority.cacheIdentity, intents: GatewayIntents.guilds.rawValue))
            let hub = GatewayEventHub(configuration: try .init())
            #if os(Linux)
            let httpConfiguration = try NIOHTTPConfiguration()
            let socketConfiguration = try NIOWebSocketConfiguration()
            let http = try NIOHTTPTransport(configuration: httpConfiguration)
            let socket: NIOWebSocketTransport
            do {
                socket = try NIOWebSocketTransport(configuration: socketConfiguration)
            } catch {
                await http.close()
                throw error
            }
            #else
            let transportConfiguration = try FoundationTransportConfiguration()
            let http = FoundationHTTPTransport(configuration: transportConfiguration)
            let socket = FoundationWebSocketTransport(configuration: transportConfiguration)
            #endif
            let rates = RateLimitCoordinator(clock: clock)
            let rest = RESTClient(credential: .bot(token), identity: RateLimitIdentity(),
                transport: http, coordinator: rates, clock: clock)
            let client = DiscordClient(token: token, configuration: configuration,
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
