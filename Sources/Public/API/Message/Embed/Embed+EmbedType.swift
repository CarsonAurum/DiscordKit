//
//  Embed+EmbedType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Embed {
    public enum EmbedType: String, DiscordModel {
        case rich
        case image
        case video
        case gif = "gifv"
        case article
        case link
        case pollResult = "poll_result"
    }
}
