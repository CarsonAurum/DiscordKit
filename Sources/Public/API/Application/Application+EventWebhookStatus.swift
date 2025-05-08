//
//  Application+EventWebhookStatus.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

// MARK: - EventWebhookStatus

extension Application {
    /// Status indicating whether event webhooks are enabled or disabled for an application.
    @PrettyDescription
    public enum EventWebhookStatus: Int, DiscordModel, CustomStringConvertible {
        /// Webhook events disabled by developer.
        case disabled = 1
        /// Webhook events enabled by developer.
        case enabled = 2
        /// Webhook events disabled by discord -- usually due to activity.
        case disabledByDiscord = 3
    }
}
