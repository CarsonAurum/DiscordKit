//
//  Component+Section.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

import NovaMacros

extension Component {
    
    @PrettyDescription
    public struct Section: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let components: [Component]
        public let accessory: Component
    }
}
