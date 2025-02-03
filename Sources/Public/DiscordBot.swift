//
//  DiscordBot.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import NIO
import WebSocketKit
import AsyncHTTPClient
import AnyCodable
import Logging

// MARK: - DiscordBot

/// The primary source of truth for the Discord app.
public final actor DiscordBot {
    
    /// Start the bot creation process by providing intents and a token.
    /// - Parameters:
    ///   - token: The token to use when connecting to Discord.
    ///   - intents: The intents to specify when connecting to the Discord gateway.
    public init(token: String, intents: GatewayIntents) {
        self.intents = intents
        self.coders = (JSONEncoder(), JSONDecoder())
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.socketManager = WebSocketManager(coders: self.coders, eventLoopGroup: self.eventLoopGroup)
        self.restManager = RESTManager(coders: self.coders, token: token, eventLoopGroup: self.eventLoopGroup)
        self.heartbeatManager = HeartbeatManager(
            self.socketManager,
            sequenceStream: self.socketManager.sequenceStream
        )
        self.identifyManager = IdentifyManager(socket: socketManager, token: token, intents: intents)
        self.reconnectManager = ReconnectManager(socketManager, token: token)
        self.socketHandler = WebSocketHandler(
            socketManager: self.socketManager,
            heartbeatManager: self.heartbeatManager,
            identifyManager: self.identifyManager,
            reconnectManager: self.reconnectManager,
            decoder: self.coders.decoder
        )
        Task { await self.socketManager.setReconnectManager(reconnectManager) }
    }
    
    /// Finalize the configuration process and connect to the Discord gateway.
    /// - Parameter shouldBlock: `true` if the bot should block the calling thread; `false` otherwise.
    public func connect(shouldBlock: Bool = false) async throws {
        let endpoint = try await restManager.getGatewayBot()
        guard let url = endpoint?.url else {
            logger.critical("Could not get gateway route.")
            fatalError()
        }
        try await socketManager.connect(to: url + "/?v=10&encoding=json")
        logger.info("Connected.")
        if shouldBlock {
            try await socketHandler.handle()
        } else {
            Task {
                try await socketHandler.handle()
            }
        }
    }
    
    /// Disconnect from the socket.
    public func disconnect() async throws {
        try await self.socketManager.disconnect()
        logger.info("Disconnected.")
    }
    
    // MARK: Private
    
    /// The intents to use when connecting to the Discord gateway.
    private let intents: GatewayIntents
    
    /// The logger to use within this manager.
    private let logger = Logger(label: "DiscordBot")
    
    /// The coders to use throughout the library.
    private let coders: CoderPackage
    
    /// The primary event loop group on which all HTTP and Gateway events occur.
    private var eventLoopGroup: EventLoopGroup
    
    /// The manager controlling the web socket connection.
    private let socketManager: WebSocketManager
    
    /// The manager controlling REST connections.
    private let restManager: RESTManager
    
    /// The manager controlling heartbeating.
    private let heartbeatManager: HeartbeatManager
    
    /// The manager to control responses to the web socket.
    private let socketHandler: WebSocketHandler
    
    /// The manager to handle identification to the discord gateway.
    private let identifyManager: IdentifyManager
    
    private let reconnectManager: ReconnectManager
}
