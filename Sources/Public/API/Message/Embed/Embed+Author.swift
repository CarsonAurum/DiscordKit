//
//  Embed+Author.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Embed {
    public struct Author: DiscordModel {
        public let name: String
        public let url: String?
        public let iconURL: String?
        public let proxyIconURL: String?
    }
}

extension Message.Embed.Author {
    enum CodingKeys: String, CodingKey {
        case name
        case url
        case iconURL = "icon_url"
        case proxyIconURL = "proxy_icon_url"
    }
}
