//
//  Channel+Flags.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Channel {
    public struct Flags: OptionSet, DiscordModel {
        
        public static let pinned = Flags(rawValue: 1 << 1)
        public static let requireTag = Flags(rawValue: 1 << 4)
        public static let hideMediaDownloadOptions = Flags(rawValue: 1 << 15)
        
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
}
