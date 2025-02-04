//
//  Application+InstallParams.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - InstallParams

extension Application {
    public struct InstallParams: DiscordModel {
        public let scopes: [String]
        public let permissions: String
    }
}

// MARK: CustomStringConvertible

extension Application.InstallParams: CustomStringConvertible {
    public var description: String {
        "[Scopes: \(scopes.joined(separator: ", ")) || Permission: \(permissions)]"
    }
}
