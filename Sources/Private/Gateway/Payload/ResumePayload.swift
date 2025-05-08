//
//  ResumePayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/2/25.
//

import NovaMacros

/// The payload to send on resuming a previous session.
@CodingKeys(.custom(["sequence": "seq"]))
@PrettyDescription
struct ResumePayload: Codable, Hashable, Sendable, CustomStringConvertible {
    
    /// The token associated with the session.
    let token: String
    
    /// The ID of the session to be resumed.
    let sessionId: String
    
    /// The last received sequence number.
    let sequence: Int?
}
