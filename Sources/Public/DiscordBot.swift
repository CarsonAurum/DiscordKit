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

public final actor DiscordBot {
    
    /// Finalize the configuration process and connect to the Discord gateway.
    public func connect(shouldBlock: Bool = false) async throws {
        let endpoint = try await restManager.getGatewayBot()
        guard let url = endpoint?.url else {
            logger.critical("Could not get gateway route.")
            fatalError()
        }
        // Note: the URL string is stored in the reconnect manager for reconnects.
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
    
    public func onReady(_ handler: @Sendable @escaping (ReadyData) async -> Void) async {
        await self.socketHandler.setReadyHandler(handler)
    }
    
    // MARK: - Private
    
    /// The intents to use when connecting to the Discord gateway.
    private let intents: GatewayIntents
    
    /// The logger for the bot.
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
    
    /// The new manager for handling reconnection logic.
    private let reconnectManager: ReconnectManager
    
    public init(token: String, intents: GatewayIntents) {
        self.intents = intents
        self.coders = (JSONEncoder(), JSONDecoder())
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        // Initialize the new ReconnectManager.
        self.reconnectManager = ReconnectManager()
        
        self.socketManager = WebSocketManager(coders: self.coders, eventLoopGroup: self.eventLoopGroup, reconnectManager: reconnectManager)
        self.restManager = RESTManager(coders: self.coders, token: token, eventLoopGroup: self.eventLoopGroup)
        self.heartbeatManager = HeartbeatManager(
            self.socketManager,
            sequenceStream: self.socketManager.sequenceStream
        )
        self.identifyManager = IdentifyManager(socket: socketManager, token: token, intents: intents, reconnectManager: reconnectManager)
        self.socketHandler = WebSocketHandler(
            socketManager: self.socketManager,
            heartbeatManager: self.heartbeatManager,
            identifyManager: self.identifyManager,
            decoder: self.coders.decoder,
            reconnectManager: self.reconnectManager
        )
        Task { await self.socketManager.setHeartbeatManager(self.heartbeatManager) }
    }
}
