//
//  Application+IntegrationType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

// MARK: - IntegrationType

extension Application {
    /// Where an app can be installed.
    @PrettyDescription
    public enum IntegrationType: Int, DiscordModel, CustomStringConvertible {
        /// App is installable to servers.
        case guildInstall = 0
        /// App is installable to users.
        case userInstall = 1
    }
}
