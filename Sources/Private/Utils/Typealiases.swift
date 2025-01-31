//
//  Typealiases.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import AnyCodable

/// Codable, Hashable, Sendable
internal typealias DiscordModel = Codable & Hashable & Sendable

/// A tuple containing a JSON encoder and decoder pair
internal typealias CoderPackage = (encoder: JSONEncoder, decoder: JSONDecoder)

/// A stream of gateway events that can be iterated over in an async manner.
internal typealias GatewayEventAsyncStream = AsyncStream<GatewayEvent<AnyCodable>>
