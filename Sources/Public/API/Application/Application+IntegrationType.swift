//
//  Application+IntegrationType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - IntegrationType

extension Application {
    
    /// Where an app can be installed.
    public enum IntegrationType: Int, DiscordModel {
        
        /// App is installable to servers.
        case guildInstall = 0
        
        /// App is installable to users.
        case userInstall = 1
    }
}

// MARK: CustomStringConvertible

extension Application.IntegrationType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .guildInstall:
            return "Guild Install"
        case .userInstall:
            return "User Install"
        }
    }
}
