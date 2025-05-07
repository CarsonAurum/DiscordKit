//
//  Component+File.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

extension Component {
    public struct File: DiscordModel {
        public let id: Int?
        public let file: UnfurledMediaItem
        public let isSpoiler: Bool
    }
}

extension Component.File {
    enum CodingKeys: String, CodingKey {
        case id
        case file
        case isSpoiler = "spoiler"
    }
}
