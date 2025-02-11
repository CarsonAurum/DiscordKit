//
//  Response+CallbackData.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.Response {
    public enum CallbackData: DiscordModel {
        case message(Messages)
        case autocomplete(Autocomplete)
        case modal(Modal)
    }
}
