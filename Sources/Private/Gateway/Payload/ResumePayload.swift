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
