//
//  Guild+ExplicitContentFilter.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

extension Guild {
    public enum ExplicitContentFilter: Int, DiscordModel {
        case disabled = 0
        case membersWithoutRoles = 1
        case allMembers = 2
    }
}

extension Guild.ExplicitContentFilter: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disabled:                 return "Disabled"
        case .membersWithoutRoles:      return "Members Without roles"
        case .allMembers:               return "All Members"
        }
    }
}
