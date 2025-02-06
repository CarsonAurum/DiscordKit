//
//  Channel+VideoQualityMode.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Channel {
    public enum VideoQualityMode: Int, DiscordModel {
        case auto = 1
        case full = 2
    }
}

extension Channel.VideoQualityMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .auto:    return "Auto"
        case .full:    return "Full"
        }
    }
}
