//
//  Channel+ChannelType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Channel {
    public enum ChannelType: Int, DiscordModel {
        case guildText = 0
        case dm = 1
        case guildVoice = 2
        case groupDM = 3
        case guildCategory = 4
        case guildAnnouncement = 5
        case announcementThread = 10
        case publicThread = 11
        case privateThread = 12
        case guildStageVoice = 13
        case guildDirectory = 14
        case guildForum = 15
        case guildMedia = 16
    }
}

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
