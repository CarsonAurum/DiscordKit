//
//  Component+Thumbnail.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

extension Component {
    public struct Thumbnail: DiscordModel {
        public let id: Int?
        public let media: UnfurledMediaItem
        public let description: String?
        public let isSpoiler: Bool?
    }
}

extension Component.Thumbnail {
    enum CodingKeys: String, CodingKey {
        case id
        case media
        case description
        case isSpoiler = "spoiler"
    }
}
