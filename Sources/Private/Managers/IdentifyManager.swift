//
//  IdentifyManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

actor IdentifyManager {
    private weak var socket: WebSocketManager?
    private(set) var payload: IdentifyPayload
    private var hasIdentified: Bool = false
    
    init(
        socket: WebSocketManager,
        token: String,
        intents: GatewayIntents = .default,
        largeThreshold: Int? = nil,
        shardInfo: (id: Int, nShards: Int)? = nil,
        presence: Presence? = nil
    ) {
        self.socket = socket
        let shardInfoComputed: [Int]? = shardInfo.map { [$0.id, $0.nShards] }
        let adjustedThreshold = largeThreshold.map { max(50, min($0, 250)) }
        
        payload = .init(
            token: token,
            properties: .init(os: "macOS", browser: "DiscordKit", device: "swift-nio"),
            isCompressed: false,
            largeThreshold: adjustedThreshold,
            shardInfo: shardInfoComputed,
            presence: presence,
            intents: intents
        )
    }
    
    /// Send either an identify or resume payload.
    func send() async {
        await self.socket?.send(opcode: .identify, data: payload)
    }
}
