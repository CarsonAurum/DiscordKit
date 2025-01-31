//
//  IdentifyManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

actor IdentifyManager {
    private weak var socket: WebSocketManager?
    private(set) var payload: IdentifyPayload
    private var shouldIdentify: Bool = false
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
    func send() async {
        await self.socket?.send(opcode: .identify, data: payload)
    }
}
