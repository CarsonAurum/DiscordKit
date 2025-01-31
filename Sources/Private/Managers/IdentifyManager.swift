//
//  IdentifyManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - IdentifyManager

/// A manager to handle the identify mechanism with Discord's gateway.
actor IdentifyManager {
    
    /// The socket manager to use when sending the identify.
    private weak var socket: WebSocketManager?
    
    /// The payload to send.
    private(set) var payload: IdentifyPayload
    
    /// Construct a new identify manager with any information known at creation time.
    /// - Parameters:
    ///   - socket: The manager to use when sending identify connections.
    ///   - token: The token to use when identifying.
    ///   - intents: The intents to use when identifying.
    ///   - largeThreshold: An optional flag to determine
    ///   - shardInfo: The optional information to use when identifying a specific shard.
    ///   - presence: The optional presence information to send on initial identification.
    init(
        socket: WebSocketManager,
        token: String,
        intents: GatewayIntents = .default,
        largeThreshold: Int? = nil,
        shardInfo: (id: Int, nShards: Int)? = nil,
        presence: Presence? = nil
    ) {
        self.socket = socket
        var shardInfoComputed: [Int]? = nil
        if let shardInfo = shardInfo {
            shardInfoComputed = [shardInfo.id, shardInfo.nShards]
        }
        var largeThresholdComputed: Int? = nil
        if let largeThreshold = largeThreshold {
            if largeThreshold > 250 {
                largeThresholdComputed = 250
            } else if largeThreshold < 50 {
                largeThresholdComputed = 50
            } else {
                largeThresholdComputed = largeThreshold
            }
        }
        payload = .init(
            token: token,
            properties: .init(os: "darwin", browser: "SwiftDiscordAdapter", device: "swift-nio"),
            isCompressed: false,
            largeThreshold: largeThresholdComputed,
            shardInfo: shardInfoComputed,
            presence: presence,
            intents: intents)
    }
    
    /// Update the presence used when identifying.
    /// - Note: This is only available before the identify message has been sent.
    /// - Parameter presence: The new presence to include.
    func setPresence(_ presence: Presence?) {
        self.payload = .init(
            token: payload.token,
            properties: payload.properties,
            isCompressed: payload.isCompressed,
            largeThreshold: payload.largeThreshold,
            shardInfo: payload.shardInfo,
            presence: presence,
            intents: payload.intents)
    }
    
    /// Send the identify message.
    func send() async {
        await self.socket?.send(opcode: .identify, data: payload)
    }
}
