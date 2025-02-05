//
//  Guild+Feature.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild {
    public enum Feature: DiscordModel {
        case animatedBanner
        case animatedIcon
        case applicationCommandPermissionsV2
        case autoModeration
        case banner
        case community
        case creatorMonetizableProvisional
        case creatorStorePage
        case developerSupportServer
        case discoverable
        case featurable
        case invitesDisable
        case inviteSplash
        case memberVerificationGateEnabled
        case moreSoundboard
        case moreStickers
        case news
        case partnered
        case previewEnabled
        case raidAlertsDisabled
        case roleIcons
        case roleSubscriptionsAvailableForPurchase
        case roleSubscriptionsEnabled
        case soundboard
        case ticketedEventsURL
        case vanityURL
        case verified
        case vipRegions
        case welcomeScreenEnabled
        case unknown(String)
    }
}

extension Guild.Feature {
    // Decoding: create an instance of Feature from a decoder.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        switch stringValue {
        case "ANIMATED_BANNER":                             self = .animatedBanner
        case "ANIMATED_ICON":                               self = .animatedIcon
        case "APPLICATION_COMMAND_PERMISSIONS_V2":          self = .applicationCommandPermissionsV2
        case "AUTO_MODERATION":                             self = .autoModeration
        case "BANNER":                                      self = .banner
        case "COMMUNITY":                                   self = .community
        case "CREATOR_MONETIZABLE_PROVISIONAL":             self = .creatorMonetizableProvisional
        case "CREATOR_STORE_PAGE":                          self = .creatorStorePage
        case "DEVELOPER_SUPPORT_SERVER":                    self = .developerSupportServer
        case "DISCOVERABLE":                                self = .discoverable
        case "FEATURABLE":                                  self = .featurable
        case "INVITES_DISABLE":                             self = .invitesDisable
        case "INVITE_SPLASH":                               self = .inviteSplash
        case "MEMBER_VERIFICATION_GATE_ENABLED":            self = .memberVerificationGateEnabled
        case "MORE_SOUNDBOARD":                             self = .moreSoundboard
        case "MORE_STICKERS":                               self = .moreStickers
        case "NEWS":                                        self = .news
        case "PARTNERED":                                   self = .partnered
        case "PREVIEW_ENABLED":                             self = .previewEnabled
        case "RAID_ALERTS_DISABLED":                        self = .raidAlertsDisabled
        case "ROLE_ICONS":                                  self = .roleIcons
        case "ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE":   self = .roleSubscriptionsAvailableForPurchase
        case "ROLE_SUBSCRIPTIONS_ENABLED":                  self = .roleSubscriptionsEnabled
        case "SOUNDBOARD":                                  self = .soundboard
        case "TICKETED_EVENTS_URL":                         self = .ticketedEventsURL
        case "VANITY_URL":                                  self = .vanityURL
        case "VERIFIED":                                    self = .verified
        case "VIP_REGIONS":                                 self = .vipRegions
        case "WELCOME_SCREEN_ENABLED":                      self = .welcomeScreenEnabled
        default:                                            self = .unknown(stringValue)
        }
    }
    
    // Encoding: convert an instance of Feature to its corresponding string representation.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let stringValue: String
        
        switch self {
        case .animatedBanner:           stringValue = "ANIMATED_BANNER"
        case .animatedIcon:             stringValue = "ANIMATED_ICON"
        case .applicationCommandPermissionsV2:
            stringValue = "APPLICATION_COMMAND_PERMISSIONS_V2"
        case .autoModeration:           stringValue = "AUTO_MODERATION"
        case .banner:                   stringValue = "BANNER"
        case .community:                stringValue = "COMMUNITY"
        case .creatorMonetizableProvisional:
            stringValue = "CREATOR_MONETIZABLE_PROVISIONAL"
        case .creatorStorePage:         stringValue = "CREATOR_STORE_PAGE"
        case .developerSupportServer:   stringValue = "DEVELOPER_SUPPORT_SERVER"
        case .discoverable:             stringValue = "DISCOVERABLE"
        case .featurable:               stringValue = "FEATURABLE"
        case .invitesDisable:           stringValue = "INVITES_DISABLE"
        case .inviteSplash:             stringValue = "INVITE_SPLASH"
        case .memberVerificationGateEnabled:
            stringValue = "MEMBER_VERIFICATION_GATE_ENABLED"
        case .moreSoundboard:           stringValue = "MORE_SOUNDBOARD"
        case .moreStickers:             stringValue = "MORE_STICKERS"
        case .news:                     stringValue = "NEWS"
        case .partnered:                stringValue = "PARTNERED"
        case .previewEnabled:           stringValue = "PREVIEW_ENABLED"
        case .raidAlertsDisabled:       stringValue = "RAID_ALERTS_DISABLED"
        case .roleIcons:                stringValue = "ROLE_ICONS"
        case .roleSubscriptionsAvailableForPurchase:
            stringValue = "ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE"
        case .roleSubscriptionsEnabled: stringValue = "ROLE_SUBSCRIPTIONS_ENABLED"
        case .soundboard:               stringValue = "SOUNDBOARD"
        case .ticketedEventsURL:        stringValue = "TICKETED_EVENTS_URL"
        case .vanityURL:                stringValue = "VANITY_URL"
        case .verified:                 stringValue = "VERIFIED"
        case .vipRegions:               stringValue = "VIP_REGIONS"
        case .welcomeScreenEnabled:     stringValue = "WELCOME_SCREEN_ENABLED"
        case .unknown(let val):         stringValue = val
        }
        try container.encode(stringValue)
    }
}
