// File: Sources/DiscordModels/MonetizationValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Marker separating entitlement identifiers from related premium resources.
public enum EntitlementTag: Sendable {}
/// Exact unsigned 64-bit entitlement identifier, encoded as decimal text.
public typealias EntitlementID = Snowflake<EntitlementTag>
/// Marker separating recurring subscription identifiers from SKU identifiers.
public enum SubscriptionTag: Sendable {}
/// Exact unsigned 64-bit recurring subscription identifier, encoded as decimal text.
public typealias SubscriptionID = Snowflake<SubscriptionTag>

/// Written API v10 premium offering kinds, verified 2026-10-16 against the SKU reference.
/// Response `RawValue` wrappers retain future integral cases without assigning access semantics.
public enum SKUType: Int, Sendable, CaseIterable {
    /// A durable one-time purchase.
    case durable = 2
    /// A one-time purchase consumed after use.
    case consumable = 3
    /// A recurring subscription; use this SKU when testing subscription entitlements.
    case subscription = 5
    /// Discord's automatically created subscription group; currently not used by integrations.
    case subscriptionGroup = 6
}

/// Written API v10 SKU flags. Flags describe an offering and never grant premium access.
/// Unknown bits survive initialization, unions and membership checks without normalization.
public struct SKUFlags: OptionSet, Sendable, Hashable {
    /// Complete unsigned response bitfield, including unknown future bits.
    public let rawValue: UInt64

    /// Retains a complete offering bitfield without checking eligibility, availability or ownership.
    /// - Parameter rawValue: Any unsigned 64-bit value, including zero and unrecognized bit combinations.
    /// Construction is synchronous, performs no I/O, owns no external resources and confers no entitlement.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// The offering is available for purchase at the time of the response.
    public static let available = Self(rawValue: 1 << 2)
    /// A recurring offering purchased by a user and applied to one guild for that guild's members.
    public static let guildSubscription = Self(rawValue: 1 << 7)
    /// A recurring offering purchased for one user across guilds.
    public static let userSubscription = Self(rawValue: 1 << 8)
}

/// Written API v10 entitlement origins, verified 2026-10-16 against the Entitlement reference.
/// Unknown integral values remain representable through response `RawValue` wrappers.
public enum EntitlementType: Int, Sendable, CaseIterable {
    /// Purchased by a user.
    case purchase = 1
    /// Granted for a Discord Nitro subscription.
    case premiumSubscription = 2
    /// Gifted by a developer.
    case developerGift = 3
    /// Purchased by a developer in application test mode.
    case testModePurchase = 4
    /// Granted while the offering was free.
    case freePurchase = 5
    /// Gifted by another user.
    case userGift = 6
    /// Claimed for free by a Nitro subscriber.
    case premiumPurchase = 7
    /// Purchased as an application subscription.
    case applicationSubscription = 8
}

/// Written API v10 recurring-payment states. Never use these states alone to grant perks;
/// Discord directs applications to evaluate entitlements for the requested SKU instead.
/// Status can change within a billing period, and active status can extend beyond its period.
public enum SubscriptionStatus: Int, Sendable, CaseIterable {
    /// Scheduled to renew; a failed payment may still be retrying.
    case active = 0
    /// Not currently being charged; refund/chargeback may cause this within the current period.
    case inactive = 1
    /// Active but canceled and not scheduled to renew.
    case ending = 2
}
