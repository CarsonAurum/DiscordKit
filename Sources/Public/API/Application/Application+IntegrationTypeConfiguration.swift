//
//  Application+IntegrationTypeConfiguration.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - IntegrationTypeConfiguration

extension Application {
    
    /// Configuration for a specific installation context.
    public struct IntegrationTypeConfiguration: DiscordModel {
        
        /// Install params for the specific in-app authorization context.
        public let installParams: InstallParams?
    }
}

// MARK: Codable

extension Application.IntegrationTypeConfiguration {
    enum CodingKeys: String, CodingKey {
        case installParams = "oauth2_install_params"
    }
}

// MARK: CustomStringConvertible

extension Application.IntegrationTypeConfiguration: CustomStringConvertible {
    public var description: String {
        if let installParams = installParams {
            return "\(installParams)"
        } else {
            return "None"
        }
    }
}
