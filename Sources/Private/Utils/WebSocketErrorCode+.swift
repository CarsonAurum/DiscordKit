//
//  WebSocketErrorCode+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/3/25.
//

import NIOWebSocket

extension WebSocketErrorCode {
    public var shouldReconnect: Bool {
        switch self {
        case .normalClosure:
            return false
        default:
            return true
        }
    }
}
