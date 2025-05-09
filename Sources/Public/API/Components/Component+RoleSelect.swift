//
//  Component+RoleSelect.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isDisabled": "disabled"
    ]))
    @PrettyDescription
    public struct RoleSelect: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let customId: String
        public let placeholder: String?
        public let defaultValues: [SelectDefaultValue]?
        public let minValues: Int?
        public let maxValues: Int?
        public let isDisabled: Bool?
    }
}
