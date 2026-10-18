/// Actor-confined scheduling policy for one bounded, control-prioritized DAVE owner.
///
/// This reducer owns reservations, not tasks, continuations or cryptography. Its actor
/// owner registers a suspended caller immediately after a queued reservation, resumes only
/// the ticket selected by `release`, and resolves the tickets returned by `close`. Keeping
/// scheduling separate makes capacity and priority independent of crypto execution timing.
/// The owner must serialize all mutation and must not copy a live policy into another owner.
struct DAVEOperationAdmissionPolicy: Sendable {
    /// One lifetime-unique operation identity and its explicit scheduling class.
    struct Ticket: Sendable, Equatable {
        let id: UInt64
        let control: Bool
    }

    /// Result of one fail-fast reservation, including whether it owns execution immediately.
    struct Reservation: Sendable, Equatable {
        let ticket: Ticket
        let admitted: Bool
    }

    let maximumPendingOperations: Int
    private(set) var active: Ticket?
    private(set) var isClosed = false
    private var pending: [Ticket] = []
    private var nextID: UInt64 = 0

    /// Number of finite queued reservations, excluding the one active operation.
    var pendingCount: Int { pending.count }

    /// Creates an idle scheduler without allocating a queue, tasks or synchronization objects.
    /// - Parameter maximumPendingOperations: Queued-operation bound in `2...1024`. Media can
    ///   reserve all but one queued position; controls can use the full queue. The active
    ///   operation is independently limited to one and is excluded from this count.
    /// - Throws: `DAVESessionError.invalidConfiguration` for a bound outside that range.
    init(maximumPendingOperations: Int) throws {
        guard (2...1024).contains(maximumPendingOperations) else {
            throw DAVESessionError.invalidConfiguration
        }
        self.maximumPendingOperations = maximumPendingOperations
    }

    /// Reserves immediate execution or one bounded queued position without suspending.
    ///
    /// Controls preserve their own admission order ahead of every queued media ticket.
    /// Media preserves FIFO order behind controls. An already active operation is never
    /// preempted. Sustained controls may delay media; the policy promises control priority,
    /// not starvation freedom. Rejected reservations retain no caller/operation metadata.
    /// - Parameter control: True for signaling/identity/readiness, false for encoded media.
    /// - Returns: A unique ticket and whether it immediately owns execution. The actor owner
    ///   installs the queued caller's continuation before its next suspension.
    /// - Throws: `CancellationError` before mutation, `closed` after terminal closure, or
    ///   `capacityExceeded` for a full class-specific queue or exhausted UInt64 ticket space.
    ///   Ticket identities never wrap; a capacity rejection may consume an identity.
    mutating func reserve(control: Bool) throws -> Reservation {
        try Task.checkCancellation()
        guard !isClosed else { throw DAVESessionError.closed }
        guard nextID < UInt64.max else { throw DAVESessionError.capacityExceeded }
        let ticket = Ticket(id: nextID, control: control)
        nextID += 1
        if active == nil {
            active = ticket
            return Reservation(ticket: ticket, admitted: true)
        }
        guard pending.count < maximumPendingOperations - (control ? 0 : 1) else {
            throw DAVESessionError.capacityExceeded
        }
        if control, let index = pending.firstIndex(where: { !$0.control }) {
            pending.insert(ticket, at: index)
        } else {
            pending.append(ticket)
        }
        return Reservation(ticket: ticket, admitted: false)
    }

    /// Removes one still-queued reservation without changing the active operation.
    /// - Parameter id: Previously reserved ticket identity; unknown/active/removed values are
    ///   harmless. Lifetime uniqueness prevents delayed cancellation from affecting a new ticket.
    /// - Returns: True only when one queued ticket was removed. The actor owner then resumes
    ///   exactly that ticket's caller with cancellation. Repeated removal returns false.
    mutating func cancel(_ id: UInt64) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        return true
    }

    /// Completes the active reservation and selects the next queued operation atomically.
    /// - Returns: The next control/media ticket, already marked active, or nil after draining,
    ///   closure or an idle release. The actor owner resumes exactly the selected caller;
    ///   nil allows its single shared cleanup waiter to proceed. Only the admitted operation
    ///   releases its ownership, exactly once on success, failure or post-grant cancellation.
    mutating func release() -> Ticket? {
        guard active != nil else { return nil }
        if !isClosed, !pending.isEmpty {
            let next = pending.removeFirst()
            active = next
            return next
        }
        active = nil
        return nil
    }

    /// Permanently rejects new reservations and detaches every queued ticket for rejection.
    /// - Returns: Pending tickets in their existing priority/FIFO order. Their continuations
    ///   are resumed with `closed` by the owner. The active reservation remains owned until
    ///   it releases; repeated close returns an empty array and does not duplicate cleanup.
    mutating func close() -> [Ticket] {
        isClosed = true
        let rejected = pending
        pending.removeAll(keepingCapacity: false)
        return rejected
    }
}
