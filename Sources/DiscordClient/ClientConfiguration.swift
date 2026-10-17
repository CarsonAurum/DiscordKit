import DiscordCore
import DiscordGateway
import DiscordTransport

/// Closed runtime failures; diagnostics never embed credentials or received payloads.
public enum ClientFailure: Error, Sendable, Equatable {
    case invalidConfiguration, alreadyRunning, stopped, capacityExceeded, notReady
}

/// Immutable explicit intents, topology and ingestion limits for one single-use client.
public struct ClientConfiguration: Sendable {
    public let intents: GatewayIntents
    public let topologyGeneration: UInt64
    public let shardIndices: [Int]?
    public let maximumShards: Int
    public let ingestionBatchSize: Int
    public let shard: GatewayShardConfiguration

    /// Validates local bounds without discovering Discord or launching tasks.
    /// Privileged intents still require Developer Portal enablement and approval.
    /// - Parameters:
    ///   - intents: Explicit desired v10 events; no intent is implicitly enabled.
    ///   - topologyGeneration: Deployment fence, default zero; drain before changing topology.
    ///   - shardIndices: Unique nonnegative subset, or nil for discovery's recommendation.
    ///   - maximumShards: Local active-session ceiling in 1...4096, default 256.
    ///   - ingestionBatchSize: Events removed per suspension in 1...1024, default 64.
    ///   - shard: Validated per-shard raw queue/time/request bounds.
    /// - Throws: `invalidConfiguration` for invalid, duplicate or excessive local limits.
    public init(intents: GatewayIntents, topologyGeneration: UInt64 = 0,
                shardIndices: [Int]? = nil, maximumShards: Int = 256,
                ingestionBatchSize: Int = 64, shard: GatewayShardConfiguration = try! .init()) throws {
        guard (1...4096).contains(maximumShards), (1...1024).contains(ingestionBatchSize),
              shardIndices.map({ $0.count <= maximumShards && Set($0).count == $0.count
                  && $0.allSatisfy { $0 >= 0 } }) ?? true else { throw ClientFailure.invalidConfiguration }
        self.intents = intents; self.topologyGeneration = topologyGeneration
        self.shardIndices = shardIndices; self.maximumShards = maximumShards
        self.ingestionBatchSize = ingestionBatchSize; self.shard = shard
    }
}

/// Shared aggregate reservation ledger, injectable across independent bot identities.
/// Reservations bound clients, actual shards and raw queue ceilings, not served users.
public actor ClientResourceBudget {
    private let maximumClients: Int
    private let maximumShards: Int
    private let maximumRawEvents: Int
    private let maximumRawBytes: Int
    private var reservations: [UInt64: (shards: Int, events: Int, bytes: Int)] = [:]
    private var nextID: UInt64 = 0

    /// Creates a finite ledger without any background work.
    /// - Parameters:
    ///   - maximumClients: Concurrent running clients, default 16.
    ///   - maximumShards: Total active sessions across clients, default 256.
    ///   - maximumRawEvents: Sum of reserved raw queue count ceilings, default 32768.
    ///   - maximumRawBytes: Sum of raw wire byte ceilings, default 1 GiB.
    /// - Throws: `invalidConfiguration` for nonpositive limits.
    public init(maximumClients: Int = 16, maximumShards: Int = 256,
                maximumRawEvents: Int = 32768, maximumRawBytes: Int = 1_073_741_824) throws {
        guard maximumClients > 0, maximumShards > 0, maximumRawEvents > 0, maximumRawBytes > 0 else {
            throw ClientFailure.invalidConfiguration
        }
        self.maximumClients = maximumClients; self.maximumShards = maximumShards
        self.maximumRawEvents = maximumRawEvents; self.maximumRawBytes = maximumRawBytes
    }

    /// Atomically reserves the complete known topology; no waiting tasks are retained.
    /// - Parameters:
    ///   - shards: Selected local shard count, including zero.
    ///   - configuration: Per-shard raw event/byte ceilings.
    /// - Returns: Opaque monotonically allocated reservation, releasable once or repeatedly.
    /// - Throws: `capacityExceeded` for exhausted or overflowing resource arithmetic.
    public func reserve(shards: Int, configuration: GatewayShardConfiguration) throws -> UInt64 {
        let (events, eo) = shards.multipliedReportingOverflow(by: configuration.maximumBufferedEvents)
        let (bytes, bo) = shards.multipliedReportingOverflow(by: configuration.maximumBufferedBytes)
        let used = snapshot()
        guard shards >= 0, !eo, !bo, reservations.count < maximumClients, nextID < UInt64.max,
              shards <= maximumShards - used.shards, events <= maximumRawEvents - used.rawEvents,
              bytes <= maximumRawBytes - used.rawBytes else { throw ClientFailure.capacityExceeded }
        nextID += 1
        reservations[nextID] = (shards, events, bytes)
        return nextID
    }

    /// Releases a completed run's accounting; unknown or repeated reservations are harmless.
    /// - Parameter reservation: Previously returned opaque reservation.
    public func release(_ reservation: UInt64) { reservations.removeValue(forKey: reservation) }

    /// Adds discovered shard ceilings to an already reserved running-client slot atomically.
    /// - Parameters:
    ///   - reservation: Existing live reservation; invalid or released IDs fail closed.
    ///   - shards: Nonnegative selected local session count.
    ///   - configuration: Validated per-shard raw queue ceilings.
    /// - Throws: `capacityExceeded` for invalid reservations, arithmetic overflow or exhausted
    ///   aggregate sessions/events/bytes. Failure leaves the previous reservation unchanged.
    public func resize(_ reservation: UInt64, shards: Int, configuration: GatewayShardConfiguration) throws {
        guard let previous = reservations[reservation] else { throw ClientFailure.capacityExceeded }
        let (events, eo) = shards.multipliedReportingOverflow(by: configuration.maximumBufferedEvents)
        let (bytes, bo) = shards.multipliedReportingOverflow(by: configuration.maximumBufferedBytes)
        let used = snapshot()
        guard shards >= 0, !eo, !bo,
              shards <= maximumShards - (used.shards - previous.shards),
              events <= maximumRawEvents - (used.rawEvents - previous.events),
              bytes <= maximumRawBytes - (used.rawBytes - previous.bytes) else { throw ClientFailure.capacityExceeded }
        reservations[reservation] = (shards, events, bytes)
    }

    /// Reports current reserved ceilings without labels containing credentials or resource IDs.
    /// - Returns: Clients, actual sessions, raw event ceiling and raw wire byte ceiling.
    public func snapshot() -> (clients: Int, shards: Int, rawEvents: Int, rawBytes: Int) {
        (reservations.count, reservations.values.reduce(0) { $0 + $1.shards },
         reservations.values.reduce(0) { $0 + $1.events }, reservations.values.reduce(0) { $0 + $1.bytes })
    }
}
