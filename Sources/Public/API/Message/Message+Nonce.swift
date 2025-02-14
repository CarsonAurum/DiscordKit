//
//  Message+Nonce.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message {
    public enum Nonce: DiscordModel {
        case int(Int)
        case string(String)
    }
}
