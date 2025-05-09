//
//  Component+Thumbnail.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isSpoiler": "spoiler",
        "thumbnailDescription": "description"
    ]))
    @PrettyDescription
    public struct Thumbnail: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let media: UnfurledMediaItem
        public let thumbnailDescription: String?
        public let isSpoiler: Bool?
    }
}
