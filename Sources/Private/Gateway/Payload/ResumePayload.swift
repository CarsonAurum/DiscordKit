//
//  ResumePayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/2/25.
//

/// The payload to send on resuming a previous session.
struct ResumePayload: DiscordModel {
    
    /// The token associated with the session.
    let token: String
    
    /// The ID of the session to be resumed.
    let sessionID: String
    
    /// The last received sequence number.
    let sequence: Int?
}

extension ResumePayload {
    enum CodingKeys: String, CodingKey {
        case token
        case sessionID = "session_id"
        case sequence = "seq"
    }
}

extension ResumePayload: CustomStringConvertible {
    public var description: String {
        var result = "[Token: \(token) || Session ID: \(sessionID) || Sequence: "
        if let sequence = sequence {
            result += "\(sequence)"
        } else {
            result += "<nil>"
        }
        result += "]"
        return result
    }
}
