//
//  Channel+SortOrderType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Channel {
    public enum SortOrderType: Int, DiscordModel {
        case latestActivity = 0
        case creationDate = 1
    }
}
