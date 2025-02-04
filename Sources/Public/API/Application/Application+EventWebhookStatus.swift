//
//  Application+EventWebhookStatus.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

// MARK: - EventWebhookStatus

extension Application {
    
    /// Status indicating whether event webhooks are enabled or disabled for an application.
    public enum EventWebhookStatus: Int, DiscordModel {
        
        /// Webhook events disabled by developer.
        case disabled = 1
        
        /// Webhook events enabled by developer.
        case enabled = 2
        
        /// Webhook events disabled by discord -- usually due to activity.
        case disabledByDiscord = 3
    }
}

// MARK: CustomStringConvertible

extension Application.EventWebhookStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .enabled:
            return "Enabled"
        case .disabledByDiscord:
            return "Disabled by Discord"
        }
    }
}
