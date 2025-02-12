//
//  Message+Embed.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

import Foundation

extension Message {
    public struct Embed: DiscordModel {
        public let title: String?
        public let type: EmbedType?
        public let embedDescription: String?
        public let url: String?
        public let timestamp: Date?
        public let color: Int?
        public let footer: Footer?
        public let image: Image?
        public let thumbnail: Thumbnail?
        public let video: Video?
        public let provider: Provider?
        public let author: Author?
        public let fields: [Field]?
    }
}

extension Message.Embed {
    enum CodingKeys: String, CodingKey {
        case title
        case type
        case embedDescription = "description"
        case url
        case timestamp
        case color
        case footer
        case image
        case thumbnail
        case video
        case provider
        case author
        case fields
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(EmbedType.self, forKey: .type)
        embedDescription = try container.decodeIfPresent(String.self, forKey: .embedDescription)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        
        if let timestampString = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.timestamp = fmt.date(from: timestampString)
        } else {
            self.timestamp = nil
        }
        
        color = try container.decodeIfPresent(Int.self, forKey: .color)
        footer = try container.decodeIfPresent(Footer.self, forKey: .footer)
        image = try container.decodeIfPresent(Image.self, forKey: .image)
        thumbnail = try container.decodeIfPresent(Thumbnail.self, forKey: .thumbnail)
        video = try container.decodeIfPresent(Video.self, forKey: .video)
        provider = try container.decodeIfPresent(Provider.self, forKey: .provider)
        author = try container.decodeIfPresent(Author.self, forKey: .author)
        fields = try container.decodeIfPresent([Field].self, forKey: .fields)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(embedDescription, forKey: .embedDescription)
        try container.encodeIfPresent(url, forKey: .url)
        
        if let timestamp = timestamp {
            let dateString = ISO8601DateFormatter().string(from: timestamp)
            try container.encode(dateString, forKey: .timestamp)
        } else {
            try container.encodeNil(forKey: .timestamp)
        }
        
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(footer, forKey: .footer)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encodeIfPresent(video, forKey: .video)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(fields, forKey: .fields)
    }
}
