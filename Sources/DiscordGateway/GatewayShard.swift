import DiscordCore
import DiscordTransport
import Foundation

/// Explicit per-shard resource/time bounds. No constructor launches hidden tasks.
public struct GatewayShardConfiguration: Sendable {
    public let maximumFrameBytes: Int
    public let maximumBufferedEvents: Int
    public let maximumBufferedBytes: Int
    public let maximumReconnectAttempts: Int
    public let helloTimeout: Duration
    public let writeTimeout: Duration
    public let leaseLifetime: Duration
    public let retryBase: Duration
    public let retryMaximum: Duration

    /// Validates finite frame/queue/retry/lease bounds before opening any socket.
    /// - Parameters:
    ///   - maximumFrameBytes: Positive inbound JSON UTF-8 limit, default 1 MiB.
    ///   - maximumBufferedEvents: Positive raw event count limit, default 128.
    ///   - maximumBufferedBytes: Positive total retained wire byte limit, default 4 MiB.
    ///   - maximumReconnectAttempts: Total retries for one run in 0...30, including reconnect
    ///     storms; default five. Zero permits only the original connection attempt.
    ///   - helloTimeout: Positive timeout for connection/Hello, default 15 seconds.
    ///   - writeTimeout: Positive bound on one control write, default ten seconds.
    ///   - leaseLifetime: Lease duration of at least two milliseconds, renewed halfway through;
    ///     default 60 seconds.
    ///   - retryBase: Positive exponential reconnect base, default one second.
    ///   - retryMaximum: Maximum retry delay at least the base, default 30 seconds.
    /// - Throws: `invalidConfiguration` for zero/negative bounds or more than 30 retries.
    public init(maximumFrameBytes: Int = 1_048_576, maximumBufferedEvents: Int = 128,
                maximumBufferedBytes: Int = 4_194_304, maximumReconnectAttempts: Int = 5,
                helloTimeout: Duration = .seconds(15), writeTimeout: Duration = .seconds(10),
                leaseLifetime: Duration = .seconds(60), retryBase: Duration = .seconds(1),
                retryMaximum: Duration = .seconds(30)) throws {
        guard maximumFrameBytes > 0, maximumBufferedEvents > 0, maximumBufferedBytes > 0,
              (0...30).contains(maximumReconnectAttempts), helloTimeout > .zero,
              writeTimeout > .zero, leaseLifetime >= .milliseconds(2),
              retryBase > .zero, retryMaximum >= retryBase else { throw GatewayFailure.invalidConfiguration }
        self.maximumFrameBytes = maximumFrameBytes; self.maximumBufferedEvents = maximumBufferedEvents
        self.maximumBufferedBytes = maximumBufferedBytes; self.maximumReconnectAttempts = maximumReconnectAttempts
        self.helloTimeout = helloTimeout; self.writeTimeout = writeTimeout; self.leaseLifetime = leaseLifetime
        self.retryBase = retryBase; self.retryMaximum = retryMaximum
    }
}

/// Nonsecret operational state; it deliberately excludes token, session ID, URL and payloads.
public struct GatewayShardSnapshot: Sendable {
    public let phase: GatewayPhase
    public let socketGeneration: UInt64
    public let sequence: Int64?
    public let hasResumableSession: Bool
    public let bufferedEvents: Int
    public let bufferedBytes: Int
}

/// Owns one fenced shard's socket/session and bounded raw ingestion queue.
///
/// `run` supervises receive, heartbeat, authentication and lease renewal as structured
/// children. Control handling never calls user code. Consumers synchronously poll batches;
/// overflow terminates the run and requires resynchronization rather than silently dropping.
/// Only JSON/uncompressed Gateway v10 control is implemented; full event/request catalogs,
/// outgoing application commands, compression and broadcast subscriptions are separate work.
public actor GatewayShard<C: Clock, Leases: ShardLeaseStore> where C.Duration == Duration, Leases.LeaseClock == C {
    public let identity: ShardIdentity
    private let token: BotToken
    private let intents: UInt64
    private let initialURL: URL
    private let transport: any WebSocketTransport
    private let clock: C
    private let leases: Leases
    private let startup: any GatewayStartupCoordinator
    private let configuration: GatewayShardConfiguration
    private let random: @Sendable () -> Double
    private let owner: UUID
    private var state = GatewaySessionState()
    private var running = false
    private var generation: UInt64 = 0
    private var connection: (any WebSocketConnection)?
    private var lease: ShardLease<C>?
    private var sessionID: String?
    private var resumeURL: URL?
    private var sequence: Int64?
    private var heartbeatPending = false
    private var events: [GatewayEvent] = []
    private var bufferedBytes = 0

    /// Stores a complete injected shard runtime without performing I/O.
    /// - Parameters:
    ///   - identity: Validated fixed-topology shard; changing topology requires drain and a new instance.
    ///   - token: Redacted bot credential; exposed only while encoding Identify/Resume for trusted origins.
    ///   - intents: Explicit Discord intents; privileged intents require portal configuration/review.
    ///   - discovery: Current authenticated discovery snapshot; its URL is origin validated.
    ///   - transport: Qualified injected WebSocket adapter; session capability enables resumable aborts/codes.
    ///   - clock: Monotonic clock shared with the lease store.
    ///   - leases: Shared injectable ownership store, failing closed on outages or expired fences.
    ///   - startup: Shared per-credential atomic Identify budget, also shared across topology generations.
    ///   - configuration: Finite bounds/timeouts validated before construction.
    ///   - owner: Fresh nonsecret worker ID; defaults to a random UUID.
    ///   - random: Independent jitter sample; values are clamped to 0...1 and nonfinite samples become 0.5.
    public init(identity: ShardIdentity, token: BotToken, intents: UInt64, discovery: GatewayDiscovery,
                transport: any WebSocketTransport, clock: C, leases: Leases,
                startup: any GatewayStartupCoordinator, configuration: GatewayShardConfiguration,
                owner: UUID = UUID(), random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) {
        self.identity = identity; self.token = token; self.intents = intents; initialURL = discovery.url
        self.transport = transport; self.clock = clock; self.leases = leases; self.startup = startup
        self.configuration = configuration; self.owner = owner; self.random = random
    }

    /// Runs until explicit stop, cancellation, exhausted retries or a terminal failure.
    ///
    /// A single run is allowed per instance. Cleanup closes the active socket, awaits
    /// all children, discards queued events/session state and releases the latest lease.
    /// Session-aware adapters preserve resumable sessions across reconnect; ordinary
    /// adapters use conservative fresh Identify after their graceful close.
    /// - Throws: Cancellation, ownership/coordinator failures, fatal close, malformed control,
    ///   overflow or bounded retry exhaustion. Unknown injected errors become the fixed
    ///   `coordinatorUnavailable` category so dependency text cannot expose credentials.
    ///   Remote release failure takes precedence over a prior run error so uncertain handoff is visible.
    public func run() async throws {
        guard !running, state.phase == .disconnected else { throw GatewayFailure.alreadyRunning }
        try Task.checkCancellation()
        running = true
        var runFailure: (any Error)?
        do {
            let acquired = try await leases.acquire(identity, owner: owner, lifetime: configuration.leaseLifetime)
            lease = acquired
            guard running else { throw CancellationError() }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.connectionLoop() }
                group.addTask { try await self.ownershipLoop() }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch { runFailure = safeGatewayFailure(error) }
        // A failed remote release is observable even when the original run also failed.
        // Until expiry, an external coordinator may still retain the ownership record.
        try await finish()
        if let runFailure { throw runFailure }
    }

    /// Requests controlled drain/handoff; closing unblocks receive before `run` finishes cleanup.
    /// Repeated stops are harmless. The caller should await its run task before handing off topology.
    /// Stopping a never-started instance permanently transitions it to stopped without acquiring a lease.
    public func stop() async {
        let neverStarted = !running && state.phase == .disconnected
        running = false
        if state.phase != .stopped, state.phase != .draining { _ = try? state.apply(.drain) }
        await connection?.close()
        if neverStarted { _ = try? state.apply(.closed) }
    }

    /// Returns a nonsecret snapshot without suspending or running handlers.
    /// - Returns: Current lifecycle/generation/sequence and bounded event accounting.
    public func snapshot() -> GatewayShardSnapshot {
        GatewayShardSnapshot(phase: state.phase, socketGeneration: generation, sequence: sequence,
            hasResumableSession: sessionID != nil && sequence != nil && resumeURL != nil,
            bufferedEvents: events.count, bufferedBytes: bufferedBytes)
    }

    /// Removes the oldest bounded batch in shard ingestion order without waiting for new events.
    /// - Parameter maximum: Positive maximum event count; default 64. Nonpositive values return empty.
    /// - Returns: Up to `maximum` queued events, possibly empty; no global or exactly-once ordering is promised.
    public func drainEvents(maximum: Int = 64) -> [GatewayEvent] {
        guard maximum > 0 else { return [] }
        let count = min(maximum, events.count)
        let result = Array(events.prefix(count))
        events.removeFirst(count)
        bufferedBytes -= result.reduce(0) { $0 + $1.byteCount }
        return result
    }

    /// Owns sequential socket generations and a finite reconnect budget for the whole run.
    /// - Throws: Cancellation or terminal protocol/ownership failures; transient errors consume retries.
    private func connectionLoop() async throws {
        var retries = 0
        while running {
            try Task.checkCancellation()
            guard generation < UInt64.max else { throw GatewayFailure.staleGeneration }
            generation += 1
            let active = generation
            _ = try state.apply(.start)
            do {
                try await fence(active)
                let request = HTTPRequest(method: "GET", url: resumeURL ?? initialURL)
                let socket = try await transport.connectWebSocket(request, context:
                    TransportContext(clock: clock, deadline: clock.now.advanced(by: configuration.helloTimeout)))
                guard running, generation == active else { await socket.close(); return }
                connection = socket
                try await fence(active)
                _ = try state.apply(.connected)
                try await supervise(socket, generation: active)
                throw GatewayFailure.disconnected
            } catch {
                let socket = connection
                let code = await (socket as? any WebSocketSessionConnection)?.peerCloseCode()
                if let resumable = socket as? any WebSocketSessionConnection {
                    await resumable.closeForReconnect()
                } else {
                    await socket?.close()
                    clearSession()
                }
                connection = nil
                heartbeatPending = false
                if !running { return }
                try Task.checkCancellation()
                if GatewayCloseDisposition.classify(code) == .fatal { throw GatewayFailure.fatalClose(code!) }
                if GatewayCloseDisposition.classify(code) == .identify { clearSession() }
                if error is ShardOwnershipFailure || error is JSONValueError { throw error }
                if let failure = error as? GatewayFailure {
                    switch failure {
                    case .invalidConfiguration, .invalidPayload, .unsupportedEncoding, .eventCapacityExceeded,
                         .startupRefreshRequired, .coordinatorUnavailable, .fatalClose, .staleGeneration: throw failure
                    default: break
                    }
                }
                guard retries < configuration.maximumReconnectAttempts else { throw GatewayFailure.retryLimitExceeded }
                _ = try state.apply(.reconnect)
                var cap = configuration.retryBase
                for _ in 0..<retries {
                    if cap >= configuration.retryMaximum / 2 { cap = configuration.retryMaximum; break }
                    cap *= 2
                }
                retries += 1
                try await clock.sleep(for: cap * jitter())
            }
        }
    }

    /// Reads Hello before supervising independent receive, heartbeat and authentication children.
    /// - Parameters:
    ///   - socket: Current generation's established connection.
    ///   - generation: Fence captured before any suspension.
    /// - Throws: Child/transport failures after cancelling and awaiting all siblings.
    private func supervise(_ socket: any WebSocketConnection, generation active: UInt64) async throws {
        guard let message = try await socket.receive(context: TransportContext(clock: clock,
            deadline: clock.now.advanced(by: configuration.helloTimeout))) else { throw GatewayFailure.disconnected }
        try await fence(active)
        let hello = try GatewayEnvelope(message, maximumBytes: configuration.maximumFrameBytes)
        guard hello.opcode == 10, case .object(let data) = hello.data,
              case .number(let value) = data["heartbeat_interval"], let milliseconds = Int64(value.rawValue),
              milliseconds > 0, milliseconds <= 3_600_000 else { throw GatewayFailure.invalidPayload }
        let interval = Duration.milliseconds(milliseconds)
        let resume = sessionID != nil && resumeURL != nil && sequence != nil
        _ = try state.apply(.hello(resumable: resume))
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { try await self.receiveLoop(socket, generation: active); return true }
            group.addTask { try await self.heartbeatLoop(interval: interval, generation: active); return true }
            group.addTask { try await self.authenticate(resuming: resume, generation: active); return false }
            defer { group.cancelAll() }
            // Authentication is finite; a stopped control loop cancels its sleeping sibling immediately.
            for try await stopped in group { if stopped { break } }
        }
    }

    /// Receives controls independently of all event consumers and user handlers.
    /// - Parameters:
    ///   - socket: Current generation's sole read owner.
    ///   - generation: Captured fence; every completion is validated before state mutation.
    /// - Throws: Protocol, capacity, ownership, disconnect or adapter errors.
    private func receiveLoop(_ socket: any WebSocketConnection, generation active: UInt64) async throws {
        while running {
            guard let message = try await socket.receive(context: TransportContext(clock: clock)) else {
                throw GatewayFailure.disconnected
            }
            try await fence(active)
            let envelope = try GatewayEnvelope(message, maximumBytes: configuration.maximumFrameBytes)
            switch envelope.opcode {
            case 0:
                guard let next = envelope.sequence, let name = envelope.name else { throw GatewayFailure.invalidPayload }
                if let sequence, next <= sequence { continue }
                if name == "READY" {
                    guard case .object(let data) = envelope.data,
                          case .string(let session) = data["session_id"], !session.isEmpty,
                          case .string(let url) = data["resume_gateway_url"] else { throw GatewayFailure.invalidPayload }
                    let validated = try gatewayURL(url)
                    _ = try state.apply(.ready)
                    sessionID = session; resumeURL = validated
                } else if name == "RESUMED" { _ = try state.apply(.ready) }
                sequence = next
                try append(envelope)
            case 1: try await sendHeartbeat(generation: active, scheduled: false)
            case 7: throw GatewayFailure.reconnectRequested
            case 9:
                guard case .bool(let resumable) = envelope.data else { throw GatewayFailure.invalidPayload }
                if !resumable { clearSession() }
                throw GatewayFailure.reconnectRequested
            case 11: heartbeatPending = false
            case 10: throw GatewayFailure.invalidPayload
            default: try append(envelope)
            }
        }
    }

    /// Schedules jittered first and fixed subsequent heartbeats independently of ingestion/handlers.
    /// - Parameters:
    ///   - interval: Validated server interval, strictly positive and at most one hour.
    ///   - generation: Socket fence protecting all timer completions.
    /// - Throws: Missing ACK before the next scheduled beat, cancellation or send/ownership failures.
    private func heartbeatLoop(interval: Duration, generation active: UInt64) async throws {
        var deadline = clock.now.advanced(by: interval * jitter())
        while running {
            try await clock.sleep(until: deadline, tolerance: nil)
            try await sendHeartbeat(generation: active, scheduled: true)
            deadline = clock.now.advanced(by: interval)
        }
    }

    /// Sends a heartbeat immediately; requested beats do not reset the periodic schedule.
    /// - Parameters:
    ///   - generation: Socket generation to validate before and after sends.
    ///   - scheduled: Whether to monitor the prior scheduled beat; requested beats do not
    ///     create a premature ACK deadline when they arrive just before a periodic timer.
    /// - Throws: `missedHeartbeatACK`, cancellation, authority loss or adapter write errors.
    private func sendHeartbeat(generation active: UInt64, scheduled: Bool) async throws {
        try await fence(active)
        if scheduled {
            if heartbeatPending { throw GatewayFailure.missedHeartbeatACK }
            heartbeatPending = true
        }
        try await send(opcode: 1, data: sequence.map(gatewayNumber) ?? .null, generation: active)
    }

    /// Obtains shared Identify allowance, or resumes without consuming startup quota.
    /// - Parameters:
    ///   - resuming: Whether Hello found a complete retained session.
    ///   - generation: Captured socket fence; waiting does not block receive/heartbeat.
    /// - Throws: Coordinator, cancellation, lost authority, payload size or adapter write errors.
    private func authenticate(resuming: Bool, generation active: UInt64) async throws {
        if resuming, let sessionID, let sequence {
            let payload = token.withUnsafeValue { token in JSONValue.object([
                "token": .string(token), "session_id": .string(sessionID), "seq": gatewayNumber(sequence)]) }
            try await send(opcode: 6, data: payload, generation: active)
            return
        }
        while true {
            try await fence(active)
            let admission: GatewayStartAdmission
            do { admission = try await startup.reserveIdentify(for: identity) }
            catch { throw safeGatewayFailure(error) }
            try await fence(active)
            switch admission {
            case .admitted:
                let payload = token.withUnsafeValue { token in JSONValue.object([
                    "token": .string(token), "intents": gatewayNumber(intents),
                    "shard": .array([gatewayNumber(identity.index), gatewayNumber(identity.count)]),
                    "properties": .object(["os": .string("portable"), "browser": .string("DiscordKit"),
                                           "device": .string("DiscordKit")])]) }
                try await send(opcode: 2, data: payload, generation: active)
                return
            case .wait(let duration):
                guard duration > .zero else { throw GatewayFailure.invalidConfiguration }
                try await clock.sleep(for: duration)
            }
        }
    }

    /// Sends one bounded control payload through the adapter's serialized write lane.
    /// - Parameters:
    ///   - opcode: Implemented control opcode (Identify, Resume or Heartbeat).
    ///   - data: Exact JSON payload, possibly containing the token; never logged.
    ///   - generation: Socket fence rechecked around every suspension.
    /// - Throws: Authority, cancellation, 4096-byte outbound limit or adapter/deadline failures.
    private func send(opcode: Int, data: JSONValue, generation active: UInt64) async throws {
        try await fence(active)
        guard let socket = connection else { throw GatewayFailure.disconnected }
        let bytes = try JSONValue.object(["op": gatewayNumber(opcode), "d": data])
            .serialized(limits: JSONLimits(maximumBytes: 4_096))
        try await socket.send(.text(String(decoding: bytes, as: UTF8.self)), context:
            TransportContext(clock: clock, deadline: clock.now.advanced(by: configuration.writeTimeout)))
        try await fence(active)
    }

    /// Fails closed before sends and before accepting any asynchronous completion.
    /// - Parameter generation: Captured socket generation; replacement work is always rejected.
    /// - Throws: Cancellation, stale generation, expired/replaced lease or coordinator failure.
    private func fence(_ active: UInt64) async throws {
        while true {
            try Task.checkCancellation()
            guard running, generation == active, let ticket = lease else { throw GatewayFailure.staleGeneration }
            do { try await leases.validate(ticket) }
            catch {
                if lease?.generation != ticket.generation { continue }
                throw safeGatewayFailure(error)
            }
            guard running, generation == active else { throw GatewayFailure.staleGeneration }
            if lease?.generation == ticket.generation { return }
        }
    }

    /// Renews ownership halfway through each lease; failures terminate supervised socket work.
    /// - Throws: Cancellation or lease-store errors; the public run boundary preserves known
    ///   closed errors and sanitizes arbitrary dependency failures to coordinator unavailability.
    private func ownershipLoop() async throws {
        while running {
            try await clock.sleep(for: configuration.leaseLifetime / 2)
            try Task.checkCancellation()
            guard running, let ticket = lease else { return }
            let renewed = try await leases.renew(ticket, lifetime: configuration.leaseLifetime)
            guard running else { try await leases.release(renewed); return }
            lease = renewed
        }
    }

    /// Appends one frame only after both queue bounds pass, preserving per-shard order.
    /// - Parameter envelope: Validated event or unknown opcode; controls are not queued.
    /// - Throws: `eventCapacityExceeded` atomically before exceeding either bound.
    private func append(_ envelope: GatewayEnvelope) throws {
        guard events.count < configuration.maximumBufferedEvents,
              envelope.byteCount <= configuration.maximumBufferedBytes - bufferedBytes else {
            throw GatewayFailure.eventCapacityExceeded
        }
        events.append(GatewayEvent(shard: identity, envelope: envelope)); bufferedBytes += envelope.byteCount
    }

    /// Discards invalid or unsupported resumable state without changing queued event history.
    private func clearSession() { sessionID = nil; resumeURL = nil; sequence = nil }

    /// Produces a bounded jitter fraction, tolerating faulty injected random sources.
    /// - Returns: Finite value in 0...1, with 0.5 substituted for NaN/infinity.
    private func jitter() -> Double {
        let value = random()
        return value.isFinite ? min(1, max(0, value)) : 0.5
    }

    /// Completes stop/error cleanup after all structured children have exited.
    /// Socket ownership is cleared before suspension; the latest lease is released once.
    /// - Throws: Known closed release failure, or fixed coordinator unavailability for unknown
    ///   errors, after local cleanup; callers must wait for lease
    ///   expiry or repair coordination before assuming handoff authority became available.
    private func finish() async throws {
        running = false
        let socket = connection; connection = nil
        await socket?.close()
        var releaseFailure: (any Error)?
        if let ticket = lease {
            lease = nil
            do { try await leases.release(ticket) } catch { releaseFailure = safeGatewayFailure(error) }
        }
        events.removeAll(); bufferedBytes = 0; heartbeatPending = false; clearSession()
        if state.phase == .draining { _ = try? state.apply(.closed) }
        else if state.phase != .stopped { _ = try? state.apply(.fatal) }
        if let releaseFailure { throw releaseFailure }
    }
}

/// Runs a finite fixed-topology shard subset as structured sibling tasks.
public struct GatewayBot<C: Clock, Leases: ShardLeaseStore>: Sendable where C.Duration == Duration, Leases.LeaseClock == C {
    public let shards: [GatewayShard<C, Leases>]

    /// Validates aggregate session bounds and one consistent topology before launch.
    /// - Parameters:
    ///   - shards: Unique actors sharing bot/count/generation; an empty subset is permitted.
    ///   - maximumShards: Positive local active-session limit, default 256.
    /// - Throws: `invalidConfiguration` for duplicates, mixed topology or exceeded capacity.
    public init(shards: [GatewayShard<C, Leases>], maximumShards: Int = 256) throws {
        guard maximumShards > 0, shards.count <= maximumShards else { throw GatewayFailure.invalidConfiguration }
        let identities = shards.map(\.identity)
        guard Set(identities).count == identities.count else { throw GatewayFailure.invalidConfiguration }
        if let first = identities.first {
            guard identities.allSatisfy({ $0.botID == first.botID && $0.count == first.count
                && $0.topologyGeneration == first.topologyGeneration }) else { throw GatewayFailure.invalidConfiguration }
        }
        self.shards = shards
    }

    /// Supervises all selected shards; one failure cancels and awaits every sibling's cleanup.
    /// - Throws: First observed shard failure or cancellation after owned resources are released.
    public func run() async throws {
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for shard in shards { group.addTask { try await shard.run() } }
            defer { group.cancelAll() }
            for try await _ in group {}
        }
    }

    /// Requests concurrent drain for the finite subset; await `run` for completed ownership release.
    public func stop() async {
        await withTaskGroup(of: Void.self) { group in
            for shard in shards { group.addTask { await shard.stop() } }
        }
    }
}
