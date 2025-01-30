//
//  WebSocketManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import AnyCodable
import Foundation
import Logging
import NIO
import WebSocketKit

/// A manager handling an active web socket connection.
actor WebSocketManager {
    
    /// The async stream providing events from the web socket.
    public let eventStream: GatewayEventAsyncStream
    
    /// The async stream providing sequence numbers from the web socket.
    public let sequenceStream: AsyncStream<Int>
    
    /// Construct a new web socket manager.
    /// - Parameters:
    ///   - coders: The JSON encoder/decoder to use within this manager.
    ///   - eventLoopGroup: The event loop on which the web socket should run.
    public init(coders: CoderPackage, eventLoopGroup: EventLoopGroup) {
        self.coders = coders
        self.eventLoopGroup = eventLoopGroup
        
        var localEventContinuation: GatewayEventAsyncStream.Continuation?
        var localSequenceContinuation: AsyncStream<Int>.Continuation?
        
        self.eventStream = .init { localEventContinuation = $0 }
        self.eventContinuation = localEventContinuation
        self.sequenceStream = .init { localSequenceContinuation = $0 }
        self.sequenceContinuation = localSequenceContinuation
    }
    
    /// Attempt a new web socket connection to the given URL.
    /// - Parameter endpoint: The endpoint URL to connect.
    public func connect(to endpoint: String) async throws {
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
                        self.logger.error("Unable to decode event.")
                    }
                }
            }
            socket.onClose.whenComplete { result in
                Task {
                    self.logger.info(
                        "Socket closed. Code: \(socket.closeCode.debugDescription)"
                    )
                    await self.eventContinuation?.finish()
                    await self.sequenceContinuation?.finish()
                }
            }
        }.get()
    }
    
    /// The logger to use within this manager.
    private let logger = Logger(label: "WebSocketManager")
    
    /// The event loop on which to run the web socket connection.
    private let eventLoopGroup: EventLoopGroup
    
    /// The JSON coders to use within this manager.
    private let coders: CoderPackage
    
    /// The living web socket, while it is available.
    private var webSocket: WebSocket?
    
    /// The continuation to push events.
    private var eventContinuation: GatewayEventAsyncStream.Continuation?
    
    /// The continuation to push sequence numbers.
    private var sequenceContinuation: AsyncStream<Int>.Continuation?
    
    /// Set the socket, within this actor's context.
    /// - Parameter socket: The socket to set.
    private func setSocket(_ socket: WebSocket) { self.webSocket = socket }
}
