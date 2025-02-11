//
//  Response+CallbackType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.Response {
    public enum CallbackType: Int, DiscordModel {
        case pong = 1
        case channelMessageWithSource = 4
        case deferredChannelMessageWithSource = 5
        case deferredUpdateMessage = 6
        case updateMessage = 7
        case applicationCommandAutocompleteResult = 8
        case modal = 9
        case launchActivity = 12
    }
}
