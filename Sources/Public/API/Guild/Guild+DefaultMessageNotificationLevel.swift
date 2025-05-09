//
//  Guild+DefaultMessageNotificationLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum DefaultMessageNotificationLevel: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case allMessages = 0
        case onlyMentions = 1
    }
}
