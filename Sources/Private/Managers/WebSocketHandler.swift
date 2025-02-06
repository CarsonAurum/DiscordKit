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
    ///   - socketManager: The socket manager to use when listening for messages.
    ///   - heartbeatManager: The heartbeat manager to use when heartbeating.
    ///   - identifyManager: The identify manager to use for authentication/resume.
    ///   - decoder: The decoder to use when reading messages.
    ///   - reconnectManager: The reconnect manager to use for handling reconnections.
    init(
        socketManager: WebSocketManager,
        heartbeatManager: HeartbeatManager,
        identifyManager: IdentifyManager,
        decoder: JSONDecoder,
        reconnectManager: ReconnectManager
    ) {
        self.socketManager = socketManager
        self.heartbeatManager = heartbeatManager
        self.identifyManager = identifyManager
        self.decoder = decoder
        self.reconnectManager = reconnectManager
    }
    
    /// Run an async-for loop to handle incoming events.
    func handle() async throws {
        if let socketManager = socketManager {
            for await msg in socketManager.eventStream {
                logger.debug("Received: \(msg)")
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
                            logger.trace("Hello payload: \(payload)")
                            if let shouldResume = await identifyManager?.shouldAttemptResume,
                               shouldResume,
                               let lastSequence = await heartbeatManager?.sequence {
                                logger.info("Attempting resume with sequence \(lastSequence)")
                                await identifyManager?.sendResume(sequence: lastSequence)
                            } else {
                                logger.info("Sending new identify payload.")
                                await identifyManager?.sendIdentify()
                            }
                            if let heartbeatManager = heartbeatManager {
                                await heartbeatManager.setInterval(payload.interval)
                                await heartbeatManager.startHeartbeat()
                            } else {
                                self.logger.error("No HeartbeatManager found!")
                            }
                        } catch {
                            logger.error("Error decoding hello payload: \(error)")
                        }
                    }
                case .reconnect:
                    Task {
                        logger.info("Received reconnect opcode from gateway. Reconnecting...")
                        do {
                            try await socketManager.disconnect(shouldTerminate: false)
                            try await Task.sleep(for: .seconds(1))
                            try await reconnectManager?.attemptReconnect(socketManager: socketManager)
                        } catch {
                            logger.error("Error during reconnect: \(error)")
                        }
                    }
                case .invalidSession:
                    Task {
                        do {
                            // The invalid session payload is expected to be a Boolean.
                            let canResume = try decoder.decode(Bool.self, from: msg.getData())
                            logger.info("Received invalid session opcode. canResume: \(canResume)")
                            try await socketManager.disconnect()
                            try await Task.sleep(for: .seconds(1))
                            if canResume {
                                await identifyManager?.setShouldAttemptResume(true)
                            } else {
                                await identifyManager?.clearSession()
                            }
                            try await reconnectManager?.attemptReconnect(socketManager: socketManager)
                        } catch {
                            logger.error("Error handling invalid session: \(error)")
                        }
                    }
                case .heartbeatACK:
                    if let heartbeatManager = heartbeatManager {
                        Task { await heartbeatManager.acknowledgeHeartbeat() }
                    } else {
                        self.logger.error("No HeartbeatManager found!")
                    }
                default:
                    self.logger.warning("Unhandled Opcode: \(msg.opcode)")
                }
            }
        } else {
            logger.error("No WebSocket found!")
        }
    }
    
    func setReadyHandler(_ handler: @Sendable @escaping (ReadyData) async -> Void) {
        self.readyHandler = handler
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
    
    /// The reconnect manager used for reconnection logic.
    private weak var reconnectManager: ReconnectManager?
    
    /// The decoder to use when reading messages.
    private let decoder: JSONDecoder
    
    private var readyHandler: (@Sendable (ReadyData) async -> Void)?
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
                Task { [weak self] in
                    await withTaskGroup(of: Void.self) { [weak self] group in
                       group.addTask { [weak self] in await self?.reconnectManager?.setEndpoint(payload.resumeURL) }
                      // group.addTask { [weak self] in await self?.identifyManager?.setSessionID(payload.socketManager?.self) }
                        group.addTask { [weak self] in
                            await self?.readyHandler?(.init(
                                guilds: payload.guilds,
                                user: payload.user,
                                application: payload.application
                            ))
                        }
                    }
                }
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
