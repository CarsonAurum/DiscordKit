//
//  Channel+SortOrderType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension Channel {
    
    @PrettyDescription
    public enum SortOrderType: Int, DiscordModel, CustomStringConvertible {
        case latestActivity = 0
        case creationDate = 1
    }
}
