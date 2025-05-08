//
//  Application+IntegrationTypeConfiguration.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

// MARK: - IntegrationTypeConfiguration

extension Application {
    /// Configuration for a specific installation context.
    @CodingKeys(.custom([
        "installParams": "oauth2_install_params"
    ]))
    @PrettyDescription
    public struct IntegrationTypeConfiguration: Codable, Hashable, Sendable, CustomStringConvertible {
        /// Install params for the specific in-app authorization context.
        public let installParams: InstallParams?
    }
}
