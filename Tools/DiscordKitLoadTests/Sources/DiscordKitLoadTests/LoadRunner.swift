import DiscordNIOTransport
import DiscordTransport
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Nearest-rank latency quantiles over a bounded prefix of successful exchanges.
/// These are workload measurements, never deterministic test deadlines.
struct LatencySummary: Codable, Equatable, Sendable {
    let sampleCount: Int
    let p50Milliseconds: Double?
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    /// Sorts finite nonnegative samples and derives standard nearest-rank quantiles.
    /// - Parameter milliseconds: Successful end-to-end samples; invalid values are ignored.
    /// - Returns: Quantiles or nil for each quantile when no valid sample exists.
    static func summarize(_ milliseconds: [Double]) -> Self {
        let sorted = milliseconds.filter { $0.isFinite && $0 >= 0 }.sorted()
        return Self(sampleCount: sorted.count, p50Milliseconds: percentile(sorted, fraction: 0.5),
                    p95Milliseconds: percentile(sorted, fraction: 0.95),
                    p99Milliseconds: percentile(sorted, fraction: 0.99))
    }

    /// Reads one nearest-rank percentile from an already sorted nonnegative sample.
    /// - Parameters:
    ///   - sorted: Increasing valid measurements; empty is permitted.
    ///   - fraction: Quantile in zero through one; internal callers use fixed constants.
    /// - Returns: Selected sample or nil when the sample is empty.
    private static func percentile(_ sorted: [Double], fraction: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        return sorted[max(0, min(sorted.count - 1, Int(ceil(fraction * Double(sorted.count))) - 1))]
    }
}

/// Process-only memory/CPU snapshot. Peer-process costs are excluded deliberately.
struct ProcessSample: Codable, Sendable {
    let cpuSeconds: Double
    let peakRSSBytes: UInt64
    let residentBytes: UInt64?
    let liveAllocationBlocks: UInt64?
    let liveAllocationBytes: UInt64?

    /// Samples OS counters without allocating a population-sized structure.
    ///
    /// Darwin reports RSS in bytes and malloc-zone live blocks/bytes; these are live
    /// allocation gauges, not cumulative allocation events or a streaming allocation
    /// trace. Unsupported gauges remain nil. Linux reports `ru_maxrss` in KiB.
    /// - Returns: Best-effort current counters; zero CPU/peak RSS when rusage fails.
    static func capture() -> Self {
        var usage = rusage()
        #if canImport(Darwin)
        let result = getrusage(RUSAGE_SELF, &usage)
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let infoResult = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        var allocations = malloc_statistics_t()
        malloc_zone_statistics(nil, &allocations)
        let resident: UInt64? = infoResult == KERN_SUCCESS ? UInt64(info.resident_size) : nil
        let blocks: UInt64? = UInt64(allocations.blocks_in_use)
        let bytes: UInt64? = UInt64(allocations.size_in_use)
        let peak = result == 0 ? UInt64(max(0, usage.ru_maxrss)) : 0
        #else
        let result = getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
        let resident: UInt64? = nil
        let blocks: UInt64? = nil
        let bytes: UInt64? = nil
        let peak = result == 0 ? UInt64(max(0, usage.ru_maxrss)) * 1_024 : 0
        #endif
        let cpu = result == 0 ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 : 0
        return Self(cpuSeconds: cpu, peakRSSBytes: peak, residentBytes: resident,
                    liveAllocationBlocks: blocks, liveAllocationBytes: bytes)
    }
}

/// Bounded local-run results; logical populations and actual work remain separate.
struct LoadMeasurement: Codable, Sendable {
    let profile: String
    let profileVersion: Int
    let logicalAccounts: Int
    let activeLogicalAccounts: Int
    let botIdentities: Int
    let simulatedWorkers: Int
    let configuredRequests: Int
    let offeredRequests: Int
    let admittedSuccesses: Int
    let capacityRefusals: Int
    let cancelledRequests: Int
    let failedRequests: Int
    let receivedBytes: Int
    let offeredConcurrency: Int
    let deadlineEnabled: Bool
    let requestDeadlineMilliseconds: Double?
    let maximumHarnessTasks: Int
    let configuredMaximumConnections: Int
    let sampledPeakPoolSlots: Int
    let durationSeconds: Double
    let successesPerSecond: Double
    let latency: LatencySummary
    let cpuSeconds: Double
    let meanCPUPercentOfOneCore: Double
    let before: ProcessSample
    let steady: ProcessSample
    let targetP99Milliseconds: Double
    let minimumSuccessesPerSecond: Double
    let latencyTargetMet: Bool
    let throughputTargetMet: Bool
    let maximumPeakRSSBytes: UInt64
    let maximumEndHeapBytes: UInt64
    let peakRSSBudgetMet: Bool
    let endHeapBudgetMet: Bool?
}

/// A structured, bounded-cohort GET workload against one caller-owned local peer.
/// No retries, queue, cache, credential, or Discord service requests are introduced.
struct LoadRunner: Sendable {
    /// Executes the profile while retaining at most a fixed number of tasks/samples.
    ///
    /// One task owns one response through EOF. Cancellation stops replenishment,
    /// cancels active work, and awaits the task group. Fail-fast capacity refusals
    /// count separately from faulty responses and socket errors. CPU/RSS cover only
    /// this client process; pool-slot peaks are sampled after response headers and
    /// can miss transient peaks, so the configured cap is reported separately.
    /// - Parameters:
    ///   - profile: Validated numeric workload and budget dimensions.
    ///   - transport: Caller-owned adapter, closed separately after measurement.
    ///   - url: Loopback HTTP endpoint; remote destinations are rejected.
    ///   - offeredConcurrency: Positive task cohort, at most profile cap times its burst multiplier.
    ///   - requestDeadline: Positive per-request duration up to sixty seconds, default ten; nil disables
    ///     deadline races for explicit allocation diagnostics, retaining cancellation.
    ///   - poolSlots: Optional adapter diagnostic returning current active plus idle slots.
    /// - Returns: Measured summary with bounded prefix quantiles and explicit refusals.
    /// - Throws: Invalid profile/concurrency/URL errors before any transport work begins.
    func run<T: HTTPTransport>(profile: WorkloadProfile, transport: T, url: URL,
                               offeredConcurrency: Int, requestDeadline: Duration? = .seconds(10),
                               poolSlots: @escaping @Sendable () async -> Int = { 0 }) async throws -> LoadMeasurement {
        try profile.validate()
        guard offeredConcurrency > 0, offeredConcurrency <= profile.activeCohort * profile.burstMultiplier,
              requestDeadline.map({ $0 > .zero && $0 <= .seconds(60) }) ?? true,
              url.scheme == "http", ["127.0.0.1", "::1", "[::1]"].contains(url.host ?? ""),
              url.user == nil, url.password == nil else { throw LoadFailure.invalidArguments }
        let clock = ContinuousClock()
        let before = ProcessSample.capture()
        let start = clock.now
        var offered = 0
        var successes = 0
        var refusals = 0
        var cancelled = 0
        var failures = 0
        var bytes = 0
        var sampledPeak = 0
        var samples: [Double] = []
        samples.reserveCapacity(min(profile.maximumLatencySamples, profile.requests))
        let maxTasks = min(offeredConcurrency, profile.requests)
        await withTaskGroup(of: ExchangeOutcome.self) { group in
            for ordinal in 0..<maxTasks where !Task.isCancelled {
                group.addTask {
                    await exchange(profile: profile, transport: transport, url: url, ordinal: ordinal, requestDeadline: requestDeadline, poolSlots: poolSlots)
                }
                offered += 1
            }
            while let outcome = await group.next() {
                switch outcome.result {
                case .success:
                    successes += 1
                    bytes += outcome.bytes
                    if samples.count < profile.maximumLatencySamples { samples.append(outcome.milliseconds) }
                case .capacity: refusals += 1
                case .cancelled: cancelled += 1
                case .failure: failures += 1
                }
                sampledPeak = max(sampledPeak, outcome.poolSlots)
                if Task.isCancelled { group.cancelAll() }
                else if offered < profile.requests {
                    let ordinal = offered
                    group.addTask {
                        await exchange(profile: profile, transport: transport, url: url, ordinal: ordinal, requestDeadline: requestDeadline, poolSlots: poolSlots)
                    }
                    offered += 1
                }
            }
        }
        let duration = seconds(start.duration(to: clock.now))
        let steady = ProcessSample.capture()
        let latency = LatencySummary.summarize(samples)
        let throughput = Double(successes) / max(duration, 0.000_001)
        let cpu = max(0, steady.cpuSeconds - before.cpuSeconds)
        return LoadMeasurement(
            profile: profile.name, profileVersion: profile.version, logicalAccounts: profile.logicalAccounts,
            activeLogicalAccounts: profile.activeLogicalAccounts, botIdentities: profile.botIdentities, simulatedWorkers: profile.simulatedWorkers,
            configuredRequests: profile.requests, offeredRequests: offered, admittedSuccesses: successes,
            capacityRefusals: refusals, cancelledRequests: cancelled, failedRequests: failures, receivedBytes: bytes,
            offeredConcurrency: offeredConcurrency, deadlineEnabled: requestDeadline != nil,
            requestDeadlineMilliseconds: requestDeadline.map { seconds($0) * 1_000 }, maximumHarnessTasks: offered == 0 ? 0 : maxTasks,
            configuredMaximumConnections: profile.maximumConnections, sampledPeakPoolSlots: sampledPeak,
            durationSeconds: duration, successesPerSecond: throughput, latency: latency, cpuSeconds: cpu,
            meanCPUPercentOfOneCore: cpu / max(duration, 0.000_001) * 100,
            before: before, steady: steady, targetP99Milliseconds: profile.targetP99Milliseconds,
            minimumSuccessesPerSecond: profile.minimumSuccessesPerSecond,
            latencyTargetMet: latency.p99Milliseconds.map { $0 <= profile.targetP99Milliseconds } ?? false,
            throughputTargetMet: throughput >= profile.minimumSuccessesPerSecond,
            maximumPeakRSSBytes: profile.maximumPeakRSSBytes, maximumEndHeapBytes: profile.maximumEndHeapBytes,
            peakRSSBudgetMet: steady.peakRSSBytes <= profile.maximumPeakRSSBytes,
            endHeapBudgetMet: steady.liveAllocationBytes.map { $0 <= profile.maximumEndHeapBytes })
    }

    /// Converts a monotonic duration without truncating fractional seconds.
    /// - Parameter duration: Nonnegative elapsed monotonic time from this process.
    /// - Returns: Seconds represented as a floating-point measurement.
    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Owns one deadline-bounded HTTP exchange and validates the entire received body.
    /// - Parameters:
    ///   - profile: Workload with an exact payload byte count and simulated workers.
    ///   - transport: Adapter owned by the enclosing run.
    ///   - url: Validated loopback endpoint, unchanged across all identities.
    ///   - ordinal: Logical request index, mapped arithmetically without allocation.
    ///   - requestDeadline: Positive timeout from entry, or nil for explicit diagnostics.
    ///   - poolSlots: Sampled diagnostic; called once after headers are received.
    /// - Returns: Safe categorical result; failed bodies are closed before completion.
    private func exchange<T: HTTPTransport>(profile: WorkloadProfile, transport: T, url: URL,
                                            ordinal: Int, requestDeadline: Duration?, poolSlots: @Sendable () async -> Int) async -> ExchangeOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        let assignment = profile.assignment(for: ordinal)
        var body: BodyStream?
        do {
            let response = try await transport.execute(
                HTTPRequest(method: "GET", url: url,
                            headers: [HTTPHeader(name: "X-Load-Worker", value: String(assignment.worker))]),
                context: TransportContext(clock: clock, deadline: requestDeadline.map { start.advanced(by: $0) }))
            body = response.body
            let slots = await poolSlots()
            guard response.status == 200 else { throw LoadFailure.unexpectedResponse }
            var received = 0
            if let body {
                for try await chunk in body {
                    guard chunk.count <= profile.payloadBytes - received,
                          chunk.allSatisfy({ $0 == 120 }) else { throw LoadFailure.unexpectedResponse }
                    received += chunk.count
                }
            }
            guard received == profile.payloadBytes else { throw LoadFailure.unexpectedResponse }
            return ExchangeOutcome(result: .success, bytes: received,
                                   milliseconds: seconds(start.duration(to: clock.now)) * 1_000, poolSlots: slots)
        } catch {
            if let body { await body.close() }
            let result: ExchangeOutcome.Result
            if error is CancellationError { result = .cancelled }
            else if let failure = error as? NIOAdapterFailure, failure == .capacityExceeded { result = .capacity }
            else { result = .failure }
            return ExchangeOutcome(result: result, bytes: 0,
                                   milliseconds: seconds(start.duration(to: clock.now)) * 1_000, poolSlots: 0)
        }
    }
}

/// One request's bounded result; arbitrary peer errors and bodies are never retained.
private struct ExchangeOutcome: Sendable {
    enum Result: Sendable { case success, capacity, cancelled, failure }
    let result: Result
    let bytes: Int
    let milliseconds: Double
    let poolSlots: Int
}

/// Allocation diagnostic implementing the existing portable body contract without sockets.
/// It mirrors adapter deadline races so probes can separate clocks/body overhead from I/O.
struct PortableLoadTransport: HTTPTransport {
    let payloadBytes: Int

    /// Returns one bounded ASCII-x body with the same deadline checks as real adapters.
    /// - Parameters:
    ///   - request: Ignored request metadata; no local socket or remote peer is used.
    ///   - context: Injected cancellation and optional deadline covering headers/body reads.
    /// - Returns: One finite response with an exactly configured payload length.
    /// - Throws: Context cancellation/deadline or invalid body-stream limits.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
    where C.Duration == Duration {
        try await context.run {
            let source = PortableLoadBody(payloadBytes: payloadBytes)
            return HTTPResponse(status: 200, body: try BodyStream(
                maximumChunkBytes: max(1, payloadBytes),
                next: { try await context.run { await source.next() } }, close: {}))
        }
    }
}

/// One portable diagnostic payload, released at EOF without per-account storage.
private actor PortableLoadBody {
    private var pending: Data?

    /// Retains exactly one fixed payload for a single exchange.
    /// - Parameter payloadBytes: Validated nonnegative body length in bytes.
    init(payloadBytes: Int) { pending = Data(repeating: 120, count: payloadBytes) }

    /// Returns the chunk once, then EOF; no background operation or buffer queue exists.
    /// - Returns: Payload on the first pull and nil on all later pulls.
    func next() -> Data? { defer { pending = nil }; return pending }
}
