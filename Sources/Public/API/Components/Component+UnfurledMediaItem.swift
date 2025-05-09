//
//  Component+UnfurledMediaItem.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.all)
    @PrettyDescription
    public struct UnfurledMediaItem: Codable, Hashable, Sendable, CustomStringConvertible {
        public let url: String
        public let proxyUrl: String?
        public let height: Int?
        public let width: Int?
        public let contentType: String?
    }
}
