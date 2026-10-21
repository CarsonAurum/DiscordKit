import DiscordLogging
import DiscordCore
import DiscordMedia
import DiscordModels
import DiscordTransport
import DiscordVoiceCodecs
import DiscordVoiceCrypto
import Foundation

/// Injected owned DAVE signaling and complete-frame protection for one exact session.
/// Implementations serialize bounded cryptographic admission and authenticate actual MLS state.
/// Voice never imports a concrete DAVE implementation or trusts a boolean readiness flag.
public protocol VoiceSessionE2EE: VoiceFrameTransformer {
    /// Starts the authenticated negotiated version without opening a transport.
    /// - Parameter protocolVersion: Nonzero version from Session Description.
    /// - Returns: Ordered commands to send exactly once.
    /// - Throws: Cancellation, closure, version, key-establishment or admission failures.
    func start(protocolVersion: UInt16) async throws -> [VoiceGatewayFrame]
    /// Processes one authenticated DAVE or membership control in socket order.
    /// - Parameters:
    ///   - frame: Validated server control for this exact session.
    ///   - now: Nonnegative monotonically increasing seconds in the injected clock domain.
    /// - Returns: Bounded commands to send in order without replay.
    /// - Throws: Cancellation, malformed signaling, membership, epoch or key failures.
    func receive(_ frame: VoiceGatewayFrame, now: TimeInterval) async throws -> [VoiceGatewayFrame]
    /// Checks live MLS readiness and exact identity before authorizing the copied reducer.
    /// - Parameter state: Reducer currently awaiting E2EE.
    /// - Returns: Ready reducer only if current membership, epoch and identity match.
    /// - Throws: Unavailable media before establishment, or identity/version/admission failures.
    func authorizeGateway(_ state: VoiceGatewaySessionState) async throws -> VoiceGatewaySessionState
    /// Associates an authenticated Ready/Speaking SSRC with its account.
    /// - Parameters:
    ///   - ssrc: Audio source; RTP packets cannot establish this binding.
    ///   - userID: Nonzero authenticated account.
    /// - Throws: Closure, capacity or conflicting binding failures.
    func bindSSRC(_ ssrc: UInt32, userID: UserID) async throws
    /// Removes a departed account's source mapping; repeated removal is harmless.
    /// - Parameter userID: Account from an authenticated disconnect control.
    func removeParticipant(_ userID: UserID) async
    /// Rejects new work, awaits admitted operations and releases ephemeral keys idempotently.
    func close() async
}

/// Sanitized supervised-session errors; no token, endpoint, key or payload is retained.
public enum VoiceSessionFailure: Error, Sendable, Equatable {
    case invalidEndpoint, alreadyRunning, unavailable, connectionLost, retryExhausted
    case peerClosed(Int), rejoinRequired, participantCapacity, concurrentPlayback
}

/// Explicit time, retry and memory policy for one supervised Voice v8 session.
public struct VoiceSessionConfiguration: Sendable {
    public let handshakeTimeout: Duration
    public let operationTimeout: Duration
    public let retryDelay: Duration
    public let maximumReconnectAttempts: Int
    public let maximumFrameBytes: Int
    public let maximumReceiveStreams: Int
    public let maximumMediaBytes: Int

    /// Validates finite bounds without starting tasks or consulting a clock.
    /// - Parameters:
    ///   - handshakeTimeout: Positive post-HELLO negotiation bound through one day, default 30 seconds.
    ///   - operationTimeout: Positive per connect/write/discovery bound through one day, default ten seconds.
    ///   - retryDelay: Positive retry spacing through one day, default one second.
    ///   - maximumReconnectAttempts: Lifetime resumable retries, 0...30, default five.
    ///   - maximumFrameBytes: Complete control message byte cap, 256...16 MiB, default 1 MiB.
    ///   - maximumReceiveStreams: Authenticated audio-source cap, 1...1024, default 64.
    ///   - maximumMediaBytes: Aggregate jitter storage cap, 1...64 MiB, default 4 MiB.
    /// - Throws: `invalidConfiguration` for invalid limits. Retry never raises a bound.
    public init(handshakeTimeout: Duration = .seconds(30), operationTimeout: Duration = .seconds(10),
                retryDelay: Duration = .seconds(1), maximumReconnectAttempts: Int = 5,
                maximumFrameBytes: Int = 1_048_576, maximumReceiveStreams: Int = 64,
                maximumMediaBytes: Int = 4_194_304) throws {
        guard handshakeTimeout > .zero, handshakeTimeout <= .seconds(86_400),
              operationTimeout > .zero, operationTimeout <= .seconds(86_400),
              retryDelay > .zero, retryDelay <= .seconds(86_400),
              (0...30).contains(maximumReconnectAttempts), (256...16_777_216).contains(maximumFrameBytes),
              (1...1024).contains(maximumReceiveStreams), (1...67_108_864).contains(maximumMediaBytes) else {
            throw VoiceControlFailure.invalidConfiguration
        }
        self.handshakeTimeout = handshakeTimeout; self.operationTimeout = operationTimeout
        self.retryDelay = retryDelay; self.maximumReconnectAttempts = maximumReconnectAttempts
        self.maximumFrameBytes = maximumFrameBytes; self.maximumReceiveStreams = maximumReceiveStreams
        self.maximumMediaBytes = maximumMediaBytes
    }

    /// Finite default policy; construction performs no I/O and cannot fail.
    public static var standard: Self { try! Self() }
}

/// Payload-free session diagnostics; counts describe this local owner, not live capacity.
public struct VoiceSessionSnapshot: Sendable {
    public let phase: VoiceGatewayPhase
    public let isRunning: Bool
    public let reconnectAttempts: Int
    public let mappedSources: Int
    public let pendingControlCount: Int
    public let pendingControlBytes: Int
    public let rejectedDatagrams: UInt64
    public let hasDatagramTransport: Bool
}

/// Owns a Voice v8 WebSocket, UDP discovery, heartbeat/resume and bounded media composition.
///
/// Construction is inert. `run()` owns structured control, heartbeat and UDP children.
/// Media codecs and consumer sources/sinks never execute in the heartbeat child. A channel,
/// token or server replacement requires a fresh session, supplied by `VoiceManager`.
/// Transport and DAVE nonces survive resumable socket replacement. Media is suspended until
/// the actual E2EE owner reauthorizes the exact reducer; there is no plaintext fallback.
public actor VoiceSession<C: Clock>: VoiceManagedSession where C.Duration == Duration {
    public nonisolated let identity: VoiceConnectionIdentity
    private let credentials: VoiceConnectionCredentials
    private let webSocket: any WebSocketTransport
    private let makeDatagram: @Sendable (TransportContext<C>) async throws -> any DatagramTransport
    private let e2ee: any VoiceSessionE2EE
    private let clock: C
    private let configuration: VoiceSessionConfiguration
    private let encoder: OpusAudioEncoder
    private let now: @Sendable () -> TimeInterval
    private let url: URL
    private var state: VoiceGatewaySessionState
    private var connection: (any WebSocketConnection)?
    private var datagram: (any DatagramTransport)?
    private var peer: DatagramAddress?
    private var localSSRC: UInt32?
    private var cipher: VoiceTransportCipher?
    private var media: VoiceMediaPipeline<C>?
    private var sources: [UserID: UInt32] = [:]
    private var running = false
    private var stopped = false
    private var playing = false
    private var playback: Task<Void, any Error>?
    private var writingSpeaking = false
    private var speaking = false
    private var attempts = 0
    private var rejected: UInt64 = 0
    private var heartbeatNonce: UInt64 = 0
    private var e2eeStarted = false
    private var discoveryComplete = false
    private var pendingMembership: [VoiceGatewayFrame] = []
    private var pendingControlBytes = 0
    private var cleanup: Task<Void, Never>?
    private var diagnosticContext: Logger.Metadata?
    private let udpSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    /// Creates one inert exact-identity session with injected adapters and monotonic time.
    /// - Parameters:
    ///   - credentials: Fresh two-event rendezvous result; never reused on a move/replacement.
    ///   - webSocket: TLS-capable adapter; construction does not connect it.
    ///   - makeDatagram: Opens one owned bounded UDP socket when Ready arrives; partial failure
    ///     cleanup belongs to the factory. The session closes every successfully returned socket.
    ///   - e2ee: Owned exact-identity DAVE backend with shared signing identity and trusted sender.
    ///   - clock: Monotonic clock for all deadlines, pacing and DAVE time.
    ///   - configuration: Explicit finite policy, default standard.
    ///   - encoder: Owned Opus policy, default 48-kHz stereo CELT/20ms/64kbps.
    ///   - now: Optional shared monotonic seconds source, using the same origin as the DAVE
    ///     adapter. Nil uses elapsed time since session construction; callers composing a
    ///     DAVE adapter should inject one shared closure into both owners.
    /// - Throws: Invalid endpoint, configuration or codec errors before acquiring resources.
    public init(credentials: VoiceConnectionCredentials, webSocket: any WebSocketTransport,
                makeDatagram: @escaping @Sendable (TransportContext<C>) async throws -> any DatagramTransport,
                e2ee: any VoiceSessionE2EE, clock: C,
                configuration: VoiceSessionConfiguration = .standard,
                encoder: OpusAudioEncoder? = nil,
                now: (@Sendable () -> TimeInterval)? = nil) throws {
        self.credentials = credentials; identity = credentials.identity
        self.webSocket = webSocket; self.makeDatagram = makeDatagram; self.e2ee = e2ee
        self.clock = clock; self.configuration = configuration
        let origin = clock.now
        self.now = now ?? {
            let elapsed = origin.duration(to: clock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
        self.encoder = try encoder ?? OpusAudioEncoder(channelCount: 2)
        url = try Self.endpointURL(credentials.endpoint)
        state = try VoiceGatewaySessionState(credentials: credentials, maximumDAVEProtocolVersion: 1)
    }

    /// Runs until stopped, cancelled, irrecoverable closure or the finite retry budget expires.
    /// - Throws: Concurrent-run/closed errors, sanitized protocol errors, timeout/cancellation,
    ///   or transport/backend failures. All acquired sockets, media and E2EE keys close before return.
    /// Resumable retries preserve counters; session-invalidating codes require new Gateway credentials.
    public func run() async throws {
        try await DiscordLog.withOperation("voice.session", event: "voice.session.run") {
            try await runOwned()
        }
    }

    /// Executes the admitted supervised lifetime inside its inherited diagnostic scope.
    /// - Throws: Original session failure after all owned children and resources close.
    private func runOwned() async throws {
        guard !running else { throw VoiceSessionFailure.alreadyRunning }
        guard !stopped else { throw VoiceControlFailure.closed }
        diagnosticContext = DiscordLog.context
        let logger = DiscordLog.makeLogger("voice.session")
        logger.info("Voice session running", metadata: ["dk.event": "voice.session.running"])
        logger.trace("Voice session ownership admitted", metadata: ["dk.event": "voice.session.admitted",
            "dk.maximum_reconnect_attempts": .stringConvertible(configuration.maximumReconnectAttempts),
            "dk.maximum_receive_streams": .stringConvertible(configuration.maximumReceiveStreams),
            "dk.maximum_media_bytes": .stringConvertible(configuration.maximumMediaBytes)])
        running = true
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                logger.trace("Voice control and datagram children starting", metadata: ["dk.event": "voice.session.children.starting"])
                group.addTask { try await self.runConnections() }
                group.addTask { try await self.receiveMedia() }
                defer { group.cancelAll() }
                while let _ = try await group.next() {
                    if stopped { group.cancelAll(); return }
                }
            }
            await dispose(); running = false
            logger.info("Voice session stopped", metadata: ["dk.event": "voice.session.stopped"])
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Voice session cancelled", metadata: ["dk.event": "voice.session.cancelled"])
            } else {
                logger.error("Voice session failed", metadata: ["dk.event": "voice.session.failed",
                    "dk.failure": .string(Self.failureCategory(error)), "dk.phase": .string(Self.phaseCategory(state.phase))])
            }
            await dispose(); running = false
            throw error
        }
    }

    /// Supervises successive WebSocket generations while the lifetime UDP reader remains active.
    /// Cancelling a per-attempt socket task must never cancel the UDP receive, because owned
    /// adapters may close UDP on receive cancellation. Only terminal session cleanup cancels it.
    /// The first protocol, crypto, capacity or deadline failure remains causal even when
    /// cancelling sibling reads changes the native socket status during cleanup. Only an
    /// actual connection-loss result is classified from observed peer-close evidence.
    /// - Throws: Original terminal protocol/deadline errors, observed peer errors,
    ///   cancellation or exhausted resume policy; cleanup never authorizes another retry.
    private func runConnections() async throws {
        while !stopped {
            DiscordLog.makeLogger("voice.session").trace("Voice connection attempt admitted", metadata: ["dk.event": "voice.connection.attempt",
                "dk.attempt": .stringConvertible(attempts + 1), "dk.phase": .string(Self.phaseCategory(state.phase))])
            do { try await attempt(); break }
            catch {
                if stopped { break }
                await media?.setAuthorized(false)
                try Task.checkCancellation()
                // Only actual socket loss or heartbeat failure permits a resume. Malformed
                // signaling, crypto, discovery, timeout and capacity failures preserve their
                // causal error before sampling status that cancellation cleanup may change.
                let lost = (error as? VoiceSessionFailure) == .connectionLost
                let missed = (error as? VoiceControlFailure) == .missedHeartbeatACK
                guard lost || missed else {
                    DiscordLog.makeLogger("voice.session").trace("Voice failure cannot resume", metadata: ["dk.event": "voice.connection.resume.rejected",
                        "dk.failure": .string(Self.failureCategory(error))])
                    throw error
                }
                let code = await (connection as? any WebSocketSessionConnection)?.peerCloseCode()
                if let code, !Self.canResume(closeCode: code) {
                    if lost { throw VoiceSessionFailure.peerClosed(code) }
                    throw error
                }
                guard let resumable = connection as? any WebSocketSessionConnection else {
                    throw VoiceSessionFailure.rejoinRequired
                }
                guard attempts < configuration.maximumReconnectAttempts else {
                    throw VoiceSessionFailure.retryExhausted
                }
                attempts += 1; state.connectionLost()
                DiscordLog.makeLogger("voice.session").notice("Voice connection resuming", metadata: ["dk.event": "voice.connection.resuming",
                    "dk.attempt": .stringConvertible(attempts)])
                await resumable.closeForReconnect(); connection = nil
                try await clock.sleep(until: clock.now.advanced(by: configuration.retryDelay), tolerance: nil)
            }
        }
    }

    /// Stops all owned resources idempotently, including in-flight reads and playback gates.
    /// The caller that owns `run()` should also await that task to join its structured children.
    /// No leave command is sent here; `VoiceManager.leave` owns main-Gateway control.
    public func stop() async { await dispose() }

    /// Reports numeric state without exposing any credential or packet contents.
    /// - Returns: Current phase, retry/source/rejection counts and ownership flags.
    public func snapshot() -> VoiceSessionSnapshot {
        .init(phase: state.phase, isRunning: running, reconnectAttempts: attempts,
              mappedSources: sources.count, pendingControlCount: pendingMembership.count,
              pendingControlBytes: pendingControlBytes, rejectedDatagrams: rejected,
              hasDatagramTransport: datagram != nil)
    }

    /// Obtains the bounded encoded/PCM send, playout and recording surface after E2EE readiness.
    /// - Returns: The owned pipeline, or nil while connecting/suspended/closed. Retained references
    ///   remain authorization-gated on later control transitions and close.
    public func mediaPipeline() -> VoiceMediaPipeline<C>? { state.phase == .ready ? media : nil }

    /// Publishes Speaking before audio, or clears it after explicit silence termination.
    /// - Parameter speaking: True for microphone audio bit one; false clears all bits.
    /// - Throws: Unavailable/closed state, overlapping speaking write, cancellation or transport error.
    /// One caller owns talkspurt ordering; this API never queues unbounded writes or retries them.
    public func setSpeaking(_ speaking: Bool) async throws {
        guard state.phase == .ready, let localSSRC, !writingSpeaking else { throw VoiceSessionFailure.unavailable }
        writingSpeaking = true; defer { writingSpeaking = false }
        try await send(VoiceGatewayFrame(opcode: 5, data: .object([
            "speaking": voiceControlNumber(speaking ? 1 : 0), "delay": voiceControlNumber(0),
            "ssrc": voiceControlNumber(localSSRC)])))
        self.speaking = speaking
        await media?.setSendingAllowed(speaking)
    }

    /// Streams paced PCM from a caller-owned async source through the owned codec and DAVE path.
    /// - Parameter source: Finite or cancellation-aware normalized 48-kHz buffers matching the encoder.
    /// - Throws: Concurrent playback, source/format/codec/transport/cancellation errors. Failure stops
    ///   this session so device-unplug/source failures cannot leave a live unobserved talkspurt.
    /// Normal completion sends five authenticated silence frames then clears Speaking. Source
    /// iteration suspends independently from the structured heartbeat/control children. The
    /// session retains one playback task: stop and terminal disconnect cancel and await it,
    /// including a cooperative source parked waiting for its next buffer. Resumable socket
    /// loss and authenticated key transitions suspend source consumption until actual media
    /// reauthorization within the finite handshake budget. A frame invalidated while sending
    /// is discarded rather than replayed; format, crypto and transport failures remain terminal.
    public func play<S: AsyncSequence & Sendable>(_ source: S) async throws
    where S.Element == PCMBuffer, S.AsyncIterator: Sendable {
        guard !playing, let media = mediaPipeline() else { throw VoiceSessionFailure.concurrentPlayback }
        playing = true; defer { playing = false }
        let operation = Task { [self] in
            try Task.checkCancellation()
            try await setSpeaking(true)
            var iterator = source.makeAsyncIterator()
            while true {
                try await waitForPlaybackReadiness(media)
                guard let buffer = try await iterator.next() else { break }
                do { _ = try await media.send(buffer, context: context()) }
                catch let error as VoiceMediaPipelineError where error == .unauthorized || error == .staleOperation {
                    // The revocation guards fail before UDP dispatch. Drop this consumed frame;
                    // preserve the source and wait for the actual epoch owner to reauthorize.
                    try await waitForPlaybackReadiness(media)
                }
            }
            try await waitForPlaybackReadiness(media)
            try await media.sendTerminationSilence(context: context())
            try await setSpeaking(false)
        }
        playback = operation
        defer { playback = nil }
        do {
            try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: { operation.cancel() }
            try Task.checkCancellation()
        } catch {
            await dispose(); throw error
        }
    }

    /// Suspends source consumption until the current session and media owner are authorized again.
    /// - Parameter media: Exact pipeline already owned by this playback operation.
    /// - Throws: Cancellation, permanent closure or the configured finite negotiation deadline.
    /// The pipeline owns pacing reset and cryptographic generations; no frame is retained or replayed.
    private func waitForPlaybackReadiness(_ media: VoiceMediaPipeline<C>) async throws {
        let deadline = clock.now.advanced(by: configuration.handshakeTimeout)
        while true {
            try Task.checkCancellation()
            guard !stopped, state.phase != .closed else { throw VoiceControlFailure.closed }
            let snapshot = await media.snapshot()
            guard !stopped, !snapshot.closed else { throw VoiceControlFailure.closed }
            if state.phase == .ready, snapshot.authorized, snapshot.sendingAllowed { return }
            guard clock.now < deadline else { throw TransportFailure.deadlineExceeded }
            try await clock.sleep(until: min(clock.now.advanced(by: .milliseconds(20)), deadline), tolerance: nil)
        }
    }

    /// Validates Voice close policy from the current official opcode table (2026-10-18).
    /// - Parameter closeCode: Numeric peer close code; arbitrary reason text is never retained.
    /// - Returns: True only for abrupt/ordinary service loss and documented resumable cases.
    /// Authentication, invalid-session, disconnect, malformed/rate-limited/terminated calls fail closed.
    public nonisolated static func canResume(closeCode: Int) -> Bool {
        [1006, 1011, 1012, 1013, 4000, 4015].contains(closeCode)
    }

    /// Builds the explicit v8 secure URL from an authenticated bounded endpoint authority.
    /// - Parameter endpoint: Host and optional port only; schemes, credentials, paths and query are rejected.
    /// - Returns: A secure WebSocket URL with exactly the `v=8` query.
    /// - Throws: `invalidEndpoint` for malformed/empty authority or invalid port. DNS/TLS stay adapter-owned.
    private nonisolated static func endpointURL(_ endpoint: String) throws -> URL {
        guard !endpoint.isEmpty, endpoint.utf8.count <= 4_096,
              !endpoint.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "?" || $0 == "#" || $0 == "@" }),
              var parts = URLComponents(string: "wss://" + endpoint),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.port == nil || (1...65_535).contains(parts.port!) else { throw VoiceSessionFailure.invalidEndpoint }
        parts.path = "/"; parts.queryItems = [URLQueryItem(name: "v", value: "8")]
        guard let url = parts.url else { throw VoiceSessionFailure.invalidEndpoint }
        return url
    }

    /// Runs one socket generation with independent structured control/heartbeat/deadline children.
    /// - Throws: Original protocol, timeout or transport errors; children are cancelled and joined.
    private func attempt() async throws {
        let logger = DiscordLog.makeLogger("voice.session")
        logger.trace("Voice WebSocket opening", metadata: ["dk.event": "voice.connection.opening"])
        let socket = try await webSocket.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context())
        guard !stopped else { await socket.close(); throw VoiceControlFailure.closed }
        connection = socket
        logger.debug("Voice WebSocket acquired", metadata: ["dk.event": "voice.connection.opened"])
        logger.trace("Voice HELLO awaiting", metadata: ["dk.event": "voice.hello.waiting"])
        let helloContext = TransportContext(clock: clock, deadline: clock.now.advanced(by: configuration.operationTimeout))
        guard let message = try await socket.receive(context: helloContext) else { throw VoiceSessionFailure.connectionLost }
        let hello = try VoiceGatewayFrame(message, limits: limits())
        guard hello.opcode == 8 else { throw VoiceControlFailure.invalidTransition }
        try await consume(hello)
        logger.trace("Voice HELLO validated", metadata: ["dk.event": "voice.hello.validated"])
        guard let interval = state.heartbeatIntervalMilliseconds else { throw VoiceControlFailure.invalidPayload }
        logger.trace("Voice handshake supervisors starting", metadata: ["dk.event": "voice.handshake.children.starting",
            "dk.heartbeat_interval_ms": .stringConvertible(interval)])
        let handshakeDeadline = clock.now.advanced(by: configuration.handshakeTimeout)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.receiveControls(socket) }
            group.addTask { try await self.heartbeat(interval: .milliseconds(Int64(interval))) }
            group.addTask { try await self.checkHandshake(until: handshakeDeadline) }
            defer { group.cancelAll() }
            while let _ = try await group.next() { if stopped { group.cancelAll(); return } }
        }
    }

    /// Reads controls serially without executing caller media sources or sinks.
    /// - Parameter socket: Exact attempt's socket; old generations never mutate the new reducer.
    /// - Throws: EOF/loss, frame/protocol/backend failures, cancellation or transport errors.
    private func receiveControls(_ socket: any WebSocketConnection) async throws {
        while !stopped {
            let message: WebSocketMessage
            do {
                guard let received = try await socket.receive(context: TransportContext(clock: clock)) else {
                    throw VoiceSessionFailure.connectionLost
                }
                message = received
            } catch is CancellationError { throw CancellationError() }
            catch let failure as TransportFailure where failure != .closed { throw failure }
            catch { throw VoiceSessionFailure.connectionLost }
            try await consume(VoiceGatewayFrame(message, limits: limits()))
        }
    }

    /// Schedules authoritative HELLO intervals and detects missing ACK before another send.
    /// - Parameter interval: Positive server interval; READY's obsolete interval is ignored.
    /// - Throws: Cancellation, missed ACK, nonce exhaustion or write errors.
    private func heartbeat(interval: Duration) async throws {
        var next = clock.now.advanced(by: interval)
        while !stopped {
            try await clock.sleep(until: next, tolerance: nil)
            guard !stopped else { return }
            try state.heartbeatDeadlineElapsed()
            guard heartbeatNonce < UInt64.max else { throw VoiceControlFailure.invalidConfiguration }
            heartbeatNonce += 1
            try await send(state.heartbeat(nonce: heartbeatNonce))
            next = clock.now.advanced(by: interval)
        }
    }

    /// Waits for UDP creation, then admits datagrams independently of control work.
    /// - Throws: Socket loss/cancellation; unauthenticated malformed media is counted and discarded.
    private func receiveMedia() async throws {
        if !discoveryComplete {
            for await _ in udpSignal.stream { if discoveryComplete || stopped { break } }
        }
        guard let datagram else { return }
        while !stopped {
            guard let packet = try await datagram.receiveDatagram(context: TransportContext(clock: clock)) else {
                if stopped { return }; throw VoiceSessionFailure.connectionLost
            }
            guard let media else { continue }
            do { try await media.receive(packet) }
            catch is CancellationError { throw CancellationError() }
            catch { if rejected < UInt64.max { rejected += 1 } }
        }
    }

    /// Enforces initial/resume E2EE completion without relying on future control arrivals.
    /// - Parameter deadline: Absolute negotiation deadline in this session clock.
    /// - Throws: Cancellation or deadlineExceeded unless media is ready when the deadline expires.
    private func checkHandshake(until deadline: C.Instant) async throws {
        try await clock.sleep(until: deadline, tolerance: nil)
        guard state.phase == .ready || stopped else {
            DiscordLog.makeLogger("voice.session").warning("Voice handshake deadline expired", metadata: ["dk.event": "voice.handshake.expired",
                "dk.phase": .string(Self.phaseCategory(state.phase))])
            throw TransportFailure.deadlineExceeded
        }
    }

    /// Reduces one control and executes its bounded ownership effects.
    /// - Parameter frame: Complete authenticated socket frame.
    /// - Throws: Protocol, discovery, crypto, bounds or send failures; no command is retried.
    private func consume(_ frame: VoiceGatewayFrame) async throws {
        let logger = DiscordLog.makeLogger("voice.session")
        logger.trace("Voice control admitted", metadata: ["dk.event": "voice.control.admitted",
            "dk.opcode": .stringConvertible(frame.opcode), "dk.phase": .string(Self.phaseCategory(state.phase))])
        let effect = try state.receive(frame)
        logger.trace("Voice control reduced", metadata: ["dk.event": "voice.control.reduced",
            "dk.opcode": .stringConvertible(frame.opcode), "dk.phase": .string(Self.phaseCategory(state.phase))])
        if state.phase != .ready { await media?.setAuthorized(false) }
        guard !stopped else { throw VoiceControlFailure.closed }
        switch effect {
        case .send(let frame): try await send(frame)
        case .discoverUDP(let server):
            logger.debug("Voice datagram discovery starting", metadata: ["dk.event": "voice.discovery.started"])
            guard datagram == nil else { throw VoiceControlFailure.invalidTransition }
            let udp = try await makeDatagram(context())
            guard !stopped else { await udp.close(); throw VoiceControlFailure.closed }
            datagram = udp; localSSRC = server.ssrc
            logger.trace("Voice datagram transport acquired", metadata: ["dk.event": "voice.discovery.transport.acquired"])
            let destination = DatagramAddress(host: server.ip, port: server.port); peer = destination
            try await udp.sendDatagram(Datagram(bytes: VoiceDiscovery.request(ssrc: server.ssrc), peer: destination), context: context())
            guard let response = try await udp.receiveDatagram(context: context()), response.peer == destination else {
                throw VoiceControlFailure.invalidPayload
            }
            logger.trace("Voice datagram discovery reply received", metadata: ["dk.event": "voice.discovery.reply.received"])
            let external = try VoiceDiscovery.response(response.bytes, ssrc: server.ssrc)
            logger.trace("Voice datagram discovery reply validated", metadata: ["dk.event": "voice.discovery.reply.validated"])
            try await e2ee.bindSSRC(server.ssrc, userID: identity.userID)
            try await send(state.selectProtocol(address: external.host, port: external.port))
            logger.trace("Voice transport protocol selected", metadata: ["dk.event": "voice.discovery.protocol.selected"])
            discoveryComplete = true
            DiscordLog.makeLogger("voice.session").debug("Voice datagram discovery completed", metadata: ["dk.event": "voice.discovery.completed"])
            udpSignal.continuation.yield(())
        case .configureMedia(let description):
            logger.debug("Voice media configuration starting", metadata: ["dk.event": "voice.media.configuring"])
            guard let datagram, let peer, let localSSRC,
                  let mode = VoiceEncryptionMode(rawValue: description.mode) else { throw VoiceControlFailure.invalidTransition }
            let keyOwner = try VoiceTransportCipher(mode: mode, key: description.secretKey,
                maximumReceiveStreams: configuration.maximumReceiveStreams)
            cipher = keyOwner
            let pipeline = try VoiceMediaPipeline(clock: clock, transport: datagram, peer: peer, cipher: keyOwner,
                transformer: e2ee, ssrc: localSSRC, encoder: encoder,
                maximumReceiveStreams: configuration.maximumReceiveStreams, maximumBufferedBytes: configuration.maximumMediaBytes)
            media = pipeline; await pipeline.setSendingAllowed(false)
            for (user, source) in sources {
                try await e2ee.bindSSRC(source, userID: user)
                try await pipeline.registerReceiveStream(ssrc: source,
                    maximumBytes: min(262_144, configuration.maximumMediaBytes))
            }
            logger.trace("Voice E2EE establishment starting", metadata: ["dk.event": "voice.e2ee.starting"])
            let commands = try await e2ee.start(protocolVersion: description.daveProtocolVersion)
            logger.trace("Voice E2EE establishment commands prepared", metadata: ["dk.event": "voice.e2ee.commands.prepared",
                "dk.commands": .stringConvertible(commands.count)])
            for command in commands { try await send(command) }
            guard !stopped else { throw VoiceControlFailure.closed }
            e2eeStarted = true
            DiscordLog.makeLogger("voice.session").debug("Voice media configured", metadata: ["dk.event": "voice.media.configured"])
            logger.trace("Voice early controls draining", metadata: ["dk.event": "voice.control.early.draining",
                "dk.pending": .stringConvertible(pendingMembership.count), "dk.pending_bytes": .stringConvertible(pendingControlBytes)])
            let pending = pendingMembership; pendingMembership.removeAll(); pendingControlBytes = 0
            for event in pending { try await processE2EE(event) }
            try await authorizeIfAvailable()
        case .processE2EE(let frame):
            if e2eeStarted { try await processE2EE(frame) } else { try retainEarlyControl(frame) }
        case .event(let frame): try await membership(frame)
        case .none:
            if frame.opcode == 9 { try await authorizeIfAvailable() }
        }
        guard !stopped else { throw VoiceControlFailure.closed }
    }

    /// Applies DAVE signaling once and keeps media suspended until the actual epoch is available.
    /// - Parameter frame: DAVE/member server control.
    /// - Throws: Backend or transport errors; all returned commands are sent once in order.
    private func processE2EE(_ frame: VoiceGatewayFrame) async throws {
        let logger = DiscordLog.makeLogger("voice.session")
        logger.trace("Voice E2EE control processing", metadata: ["dk.event": "voice.e2ee.control.started",
            "dk.opcode": .stringConvertible(frame.opcode)])
        let commands = try await e2ee.receive(frame, now: now())
        logger.trace("Voice E2EE control processed", metadata: ["dk.event": "voice.e2ee.control.completed",
            "dk.commands": .stringConvertible(commands.count)])
        for command in commands { try await send(command) }
        try await authorizeIfAvailable()
    }

    /// Attempts readiness after every authenticated transition; unavailable state stays suspended.
    /// Backend receive failures already propagate; readiness failure never authorizes passthrough.
    /// - Throws: Cancellation or an admitted Speaking write failure after readiness succeeds.
    private func authorizeIfAvailable() async throws {
        guard !stopped, state.phase == .awaitingE2EE else { return }
        let logger = DiscordLog.makeLogger("voice.session")
        logger.trace("Voice media authorization checking", metadata: ["dk.event": "voice.media.authorization.checking"])
        let authorized: VoiceGatewaySessionState
        do {
            authorized = try await e2ee.authorizeGateway(state)
        } catch is CancellationError { throw CancellationError() }
        catch {
            await media?.setAuthorized(false)
            logger.trace("Voice media authorization pending", metadata: ["dk.event": "voice.media.authorization.pending"])
            return
        }
        guard !stopped, state.phase == .awaitingE2EE else { return }
        try state.acceptAuthorization(from: authorized)
        // Speaking must precede every newly enabled outbound media path, including clients
        // that use the exposed encoded pipeline without the PCM playback convenience.
        try await setSpeaking(true)
        await media?.setAuthorized(true)
        DiscordLog.makeLogger("voice.session").info("Voice media authorized", metadata: ["dk.event": "voice.media.authorized"])
    }

    /// Routes authenticated speaking/member events into bounded source and DAVE state.
    /// - Parameter frame: Server event; unknown future events require no retained queue.
    /// - Throws: Malformed mappings, source-capacity, cryptographic or write errors.
    /// Closure is rechecked after binding/stream suspension so admitted backend work cannot
    /// restore session source metadata after terminal cleanup has cleared it.
    private func membership(_ frame: VoiceGatewayFrame) async throws {
        if frame.opcode == 5 {
            guard case .json(.object(let data)) = frame.payload, case .string(let value) = data["user_id"],
                  let rawID = UInt64(value), rawID > 0, case .number(let number) = data["ssrc"],
                  let ssrc = UInt32(number.rawValue) else { throw VoiceControlFailure.invalidPayload }
            let user = UserID(rawValue: rawID)
            guard sources[user] != nil || sources.count < configuration.maximumReceiveStreams else {
                throw VoiceSessionFailure.participantCapacity
            }
            try await e2ee.bindSSRC(ssrc, userID: user)
            guard !stopped, state.phase != .closed else { throw VoiceControlFailure.closed }
            if let previous = sources[user], previous != ssrc { await media?.removeReceiveStream(ssrc: previous) }
            guard !stopped, state.phase != .closed else { throw VoiceControlFailure.closed }
            if sources[user] != ssrc {
                try await media?.registerReceiveStream(ssrc: ssrc,
                    maximumBytes: min(262_144, configuration.maximumMediaBytes))
            }
            guard !stopped, state.phase != .closed else { throw VoiceControlFailure.closed }
            sources[user] = ssrc
            DiscordLog.makeLogger("voice.session").trace("Voice authenticated source mapping installed", metadata: ["dk.event": "voice.membership.source.installed",
                "dk.sources": .stringConvertible(sources.count)])
        } else if frame.opcode == 11 || frame.opcode == 13 {
            try state.suspendMedia()
            await media?.setAuthorized(false)
            DiscordLog.makeLogger("voice.session").debug("Voice media suspended for membership transition", metadata: ["dk.event": "voice.membership.media.suspended",
                "dk.sources": .stringConvertible(sources.count)])
            if frame.opcode == 13, case .json(.object(let data)) = frame.payload,
               case .string(let value) = data["user_id"], let rawID = UInt64(value) {
                let user = UserID(rawValue: rawID)
                if let source = sources.removeValue(forKey: user) { await media?.removeReceiveStream(ssrc: source) }
                await e2ee.removeParticipant(user)
            }
            if e2eeStarted { try await processE2EE(frame) }
            else {
                try retainEarlyControl(frame)
            }
        }
    }

    /// Writes a complete control under a finite operation deadline without replay.
    /// - Parameter frame: Validated client command.
    /// - Throws: Closure, serialization, cancellation or transport failures.
    private func send(_ frame: VoiceGatewayFrame) async throws {
        guard !stopped, let connection else { throw VoiceControlFailure.closed }
        let logger = DiscordLog.makeLogger("voice.session")
        logger.trace("Voice control write starting", metadata: ["dk.event": "voice.control.write.started", "dk.opcode": .stringConvertible(frame.opcode)])
        try await connection.send(frame.message(limits: limits()), context: context())
        logger.trace("Voice control write completed", metadata: ["dk.event": "voice.control.write.completed", "dk.opcode": .stringConvertible(frame.opcode)])
        guard !stopped else { throw VoiceControlFailure.closed }
    }

    /// Builds a fresh operation deadline so long playback does not inherit an expired one.
    /// - Returns: Session clock with operationTimeout from the current instant.
    private func context() -> TransportContext<C> { .init(clock: clock, deadline: clock.now.advanced(by: configuration.operationTimeout)) }

    /// Bounds every JSON and binary control before state mutation.
    /// - Returns: Whole-frame cap with finite depth/node limits.
    private func limits() -> JSONLimits { .init(maximumBytes: configuration.maximumFrameBytes) }

    /// Retains pre-negotiation authenticated controls under both count and aggregate byte bounds.
    /// - Parameter frame: Early DAVE/member frame whose order must survive Session Description.
    /// - Throws: Closure, capacity or bounded serialization errors before retaining the complete
    ///   frame. A late admitted backend result cannot repopulate the queue after stop clears it.
    private func retainEarlyControl(_ frame: VoiceGatewayFrame) throws {
        guard !stopped else { throw VoiceControlFailure.closed }
        let count: Int
        switch try frame.message(limits: limits()) {
        case .text(let value): count = value.utf8.count
        case .binary(let value): count = value.count
        }
        guard pendingMembership.count < configuration.maximumReceiveStreams,
              count <= configuration.maximumFrameBytes - pendingControlBytes else { throw VoiceSessionFailure.participantCapacity }
        pendingMembership.append(frame); pendingControlBytes += count
        DiscordLog.makeLogger("voice.session").trace("Voice early control retained", metadata: ["dk.event": "voice.control.early.retained",
            "dk.pending": .stringConvertible(pendingMembership.count), "dk.pending_bytes": .stringConvertible(pendingControlBytes)])
    }

    /// Maps reducer phases to fixed semantic metadata without reflecting retained session state.
    /// - Parameter phase: Current pure reducer phase.
    /// - Returns: Stable lifecycle category with no associated session values.
    private nonisolated static func phaseCategory(_ phase: VoiceGatewayPhase) -> String {
        switch phase {
        case .awaitingHello: "awaiting_hello"
        case .identifying: "identifying"
        case .awaitingProtocolSelection: "awaiting_protocol_selection"
        case .awaitingSessionDescription: "awaiting_session_description"
        case .awaitingE2EE: "awaiting_e2ee"
        case .ready: "ready"
        case .reconnecting: "reconnecting"
        case .resuming: "resuming"
        case .closed: "closed"
        }
    }

    /// Classifies terminal failures into a finite vocabulary without rendering adapter errors.
    /// - Parameter error: Original causal failure, which can contain private adapter data.
    /// - Returns: A fixed diagnostic category, independent of error text and payloads.
    private nonisolated static func failureCategory(_ error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        if error as? TransportFailure == .deadlineExceeded { return "deadline" }
        if error is TransportFailure { return "transport" }
        if error is VoiceControlFailure { return "control" }
        if error is VoiceSessionFailure { return "session" }
        return "dependency"
    }

    /// Reserves terminal closure before suspension and shares complete cleanup among all callers.
    /// Resources acquired after stop are closed by their startup guards before ownership transfer.
    private func dispose() async {
        await DiscordLog.$context.withValue(diagnosticContext ?? DiscordLog.context) {
            await disposeOwned()
        }
    }

    /// Releases terminal ownership under the explicit session lifetime diagnostic scope.
    /// All callers share the same cancellation-independent cleanup task.
    private func disposeOwned() async {
        if let cleanup {
            DiscordLog.makeLogger("voice.session").trace("Voice session cleanup shared", metadata: ["dk.event": "voice.session.cleanup.shared"])
            await cleanup.value; return
        }
        DiscordLog.makeLogger("voice.session").debug("Voice session closing", metadata: ["dk.event": "voice.session.closing",
            "dk.rejected_packets": .stringConvertible(rejected), "dk.sources": .stringConvertible(sources.count)])
        stopped = true; state.close(); udpSignal.continuation.finish(); sources.removeAll(); pendingMembership.removeAll(); pendingControlBytes = 0
        let media = media, cipher = cipher, e2ee = e2ee, connection = connection, datagram = datagram
        let playback = playback
        playback?.cancel()
        self.playback = nil
        self.media = nil; self.cipher = nil; self.connection = nil; self.datagram = nil; peer = nil
        let task = Task {
            let logger = DiscordLog.makeLogger("voice.session")
            logger.trace("Voice media ownership releasing", metadata: ["dk.event": "voice.session.cleanup.media"])
            await media?.close()
            _ = await playback?.result
            logger.trace("Voice cryptographic ownership releasing", metadata: ["dk.event": "voice.session.cleanup.crypto"])
            await cipher?.close(); await e2ee.close()
            logger.trace("Voice transport ownership releasing", metadata: ["dk.event": "voice.session.cleanup.transport"])
            await connection?.close(); await datagram?.close()
            logger.debug("Voice owned resources released", metadata: ["dk.event": "voice.session.cleanup.completed"])
        }
        cleanup = task
        await task.value
    }
}
