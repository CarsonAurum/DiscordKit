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
    public let status: [Presence.Status]
    public let isAFK: Bool
}

extension Presence {
    enum CodingKeys: String, CodingKey {
        case idleSince = "since"
        case activities
        case status
        case isAFK = "afk"
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

