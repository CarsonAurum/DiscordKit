//
//  Option+Choice.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension ApplicationCommand.Option {
    
    @CodingKeys(.all)
    @PrettyDescription
    public struct Choice: Codable, Hashable, Sendable, CustomStringConvertible {
        public let name: String
        public let nameLocalizations: [Locale: String]?
        public let value: T
    }
}
