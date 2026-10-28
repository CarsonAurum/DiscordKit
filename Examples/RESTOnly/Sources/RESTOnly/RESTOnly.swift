// File: Examples/RESTOnly/Sources/RESTOnly/RESTOnly.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordFoundationTransport
import DiscordHTTP
import Foundation

/// A REST-only consumer using an explicitly owned Foundation adapter and shared rate authority.
@main
struct RESTOnly {
    /// Fetches the current bot and application, then awaits adapter cleanup on every exit path.
    /// Reads only `DISCORD_BOT_TOKEN`; the token and server-controlled strings are never printed.
    /// Without a token, exits before network I/O. Running this opt-in example sends real API v10
    /// requests; repository validation only builds it. Errors use fixed category descriptions.
    static func main() async {
        guard let value = ProcessInfo.processInfo.environment["DISCORD_BOT_TOKEN"] else {
            print("Set DISCORD_BOT_TOKEN to run the REST-only example.")
            return
        }
        do {
            let token = try BotToken(value)
            let clock = ContinuousClock()
            let coordinator = RateLimitCoordinator(clock: clock)
            let transport = FoundationHTTPTransport(configuration: try .init())
            let client = RESTClient(credential: .bot(token), identity: RateLimitIdentity(),
                transport: transport, coordinator: coordinator, clock: clock)
            do {
                let user = try await client.execute(DiscordEndpoints.currentUser(), deadline: clock.now.advanced(by: .seconds(30)))
                let application = try await client.execute(DiscordEndpoints.currentApplication(), deadline: clock.now.advanced(by: .seconds(30)))
                print("Fetched bot \(user.id.rawValue) and application \(application.id.rawValue).")
            } catch {
                print("REST request failed; inspect the typed error in your own application.")
            }
            await coordinator.close()
            await transport.close()
        } catch {
            print("REST configuration is invalid.")
        }
    }
}
