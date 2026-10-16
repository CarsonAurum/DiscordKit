import DiscordCore
import DiscordHTTP
import DiscordTransport
import Foundation

/// Numeric budgets for an offline HTTP policy workload; population never implies simultaneous sockets.
struct HTTPWorkloadProfile: Codable, Equatable, Sendable {
    let version: Int
    let name: String
    let logicalAccounts: Int
    let botIdentities: Int
    let requests: Int
    let cohort: Int
    let maximumQueuedRequests: Int
    let maximumQueuedBytes: Int
    let maximumConcurrentRequests: Int
    let maximumCacheEntries: Int
    let maximumCacheBytes: Int
    let maximumMetadata: Int
    let maximumLatencySamples: Int
    let targetP99Milliseconds: Double
    let maximumPeakRSSBytes: UInt64

    /// Rejects unsafe or inconsistent host-resource budgets before constructing policy owners.
    /// - Throws: `LoadFailure.invalidProfile` for unsupported version, population or unbounded dimensions.
    func validate() throws {
        guard version == 1, !name.isEmpty, logicalAccounts > 0, logicalAccounts <= 1_000_000_000,
              (1...64).contains(botIdentities), requests >= botIdentities, requests <= 1_000_000,
              (1...128).contains(cohort), (1...1_024).contains(maximumQueuedRequests),
              maximumQueuedBytes > 0, maximumQueuedBytes <= 16_777_216,
              maximumConcurrentRequests > 0, maximumConcurrentRequests <= cohort,
              maximumCacheEntries >= botIdentities, maximumCacheEntries <= 1_024,
              maximumCacheBytes >= botIdentities * 256, maximumCacheBytes <= 16_777_216,
              maximumMetadata >= botIdentities * 32, maximumMetadata <= 16_384,
              (1...10_000).contains(maximumLatencySamples), targetP99Milliseconds.isFinite,
              targetP99Milliseconds > 0, maximumPeakRSSBytes > 0
        else { throw LoadFailure.invalidProfile }
    }

    /// Loads one checked-in numeric profile using a safe basename.
    /// - Parameters:
    ///   - name: Lowercase letters, digits and hyphens, such as `accounts-100`.
    ///   - directory: Existing HTTP profile directory in the source checkout.
    /// - Returns: Validated HTTP policy workload dimensions.
    /// - Throws: Safe argument/profile failures or file/JSON decoding errors.
    static func load(name: String, directory: URL) throws -> Self {
        guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
        else { throw LoadFailure.invalidArguments }
        let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        try profile.validate()
        return profile
    }
}

/// Bounded counters and timing for an offline scripted HTTP policy measurement.
struct HTTPPolicyReport: Codable, Sendable {
    let scenario: String
    let profile: HTTPWorkloadProfile
    let burst: Bool
    let offeredConcurrency: Int
    let offeredRequests: Int
    let successfulRequests: Int
    let refusedRequests: Int
    let failedRequests: Int
    let cancelledRequests: Int
    let wireExchanges: Int
    let retryResponses: Int
    let cacheWireExchanges: Int
    let coalescedStormWireExchanges: Int
    let avoidedExchanges: Int
    let minimumIdentitySuccesses: Int
    let maximumIdentitySuccesses: Int
    let sampledPeakQueuedCount: Int
    let sampledPeakQueuedBytes: Int
    let sampledPeakActiveCount: Int
    let sampledPeakMetadataCount: Int
    let sampledPeakCacheEntries: Int
    let sampledPeakCacheBytes: Int
    let peakTransportExchanges: Int
    let peakRetryMetadata: Int
    let activeAfterShutdown: Int
    let queuedAfterShutdown: Int
    let flightsAfterShutdown: Int
    let cacheEntriesAfterShutdown: Int
    let seconds: Double
    let successfulRequestsPerSecond: Double
    let latency: LatencySummary
    let cpuSeconds: Double
    let meanCPUPercentOfOneCore: Double
    let before: ProcessSample
    let afterShutdown: ProcessSample
    let targetP99Met: Bool
    let rssBudgetMet: Bool
    let sampledResourceBudgetsMet: Bool
    let notes: [String]
}

/// A finite mixed-identity policy workload with cache reuse, hot buckets, read storms and rejected-request retries.
struct HTTPPolicyRunner: Sendable {
    /// Runs one bounded task cohort against an entirely local scripted adapter.
    /// - Parameters:
    ///   - profile: Validated logical population and numeric runtime-owner budgets.
    ///   - burst: Offers ten times the ordinary cohort while retaining the same queue/in-flight/cache caps.
    ///   - simulatedLatency: Artificial exchange latency, default one millisecond; zero removes timers in tests.
    /// - Returns: Measured counts, sampled owner caps, bounded latency quantiles and process CPU/RSS.
    /// - Throws: Invalid profile/configuration or setup errors. Individual policy failures are counted.
    ///
    /// No credentials or sockets are created. Every credential partition is a fresh opaque identity;
    /// population/worker dimensions do not claim distributed coordination or Discord quota capacity.
    func run(profile: HTTPWorkloadProfile, burst: Bool = false, simulatedLatency: Duration = .milliseconds(1)) async throws -> HTTPPolicyReport {
        try profile.validate()
        guard simulatedLatency >= .zero, simulatedLatency <= .seconds(1) else { throw LoadFailure.invalidArguments }
        let clock = ContinuousClock()
        let policy = SchedulingPolicy(maximumQueuedRequests: profile.maximumQueuedRequests,
            maximumQueuedRequestsPerIdentity: profile.maximumQueuedRequests,
            maximumQueuedBytes: profile.maximumQueuedBytes, maximumQueuedBytesPerIdentity: profile.maximumQueuedBytes,
            maximumConcurrentRequests: profile.maximumConcurrentRequests,
            maximumConcurrentRequestsPerIdentity: profile.maximumConcurrentRequests,
            maximumMetadata: profile.maximumMetadata, maximumQueueAge: .seconds(10), fairnessInterval: .microseconds(100),
            provisionalWindow: .microseconds(1), initialGlobalRequestsPerSecond: 1_000_000)
        let coordinator = RateLimitCoordinator(clock: clock, policy: policy)
        let cache = ReadCache(clock: clock, policy: ReadCachePolicy(maximumEntries: profile.maximumCacheEntries,
            maximumBytes: profile.maximumCacheBytes, maximumEntriesPerIdentity: profile.maximumCacheEntries,
            maximumBytesPerIdentity: profile.maximumCacheBytes))
        let coalescer = RequestCoalescer(maximumFlights: profile.maximumConcurrentRequests,
            maximumFlightsPerIdentity: profile.maximumConcurrentRequests,
            maximumWaiters: profile.cohort * 10, maximumWaitersPerFlight: profile.cohort * 10)
        let transport = HTTPPolicyTransport(simulatedLatency: simulatedLatency)
        let clients = (0..<profile.botIdentities).map { _ in
            RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
                coordinator: coordinator, clock: clock, cache: cache, coalescer: coalescer,
                maximumResponseBytes: 1_024, maximumExchangeDuration: .seconds(10))
        }
        let endpoints = try (0..<10).map { index in try endpoint(kind: index, ordinal: 0) }
        let before = ProcessSample.capture()
        let start = clock.now
        var offered = 0, successes = 0, refusals = 0, failures = 0, cancelled = 0
        var identitySuccesses = Array(repeating: 0, count: profile.botIdentities)
        var samples: [Duration] = []
        var peaks = HTTPResourcePeaks()
        let concurrency = profile.cohort * (burst ? 10 : 1)
        await withTaskGroup(of: HTTPPolicyOutcome.self) { group in
            for ordinal in 0..<min(concurrency, profile.requests) {
                group.addTask { await exchange(ordinal: ordinal, clients: clients, endpoints: endpoints,
                    coordinator: coordinator, cache: cache, clock: clock) }
                offered += 1
            }
            while let result = await group.next() {
                switch result.kind {
                case .success:
                    successes += 1; identitySuccesses[result.identity] += 1
                    if samples.count < profile.maximumLatencySamples { samples.append(result.elapsed) }
                case .refused: refusals += 1
                case .failure: failures += 1
                case .cancelled: cancelled += 1
                }
                peaks.observe(result)
                if Task.isCancelled { group.cancelAll() }
                else if offered < profile.requests {
                    let ordinal = offered
                    group.addTask { await exchange(ordinal: ordinal, clients: clients, endpoints: endpoints,
                        coordinator: coordinator, cache: cache, clock: clock) }
                    offered += 1
                }
            }
        }
        let elapsed = durationSeconds(start.duration(to: clock.now))
        await coalescer.close(); await coordinator.close(); await cache.removeAll()
        let after = ProcessSample.capture()
        let state = await coordinator.snapshot()
        let flights = await coalescer.snapshot()
        let cached = await cache.snapshot()
        let wire = await transport.snapshot()
        let latency = LatencySummary.summarizeDurations(samples)
        let cpu = max(0, after.cpuSeconds - before.cpuSeconds)
        return HTTPPolicyReport(scenario: "offlineHTTPPolicy", profile: profile, burst: burst, offeredConcurrency: concurrency,
            offeredRequests: offered, successfulRequests: successes, refusedRequests: refusals,
            failedRequests: failures, cancelledRequests: cancelled, wireExchanges: wire.calls, retryResponses: wire.retries,
            cacheWireExchanges: wire.cache, coalescedStormWireExchanges: wire.storm,
            avoidedExchanges: max(0, successes - (wire.calls - wire.retries)),
            minimumIdentitySuccesses: identitySuccesses.min() ?? 0, maximumIdentitySuccesses: identitySuccesses.max() ?? 0,
            sampledPeakQueuedCount: peaks.queued, sampledPeakQueuedBytes: peaks.queuedBytes,
            sampledPeakActiveCount: peaks.active, sampledPeakMetadataCount: peaks.metadata,
            sampledPeakCacheEntries: peaks.cacheEntries, sampledPeakCacheBytes: peaks.cacheBytes,
            peakTransportExchanges: wire.peakActive, peakRetryMetadata: wire.peakRetryMetadata,
            activeAfterShutdown: state.activeCount, queuedAfterShutdown: state.queuedCount,
            flightsAfterShutdown: flights.flights, cacheEntriesAfterShutdown: cached.entries,
            seconds: elapsed, successfulRequestsPerSecond: Double(successes) / max(elapsed, 0.000_001), latency: latency,
            cpuSeconds: cpu, meanCPUPercentOfOneCore: cpu / max(elapsed, 0.000_001) * 100, before: before, afterShutdown: after,
            targetP99Met: latency.p99Milliseconds.map { $0 <= profile.targetP99Milliseconds } ?? false,
            rssBudgetMet: after.peakRSSBytes <= profile.maximumPeakRSSBytes,
            sampledResourceBudgetsMet: peaks.queued <= profile.maximumQueuedRequests && peaks.queuedBytes <= profile.maximumQueuedBytes &&
                peaks.active <= profile.maximumConcurrentRequests && peaks.metadata <= profile.maximumMetadata &&
                peaks.cacheEntries <= profile.maximumCacheEntries && peaks.cacheBytes <= profile.maximumCacheBytes &&
                wire.peakActive <= profile.maximumConcurrentRequests && wire.peakRetryMetadata <= concurrency,
            notes: ["Offline scripted adapter: zero sockets, zero credentials, one client process; logical accounts mean served end users.",
                "Mix: 40% explicit TTL reads, 30% coalesced read storms, 10% hot buckets, 10% independent reads, 10% first-attempt 429 retries.",
                "Artificial per-exchange latency is \(durationSeconds(simulatedLatency) * 1_000) ms; hot buckets reset after 2 ms; retry rejection after 1 ms.",
                "Synthetic initial global allowance is 1000000/s solely to isolate policy overhead; this is not Discord's quota or a production recommendation.",
                "Resource peaks are sampled after logical operations; configured caps and deterministic root tests establish hard bounds.",
                "Latency retains at most \(profile.maximumLatencySamples) successful prefix samples. CPU/RSS include this process only; no fleet, socket capacity or soak claim."])
    }

    /// Constructs one operation kind with explicit read reuse and a stable nonsecret rate template.
    /// - Parameters:
    ///   - kind: Ordinal modulo ten controlling the documented request mix.
    ///   - ordinal: Stable request number used only by independent/retry operations.
    /// - Returns: A safe descriptor using `.none` authentication and binary identity decoding.
    /// - Throws: Descriptor validation errors if the checked-in harness contract is inconsistent.
    private func endpoint(kind: Int, ordinal: Int) throws -> Endpoint<Data> {
        let name = kind < 4 ? "cache" : (kind < 7 ? "storm" : (kind == 7 ? "hot" : (kind == 8 ? "cold" : "retry")))
        let readPolicy: ReadPolicy? = kind < 4 ? ReadPolicy(timeToLive: .seconds(60), tags: ["cache"]) : (kind < 7 ? ReadPolicy() : nil)
        return try Endpoint(method: "GET", path: ["measurements", name], route: "/measurements/" + name,
            query: kind >= 8 ? [QueryItem(name: "ordinal", value: String(ordinal))] : [], authentication: .none,
            retrySafety: .safe, readPolicy: readPolicy, decode: { $0 })
    }

    /// Measures one logical request and captures aggregate owner gauges without identity diagnostic labels.
    /// - Parameters:
    ///   - ordinal: Request ordinal assigning one identity and request kind.
    ///   - clients: Fixed finite credential partitions sharing owners.
    ///   - endpoints: Reusable descriptors for cache/storm/hot operations.
    ///   - coordinator: Shared bounded scheduler/rate authority.
    ///   - cache: Shared authentication-partitioned bounded successful-byte cache.
    ///   - clock: Measurement clock, not used for deterministic unit-test assertions.
    /// - Returns: Categorical result, exact elapsed duration and sampled bounded resource gauges.
    private func exchange(ordinal: Int, clients: [RESTClient<ContinuousClock>], endpoints: [Endpoint<Data>],
                          coordinator: RateLimitCoordinator<ContinuousClock>, cache: ReadCache<ContinuousClock>,
                          clock: ContinuousClock) async -> HTTPPolicyOutcome {
        let identity = (ordinal / 10) % clients.count
        let start = clock.now
        let kind: HTTPPolicyOutcome.Kind
        do {
            let endpoint = ordinal % 10 >= 8 ? try endpoint(kind: ordinal % 10, ordinal: ordinal) : endpoints[ordinal % 10]
            let data = try await clients[identity].execute(endpoint, deadline: clock.now.advanced(by: .seconds(10)))
            guard data == Data(repeating: 120, count: 256) else { throw LoadFailure.unexpectedResponse }
            kind = .success
        } catch is CancellationError { kind = .cancelled }
        catch RateLimitFailure.queueFull { kind = .refused }
        catch HTTPReadFailure.capacityExceeded { kind = .refused }
        catch { kind = .failure }
        let state = await coordinator.snapshot()
        let cached = await cache.snapshot()
        return HTTPPolicyOutcome(identity: identity, kind: kind, elapsed: start.duration(to: clock.now),
            queued: state.queuedCount, queuedBytes: state.queuedBytes, active: state.activeCount,
            metadata: state.metadataCount, cacheEntries: cached.entries, cacheBytes: cached.bytes)
    }

    /// Converts measured elapsed duration without truncating fractional seconds.
    /// - Parameter duration: Monotonic elapsed measurement or configured artificial delay.
    /// - Returns: Floating-point seconds for reporting only.
    private func durationSeconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// One bounded task-group result; stores only aggregate gauges and an arithmetic identity index.
private struct HTTPPolicyOutcome: Sendable {
    enum Kind: Sendable { case success, refused, failure, cancelled }
    let identity: Int
    let kind: Kind
    let elapsed: Duration
    let queued: Int
    let queuedBytes: Int
    let active: Int
    let metadata: Int
    let cacheEntries: Int
    let cacheBytes: Int
}

/// Fixed-size peak accounting, independent of offered request/population count.
private struct HTTPResourcePeaks {
    var queued = 0, queuedBytes = 0, active = 0, metadata = 0, cacheEntries = 0, cacheBytes = 0
    /// Incorporates one sampled task completion without retaining its request metadata.
    /// - Parameter outcome: Completed result carrying aggregate owner gauges.
    mutating func observe(_ outcome: HTTPPolicyOutcome) {
        queued = max(queued, outcome.queued); queuedBytes = max(queuedBytes, outcome.queuedBytes)
        active = max(active, outcome.active); metadata = max(metadata, outcome.metadata)
        cacheEntries = max(cacheEntries, outcome.cacheEntries); cacheBytes = max(cacheBytes, outcome.cacheBytes)
    }
}

/// A local server simulation bounded by active calls; no network origin is contacted.
private actor HTTPPolicyTransport: HTTPTransport {
    let simulatedLatency: Duration
    var calls = 0, retries = 0, cache = 0, storm = 0, active = 0, peakActive = 0, peakRetryMetadata = 0
    var pendingRetries: Set<String> = []
    /// Stores artificial measurement latency without creating timers or tasks.
    /// - Parameter simulatedLatency: Nonnegative configured delay, zero in deterministic tests.
    init(simulatedLatency: Duration) { self.simulatedLatency = simulatedLatency }

    /// Simulates learned buckets and one explicit 429 rejection per retry operation.
    /// - Parameters:
    ///   - request: Pinned Discord request; must carry no authorization or body in this workload.
    ///   - context: Cancellation/deadline checked before and after artificial delay.
    /// - Returns: Bounded 256-byte success or small 429 response with explicit retry metadata.
    /// - Throws: Cancellation/deadline or safe unexpected-request failures; no credentials or raw URLs are logged.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse where C.Duration == Duration {
        try context.check()
        guard request.url.host == "discord.com", request.headers.allSatisfy({ $0.name.lowercased() != "authorization" }), request.body == nil
        else { throw LoadFailure.unexpectedResponse }
        calls += 1; active += 1; peakActive = max(peakActive, active)
        defer { active -= 1 }
        if simulatedLatency > .zero { try await context.clock.sleep(for: simulatedLatency) }
        try context.check()
        let name = request.url.lastPathComponent
        if name == "cache" { cache += 1 }
        if name == "storm" { storm += 1 }
        let key = request.url.query ?? ""
        if name == "retry", pendingRetries.insert(key).inserted {
            peakRetryMetadata = max(peakRetryMetadata, pendingRetries.count); retries += 1
            let body = try RequestBody(bytes: Data("{\"retry_after\":0.001,\"global\":false}".utf8), contentType: "application/json")
            return HTTPResponse(status: 429, headers: [HTTPHeader(name: "Retry-After", value: "0.001")], body: try body.makeStream())
        }
        if name == "retry" { pendingRetries.remove(key) }
        let headers = [HTTPHeader(name: "X-RateLimit-Bucket", value: "synthetic-" + name),
            HTTPHeader(name: "X-RateLimit-Limit", value: "1000000"),
            HTTPHeader(name: "X-RateLimit-Remaining", value: name == "hot" ? "0" : "1000000"),
            HTTPHeader(name: "X-RateLimit-Reset-After", value: name == "hot" ? "0.002" : "0.001")]
        return HTTPResponse(status: 200, headers: headers,
            body: try RequestBody(bytes: Data(repeating: 120, count: 256), contentType: "application/octet-stream").makeStream())
    }

    /// Captures aggregate wire/ownership counters without exposing paths or request identities.
    /// - Returns: Executions, categorical responses, peak active exchanges and bounded retry metadata.
    func snapshot() -> (calls: Int, retries: Int, cache: Int, storm: Int, peakActive: Int, peakRetryMetadata: Int) {
        (calls, retries, cache, storm, peakActive, peakRetryMetadata)
    }
}
