import Foundation

/// Exactly-once resource accounting, isolated per test rather than globally shared.
public actor ResourceCounter {
    /// Immutable accounting snapshot; `acquired == released + live` always holds.
    public struct Snapshot: Sendable, Equatable {
        public let acquired: Int
        public let released: Int
        public let live: Int
    }
    private var live: Set<UUID> = []
    private var acquired = 0
    private var released = 0

    /// Creates empty accounting with no external resources or side effects.
    public init() {}

    /// Records one acquisition and returns a freely copyable, idempotent release token.
    /// - Returns: A lease; explicit release is required even on failure/cancellation.
    public func acquire() -> ResourceLease {
        let id = UUID()
        live.insert(id)
        acquired += 1
        return ResourceLease(counter: self, id: id)
    }

    /// Returns a consistent snapshot for exact cleanup assertions.
    /// - Returns: Total acquisitions/releases and currently live resource count.
    public func snapshot() -> Snapshot { Snapshot(acquired: acquired, released: released, live: live.count) }

    /// Releases one known resource exactly once; duplicate releases have no effect.
    /// - Parameter id: Token allocated by this same counter.
    fileprivate func release(_ id: UUID) {
        if live.remove(id) != nil { released += 1 }
    }
}

/// Copyable explicit cleanup ownership. There is no nondeterministic deinit accounting.
public struct ResourceLease: Sendable {
    private let counter: ResourceCounter
    private let id: UUID

    /// Binds a lease to one acquired counter entry.
    /// - Parameters:
    ///   - counter: Counter that owns the resource identity.
    ///   - id: Unique resource identifier allocated during acquisition.
    fileprivate init(counter: ResourceCounter, id: UUID) { self.counter = counter; self.id = id }

    /// Records cleanup once across all copies and concurrent callers.
    /// This operation cannot throw and is safe when the invoking task is cancelled.
    public func release() async { await counter.release(id) }
}
