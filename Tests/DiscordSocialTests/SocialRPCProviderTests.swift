import DiscordCore
import DiscordRPC
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordSocial

/// Complete RPC peer with scripted correlated replies, not a replacement Social protocol.
private actor SocialRPCPeer: RPCConnection {
    private var incoming = [RPCFrame(opcode: .frame, payload: Data(#"{"cmd":"DISPATCH","evt":"READY","data":{"v":1}}"#.utf8))]
    private var waiter: CheckedContinuation<RPCFrame?, Never>?
    private var replies: [JSONValue]
    private let onRequest: @Sendable () -> Void
    private(set) var requests: [[String: JSONValue]] = []
    private(set) var closed = false

    /// Stores finite command-data replies; construction performs no simulated handshake or writes.
    /// - Parameters:
    ///   - replies: One data value per command; exhaustion intentionally leaves requests unanswered.
    ///   - onRequest: Nonblocking observer called after a command is recorded; default does nothing.
    init(replies: [JSONValue], onRequest: @escaping @Sendable () -> Void = {}) {
        self.replies = replies; self.onRequest = onRequest
    }

    /// Checks startup cancellation without claiming authentication or approved Discord access.
    /// - Parameters:
    ///   - applicationID: Synthetic registered application identifier.
    ///   - context: Checked startup clock/deadline.
    /// - Throws: Cancellation or deadline expiration.
    func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
    }

    /// Records and replies to one real runtime frame using its command and nonce.
    /// - Parameters:
    ///   - frame: Complete command frame; control frames do not consume reply scripts.
    ///   - context: Checked runtime write context.
    /// - Throws: Cancellation or malformed fixture JSON.
    func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard frame.opcode == .frame else { return }
        guard case .object(let object) = try JSONValue.parse(frame.payload) else { throw RPCFailure.invalidPayload }
        requests.append(object); onRequest()
        guard !replies.isEmpty else { return }
        let reply = RPCFrame(opcode: .frame, payload: try JSONValue.object([
            "cmd": object["cmd"]!, "nonce": object["nonce"]!, "data": replies.removeFirst()]).serialized())
        if let waiter { self.waiter = nil; waiter.resume(returning: reply) } else { incoming.append(reply) }
    }

    /// Returns READY or a scripted reply, otherwise waits until explicit client-owned cleanup.
    /// - Parameter context: Checked runtime read context.
    /// - Returns: Next frame, or nil after terminal close.
    /// - Throws: Cancellation or deadline before the read is admitted.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration {
        try context.check()
        if !incoming.isEmpty { return incoming.removeFirst() }
        if closed { return nil }
        return await withCheckedContinuation { waiter = $0 }
    }

    /// Closes the synthetic connection exactly once and unblocks the sole reader.
    func close() async { closed = true; waiter?.resume(returning: nil); waiter = nil }
}

/// Injects the deterministic peer without native IPC or a Discord desktop installation.
private struct SocialRPCConnector: RPCConnector {
    let peer: SocialRPCPeer
    /// Transfers the scripted peer after checking the explicit startup context.
    /// - Parameters:
    ///   - applicationID: Synthetic application identifier; no external connection occurs.
    ///   - context: Startup cancellation/deadline.
    /// - Returns: The exclusively owned synthetic peer.
    /// - Throws: Cancellation or expiration.
    func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws -> any RPCConnection where C.Duration == Duration {
        try context.check(); return peer
    }
}

/// Typed Social bridge coverage over actual bounded RPC request/correlation/lifecycle machinery.
@Suite(.timeLimit(.minutes(1))) struct SocialRPCProviderTests {
    /// Every bridge emits documented commands/arguments and decodes typed results without hidden I/O.
    /// Presence remains redacted and forced movement carries caller approval only when explicitly supplied.
    /// - Throws: Unexpected fixture or runtime failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func typedDesktopOperations() async throws {
        let object: JSONValue = .object([:])
        let peer = SocialRPCPeer(replies: [object, .null, .object(["channels": .array([.object(["id": .string("18446744073709551615")])])]),
            .object(["mute": .bool(false)]), .object(["mute": .bool(true)]),
            .object(["user_id": .string("2"), "volume": .number(try JSONNumber(rawValue: "200")), "mute": .bool(true)]),
            .null, .object(["id": .string("18446744073709551615")]), .null, object, object])
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: SocialRPCConnector(peer: peer))
        let provider = try SocialRPCProvider(client: client, processID: 123)
        #expect(await peer.requests.isEmpty)
        #expect(provider.presenceRequirements == .init(host: .desktopRPC, scopes: ["rpc", "rpc.activities.write"]))
        #expect(provider.voiceReadRequirements == .init(host: .desktopRPC, scopes: ["rpc", "rpc.voice.read"]))
        #expect(provider.voiceWriteRequirements == .init(host: .desktopRPC, scopes: ["rpc", "rpc.voice.write"]))
        #expect(provider.channelRequirements == .init(host: .desktopRPC, scopes: ["rpc"]))
        _ = try await client.connect(context: context)
        try await provider.updatePresence(.init(name: "Game", details: "Private details", state: "Playing"), context: context)
        #expect(try await provider.setPresence(.init(fields: ["name": .string("Game")]), context: context) == .null)
        #expect(try await provider.guildChannels(.init(rawValue: 1), context: context).channels.first?.id.rawValue == .max)
        #expect(try await provider.voiceSettings(context: context).mute == .value(false))
        #expect(try await provider.updateVoiceSettings(.init(fields: ["mute": .bool(true)]), context: context).mute == .value(true))
        #expect(try await provider.updateUserVoiceSettings(userID: .init(rawValue: 2), pan: .init(left: 0, right: 1),
            volume: 200, mute: true, context: context).volume == .value(200))
        #expect(try await provider.selectTextChannel(nil, context: context) == .null)
        if case .value(let channel) = try await provider.selectVoiceChannel(.init(rawValue: .max), force: true,
            userApprovedMove: true, context: context) { #expect(channel.id.rawValue == .max) } else { Issue.record("Expected selected channel") }
        #expect(try await provider.selectVoiceChannel(nil, context: context) == .null)
        #expect(try await provider.replyToJoinRequest(userID: .init(rawValue: 2), accept: true, context: context) == object)
        #expect(try await provider.replyToJoinRequest(userID: .init(rawValue: 2), accept: false, context: context) == object)
        let requests = await peer.requests
        #expect(requests.compactMap { $0["cmd"] } == ["SET_ACTIVITY", "SET_ACTIVITY", "GET_CHANNELS", "GET_VOICE_SETTINGS",
            "SET_VOICE_SETTINGS", "SET_USER_VOICE_SETTINGS", "SELECT_TEXT_CHANNEL", "SELECT_VOICE_CHANNEL",
            "SELECT_VOICE_CHANNEL", "SEND_ACTIVITY_JOIN_INVITE", "CLOSE_ACTIVITY_REQUEST"].map(JSONValue.string))
        #expect(requests[0]["args"] == .object(["pid": .number(try JSONNumber(rawValue: "123")),
            "activity": .object(["name": .string("Game"), "details": .string("Private details"), "state": .string("Playing")])]))
        #expect(requests[1]["args"] == .object(["pid": .number(try JSONNumber(rawValue: "123")), "activity": .object(["name": .string("Game")])]))
        #expect(requests[7]["args"] == .object(["channel_id": .string("18446744073709551615"), "force": .bool(true)]))
        #expect(requests[8]["args"] == .object(["channel_id": .null]))
        #expect(!(await peer.closed))
        await client.close()
        #expect(await peer.closed)
    }

    /// Invalid IDs/processes, unapproved force, expired contexts and malformed host replies fail explicitly.
    /// The wrapper adds no fallback retry, implicit connection or local consent inference.
    /// - Throws: Unexpected valid construction/startup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func validationAndFailureBoundaries() async throws {
        let peer = SocialRPCPeer(replies: [.array([])])
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: SocialRPCConnector(peer: peer))
        for pid in [0, -1, Int.min] {
            #expect(throws: RPCCatalogError.invalidArguments) { try SocialRPCProvider(client: client, processID: pid) }
        }
        let provider = try SocialRPCProvider(client: client, processID: 1)
        await #expect(throws: RPCFailure.notConnected) { try await provider.voiceSettings(context: context) }
        _ = try await client.connect(context: context)
        await #expect(throws: RPCCatalogError.invalidArguments) {
            try await provider.selectVoiceChannel(.init(rawValue: 1), force: true, context: context)
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await provider.voiceSettings(context: .init(clock: clock, deadline: clock.now))
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.voiceSettings(context: context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await peer.requests.isEmpty)
        await #expect(throws: RPCCatalogError.invalidPayload) { try await provider.voiceSettings(context: context) }
        #expect(await peer.requests.count == 1)
        await client.close()
    }

    /// Cancellation after a real command write releases its waiter without replay or shared-client closure.
    /// - Throws: Unexpected startup or barrier failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringRequest() async throws {
        let sent = TestBarrier(), clock = ManualClock()
        let peer = SocialRPCPeer(replies: [], onRequest: { sent.open() })
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: SocialRPCConnector(peer: peer))
        let provider = try SocialRPCProvider(client: client, processID: 1), context = TransportContext(clock: clock)
        _ = try await client.connect(context: context)
        let task = Task { try await provider.voiceSettings(context: context) }
        try await sent.wait(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await client.resourceCounts().pending == 0)
        #expect(await peer.requests.count == 1)
        #expect(!(await peer.closed))
        await client.close()
    }

    /// Nil neutral text fields remain absent in the outgoing activity rather than becoming null or defaults.
    /// - Throws: Unexpected valid construction, startup or request failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func minimalNeutralPresence() async throws {
        let peer = SocialRPCPeer(replies: [.null]), clock = ManualClock()
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: SocialRPCConnector(peer: peer))
        let provider = try SocialRPCProvider(client: client, processID: Int.max), context = TransportContext(clock: clock)
        _ = try await client.connect(context: context)
        try await provider.updatePresence(.init(name: "Game"), context: context)
        let requests = await peer.requests
        #expect(requests.count == 1)
        #expect(requests.first?["args"] == .object(["pid": .number(try JSONNumber(rawValue: String(Int.max))),
            "activity": .object(["name": .string("Game")])]))
        await client.close()
    }
}
