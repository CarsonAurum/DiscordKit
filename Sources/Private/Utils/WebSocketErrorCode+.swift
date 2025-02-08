//
//  WebSocketErrorCode+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/3/25.
//

import NIOWebSocket

extension WebSocketErrorCode {
    var shouldAutoReconnect: Bool {
        switch self {
        case .normalClosure,
             .unknown(4004),
             .unknown(4010),
             .unknown(4011),
             .unknown(4012),
             .unknown(4013),
             .unknown(4014):
            return false
        default:
            return true
        }
    }
}
