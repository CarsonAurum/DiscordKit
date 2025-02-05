//
//  IdentifyManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import Foundation
import Logging

actor IdentifyManager {
    private let logger = Logger(label: "IdentifyManager")
    private weak var socket: WebSocketManager?
    private var identifyPayload: IdentifyPayload
    private let token: String
    
    // When true, we will attempt a resume upon receiving the hello event.
    private(set) var shouldAttemptResume: Bool = false
    
    /// The reconnect manager for storing session IDs.
    private let reconnectManager: ReconnectManager
    
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
        // When sending a fresh identify, clear any resume flag.
        shouldAttemptResume = false
        await self.socket?.send(opcode: .identify, data: identifyPayload)
    }
    
    /// Send a resume payload.
    func sendResume(sequence: Int? = nil) async {
        // Retrieve the stored session ID from the reconnect manager.
        guard let sessionID = await reconnectManager.getSessionID() else {
            logger.error("Cannot resume: No session ID set.")
            return
        }
        // After attempting a resume, clear the flag.
        shouldAttemptResume = false
        await self.socket?.send(opcode: .resume, data: ResumePayload(
            token: token,
            sessionID: sessionID,
            sequence: sequence
        ))
    }
    
    /// Save the session ID from a ready event.
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
