import DiscordLogging
import Foundation

/// An opaque authentication scope and exact request representation. Never log its contents.
public struct HTTPReadKey: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let identity: RateLimitIdentity
    let representation: String

    /// Separates private results by credential generation and complete request representation.
    /// - Parameters:
    ///   - identity: Shared opaque identity; rotate when credentials or scopes change.
    ///   - representation: Canonical route, query, body and representation metadata.
    public init(identity: RateLimitIdentity, representation: String) {
        self.identity = identity
        self.representation = representation
    }

    /// Conceals paths, queries and authentication scope from ordinary diagnostics.
    public var description: String { "HTTPReadKey(redacted)" }
    /// Conceals the same information in debug output.
    public var debugDescription: String { description }
    /// Prevents reflection from revealing key components.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Numeric retained-payload budgets; actor/index overhead must be measured separately.
public struct ReadCachePolicy: Sendable {
    public let maximumEntries: Int
    public let maximumBytes: Int
    public let maximumEntriesPerIdentity: Int
    public let maximumBytesPerIdentity: Int

    /// Configures finite total and per-identity LRU budgets. Zero disables retention.
    /// - Parameters:
    ///   - maximumEntries: Aggregate retained entries, default 256.
    ///   - maximumBytes: Aggregate payload bytes, default 4 MiB.
    ///   - maximumEntriesPerIdentity: One identity's retained entries, default 64.
    ///   - maximumBytesPerIdentity: One identity's payload bytes, default 1 MiB.
    /// - Precondition: All bounds are nonnegative.
    public init(maximumEntries: Int = 256, maximumBytes: Int = 4 * 1_024 * 1_024,
                maximumEntriesPerIdentity: Int = 64, maximumBytesPerIdentity: Int = 1_024 * 1_024) {
        precondition(min(maximumEntries, maximumBytes, maximumEntriesPerIdentity, maximumBytesPerIdentity) >= 0)
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
        self.maximumEntriesPerIdentity = maximumEntriesPerIdentity
        self.maximumBytesPerIdentity = maximumBytesPerIdentity
    }
}

/// A bounded opt-in response cache. Snapshots never establish current authorization.
///
/// TTL bounds unobserved external changes. Consumers must invalidate after observed
/// visibility/scope changes; local successful writes invalidate their declared tags.
/// A global revision fences completions started before any invalidation, conservatively
/// declining their insertion even when another identity was invalidated.
public actor ReadCache<C: Clock> where C.Duration == Duration {
    private struct Entry {
        let data: Data
        let expires: C.Instant
        let tags: Set<String>
        var access: UInt64
    }
    private let clock: C
    private let policy: ReadCachePolicy
    private var entries: [HTTPReadKey: Entry] = [:]
    private var revision: UInt64 = 0
    private var access: UInt64 = 0
    private var bytes = 0

    /// Creates an empty cache without launching tasks or scheduling refreshes.
    /// - Parameters:
    ///   - clock: Monotonic freshness clock, shared with the owning client.
    ///   - policy: Finite entry and retained-payload budgets.
    public init(clock: C, policy: ReadCachePolicy = .init()) {
        self.clock = clock
        self.policy = policy
    }

    /// Captures a generation before a fetch; stale generations cannot repopulate invalidations.
    /// - Returns: Current conservative invalidation generation.
    public func generation() -> UInt64 { revision }

    /// Returns a fresh snapshot and promotes it in LRU order; expiry is inclusive.
    /// - Parameter key: Complete authentication and representation identity.
    /// - Returns: Retained successful bytes, or nil for a missing/expired entry.
    public func value(for key: HTTPReadKey) -> Data? {
        prune()
        guard var entry = entries[key] else {
            DiscordLog.makeLogger("http.cache").trace("REST response cache lookup missed", metadata: ["dk.event": "http.cache.lookup.missed", "dk.entries": .stringConvertible(entries.count)])
            return nil
        }
        access &+= 1
        entry.access = access
        entries[key] = entry
        DiscordLog.makeLogger("http.cache").trace("REST response cache lookup succeeded", metadata: ["dk.event": "http.cache.lookup.hit", "dk.bytes": .stringConvertible(entry.data.count)])
        return entry.data
    }

    /// Retains a successful response within both budgets, evicting oldest eligible entries.
    /// - Parameters:
    ///   - data: Successful response payload; errors must never be passed here.
    ///   - key: Complete scoped representation key.
    ///   - timeToLive: Positive freshness duration; zero/negative disables insertion.
    ///   - tags: Bounded endpoint invalidation tags.
    ///   - generation: Revision captured before the fetch; stale completions are discarded.
    public func insert(_ data: Data, for key: HTTPReadKey, timeToLive: Duration,
                       tags: Set<String>, generation: UInt64) {
        prune()
        guard key.representation.utf8.count <= 131_072, tags.count <= 128,
              tags.reduce(0, { $0 + $1.utf8.count }) <= 65_536,
              generation == revision, timeToLive > .zero,
              policy.maximumEntries > 0, policy.maximumEntriesPerIdentity > 0,
              data.count <= min(policy.maximumBytes, policy.maximumBytesPerIdentity) else { return }
        remove(key)
        while entries.keys.filter({ $0.identity == key.identity }).count >= policy.maximumEntriesPerIdentity
            || identityBytes(key.identity) > policy.maximumBytesPerIdentity - data.count {
            guard let oldest = entries.filter({ $0.key.identity == key.identity }).min(by: { $0.value.access < $1.value.access })?.key else { return }
            remove(oldest)
        }
        while entries.count >= policy.maximumEntries || bytes > policy.maximumBytes - data.count {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { return }
            remove(oldest)
        }
        access &+= 1
        entries[key] = Entry(data: data, expires: clock.now.advanced(by: timeToLive), tags: tags, access: access)
        bytes += data.count
        DiscordLog.makeLogger("http.cache").trace("REST response cache retained validated bytes", metadata: ["dk.event": "http.cache.inserted", "dk.entries": .stringConvertible(entries.count), "dk.bytes": .stringConvertible(bytes)])
    }

    /// Fences old fetches and removes matching snapshots. Empty tags invalidate all for the identity.
    /// - Parameters:
    ///   - identity: Scope whose visibility or local state changed.
    ///   - tags: Intersecting endpoint tags; empty invalidates every scoped representation.
    public func invalidate(identity: RateLimitIdentity, tags: Set<String> = []) {
        revision &+= 1
        let keys = entries.filter { $0.key.identity == identity && (tags.isEmpty || !$0.value.tags.isDisjoint(with: tags)) }.map(\.key)
        for key in keys { remove(key) }
    }

    /// Drops every retained snapshot and fences all outstanding fetch generations.
    public func removeAll() {
        revision &+= 1
        entries.removeAll()
        bytes = 0
    }

    /// Reports retained entries/payload bytes after removing expired entries.
    /// - Returns: Accounted payload budgets, excluding Swift runtime/index overhead.
    public func snapshot() -> (entries: Int, bytes: Int) {
        prune()
        return (entries.count, bytes)
    }

    /// Removes inclusive-expired entries without timers or background tasks.
    private func prune() {
        let expired = entries.filter { $0.value.expires <= clock.now }.map(\.key)
        for key in expired { remove(key) }
        if !expired.isEmpty {
            DiscordLog.makeLogger("http.cache").trace("REST response cache expired entries pruned", metadata: ["dk.event": "http.cache.expired", "dk.removed": .stringConvertible(expired.count)])
        }
    }

    /// Releases one entry and its exact payload accounting; missing keys are harmless.
    /// - Parameter key: Representation to remove.
    private func remove(_ key: HTTPReadKey) {
        if let old = entries.removeValue(forKey: key) {
            bytes -= old.data.count
            DiscordLog.makeLogger("http.cache").trace("REST response cache entry released", metadata: ["dk.event": "http.cache.removed", "dk.entries": .stringConvertible(entries.count), "dk.bytes": .stringConvertible(bytes)])
        }
    }

    /// Sums one identity's retained payload accounting within the finite entry bound.
    /// - Parameter identity: Opaque scope to measure.
    /// - Returns: Retained bytes for that scope.
    private func identityBytes(_ identity: RateLimitIdentity) -> Int {
        entries.filter { $0.key.identity == identity }.reduce(0) { $0 + $1.value.data.count }
    }
}
