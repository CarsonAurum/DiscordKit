//
//  Component+ActionRow.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component {
    
    @PrettyDescription
    public struct ActionRow: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let components: [Component]
    }
}
