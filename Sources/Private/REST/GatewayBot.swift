//
//  GatewayBot.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import AsyncHTTPClient
import Logging
import NIOHTTP1
import Foundation

// MARK: - GatewayBot

/// An actor for the `/gateway/bot` endpoint.
actor GatewayBot {
    
    /// The client on which the request should be executed.
    let client: HTTPClient
    
    /// The headers to include with the request.
    let headers: HTTPHeaders
    
    /// Create a new endpoint manager.
    /// - Parameters:
    ///   - client: The client on which requests should be executed.
    ///   - headers: The headers to include with requests.
    ///   - decoder: The decoder to use when parsing the response.
    init(client: HTTPClient, headers: HTTPHeaders, decoder: JSONDecoder) throws {
        self.client = client
        self.headers = headers
        self.decoder = decoder
    }
    
    /// Run the request and receive a response.
    /// - Returns: The response payload, if it exists.
    func get() async throws -> Payload? {
        let request = try HTTPClient.Request(url: DiscordURL.GATEWAY_BOT, method: .GET, headers: self.headers)
        let response = try await client.execute(request: request).get()
        if response.status == .ok {
            if let body = response.body {
                let gatewayResponse = try decoder.decode(Payload.self, from: Data(buffer: body))
                logger.trace("Response: \(gatewayResponse)")
                return gatewayResponse
            } else {
                logger.error("No response body.")
            }
        } else if response.status == .unauthorized {
            logger.error("Unauthorized bot token.")
        } else {
            logger.error("Received Response: \(response.status)")
        }
        return nil
    }
    
    // MARK: Private
    
    /// The logger to use for this requester.
    private let logger = Logger(label: "/gateway/bot/")
    
    /// The decoder to use within this requester.
    private let decoder: JSONDecoder
}

// MARK: - Payload

extension GatewayBot {
    
    /// The data sent from the `/gateway/bot` endpoint.
    struct Payload: DiscordModel {
        
        /// WSS URL that can be used for connecting to the gateway.
        let url: String
        
        /// Recommended number of shards to use when connecting.
        let shards: Int
        
        /// Information on the current session start limit.
        let sessionStartLimit: SessionStartLimit
    }
}

// MARK: Codable
    
extension GatewayBot.Payload {
    enum CodingKeys: String, CodingKey {
        case url
        case shards
        case sessionStartLimit = "session_start_limit"
    }
}

// MARK: CustomStringConvertible

extension GatewayBot.Payload: CustomStringConvertible {
    var description: String {
        "[Connect to \(url) with \(shards) shards. \(sessionStartLimit)]"
    }
}

// MARK: - SessionStartLimit
        
extension GatewayBot.Payload {
    
    /// Information about starting a new session.
    struct SessionStartLimit: DiscordModel {
        
        /// Total number of session starts the current user is allowed.
        let total: Int
        
        /// Remaining number of session starts the current user is allowed.
        let remaining: Int
        
        /// Number of milliseconds after which the limit resets.
        let resetAfter: Int
        
        /// Number of identify requests allowed per 5 seconds.
        let maxConcurrency: Int
    }
}

// MARK: Codable

extension GatewayBot.Payload.SessionStartLimit {
    enum CodingKeys: String, CodingKey {
        case total
        case remaining
        case resetAfter = "reset_after"
        case maxConcurrency = "max_concurrency"
    }
}

// MARK: CustomStringConvertible

extension GatewayBot.Payload.SessionStartLimit: CustomStringConvertible {
    var description: String {
        "[{\(maxConcurrency)}: \(remaining)/\(total) reconnects; Resets in \((Double(resetAfter) / 1000) / 60) seconds.]"
    }
}
