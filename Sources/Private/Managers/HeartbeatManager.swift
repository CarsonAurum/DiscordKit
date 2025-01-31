//
//  HeartbeatManager.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Logging
import NIO

// MARK: - HeartbeatManager

/// A manager to facilitate regular heartbeats across Discord's gateway.
actor HeartbeatManager {
    
    /// Construct a new heartbeat manager.
    /// - Parameters:
    ///   - socketManager: The socket manager to use when sending heartbeats.
    ///   - sequenceStream: The stream to observe for changes in sequence value from the web socket.
    init(_ socketManager: WebSocketManager, sequenceStream: AsyncStream<Int>) {
        self.socketManager = socketManager
        self.sequenceStream = sequenceStream
    }
    
    /// Change the interval from within the manager's thread context.
    /// - Parameter interval: The new interval.
    func setInterval(_ interval: Int) {
        self.interval = interval
    }
    
    /// Initialize the new heartbeat task and sequence task.
    /// - Note: This will only happen if the interval is set, and no previous heartbeat task is running.
    func startHeartbeat() {
        guard let interval = self.interval else {
            logger.critical("Cannot start heartbeat: no interval set.")
            return
        }
        guard heartbeatTask == nil else {
            logger.warning("startHeartbeat() called but heartbeat is already running.")
            return
        }
        logger.debug("Starting heartbeat loop. Interval: \(interval) ms.")
        sequenceTask = Task {
            for await newSequence in sequenceStream {
                self.sequence = newSequence
            }
        }
        heartbeatTask = Task {
            while !Task.isCancelled {
                await sendHeartbeat()
                do {
                    try await Task.sleep(for: .milliseconds(interval))
                } catch { }
            }
        }
    }
    
    /// Stop the heartbeat and sequence tasks.
    func stopHeartbeat() {
        logger.debug("Stopping heartbeat...")
        heartbeatTask?.cancel()
        heartbeatTask = nil
        sequenceTask?.cancel()
        sequenceTask = nil
        ackTimeoutTask?.cancel()
        ackTimeoutTask = nil
        pendingAck = false
    }
    
    /// Used to acknowledge a heartbeat from Discord's API.
    func acknowledgeHeartbeat() {
        pendingAck = false
        ackTimeoutTask?.cancel()
        ackTimeoutTask = nil
        logger.debug("Heartbeat Acknowledged.")
    }
    
    /// Send a heartbeat.
    func sendHeartbeat() async {
        logger.debug("Sending heartbeat with sequence \(sequence.map(String.init) ?? "<nil>").")
        pendingAck = true
        await self.socketManager?.send(opcode: .heartbeat, data: sequence)
        ackTimeoutTask?.cancel()
        ackTimeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                handleAckTimeout()
            } catch { }
        }
    }
    
    // MARK: Private
    
    /// The handler for acknowledgement timeouts.
    private func handleAckTimeout() {
        guard pendingAck else { return }
        logger.error("Heartbeat not acknowledged: Connection Unstable.")
        stopHeartbeat()
    }
    
    /// The socket manager to use when sending heartbeats.
    private weak var socketManager: WebSocketManager?
    
    /// The logger to use within this manager.
    private let logger = Logger(label: "HeartbeatManager")
    
    /// The stream to observe when looking for a sequence value.
    private let sequenceStream: AsyncStream<Int>
    
    /// The most recent sequence value, if it exists.
    private var sequence: Int?
    
    /// The most recent interval value, if it exists.
    private var interval: Int?
    
    /// Heartbeat task storage.
    private var heartbeatTask: Task<Void, Never>?
    
    /// Acknowledgement timeout task storage.
    private var ackTimeoutTask: Task<Void, Never>?
    
    //// Sequence task storage.
    private var sequenceTask: Task<Void, Never>?
    
    /// Flag to determine if the manager is waiting for acknowledgement on the previously sent heartbeat.
    private var pendingAck: Bool = false
    
}

