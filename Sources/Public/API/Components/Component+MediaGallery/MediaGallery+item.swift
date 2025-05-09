//
//  MediaGallery+item.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component.MediaGallery {
    
    @CodingKeys(.custom([
        "itemDescription": "description",
        "isSpoiler": "spoiler"
    ]))
    @PrettyDescription
    public struct Item: Codable, Hashable, Sendable, CustomStringConvertible {
        public let media: Component.UnfurledMediaItem
        public let itemDescription: String?
        public let isSpoiler: Bool?
    }
}
