//
//  Channel+ChannelType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension Channel {
    /// An enumeration of the various channel types supported by Discord.
    @PrettyDescription
    public enum ChannelType: Int, DiscordModel, CustomStringConvertible {
        /// A text channel within a guild.
        case guildText = 0
        /// A direct message channel between two users.
        case dm = 1
        /// A voice channel within a guild.
        case guildVoice = 2
        /// A group direct message channel.
        case groupDm = 3
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
