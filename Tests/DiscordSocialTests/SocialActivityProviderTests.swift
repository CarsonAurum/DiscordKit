import DiscordActivities
import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordSocial

/// Authenticated simulated host used only to exercise the real Activity request owner.
private actor SocialActivityPeer: ActivityTransport {
    private var incoming: [Data] = []
    private var waiter: CheckedContinuation<Data?, Never>?
    private var replies: [JSONValue]
    private let onRequest: @Sendable () -> Void
    private(set) var requests: [[String: JSONValue]] = []
    private(set) var closed = false

    /// Stores finite replies and an optional admission observer without starting any work.
    /// - Parameters:
    ///   - replies: One response-data object per request; exhaustion intentionally leaves requests unanswered.
    ///   - onRequest: Nonblocking barrier callback after recording an actual command; default does nothing.
    init(replies: [JSONValue], onRequest: @escaping @Sendable () -> Void = {}) {
        self.replies = replies; self.onRequest = onRequest
    }

    /// Records one command and echoes exact nonce/command correlation, or supplies synthetic READY.
    /// - Parameter data: Complete tuple emitted by the production Activity client.
    /// - Throws: Malformed fixture JSON or tuple serialization errors.
    func send(_ data: Data) async throws {
        guard case .array(let tuple) = try JSONValue.parse(data), tuple.count == 2 else { throw ActivityFailure.invalidFrame }
        if tuple[0] == .number(try JSONNumber(rawValue: "0")) {
            push(Data(#"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":"production"}}}]"#.utf8))
        } else if tuple[0] == .number(try JSONNumber(rawValue: "1")), case .object(let object) = tuple[1] {
            requests.append(object); onRequest()
            guard !replies.isEmpty else { return }
            push(try JSONValue.array([.number(JSONNumber(rawValue: "1")), .object([
                "cmd": object["cmd"]!, "nonce": object["nonce"]!, "evt": .null, "data": replies.removeFirst()])]).serialized())
        }
    }

    /// Reads the next synthetic trusted-host tuple or waits for an explicit host reply/cleanup.
    /// - Returns: Complete tuple bytes, or nil after terminal close.
    func receive() async throws -> Data? {
        if !incoming.isEmpty { return incoming.removeFirst() }
        if closed { return nil }
        return await withCheckedContinuation { waiter = $0 }
    }

    /// Delivers a tuple to the sole reader or the finite fixture queue.
    /// - Parameter data: Already bounded fixture tuple bytes.
    private func push(_ data: Data) {
        if let waiter { self.waiter = nil; waiter.resume(returning: data) } else { incoming.append(data) }
    }

    /// Disposes the simulated host and unblocks the sole reader; repeated calls are harmless.
    func close() async { closed = true; waiter?.resume(returning: nil); waiter = nil }
}

/// Typed Activity provider tests cover host-specific semantics without claiming browser or mobile qualification.
@Suite(.timeLimit(.minutes(1))) struct SocialActivityProviderTests {
    /// All commands use the current public names and schemas, with host-derived immutable application names.
    /// Nullable clearing is specific to Activity while neutral presence omits absent text fields.
    /// - Throws: Unexpected fixture, startup, descriptor or decoding failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func typedHostOperations() async throws {
        let presence: JSONValue = .object(["name": .string("Game"), "type": .number(try JSONNumber(rawValue: "0"))])
        let peer = SocialActivityPeer(replies: [presence, presence, presence,
            .object(["relationships": .array([])]), .object(["participants": .array([])]),
            .null, .object(["opened": .bool(false)])])
        let clock = ManualClock()
        let client = try Self.client(peer: peer, clock: clock)
        let provider = try SocialActivityProvider(client: client, applicationName: "Game")
        let context = TransportContext(clock: clock)
        #expect(await peer.requests.isEmpty)
        #expect(provider.presenceRequirements == .init(host: .activityHost, scopes: ["rpc.activities.write"]))
        #expect(provider.relationshipRequirements == .init(host: .activityHost, scopes: ["relationships.read"]))
        #expect(provider.hostRequirements == .init(host: .activityHost))
        try await client.start()
        try await provider.updatePresence(.init(name: "Game", details: "Private details", state: "Playing"), context: context)
        try await provider.updatePresence(.init(name: "Game"), context: context)
        #expect(try await provider.setPresence(.null, context: context).name == "Game")
        #expect(try await provider.relationships(context: context).relationships.isEmpty)
        #expect(try await provider.participants(context: context).participants.isEmpty)
        try await provider.openInviteDialog(context: context)
        #expect(try await provider.openExternalLink("https://example.com/", context: context).opened == .value(false))
        let requests = await peer.requests
        #expect(requests.compactMap { $0["cmd"] } == ["SET_ACTIVITY", "SET_ACTIVITY", "SET_ACTIVITY", "GET_RELATIONSHIPS",
            "GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS", "OPEN_INVITE_DIALOG", "OPEN_EXTERNAL_LINK"].map(JSONValue.string))
        #expect(requests[0]["args"] == .object(["activity": .object(["details": .string("Private details"), "state": .string("Playing")])]))
        #expect(requests[1]["args"] == .object(["activity": .object([:])]))
        #expect(requests[2]["args"] == .object(["activity": .null]))
        #expect(requests[3]["args"] == .object([:]))
        #expect(requests[6]["args"] == .object(["url": .string("https://example.com/")]))
        #expect(!(await peer.closed))
        await client.close()
        #expect(await peer.closed)
    }

    /// Invalid configured names and unsupported requested renames fail before any host command.
    /// Expiration/cancellation preserve bounded ownership; malformed host data never becomes a valid snapshot.
    /// - Throws: Unexpected fixture construction or startup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nameAndFailureBoundaries() async throws {
        let peer = SocialActivityPeer(replies: [.object(["relationships": .null])])
        let clock = ManualClock()
        let client = try Self.client(peer: peer, clock: clock)
        for name in ["", "\u{0}", "\n", String(repeating: "x", count: 129), String(repeating: "é", count: 65)] {
            #expect(throws: SocialActivityProviderError.invalidApplicationName) {
                try SocialActivityProvider(client: client, applicationName: name)
            }
        }
        let provider = try SocialActivityProvider(client: client, applicationName: String(repeating: "é", count: 64))
        await #expect(throws: SocialActivityProviderError.applicationNameMismatch) {
            try await provider.updatePresence(.init(name: "Other"), context: .init(clock: clock))
        }
        try await client.start()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await provider.relationships(context: .init(clock: clock, deadline: clock.now))
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.relationships(context: .init(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await peer.requests.isEmpty)
        await #expect(throws: ActivityCatalogError.invalidPayload) {
            try await provider.relationships(context: .init(clock: clock))
        }
        #expect(await peer.requests.count == 1)
        await client.close()
        await #expect(throws: ActivityFailure.closed) { try await provider.participants(context: .init(clock: clock)) }
    }

    /// Cancellation after command admission releases the pending correlation without closing the shared host.
    /// An unanswered command is never replayed and caller-owned close remains explicit.
    /// - Throws: Unexpected fixture, startup or barrier failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringRequest() async throws {
        let sent = TestBarrier()
        let observedPeer = SocialActivityPeer(replies: [], onRequest: { sent.open() })
        let clock = ManualClock()
        let client = try Self.client(peer: observedPeer, clock: clock)
        let provider = try SocialActivityProvider(client: client, applicationName: "Game")
        try await client.start()
        let task = Task { try await provider.relationships(context: .init(clock: clock)) }
        try await sent.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await client.snapshot().pending == 0)
        #expect(await observedPeer.requests.count == 1)
        #expect(!(await observedPeer.closed))
        await client.close()
    }

    /// The caller's monotonic deadline covers an admitted unanswered request and releases its waiter.
    /// Virtual time advances only after a real command write, with no timing-dependent sleeps.
    /// - Throws: Unexpected fixture, startup, barrier or virtual-clock failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deadlineDuringRequest() async throws {
        let sent = TestBarrier(), clock = ManualClock()
        let peer = SocialActivityPeer(replies: [], onRequest: { sent.open() })
        let client = try Self.client(peer: peer, clock: clock)
        let provider = try SocialActivityProvider(client: client, applicationName: "Game")
        try await client.start()
        let deadline = clock.now.advanced(by: .seconds(1))
        let task = Task { try await provider.relationships(context: .init(clock: clock, deadline: deadline)) }
        try await sent.wait()
        try clock.advance(by: .seconds(2))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        #expect(await client.snapshot().pending == 0)
        #expect(await peer.requests.count == 1)
        #expect(!(await peer.closed))
        #expect(clock.pendingSleepCount == 0)
        await client.close()
    }

    /// Constructs a genuine Activity client over a deterministic trusted-host adapter.
    /// - Parameters:
    ///   - peer: Simulated already authenticated host-message source; not a real Discord browser.
    ///   - clock: Shared monotonic operation clock.
    /// - Returns: Inert Activity client requiring explicit start and close.
    /// - Throws: Invalid local URL/host or client configuration.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func client(peer: SocialActivityPeer, clock: ManualClock) throws -> ActivityClient<ManualClock> {
        let host = try ActivityHostParameters(url: #require(URL(string: "https://1.discordsays.com/?frame_id=f&instance_id=i&platform=mobile")))
        return try ActivityClient(applicationID: .init(rawValue: 1), host: host, transport: peer, clock: clock)
    }
}
