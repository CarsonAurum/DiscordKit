//
//  GlobalApplicationCommands.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/14/25.
//

import NIOHTTP1
import Logging
import AsyncHTTPClient
import Foundation

actor GlobalApplicationCommands {
    private let logger = Logger(label: "/applications/{app_id}/commands")
    private let url: String
    private let client: HTTPClient
    private let headers: HTTPHeaders
    private let coders: CoderPackage
    
    public init(client: HTTPClient, headers: HTTPHeaders, appID: Snowflake, coders: CoderPackage) {
        self.url = DiscordURL.GLOBAL_APPLICATION_COMMANDS(appID: appID)
        self.client = client
        self.headers = headers
        self.coders = coders
    }
    
    public func post(_ command: BotCommand) async throws -> ApplicationCommand? {
        var request = try HTTPClient.Request(url: self.url, method: .POST, headers: self.headers)
        request.body = try .bytes(coders.encoder.encode(command))
        let response = try await self.client.execute(request: request).get()
        
        guard response.status == .ok || response.status == .created else {
            logger.error("Received \(response.status) when creating command: \(command)")
            return nil
        }
        guard let responseBody = response.body else {
            logger.error("No command information received when creating command: \(command)")
            return nil
        }
        let responseData = Data(buffer: responseBody)
        let createdCommand = try coders.decoder.decode(ApplicationCommand.self, from: responseData)
        if response.status == .ok {
            logger.info("Updated Command: \(createdCommand)")
        } else if response.status == .created {
            logger.info("Created Command: \(createdCommand)")
        }
        return createdCommand
    }
    
    public func put(_ commands: [BotCommand]) async throws -> [ApplicationCommand]? {
        var request = try HTTPClient.Request(url: self.url, method: .PUT, headers: self.headers)
        request.body = try .bytes(coders.encoder.encode(commands))
        let response = try await self.client.execute(request: request).get()
        
        guard response.status == .ok else {
            logger.error("Received \(response.status) when putting commands.")
            return nil
        }
        guard let responseBody = response.body else {
            logger.error("No command information received when putting commands.")
            return nil
        }
        let responseData = Data(buffer: responseBody)
        let createdCommands = try coders.decoder.decode([ApplicationCommand].self, from: responseData)
        return createdCommands
    }
}
