//
//  Typealiases.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import AnyCodable

internal typealias DiscordModel = Codable & Hashable & Sendable
internal typealias CoderPackage = (encoder: JSONEncoder, decoder: JSONDecoder)
internal typealias GatewayEventAsyncStream = AsyncStream<Void>
