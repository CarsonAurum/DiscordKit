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

extension Interaction.Response {
    public enum CallbackType: Int, DiscordModel {
        case pong = 1
        case channelMessageWithSource = 4
        case deferredChannelMessageWithSource = 5
        case deferredUpdateMessage = 6
        case updateMessage = 7
        case applicationCommandAutocompleb
        case launchActivity = 12
    }
}

extension Interaction.Response {
    public enum CallbackData: DiscordModel {
        case message(Messages)
        case autocomplete(Autocomplete)
        case modal(Modal)
    }
}

extension Interaction.Response.CallbackData {
    public struct Messages: DiscordModel {
        
    }
}

extension Interaction.Response.CallbackData {
    public struct Autocomplete: DiscordModel {
        
    }
}

extension Interaction.Response.CallbackData {
    public struct Modal: DiscordModel {
        
    }
}
