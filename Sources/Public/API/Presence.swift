//
//  Presence.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import Foundation

// MARK: - Presence

public struct Presence: DiscordModel {
    public let idleSince: Date?
    public let activities: [Activity]
    public let status: Status
    public let isAFK: Bool
}

extension Presence {
    enum CodingKeys: String, CodingKey {
        case idleSince = "since"
        case activities
        case status
        case isAFK = "afk"
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let timestampMillis = try container.decodeIfPresent(Int64.self, forKey: .idleSince) {
            self.idleSince = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        } else {
            self.idleSince = nil
        }
        self.activities = try container.decode([Activity].self, forKey: .activities)
        self.status = try container.decode(Status.self, forKey: .status)
        self.isAFK = try container.decode(Bool.self, forKey: .isAFK)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let date = idleSince {
            let timestampMillis = Int64(date.timeIntervalSince1970 * 1000)
            try container.encode(timestampMillis, forKey: .idleSince)
        } else {
            try container.encodeNil(forKey: .idleSince)
        }
        try container.encode(activities, forKey: .activities)
        try container.encode(status, forKey: .status)
        try container.encode(isAFK, forKey: .isAFK)
    }
}


extension Presence {
    public enum Status: String, DiscordModel {
        case online
        case doNotDisturb = "dnd"
        case idle
        case invisible
        case offline
    }
}

