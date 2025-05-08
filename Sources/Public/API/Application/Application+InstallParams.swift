//
//  Application+InstallParams.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - InstallParams

extension Application {
    /// Settings for the app's default in-app authorization link.
    public struct InstallParams: Codable, Hashable, Sendable {
        /// Scopes to add the application to the server with.
        public let scopes: [String]
        /// Permissions to request for the bot role.
        public let permissions: String
    }
}

// MARK: CustomStringConvertible

extension Application.InstallParams: CustomStringConvertible {
    public var description: String {
        "[Scopes: \(scopes.joined(separator: ", ")) || Permission: \(permissions)]"
    }
}
