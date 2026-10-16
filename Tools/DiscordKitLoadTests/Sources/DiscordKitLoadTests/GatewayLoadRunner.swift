import DiscordCore
import DiscordGateway
import DiscordTransport
import Foundation

/// Scripted local Gateway evidence; logical users are separate from the bounded selected session subset.
struct GatewayLoadReport: Codable, Sendable {
    let profile: String
    let logicalAccounts: Int
    let profileBotIdentities: Int
    let selectedBotIdentities: Int
    let selectedShards: Int
    let targetDispatches: Int
    let deliveredDispatches: Int
    let reconnects: Int
    let identifies: Int
    let resumes: Int
    let heartbeats: Int
    let heartbeatACKs: Int
    let startupStormOffered: Int
    let startupStormAdmitted: Int
    let sampledPeakQueuedEvents: Int
    let configuredMaximumQueuedEvents: Int
    let configuredMaximumQueuedBytes: Int
    let peakOwnedConnections: Int
    let ownedConnectionsAfterShutdown: Int
    let leasesAfterShutdown: Int
    let controlDelay: LatencySummary
    let eventLag: LatencySummary
    let durationSeconds: Double
    let cpuSeconds: Double
    let meanCPUPercentOfOneCore: Double
    let before: ProcessSample
    let afterShutdown: ProcessSample
    let notes: [String]
}

/// Measures structured shard lifecycle, startup contention and slow bounded ingestion without sockets.
struct GatewayLoadRunner: Sendable {
    /// Loads one existing logical profile and runs its bounded selected Gateway subset.
    /// - Parameters:
    ///   - profileName: Safe repository-owned profile basename.
    ///   - burst: Whether to offer tenfold startup contention and double event credits.
    /// - Returns: JSON-encodable CPU/RSS/control/event evidence with complete ownership cleanup.
    /// - Throws: Profile, protocol, cancellation, ownership or unexpected scripted failures.
    func run(profileName: String, burst: Bool) async throws -> GatewayLoadReport {
        let profile = try WorkloadProfile.load(name: profileName,
            directory: LoadPaths.packageDirectory.appendingPathComponent("Profiles"))
        return try await run(profile: profile, burst: burst)
    }

    /// Runs a bounded local session subset with a synthetic reconnect per shard and credit-limited dispatches.
    ///
    /// The producer credit limit models bounded upstream demand, while consumers deliberately yield
    /// between batches. This measures lifecycle/control isolation; it does not measure network I/O,
    /// unbounded ingress, production scheduling, real Discord quotas or distributed coordination.
    /// - Parameters:
    ///   - profile: Validated served-user profile; at most 64 configured shards are selected.
    ///   - burst: Multiplies isolated startup-storm offers by ten and event credits by two.
    /// - Returns: Measurements retaining at most 4,096 latency samples in each category.
    /// - Throws: Invalid profile, cancellation, unexpected stream failure or owned cleanup failure.
    func run(profile: WorkloadProfile, burst: Bool) async throws -> GatewayLoadReport {
        try profile.validate()
        guard profile.shards <= 64 else { throw LoadFailure.invalidProfile }
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let before = ProcessSample.capture(), started = clock.now
        let shardCount = profile.shards
        let botCount = min(4, max(1, shardCount / 2))
        guard shardCount % botCount == 0 else { throw LoadFailure.invalidProfile }
        let perBot = shardCount / botCount
        let totalEvents = min(profile.requests, 100_000)
        guard totalEvents >= shardCount else { throw LoadFailure.invalidProfile }
        let metrics = GatewayLoadMetrics()
        let leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: shardCount)
        var shards: [GatewayShard<ContinuousClock, InProcessShardLeaseStore<ContinuousClock>>] = []
        var feeds: [GatewayLoadFeed] = []
        for bot in 0..<botCount {
            let botID = UserID(rawValue: UInt64(bot + 1))
            let discovery = try GatewayDiscovery(json: JSONValue.parse("""
            {"url":"wss://gateway.discord.gg/","shards":\(perBot),"session_start_limit":
            {"total":\(perBot * 2),"remaining":\(perBot * 2),"reset_after":86400000,"max_concurrency":\(perBot)}}
            """))
            let startup = InProcessGatewayStartupCoordinator(botID: botID, limit: discovery.sessionStartLimit, clock: clock)
            for index in 0..<perBot {
                let ordinal = bot * perBot + index
                let count = totalEvents / shardCount + (ordinal < totalEvents % shardCount ? 1 : 0)
                let feed = GatewayLoadFeed(target: count, credits: burst ? 16 : 8,
                    payloadBytes: min(profile.payloadBytes, 1_024), metrics: metrics)
                feeds.append(feed)
                let shard = GatewayShard(identity: try ShardIdentity(botID: botID, topologyGeneration: 0, index: index, count: perBot),
                    token: try BotToken("synthetic-local-only"), intents: 1, discovery: discovery,
                    transport: GatewayLoadTransport(feed: feed, metrics: metrics), clock: clock,
                    leases: leases, startup: startup, configuration: try GatewayShardConfiguration(
                        maximumBufferedEvents: 32, maximumBufferedBytes: 65_536,
                        maximumReconnectAttempts: 1, leaseLifetime: .seconds(60)), random: { 0 })
                shards.append(shard)
            }
        }
        let stormOffers = shardCount * (burst ? 10 : 2)
        let storm = try InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 9_999),
            limit: GatewaySessionStartLimit(total: shardCount, remaining: shardCount,
                resetAfter: .seconds(60), maxConcurrency: shardCount), clock: clock)
        let stormAdmissions = try await withThrowingTaskGroup(of: Int.self) { group in
            for ordinal in 0..<stormOffers {
                group.addTask {
                    let key = try ShardIdentity(botID: UserID(rawValue: 9_999), topologyGeneration: UInt64(ordinal),
                        index: ordinal % shardCount, count: shardCount)
                    return try await storm.reserveIdentify(for: key) == .admitted ? 1 : 0
                }
            }
            var result = 0
            for try await count in group { result += count }
            return result
        }
        let selectedShards = shards, selectedFeeds = feeds
        try await withThrowingTaskGroup(of: Void.self) { group in
            for shard in selectedShards { group.addTask { try await shard.run() } }
            group.addTask {
                try await withThrowingTaskGroup(of: Void.self) { consumers in
                    for ordinal in selectedShards.indices {
                        consumers.addTask {
                            let shard = selectedShards[ordinal], feed = selectedFeeds[ordinal]
                            while await feed.deliveredCount() < feed.target {
                                try Task.checkCancellation()
                                for _ in 0..<32 { await Task.yield() }
                                let snapshot = await shard.snapshot()
                                await metrics.observeQueue(snapshot.bufferedEvents)
                                let batch = await shard.drainEvents(maximum: 8)
                                try await feed.consume(batch)
                            }
                        }
                    }
                    defer { consumers.cancelAll() }
                    for try await _ in consumers {}
                }
                for shard in selectedShards { await shard.stop() }
            }
            defer { group.cancelAll() }
            for try await _ in group {}
        }
        let elapsed = Self.seconds(started.duration(to: clock.now))
        let after = ProcessSample.capture(), values = await metrics.snapshot()
        let leaseCount = await leases.retainedLeaseCount()
        return GatewayLoadReport(profile: profile.name, logicalAccounts: profile.logicalAccounts,
            profileBotIdentities: profile.botIdentities, selectedBotIdentities: botCount, selectedShards: shardCount,
            targetDispatches: totalEvents, deliveredDispatches: values.dispatches,
            reconnects: values.resumes, identifies: values.identifies, resumes: values.resumes,
            heartbeats: values.heartbeats, heartbeatACKs: values.acks,
            startupStormOffered: stormOffers, startupStormAdmitted: stormAdmissions,
            sampledPeakQueuedEvents: values.peakQueue, configuredMaximumQueuedEvents: shardCount * 32,
            configuredMaximumQueuedBytes: shardCount * 65_536, peakOwnedConnections: values.peakConnections,
            ownedConnectionsAfterShutdown: values.connections, leasesAfterShutdown: leaseCount,
            controlDelay: LatencySummary.summarize(values.control), eventLag: LatencySummary.summarize(values.lag),
            durationSeconds: elapsed, cpuSeconds: max(0, after.cpuSeconds - before.cpuSeconds),
            meanCPUPercentOfOneCore: elapsed > 0 ? max(0, after.cpuSeconds - before.cpuSeconds) / elapsed * 100 : 0,
            before: before, afterShutdown: after,
            notes: ["Scripted local-only JSON Gateway; zero sockets and no real credential or Discord request.",
                "Logical served users and configured bot identities are separate from selected measured sessions.",
                "One reconnect per selected shard exercises Resume without additional Identify allowance.",
                "An isolated synthetic identity measures startup contention without resetting runtime budgets.",
                "Consumers yield between batches; producer credits bound source demand and pending timestamp metadata.",
                "Queue peaks are per-shard sampled maxima; configured aggregate ceilings include every selected shard.",
                "CPU/RSS are process measurements; allocator/parser overhead is outside wire-byte accounting.",
                "This evidence does not qualify network throughput, real Discord quotas, fleet behavior or runtime capacity."])
    }

    /// Converts a bounded monotonic duration to report seconds without wall-clock arithmetic.
    /// - Parameter duration: Nonnegative elapsed process measurement.
    /// - Returns: Floating-point seconds.
    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Single-waiter cancellation-aware signal; one current generation is retained per feed.
private actor GatewayLoadSignal {
    private var opened = false
    private var waiter: (UUID, CheckedContinuation<Void, any Error>)?

    /// Suspends until opened, with cancellation removing the sole continuation.
    /// - Throws: Cancellation or invalid concurrent waiter use in the local script.
    func wait() async throws {
        try Task.checkCancellation()
        if opened { return }
        guard waiter == nil else { throw LoadFailure.unexpectedResponse }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter = (id,$0) }
        } onCancel: { Task { await self.cancel(id) } }
    }

    /// Opens permanently, releasing an optional pending waiter exactly once.
    func open() { opened = true; let pending = waiter; waiter = nil; pending?.1.resume() }

    /// Removes a cancelled registration without affecting a replacement generation.
    /// - Parameter id: Exact waiter generation registered by the cancelled operation.
    private func cancel(_ id: UUID) {
        guard waiter?.0 == id else { return }
        let pending = waiter; waiter = nil; pending?.1.resume(throwing: CancellationError())
    }
}

/// Shared bounded counters and latency prefixes, with no credential/session diagnostic labels.
private actor GatewayLoadMetrics {
    struct Values: Sendable {
        var identifies = 0, resumes = 0, heartbeats = 0, acks = 0, dispatches = 0
        var connections = 0, peakConnections = 0, peakQueue = 0
        var control: [Double] = [], lag: [Double] = []
    }
    private var values = Values()

    /// Adjusts owned sockets; the maximum is measured rather than inferred from logical users.
    /// - Parameter change: One on upgrade, negative one on idempotent close.
    func connection(_ change: Int) { values.connections += change; values.peakConnections = max(values.peakConnections, values.connections) }

    /// Records one implemented outgoing opcode without retaining its token-bearing JSON.
    /// - Parameter opcode: Identify, Resume or Heartbeat control.
    func outgoing(_ opcode: Int) {
        if opcode == 2 { values.identifies += 1 }
        if opcode == 6 { values.resumes += 1 }
        if opcode == 1 { values.heartbeats += 1 }
    }

    /// Records an ACK delivered to the receive loop independently of consumer credits.
    func ack() { values.acks += 1 }

    /// Records an application event consumed by the deliberately yielding consumer.
    /// - Parameter milliseconds: Time from local frame generation to ingestion-queue drain.
    func dispatch(_ milliseconds: Double) { values.dispatches += 1; if values.lag.count < 4_096 { values.lag.append(milliseconds) } }

    /// Records server-requested heartbeat response time without including periodic heartbeats.
    /// - Parameter milliseconds: Local requested-beat-to-control-send delay.
    func control(_ milliseconds: Double) { if values.control.count < 4_096 { values.control.append(milliseconds) } }

    /// Samples one shard's queue depth; configured aggregate ceilings are reported separately.
    /// - Parameter count: Nonnegative raw event count from a shard snapshot.
    func observeQueue(_ count: Int) { values.peakQueue = max(values.peakQueue, count) }

    /// Copies bounded counters/sample prefixes after all runtime tasks have exited.
    /// - Returns: Final process-local workload accounting.
    func snapshot() -> Values { values }
}

/// One shard's event source shared across reconnect generations, bounded by producer credits.
private actor GatewayLoadFeed {
    let target: Int
    let payload: String
    let metrics: GatewayLoadMetrics
    var sequence: Int64 = 0
    var generated = 0, delivered = 0, credits: Int
    var reconnected = false
    var timestamps: [Int64: ContinuousClock.Instant] = [:]
    var signal = GatewayLoadSignal()

    /// Configures a finite dispatch source; payload bytes and unconsumed metadata remain bounded.
    /// - Parameters:
    ///   - target: Positive total application events for this shard.
    ///   - credits: Positive maximum undrained application events.
    ///   - payloadBytes: Nonnegative synthetic ASCII bytes per event, at most 1,024.
    ///   - metrics: Shared bounded measurement accumulator.
    init(target: Int, credits: Int, payloadBytes: Int, metrics: GatewayLoadMetrics) {
        self.target = target; self.credits = credits; payload = String(repeating: "x", count: payloadBytes); self.metrics = metrics
    }

    /// Reports how many application events the consumer has actually drained.
    /// - Returns: Monotonic count in zero through target.
    func deliveredCount() -> Int { delivered }

    /// Generates one sequence for READY/RESUMED without consuming application credits.
    /// - Returns: Strictly increasing session dispatch sequence.
    func controlSequence() -> Int64 { sequence += 1; return sequence }

    /// Reserves a single simulated reconnect around the midpoint of this shard's workload.
    /// - Returns: Whether this receive should emit opcode seven.
    func shouldReconnect() -> Bool {
        guard !reconnected, generated >= target / 2 else { return false }
        reconnected = true; return true
    }

    /// Generates an event only within the bounded outstanding source-credit allowance.
    /// - Returns: Sequence and payload, or nil while all credits are held by the consumer.
    func nextEvent() -> (Int64,String)? {
        guard generated < target, credits > 0 else { return nil }
        generated += 1; credits -= 1; sequence += 1
        timestamps[sequence] = ContinuousClock().now
        return (sequence,payload)
    }

    /// Returns the current generation's source wakeup for credits, ACKs or closure.
    /// - Returns: One-shot signal; a caller always rechecks conditions after waking.
    func wakeup() -> GatewayLoadSignal { signal }

    /// Replaces the wake generation after state change, unblocking the prior reader if necessary.
    func wake() async { let previous = signal; signal = GatewayLoadSignal(); await previous.open() }

    /// Removes delivered timestamps, replenishes exact application credits and records queue lag.
    /// - Parameter events: Bounded batch drained from this shard's ingestion queue.
    /// - Throws: Unknown sequence/count violations indicating a broken fixture or lost/duplicate dispatch.
    func consume(_ events: [GatewayEvent]) async throws {
        for event in events where event.name == "LOAD_EVENT" {
            guard let sequence = event.sequence, let stamp = timestamps.removeValue(forKey: sequence) else {
                throw LoadFailure.unexpectedResponse
            }
            delivered += 1; credits += 1
            let duration = stamp.duration(to: ContinuousClock().now)
            await metrics.dispatch(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        if !events.isEmpty { await wake() }
    }
}

/// Scripted transport returns a new owned session socket for every reconnect generation.
private struct GatewayLoadTransport: WebSocketTransport {
    let feed: GatewayLoadFeed
    let metrics: GatewayLoadMetrics

    /// Opens a counted in-memory socket after validating cancellation/deadline and trusted URL shape.
    /// - Parameters:
    ///   - request: Versioned Gateway URL; no network request is performed.
    ///   - context: Runtime's injected monotonic startup deadline.
    /// - Returns: New session-aware script connection sharing this shard's finite source.
    /// - Throws: Cancellation/deadline or invalid script request.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        guard request.url.scheme == "wss" else { throw LoadFailure.invalidArguments }
        await metrics.connection(1)
        return GatewayLoadSocket(feed: feed, metrics: metrics)
    }
}

/// Receives script controls independently of source credits; no user callback blocks ACK processing.
private actor GatewayLoadSocket: WebSocketSessionConnection {
    let feed: GatewayLoadFeed
    let metrics: GatewayLoadMetrics
    var hello = false, authenticated = false, ready = false, resuming = false, closed = false
    var acks = 0, applicationFrames = 0
    var requestedAt: ContinuousClock.Instant?

    /// Takes ownership of a counted scripted connection without launching background work.
    /// - Parameters:
    ///   - feed: Finite shard source shared through resume generations.
    ///   - metrics: Shared counters released by idempotent close.
    init(feed: GatewayLoadFeed, metrics: GatewayLoadMetrics) { self.feed = feed; self.metrics = metrics }

    /// Parses only outgoing control opcode and records bounded response delay, discarding token fields.
    /// - Parameters:
    ///   - message: Runtime-generated bounded text control frame.
    ///   - context: Cancellation/deadline for the send.
    /// - Throws: Context failure, closure or malformed synthetic control.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        guard case .text(let text) = message, case .object(let root) = try JSONValue.parse(text),
              case .number(let op) = root["op"], let opcode = Int(op.rawValue) else { throw LoadFailure.unexpectedResponse }
        if opcode == 2 || opcode == 6 { authenticated = true; resuming = opcode == 6 }
        if opcode == 1 {
            acks = min(2, acks + 1)
            if let requestedAt {
                let duration = requestedAt.duration(to: ContinuousClock().now)
                await metrics.control(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
                self.requestedAt = nil
            }
        }
        await metrics.outgoing(opcode)
        await feed.wake()
    }

    /// Produces Hello/auth dispatch, priority ACK/requested beat, one reconnect and credited events.
    /// - Parameter context: Cancellation/deadline for this sole pull reader.
    /// - Returns: Finite uncompressed JSON frames, or EOF after explicit close.
    /// - Throws: Cancellation, deadline or local script invariant failure.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        while true {
            try context.check()
            if closed { return nil }
            if !hello { hello = true; return .text(#"{"op":10,"d":{"heartbeat_interval":1000}}"#) }
            if acks > 0 { acks -= 1; await metrics.ack(); return .text(#"{"op":11,"d":null}"#) }
            if authenticated && !ready {
                ready = true
                let sequence = await feed.controlSequence()
                return .text(resuming ? "{\"op\":0,\"s\":\(sequence),\"t\":\"RESUMED\",\"d\":{}}" :
                    "{\"op\":0,\"s\":\(sequence),\"t\":\"READY\",\"d\":{\"session_id\":\"local\",\"resume_gateway_url\":\"wss://resume.discord.gg/\"}}")
            }
            if ready {
                if requestedAt == nil, applicationFrames > 0, applicationFrames % 8 == 0 {
                    applicationFrames += 1; requestedAt = ContinuousClock().now
                    return .text(#"{"op":1,"d":null}"#)
                }
                if await feed.shouldReconnect() { return .text(#"{"op":7,"d":null}"#) }
                if let (sequence,payload) = await feed.nextEvent() {
                    applicationFrames += 1
                    return .text("{\"op\":0,\"s\":\(sequence),\"t\":\"LOAD_EVENT\",\"d\":{\"payload\":\"\(payload)\"}}")
                }
            }
            let signal = await feed.wakeup()
            // Recheck after obtaining the wake generation to avoid missing a send/credit race.
            if acks > 0 || closed || (!ready && authenticated) { continue }
            if ready, let (sequence,payload) = await feed.nextEvent() {
                applicationFrames += 1
                return .text("{\"op\":0,\"s\":\(sequence),\"t\":\"LOAD_EVENT\",\"d\":{\"payload\":\"\(payload)\"}}")
            }
            try await signal.wait()
        }
    }

    /// Discards the socket and wakes any outstanding pull once, releasing counted ownership.
    func close() async {
        guard !closed else { return }
        closed = true
        await metrics.connection(-1)
        await feed.wake()
    }

    /// Uses the same in-memory abort; no normal close can invalidate the retained synthetic session.
    func closeForReconnect() async { await close() }

    /// Reports no peer close frame for the scripted reconnect control.
    /// - Returns: Always nil; opcode seven drives this workload's resumption.
    func peerCloseCode() async -> Int? { nil }
}
