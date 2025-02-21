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
import Foundation
import Collections

public actor InteractionContext {
    private let logger = Logger(label: "InteractionContext")
    private let responseRoute: String
    private let client: HTTPClient
    private let headers: HTTPHeaders
    private let coders: CoderPackage
    private var responseDeque: Deque<Interaction.Response>
    private var callbackDeque: Deque<Interaction.CallbackResponse>
    init(
        client: HTTPClient,
        headers: HTTPHeaders,
        coders: CoderPackage,
        interaction: Interaction) {
            self.client = client
            self.headers = headers
            self.coders = coders
            self.responseRoute = "interactions/\(interaction.id.value)/\(interaction.token)/callback?with_response=true"
            self.responseDeque = []
            self.callbackDeque = []
    }
    
    public func deferReply(isEphemeral: Bool = false) async {
        let flags: Message.Flags = isEphemeral ? [.ephemeral] : []
        let body = Interaction.Response(
            type: .deferredChannelMessageWithSource,
            data: .message(.init(
                isTTS: nil,
                content: nil,
                embeds: nil,
                flags: flags,
                components: nil,
                attachments: nil
            ))
        )
        responseDeque.append(body)
        logger.trace("Sending: \(body)")
        do {
            let bodyData = try coders.encoder.encode(body)
            let result = try await _sendData(bodyData)
            
        } catch {
            logger.error("\(error)")
        }
    }
    
    public func sendMessage(_ msg: String) async {
        let body = Interaction.Response(
            type: .channelMessageWithSource,
            data: .message(.init(
                isTTS: nil,
                content: msg,
                embeds: nil,
                flags: nil,
                components: nil,
                attachments: nil
            )))
        if callbackDeque.isEmpty {
            logger.trace("Sending: \(body)")
            do {
                let result = try await _sendData(coders.encoder.encode(body))
            } catch {
                logger.error("\(error)")
            }
        } else {
            
        }
    }
    
    private func _sendData(_ data: Data) async throws -> Interaction.CallbackResponse? {
        
        let request = try HTTPClient.Request(
            url: DiscordURL.BASE_URL + self.responseRoute,
            method: .POST,
            headers: self.headers,
            body: .bytes(data)
        )
        let response = try await self.client.execute(request: request).get()
        if response.status == .ok {
            logger.trace("Status: OK.")
            if let body = response.body {
                let callbackResponse = try self.coders.decoder.decode(
                    Interaction.CallbackResponse.self,
                    from: .init(buffer: body)
                )
                logger.trace("Payload: \(callbackResponse)")
                callbackDeque.append(callbackResponse)
                return callbackResponse
            } else {
                logger.error("No Body.")
                return nil
            }
        } else {
            logger.error("Received: \(response.status)")
            return nil
        }
    }
}
