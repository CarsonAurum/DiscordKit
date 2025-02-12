//
//  Embed+Footer.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Embed {
    public struct Footer: DiscordModel {
        public let text: String
        public let iconURL: String?
        public let proxyIconURL: String?
    }
}

extension Message.Embed.Footer {
    enum CodingKeys: String, CodingKey {
        case text
        case iconURL = "icon_url"
        case proxyIconURL = "proxy_icon_url"
    }
}
