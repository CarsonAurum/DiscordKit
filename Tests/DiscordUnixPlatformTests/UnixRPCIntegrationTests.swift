// File: Tests/DiscordUnixPlatformTests/UnixRPCIntegrationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if !os(Windows) && !os(WASI)
import DiscordCore
import DiscordRPC
import DiscordTestSupport
import DiscordTransport
import DiscordUnixPlatform
import Foundation
import NIOCore
import NIOPosix
import Synchronization
import Testing

/// Native Unix-domain integration with a simulated RPC v1 desktop peer, never Discord itself.
@Suite("Native Unix RPC integration")
struct UnixRPCIntegrationTests {
    /// Runs discovery/open, IPC handshake, READY, correlated GET_GUILDS and opaque ping/pong
    /// over real Unix sockets. Cancels an admitted unanswered GET_CHANNELS without replay,
    /// then closes the RPC session and awaits native peer EOF plus queue/resource cleanup.
    /// No credentials, actual desktop endpoint, TCP service or wall-clock sleep is used.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nativeUnixRPCHandshakeRequestControlAndCancellation() async throws {
        let peer = try await UnixRPCPeer.open()
        let clock = ContinuousClock()
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(20)))
        do {
            let opener = UnixRPCNativeOpening()
            let connector = try RPCIPCConnector(platform: .unix, environment: ["XDG_RUNTIME_DIR": peer.directory],
                indices: 0..<1, opener: opener, maximumPayloadBytes: 4_096)
            let client = try RPCClient(applicationID: .init(rawValue: UInt64.max), clock: clock, connector: connector,
                maximumPendingRequests: 2, maximumPendingBytes: 8_192, maximumEvents: 2,
                maximumEventBytes: 8_192, maximumPayloadBytes: 4_096)
            do {
                let ready = try await client.connect(context: context)
                #expect(ready == .object(["v": .number(try JSONNumber(rawValue: "1"))]))
                let result = try await client.request(.getGuilds(), context: context)
                #expect(result == .object(["guilds": .array([.object([
                    "id": .string("18446744073709551615"), "name": .string("Local Guild")])])]))
                try await context.run { try await peer.observation.pongReceived.wait() }
                let held = Task {
                    try await client.request(.getChannels(.init(rawValue: UInt64.max)), context: context)
                }
                try await context.run { try await peer.observation.heldRequestReceived.wait() }
                held.cancel()
                await #expect(throws: CancellationError.self) { _ = try await held.value }
                #expect(await client.resourceCounts().pending == 0)
                #expect(await client.resourceCounts().pendingBytes == 0)
                await client.close()
                await client.close()
                try await context.run { try await peer.observation.connectionClosed.wait() }
                let counts = await client.resourceCounts()
                #expect(counts.pending == 0 && counts.pendingBytes == 0 && counts.events == 0 && counts.eventBytes == 0)
                let observed = peer.observation.snapshot()
                #expect(!observed.invalidWire)
                #expect(observed.handshake == .object(["v": .number(try JSONNumber(rawValue: "1")),
                    "client_id": .string("18446744073709551615")]))
                #expect(observed.commands == ["GET_GUILDS", "GET_CHANNELS"])
                #expect(observed.pong == Data([0, 255, 128]))
                #expect(observed.closedConnections == 1)
                #expect(await opener.openCount == 1)
            } catch {
                await client.close()
                throw error
            }
        } catch {
            await peer.close()
            throw error
        }
        await peer.close()
        #expect(!FileManager.default.fileExists(atPath: peer.directory))
    }
}

/// Opens only the explicit fixture candidate using the actual production Unix adapter.
private actor UnixRPCNativeOpening: RPCIPCOpening {
    var openCount = 0

    /// Opens a real local Unix stream with finite native read/write budgets.
    /// - Parameters:
    ///   - path: Unique test-owned absolute socket path supplied by RPC discovery.
    ///   - context: Clock/deadline/cancellation spanning native connection startup.
    /// - Returns: Owned native transport whose lifetime passes to the RPC connection.
    /// - Throws: Native path/open, cancellation or deadline errors; no fallback is used.
    func open<C: Clock>(path: String, context: TransportContext<C>) async throws -> any IPCTransport where C.Duration == Duration {
        openCount += 1
        return try await UnixIPCTransport.connect(path: path, maximumBufferedBytes: 8_192,
            maximumWriteBytes: 4_104, context: context)
    }
}

/// Thread-safe finite observation record shared by the event-loop handler and async test.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class UnixRPCObservation: Sendable {
    struct State: Sendable {
        var handshake: JSONValue?
        var commands: [String] = []
        var pong: Data?
        var invalidWire = false
        var closedConnections = 0
    }
    private let state = Mutex(State())
    let pongReceived = TestBarrier()
    let heldRequestReceived = TestBarrier()
    let connectionClosed = TestBarrier()

    /// Captures the validated native IPC handshake once for final identity/version assertions.
    /// - Parameter value: Parsed bounded handshake object supplied by the RPC runtime.
    func recordHandshake(_ value: JSONValue) { state.withLock { $0.handshake = value } }

    /// Records at most two command names so a malformed peer cannot grow fixture storage.
    /// - Parameter command: Exact parsed command name, without nonce or argument contents.
    /// - Returns: Whether the finite test command capacity remained available.
    func recordCommand(_ command: String) -> Bool {
        state.withLock { value in
            guard value.commands.count < 2 else { value.invalidWire = true; return false }
            value.commands.append(command)
            return true
        }
    }

    /// Captures a bounded opaque pong payload and releases the async assertion gate.
    /// - Parameter bytes: Exact IPC pong bytes, at most 4,096 under the frame decoder cap.
    func recordPong(_ bytes: Data) { state.withLock { $0.pong = bytes }; pongReceived.open() }

    /// Marks malformed/unexpected frames without exposing the peer's raw bytes in errors.
    func markInvalidWire() { state.withLock { $0.invalidWire = true } }

    /// Counts native disconnection and unblocks cleanup verification after channel inactivity.
    func recordClosed() {
        state.withLock { $0.closedConnections += 1 }
        connectionClosed.open()
    }

    /// Reads an immutable bounded observation snapshot under the shared mutex.
    /// - Returns: Handshake, command/control evidence and cleanup counts.
    func snapshot() -> State { state.withLock { $0 } }
}

/// Unique Unix listener and event loop owned by exactly one native integration test.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct UnixRPCPeer: Sendable {
    let group: MultiThreadedEventLoopGroup
    let channel: any Channel
    let directory: String
    let observation: UnixRPCObservation

    /// Binds one short unique `discord-ipc-0` fixture namespace without desktop discovery.
    /// - Returns: Owned listener and observation state; caller must await close on every exit.
    /// - Throws: Temporary directory, Unix bind, handler or frame-decoder setup failures.
    static func open() async throws -> UnixRPCPeer {
        let directory = "/tmp/dkrpc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let observation = UnixRPCObservation()
        do {
            let channel = try await ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(UnixRPCPeerHandler(observation: observation))
                    }
                }.bind(unixDomainSocketPath: directory + "/discord-ipc-0").get()
            return UnixRPCPeer(group: group, channel: channel, directory: directory, observation: observation)
        } catch {
            try? await group.shutdownGracefully()
            try? FileManager.default.removeItem(atPath: directory)
            throw error
        }
    }

    /// Closes the fixture listener, awaits its event-loop shutdown and removes the namespace.
    /// The test closes its RPC client before calling this method so accepted channels reach EOF.
    func close() async {
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
        try? await group.shutdownGracefully()
        try? FileManager.default.removeItem(atPath: directory)
    }
}

/// Event-loop-confined simulated desktop; implements only handshake and this test's two commands.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class UnixRPCPeerHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private var decoder: RPCFrameDecoder
    private let observation: UnixRPCObservation

    /// Stores thread-safe observation and a finite incremental decoder before activation.
    /// - Parameter observation: Shared evidence and deterministic async synchronization gates.
    /// - Throws: Frame limit validation failure, which prevents accepting a test connection.
    init(observation: UnixRPCObservation) throws {
        decoder = try RPCFrameDecoder(maximumPayloadBytes: 4_096)
        self.observation = observation
    }

    /// Decodes actual Unix fragments and emits bounded READY, ping and command responses.
    /// - Parameters:
    ///   - context: Sole event-loop owner of native writes and handler state.
    ///   - data: Arbitrarily split/coalesced raw native bytes, capped by the decoder.
    /// Invalid input closes the simulated peer and is reported in final observations.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        do {
            var buffer = unwrapInboundIn(data)
            let bytes = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
            for frame in try decoder.append(bytes) {
                switch frame.opcode {
                case .handshake:
                    let value = try JSONValue.parse(frame.payload)
                    observation.recordHandshake(value)
                    try send([RPCFrame(opcode: .frame, payload: JSONValue.object([
                        "cmd": .string("DISPATCH"), "evt": .string("READY"),
                        "data": .object(["v": .number(try JSONNumber(rawValue: "1"))])]).serialized())], context: context)
                case .pong: observation.recordPong(frame.payload)
                case .frame:
                    guard case .object(let object) = try JSONValue.parse(frame.payload),
                          case .string(let command) = object["cmd"], let nonce = object["nonce"],
                          observation.recordCommand(command) else { throw RPCFailure.invalidPayload }
                    if command == "GET_GUILDS" {
                        let response = try JSONValue.object(["cmd": .string(command), "nonce": nonce, "evt": .null,
                            "data": .object(["guilds": .array([.object(["id": .string("18446744073709551615"),
                                                                       "name": .string("Local Guild")])])])]).serialized()
                        try send([.init(opcode: .ping, payload: Data([0, 255, 128])),
                                  .init(opcode: .frame, payload: response)], context: context)
                    } else if command == "GET_CHANNELS" {
                        observation.heldRequestReceived.open()
                    } else { throw RPCFailure.invalidPayload }
                default: throw RPCFailure.malformedFrame
                }
            }
        } catch {
            observation.markInvalidWire()
            context.close(promise: nil)
        }
    }

    /// Coalesces finite complete frames into one native write, exercising client frame splitting.
    /// - Parameters:
    ///   - frames: One READY frame or one ping-plus-response pair.
    ///   - context: Event-loop-confined socket writer; no concurrent write task is created.
    /// - Throws: Frame cap violations before submitting any partial output.
    private func send(_ frames: [RPCFrame], context: ChannelHandlerContext) throws {
        var bytes = Data()
        for frame in frames { bytes.append(try frame.encoded(maximumPayloadBytes: 4_096)) }
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(bytes: bytes)), promise: nil)
    }

    /// Records native EOF so client cleanup is verified without timing-dependent sleeps.
    /// - Parameter context: Closed native channel; inactivity continues down the pipeline.
    func channelInactive(context: ChannelHandlerContext) {
        observation.recordClosed()
        context.fireChannelInactive()
    }

    /// Records native pipeline errors and closes the test-owned accepted channel.
    /// - Parameters:
    ///   - context: Event-loop-confined accepted socket context.
    ///   - error: Native diagnostic deliberately discarded rather than logged.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        observation.markInvalidWire()
        context.close(promise: nil)
    }
}
#endif
