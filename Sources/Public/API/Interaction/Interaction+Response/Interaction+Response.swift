//
//  Interaction+Response.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/10/25.
//

extension Interaction {
    public struct Response: DiscordModel {
        public let type: CallbackType
        public let data: CallbackData
    }
}
