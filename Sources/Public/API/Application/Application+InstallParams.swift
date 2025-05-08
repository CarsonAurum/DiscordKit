//
//  Application+InstallParams.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

// MARK: - InstallParams

extension Application {
    /// Settings for the app's default in-app authorization link.
    @PrettyDescription
    public struct InstallParams: Codable, Hashable, Sendable, CustomStringConvertible {
        /// Scopes to add the application to the server with.
        public let scopes: [String]
        /// Permissions to request for the bot role.
        public let permissions: String
    }
}
