//
//  Interaction+CallbackResponse.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction {
    public struct CallbackResponse: DiscordModel {
        public let interaction: Callback
        public let resource: Resource?
    }
}
