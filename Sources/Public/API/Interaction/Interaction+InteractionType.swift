//
//  Interaction+InteractionType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Interaction {
    public enum InteractionType: Int, DiscordModel {
        case ping = 1
        case applicationCommand = 2
        case messageComponent = 3
        case applicationCommandAutocomplete = 4
        case modalSubmit = 5
    }
}

extension Interaction.InteractionType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ping:                             return "Ping"
        case .applicationCommand:               return "Application Command"
        case .messageComponent:                 return "Message Component"
        case .applicationCommandAutocomplete:   return "Application Command Autocomplete"
        case .modalSubmit:                      return "Modal Submit"
        }
    }
}
