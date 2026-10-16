import Foundation

/// Explicit bounded admission failures shared by read reuse components.
public enum HTTPReadFailure: Error, Equatable, Sendable {
    case capacityExceeded
    case closed
}

/// Bounded single-flight reads with independently cancellable subscribers.
///
/// An exchange is owned by this actor until completion, final waiter cancellation,
/// or close. Each caller receives its own continuation; cancelling one subscriber
/// cannot cancel another's exchange. Operations must cooperate with cancellation.
/// Only explicitly eligible endpoint descriptors may enter this component.
public actor RequestCoalescer {
    private struct Flight {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Data, any Error>]
    }
    private let maximumFlights: Int
    private let maximumFlightsPerIdentity: Int
    private let maximumWaiters: Int
    private let maximumWaitersPerFlight: Int
    private var flights: [HTTPReadKey: Flight] = [:]
    private var waiterCount = 0
    private var closed = false

    /// Creates an idle coalescer with finite active-exchange and subscriber bounds.
    /// - Parameters:
    ///   - maximumFlights: Aggregate active exchanges, default 128.
    ///   - maximumFlightsPerIdentity: Active exchanges for one scope, default 32.
    ///   - maximumWaiters: Aggregate subscribers, default 1,024.
    ///   - maximumWaitersPerFlight: Subscribers to one representation, default 256.
    /// - Precondition: Every bound is positive.
    public init(maximumFlights: Int = 128, maximumFlightsPerIdentity: Int = 32,
                maximumWaiters: Int = 1_024, maximumWaitersPerFlight: Int = 256) {
        precondition(min(maximumFlights, maximumFlightsPerIdentity, maximumWaiters, maximumWaitersPerFlight) > 0)
        self.maximumFlights = maximumFlights
        self.maximumFlightsPerIdentity = maximumFlightsPerIdentity
        self.maximumWaiters = maximumWaiters
        self.maximumWaitersPerFlight = maximumWaitersPerFlight
    }

    /// Joins or creates one exchange, preserving individual cancellation and failure delivery.
    /// - Parameters:
    ///   - key: Exact authentication-scoped representation identity.
    ///   - operation: Replay-free exchange, invoked once only for the first subscriber.
    /// - Returns: Shared successful bytes, independently decoded by each caller.
    /// - Throws: Operation failure, cancellation, closed ownership or bounded overload.
    public func run(key: HTTPReadKey, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        let waiter = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(key: key, waiter: waiter, continuation: continuation, operation: operation)
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiter: waiter) }
        }
        try Task.checkCancellation()
        return data
    }

    /// Cancels and awaits every owned exchange before resuming subscribers and returning.
    /// Repeated close calls reject new work and wait for the same active cleanups.
    public func close() async {
        closed = true
        let current = flights
        for flight in current.values { flight.task.cancel() }
        for flight in current.values { await flight.task.value }
    }

    /// Reports bounded owned exchanges/subscribers, with no credential labels.
    /// - Returns: Current active-flight and waiter counts.
    public func snapshot() -> (flights: Int, waiters: Int) { (flights.count, waiterCount) }

    /// Cancels and awaits all old reads for one changed credential/visibility scope.
    /// - Parameter identity: Scope whose successful local writes or observed permissions changed.
    /// Existing subscribers fail cancellation; callers may fetch again after invalidation returns.
    public func invalidate(identity: RateLimitIdentity) async {
        let tasks = flights.filter { $0.key.identity == identity }.map { $0.value.task }
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    /// Registers atomically before launching work; pre-cancelled callers never reserve capacity.
    /// - Parameters:
    ///   - key: Scoped representation.
    ///   - waiter: Unique subscriber token.
    ///   - continuation: Exactly-once completion owned until removal.
    ///   - operation: Exchange closure for a new flight only.
    private func register(key: HTTPReadKey, waiter: UUID, continuation: CheckedContinuation<Data, any Error>,
                          operation: @escaping @Sendable () async throws -> Data) {
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        guard !closed else { continuation.resume(throwing: HTTPReadFailure.closed); return }
        guard key.representation.utf8.count <= 131_072 else {
            continuation.resume(throwing: HTTPReadFailure.capacityExceeded); return
        }
        guard waiterCount < maximumWaiters else { continuation.resume(throwing: HTTPReadFailure.capacityExceeded); return }
        if var flight = flights[key] {
            guard !flight.waiters.isEmpty, flight.waiters.count < maximumWaitersPerFlight else {
                continuation.resume(throwing: HTTPReadFailure.capacityExceeded); return
            }
            flight.waiters[waiter] = continuation
            flights[key] = flight
            waiterCount += 1
            return
        }
        guard flights.count < maximumFlights,
              flights.keys.filter({ $0.identity == key.identity }).count < maximumFlightsPerIdentity else {
            continuation.resume(throwing: HTTPReadFailure.capacityExceeded); return
        }
        let generation = UUID()
        let task = Task {
            let result: Result<Data, any Error>
            do {
                let data = try await operation()
                try Task.checkCancellation()
                result = .success(data)
            }
            catch { result = .failure(error) }
            finish(key: key, generation: generation, result: result)
        }
        flights[key] = Flight(generation: generation, task: task, waiters: [waiter: continuation])
        waiterCount += 1
    }

    /// Removes one cancelled subscriber; final cancellation awaits exchange cleanup.
    /// - Parameters:
    ///   - key: Scoped flight identity.
    ///   - waiter: Subscriber token; completion/cancellation races are harmless.
    private func cancel(key: HTTPReadKey, waiter: UUID) async {
        guard var flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        waiterCount -= 1
        if flight.waiters.isEmpty {
            // Retain the empty flight until cleanup completes so close also awaits it.
            flights[key] = flight
            flight.task.cancel()
            await flight.task.value
        } else { flights[key] = flight }
        continuation.resume(throwing: CancellationError())
    }

    /// Publishes only the matching generation, releasing every retained continuation once.
    /// - Parameters:
    ///   - key: Scoped representation.
    ///   - generation: Fence against stale completion from an earlier flight.
    ///   - result: Exchange bytes or original safe pipeline error.
    private func finish(key: HTTPReadKey, generation: UUID, result: Result<Data, any Error>) {
        guard let flight = flights[key], flight.generation == generation else { return }
        flights.removeValue(forKey: key)
        waiterCount -= flight.waiters.count
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }
}
