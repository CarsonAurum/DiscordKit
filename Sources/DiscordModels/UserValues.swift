// File: Sources/DiscordModels/UserValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Documented User flag bits; the wrapper retains unknown unsigned bits without establishing permissions.
public struct UserFlags: OptionSet, Sendable, Hashable {
    /// Exact received bitfield, including future bits.
    public let rawValue: UInt64

    /// Stores a user flag bitfield without clearing future bits or inferring scope visibility.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero.
    /// Construction is synchronous and has no I/O, mutation or ownership side effects.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Discord employee.
    public static let staff = Self(rawValue: 1 << 0)
    /// Partnered server owner.
    public static let partner = Self(rawValue: 1 << 1)
    /// HypeSquad events member.
    public static let hypeSquad = Self(rawValue: 1 << 2)
    /// Bug Hunter level 1.
    public static let bugHunterLevel1 = Self(rawValue: 1 << 3)
    /// HypeSquad House Bravery.
    public static let houseBravery = Self(rawValue: 1 << 6)
    /// HypeSquad House Brilliance.
    public static let houseBrilliance = Self(rawValue: 1 << 7)
    /// HypeSquad House Balance.
    public static let houseBalance = Self(rawValue: 1 << 8)
    /// Early Nitro supporter.
    public static let earlySupporter = Self(rawValue: 1 << 9)
    /// User represents a team.
    public static let teamPseudoUser = Self(rawValue: 1 << 10)
    /// Bug Hunter level 2.
    public static let bugHunterLevel2 = Self(rawValue: 1 << 14)
    /// Verified bot.
    public static let verifiedBot = Self(rawValue: 1 << 16)
    /// Early verified bot developer.
    public static let verifiedDeveloper = Self(rawValue: 1 << 17)
    /// Moderator Programs Alumni.
    public static let certifiedModerator = Self(rawValue: 1 << 18)
    /// Bot uses HTTP interactions and appears online.
    public static let botHTTPInteractions = Self(rawValue: 1 << 19)
}

/// Known API v10 nameplate backgrounds; RawValue retains future response spellings.
public enum UserNameplatePalette: String, Sendable, CaseIterable {
    /// Crimson palette.
    case crimson = "crimson"
    /// Berry palette.
    case berry = "berry"
    /// Sky palette.
    case sky = "sky"
    /// Teal palette.
    case teal = "teal"
    /// Forest palette.
    case forest = "forest"
    /// Bubble gum palette.
    case bubbleGum = "bubble_gum"
    /// Violet palette.
    case violet = "violet"
    /// Cobalt palette.
    case cobalt = "cobalt"
    /// Clover palette.
    case clover = "clover"
    /// Lemon palette.
    case lemon = "lemon"
    /// White palette.
    case white = "white"
}

/// Known connection visibility values; raw response integers remain forward compatible.
public enum UserConnectionVisibility: Int, Sendable, CaseIterable {
    /// Visible only to the user.
    case none = 0
    /// Visible to everyone.
    case everyone = 1
}

/// Current API v10 connection services; deprecated Battle.net/Riot values remain readable through RawValue.
public enum UserConnectionService: String, Sendable, CaseIterable {
    /// Amazon Music.
    case amazonMusic = "amazon-music"
    /// Bungie.net.
    case bungie = "bungie"
    /// Bluesky.
    case bluesky = "bluesky"
    /// Crunchyroll.
    case crunchyroll = "crunchyroll"
    /// Domain.
    case domain = "domain"
    /// eBay.
    case ebay = "ebay"
    /// Epic Games.
    case epicGames = "epicgames"
    /// Facebook.
    case facebook = "facebook"
    /// GitHub.
    case github = "github"
    /// Legacy Instagram connection; users can no longer add it.
    case instagram = "instagram"
    /// Mastodon.
    case mastodon = "mastodon"
    /// PayPal.
    case paypal = "paypal"
    /// PlayStation Network.
    case playstation = "playstation"
    /// Reddit.
    case reddit = "reddit"
    /// Roblox.
    case roblox = "roblox"
    /// Spotify.
    case spotify = "spotify"
    /// Legacy Skype connection; users can no longer add it.
    case skype = "skype"
    /// Steam.
    case steam = "steam"
    /// TikTok.
    case tiktok = "tiktok"
    /// Twitch.
    case twitch = "twitch"
    /// X (Twitter).
    case twitter = "twitter"
    /// Xbox.
    case xbox = "xbox"
    /// YouTube.
    case youtube = "youtube"
}
