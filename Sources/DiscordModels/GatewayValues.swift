// File: Sources/DiscordModels/GatewayValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Documented received activity kinds. RawValue retains future integral variants.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events#activity-object-activity-types.
public enum GatewayReceivedActivityType: Int, Sendable, CaseIterable {
    /// Playing the named game.
    case playing = 0
    /// Streaming with the documented provider URL rules.
    case streaming = 1
    /// Listening to the named content.
    case listening = 2
    /// Watching the named content.
    case watching = 3
    /// A custom status, potentially suppressed by profile privacy.
    case custom = 4
    /// Competing in an activity.
    case competing = 5
}

/// Which activity field supplies member-list status text; unknown values remain representable in RawValue.
public enum GatewayActivityStatusDisplayType: Int, Sendable, CaseIterable {
    /// Display the activity name.
    case name = 0
    /// Display the activity state.
    case state = 1
    /// Display the activity details.
    case details = 2
}

/// Documented normal and super-reaction kinds; independent of the burst Boolean retained on notifications.
public enum GatewayReactionType: Int, Sendable, CaseIterable {
    /// A normal reaction.
    case normal = 0
    /// A super-reaction.
    case burst = 1
}

/// Documented voice-effect animation kinds; RawValue retains future integral variants.
public enum GatewayVoiceEffectAnimationType: Int, Sendable, CaseIterable {
    /// A Nitro subscriber animation.
    case premium = 0
    /// A standard animation.
    case basic = 1
}
