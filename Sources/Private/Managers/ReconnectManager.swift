//
//  ReconnectManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/2/25.
//

actor ReconnectManager {
    
    private weak var socket: WebSocketManager?
    private var sequenceTask: Task<Void, Never>?
    private let token: String
    private var reconnectURL: String?
    private var sessionID: String?
    private var sequence: Int?
    
    init(_ socket: WebSocketManager, token: String) {
        self.socket = socket
        self.token = token
    }
    
    func startSequenceTask(_ stream: AsyncStream<Int>) {
        sequenceTask = Task {
            for await newSequence in stream {
                self.sequence = newSequence
            }
        }
    }
    func setReconnectInfo(url reconnectURL: String, id sessionID: String) {
        self.reconnectURL = reconnectURL
        self.sessionID = sessionID
    }
    func reconnect() async throws {
        
    }
}
