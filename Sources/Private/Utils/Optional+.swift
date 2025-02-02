//
//  Optional+.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/1/25.
//

extension Optional {
    public var isSome: Bool { self != nil }
    public var isNone: Bool { self == nil }
}
