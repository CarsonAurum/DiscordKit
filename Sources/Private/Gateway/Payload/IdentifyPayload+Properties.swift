//
//  IdentifyPayload+Properties.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - Properties

extension IdentifyPayload {
    
    /// Information about the connecting client.
    struct Properties: Codable, Hashable, Sendable {
        
        /// The operating system of the client.
        public let os: String
        
        /// The browser of the client.
        public let browser: String
        
        /// The device of the client.
        public let device: String
    }
}

// MARK: CustomStringConvertible

extension IdentifyPayload.Properties: CustomStringConvertible {
    var description: String {
        "[\(browser)@\(device)-\(os)]"
    }
}
