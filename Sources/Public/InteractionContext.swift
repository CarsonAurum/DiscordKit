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

public actor InteractionContext {
    private let
    private let responseRoute: String
    private let client: HTTPClient
    private let headers: HTTPHeaders
    private let coders: CoderPackage
    init(
        client: HTTPClient,
        headers: HTTPHeaders,
        coders: CoderPackage,
        interaction: Interaction) {
            self.client = client
            self.headers = headers
            self.coders = coders
        self.responseRoute = "/interactions/\(interaction.id.value)/\(interaction.token)/callback/"
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
    }
}
