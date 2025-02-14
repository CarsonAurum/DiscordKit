//
//  DiscordURL.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

/// A centralized location for URL strings.
enum DiscordURL {
    
    /// The core Discord URL
    internal static let BASE_URL = "https://discord.com/api/v10/"
    
    /// The `/gateway/` endpoint.
    internal static let GATEWAY = BASE_URL + "gateway"
    
    /// The `/gateway/bot/` endpoint.
    internal static let GATEWAY_BOT = BASE_URL + "gateway/bot"
    
    internal static func GLOBAL_APPLICATION_COMMANDS(appID: Snowflake) -> String {
        BASE_URL + "applications/\(appID.value)/commands"
    }
}
