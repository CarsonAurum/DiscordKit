//
//  Channel+ChannelType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Channel {
    /// An enumeration of the various channel types supported by Discord.
    public enum ChannelType: Int, DiscordModel {
        /// A text channel within a guild.
        case guildText = 0
        /// A direct message channel between two users.
        case dm = 1
        /// A voice channel within a guild.
        case guildVoice = 2
        /// A group direct message channel.
        case groupDM = 3
        /// A category channel that contains other channels.
        case guildCategory = 4
        /// An announcement channel in a guild.
        case guildAnnouncement = 5
        /// A thread within an announcement channel.
        case announcementThread = 10
        /// A public thread within a channel.
        case publicThread = 11
        /// A private thread within a channel.
        case privateThread = 12
        /// A Stage Voice channel in a guild.
        case guildStageVoice = 13
        /// A channel that serves as a directory within a guild.
        case guildDirectory = 14
        /// A forum channel within a guild.
        case guildForum = 15
        /// A channel for sharing media content.
        case guildMedia = 16
    }
}

/// Provides human-readable descriptions for each ChannelType case.
extension Channel.ChannelType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .guildText:            return "Guild Text"
        case .dm:                   return "DM"
        case .guildVoice:           return "Guild Voice"
        case .groupDM:              return "Group DM"
        case .guildCategory:        return "Guild Category"
        case .guildAnnouncement:    return "Guild Announcement"
        case .announcementThread:   return "Announcement Thread"
        case .publicThread:         return "Public Thread"
        case .privateThread:        return "Private Thread"
        case .guildStageVoice:      return "Guild Stage Voice"
        case .guildDirectory:       return "Guild Directory"
        case .guildForum:           return "Guild Forum"
        case .guildMedia:           return "Guild Media"
        }
    }
}
