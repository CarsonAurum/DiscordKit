//
//  ResumePayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/2/25.
//

struct ResumePayload: DiscordModel {
    let token: String
    let sessionID: String
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
