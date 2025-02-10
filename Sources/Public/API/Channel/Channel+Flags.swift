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

extension Channel.Flags: CustomStringConvertible {
    public var description: String {
        var cases = [String]()
        if contains(.pinned) { cases.append("Pinned") }
        if contains(.requireTag) { cases.append("Require Tag") }
        if contains(.hideMediaDownloadOptions) { cases.append("Hide Media Download Options") }
        return "[\(cases.joined(separator: ", "))]"
    }
}
