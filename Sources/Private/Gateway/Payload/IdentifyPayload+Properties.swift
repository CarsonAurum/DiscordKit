//
//  IdentifyPayload+Properties.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import NovaMacros

// MARK: - Properties

extension IdentifyPayload {
    
    /// Information about the connecting client.
    @PrettyDescription
    struct Properties: Codable, Hashable, Sendable, CustomStringConvertible {
        
        /// The operating system of the client.
        public let os: String
        
        /// The browser of the client.
        public let browser: String
        
        /// The device of the client.
        public let device: String
    }
}
