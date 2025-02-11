//
//  Interaction+Data.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction {
    public enum Data: DiscordModel {
        case applicationCommand(Interaction.Data.ApplicationCommand)
        case messageComponent(Interaction.Data.MessageComponent)
        case modalSubmit(Interaction.Data.ModalSubmit)
    }
}
