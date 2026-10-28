// File: Tests/DiscordTestSupport/ScriptedIngress.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTransport

/// Failures specific to deterministic inbound HTTP scripts, without introducing runtime protocol policy.
public enum ScriptedIngressFailure: Error, Sendable, Equatable {
    /// A previous call already reserved the exchange's one response, even if that call failed.
    case responseAlreadyReserved
}

/// A single-use response owner with injectable, cancellation-cooperative transmission work.
///
/// No networking occurs. Reservation precedes suspension and survives every failure.
/// The responder closes every supplied body, including duplicate-call bodies, and
/// optionally releases one test resource lease when responding or closing finishes.
public actor ScriptedHTTPResponder: HTTPResponder {
    /// An operation that inspects or consumes the response; the responder retains final cleanup ownership.
    public typealias Step = @Sendable (HTTPResponse) async throws -> Void
    private let step: Step
    private let lease: ResourceLease?
    private var reserved = false
    private var closed = false
    private var operation: Task<Void, any Error>?
    private var cleanupTask: Task<Void, Never>?
    /// Number of admitted response reservations, always zero or one.
    public private(set) var reservationCount = 0
    /// Successful responses completed before explicit closure; always zero or one.
    public private(set) var completionCount = 0

    /// Creates an unreserved response slot without running transmission work.
    /// - Parameters:
    ///   - lease: Optional exactly-once accounting lease owned until response completion or explicit close.
    ///   - step: Transmission simulation, succeeding immediately by default. Suspended work must
    ///     cooperate with cancellation and must not await closure of this same responder.
    public init(lease: ResourceLease? = nil, step: @escaping Step = { _ in }) {
        self.lease = lease
        self.step = step
    }

    /// Reserves one response before any suspension and performs the scripted transmission once.
    ///
    /// Cancellation, expiration, and script failure leave the reservation consumed.
    /// Every supplied body is closed before this method returns or throws. A stored,
    /// awaited task lets explicit close cancel pending work; caller cancellation is
    /// forwarded to that task. Transmission steps must honor cooperative cancellation.
    /// Cancellation and the inclusive deadline are rechecked after awaiting that
    /// task, before recording completion; a response already sent cannot be retracted.
    /// - Parameters:
    ///   - response: Metadata and optional single-use body, whose cleanup ownership transfers on every call.
    ///   - context: Monotonic clock and inclusive deadline for the transmission.
    /// - Throws: `ScriptedIngressFailure.responseAlreadyReserved` for a second call,
    ///   `TransportFailure.closed` after unused-slot closure, cancellation, expiration,
    ///   or the original script failure. An explicitly closed in-flight operation cannot succeed late.
    public func respond<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        guard !reserved else {
            await response.body?.close()
            throw ScriptedIngressFailure.responseAlreadyReserved
        }
        guard !closed else {
            await response.body?.close()
            throw TransportFailure.closed
        }
        reserved = true
        reservationCount += 1
        do { try context.check() }
        catch {
            await response.body?.close()
            await finish()
            throw error
        }
        let step = self.step
        let task = Task {
            do {
                try await context.run { try await step(response) }
                await response.body?.close()
                try context.check()
            } catch {
                await response.body?.close()
                throw error
            }
        }
        operation = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try context.check()
            guard !closed else { throw TransportFailure.closed }
            completionCount += 1
            await finish()
        } catch {
            await finish()
            throw error
        }
    }

    /// Prevents new responses, cancels and awaits pending transmission, and releases the lease once.
    ///
    /// Closing never retracts a response already delivered by its script. Repeated or
    /// concurrent close calls wait for the same release; bodies close before cleanup returns.
    public func close() async {
        closed = true
        operation?.cancel()
        if let operation { _ = await operation.result }
        await finish()
    }

    /// Reserves one cleanup task before suspension so reentrant close/response callers share completion.
    ///
    /// Cancellation of an invoking caller cannot cancel lease release. The task is
    /// retained and awaited by the owning responder; no detached work is created.
    private func finish() async {
        if let cleanupTask { await cleanupTask.value; return }
        let lease = self.lease
        let task = Task { if let lease { await lease.release() } }
        cleanupTask = task
        await task.value
    }
}

/// A finite inbound HTTP backlog with controlled acceptance and no sockets or application handlers.
///
/// At most one acceptance may suspend. Accepted exchanges transfer completely to
/// the caller; explicit close owns only queued or not-yet-transferred exchanges.
/// Pulls preserve script order, and an empty/exhausted backlog yields orderly EOF.
public actor ScriptedHTTPIngress: HTTPIngress {
    /// Optional acceptance work used to control suspension or inject errors before ownership transfers.
    public typealias Acceptance = @Sendable (HTTPRequest) async throws -> Void
    private let incoming: [HTTPExchange]
    private let beforeAccept: Acceptance
    private let lease: ResourceLease?
    private var index = 0
    private var accepting = false
    private var closed = false
    private var operation: Task<Void, any Error>?
    private var activeExchange: HTTPExchange?
    private var cleanupTask: Task<Void, Never>?
    /// Exchanges whose ownership transferred successfully, excluding failed/closed pending requests.
    public private(set) var acceptanceCount = 0

    /// Stores a bounded listener backlog without accepting requests or starting tasks.
    /// - Parameters:
    ///   - incoming: Exchanges whose ownership transfers to this listener on successful initialization.
    ///   - maximumExchanges: Positive backlog capacity, default 1,024; no implicit queue grows after initialization.
    ///   - lease: Optional listener resource lease, released on EOF or explicit close.
    ///   - beforeAccept: Immediate success by default; injected suspension must cooperate with
    ///     cancellation and must not await closure of this same listener.
    /// - Throws: `TestSupportFailure.capacityExceeded` for invalid/exceeded capacity.
    ///   Initialization failure leaves exchange and lease cleanup with the caller.
    public init(incoming: [HTTPExchange], maximumExchanges: Int = 1_024,
                lease: ResourceLease? = nil, beforeAccept: @escaping Acceptance = { _ in }) throws {
        guard maximumExchanges > 0, incoming.count <= maximumExchanges else {
            throw TestSupportFailure.capacityExceeded
        }
        self.incoming = incoming
        self.beforeAccept = beforeAccept
        self.lease = lease
    }

    /// Reserves the next exchange and transfers it only after successful bounded acceptance.
    ///
    /// Pre-cancellation/expiration do not consume queued input. Failure after reservation
    /// discards and closes that one exchange; no request is replayed. Concurrent calls
    /// fail rather than queue. Cancellation and expiration are checked again after
    /// awaiting acceptance work, including losing-timer cleanup, before ownership
    /// transfers. EOF closes the listener lease and returns nil.
    /// - Parameter context: Clock and optional deadline for acceptance, including injected suspension.
    /// - Returns: The next caller-owned exchange, or nil after orderly EOF/closure.
    /// - Throws: `TransportFailure.concurrentRead` for another active accept, cancellation,
    ///   deadline expiration, `TransportFailure.closed` for interrupted pending work,
    ///   or an injected error. Failed exchanges close request bodies and responders before throwing.
    public func accept<C: Clock>(context: TransportContext<C>) async throws -> HTTPExchange?
        where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        guard !accepting else { throw TransportFailure.concurrentRead }
        guard index < incoming.count else { await close(); return nil }
        let exchange = incoming[index]
        index += 1
        accepting = true
        activeExchange = exchange
        let beforeAccept = self.beforeAccept
        let task = Task { try await context.run { try await beforeAccept(exchange.request) } }
        operation = task
        defer {
            accepting = false
            operation = nil
            activeExchange = nil
        }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try context.check()
            guard !closed else { throw TransportFailure.closed }
            acceptanceCount += 1
            return exchange
        } catch {
            await exchange.request.body?.close()
            await exchange.responder.close()
            throw error
        }
    }

    /// Closes queued/pending exchanges and cancels acceptance without touching previously accepted exchanges.
    ///
    /// The closed flag and one shared cleanup task are reserved before suspension.
    /// Returning means pending work terminated and all listener-owned bodies,
    /// responders, and its lease finished cleanup. Repeated calls share that work.
    public func close() async {
        if let cleanupTask { await cleanupTask.value; return }
        closed = true
        let operation = self.operation
        operation?.cancel()
        var owned = Array(incoming[index...])
        if let activeExchange { owned.append(activeExchange) }
        let exchanges = owned
        let lease = self.lease
        let task = Task {
            if let operation { _ = await operation.result }
            for exchange in exchanges {
                await exchange.request.body?.close()
                await exchange.responder.close()
            }
            await lease?.release()
        }
        cleanupTask = task
        await task.value
    }
}
