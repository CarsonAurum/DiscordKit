//
//  RESTManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Logging
import NIO
import NIOHTTP1
import AsyncHTTPClient

// MARK: - RESTManager

/// A manager handling HTTP requests to Discord.
actor RESTManager {
    
    /// Construct a new rest manager.
    /// - Parameters:
    ///   - coders: The JSON coders to use when working with requests over the REST API.
    ///   - token: The token to use when authorizing endpoint requests.
    ///   - eventLoopGroup: The event loop on which requests to the REST API should be made.
    init(coders: CoderPackage, token: String, eventLoopGroup: EventLoopGroup) {
        self.headers = [
            "Authorization": "Bot \(token)",
            "Content-Type": "application/json"
        ]
        self.client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        self.coders = coders
    }
    
    /// Get the primary gateway connection information from discord.
    /// - Returns: The payload, if it exists.
    func getGatewayBot() async throws -> GatewayBot.Payload? {
        let request = try GatewayBot(client: self.client, headers: self.headers, decoder: coders.decoder)
        return try await request.get()
    }
    
    func registerGlobalCommand(appID: Snowflake, _ command: BotCommand) async throws {
        let request = GlobalApplicationCommands(client: self.client, headers: headers, appID: appID, coders: coders)
        let result = try await request.post(command)
        if let result = result {
            logger.trace("Response: \(result)")
        }
    }
    
    func registerGlobalCommands(appID: Snowflake, _ commands: [BotCommand]) async throws {
        let request = GlobalApplicationCommands(client: self.client, headers: self.headers, appID: appID, coders: coders)
        let result = try await request.put(commands)
        if let result = result {
            logger.trace("Response: \(result)")
        }
    }
    
    /// Create a new context for a given interaction.
    /// - Parameter interaction: The interaction whose context will be generated.
    /// - Returns: The newly created context.
    func getInteractionContext(_ interaction: Interaction) -> InteractionContext {
        InteractionContext(client: self.client, headers: self.headers, coders: coders, interaction: interaction)
    }
    
    // MARK: Private
    
    /// The headers to attach to a Discord request.
    private let headers: HTTPHeaders
    
    /// The client on which requests will be executed.
    private let client: HTTPClient
    
    /// The JSON coders to use when working with requests from the REST API.
    private let coders: CoderPackage
    
    /// The logger to use within this manager.
    private let logger = Logger(label: "RESTManager")
}
