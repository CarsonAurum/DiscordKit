//
//  ReadyPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - ReadyPayload

/// The payload included with a ready dispatch event
struct ReadyPayload: DiscordModel {
    
    /// The version of the API being used
    let version: Int
    
    /// The URL to use when resuming
    let resumeURL: String
    
    /// The ID needed for resuming
    let sessionID: String
    
    /// The list of unavailable guilds that this user is a part of
    let guilds: [Guild]
    
    /// This bot's user
    let user: User
    
    /// This application
    let application: Application
}

// MARK: Codable

extension ReadyPayload {
    enum CodingKeys: String, CodingKey {
        case version = "v"
        case resumeURL = "resume_gateway_url"
        case sessionID = "session_id"
        case guilds
        case user
        case application
    }
}

// MARK: CustomStringConvertible

extension ReadyPayload: CustomStringConvertible {
    var description: String {
        "[v\(version) || Reconnect At: \(resumeURL) with ID: \(sessionID) || \(guilds.count) Guilds || \(user) || " +
        "\(application)]"
    }
}
