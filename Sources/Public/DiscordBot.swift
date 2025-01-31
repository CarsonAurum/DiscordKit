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
    public init(token: String, intents: GatewayIntents) {
        self.intents = intents
        self.coders = (JSONEncoder(), JSONDecoder())
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.socketManager = WebSocketManager(coders: self.coders, eventLoopGroup: self.eventLoopGroup)
        self.restManager = RESTManager(coders: self.coders, token: token, eventLoopGroup: self.eventLoopGroup)
        self.heartbeatManager = HeartbeatManager(self.socketManager, sequenceStream: self.socketManager.sequenceStream)
        self.socketHandler = WebSocketHandler(socketManager: self.socketManager, heartbeatManager: self.heartbeatManager, decoder: self.coders.decoder)
    }
    private let intents: GatewayIntents
    
    private let logger = Logger(label: "DiscordKit")
    
    private let coders: CoderPackage
    
    private var eventLoopGroup: EventLoopGroup
    
    private let socketManager: WebSocketManager
    
    private let restManager: RESTManager
    
    private let heartbeatManager: HeartbeatManager
    
    private let socketHandler: WebSocketHandler
}
