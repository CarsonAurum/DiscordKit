// File: Tests/DiscordNIOTransportTests/DatagramAdapterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordNIOTransport

/// Datagram adapter conformance over independently bound loopback sockets.
@Suite struct DatagramAdapterTests {
    /// Supplies a failure deadline without using time to order successful assertions.
    /// - Returns: A fresh monotonic context expiring after ten seconds.
    private func context() -> TransportContext<ContinuousClock> {
        let clock = ContinuousClock()
        return .init(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
    }

    /// Owns two fresh sockets and awaits cleanup on both normal and failing exits.
    /// - Parameters:
    ///   - host: Numeric local loopback address; defaults to IPv4.
    ///   - body: Test operations that must not retain either socket.
    /// - Throws: Socket setup or the original assertion/setup failure.
    private func withPair(host: String = "127.0.0.1",
                          _ body: (NIODatagramTransport, NIODatagramTransport) async throws -> Void) async throws {
        let first = try await NIODatagramTransport.bind(localAddress: .init(host: host, port: 0), context: context())
        do {
            let second = try await NIODatagramTransport.bind(localAddress: .init(host: host, port: 0), context: context())
            do { try await body(first, second) }
            catch { await second.close(); throw error }
            await second.close()
        } catch { await first.close(); throw error }
        await first.close()
    }

    /// Confirms empty/binary packets retain payload boundaries and numeric source address.
    /// macOS can impose a UDP send ceiling below the protocol's 65,507-byte limit;
    /// the 8 KiB case stays within the qualified host's native datagram ceiling.
    /// - Parameter bytes: Complete empty, small, or qualified 8 KiB UDP payload.
    /// - Throws: Local binding, send, receive, or cleanup failures.
    @Test(arguments: [Data(), Data([0, 128, 255]), Data(repeating: 42, count: 8_192)])
    func loopback(bytes: Data) async throws {
        try await withPair { (sender: NIODatagramTransport, receiver: NIODatagramTransport) async throws in
            try await sender.sendDatagram(.init(bytes: bytes, peer: receiver.localAddress), context: context())
            let received = try #require(try await receiver.receiveDatagram(context: context()))
            #expect(received.bytes == bytes)
            #expect(received.peer == sender.localAddress)
            #expect(sender.localAddress.port != 0)
        }
    }

    /// Verifies the separate IPv6 socket-family path and source-address conversion.
    /// - Throws: Native IPv6 bind, send or receive failure on the qualified host.
    @Test func ipv6Loopback() async throws {
        try await withPair(host: "::1") { sender, receiver in
            try await sender.sendDatagram(.init(bytes: Data([6]), peer: receiver.localAddress), context: context())
            let packet = try #require(try await receiver.receiveDatagram(context: context()))
            #expect(packet.bytes == Data([6]))
            #expect(packet.peer == sender.localAddress)
            #expect(packet.peer.host == "::1")
        }
    }

    /// Rejects excessive outgoing packets before consuming or closing a healthy socket.
    /// - Throws: Unexpected local transport failures.
    @Test func oversizedSendAndInvalidAddressAreRecoverable() async throws {
        try await withPair { (sender: NIODatagramTransport, receiver: NIODatagramTransport) async throws in
            await #expect(throws: TransportFailure.chunkTooLarge(limit: 65_507, actual: 65_508)) {
                try await sender.sendDatagram(.init(bytes: Data(repeating: 0, count: 65_508),
                                                    peer: receiver.localAddress), context: context())
            }
            await #expect(throws: NIOServiceFailure.invalidAddress) {
                try await sender.sendDatagram(.init(bytes: Data(), peer: .init(host: "not a numeric address", port: 1)),
                                              context: context())
            }
            try await sender.sendDatagram(.init(bytes: Data([7]), peer: receiver.localAddress), context: context())
            #expect(try await receiver.receiveDatagram(context: context())?.bytes == Data([7]))
        }
    }

    /// Rejects a complete inbound packet above the configured size instead of truncating it.
    /// - Throws: Unexpected socket setup or communication failures.
    @Test func oversizedReceiveClosesSocket() async throws {
        let receiver = try await NIODatagramTransport.bind(maximumDatagramBytes: 2, context: context())
        let sender = try await NIODatagramTransport.bind(context: context())
        do {
            try await sender.sendDatagram(.init(bytes: Data([1, 2, 3]), peer: receiver.localAddress), context: context())
            await #expect(throws: TransportFailure.chunkTooLarge(limit: 2, actual: 3)) {
                try await receiver.receiveDatagram(context: context())
            }
        } catch { await sender.close(); await receiver.close(); throw error }
        await sender.close()
        await receiver.close()
    }

    /// Exercises single-reader admission and cancellation while a receive is pending.
    /// The first completed child must be the rejected duplicate, establishing the
    /// other receive has suspended before cancellation is requested.
    /// - Throws: Unexpected setup or receive failures.
    @Test func concurrentReceiveAndCancellation() async throws {
        let socket = try await NIODatagramTransport.bind(context: context())
        let noDeadline = TransportContext(clock: ContinuousClock())
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { _ = try await socket.receiveDatagram(context: noDeadline); return 0 }
                    catch TransportFailure.concurrentRead { return 1 }
                    catch is CancellationError { return 2 }
                    catch { return 3 }
                }
            }
            #expect(await group.next() == 1)
            group.cancelAll()
            #expect(await group.next() == 2)
        }
        await socket.close()
        #expect(try await socket.receiveDatagram(context: context()) == nil)
        await #expect(throws: TransportFailure.closed) {
            try await socket.sendDatagram(.init(bytes: Data(), peer: socket.localAddress), context: context())
        }
    }

    /// Rejects invalid budgets and DNS-like bind addresses before socket allocation.
    /// - Parameter limit: Invalid payload limit, including the two boundary violations.
    @Test(arguments: [0, -1, 65_508, Int.max])
    func invalidConfiguration(limit: Int) async {
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIODatagramTransport.bind(maximumDatagramBytes: limit, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIODatagramTransport.bind(maximumPendingDatagrams: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIODatagramTransport.bind(maximumPendingBytes: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidAddress) {
            try await NIODatagramTransport.bind(localAddress: .init(host: "localhost", port: 0), context: context())
        }
    }

    /// Covers inclusive already-expired binding and cancellation before resource setup.
    @Test func preflightDeadlineAndCancellation() async {
        let clock = ContinuousClock()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await NIODatagramTransport.bind(context: .init(clock: clock, deadline: clock.now))
        }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NIODatagramTransport.bind(context: .init(clock: ContinuousClock()))
        }
        do { _ = try await operation.value; Issue.record("Expected cancellation before bind") }
        catch { #expect(error is CancellationError) }
    }

    /// Advances an injected deadline while receiving, proving native cancellation
    /// unblocks the structured race and removes the clock's sleeper registration.
    /// - Throws: Local binding, manual-clock or barrier failures.
    @Test func deadlineDuringReceive() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let socket = try await NIODatagramTransport.bind(context: context())
        let registered = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { registered.open() })
        let operation = Task {
            try await socket.receiveDatagram(context: .init(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
        }
        try await registered.wait()
        try clock.advance(by: .seconds(1))
        do { _ = try await operation.value; Issue.record("Expected receive deadline") }
        catch { #expect(error as? TransportFailure == .deadlineExceeded) }
        #expect(clock.pendingSleepCount == 0)
        #expect(try await socket.receiveDatagram(context: context()) == nil)
        await socket.close()
    }

    /// Verifies repeated/concurrent close discards queued data and releases ownership.
    /// - Throws: Unexpected loopback setup or native send failures.
    @Test func closeIsConcurrentAndIdempotent() async throws {
        try await withPair { (sender: NIODatagramTransport, receiver: NIODatagramTransport) async throws in
            try await sender.sendDatagram(.init(bytes: Data([1]), peer: receiver.localAddress), context: context())
            async let first: Void = receiver.close()
            async let second: Void = receiver.close()
            _ = await (first, second)
            await receiver.close()
            #expect(try await receiver.receiveDatagram(context: context()) == nil)
            await #expect(throws: TransportFailure.closed) {
                try await receiver.sendDatagram(.init(bytes: Data(), peer: sender.localAddress), context: context())
            }
        }
    }
}

/// Deterministic mailbox and admission branches independent of native UDP delivery.
@Suite struct NIOServiceQueueTests {
    /// A socket slot cannot submit work before publication or after termination.
    /// Repeated terminal calls allocate no threads and retain no waiter/future work.
    @Test func channelSlotTerminalAdmission() async {
        let slot = NIOServiceChannelSlot()
        await #expect(throws: TransportFailure.closed) {
            try await slot.whileOpen { $0.eventLoop.makeSucceededFuture(()) }
        }
        slot.terminate(); slot.terminate()
        await #expect(throws: TransportFailure.closed) {
            try await slot.whileOpen { $0.eventLoop.makeSucceededFuture(()) }
        }
    }

    /// Confirms byte/count budgets, FIFO ordering, empty values and sticky termination.
    /// - Throws: Unexpected mailbox read failures.
    @Test func budgetsOrderingAndTermination() async throws {
        let queue = NIOServiceQueue<Data>(maximumCount: 2, maximumBytes: 3)
        #expect(queue.offer(Data(), bytes: 0))
        #expect(queue.offer(Data([1, 2, 3]), bytes: 3))
        #expect(!queue.offer(Data(), bytes: 0))
        #expect(try await queue.next() == Data())
        #expect(!queue.offer(Data([4]), bytes: 1))
        #expect(try await queue.next() == Data([1, 2, 3]))
        #expect(queue.offer(Data([4]), bytes: 1))
        queue.finish(NIOServiceFailure.queueOverflow)
        queue.finish()
        #expect(!queue.offer(Data(), bytes: 0))
        await #expect(throws: NIOServiceFailure.queueOverflow) { try await queue.next() }
        let closed = NIOServiceQueue<Data>(maximumCount: 1, maximumBytes: 1)
        closed.finish()
        #expect(try await closed.next() == nil)
    }

    /// Uses duplicate-read rejection as a registration barrier, then direct-delivers.
    /// - Throws: Unexpected mailbox failures.
    @Test func directDeliveryAndConcurrentRead() async throws {
        let queue = NIOServiceQueue<Data>(maximumCount: 1, maximumBytes: 1)
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return try await queue.next() == Data([8]) ? 8 : 0 }
                    catch TransportFailure.concurrentRead { return 1 }
                    catch { return 2 }
                }
            }
            #expect(await group.next() == 1)
            #expect(queue.offer(Data([8]), bytes: 1))
            #expect(await group.next() == 8)
        }
        queue.finish()
    }
}
