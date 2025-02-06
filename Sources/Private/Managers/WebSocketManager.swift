//
//  WebSocketManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//
import Foundation
import Logging
import NIO
import WebSocketKit
import AnyCodable

// MARK: - WebSocketManager

actor WebSocketManager {
    
    /// The async stream providing events from the web socket.
    let eventStream: GatewayEventAsyncStream
    
    /// The async stream providing sequence numbers from the web socket.
    let sequenceStream: AsyncStream<Int>
    
    /// The reconnect manager to handle reconnection state.
    private let reconnectManager: ReconnectManager
    
    /// The JSON coders used within this manager.
    private let coders: CoderPackage
    
    /// The event loop group on which the web socket should run.
    private let eventLoopGroup: EventLoopGroup
    
    /// The living web socket, while it is available.
    private var webSocket: WebSocket?
    
    /// The continuation to push events.
    private var eventContinuation: GatewayEventAsyncStream.Continuation?
    
    /// The continuation to push sequence numbers.
    private var sequenceContinuation: AsyncStream<Int>.Continuation?
    
    /// A logger for this manager.
    let logger = Logger(label: "WebSocketManager")
    
    // MARK: - Initialization
    
    init(coders: CoderPackage, eventLoopGroup: EventLoopGroup, reconnectManager: ReconnectManager) {
        self.coders = coders
        self.eventLoopGroup = eventLoopGroup
        self.reconnectManager = reconnectManager
        
        var localEventContinuation: GatewayEventAsyncStream.Continuation?
        var localSequenceContinuation: AsyncStream<Int>.Continuation?
        self.eventStream = .init { localEventContinuation = $0 }
        self.eventContinuation = localEventContinuation
        self.sequenceStream = .init { localSequenceContinuation = $0 }
        self.sequenceContinuation = localSequenceContinuation
    }
    
    // MARK: - Connection Management
    
    /// Attempt a new web socket connection to the given URL.
    /// - Parameter endpoint: The endpoint URL to connect.
    func connect(to endpoint: String) async throws {
        await reconnectManager.setEndpoint(endpoint)
        let endpoint = endpoint + "/?v=10&encoding=json"
        
        try await WebSocket.connect(
            to: endpoint,
            configuration: .init(maxFrameSize: 1 << 24),
            on: eventLoopGroup
        ) { socket in
            Task { await self.setSocket(socket) }
            
            socket.onText { socket, txt in
                Task {
                    guard let data = txt.data(using: .utf8) else {
                        self.logger.error("Unable to decode text using UTF-8.")
                        return
                    }
                    do {
                        let event = try self.coders.decoder.decode(GatewayEvent<AnyCodable>.self, from: data)
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                if let sequence = event.sequence {
                                    await self.sequenceContinuation?.yield(sequence)
                                }
                            }
                            group.addTask {
                                await self.eventContinuation?.yield(event)
                            }
                        }
                    } catch {
                        self.logger.error("Unable to decode event: \(error)")
                    }
                }
            }
            socket.onClose.whenComplete { result in
                let shouldReset = socket.closeCode?.shouldAutoReconnect ?? true
                self.logger.info("Socket closed. Code: \(String(describing: socket.closeCode))")
                Task {
                    if let heartbeatManager = await self.heartbeatManager {
                        await heartbeatManager.stopHeartbeat()
                    }
                    if shouldReset {
                        try await self.reconnectManager.attemptReconnect(socketManager: self)
                    } else {
                        await self.terminate()
                    }
                }
            }
        }.get()
    }
    
    /// Send a gateway event with a given payload.
    func send<T>(opcode: GatewayEvent<T>.Opcode, data: T) where T: DiscordModel {
        do {
            let payload = GatewayEvent(opcode: opcode, data: data)
            let data = try self.coders.encoder.encode(payload)
            if let dataString = String(data: data, encoding: .utf8) {
                self.webSocket?.send(dataString)
                logger.debug("Sent: \(payload)")
                logger.trace("Payload: \(payload.data)")
            }
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// Disconnect the active websocket with a normal closure code.
    func disconnect(shouldTerminate: Bool = true) async throws {
        if shouldTerminate {
            try await webSocket?.close(code: .normalClosure)
        } else {
            try await webSocket?.close(code: .policyViolation)
        }
        try await Task.sleep(for: .milliseconds(100))
        if shouldTerminate {
            terminate()
        }
    }
    
    func terminate() {
        eventContinuation?.finish()
        sequenceContinuation?.finish()
    }
    
    // MARK: - Private Helpers
    
    /// Set the active socket.
    private func setSocket(_ socket: WebSocket) {
        self.webSocket = socket
    }
    
    /// A weak reference to the heartbeat manager.
    private weak var heartbeatManager: HeartbeatManager?
    
    func setHeartbeatManager(_ heartbeatManager: HeartbeatManager) {
        self.heartbeatManager = heartbeatManager
    }
}
