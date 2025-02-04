//
//  User.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

public struct User: DiscordModel {
    public let id: Snowflake
    public let username: String
    public let discriminator: String
    public let globalName: String?
    public let avatar: String?
    public let isBot: Bool?
    public let isSystem: Bool?
    public let isMFAEnabled: Bool?
    public let banner: String?
    public let accentColor: Int?
    public let locale: Locale?
    public let isVerified: Bool?
    public let email: String?
    public let flags: Flags?
    public let nitroType: NitroType?
    public let publicFlags: Flags?
    public let avatarDecorationData: AvatarDecorationData?
}

extension User {
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case discriminator
        case globalName = "global_name"
        case avatar
        case isBot = "bot"
        case isSystem = "system"
        case isMFAEnabled = "mfa_enabled"
        case banner
        case accentColor = "accent_color"
        case locale
        case isVerified = "verified"
        case email
        case flags
        case nitroType = "premium_type"
        case publicFlags = "public_flags"
        case avatarDecorationData = "avatar_decoration_data"
    }
}

extension User {
    public struct Flags: OptionSet, DiscordModel {
        public static let staff = Flags(rawValue: 1 << 0)
        public static let partner = Flags(rawValue: 1 << 1)
        public static let hypesquad = Flags(rawValue: 1 << 2)
        public static let bugHunter1 = Flags(rawValue: 1 << 3)
        public static let hypesquadBravery = Flags(rawValue: 1 << 6)
        public static let hypesquadBrilliance = Flags(rawValue: 1 << 7)
        public static let hypesquadBalance = Flags(rawValue: 1 << 8)
        public static let nitroEarlySupporter = Flags(rawValue: 1 << 9)
        public static let teamPseudoUser = Flags(rawValue: 1 << 10)
        public static let bugHunter2 = Flags(rawValue: 1 << 14)
        public static let verifiedBot = Flags(rawValue: 1 << 16)
        public static let verifiedDeveloper = Flags(rawValue: 1 << 17)
        public static let certifiedModerator = Flags(rawValue: 1 << 18)
        public static let botHTTPInteractions = Flags(rawValue: 1 << 19)
        public static let activeDeveloper = Flags(rawValue: 1 << 22)
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension User.Flags: CustomStringConvertible {
    public var description: String {
        var cases = [String]()
        if contains(.staff) { cases.append("Staff") }
        if contains(.partner) { cases.append("Partner") }
        if contains(.hypesquad) { cases.append("Hypesquad") }
        if contains(.bugHunter1) { cases.append("Hug Hunter 1") }
        if contains(.hypesquadBravery) { cases.append("Hypesquad Bravery") }
        if contains(.hypesquadBrilliance) { cases.append("Hypesquad Brilliance") }
        if contains(.hypesquadBalance) { cases.append("Hypesquad Balance") }
        if contains(.nitroEarlySupporter) { cases.append("Nitro Early Supporter") }
        if contains(.teamPseudoUser) { cases.append("Team User") }
        if contains(.bugHunter2) { cases.append("Bug Hunter 2") }
        if contains(.verifiedBot) { cases.append("Verified Bot") }
        if contains(.verifiedDeveloper) { cases.append("Verified Developer") }
        if contains(.certifiedModerator) { cases.append("Certified Moderator") }
        if contains(.botHTTPInteractions) { cases.append("Bot HTTP Interactions") }
        if contains(.activeDeveloper) { cases.append("Active Developer") }
        return "[\(cases.joined(separator: ", "))]"
    }
}


extension User {
    public enum NitroType: Int, DiscordModel {
        case none = 0
        case nitroClassic = 1
        case nitro = 2
        case nitroBasic = 3
    }
}

extension User.NitroType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:             return "None"
        case .nitroClassic:     return "Nitro Classic"
        case .nitro:            return "Nitro"
        case .nitroBasic:       return "Nitro Basic"
        }
    }
}

extension User {
    public struct AvatarDecorationData: DiscordModel {
        public let asset: String
        public let skuID: Snowflake
    }
}

extension User.AvatarDecorationData {
    enum CodingKeys: String, CodingKey {
        case asset
        case skuID = "sku_id"
    }
}

extension User.AvatarDecorationData: CustomStringConvertible {
    public var description: String {
        "[Asset: \(asset) || SKU: \(skuID)]"
    }
}
