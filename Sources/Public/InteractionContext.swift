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
    private let initialResponseRoute: String
    private let webhookRoute: String
    private let client: HTTPClient
    private let headers: HTTPHeaders
    private let coders: CoderPackage
    private var responseDeque: Deque<Interaction.Response>
    private var callbackDeque: Deque<Interaction.CallbackResponse>
    public let interaction: Interaction
    init(
        client: HTTPClient,
        headers: HTTPHeaders,
        coders: CoderPackage,
        interaction: Interaction) {
            self.client = client
            self.headers = headers
            self.coders = coders
            self.initialResponseRoute = "interactions/\(interaction.id.value)/\(interaction.token)/callback?with_response=true"
            self.webhookRoute =
                "webhooks/\(interaction.applicationID.value)/\(interaction.token)/"
            self.responseDeque = []
            self.callbackDeque = []
            self.interaction = interaction
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
            let result = try await _sendInitialData(bodyData)
            if let result = result {
                callbackDeque.append(result)
            }
        } catch {
            logger.error("\(error)")
        }
    }
    
    public func sendMessage(_ msg: String) async {
        if callbackDeque.isEmpty {
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
            responseDeque.append(body)
            logger.trace("Sending: \(body)")
            do {
                _ = try await _sendInitialData(coders.encoder.encode(body))
            } catch {
                logger.error("\(error)")
            }
        } else if callbackDeque.first?.interaction.isResponseMessageLoading ?? false {
            let payload = EditWebhookMessagePayload(content: msg)
            logger.trace("Editing original deferred message with payload: \(payload)")
            do {
                let bodyData = try coders.encoder.encode(payload)
                _ = try await _sendEditInitialData(bodyData)
            } catch {
                logger.error("\(error)")
            }
        } else {
            // Possibly handle followup logic here in future
        }
    }
    
    private func _sendEditInitialData(_ data: Data) async throws -> Message? {
        let request = try HTTPClient.Request(
            url: DiscordURL.BASE_URL + self.webhookRoute + "messages/@original",
            method: .PATCH,
            headers: self.headers,
            body: .bytes(data)
        )
        let response = try await self.client.execute(request: request).get()
        if response.status == .ok {
            logger.trace("Status: OK.")
            if let body = response.body {
                let callbackResponse = try self.coders.decoder.decode(
                    Message.self,
                    from: .init(buffer: body)
                )
                logger.trace("Payload: \(callbackResponse)")
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
    
    private func _sendInitialData(_ data: Data) async throws -> Interaction.CallbackResponse? {
        let request = try HTTPClient.Request(
            url: DiscordURL.BASE_URL + self.initialResponseRoute,
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
