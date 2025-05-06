//
//  MediaGallery+item.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

extension Component.MediaGallery {
    public struct Item: DiscordModel {
        public let media: Component.UnfurledMediaItem
        public let description: String?
        public let isSpoiler: Bool?
    }
}

extension Component.MediaGallery.Item {
    enum CodingKeys: String, CodingKey {
        case media
        case description
        case isSpoiler = "spoiler"
    }
}
