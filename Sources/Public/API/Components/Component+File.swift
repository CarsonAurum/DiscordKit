//
//  Component+File.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isSpoiler": "spoiler"
    ]))
    @PrettyDescription
    public struct File: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let file: UnfurledMediaItem
        public let isSpoiler: Bool
    }
}
