//
//  Channel+ThreadMetadata.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import Foundation

extension Channel {
    public struct ThreadMetadata: DiscordModel {
        public let isArchived: Bool
        public let autoArchiveDuration: Int
        public let archiveTimestamp: Date
        public let isLocked: Bool
        public let isInvitable: Bool?
        public let createTimestamp: Date?
    }
}

extension Channel.ThreadMetadata {
    enum CodingKeys: String, CodingKey {
        case isArchived = "archived"
        case autoArchiveDuration = "auto_archive_duration"
        case archiveTimestamp = "archive_timestamp"
        case isLocked = "locked"
        case isInvitable = "invitable"
        case createTimestamp = "created_at"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isArchived = try container.decode(Bool.self, forKey: .isArchived)
        self.autoArchiveDuration = try container.decode(Int.self, forKey: .autoArchiveDuration)
        
        let archiveTimestampString = try container.decode(String.self, forKey: .archiveTimestamp)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.archiveTimestamp = fmt.date(from: archiveTimestampString)!
        
        self.isLocked = try container.decode(Bool.self, forKey: .isLocked)
        self.isInvitable = try container.decodeIfPresent(Bool.self, forKey: .isInvitable)
        
        if let createTimestampString = try container.decodeIfPresent(String.self, forKey: .createTimestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.createTimestamp = fmt.date(from: createTimestampString)
        } else {
            self.createTimestamp = nil
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(autoArchiveDuration, forKey: .autoArchiveDuration)
        
        let archiveTimestampString = ISO8601DateFormatter().string(from: archiveTimestamp)
        try container.encode(archiveTimestampString, forKey: .archiveTimestamp)
        
        try container.encode(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(isInvitable, forKey: .isInvitable)
        if let createTimestamp = createTimestamp {
            let dateString = ISO8601DateFormatter().string(from: createTimestamp)
            try container.encode(dateString, forKey: .createTimestamp)
        } else {
            try container.encodeNil(forKey: .createTimestamp)
        }
    }
}
