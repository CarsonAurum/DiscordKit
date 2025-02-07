//
//  Channel+ForumLayoutType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

extension Channel {
    public enum ForumLayoutType: Int, DiscordModel {
        case notSet = 0
        case listView = 1
        case galleryView = 2
    }
}

extension Channel.ForumLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notSet:       return "Not Set"
        case .listView:     return "List View"
        case .galleryView:  return "Gallery View"
        }
    }
}
