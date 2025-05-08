//
//  Channel+ForumLayoutType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import NovaMacros

extension Channel {
    
    @PrettyDescription
    public enum ForumLayoutType: Int, DiscordModel, CustomStringConvertible {
        case notSet = 0
        case listView = 1
        case galleryView = 2
    }
}
