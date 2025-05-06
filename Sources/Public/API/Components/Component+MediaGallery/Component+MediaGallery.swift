//
//  Component+MediaGallery.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

extension Component {
    public struct MediaGallery: DiscordModel {
        public let id: Int?
        public let items: [Item]
    }
}
