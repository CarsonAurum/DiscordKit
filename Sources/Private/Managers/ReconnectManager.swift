//
//  ReconnectManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation
import Logging

/// An actor to manage reconnection logic for the Discord gateway.
actor ReconnectManager {
    
    /// The URL endpoint to reconnect to.
    private var endpoint: String?
    
    /// The session identifier (used during resume).
    private var sessionID: String?
    
    /// The current number of reconnect attempts.
    private var reconnectAttempts: Int = 0
    
    /// The maximum allowed reconnect attempts.
    private let maxReconnectAttempts: Int = 5
    
    /// A logger to log reconnection-related events.
    private let logger = Logger(label: "ReconnectManager")
    
    // MARK: - Endpoint Management
    
    /// Store the endpoint.
    func setEndpoint(_ endpoint: String) {
        self.endpoint = endpoint
        logger.debug("Stored reconnect endpoint: \(endpoint)")
    }
    
    /// Retrieve the stored endpoint.
    func getEndpoint() -> String? {
        return endpoint
    }
    
    // MARK: - Session ID Management
    
    /// Save the session ID.
    func setSessionID(_ sessionID: String) {
        self.sessionID = sessionID
        logger.debug("Stored session ID: \(sessionID)")
    }
    
    /// Clear the saved session.
    func clearSession() {
        self.sessionID = nil
        logger.debug("Cleared session ID")
    }
    
    // MARK: - Reconnection Logic
    
    /// Attempt a reconnection using the stored endpoint.
    /// - Parameter socketManager: The WebSocketManager to use for reconnecting.
    func attemptReconnect(socketManager: WebSocketManager) async throws {
        guard let endpoint = self.endpoint else {
            logger.error("No stored endpoint to reconnect to.")
            return
        }
        
        if reconnectAttempts >= maxReconnectAttempts {
            logger.error("Maximum reconnect attempts reached (\(maxReconnectAttempts)). Terminating connection.")
            socketManager.terminate()
            return
        }
        
        reconnectAttempts += 1
        logger.info("Attempting reconnect \(reconnectAttempts) of \(maxReconnectAttempts) to \(endpoint)")
        try await socketManager.connect(to: endpoint)
        reconnectAttempts = 0
    }
}
