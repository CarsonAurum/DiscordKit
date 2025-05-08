//
//  ReadyPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import NovaMacros

// MARK: - ReadyPayload

/// The payload included with a ready dispatch event
@CodingKeys(.custom([
    "version": "v",
    "resumeURL": "resume_gateway_url"
]))
@PrettyDescription
struct ReadyPayload: Codable, Hashable, Sendable, CustomStringConvertible {
    
    /// The version of the API being used
    let version: Int
    
    /// The URL to use when resuming
    let resumeURL: String
    
    /// The ID needed for resuming
    let sessionId: String
    
    /// The list of unavailable guilds that this user is a part of
    let guilds: [Guild]
    
    /// This bot's user
    let user: User
    
    /// This application
    let application: Application
}
