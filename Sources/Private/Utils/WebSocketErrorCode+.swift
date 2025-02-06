//
//  WebSocketErrorCode+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/3/25.
//

import NIOWebSocket

extension WebSocketErrorCode {
    public var shouldAutoReconnect: Bool {
        switch self {
        case .normalClosure, .policyViolation:
            return false
        default:
            return true
        }
    }
}
