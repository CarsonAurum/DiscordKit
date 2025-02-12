//
//  InteractionContext.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/9/25.
//

import NIOHTTP1
import NIO
import AnyCodable
import AsyncHTTPClient
import Logging

public actor InteractionContext {
    private let responseRoute: String
    private let client: HTTPClient
    private let headers: HTTPHeaders
    private let coders: CoderPackage
    private let logger = Logger(label: "InteractionContext")
    init(
        client: HTTPClient,
        headers: HTTPHeaders,
        coders: CoderPackage,
        interaction: Interaction) {
            self.client = client
            self.headers = headers
            self.coders = coders
        self.responseRoute = "/interactions/\(interaction.id.value)/\(interaction.token)/callback/?with_response=true"
    }
    
    public func sendMessage(_ msg: String) async {
        let body = Interaction.Response(
            type: .channelMessageWithSource,
            data: .message(.init(
                isTTS: nil,
                content: msg,
                flags: nil,
                components: nil,
                attachments: nil
            ))
        )
        logger.trace("Sending: \(body)")
        do {
            let request = try HTTPClient.Request(
                url: self.responseRoute,
                method: .POST,
                headers: self.headers,
                body: .bytes(self.coders.encoder.encode(body))
            )
            let response = try await self.client.execute(request: request).get()
            if response.status == .ok {
                logger.trace("Status: OK.")
                if let body = response.body {
                    let callbackResponse = try self.coders.decoder.decode(Interaction.CallbackResponse.self, from: .init(buffer: body))
                    logger.trace("Payload: \(callbackResponse)")
                } else {
                    logger.error("No Body.")
                }
            } else {
                logger.error("Received: \(response.status)")
            }
        } catch {
            logger.error("\(error)")
        }
    }
}
