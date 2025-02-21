//
//  Optional+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/1/25.
//

extension Optional {
    internal var isSome: Bool { self != nil }
    internal var isNone: Bool { self == nil }
}
