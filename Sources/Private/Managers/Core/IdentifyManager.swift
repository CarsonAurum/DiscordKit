//
//  IdentifyManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import Foundation
import Logging

/// A manager responsible for handling identify and resume payloads.
actor IdentifyManager {
    
    /// The logger for this actor.
    private let logger = Logger(label: "IdentifyManager")
    
    /// The socket over which messages should be sent.
    private weak var socket: WebSocketManager?
    
    /// The computed identify payload.
    private var identifyPayload: IdentifyPayload
    
    /// The bot token.
    private let token: String
    
    /// When true, a resume should be attempted.
    private(set) var shouldAttemptResume: Bool = false
    
    /// The reconnect manager for storing session IDs.
    private let reconnectManager: ReconnectManager
    
    /// Construct a new actor with the given data.
    /// - Parameters:
    ///   - socket: The websocket to send messages over.
    ///   - token: The token associated with this bot.
    ///   - intents: The intents to use when connecting to the gateway.
    ///   - largeThreshold: The number of users before a guild will not include all members.
    ///   - shardInfo: Sharding information
    ///   - presence: The initial presence to use when connecting.
    ///   - reconnectManager: The manager to use when sending reconnect requests.
    init(
        socket: WebSocketManager,
        token: String,
        intents: GatewayIntents = .default,
        largeThreshold: Int? = nil,
        shardInfo: (id: Int, nShards: Int)? = nil,
        presence: Presence? = nil,
        reconnectManager: ReconnectManager
    ) {
        self.socket = socket
        self.token = token
        self.reconnectManager = reconnectManager
        
        let shardInfoComputed: [Int]? = shardInfo.map { [$0.id, $0.nShards] }
        let adjustedThreshold = largeThreshold.map { max(50, min($0, 250)) }
        
        identifyPayload = .init(
            token: token,
            properties: .init(os: "macOS", browser: "DiscordKit", device: "swift-nio"),
            isCompressed: false,
            largeThreshold: adjustedThreshold,
            shardInfo: shardInfoComputed,
            presence: presence,
            intents: intents
        )
    }
    
    /// Send an identify payload.
    func sendIdentify() async {
        shouldAttemptResume = false
        await self.socket?.send(opcode: .identify, data: identifyPayload)
    }
    
    /// Send a resume payload.
    /// - Parameter sequence: The sequence to use when reconnecting.
    func sendResume(sequence: Int? = nil) async {
        guard let sessionID = await reconnectManager.getSessionID() else {
            logger.error("Cannot resume: No session ID set.")
            return
        }
        shouldAttemptResume = false
        await self.socket?.send(opcode: .resume, data: ResumePayload(
            token: token,
            sessionID: sessionID,
            sequence: sequence
        ))
    }
    
    /// Save the session ID from a ready event.
    /// - Parameter sessionID: The session ID to store.
    func setSessionID(_ sessionID: String) async {
        await reconnectManager.setSessionID(sessionID)
        shouldAttemptResume = true
    }
    
    /// Clear the saved session.
    func clearSession() async {
        await reconnectManager.clearSession()
        shouldAttemptResume = false
    }
    
    /// Set whether we should attempt a resume on the next hello.
    func setShouldAttemptResume(_ value: Bool) async {
        self.shouldAttemptResume = value
    }
}
