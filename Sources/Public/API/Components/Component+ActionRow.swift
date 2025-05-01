//
//  Component+ActionRow.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component {
    public struct ActionRow: DiscordModel {
        public let id: Int?
        public let components: [Component]
    }
}
