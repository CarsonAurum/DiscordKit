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
    let responseRoute: String
    let client: HTTPClient
    let headers: HTTPHeaders
    let coders: CoderPackage
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
}
