//
//  Component+StringSelect.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isDisabled": "disabled"
    ]))
    @PrettyDescription
    public struct StringSelect: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let customId: String
        public let options: [Option]
        public let placeholder: String?
        public let minValues: Int?
        public let maxValues: Int?
        public let isDisabled: Bool?
    }
}
