//
//  DiscordBotDelegate.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/21/25.
//
public protocol DiscordBotDelegate: AnyObject, Sendable {
    func discordBot(onReady data: ReadyData) async
    func discordBot(onReconnect: Void) async
    func discordBot(onMessageCreate data: Message) async
}

extension DiscordBotDelegate {
    public func discordBot(onReady data: ReadyData) async { }
    public func discordBot(onReconnect: ()) async { }
    public func discordBot(onMessageCreate data: Message) async { }
}
