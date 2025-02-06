//
//  ApplicationCommand+Option.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension ApplicationCommand {
    public struct Option<T>: DiscordModel where T: Codable, T: Hashable, T: Sendable {
        
    }
}
