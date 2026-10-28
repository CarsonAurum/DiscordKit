// File: Tests/DiscordCommandDSLTests/ApplicationLifecycleTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Deterministic host supervision and accepted-exchange cleanup checks using local signed fixtures.
/// These tests exercise task/listener ownership without sockets, real credentials, wall-time sleeps or registration.
@Suite(.timeLimit(.minutes(1))) struct ApplicationLifecycleTests {
    /// Acceptance failure cancels and joins an already admitted handler before releasing listener ownership.
    /// The original acceptance error survives cleanup, and every resource lease is released exactly once.
    /// - Throws: Unexpected local signing or barrier setup failures fail the test; the injected error is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func acceptanceFailureCancelsAdmittedHandler() async throws {
        let entered = TestBarrier(), blocked = TestBarrier(), cleaned = TestBarrier()
        let tracker = ResourceCounter(), clock = ManualClock()
        let response = ScriptedHTTPResponder(lease: await tracker.acquire())
        let handlerLease = await tracker.acquire()
        let listener = FailingCommandIngress(first: try ApplicationTests.exchange(ApplicationTests.bytes(), responder: response),
            handlerEntered: entered, lease: await tracker.acquire())
        let app = try ApplicationTests.application(handler: { _ in
            entered.open()
            do {
                try await blocked.wait()
                Issue.record("Suspended handler completed without cancellation")
            } catch {
                #expect(error is CancellationError)
                await handlerLease.release()
                cleaned.open()
                throw error
            }
        })
        await #expect(throws: TestSupportFailure.scripted("accept")) {
            try await app.run(listener: listener, context: TransportContext(clock: clock))
        }
        try await cleaned.wait()
        #expect(await listener.acceptanceCount == 1)
        #expect(await listener.failureCount == 1)
        #expect(await listener.closed)
        #expect(await response.completionCount == 0)
        #expect(blocked.waitingCount == 0)
        #expect(await tracker.snapshot().acquired == 3)
        #expect(await tracker.snapshot().released == 3)
        #expect(await tracker.snapshot().live == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation after one accepted handler and the next pending accept closes all ownership and joins both.
    /// The queued exchange never reaches a response slot, and admitted user work cooperatively cleans up.
    /// - Throws: Unexpected signing or barrier errors fail the test; host cancellation itself is required.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAfterAcceptanceClosesAdmittedAndQueuedWork() async throws {
        let entered = TestBarrier(), accepting = TestBarrier(), cleaned = TestBarrier()
        let handlerBlocked = TestBarrier(onWaitScheduled: entered.open)
        let acceptBlocked = TestBarrier(onWaitScheduled: accepting.open)
        let tracker = ResourceCounter(), clock = ManualClock()
        let admitted = ScriptedHTTPResponder(lease: await tracker.acquire())
        let queued = ScriptedHTTPResponder(lease: await tracker.acquire())
        let handlerLease = await tracker.acquire()
        let waiting = HTTPExchange(request: HTTPRequest(method: "GET", url: URL(string: "https://example.invalid/pending")!),
            responder: queued)
        let listener = try ScriptedHTTPIngress(incoming: [ApplicationTests.exchange(ApplicationTests.bytes(), responder: admitted), waiting],
            lease: await tracker.acquire(), beforeAccept: { request in
                if request.method == "GET" { try await acceptBlocked.wait() }
            })
        let app = try ApplicationTests.application(handler: { _ in
            do {
                try await handlerBlocked.wait()
                Issue.record("Admitted handler completed before cancellation")
            } catch {
                #expect(error is CancellationError)
                await handlerLease.release()
                cleaned.open()
                throw error
            }
        })
        let task = Task { try await app.run(listener: listener, context: TransportContext(clock: clock)) }
        try await entered.wait()
        try await accepting.wait()
        #expect(await listener.acceptanceCount == 1)
        #expect(handlerBlocked.waitingCount == 1)
        #expect(acceptBlocked.waitingCount == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await cleaned.wait()
        #expect(await listener.acceptanceCount == 1)
        #expect(await admitted.completionCount == 0)
        #expect(await queued.reservationCount == 0)
        #expect(handlerBlocked.waitingCount == 0)
        #expect(acceptBlocked.waitingCount == 0)
        #expect(await tracker.snapshot().acquired == 4)
        #expect(await tracker.snapshot().released == 4)
        #expect(await tracker.snapshot().live == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// A successful acceptance completing during shutdown must close its unread body and response slot without admission.
    /// The controlled ingress models an adapter whose acceptance had already committed as closure/cancellation won.
    /// Cleanup is required whether the transfer reaches the pending slot before closure or observes an already closed slot;
    /// the test does not infer which private actor branch wins that scheduler race.
    /// - Throws: Unexpected local fixture/barrier errors fail; the original handler failure remains required.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lateAcceptanceDuringShutdownDisposesTransferredExchange() async throws {
        let accepting = TestBarrier(), closed = TestBarrier(), tracker = ResourceCounter(), clock = ManualClock()
        let admitted = ScriptedHTTPResponder(lease: await tracker.acquire())
        let lateResponse = ScriptedHTTPResponder(lease: await tracker.acquire())
        let bodyLease = await tracker.acquire(), observations = CommandLifecycleObservations()
        let lateBody = try BodyStream(maximumChunkBytes: 1, next: {
            await observations.read()
            Issue.record("Late accepted request body reached a handler")
            return nil
        }, close: {
            await observations.closeBody()
            await bodyLease.release()
        })
        let late = HTTPExchange(request: HTTPRequest(method: "GET", url: URL(string: "https://example.invalid/late")!, body: lateBody),
            responder: lateResponse)
        let listener = LateCommandIngress(first: try ApplicationTests.exchange(ApplicationTests.bytes(), responder: admitted),
            late: late, accepting: accepting, closedSignal: closed, lease: await tracker.acquire())
        let app = try ApplicationTests.application(handler: { _ in
            try await accepting.wait()
            throw TestSupportFailure.scripted("handler")
        })
        let task = Task { try await app.run(listener: listener, context: TransportContext(clock: clock)) }
        try await accepting.wait()
        try await closed.wait()
        #expect(await listener.closed)
        #expect(await lateResponse.reservationCount == 0)
        await listener.releaseLateAcceptance()
        await #expect(throws: TestSupportFailure.scripted("handler")) { try await task.value }
        #expect(await listener.acceptanceCount == 2)
        #expect(await observations.bodyReads == 0)
        #expect(await observations.bodyClosures == 1)
        #expect(await lateResponse.reservationCount == 0)
        #expect(await lateResponse.completionCount == 0)
        #expect(await tracker.snapshot().acquired == 4)
        #expect(await tracker.snapshot().released == 4)
        #expect(await tracker.snapshot().live == 0)
        #expect(clock.pendingSleepCount == 0)
    }
}

/// A purpose-built listener that transfers one request, then fails only after its handler begins.
/// The finite first exchange and optional resource lease retain explicit idempotent cleanup ownership.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor FailingCommandIngress: HTTPIngress {
    private var first: HTTPExchange?
    private let handlerEntered: TestBarrier
    private let lease: ResourceLease
    private(set) var acceptanceCount = 0
    private(set) var failureCount = 0
    private(set) var closed = false

    /// Stores one listener-owned exchange and a deterministic marker for the admitted handler.
    /// - Parameters:
    ///   - first: Exchange transferred on the first successful accept; no I/O starts in construction.
    ///   - handlerEntered: Opened by user work before the second acceptance is permitted to fail.
    ///   - lease: Exactly-once listener resource accounting token released by closure.
    init(first: HTTPExchange, handlerEntered: TestBarrier, lease: ResourceLease) {
        self.first = first
        self.handlerEntered = handlerEntered
        self.lease = lease
    }

    /// Transfers the first request, then waits for admitted user work before throwing its controlled failure.
    /// - Parameter context: Caller cancellation/deadline authority checked before taking any exchange.
    /// - Returns: The one first exchange; no later call succeeds or returns EOF.
    /// - Throws: Cancellation/deadline, `TransportFailure.closed` after closure, or the exact accept sentinel.
    func accept<C: Clock>(context: TransportContext<C>) async throws -> HTTPExchange? where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        if let first {
            self.first = nil
            acceptanceCount += 1
            return first
        }
        try await handlerEntered.wait()
        failureCount += 1
        throw TestSupportFailure.scripted("accept")
    }

    /// Closes an untransferred first exchange if any and releases the listener lease idempotently.
    /// Active accepted handlers retain their own resource ownership; no background work is started.
    func close() async {
        closed = true
        let pending = first
        first = nil
        await pending?.request.body?.close()
        await pending?.responder.close()
        await lease.release()
    }
}

/// Models exactly one acceptance already committed while listener shutdown wins a scheduling race.
/// The second exchange is held in a bounded continuation until the test explicitly releases it after observing closure.
/// This deliberate late-success fixture does not claim ordinary adapters should ignore cancellation indefinitely.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor LateCommandIngress: HTTPIngress {
    private var first: HTTPExchange?
    private var late: HTTPExchange?
    private let accepting: TestBarrier
    private let closedSignal: TestBarrier
    private let lease: ResourceLease
    private var releaseAllowed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var acceptanceCount = 0
    private(set) var closed = false

    /// Stores a finite normal exchange plus one controlled late transfer without starting acceptance.
    /// - Parameters:
    ///   - first: Signed exchange admitted normally before the race begins.
    ///   - late: Unread exchange whose ownership is reserved by the second accept before its suspension.
    ///   - accepting: Marker opened only after reserving the second exchange for late return.
    ///   - closedSignal: Marker opened after listener closure and lease release, before late completion is allowed.
    ///   - lease: Exactly-once resource accounting for this listener, independent of transferred exchanges.
    init(first: HTTPExchange, late: HTTPExchange, accepting: TestBarrier, closedSignal: TestBarrier,
        lease: ResourceLease) {
        self.first = first
        self.late = late
        self.accepting = accepting
        self.closedSignal = closedSignal
        self.lease = lease
    }

    /// Returns the normal first request, or a second already-committed transfer after explicit race release.
    /// - Parameter context: Cancellation/deadline authority checked before committing either transfer.
    /// - Returns: First/late caller-owned exchange; nil when neither finite exchange remains.
    /// - Throws: Cancellation/deadline before reservation. After reserving the late exchange this test fixture
    ///   intentionally returns it even if cancellation/closure occurs, modeling an unavoidable adapter completion race.
    func accept<C: Clock>(context: TransportContext<C>) async throws -> HTTPExchange? where C.Duration == Duration {
        try context.check()
        if let first {
            self.first = nil
            acceptanceCount += 1
            return first
        }
        guard let late else { return nil }
        self.late = nil
        accepting.open()
        if !releaseAllowed { await withCheckedContinuation { waiter = $0 } }
        acceptanceCount += 1
        return late
    }

    /// Releases the one reserved late result even when its acceptance task has already been cancelled.
    /// Calling before continuation registration is safe; repeated calls have no effect and allocate no tasks.
    func releaseLateAcceptance() {
        releaseAllowed = true
        waiter?.resume()
        waiter = nil
    }

    /// Closes only listener-owned exchanges and releases its lease while preserving an already committed late transfer.
    /// The explicit race-release method unblocks that reserved completion; closure itself starts no hidden tasks.
    func close() async {
        closed = true
        let pending = [first, late].compactMap { $0 }
        first = nil
        late = nil
        for exchange in pending {
            await exchange.request.body?.close()
            await exchange.responder.close()
        }
        await lease.release()
        closedSignal.open()
    }
}

/// Serializes test-only late-body observations without exposing production implementation details.
private actor CommandLifecycleObservations {
    private(set) var bodyReads = 0
    private(set) var bodyClosures = 0

    /// Records a body pull; every test expects this count to remain zero after shutdown wins admission.
    func read() { bodyReads += 1 }

    /// Records underlying source cleanup, expected exactly once despite repeated listener/slot closure.
    func closeBody() { bodyClosures += 1 }
}
