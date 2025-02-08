//
//  Optional+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/1/25.
//

extension Optional {
    var isSome: Bool { self != nil }
    var isNone: Bool { self == nil }
}
