//
//  Reference+ReferenceType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Reference {
    public enum ReferenceType: Int, DiscordModel {
        case `default` = 0
        case forward = 1
    }
}
