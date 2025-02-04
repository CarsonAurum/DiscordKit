//
//  Guild+MFALevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

extension Guild {
    public enum MFALevel: Int, DiscordModel {
        case none = 0
        case elevated = 1
    }
}

extension Guild.MFALevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:     return "None"
        case .elevated: return "Elevated"
        }
    }
}
