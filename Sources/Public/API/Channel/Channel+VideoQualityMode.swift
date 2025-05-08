//
//  Channel+VideoQualityMode.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension Channel {
    
    @PrettyDescription
    public enum VideoQualityMode: Int, DiscordModel, CustomStringConvertible {
        case auto = 1
        case full = 2
    }
}
