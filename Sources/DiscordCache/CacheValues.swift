// File: Sources/DiscordCache/CacheValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// An opaque credential partition together with the visibility that produced a snapshot.
///
/// Use a random application-owned label, never a token. Rotate the identity when a
/// credential changes and the visibility generation after observed scope changes.
/// Intents form part of equality; clients with different intents cannot share data.
/// Actor operations reject identity labels longer than 256 UTF-8 bytes or empty labels.
public struct CacheScope: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let identity: String
    public let intents: UInt64
    public let visibilityGeneration: UInt64

    /// Describes one visibility partition without launching work or retaining credentials.
    /// - Parameters:
    ///   - identity: Nonempty opaque application label, at most 256 UTF-8 bytes.
    ///   - intents: Exact Gateway intent bits, including unknown future bits.
    ///   - visibilityGeneration: Caller-owned scope revision, initially zero.
    public init(identity: String, intents: UInt64, visibilityGeneration: UInt64 = 0) {
        self.identity = identity
        self.intents = intents
        self.visibilityGeneration = visibilityGeneration
    }

    /// Conceals identity and visibility information in ordinary diagnostics.
    public var description: String { "CacheScope(redacted)" }
    /// Conceals identity and visibility information in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from revealing identity labels.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Model families retained by the optional entity projection, independent of HTTP reuse.
public enum EntityKind: String, Hashable, Sendable {
    case guild, channel, user, member, role, message
}

/// A resource identity; guild membership and roles remain isolated by their guild.
public struct EntityKey: Hashable, Sendable {
    public let kind: EntityKind
    public let id: UInt64
    public let guildID: GuildID?

    /// Identifies a resource without claiming that it exists or is accessible.
    /// - Parameters:
    ///   - kind: Resource family, used to distinguish equal snowflake values.
    ///   - id: All 64 snowflake bits; zero is retained for caller-defined sentinels.
    ///   - guildID: Guild context; required by callers for guild-specific members/roles.
    public init(kind: EntityKind, id: UInt64, guildID: GuildID? = nil) {
        self.kind = kind
        self.id = id
        self.guildID = guildID
    }
}

/// Whether a projection contains a reviewed complete resource or a sparse observation.
public enum CacheCompleteness: Sendable, Equatable {
    case partial, complete
}

/// Availability is independent of resource deletion and field completeness.
public enum CacheAvailability: Sendable, Equatable {
    case available, unavailable, deleted
}

/// The latest source to modify a projection; this is evidence, never authorization.
public enum CacheProvenance: Sendable, Equatable {
    case gateway, rest, interaction, local, persistent
}

/// A per-shard ordered observation within a caller-owned topology/session generation.
///
/// Sequence numbers are comparable only within the same shard. A higher generation
/// supersedes older observations on that shard. Rotate generations on a fresh identify
/// or topology replacement, and preserve them across a resumed session.
public struct CacheObservationOrder: Sendable, Equatable {
    public let shard: Int
    public let generation: UInt64
    public let sequence: Int64

    /// Captures ordering supplied by a Gateway consumer without depending on Gateway.
    /// - Parameters:
    ///   - shard: Nonnegative shard index; negative values are rejected when applied.
    ///   - generation: Monotonically increasing caller-owned session generation.
    ///   - sequence: Nonnegative dispatch sequence; negative values are rejected.
    public init(shard: Int, generation: UInt64, sequence: Int64) {
        self.shard = shard
        self.generation = generation
        self.sequence = sequence
    }
}

/// A presence-aware, immutable JSON projection with explicit uncertainty metadata.
///
/// Omitted fields remain unknown. Partial updates preserve previously observed fields;
/// explicit null is retained only for top-level keys declared in `nullableFields`.
/// Redacted fields are removed, including old values. Nested structures are replaced
/// as units; adapters must validate nested schemas before constructing observations.
/// A complete snapshot refers only to this resource, never to all of its children.
public struct EntitySnapshot: Sendable, Equatable {
    public let fields: [String: JSONValue]
    public let completeness: CacheCompleteness
    public let redactedFields: Set<String>
    public let nullableFields: Set<String>
    public let availability: CacheAvailability
    public let provenance: CacheProvenance
    public let order: CacheObservationOrder?

    /// Captures values and source evidence without performing I/O or validating a schema.
    /// - Parameters:
    ///   - fields: Top-level observed fields; omission and null have distinct meanings.
    ///   - completeness: Partial by default; complete replaces the previous field set.
    ///   - redactedFields: Keys whose contents are inaccessible; old values are erased.
    ///   - nullableFields: Keys for which explicit top-level null is schema-valid.
    ///   - availability: Available by default; unavailable/deleted values cannot satisfy reads.
    ///   - provenance: Latest observation source, default Gateway.
    ///   - order: Optional shard-local order; REST observations normally omit it.
    public init(fields: [String: JSONValue], completeness: CacheCompleteness = .partial,
                redactedFields: Set<String> = [], nullableFields: Set<String> = [],
                availability: CacheAvailability = .available, provenance: CacheProvenance = .gateway,
                order: CacheObservationOrder? = nil) {
        self.fields = fields
        self.completeness = completeness
        self.redactedFields = redactedFields
        self.nullableFields = nullableFields
        self.availability = availability
        self.provenance = provenance
        self.order = order
    }
}

/// Finite retained-payload, freshness, and asynchronous refresh budgets.
///
/// Bytes account for serialized JSON, field metadata, and identity/key UTF-8 bytes,
/// not allocator/index/task overhead. Measure process RSS before capacity claims.
/// Per-identity limits aggregate all intent and visibility partitions of that identity.
public struct CacheLimits: Sendable {
    public let maximumEntries: Int
    public let maximumBytes: Int
    public let maximumEntriesPerIdentity: Int
    public let maximumBytesPerIdentity: Int
    public let maximumTimeToLive: Duration
    public let maximumRefreshes: Int
    public let maximumRefreshesPerIdentity: Int
    public let maximumWaiters: Int
    public let maximumWaitersPerRefresh: Int

    /// Sets bounded policy values; cache construction validates all supplied limits.
    /// - Parameters:
    ///   - maximumEntries: Aggregate retained entries, default 1,024; zero disables retention.
    ///   - maximumBytes: Aggregate accounted bytes, default 4 MiB; zero disables retention.
    ///   - maximumEntriesPerIdentity: All partitions of one identity, default 256.
    ///   - maximumBytesPerIdentity: All partitions of one identity, default 1 MiB.
    ///   - maximumTimeToLive: Freshness ceiling greater than zero and no more than
    ///     30 days (2,592,000 seconds), default five minutes; avoids unsafe extreme advances.
    ///   - maximumRefreshes: Positive aggregate owned refreshes, default 32.
    ///   - maximumRefreshesPerIdentity: Positive per-identity refresh cap, default eight.
    ///   - maximumWaiters: Positive aggregate callers waiting for refreshes, default 512.
    ///   - maximumWaitersPerRefresh: Positive callers sharing one refresh, default 128.
    public init(maximumEntries: Int = 1_024, maximumBytes: Int = 4 * 1_024 * 1_024,
                maximumEntriesPerIdentity: Int = 256, maximumBytesPerIdentity: Int = 1_024 * 1_024,
                maximumTimeToLive: Duration = .seconds(300), maximumRefreshes: Int = 32,
                maximumRefreshesPerIdentity: Int = 8, maximumWaiters: Int = 512,
                maximumWaitersPerRefresh: Int = 128) {
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
        self.maximumEntriesPerIdentity = maximumEntriesPerIdentity
        self.maximumBytesPerIdentity = maximumBytesPerIdentity
        self.maximumTimeToLive = maximumTimeToLive
        self.maximumRefreshes = maximumRefreshes
        self.maximumRefreshesPerIdentity = maximumRefreshesPerIdentity
        self.maximumWaiters = maximumWaiters
        self.maximumWaitersPerRefresh = maximumWaitersPerRefresh
    }
}

/// Retention is explicitly selected; construction starts no refreshes or hidden tasks.
public enum CachePolicy: Sendable {
    /// No entity retention; equivalent concurrent refreshes still share bounded work.
    case noCache
    /// A small working set: 64 aggregate entries/256 KiB, 16 entries/64 KiB per identity, 30 seconds.
    case minimal
    /// Explicit larger finite budgets, including the default bounded policy.
    case bounded(CacheLimits)
}

/// Observable ingestion outcomes; eviction/disabled retention never masquerades as storage.
public enum CacheWriteResult: Sendable, Equatable {
    case stored, ignoredStale, notRetained, ignoredEvent
}

/// Explicit failures of bounded entity projection and refresh operations.
public enum EntityCacheFailure: Error, Sendable, Equatable {
    case invalidLimits, invalidScope, invalidOrder, invalidNullField
    case capacityExceeded, closed, superseded, insufficientSnapshot, malformedEvent
}

/// Aggregate counters without credential or resource labels.
public struct EntityCacheStatistics: Sendable, Equatable {
    public let entries: Int
    public let bytes: Int
    public let refreshes: Int
    public let waiters: Int
    public let hits: UInt64
    public let misses: UInt64
    public let evictions: UInt64
    public let expirations: UInt64
    public let coalescedReads: UInt64
    public let refreshStarts: UInt64
    public let staleCompletions: UInt64
}

/// An opt-in persistent projection adapter; the in-memory cache never calls it implicitly.
///
/// Implementations must enforce the same identity/intent/visibility isolation, bounded
/// payloads and explicit wall-clock expiry at the storage boundary. Persist no raw
/// credentials. Restored values must be revalidated or assigned a fresh bounded TTL
/// explicitly by the owner; monotonic cache instants cannot survive a process restart.
public protocol EntityCachePersistence: Sendable {
    /// Reads an explicitly scoped record without implying current authorization.
    /// - Parameters:
    ///   - key: Exact resource identity and guild context.
    ///   - scope: Exact opaque credential and visibility partition.
    /// - Returns: A still-eligible snapshot, or nil on absence/expiry.
    /// - Throws: Storage, decoding, cancellation, or adapter-specific capacity failures.
    func load(key: EntityKey, scope: CacheScope) async throws -> EntitySnapshot?

    /// Stores or removes one record under explicit expiry and isolation rules.
    /// - Parameters:
    ///   - snapshot: Snapshot to persist; nil deletes the record idempotently.
    ///   - key: Exact resource identity and guild context.
    ///   - scope: Exact opaque credential and visibility partition.
    ///   - timeToLive: Positive bounded storage TTL; nonpositive means immediate removal.
    /// - Throws: Storage, cancellation, validation, or adapter-specific capacity failures.
    func store(_ snapshot: EntitySnapshot?, key: EntityKey, scope: CacheScope, timeToLive: Duration) async throws

    /// Erases a partition after a credential/visibility change, including persistent metadata.
    /// - Parameter scope: Exact partition to invalidate; unrelated partitions remain isolated.
    /// - Throws: Storage or cancellation failures; owners must fail closed until handled.
    func invalidate(scope: CacheScope) async throws
}
