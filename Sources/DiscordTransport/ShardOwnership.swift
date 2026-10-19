import DiscordLogging
import DiscordCore
import Foundation

/// A bot's shard in one explicitly versioned topology, independent of any socket.
///
/// Changing the shard count requires a new topology generation and controlled
/// drain/resynchronization. This value performs no discovery or Gateway Identify.
public struct ShardIdentity: Hashable, Sendable {
    public let botID: UserID
    public let topologyGeneration: UInt64
    public let index: Int
    public let count: Int

    /// Validates one shard without opening a session or retaining credentials.
    /// - Parameters:
    ///   - botID: Public bot user ID, never a token or diagnostic credential key.
    ///   - topologyGeneration: Consumer-owned topology revision, including zero.
    ///   - index: Zero-based shard index strictly below `count`.
    ///   - count: Positive total shard count for this topology.
    /// - Throws: `ShardOwnershipFailure.invalidAssignment` for an invalid index/count.
    public init(botID: UserID, topologyGeneration: UInt64, index: Int, count: Int) throws {
        guard count > 0, index >= 0, index < count else { throw ShardOwnershipFailure.invalidAssignment }
        self.botID = botID
        self.topologyGeneration = topologyGeneration
        self.index = index
        self.count = count
    }

    /// Tests Discord's guild-routing formula for this shard without network I/O.
    ///
    /// Uses `(guild_id >> 22) % num_shards`; nonguild events route to shard zero
    /// and therefore must be handled separately. REST guild-list partitions are
    /// unrelated. Verified against the official Gateway reference on 2026-10-15.
    /// https://docs.discord.com/developers/events/gateway#sharding
    /// - Parameter guildID: Full unsigned Discord guild snowflake, including zero.
    /// - Returns: Whether this shard receives events for the supplied guild.
    public func routes(_ guildID: GuildID) -> Bool {
        (guildID.rawValue >> 22) % UInt64(count) == UInt64(index)
    }
}

/// Closed coordination failures; external stores must fail closed on lost authority.
public enum ShardOwnershipFailure: Error, Equatable, Sendable {
    case invalidAssignment
    case invalidLimit
    case alreadyOwned
    case capacityExceeded
    case staleLease
    case coordinatorUnavailable
    case generationExhausted
}

/// An expiring fencing ticket issued atomically by a lease store.
///
/// Check immediately before sends and again after suspension before accepting
/// completions. Fencing cannot recall a network write already in flight and does
/// not establish exactly-once delivery. Instants are meaningful only to the store's
/// clock. A store restart must not reuse generations while old workers can act.
public struct ShardLease<C: Clock>: Sendable where C.Duration == Duration {
    public let shard: ShardIdentity
    public let owner: UUID
    public let generation: UInt64
    public let expiresAt: C.Instant

    /// Constructs a ticket for an injected external coordinator implementation.
    /// - Parameters:
    ///   - shard: Atomic ownership key in a fixed topology.
    ///   - owner: Nonsecret worker-instance ID; restarting workers use a fresh UUID.
    ///   - generation: Monotonically increasing nonreused fencing generation.
    ///   - expiresAt: Inclusive expiration in the issuing store's clock domain.
    /// - Important: Constructing a ticket does not grant authority; validate it with
    ///   the issuing store. External implementations must atomically persist issuance.
    public init(shard: ShardIdentity, owner: UUID, generation: UInt64, expiresAt: C.Instant) {
        self.shard = shard
        self.owner = owner
        self.generation = generation
        self.expiresAt = expiresAt
    }
}

/// Injectable atomic lease boundary for in-process or external shard coordination.
///
/// External implementations must reject stale generations and fail closed during
/// outages. Consumers stop new sends and drain/close sessions on validation failure.
/// Different topology generations are distinct keys; deployment orchestration must
/// drain the old topology before activating the replacement.
public protocol ShardLeaseStore: Sendable {
    associatedtype LeaseClock: Clock where LeaseClock.Duration == Duration

    /// Atomically acquires a free or expired shard using a fresh fencing generation.
    /// - Parameters:
    ///   - shard: Fixed-topology key to reserve.
    ///   - owner: Fresh worker-instance identifier, excluding credentials.
    ///   - lifetime: Strictly positive monotonic duration; implementations may cap it.
    /// - Returns: A ticket valid until its inclusive expiration.
    /// - Throws: Cancellation, invalid lifetime, existing owner, capacity, exhausted
    ///   generations, or coordinator unavailability; no authority on failure.
    func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) async throws -> ShardLease<LeaseClock>

    /// Checks current owner, generation and inclusive expiry without extending it.
    /// - Parameter lease: Ticket obtained from this store in its clock domain.
    /// - Throws: Cancellation, stale/expired lease, or coordinator unavailability.
    func validate(_ lease: ShardLease<LeaseClock>) async throws

    /// Atomically replaces an unexpired ticket with a new expiry with a fresh fencing generation.
    /// - Parameters:
    ///   - lease: Current ticket; a previously renewed expiry is stale.
    ///   - lifetime: Strictly positive duration from the renewal instant.
    /// - Returns: Replacement ticket; callers must discard the previous ticket.
    /// - Throws: Cancellation, invalid lifetime, exhausted generations, stale lease
    ///   or unavailable coordinator.
    func renew(_ lease: ShardLease<LeaseClock>, lifetime: Duration) async throws -> ShardLease<LeaseClock>

    /// Releases matching ownership without affecting a newer owner or renewal.
    /// - Parameter lease: Ticket to relinquish; missing/stale tickets are a no-op.
    /// - Important: Cleanup must remain usable from a cancelled task. External stores
    ///   must surface outages rather than pretending that remote release succeeded.
    func release(_ lease: ShardLease<LeaseClock>) async throws
}

/// Bounded, process-local atomic lease ownership with an injectable monotonic clock.
///
/// No background tasks, timers, queues or sockets are created. Expired entries are
/// pruned on acquisition in O(maximumLeases); retained metadata is bounded. State
/// lasts only as long as this actor; it cannot coordinate multiple processes or
/// safely persist fencing across a process restart. External fleet deployments must
/// inject a durable coordinator with their own clock/fencing and outage policy.
public actor InProcessShardLeaseStore<C: Clock>: ShardLeaseStore where C.Duration == Duration {
    public typealias LeaseClock = C
    private let clock: C
    private let maximumLeases: Int
    private var nextGeneration: UInt64 = 0
    private var leases: [ShardIdentity: ShardLease<C>] = [:]

    /// Creates an empty store with no suspended work or resource ownership.
    /// - Parameters:
    ///   - clock: Monotonic clock used for all ticket expiration decisions.
    ///   - maximumLeases: Positive bound on simultaneously retained shard records.
    /// - Throws: `ShardOwnershipFailure.invalidLimit` when the bound is nonpositive.
    public init(clock: C, maximumLeases: Int) throws {
        guard maximumLeases > 0 else { throw ShardOwnershipFailure.invalidLimit }
        self.clock = clock
        self.maximumLeases = maximumLeases
    }

    /// Reserves one free shard atomically; does not queue competing owners.
    /// - Parameters:
    ///   - shard: Fixed-topology key to acquire.
    ///   - owner: Nonsecret worker-instance UUID.
    ///   - lifetime: Positive duration from `clock.now`, with no implicit renewal.
    /// - Returns: Newly fenced ticket after pruning expired metadata.
    /// - Throws: Cancellation, invalid duration, occupied shard, capacity exhaustion,
    ///   or generation overflow. Failure never mutates active ownership.
    public func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) throws -> ShardLease<C> {
        try Task.checkCancellation()
        guard lifetime > .zero else { throw ShardOwnershipFailure.invalidLimit }
        let now = clock.now
        leases = leases.filter { $0.value.expiresAt > now }
        guard leases[shard] == nil else { throw ShardOwnershipFailure.alreadyOwned }
        guard leases.count < maximumLeases else { throw ShardOwnershipFailure.capacityExceeded }
        guard nextGeneration < .max else { throw ShardOwnershipFailure.generationExhausted }
        nextGeneration += 1
        let lease = ShardLease<C>(shard: shard, owner: owner, generation: nextGeneration,
                                 expiresAt: now.advanced(by: lifetime))
        leases[shard] = lease
        DiscordLog.makeLogger("transport.leases").trace("Shard ownership acquired", metadata: ["dk.event": "transport.leases.acquired", "leases": "\(leases.count)"])
        return lease
    }

    /// Validates authority synchronously inside this actor, with no suspension gap.
    /// - Parameter lease: Ticket from this store, including its latest renewal expiry.
    /// - Throws: Cancellation or `staleLease` for missing, expired or replaced tickets.
    public func validate(_ lease: ShardLease<C>) throws {
        try Task.checkCancellation()
        guard matches(lease), lease.expiresAt > clock.now else { throw ShardOwnershipFailure.staleLease }
    }

    /// Replaces the ownership expiry from now with a fresh fencing generation.
    /// - Parameters:
    ///   - lease: Current unexpired ticket; old renewal tickets are rejected.
    ///   - lifetime: Strictly positive replacement duration from the current instant.
    /// - Returns: Updated ticket; the input ticket becomes stale.
    /// - Throws: Cancellation, invalid duration, exhausted generations or `staleLease`;
    ///   expired owners cannot renew. A shorter lifetime may shorten the lease.
    public func renew(_ lease: ShardLease<C>, lifetime: Duration) throws -> ShardLease<C> {
        try validate(lease)
        guard lifetime > .zero else { throw ShardOwnershipFailure.invalidLimit }
        guard nextGeneration < .max else { throw ShardOwnershipFailure.generationExhausted }
        nextGeneration += 1
        let replacement = ShardLease<C>(shard: lease.shard, owner: lease.owner, generation: nextGeneration,
                                       expiresAt: clock.now.advanced(by: lifetime))
        leases[lease.shard] = replacement
        DiscordLog.makeLogger("transport.leases").trace("Shard ownership renewed", metadata: ["dk.event": "transport.leases.renewed"])
        return replacement
    }

    /// Removes only the matching ticket and tolerates repeat/stale/cancelled cleanup.
    /// - Parameter lease: Ownership to release; newer tickets remain authoritative.
    public func release(_ lease: ShardLease<C>) {
        if matches(lease) {
            leases.removeValue(forKey: lease.shard)
            DiscordLog.makeLogger("transport.leases").trace("Shard ownership released", metadata: ["dk.event": "transport.leases.released", "leases": "\(leases.count)"])
        }
    }

    /// Reports retained records, including expired records not yet pruned.
    /// - Returns: A value in `0...maximumLeases`; no tasks or sockets are retained.
    public func retainedLeaseCount() -> Int { leases.count }

    /// Compares all authority-bearing ticket fields without consulting time.
    /// - Parameter lease: Candidate ticket, possibly forged, stale or expired.
    /// - Returns: Whether the current record has identical owner, fence and expiry.
    private func matches(_ lease: ShardLease<C>) -> Bool {
        guard let current = leases[lease.shard] else { return false }
        return current.owner == lease.owner && current.generation == lease.generation
            && current.expiresAt == lease.expiresAt
    }
}
