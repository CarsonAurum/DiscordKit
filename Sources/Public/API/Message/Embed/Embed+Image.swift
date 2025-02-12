//
//  Embed+Image.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Embed {
    public struct Image: DiscordModel {
        public let url: String
        public let proxyURL: String?
        public let height: Int?
        public let width: Int?
    }
}

extension Message.Embed.Image {
    enum CodingKeys: String, CodingKey {
        case url
        case proxyURL = "proxy_url"
        case height
        case width
    }
}
