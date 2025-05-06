//
//  Component+UnfurledMediaItem.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

extension Component {
    public struct UnfurledMediaItem: DiscordModel {
        public let url: String
        public let proxyURL: String?
        public let height: Int?
        public let width: Int?
        public let contentType: String?
    }
}

extension Component.UnfurledMediaItem {
    enum CodingKeys: String, CodingKey {
        case url
        case proxyURL = "proxy_url"
        case height
        case width
        case contentType = "content_type"
    }
}
