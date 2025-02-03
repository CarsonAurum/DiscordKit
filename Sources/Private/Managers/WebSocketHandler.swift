//
//  WebSocketHandler.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import Logging
import AnyCodable

// MARK: - WebSocketHandler

/// A manager responsible for responding to WebSocket events.
actor WebSocketHandler {
    
    /// Construct a new socket handler.
    /// - Parameters:
    ///  - socketManager: The socket manager to use when listening for messages.
    ///  - heartbeatManager: The heartbeat manager to use when heartbeating.
    ///  - decoder: The decoder to use when reading messages.
    init(
        socketManager: WebSocketManager,
        heartbeatManager: HeartbeatManager,
        identifyManager: IdentifyManager,
        reconnectManager: ReconnectManager,
        decoder: JSONDecoder) {
            self.socketManager = socketManager
            self.heartbeatManager = heartbeatManager
            self.identifyManager = identifyManager
            self.reconnectManager = reconnectManager
            self.decoder = decoder
    }
    
    /// Run an async-for loop
    func handle() async throws {
        if let socketManager = socketManager {
            for await msg in socketManager.eventStream {
                logger.debug("\(msg)")
                switch msg.opcode {
                case .dispatch:
                    Task {
                        handleDispatch(msg)
                    }
                case .heartbeat:
                    Task {
                        if let heartbeatManager = heartbeatManager {
                            await heartbeatManager.sendHeartbeat()
                        } else {
                            self.logger.error("No HeartbeatManager found!")
                        }
                    }
                case .hello:
                    Task {
                        do {
                            let payload = try decoder.decode(HelloPayload.self, from: msg.getData())
                            logger.trace("Payload: \(payload)")
                            if let heartbeatManager = heartbeatManager {
                                await heartbeatManager.setInterval(payload.interval)
                                if let identifyManager = identifyManager {
                                    await identifyManager.send()
                                    await heartbeatManager.startHeartbeat()
                                } else {
                                    self.logger.error("No IdentifyManager found!")
                                }
                            } else {
                                self.logger.error("No HeartbeatManager found!")
                            }
                        } catch {
                            logger.error("\(error)")
                        }
                    }
                case .heartbeatACK:
                    if let heartbeatManager = heartbeatManager {
                        Task {
                            await heartbeatManager.acknowledgeHeartbeat()
                        }
                    } else {
                        self.logger.error("No HeartbeatManager found!")
                    }
                case .invalidSession:
                    do {
                        logger.trace("\(msg.data)")
                        let isResumable = try decoder.decode(Bool.self, from: msg.getData())
                        if isResumable {
                            logger.warning("Invalid session, attempting to resume...")
                            try await reconnectManager?.reconnect()
                        } else {
                            logger.warning("Invalid session, full reconnect required. Waiting 5s...")
                            try await socketManager.disconnect()
                            try await Task.sleep(for: .seconds(2))
                            try await socketManager.connect(to: "wss://gateway.discord.gg/?v=10&encoding=json")
                        }
                    } catch {
                        logger.error("\(error)")
                    }
                default:
                    self.logger.warning("Unhandled Opcode: \(msg.opcode)")
                }
            }
        } else {
            logger.error("No WebSocket found!")
        }
    }
    
    // MARK: Private
    
    /// The logger to use within this manager.
    private let logger = Logger(label: "WebSocketHandler")
    
    /// The socket manager to use when listening for messages.
    private weak var socketManager: WebSocketManager?
    
    /// The heartbeat manager to use when heartbeating.
    private weak var heartbeatManager: HeartbeatManager?
    
    /// The identify manager to use for identification.
    private weak var identifyManager: IdentifyManager?
    
    private weak var reconnectManager: ReconnectManager?
    
    /// The decoder to use when reading messages.
    private let decoder: JSONDecoder
}

// MARK: Private Handlers

extension WebSocketHandler {
    
    /// A private handler to specifically isolate dispatch messages.
    /// - Parameter message: The message to handle.
    private func handleDispatch(_ message: GatewayEvent<AnyCodable>) {
        switch message.name {
        case .guildCreate:
            do {
                let payload = try decoder.decode(Guild.self, from: message.getData())
                logger.trace("Payload: \(payload)")
            } catch {
                logger.error("\(error)")
            }
        case .presenceUpdate:
            do {
                let payload = try decoder.decode(Presence.Update.self, from: message.getData())
                logger.trace("Payload: \(payload)")
            } catch {
                logger.error("\(error)")
            }
        case .ready:
            do {
                let payload = try decoder.decode(ReadyPayload.self, from: message.getData())
                logger.trace("Payload: \(payload)")
                Task { await reconnectManager?.setReconnectInfo(url: payload.resumeURL, id: payload.sessionID) }
            } catch {
                logger.error("\(error)")
            }
        case .unknown(let name):
            logger.debug("Unhandled Dispatch: \(name.uppercased())")
        default:
            return
        }
    }
}


