//
//  CallbackData+Autocomplete.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import AnyCodable

extension Interaction.Response.CallbackData {
    public struct Autocomplete: DiscordModel {
        public let choices: [ApplicationCommand.Option<AnyCodable>.Choice]
    }
}
