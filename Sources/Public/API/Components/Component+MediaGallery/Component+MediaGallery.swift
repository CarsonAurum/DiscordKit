//
//  Component+MediaGallery.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component {
    
    @PrettyDescription
    public struct MediaGallery: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let items: [Item]
    }
}
