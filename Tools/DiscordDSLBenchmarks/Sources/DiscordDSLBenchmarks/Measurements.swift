import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Process gauges include the Swift allocator and benchmark; they are not cumulative allocation-event counts.
struct ProcessSample: Codable, Sendable {
    let cpuSeconds: Double
    let peakRSSBytes: UInt64
    let residentBytes: UInt64?
    let liveAllocationBlocks: UInt64?
    let liveAllocationBytes: UInt64?

    /// Reads actual process resource counters; unsupported gauges are omitted, never synthesized.
    /// Darwin RSS is bytes and malloc-zone values are live gauges; Linux peak RSS is converted from KiB.
    /// - Returns: Best-effort process counters; zero CPU/peak only when the corresponding syscall fails.
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

/// Nearest-rank invocation quantiles over a bounded, explicitly documented prefix sample.
struct LatencySummary: Codable, Equatable, Sendable {
    let sampleCount: Int
    let p50Milliseconds: Double?
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    /// Sorts valid bounded measurements and chooses nearest-rank quantiles without interpolation.
    /// - Parameter values: Millisecond measurements, excluding invalid/negative observations.
    /// - Returns: Quantiles or absent values for an empty valid sample.
    static func summarize(_ values: [Double]) -> Self {
        let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        return Self(sampleCount: sorted.count, p50Milliseconds: percentile(sorted, fraction: 0.5),
            p95Milliseconds: percentile(sorted, fraction: 0.95), p99Milliseconds: percentile(sorted, fraction: 0.99))
    }

    /// Chooses one nearest-rank observation from a sorted finite sample.
    /// - Parameters:
    ///   - values: Nondecreasing nonnegative measurements.
    ///   - fraction: One of the fixed quantiles selected above.
    /// - Returns: The indexed measurement, or nil for an empty array.
    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        return values[max(0, Int(ceil(Double(values.count) * fraction)) - 1)]
    }
}

/// Compiler and hardware identify the reproducible environment without inventing cross-platform evidence.
struct BenchmarkEnvironment: Codable, Equatable, Sendable {
    let operatingSystem: String
    let architecture: String
    let processorCount: Int
    let compiler: String
    let hardwareModel: String
    let physicalMemoryBytes: UInt64

    /// Captures host identity plus the actual `swift --version` output used by this process environment.
    /// - Returns: Hardware/OS/toolchain metadata; unavailable model/toolchain values say unavailable.
    static func capture() -> Self {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        var compiler = "unavailable"
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 { compiler = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        } catch {}
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        var model = "unavailable"
        #if canImport(Darwin)
        var size = 0
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size <= 1_024 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 {
                model = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        #endif
        return Self(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture, processorCount: ProcessInfo.processInfo.processorCount,
            compiler: compiler, hardwareModel: model, physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }
}

/// Converts monotonic duration components without truncating submillisecond observations.
/// - Parameter duration: A nonnegative elapsed monotonic duration.
/// - Returns: Floating-point seconds for reporting.
func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
