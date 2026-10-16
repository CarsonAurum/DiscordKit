import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Deterministic inbound HTTP ownership tests, with gates and manual deadlines instead of sockets or sleeps.
@Suite struct ScriptedIngressTests {
    /// Successful response transmission closes its body and lease, and duplicate calls clean their newly supplied bodies.
    /// - Throws: Unexpected response or fixture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func responderSuccessAndDuplicate() async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try await trackedBody(counter)
        let responder = ScriptedHTTPResponder(lease: lease) { response in
            #expect(response.status == 201)
            #expect(response.headers == [HTTPHeader(name: "X-Test", value: "one")])
        }
        let context = TransportContext(clock: ManualClock())
        try await responder.respond(HTTPResponse(status: 201, headers: [HTTPHeader(name: "X-Test", value: "one")], body: body), context: context)
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 1)
        #expect(await counter.snapshot().released == 2)
        let duplicateBody = try await trackedBody(counter)
        await #expect(throws: ScriptedIngressFailure.responseAlreadyReserved) {
            try await responder.respond(HTTPResponse(status: 204, body: duplicateBody), context: context)
        }
        await responder.close()
        await responder.close()
        #expect(await counter.snapshot().released == 3)
        #expect(await counter.snapshot().live == 0)
    }

    /// A second response loses while the first is suspended, proving reservation happens before actor reentrancy.
    /// - Throws: Unexpected gate, fixture, or successful first-response errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentResponseReservation() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let counter = ResourceCounter()
        let firstBody = try await trackedBody(counter)
        let secondBody = try await trackedBody(counter)
        let responder = ScriptedHTTPResponder {
            _ in entered.open()
            try await release.wait()
        }
        let context = TransportContext(clock: ManualClock())
        let first = Task { try await responder.respond(HTTPResponse(status: 200, body: firstBody), context: context) }
        try await entered.wait()
        await #expect(throws: ScriptedIngressFailure.responseAlreadyReserved) {
            try await responder.respond(HTTPResponse(status: 201, body: secondBody), context: context)
        }
        #expect(await counter.snapshot().released == 1)
        release.open()
        try await first.value
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 1)
        #expect(await counter.snapshot().released == 2)
        #expect(release.waitingCount == 0)
    }

    /// Pre-cancellation, an already expired deadline, and an injected error all consume the response slot and release resources.
    /// - Parameter failure: Which failure occurs before successful transmission.
    /// - Throws: Unexpected fixture errors; intended failures are asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["cancelled", "deadline", "script"])
    func responderFailuresConsumeReservation(failure: String) async throws {
        let counter = ResourceCounter()
        let invocations = ResourceCounter()
        let lease = await counter.acquire()
        let body = try await trackedBody(counter)
        let responder = ScriptedHTTPResponder(lease: lease) { _ in
            let invocation = await invocations.acquire()
            await invocation.release()
            if failure == "script" { throw TestSupportFailure.scripted("response") }
        }
        let clock = ManualClock()
        let context = TransportContext(clock: clock, deadline: failure == "deadline" ? clock.now : nil)
        let task = Task {
            if failure == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
            try await responder.respond(HTTPResponse(status: 200, body: body), context: context)
        }
        switch failure {
        case "cancelled": await #expect(throws: CancellationError.self) { try await task.value }
        case "deadline": await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        default: await #expect(throws: TestSupportFailure.scripted("response")) { try await task.value }
        }
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 0)
        #expect(await invocations.snapshot().acquired == (failure == "script" ? 1 : 0))
        await #expect(throws: ScriptedIngressFailure.responseAlreadyReserved) {
            try await responder.respond(HTTPResponse(status: 200), context: TransportContext(clock: clock))
        }
        await responder.close()
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
    }

    /// Caller cancellation and concurrent explicit close terminate suspended responses and await exactly-once cleanup.
    /// - Parameter explicitClose: True to close through concurrent resource owners; false to cancel the caller task.
    /// - Throws: Unexpected setup/gate failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func pendingResponderCancellation(explicitClose: Bool) async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try await trackedBody(counter)
        let entered = TestBarrier()
        let gate = TestBarrier()
        let responder = ScriptedHTTPResponder(lease: lease) { _ in entered.open(); try await gate.wait() }
        let task = Task {
            try await responder.respond(HTTPResponse(status: 200, body: body), context: TransportContext(clock: ManualClock()))
        }
        try await entered.wait()
        if explicitClose {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<8 { group.addTask { await responder.close() } }
            }
        } else { task.cancel() }
        await #expect(throws: CancellationError.self) { try await task.value }
        await responder.close()
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 0)
        #expect(await counter.snapshot().released == 2)
        #expect(gate.waitingCount == 0)
    }

    /// A manually advanced response deadline cancels cooperative transmission and removes its sleeper.
    /// - Throws: Unexpected setup, registration, or clock-advance failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func responderDeadlineDuringTransmission() async throws {
        let scheduled = TestBarrier()
        let entered = TestBarrier()
        let gate = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try await trackedBody(counter)
        let responder = ScriptedHTTPResponder(lease: lease) { _ in entered.open(); try await gate.wait() }
        let task = Task {
            try await responder.respond(HTTPResponse(status: 200, body: body),
                context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
        }
        try await entered.wait()
        try await scheduled.wait()
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        #expect(await counter.snapshot().released == 2)
        #expect(clock.pendingSleepCount == 0)
        #expect(gate.waitingCount == 0)
    }

    /// Rechecks expiration after transmission cleanup and before recording successful completion.
    /// The third clock sample changes time only after its old value was read, modeling
    /// expiration while the responder awaits its completed transmission task.
    /// - Throws: Unexpected fixture construction failures; the elapsed deadline is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func responderRechecksDeadlineBeforeCompletion() async throws {
        let manual = ManualClock()
        let clock = CompletionBoundaryClock(clock: manual, afterSnapshot: { count in
            if count == 3 { try? manual.advance(by: .seconds(1)) }
        })
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try await trackedBody(counter)
        let responder = ScriptedHTTPResponder(lease: lease)
        let context = TransportContext(clock: clock, deadline: manual.now.advanced(by: .seconds(1)))
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await responder.respond(HTTPResponse(status: 200, body: body), context: context)
        }
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 0)
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
        #expect(manual.pendingSleepCount == 0)
        await responder.close()
    }

    /// Closing an unused slot rejects later responses but still closes the rejected call's body.
    /// - Throws: Unexpected body fixture errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func closedResponderCleansRejectedBody() async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let responder = ScriptedHTTPResponder(lease: lease)
        await responder.close()
        let body = try await trackedBody(counter)
        await #expect(throws: TransportFailure.closed) {
            try await responder.respond(HTTPResponse(status: 200, body: body), context: TransportContext(clock: ManualClock()))
        }
        #expect(await responder.reservationCount == 0)
        #expect(await counter.snapshot().released == 2)
    }

    /// Invalid or exceeded finite backlog capacity fails without acquiring listener-owned resources.
    /// - Throws: Unexpected URL/body fixture construction failures.
    @Test func ingressCapacityValidation() throws {
        let exchange = HTTPExchange(request: HTTPRequest(method: "POST", url: try #require(URL(string: "https://example.invalid/one"))),
                                    responder: ScriptedHTTPResponder())
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedHTTPIngress(incoming: [], maximumExchanges: 0) }
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedHTTPIngress(incoming: [], maximumExchanges: -1) }
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedHTTPIngress(incoming: [exchange, exchange], maximumExchanges: 1) }
    }

    /// Orderly EOF releases the listener lease, while accepted exchanges remain independently caller-owned.
    /// - Throws: Unexpected setup/acceptance failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ingressOrderEOFAndOwnership() async throws {
        let counter = ResourceCounter()
        let first = try await trackedExchange(counter, path: "one")
        let second = try await trackedExchange(counter, path: "two")
        let lease = await counter.acquire()
        let ingress = try ScriptedHTTPIngress(incoming: [first, second], maximumExchanges: 2, lease: lease)
        let context = TransportContext(clock: ManualClock())
        let acceptedFirst = try #require(try await ingress.accept(context: context))
        let acceptedSecond = try #require(try await ingress.accept(context: context))
        #expect(acceptedFirst.request.url.lastPathComponent == "one")
        #expect(acceptedSecond.request.url.lastPathComponent == "two")
        #expect(try await ingress.accept(context: context) == nil)
        #expect(try await ingress.accept(context: context) == nil)
        #expect(await ingress.acceptanceCount == 2)
        #expect(await counter.snapshot().released == 1)
        await acceptedFirst.request.body?.close()
        await acceptedFirst.responder.close()
        await acceptedSecond.request.body?.close()
        await acceptedSecond.responder.close()
        await ingress.close()
        #expect(await counter.snapshot().released == 5)
        #expect(await counter.snapshot().live == 0)
    }

    /// Explicit close discards queued exchanges and releases the listener while preserving an already accepted body/responder.
    /// - Throws: Unexpected setup, acceptance, or surviving-body read errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ingressCloseDiscardsOnlyUnaccepted() async throws {
        let counter = ResourceCounter()
        let first = try await trackedExchange(counter, path: "accepted")
        let second = try await trackedExchange(counter, path: "queued")
        let lease = await counter.acquire()
        let ingress = try ScriptedHTTPIngress(incoming: [first, second], lease: lease)
        let context = TransportContext(clock: ManualClock())
        let accepted = try #require(try await ingress.accept(context: context))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await ingress.close() } }
        }
        #expect(await counter.snapshot().released == 3)
        #expect(try await ingress.accept(context: context) == nil)
        var iterator = try #require(accepted.request.body).makeAsyncIterator()
        #expect(try await iterator.next() == Data([1]))
        try await accepted.responder.respond(HTTPResponse(status: 204), context: context)
        await accepted.request.body?.close()
        #expect(await counter.snapshot().released == 5)
    }

    /// Cancellation of one reserved acceptance closes that exchange, rejects a concurrent pull, and preserves following input.
    /// - Throws: Unexpected setup, gate, or subsequent acceptance failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pendingAcceptanceCancellationAndConcurrentPull() async throws {
        let entered = TestBarrier()
        let gate = TestBarrier()
        let counter = ResourceCounter()
        let first = try await trackedExchange(counter, path: "cancelled")
        let second = try await trackedExchange(counter, path: "next")
        let ingress = try ScriptedHTTPIngress(incoming: [first, second]) { _ in entered.open(); try await gate.wait() }
        let context = TransportContext(clock: ManualClock())
        let task = Task { try await ingress.accept(context: context) }
        try await entered.wait()
        await #expect(throws: TransportFailure.concurrentRead) { try await ingress.accept(context: context) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await counter.snapshot().released == 2)
        #expect(gate.waitingCount == 0)
        gate.open()
        let accepted = try #require(try await ingress.accept(context: context))
        #expect(accepted.request.url.lastPathComponent == "next")
        #expect(await ingress.acceptanceCount == 1)
        await ingress.close()
        await accepted.request.body?.close()
        await accepted.responder.close()
        #expect(await counter.snapshot().live == 0)
    }

    /// Closing a listener cancels and awaits a pending acceptance and cleans every listener-owned exchange.
    /// - Throws: Unexpected setup or gate failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func closeInterruptsPendingAcceptance() async throws {
        let entered = TestBarrier()
        let gate = TestBarrier()
        let counter = ResourceCounter()
        let first = try await trackedExchange(counter, path: "active")
        let second = try await trackedExchange(counter, path: "queued")
        let lease = await counter.acquire()
        let ingress = try ScriptedHTTPIngress(incoming: [first, second], lease: lease) { _ in entered.open(); try await gate.wait() }
        let context = TransportContext(clock: ManualClock())
        let task = Task { try await ingress.accept(context: context) }
        try await entered.wait()
        await ingress.close()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await ingress.accept(context: context) == nil)
        #expect(await ingress.acceptanceCount == 0)
        #expect(await counter.snapshot().released == 5)
        #expect(gate.waitingCount == 0)
    }

    /// Immediate cancellation/deadlines do not consume input; a suspended deadline cleans its reserved exchange before throwing.
    /// - Throws: Unexpected setup, clock advancement, or control-gate failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func acceptanceDeadlinesAndPreCancellation() async throws {
        let scheduled = TestBarrier()
        let entered = TestBarrier()
        let gate = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let counter = ResourceCounter()
        let exchange = try await trackedExchange(counter, path: "deadline")
        let ingress = try ScriptedHTTPIngress(incoming: [exchange]) { _ in entered.open(); try await gate.wait() }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await ingress.accept(context: TransportContext(clock: clock, deadline: clock.now))
        }
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ingress.accept(context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await before.value }
        #expect(await counter.snapshot().released == 0)
        let pending = Task {
            try await ingress.accept(context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(2))))
        }
        try await entered.wait()
        try await scheduled.wait()
        try clock.advance(by: .seconds(2))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await pending.value }
        #expect(await counter.snapshot().released == 2)
        #expect(clock.pendingSleepCount == 0)
        #expect(gate.waitingCount == 0)
        #expect(try await ingress.accept(context: TransportContext(clock: clock)) == nil)
    }

    /// Expiration while awaiting losing-timer cleanup prevents accepted ownership from transferring.
    /// Work wins the structured race, then timer cancellation advances virtual time
    /// to the deadline before the listener resumes. Both exchange resources must close.
    /// - Throws: Unexpected fixture, EOF, or clock-construction errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ingressRechecksDeadlineBeforeTransfer() async throws {
        let manual = ManualClock()
        let clock = CompletionBoundaryClock(clock: manual, afterCancelledSleep: {
            try? manual.advance(by: .seconds(1))
        })
        let counter = ResourceCounter()
        let exchange = try await trackedExchange(counter, path: "completion-deadline")
        let ingress = try ScriptedHTTPIngress(incoming: [exchange])
        let context = TransportContext(clock: clock, deadline: manual.now.advanced(by: .seconds(1)))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await ingress.accept(context: context) }
        #expect(await ingress.acceptanceCount == 0)
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
        #expect(manual.pendingSleepCount == 0)
        await exchange.request.body?.close()
        await exchange.responder.close()
        #expect(try await ingress.accept(context: TransportContext(clock: manual)) == nil)
    }

    /// An injected acceptance error closes its untransferred exchange; empty listeners return repeatable EOF.
    /// - Throws: Unexpected fixture creation or empty-listener acceptance failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func acceptanceScriptFailureAndEmptyEOF() async throws {
        let counter = ResourceCounter()
        let exchange = try await trackedExchange(counter, path: "failure")
        let ingress = try ScriptedHTTPIngress(incoming: [exchange]) { _ in throw TestSupportFailure.scripted("accept") }
        let context = TransportContext(clock: ManualClock())
        await #expect(throws: TestSupportFailure.scripted("accept")) { try await ingress.accept(context: context) }
        #expect(await counter.snapshot().released == 2)
        #expect(try await ingress.accept(context: context) == nil)
        let empty = try ScriptedHTTPIngress(incoming: [])
        #expect(try await empty.accept(context: context) == nil)
        await empty.close()
        #expect(try await empty.accept(context: context) == nil)
    }

    /// Creates a bounded, pull-only body whose lease records exactly-once terminal cleanup.
    /// - Parameter counter: Per-test accounting actor; one acquisition occurs before return.
    /// - Returns: A one-byte producer that stays readable until explicitly closed.
    /// - Throws: Unexpected `BodyStream` initialization errors for the valid one-byte limit.
    private func trackedBody(_ counter: ResourceCounter) async throws -> BodyStream {
        let lease = await counter.acquire()
        return try BodyStream(maximumChunkBytes: 1, next: { Data([1]) }, close: { await lease.release() })
    }

    /// Creates an exchange with independently accounted request-body and responder ownership.
    /// - Parameters:
    ///   - counter: Per-test resource accounting; two leases are acquired.
    ///   - path: Nonempty test path appended to a credential-free reserved-domain URL.
    /// - Returns: An exchange whose body and responder the current owner must close.
    /// - Throws: Fixture URL assertion failure or unexpected body construction failure.
    private func trackedExchange(_ counter: ResourceCounter, path: String) async throws -> HTTPExchange {
        let body = try await trackedBody(counter)
        let lease = await counter.acquire()
        let url = try #require(URL(string: "https://example.invalid/\(path)"))
        return HTTPExchange(request: HTTPRequest(method: "POST", url: url, body: body), responder: ScriptedHTTPResponder(lease: lease))
    }
}
