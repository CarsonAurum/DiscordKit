//
//  Team.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/1/25.
//

public struct Team: DiscordModel {
    public let icon: String?
    public let id: Snowflake
    public let members: [Member]
    public let name: String
    public let ownerUserID: Snowflake
}

extension Team {
    public struct Member: DiscordModel {
        public let membershipState: State
        public let teamID: Snowflake
        public let user: User
        public let role: Role
    }
}

extension Team.Member {
    public enum State: Int, DiscordModel {
        case invited = 1
        case accepted = 2
    }
}

extension Team.Member {
    public enum Role: String, DiscordModel {
        case owner = ""
        case admin
        case developer
        case readOnly = "read_only"
    }
}
