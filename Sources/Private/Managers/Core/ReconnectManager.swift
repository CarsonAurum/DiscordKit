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
    
    private var reconnectEndpoint: String?
    
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
    func setEndpoint(_ endpoint: String, _ type: EndpointType) {
        if type == .reconnect {
            self.reconnectEndpoint = endpoint
            logger.debug("Stored reconnect endpoint: \(endpoint)")
        } else if type == .main {
            self.endpoint = endpoint
            logger.debug("Stored main endpoint: \(endpoint)")
        }
    }
    
    /// Retrieve the stored endpoint.
    func getEndpoint(_ type: EndpointType) -> String? {
        return endpoint
    }

    /// Save the session ID.
    /// - Parameter sessionID: The new session ID to store.
    func setSessionID(_ sessionID: String) {
        self.sessionID = sessionID
        logger.debug("Stored session ID: \(sessionID)")
    }
    
    /// Retrieve the stored session ID.
    func getSessionID() -> String? {
        return sessionID
    }
    
    /// Clear the saved session.
    func clearSession() {
        self.sessionID = nil
        self.reconnectEndpoint = nil
        self.reconnectAttempts = 0
        logger.debug("Cleared session.")
    }

    
    /// Attempt a reconnection using the stored endpoint.
    /// - Parameter socketManager: The WebSocketManager to use for reconnecting.
    func attemptReconnect(socketManager: WebSocketManager) async throws {
        // Check if we've reached the maximum number of reconnect attempts.
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.error("Maximum reconnect attempts reached (\(maxReconnectAttempts)). Terminating connection.")
            await socketManager.terminate()
            return
        }
        
        // Determine which endpoint to use: reconnectEndpoint has priority.
        guard let targetEndpoint = reconnectEndpoint ?? endpoint else {
            logger.error("No stored endpoint to reconnect with.")
            return
        }
        
        reconnectAttempts += 1
        logger.info("Attempting reconnect \(reconnectAttempts) of \(maxReconnectAttempts) to \(targetEndpoint)")
        
        // Attempt the connection using the decided endpoint.
        try await socketManager.connect(to: targetEndpoint)
    }
}

extension ReconnectManager {
    enum EndpointType {
        case main
        case reconnect
    }
}
