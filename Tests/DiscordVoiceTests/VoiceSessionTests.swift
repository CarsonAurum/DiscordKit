import DiscordLogging
import DiscordCore
import DiscordMedia
import DiscordTestSupport
import DiscordTransport
import Foundation
import Synchronization
import Testing
@testable import DiscordVoice

/// Creates a complete synthetic server JSON frame without using a real Discord session.
/// - Parameters:
///   - opcode: Documented server opcode.
///   - data: Exact bounded body.
///   - sequence: Optional fixed-width server sequence.
/// - Returns: A complete WebSocket message ready for the public parser.
/// - Throws: Bounded fixture serialization failures.
private func sessionServerFrame(_ opcode: UInt8, _ data: JSONValue, sequence: UInt16? = nil) throws -> WebSocketMessage {
    var object: [String: JSONValue] = ["op": voiceControlNumber(opcode), "d": data]
    if let sequence { object["seq"] = voiceControlNumber(sequence) }
    return .text(String(decoding: try JSONValue.object(object).serialized(), as: UTF8.self))
}

/// Cancellation-cooperative blocking peer with explicit read/send observation gates.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor SessionTestSocket: WebSocketSessionConnection {
    private var incoming: [WebSocketMessage]
    private var outgoing: [VoiceGatewayFrame] = []
    private var waiter: CheckedContinuation<WebSocketMessage?, any Error>?
    private var reads = 0
    private var readGates: [Int: TestBarrier] = [:]
    private var sendGates: [UInt8: TestBarrier] = [:]
    private var closed = false
    private var code: Int?
    private var closes = 0
    private var reconnectCloses = 0
    private var receiveFailure: TransportFailure?
    private let acknowledge: Bool

    /// Stores a finite server script without reading or creating background work.
    /// - Parameters:
    ///   - incoming: Initial complete messages in wire order.
    ///   - acknowledge: Whether to echo exact heartbeat nonces automatically.
    init(_ incoming: [WebSocketMessage], acknowledge: Bool = true) {
        self.incoming = incoming; self.acknowledge = acknowledge
    }

    /// Records one bounded client frame and optionally queues a heartbeat ACK.
    /// - Parameters:
    ///   - message: Complete outgoing JSON/binary command.
    ///   - context: Caller clock/deadline checked before admission.
    /// - Throws: Cancellation, expiry, closure or invalid fixture frame errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        let frame = try VoiceGatewayFrame(message, direction: .clientToServer)
        outgoing.append(frame); sendGates.removeValue(forKey: frame.opcode)?.open()
        if acknowledge, frame.opcode == 3, case .json(.object(let body)) = frame.payload, let nonce = body["t"] {
            enqueue(try sessionServerFrame(6, .object(["t": nonce])))
        }
    }

    /// Runs one cancellation-cooperative pull under the exact injected deadline.
    /// - Parameter context: Caller clock/deadline for this read.
    /// - Returns: Scripted complete message, or nil after close.
    /// - Throws: Cancellation/deadline or concurrent-read errors.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try await context.run { try await self.read() }
    }

    /// Performs the single-consumer suspended portion of a test read.
    /// - Returns: Next complete message or nil after orderly close.
    /// - Throws: Cancellation or overlap; cancellation releases the retained continuation.
    private func read() async throws -> WebSocketMessage? {
        try Task.checkCancellation()
        reads += 1; readGates.removeValue(forKey: reads)?.open()
        if !incoming.isEmpty { return incoming.removeFirst() }
        if let receiveFailure { self.receiveFailure = nil; throw receiveFailure }
        if closed { return nil }
        guard waiter == nil else { throw TransportFailure.concurrentRead }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waiter = continuation
            }
        } onCancel: { Task { await self.cancelRead() } }
    }

    /// Cancels the sole pending read without changing peer-session close evidence.
    private func cancelRead() {
        let waiter = waiter; self.waiter = nil; waiter?.resume(throwing: CancellationError())
    }

    /// Delivers one future complete server message without an unbounded producer task.
    /// - Parameter message: Synthetic message already bounded by the fixture.
    func enqueue(_ message: WebSocketMessage) {
        if let waiter { self.waiter = nil; waiter.resume(returning: message) }
        else { incoming.append(message) }
    }

    /// Simulates a peer close and wakes the currently pending read with EOF.
    /// - Parameter code: Numeric close evidence retained for the session's retry policy.
    func disconnect(code: Int) {
        self.code = code; closed = true
        let waiter = waiter; self.waiter = nil; waiter?.resume(returning: nil)
    }

    /// Fails the active or next read with explicit adapter validation/loss evidence.
    /// - Parameter error: Bounded sanitized transport error whose retry classification is tested.
    func failReceive(_ error: TransportFailure) {
        if let waiter { self.waiter = nil; waiter.resume(throwing: error) }
        else { receiveFailure = error }
    }

    /// Closes idempotently and wakes a pending read without a cancellation requirement.
    func close() async {
        if !closed { closes += 1 }; closed = true
        let waiter = waiter; self.waiter = nil; waiter?.resume(returning: nil)
    }

    /// Records resumable cleanup separately from terminal closure.
    func closeForReconnect() async { reconnectCloses += 1; await close() }

    /// Reports only the numeric simulated peer close code.
    /// - Returns: Last configured close code, or nil for no peer close evidence.
    func peerCloseCode() async -> Int? { code }

    /// Waits until a particular receive call begins, proving previous controls completed.
    /// - Parameter count: Positive exact read count in this finite script.
    /// - Throws: Test cancellation.
    func waitForRead(_ count: Int) async throws {
        if reads >= count { return }
        let gate = readGates[count] ?? TestBarrier(); readGates[count] = gate
        try await gate.wait()
    }

    /// Waits until a particular outgoing opcode is observed.
    /// - Parameter opcode: Client command expected by this test.
    /// - Throws: Test cancellation.
    func waitForSend(_ opcode: UInt8) async throws {
        if outgoing.contains(where: { $0.opcode == opcode }) { return }
        let gate = sendGates[opcode] ?? TestBarrier(); sendGates[opcode] = gate
        try await gate.wait()
    }

    /// Returns immutable command/cleanup evidence without affecting transport state.
    /// - Returns: Sent frames, physical terminal closes, and resumable-close calls.
    func recorded() -> ([VoiceGatewayFrame], Int, Int) { (outgoing, closes, reconnectCloses) }
}

/// Finite socket factory recording exact secure upgrade requests.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor SessionTestConnector: WebSocketTransport {
    private var sockets: [SessionTestSocket]
    private var requests: [HTTPRequest] = []

    /// Retains a bounded sequence of already-inert fake connections.
    /// - Parameter sockets: One owner per allowed connection attempt.
    init(_ sockets: [SessionTestSocket]) { self.sockets = sockets }

    /// Transfers one fake connection while retaining its exact upgrade request.
    /// - Parameters:
    ///   - request: Session-generated secure v8 URL and headers.
    ///   - context: Clock and inclusive connect deadline.
    /// - Returns: Next fake socket.
    /// - Throws: Cancellation, deadline or exhausted-script errors.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        guard !sockets.isEmpty else { throw TransportFailure.scriptExhausted }
        requests.append(request)
        return sockets.removeFirst()
    }

    /// Reports connection requests in exact attempt order.
    /// - Returns: Immutable requests; all tokens remain in later redacted Identify frames.
    func recorded() -> [HTTPRequest] { requests }
}

/// Blocking discovery/media peer keeping the UDP receive child alive until explicit stop.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor SessionTestDatagram: DatagramTransport {
    nonisolated let mediaReadStarted = TestBarrier()
    private var initial: Datagram?
    private var sent: [Datagram] = []
    private var waiter: CheckedContinuation<Datagram?, any Error>?
    private var closed = false
    private var cancelledReads = 0

    /// Stores exactly one discovery response with no socket or background task.
    /// - Parameter initial: Complete response from the expected or deliberately spoofed peer.
    init(_ initial: Datagram) { self.initial = initial }

    /// Records complete sends while preserving their datagram boundaries.
    /// - Parameters:
    ///   - datagram: Once-only complete UDP output.
    ///   - context: Injected deadline/cancellation checked before admission.
    /// - Throws: Cancellation, deadline or explicit closure.
    func sendDatagram<C: Clock>(_ datagram: Datagram, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check(); guard !closed else { throw TransportFailure.closed }; sent.append(datagram)
    }

    /// Delivers discovery once, then blocks cancellation-cooperatively for media/close.
    /// - Parameter context: Injected deadline/cancellation for one receive.
    /// - Returns: Discovery response, or nil after close.
    /// - Throws: Cancellation, expiry or concurrent-receive error.
    func receiveDatagram<C: Clock>(context: TransportContext<C>) async throws -> Datagram? where C.Duration == Duration {
        try await context.run { try await self.read() }
    }

    /// Owns the single pending UDP continuation and releases it on cancellation.
    /// - Returns: Initial discovery response or nil after close.
    /// - Throws: Cancellation or overlapping read.
    private func read() async throws -> Datagram? {
        try Task.checkCancellation()
        if let initial { self.initial = nil; return initial }
        if closed { return nil }
        guard waiter == nil else { throw TransportFailure.concurrentRead }
        mediaReadStarted.open()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waiter = continuation
            }
        } onCancel: { Task { await self.cancelRead() } }
    }

    /// Models owned native adapters by closing the UDP resource when its active read is cancelled.
    /// A WebSocket resume must therefore preserve this reader for the full session lifetime.
    private func cancelRead() {
        closed = true; cancelledReads += 1
        let waiter = waiter; self.waiter = nil; waiter?.resume(throwing: CancellationError())
    }

    /// Closes idempotently and wakes a pending media receive with EOF.
    func close() async {
        closed = true; let waiter = waiter; self.waiter = nil; waiter?.resume(returning: nil)
    }

    /// Reports complete outgoing datagrams in admission order.
    /// - Returns: Discovery followed by any paced encoded media.
    func sentDatagrams() -> [Datagram] { sent }

    /// Returns native-style cancellation/closure evidence without changing receive ownership.
    /// - Returns: Resource closure flag and number of cancelled pending-read operations.
    func lifecycle() -> (closed: Bool, cancelledReads: Int) { (closed, cancelledReads) }
}

/// Synthetic exact-identity authorization for control tests; it provides no real DAVE crypto.
private struct SessionTestReadiness: VoiceE2EEReadiness {
    let identity: VoiceConnectionIdentity

    /// Verifies the reducer receives its exact fixture identity and nonzero version one.
    /// - Parameters:
    ///   - protocolVersion: Negotiated integer version.
    ///   - identity: Entire current session identity.
    /// - Throws: `e2eeUnavailable` on any mismatch.
    func validateSession(protocolVersion: UInt16, identity: VoiceConnectionIdentity) throws {
        guard protocolVersion == 1, identity == self.identity else { throw VoiceControlFailure.e2eeUnavailable }
    }
}

/// Fake authenticated backend used only to isolate network ownership/control behavior.
private actor SessionTestE2EE: VoiceSessionE2EE {
    private let identity: VoiceConnectionIdentity
    private var closed = false
    private var controls: [UInt8] = []
    private var bindings: [UInt32: UserID] = [:]
    private let beforeBind: (@Sendable (UserID) async -> Void)?
    private var pendingBinding: Task<Void, Never>?
    private let beforeRemoval: (@Sendable (UserID) async -> Void)?
    private var pendingRemoval: Task<Void, Never>?

    /// Creates an inert exact-identity fixture without key material or network access.
    /// - Parameters:
    ///   - identity: Expected whole identity for authorization checks.
    ///   - beforeBind: Optional admitted-binding suspension hook, default nil. Closure owns
    ///     no keys; cleanup waits for its cancellation-independent task before returning.
    ///   - beforeRemoval: Optional admitted-removal suspension hook with the same cleanup
    ///     ownership, default nil; used to test pre-negotiation stop ordering.
    init(_ identity: VoiceConnectionIdentity, beforeBind: (@Sendable (UserID) async -> Void)? = nil,
         beforeRemoval: (@Sendable (UserID) async -> Void)? = nil) {
        self.identity = identity; self.beforeBind = beforeBind; self.beforeRemoval = beforeRemoval
    }

    /// Accepts only the nonzero fixture version without pretending to establish real MLS.
    /// - Parameter protocolVersion: Version from Session Description.
    /// - Returns: No outbound fixture messages.
    /// - Throws: Closed or unsupported-version errors.
    func start(protocolVersion: UInt16) async throws -> [VoiceGatewayFrame] {
        guard !closed, protocolVersion == 1 else { throw VoiceControlFailure.e2eeUnavailable }; return []
    }

    /// Records authenticated membership/control delivery without interpreting MLS.
    /// - Parameters:
    ///   - frame: Synthetic server control.
    ///   - now: Injected monotonic seconds, unused by this noncryptographic fake.
    /// - Returns: No outbound fixture messages.
    /// - Throws: Closure after explicit cleanup.
    func receive(_ frame: VoiceGatewayFrame, now: TimeInterval) async throws -> [VoiceGatewayFrame] {
        guard !closed else { throw VoiceControlFailure.closed }; controls.append(frame.opcode); return []
    }

    /// Authorizes the copied reducer through the existing whole-identity test verifier.
    /// - Parameter state: Suspended fixture reducer.
    /// - Returns: Ready fixture reducer, preserving its other fields.
    /// - Throws: Closure or exact identity/version mismatch.
    func authorizeGateway(_ state: VoiceGatewaySessionState) async throws -> VoiceGatewaySessionState {
        guard !closed else { throw VoiceControlFailure.closed }
        var result = state; try result.authorizeMedia(using: SessionTestReadiness(identity: identity)); return result
    }

    /// Records trusted SSRC association from synthetic signaling after its optional gate.
    /// - Parameters:
    ///   - ssrc: Negotiated source.
    ///   - userID: Authenticated fixture account.
    /// - Throws: Closed fixture state at admission. Already admitted work may return success
    ///   after close begins, but it never restores the fixture's removed source metadata.
    func bindSSRC(_ ssrc: UInt32, userID: UserID) async throws {
        guard !closed else { throw VoiceControlFailure.closed }
        if let beforeBind {
            let task = Task { await beforeBind(userID) }
            pendingBinding = task
            await task.value
            pendingBinding = nil
        }
        if !closed { bindings[ssrc] = userID }
    }

    /// Removes departed bindings after an optional cancellation-independent admitted hook.
    /// - Parameter userID: Departing account.
    func removeParticipant(_ userID: UserID) async {
        if let beforeRemoval {
            let task = Task { await beforeRemoval(userID) }
            pendingRemoval = task
            await task.value
            pendingRemoval = nil
        }
        bindings = bindings.filter { $0.value != userID }
    }

    /// Returns a conspicuous fixture-only prefix for packet-transport tests.
    /// - Parameters:
    ///   - opus: Complete validated ordinary Opus packet.
    ///   - ssrc: Trusted source identifier.
    /// - Returns: Prefixed fixture payload; this is deliberately not cryptographic evidence.
    /// - Throws: Closed or missing-binding state.
    func seal(_ opus: Data, ssrc: UInt32) async throws -> Data {
        guard !closed, bindings[ssrc] != nil else { throw VoiceControlFailure.e2eeUnavailable }
        return Data([0xad]) + opus
    }

    /// Removes only the explicit fixture prefix after checking the trusted source.
    /// - Parameters:
    ///   - frame: Synthetic prefixed payload.
    ///   - ssrc: Trusted source identifier.
    /// - Returns: Original fixture Opus packet.
    /// - Throws: Closed, unknown-source, or malformed-fixture errors.
    func open(_ frame: Data, ssrc: UInt32) async throws -> Data {
        guard !closed, bindings[ssrc] != nil, frame.first == 0xad else { throw VoiceControlFailure.e2eeUnavailable }
        return Data(frame.dropFirst())
    }

    /// Permanently closes the fixture, clears metadata and joins admitted binding/removal hooks.
    func close() async {
        closed = true; bindings.removeAll()
        await pendingBinding?.value; await pendingRemoval?.value
    }

    /// Reports bounded cleanup and membership-delivery evidence.
    /// - Returns: Closed state and processed server opcode list.
    func recorded() -> (Bool, [UInt8]) { (closed, controls) }
}

/// Manual-clock wrapper observing exact heartbeat/retry sleep admission without polling.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class SessionTestClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant
    let base = ManualClock()
    let firstHeartbeat = TestBarrier()
    let secondHeartbeat = TestBarrier()
    let retry = TestBarrier()
    private let heartbeatSleeps = Mutex(0)
    private let mediaSleeps = Mutex(0)
    private let mediaSleepGates = (0..<5).map { _ in TestBarrier() }

    /// Returns the underlying explicitly advanced monotonic instant.
    var now: Instant { base.now }
    /// Reports the same nanosecond resolution as the underlying clock.
    var minimumResolution: Duration { base.minimumResolution }

    /// Observes known fixture durations before suspending on the cancellation-aware clock.
    /// - Parameters:
    ///   - deadline: Exact clock-local target instant.
    ///   - tolerance: Forwarded tolerance; the underlying clock ignores early wakeups.
    /// - Throws: Cooperative cancellation or underlying test capacity failures.
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let duration = now.duration(to: deadline)
        if duration == .seconds(1) {
            let count = heartbeatSleeps.withLock { count in count += 1; return count }
            if count == 1 { firstHeartbeat.open() }; if count == 2 { secondHeartbeat.open() }
        }
        if duration == .milliseconds(50) { retry.open() }
        if duration > .zero, duration <= .milliseconds(20) {
            let count = mediaSleeps.withLock { count in count += 1; return count }
            if count <= mediaSleepGates.count { mediaSleepGates[count - 1].open() }
        }
        try await base.sleep(until: deadline, tolerance: tolerance)
    }

    /// Waits for one exact media pacing sleep to start before advancing virtual time.
    /// - Parameter count: One-based termination-silence wait in `1...5`.
    /// - Throws: Invalid test configuration or cooperative cancellation.
    func waitForMediaSleep(_ count: Int) async throws {
        guard (1...mediaSleepGates.count).contains(count) else { throw VoiceControlFailure.invalidConfiguration }
        try await mediaSleepGates[count - 1].wait()
    }
}

/// Sendable finite source simulating a device provider that reports an unplug failure.
private struct SessionFailingPCMSource: AsyncSequence, Sendable {
    typealias Element = PCMBuffer

    /// A value iterator with no retained device or non-Sendable platform state.
    struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        /// Reports the synthetic source failure at its first requested frame.
        /// - Returns: Never returns a frame; no device data or resource is owned.
        /// - Throws: `disconnected`, representing the injected source-provider error.
        mutating func next() async throws -> PCMBuffer? { throw VoiceManagerFailure.disconnected }
    }

    /// Creates an inert iterator without starting a producer or device.
    /// - Returns: A new independent failure iterator.
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

/// Observes playback entering a cancellation-aware empty stream without timing-dependent polling.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct SessionWaitingPCMSource: AsyncSequence, Sendable {
    typealias Element = PCMBuffer
    let stream: PCMFrameStream
    let readStarted: TestBarrier

    /// Retains one bounded stream iterator and an explicit observation gate.
    struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        var iterator: PCMFrameStream.AsyncIterator
        let readStarted: TestBarrier

        /// Marks source admission, then parks until stream input, finish, or task cancellation.
        /// - Returns: Next complete frame, or nil at ordinary stream completion.
        /// - Throws: Stream admission/cancellation failures; cancellation releases its reader.
        mutating func next() async throws -> PCMBuffer? {
            readStarted.open()
            return try await iterator.next()
        }
    }

    /// Creates a single-consumer iterator without starting work or reserving a reader.
    /// - Returns: Inert Sendable iterator sharing the bounded source and observation gate.
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator(), readStarted: readStarted)
    }
}

/// Exercises actual session supervision over deterministic complete-message/socket peers.
@Suite("Supervised Voice v8 session")
struct VoiceSessionTests {
    /// Constructs one bounded synthetic credential tuple, never a real account credential.
    /// - Parameter endpoint: Secure-upgrade authority to validate, default the Discord fixture host.
    /// - Returns: Complete guild/account/channel/session identity and ephemeral fake token.
    private func credentials(endpoint: String = "voice.discord.media:443") -> VoiceConnectionCredentials {
        VoiceConnectionCredentials(guildID: GuildID(rawValue: 1), userID: UserID(rawValue: 2),
            channelID: ChannelID(rawValue: 3), sessionID: "synthetic-session", token: "synthetic-token",
            endpoint: endpoint, generation: 7)
    }

    /// Builds normal Hello/Ready/Description controls with an intentionally false READY interval.
    /// - Returns: Complete server script; only HELLO's one-second interval is authoritative.
    /// - Throws: Fixture serialization failures.
    private func initialFrames() throws -> [WebSocketMessage] {
        [try sessionServerFrame(8, .object(["heartbeat_interval": voiceControlNumber(1_000)])),
         try sessionServerFrame(2, .object(["ssrc": voiceControlNumber(42), "ip": .string("127.0.0.1"),
            "port": voiceControlNumber(50_000), "heartbeat_interval": voiceControlNumber(1),
            "modes": .array([.string("aead_xchacha20_poly1305_rtpsize")])]), sequence: 65_535),
         try sessionServerFrame(4, .object(["mode": .string("aead_xchacha20_poly1305_rtpsize"),
            "secret_key": .array((0..<32).map(voiceControlNumber)), "dave_protocol_version": voiceControlNumber(1)]), sequence: 0)]
    }

    /// Builds the exact fixed-width discovery response expected by Ready's SSRC and peer.
    /// - Parameter wrongPeer: Whether to spoof the source address for peer-validation tests.
    /// - Returns: Synthetic response advertising a nonzero external loopback port.
    private func discovery(wrongPeer: Bool = false) -> Datagram {
        var bytes = [UInt8](VoiceDiscovery.request(ssrc: 42)); bytes[1] = 2
        for (index, byte) in "127.0.0.1".utf8.enumerated() { bytes[8 + index] = byte }
        bytes[72] = 0xc3; bytes[73] = 0x50
        return Datagram(bytes: Data(bytes), peer: DatagramAddress(host: wrongPeer ? "127.0.0.2" : "127.0.0.1", port: 50_000))
    }

    /// Validates current close-code policy and endpoint/configuration rejection before I/O.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func endpointConfigurationAndClosePolicy() async throws {
        for code in [1006, 1011, 1012, 1013, 4000, 4015] { #expect(VoiceSession<ManualClock>.canResume(closeCode: code)) }
        for code in [1000, 4004, 4006, 4009, 4014, 4017, 4020, 4021, 4022] {
            #expect(!VoiceSession<ManualClock>.canResume(closeCode: code))
        }
        for count in [-1, 31] {
            #expect(throws: VoiceControlFailure.invalidConfiguration) { try VoiceSessionConfiguration(maximumReconnectAttempts: count) }
        }
        for bytes in [0, 67_108_865] {
            #expect(throws: VoiceControlFailure.invalidConfiguration) { try VoiceSessionConfiguration(maximumMediaBytes: bytes) }
        }
        #expect(try VoiceSessionConfiguration(maximumMediaBytes: 67_108_864).maximumMediaBytes == 67_108_864)
        for timeout in [Duration.zero, .seconds(-1), .seconds(86_401)] {
            #expect(throws: VoiceControlFailure.invalidConfiguration) { try VoiceSessionConfiguration(handshakeTimeout: timeout) }
            #expect(throws: VoiceControlFailure.invalidConfiguration) { try VoiceSessionConfiguration(operationTimeout: timeout) }
            #expect(throws: VoiceControlFailure.invalidConfiguration) { try VoiceSessionConfiguration(retryDelay: timeout) }
        }
        let longest = try VoiceSessionConfiguration(handshakeTimeout: .seconds(86_400),
            operationTimeout: .seconds(86_400), retryDelay: .seconds(86_400))
        #expect(longest.handshakeTimeout == .seconds(86_400) && longest.operationTimeout == .seconds(86_400)
            && longest.retryDelay == .seconds(86_400))
        for endpoint in ["", "wss://voice.discord.media", "voice.discord.media/path", "user@voice.discord.media",
                         "voice.discord.media?x=1", "voice.discord.media:0", "voice.discord.media:65536", "voice discord.media"] {
            let tuple = credentials(endpoint: endpoint), backend = SessionTestE2EE(tuple.identity)
            let connector = SessionTestConnector([])
            #expect(throws: VoiceSessionFailure.invalidEndpoint) {
                try VoiceSession(credentials: tuple, webSocket: connector,
                    makeDatagram: { _ in throw TransportFailure.scriptExhausted }, e2ee: backend, clock: ManualClock())
            }
            #expect(await connector.recorded().isEmpty)
        }
    }

    /// Handshake performs exact discovery, preserves explicit v8, authorizes media and stops promptly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func handshakeSpeakingAndDirectStop() async throws {
        let tuple = credentials(), socket = SessionTestSocket(try initialFrames()), connector = SessionTestConnector([socket])
        let backend = SessionTestE2EE(tuple.identity), clock = SessionTestClock()
        let udp = SessionTestDatagram(discovery())
        let owner = try VoiceSession(credentials: tuple, webSocket: connector, makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        #expect(await owner.snapshot().phase == .awaitingHello)
        #expect(await connector.recorded().isEmpty)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        #expect(await owner.snapshot().phase == .ready)
        #expect(await owner.mediaPipeline() != nil)
        #expect(await connector.recorded().first?.url.absoluteString == "wss://voice.discord.media:443/?v=8")
        try await owner.setSpeaking(true); try await owner.setSpeaking(false)
        let frames = await socket.recorded().0
        #expect(frames.map(\.opcode) == [0, 1, 5, 5, 5])
        #expect(await udp.sentDatagrams().first?.bytes == VoiceDiscovery.request(ssrc: 42))
        await owner.stop()
        try await run.value
        let snapshot = await owner.snapshot()
        #expect(snapshot.phase == .closed && snapshot.isRunning == false)
        #expect(await backend.recorded().0)
        #expect(clock.base.pendingSleepCount == 0)
    }

    /// Missing ACK exhausts the explicit retry budget; READY's bogus interval never drives timers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func missedHeartbeatACKTerminates() async throws {
        let tuple = credentials(), socket = SessionTestSocket(try initialFrames(), acknowledge: false)
        let clock = SessionTestClock(), backend = SessionTestE2EE(tuple.identity)
        let udp = SessionTestDatagram(discovery())
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock,
            configuration: VoiceSessionConfiguration(maximumReconnectAttempts: 0))
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4); try await clock.firstHeartbeat.wait()
        try clock.base.advance(by: .seconds(1))
        try await socket.waitForSend(3); try await clock.secondHeartbeat.wait()
        try clock.base.advance(by: .seconds(1))
        await #expect(throws: VoiceSessionFailure.retryExhausted) { try await run.value }
        #expect(await owner.snapshot().phase == .closed)
        #expect(clock.base.pendingSleepCount == 0)
    }

    /// Resumable service loss preserves the native-style UDP reader, pipeline and both RTP/AEAD counters.
    /// A fake that closes on receive cancellation catches accidental per-WebSocket UDP supervision.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bufferedResumeKeepsMatchedIdentity() async throws {
        let tuple = credentials(), first = SessionTestSocket(try initialFrames())
        let second = SessionTestSocket([try sessionServerFrame(8, .object(["heartbeat_interval": voiceControlNumber(1_000)])),
                                       try sessionServerFrame(9, .null)])
        let connector = SessionTestConnector([first, second]), clock = SessionTestClock()
        let backend = SessionTestE2EE(tuple.identity), udp = SessionTestDatagram(discovery())
        let owner = try VoiceSession(credentials: tuple, webSocket: connector, makeDatagram: { _ in udp },
            e2ee: backend, clock: clock, configuration: VoiceSessionConfiguration(retryDelay: .milliseconds(50)))
        let run = Task { try await owner.run() }
        try await first.waitForRead(4)
        try await udp.mediaReadStarted.wait()
        let originalMedia = try #require(await owner.mediaPipeline())
        try await originalMedia.sendOpus(Data([0xf8, 0xff, 0xfe]), context: TransportContext(clock: clock))
        await first.disconnect(code: 4015)
        try await clock.retry.wait(); try clock.base.advance(by: .milliseconds(50))
        try await second.waitForRead(3)
        let snapshot = await owner.snapshot()
        #expect(snapshot.phase == .ready && snapshot.reconnectAttempts == 1)
        let resume = try #require(await second.recorded().0.first)
        #expect(resume.opcode == 7)
        guard case .json(.object(let body)) = resume.payload else { Issue.record("Expected JSON Resume"); return }
        #expect(body["seq_ack"] == voiceControlNumber(0) && body["session_id"] == .string("synthetic-session"))
        #expect(await first.recorded().2 == 1)
        let resumedMedia = try #require(await owner.mediaPipeline())
        #expect(resumedMedia === originalMedia)
        #expect(await udp.lifecycle().closed == false)
        #expect(await udp.lifecycle().cancelledReads == 0)
        try await resumedMedia.sendOpus(Data([0xf8, 0xff, 0xfe]), context: TransportContext(clock: clock))
        let sent = await udp.sentDatagrams()
        try #require(sent.count == 3)
        let beforeResume = try RTPPacket(bytes: sent[1].bytes), afterResume = try RTPPacket(bytes: sent[2].bytes)
        #expect(beforeResume.sequence == 0 && afterResume.sequence == 1)
        #expect(beforeResume.timestamp == 0 && afterResume.timestamp == 960)
        #expect(sent[1].bytes.suffix(4) == Data([0, 0, 0, 0]))
        #expect(sent[2].bytes.suffix(4) == Data([0, 0, 0, 1]))
        await owner.stop(); try await run.value
        #expect(await udp.lifecycle().closed)
        #expect(clock.base.pendingSleepCount == 0)
    }

    /// Early external-sender bytes remain bounded and reach E2EE only after Session Description.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func earlyDAVEControlIsDeliveredAfterNegotiation() async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity)
        var frames = try initialFrames()
        frames.insert(.binary(Data([0, 1, 25, 0xab, 0xcd])), at: 1)
        let socket = SessionTestSocket(frames), udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(5)
        #expect(await owner.snapshot().phase == .ready)
        #expect(await backend.recorded().1 == [25])
        await owner.stop(); try await run.value
        #expect(clock.pendingSleepCount == 0)
    }

    /// A late pre-negotiation participant removal cannot restore queued controls after stop.
    /// The admitted backend removal and cleanup share an explicit gate. The session first
    /// reaches closed, then the removal returns success; numeric control count/bytes must
    /// remain zero when the supervised run and backend cleanup have both completed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func stopDuringEarlyRemovalDoesNotRestorePendingControls() async throws {
        let tuple = credentials(), started = TestBarrier(), release = TestBarrier()
        let backend = SessionTestE2EE(tuple.identity, beforeRemoval: { _ in
            started.open()
            await Task { try? await release.wait() }.value
        })
        var frames = try initialFrames()
        frames.insert(try sessionServerFrame(13, .object(["user_id": .string("99")])), at: 1)
        let socket = SessionTestSocket(frames), udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await started.wait()
        let stop = Task { await owner.stop() }
        while await owner.snapshot().phase != .closed { try Task.checkCancellation(); await Task.yield() }
        release.open()
        await stop.value
        try await run.value
        let snapshot = await owner.snapshot()
        #expect(snapshot.phase == .closed && !snapshot.isRunning)
        #expect(snapshot.pendingControlCount == 0 && snapshot.pendingControlBytes == 0)
        #expect(snapshot.mappedSources == 0 && !snapshot.hasDatagramTransport)
        #expect(await backend.recorded().0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Discovery refuses a correctly formatted response from an unexpected UDP peer and closes all owners.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func discoveryRejectsUnexpectedPeer() async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery(wrongPeer: true)), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        await #expect(throws: VoiceControlFailure.invalidPayload) { try await owner.run() }
        #expect(await backend.recorded().0)
        #expect(await owner.snapshot().phase == .closed)
        #expect(await socket.recorded().0.map(\.opcode) == [0])
        #expect(clock.pendingSleepCount == 0)
    }

    /// Session-invalidating/kick/rate/call-termination codes never consume a reconnect attempt.
    /// - Parameter code: Current documented terminal numeric peer code.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [4006, 4014, 4021, 4022])
    func terminalPeerCloseRequiresFreshJoin(code: Int) async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = ManualClock(), connector = SessionTestConnector([socket])
        let owner = try VoiceSession(credentials: tuple, webSocket: connector,
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        let media = try #require(await owner.mediaPipeline())
        await socket.disconnect(code: code)
        await #expect(throws: VoiceSessionFailure.peerClosed(code)) { try await run.value }
        #expect(await connector.recorded().count == 1)
        #expect(await owner.snapshot().reconnectAttempts == 0)
        #expect(await media.snapshot().closed)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Speaking associations and participant controls update bounded source state without a rejoin.
    /// - Parameter maximumMediaBytes: Tiny or default aggregate budget; registration must honor either.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [128, 4_194_304])
    func participantMembershipUpdatesRouting(maximumMediaBytes: Int) async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock,
            configuration: VoiceSessionConfiguration(maximumMediaBytes: maximumMediaBytes))
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        await socket.enqueue(try sessionServerFrame(5, .object(["user_id": .string("99"), "ssrc": voiceControlNumber(77),
                                                              "speaking": voiceControlNumber(1)])))
        try await socket.waitForRead(5)
        #expect(await owner.snapshot().mappedSources == 1)
        await socket.enqueue(try sessionServerFrame(11, .object(["user_ids": .array([.string("2"), .string("99")])]), sequence: 1))
        try await socket.waitForRead(6)
        #expect(await owner.snapshot().phase == .ready)
        await socket.enqueue(try sessionServerFrame(13, .object(["user_id": .string("99")]), sequence: 2))
        try await socket.waitForRead(7)
        #expect(await owner.snapshot().mappedSources == 0)
        #expect(await backend.recorded().1 == [11, 13])
        await owner.stop(); try await run.value
        #expect(clock.pendingSleepCount == 0)
    }

    /// Terminal stop fences a successful late SSRC binding before source metadata can return.
    /// The backend's admitted remote binding waits independently of cancellation, and its
    /// close joins that hook. Releasing it after the session reaches closed must leave both
    /// session source diagnostics and the old media stream table empty.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func stopDuringParticipantBindingDoesNotRestoreSources() async throws {
        let tuple = credentials(), started = TestBarrier(), release = TestBarrier()
        let backend = SessionTestE2EE(tuple.identity, beforeBind: { userID in
            if userID.rawValue == 99 {
                started.open()
                await Task { try? await release.wait() }.value
            }
        })
        let socket = SessionTestSocket(try initialFrames()), udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        let media = try #require(await owner.mediaPipeline())
        await socket.enqueue(try sessionServerFrame(5, .object([
            "user_id": .string("99"), "ssrc": voiceControlNumber(77), "speaking": voiceControlNumber(1)])))
        try await started.wait()
        let stop = Task { await owner.stop() }
        while await owner.snapshot().phase != .closed { try Task.checkCancellation(); await Task.yield() }
        release.open()
        await stop.value
        try await run.value
        let snapshot = await owner.snapshot(), mediaSnapshot = await media.snapshot()
        #expect(snapshot.phase == .closed && snapshot.mappedSources == 0 && !snapshot.isRunning)
        #expect(mediaSnapshot.closed && mediaSnapshot.receiveStreamCount == 0)
        #expect(await backend.recorded().0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Playback cancellation/source disappearance close session ownership without real device access.
    /// - Parameter sourceFailure: Whether an injected unplug-style source error replaces cancellation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func playbackCancellationAndSourceFailure(sourceFailure: Bool) async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        let stream = try PCMFrameStream()
        let playback = Task {
            if sourceFailure { try await owner.play(SessionFailingPCMSource()) }
            else { try await owner.play(stream) }
        }
        // The first Speaking came from readiness; the source failure/cancellation itself
        // remains valid even if it arrives before the playback task is scheduled.
        if !sourceFailure { playback.cancel() }
        if sourceFailure {
            await #expect(throws: VoiceManagerFailure.disconnected) { try await playback.value }
        } else {
            await #expect(throws: CancellationError.self) { try await playback.value }
        }
        try await run.value
        #expect(await backend.recorded().0)
        #expect(await owner.snapshot().phase == .closed)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Session-owned stop/disconnect cancels a parked PCM source even when the play caller stays active.
    /// - Parameter cancelRun: True cancels the supervised run; false explicitly stops the session.
    /// The source gate proves playback reached iteration. Cleanup must finish and release its sole
    /// stream reader without externally cancelling playback or manufacturing a final PCM frame.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func terminalCleanupCancelsOwnedPlayback(cancelRun: Bool) async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        let stream = try PCMFrameStream(), started = TestBarrier()
        let playback = Task { try await owner.play(SessionWaitingPCMSource(stream: stream, readStarted: started)) }
        try await started.wait()
        if cancelRun { run.cancel() } else { await owner.stop() }
        await #expect(throws: CancellationError.self) { try await playback.value }
        if cancelRun { await #expect(throws: CancellationError.self) { try await run.value } }
        else { try await run.value }
        let source = await stream.snapshot()
        #expect(source.isFinished && !source.hasPendingReader && source.accountedBytes == 0)
        #expect(await backend.recorded().0)
        #expect(await owner.snapshot().phase == .closed)
        #expect(clock.pendingSleepCount == 0)
    }

    /// A finite PCM source sends its frame and five secure silence packets, then clears Speaking.
    /// Each explicit 20ms clock advance follows an observed pacing wait, with no timing sleeps.
    /// Receive admission remains available and a later explicit talkspurt
    /// can reopen outbound media without replacing the session or counter authorities.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func finitePlaybackTerminatesSpeakingAndCanRestart() async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = SessionTestClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        let media = try #require(await owner.mediaPipeline())
        let stream = try PCMFrameStream()
        try await stream.write(PCMBuffer(format: PCMFormat(sampleRate: 48_000, channelCount: 2),
                                         samples: Array(repeating: 0.1, count: 1_920)))
        await stream.finish()
        try clock.base.advance(by: .milliseconds(200))
        let playback = Task { try await owner.play(stream) }
        for count in 1...5 {
            try await clock.waitForMediaSleep(count)
            try clock.base.advance(by: .milliseconds(20))
        }
        try await playback.value
        let finished = await media.snapshot()
        #expect(finished.sentPackets == 6 && finished.authorized && !finished.sendingAllowed && !finished.closed)
        let controls = await socket.recorded().0
        let last = try #require(controls.last)
        guard case .json(.object(let fields)) = last.payload else { Issue.record("Speaking must be JSON"); return }
        #expect(last.opcode == 5 && fields["speaking"] == voiceControlNumber(0))
        await #expect(throws: VoiceMediaPipelineError.unauthorized) {
            try await media.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: .init(clock: clock))
        }
        try await owner.setSpeaking(true)
        try await media.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: .init(clock: clock))
        #expect(await media.snapshot().sentPackets == 7)
        await owner.stop(); try await run.value
        #expect(await backend.recorded().0)
        #expect(clock.base.pendingSleepCount == 0)
    }

    /// Cancelling before HELLO releases the finite receive deadline and closes the acquired socket.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringHelloRead() async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket([]), clock = ManualClock()
        let owner = try VoiceSession(credentials: tuple, webSocket: SessionTestConnector([socket]),
            makeDatagram: { _ in throw TransportFailure.scriptExhausted }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(1)
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await backend.recorded().0)
        #expect(await socket.recorded().1 == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Adapter validation/capacity failures stay terminal and never create broken resume loops.
    /// - Parameter failure: Explicit bounded adapter error distinct from socket closure/loss.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [TransportFailure.invalidLimit, .concurrentRead, .chunkTooLarge(limit: 256, actual: 257)])
    func adapterValidationErrorsAreNotRetried(failure: TransportFailure) async throws {
        let tuple = credentials(), backend = SessionTestE2EE(tuple.identity), socket = SessionTestSocket(try initialFrames())
        let udp = SessionTestDatagram(discovery()), clock = ManualClock(), connector = SessionTestConnector([socket])
        let owner = try VoiceSession(credentials: tuple, webSocket: connector,
            makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
        let run = Task { try await owner.run() }
        try await socket.waitForRead(4)
        await socket.failReceive(failure)
        await #expect(throws: failure) { try await run.value }
        #expect(await connector.recorded().count == 1)
        #expect(await owner.snapshot().reconnectAttempts == 0)
        #expect(await backend.recorded().0)
        #expect(clock.pendingSleepCount == 0)
    }
}

extension VoiceSessionTests {
    /// Captures explicit supervised lifetime and media readiness without logging voice credentials,
    /// discovery addresses, session identifiers, key arrays or per-frame media payloads.
    /// - Throws: Unexpected valid synthetic handshake or cleanup errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func structuredLoggingTracksReadinessWithoutCredentials() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let tuple = credentials()
            let socket = SessionTestSocket(try initialFrames())
            let connector = SessionTestConnector([socket])
            let backend = SessionTestE2EE(tuple.identity)
            let clock = SessionTestClock()
            let udp = SessionTestDatagram(discovery())
            let owner = try VoiceSession(credentials: tuple, webSocket: connector, makeDatagram: { _ in udp }, e2ee: backend, clock: clock)
            #expect(recorder.entries.isEmpty)
            let run = Task { try await owner.run() }
            try await socket.waitForRead(4)
            #expect(await owner.snapshot().phase == .ready)
            await owner.stop()
            try await run.value
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.voice" }
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "voice.session.running" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "voice.discovery.completed" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "voice.media.authorized" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "voice.session.stopped" })
        let rendered = entries.map { $0.message + String(describing: $0.metadata) }.joined()
        for secret in ["synthetic-session", "synthetic-token", "voice.discord.media", "127.0.0.1", "secret_key"] {
            #expect(!rendered.contains(secret))
        }
        #expect(entries.allSatisfy { $0.level != .info && $0.level != .notice })
    }
}
