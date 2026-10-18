import DiscordCore

/// Bounded account-local social reducer for trusted application-supplied observations.
///
/// Construction is inert: no tasks, timers, subscriptions, network, persistence, or
/// native SDK are owned. The application supplies authorized complete snapshots and
/// contiguous local-provider events. Actor methods contain no suspension points, so
/// validation and replacement are atomic relative to all callers. No optimistic friend
/// or block mutations are synthesized from command success. These bounded synchronous
/// operations do not observe task cancellation once admitted to the actor.
public actor SocialRelationshipStore {
    /// Fixed count and UTF-8 string budgets; there is no event history or replay queue.
    public let limits: SocialStateLimits
    private var scope: SocialScope?
    private var generation: UInt64?
    private var sequence: UInt64?
    private var synchronization = SocialSynchronization.inactive
    private var users: [UserID: SocialUser] = [:]
    private var relationships: [UserID: SocialRelationship] = [:]
    private var totalStringBytes = 0

    /// Creates an empty inert account-local reducer with validated fixed limits.
    /// - Parameter limits: Positive validated budgets; the caller chooses shared
    ///   aggregate admission when owning multiple account-local stores.
    public init(limits: SocialStateLimits) {
        self.limits = limits
    }

    /// Activates an exact consent domain and erases all prior account observations.
    ///
    /// Repeated activation also clears state. Supply a fresh consent generation when
    /// replacing authorization so delayed old-provider callbacks cannot match. This
    /// method does not obtain or validate consent itself and performs no I/O.
    /// - Parameter scope: Application/account/consent domain; both IDs must be nonzero.
    /// - Throws: `SocialStateError.invalidIdentifier` for a zero ID; prior state then remains intact.
    public func activate(scope: SocialScope) throws {
        guard scope.applicationID.rawValue != 0, scope.accountID.rawValue != 0 else {
            throw SocialStateError.invalidIdentifier
        }
        self.scope = scope
        generation = nil
        sequence = nil
        invalidate()
    }

    /// Revokes the active domain and immediately releases all retained account data.
    ///
    /// The application must also stop its provider and revoke credentials where
    /// appropriate. Later callbacks fail scope matching. Clearing is idempotent,
    /// synchronous within actor isolation, and owns no external cleanup resources.
    public func clear() {
        scope = nil
        generation = nil
        sequence = nil
        invalidate()
    }

    /// Atomically validates and installs one complete exact-scope provider baseline.
    ///
    /// Older generations/sequences are ignored before payload validation. While
    /// synchronized, an equal snapshot is a duplicate. While resynchronizing, an equal
    /// watermark snapshot may restore the complete baseline. Malformed snapshots leave
    /// prior state unchanged; exceeding a budget invalidates existing data fail-closed.
    /// - Parameter snapshot: Complete trusted-provider observation with unique IDs and no dangling relationships.
    /// - Returns: `.applied` after replacement or `.ignoredStale` for an older/duplicate baseline.
    /// - Throws: Scope, identifier, duplicate, missing-user, or capacity errors. On
    ///   `capacityExceeded`, state becomes `.needsSnapshot` with a raised watermark.
    public func apply(snapshot: SocialStateSnapshot) throws -> SocialApplyOutcome {
        try requireScope(snapshot.scope)
        if isStale(generation: snapshot.generation, sequence: snapshot.sequence,
                   equalIsStale: synchronization == .synchronized) {
            return .ignoredStale
        }
        do {
            guard snapshot.users.count <= limits.maximumUsers,
                snapshot.relationships.count <= limits.maximumRelationships
            else { throw SocialStateError.capacityExceeded }
            var nextUsers: [UserID: SocialUser] = [:]
            var nextRelationships: [UserID: SocialRelationship] = [:]
            var nextBytes = 0
            for user in snapshot.users {
                let bytes = try stringBytes(user)
                guard nextUsers[user.id] == nil else { throw SocialStateError.duplicateIdentifier }
                guard bytes <= limits.maximumTotalStringBytes - nextBytes else {
                    throw SocialStateError.capacityExceeded
                }
                nextUsers[user.id] = user
                nextBytes += bytes
            }
            for relationship in snapshot.relationships {
                guard relationship.userID.rawValue != 0 else { throw SocialStateError.invalidIdentifier }
                guard nextUsers[relationship.userID] != nil else { throw SocialStateError.missingUser }
                guard nextRelationships[relationship.userID] == nil else {
                    throw SocialStateError.duplicateIdentifier
                }
                nextRelationships[relationship.userID] = relationship
            }
            users = nextUsers
            relationships = nextRelationships
            totalStringBytes = nextBytes
            generation = snapshot.generation
            sequence = snapshot.sequence
            synchronization = .synchronized
            return .applied
        } catch SocialStateError.capacityExceeded {
            generation = snapshot.generation
            sequence = snapshot.sequence
            invalidate()
            throw SocialStateError.capacityExceeded
        }
    }

    /// Applies a contiguous provider event or requires an authoritative resnapshot.
    ///
    /// Duplicate/older events do nothing. New generations, sequence gaps, and events
    /// before a baseline advance the watermark, erase all display data, and require
    /// a snapshot. Capacity or malformed in-order events also erase data because the
    /// event cannot be safely skipped while claiming synchronization. No retry or
    /// remote mutation is performed. Sequence arithmetic never wraps at `UInt64.max`.
    /// - Parameter event: Complete normalized change from the exact active domain.
    /// - Returns: Applied, stale, or resnapshot-required outcome.
    /// - Throws: Scope, identifier, missing-user, or capacity errors; scope mismatch
    ///   leaves existing state untouched and other in-order validation failures invalidate it.
    public func apply(event: SocialStateEvent) throws -> SocialApplyOutcome {
        try requireScope(event.scope)
        if isStale(generation: event.generation, sequence: event.sequence, equalIsStale: true) {
            return .ignoredStale
        }
        guard synchronization == .synchronized, generation == event.generation,
            let previous = sequence, previous != UInt64.max, event.sequence == previous + 1
        else {
            generation = event.generation
            sequence = event.sequence
            invalidate()
            return .requiresSnapshot
        }
        do {
            try reduce(event.change)
            sequence = event.sequence
            return .applied
        } catch {
            sequence = event.sequence
            invalidate()
            throw error
        }
    }

    /// Copies the current bounded observation for deterministic local presentation.
    /// - Returns: Exact scope/order state plus users and relationships sorted by
    ///   unsigned ID. Unsynchronized and cleared views expose no account data.
    public func view() -> SocialStateView {
        SocialStateView(
            scope: scope, generation: generation, sequence: sequence, synchronization: synchronization,
            users: users.values.sorted { $0.id < $1.id },
            relationships: relationships.values.sorted { $0.userID < $1.userID }
        )
    }

    /// Requires exact account, application, and consent-generation equality.
    /// - Parameter candidate: Scope claimed by a provider callback.
    /// - Throws: `SocialStateError.scopeMismatch` when inactive or different; no state changes.
    private func requireScope(_ candidate: SocialScope) throws {
        guard let scope, candidate == scope else { throw SocialStateError.scopeMismatch }
    }

    /// Compares local provider ordering without wrapping unsigned arithmetic.
    /// - Parameters:
    ///   - candidateGeneration: Callback connection generation.
    ///   - candidateSequence: Callback sequence within that generation.
    ///   - equalIsStale: Whether equality must be treated as a duplicate.
    /// - Returns: False without a watermark, otherwise whether the callback predates it.
    private func isStale(generation candidateGeneration: UInt64, sequence candidateSequence: UInt64,
                         equalIsStale: Bool) -> Bool {
        guard let generation, let sequence else { return false }
        if candidateGeneration != generation { return candidateGeneration < generation }
        return candidateSequence < sequence || (equalIsStale && candidateSequence == sequence)
    }

    /// Clears resident observations while retaining the exact active domain and watermark.
    /// Uses empty dictionaries to release references; no provider callback or I/O occurs.
    private func invalidate() {
        users = [:]
        relationships = [:]
        totalStringBytes = 0
        synchronization = scope == nil ? .inactive : .needsSnapshot
    }

    /// Validates an admitted user's nonzero IDs and per-user UTF-8 budget.
    /// - Parameter user: Complete display data to retain.
    /// - Returns: Sum of display string UTF-8 bytes without integer overflow.
    /// - Throws: Identifier or capacity error; no state changes occur.
    private func stringBytes(_ user: SocialUser) throws -> Int {
        guard user.id.rawValue != 0 else { throw SocialStateError.invalidIdentifier }
        if let activityID = user.presence?.playingApplicationID, activityID.rawValue == 0 {
            throw SocialStateError.invalidIdentifier
        }
        var bytes = 0
        for text in [user.username, user.displayName ?? "", user.avatar ?? ""] {
            let count = text.utf8.count
            guard count <= limits.maximumUserStringBytes - bytes else {
                throw SocialStateError.capacityExceeded
            }
            bytes += count
        }
        return bytes
    }

    /// Mutates one event after ordering admission, preserving referential integrity.
    /// - Parameter change: Complete normalized provider mutation.
    /// - Throws: Invalid identifier, missing-user, or capacity errors before any partial mutation.
    private func reduce(_ change: SocialStateChange) throws {
        switch change {
        case .upsertUser(let user):
            let bytes = try stringBytes(user)
            let oldBytes = try users[user.id].map(stringBytes) ?? 0
            let remainingBytes = totalStringBytes - oldBytes
            guard users[user.id] != nil || users.count < limits.maximumUsers,
                bytes <= limits.maximumTotalStringBytes - remainingBytes
            else { throw SocialStateError.capacityExceeded }
            users[user.id] = user
            totalStringBytes = remainingBytes + bytes
        case .removeUser(let id):
            guard id.rawValue != 0 else { throw SocialStateError.invalidIdentifier }
            if let user = users.removeValue(forKey: id) { totalStringBytes -= try stringBytes(user) }
            relationships.removeValue(forKey: id)
        case .upsertRelationship(let relationship):
            guard relationship.userID.rawValue != 0 else { throw SocialStateError.invalidIdentifier }
            guard users[relationship.userID] != nil else { throw SocialStateError.missingUser }
            guard relationships[relationship.userID] != nil || relationships.count < limits.maximumRelationships else {
                throw SocialStateError.capacityExceeded
            }
            relationships[relationship.userID] = relationship
        case .removeRelationship(let id):
            guard id.rawValue != 0 else { throw SocialStateError.invalidIdentifier }
            relationships.removeValue(forKey: id)
        }
    }
}
