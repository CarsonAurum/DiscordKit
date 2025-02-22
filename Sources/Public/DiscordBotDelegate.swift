//
//  DiscordBotDelegate.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/21/25.
//
public protocol DiscordBotDelegate: AnyObject, Sendable {
    func discordBot (onready data: ReadyData)
    func discordBot (onReconnect: Void)
    func discordBot (onMessageCreate data: Message)
    
}
