//
//  Interaction+InteractionType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Interaction {
    /// The type of interaction.
    public enum InteractionType: Int, DiscordModel {
        /// Ping interactions.
        case ping = 1
        /// Application commands (of any type).
        case applicationCommand = 2
        /// Message component interactions.
        case messageComponent = 3
        /// Autocomplete interactions.
        case applicationCommandAutocomplete = 4
        /// Modal submit interactions.
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
