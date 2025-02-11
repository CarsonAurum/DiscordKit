//
//  Message+InteractionMetadata.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Message {
    public enum InteractionMetadata: DiscordModel {
        case applicationCommand(ApplicationCommand)
        case messageComponent(MessageComponent)
        case modalSubmit(ModalSubmit)
    }
}
