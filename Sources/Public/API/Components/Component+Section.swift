//
//  Component+Section.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

extension Component {
    public struct Section: DiscordModel {
        public let id: Int?
        public let components: [Component]
        public let accessory: Component
    }
}
