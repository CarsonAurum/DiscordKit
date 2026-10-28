// File: Tests/DiscordDAVETests/DAVEOperationAdmissionPolicyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTestSupport
import Testing
@testable import DiscordDAVE

/// Scheduling tests reserve exact tickets and use barriers instead of cryptographic timing.
@Suite struct DAVEOperationAdmissionPolicyTests {
    /// Rejects invalid queue bounds without creating an active or pending reservation.
    /// - Parameter count: Lower, upper and overflow-prone queue capacity fixtures.
    @Test(arguments: [Int.min, -1, 0, 1, 1_025, Int.max])
    func invalidConfiguration(count: Int) {
        #expect(throws: DAVESessionError.invalidConfiguration) {
            try DAVEOperationAdmissionPolicy(maximumPendingOperations: count)
        }
    }

    /// A finite media queue leaves exactly one final control position and never evicts work.
    /// Controls are FIFO ahead of FIFO media; the already active operation is not preempted.
    @Test func reservedControlCapacityAndFIFO() throws {
        var policy = try DAVEOperationAdmissionPolicy(maximumPendingOperations: 4)
        #expect(policy.maximumPendingOperations == 4)
        #expect(policy.active == nil && policy.pendingCount == 0 && !policy.isClosed)
        let active = try policy.reserve(control: false)
        #expect(active.admitted)
        let media = try (0..<3).map { _ in try policy.reserve(control: false) }
        #expect(media.allSatisfy { !$0.admitted && !$0.ticket.control })
        #expect(policy.active == active.ticket && policy.pendingCount == 3)
        #expect(throws: DAVESessionError.capacityExceeded) { try policy.reserve(control: false) }
        let control = try policy.reserve(control: true)
        #expect(!control.admitted && control.ticket.control && policy.pendingCount == 4)
        #expect(throws: DAVESessionError.capacityExceeded) { try policy.reserve(control: true) }
        #expect(throws: DAVESessionError.capacityExceeded) { try policy.reserve(control: false) }
        #expect(policy.active == active.ticket && policy.pendingCount == 4)
        let releasedControl = policy.release()
        #expect(releasedControl == control.ticket)
        for queued in media {
            let releasedMedia = policy.release()
            #expect(releasedMedia == queued.ticket)
        }
        let releasedLast = policy.release()
        #expect(releasedLast == nil && policy.active == nil && policy.pendingCount == 0)
        let releasedIdle = policy.release()
        #expect(releasedIdle == nil)
        let next = try policy.reserve(control: true)
        #expect(next.admitted && next.ticket.id > control.ticket.id)
    }

    /// Cancellation removes only queued identities; close rejects all pending tickets once.
    /// Active ownership survives closure until its exact operation finishes.
    @Test func cancellationAndTerminalClosure() throws {
        var policy = try DAVEOperationAdmissionPolicy(maximumPendingOperations: 4)
        let active = try policy.reserve(control: true)
        let media = try policy.reserve(control: false)
        let firstControl = try policy.reserve(control: true)
        let secondControl = try policy.reserve(control: true)
        let cancelledActive = policy.cancel(active.ticket.id)
        #expect(!cancelledActive)
        let cancelledUnknown = policy.cancel(UInt64.max)
        #expect(!cancelledUnknown)
        let cancelledFirstControl = policy.cancel(firstControl.ticket.id)
        #expect(cancelledFirstControl)
        let cancelledAgain = policy.cancel(firstControl.ticket.id)
        #expect(!cancelledAgain)
        #expect(policy.pendingCount == 2 && policy.active == active.ticket)
        let rejected = policy.close()
        #expect(rejected == [secondControl.ticket, media.ticket])
        #expect(policy.isClosed && policy.pendingCount == 0 && policy.active == active.ticket)
        let rejectedAgain = policy.close()
        #expect(rejectedAgain.isEmpty)
        let cancelledAfterClose = policy.cancel(media.ticket.id)
        #expect(!cancelledAfterClose)
        #expect(throws: DAVESessionError.closed) { try policy.reserve(control: false) }
        #expect(throws: DAVESessionError.closed) { try policy.reserve(control: true) }
        let releasedActive = policy.release()
        #expect(releasedActive == nil && policy.active == nil)
        let releasedIdle = policy.release()
        #expect(releasedIdle == nil)
    }

    /// Cancellation before reservation consumes no queue position or ticket identity.
    @Test func cancellationBeforeReservation() async throws {
        let reservation = Task {
            var policy = try DAVEOperationAdmissionPolicy(maximumPendingOperations: 2)
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try policy.reserve(control: true)
                Issue.record("Cancelled reservation unexpectedly succeeded")
            } catch { #expect(error is CancellationError) }
            #expect(policy.active == nil && policy.pendingCount == 0 && !policy.isClosed)
        }
        try await reservation.value
    }

    /// Barrier-held active work lets exact queued controls overtake media without scheduler races.
    /// Admission is reserved synchronously before tasks start; every queued task announces its
    /// actual gate suspension before the active operation is released.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func barrierHeldPriorityAndControlFIFO() async throws {
        let owner = try DAVEAdmissionPolicyHarness(maximumPendingOperations: 4)
        let active = try await owner.reserve(control: false)
        let activeTask = Task { try await owner.execute(active) }
        try await active.entered.wait()
        let mediaA = try await owner.reserve(control: false)
        let mediaB = try await owner.reserve(control: false)
        let controlA = try await owner.reserve(control: true)
        let controlB = try await owner.reserve(control: true)
        await #expect(throws: DAVESessionError.capacityExceeded) { try await owner.reserve(control: true) }
        let mediaATask = Task { try await owner.execute(mediaA) }
        let mediaBTask = Task { try await owner.execute(mediaB) }
        let controlATask = Task { try await owner.execute(controlA) }
        let controlBTask = Task { try await owner.execute(controlB) }
        for queued in [mediaA, mediaB, controlA, controlB] { try await queued.waiting.wait() }
        #expect(await owner.snapshot().order == [active.ticket.id])
        #expect(await owner.snapshot().pending == 4)
        active.release.open()
        try await controlA.entered.wait()
        #expect(await owner.snapshot().order == [active.ticket.id, controlA.ticket.id])
        controlA.release.open()
        try await controlB.entered.wait()
        #expect(await owner.snapshot().order == [active.ticket.id, controlA.ticket.id, controlB.ticket.id])
        controlB.release.open()
        try await mediaA.entered.wait()
        mediaA.release.open()
        try await mediaB.entered.wait()
        mediaB.release.open()
        _ = try await (activeTask.value, mediaATask.value, mediaBTask.value, controlATask.value, controlBTask.value)
        let snapshot = await owner.snapshot()
        #expect(snapshot.order == [active.ticket.id, controlA.ticket.id, controlB.ticket.id,
                                  mediaA.ticket.id, mediaB.ticket.id])
        #expect(snapshot.pending == 0 && snapshot.active == nil)
    }

    /// A full media subqueue still admits one control while the active operation is blocked.
    /// Queue cancellation frees its exact slot and cannot cancel the current operation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func barrierHeldReservedSlotAndQueuedCancellation() async throws {
        let owner = try DAVEAdmissionPolicyHarness(maximumPendingOperations: 2)
        let active = try await owner.reserve(control: false)
        let activeTask = Task { try await owner.execute(active) }
        try await active.entered.wait()
        let media = try await owner.reserve(control: false)
        let mediaTask = Task { try await owner.execute(media) }
        try await media.waiting.wait()
        await #expect(throws: DAVESessionError.capacityExceeded) { try await owner.reserve(control: false) }
        let control = try await owner.reserve(control: true)
        let controlTask = Task { try await owner.execute(control) }
        try await control.waiting.wait()
        #expect(await owner.snapshot().pending == 2)
        #expect(await !owner.cancel(active.ticket.id))
        #expect(await owner.cancel(media.ticket.id))
        await #expect(throws: CancellationError.self) { try await mediaTask.value }
        #expect(await owner.snapshot().pending == 1)
        active.release.open()
        try await control.entered.wait()
        control.release.open()
        _ = try await (activeTask.value, controlTask.value)
        #expect(await owner.snapshot().order == [active.ticket.id, control.ticket.id])
        #expect(await owner.snapshot().active == nil)
    }

    /// Terminal closure releases queued callers while preserving the barrier-held active owner.
    /// No queued operation executes; its late task can neither reopen nor release active work.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func barrierHeldClosureRejectsQueuedWork() async throws {
        let owner = try DAVEAdmissionPolicyHarness(maximumPendingOperations: 2)
        let active = try await owner.reserve(control: false)
        let activeTask = Task { try await owner.execute(active) }
        try await active.entered.wait()
        let media = try await owner.reserve(control: false)
        let control = try await owner.reserve(control: true)
        let mediaTask = Task { try await owner.execute(media) }
        let controlTask = Task { try await owner.execute(control) }
        try await media.waiting.wait()
        try await control.waiting.wait()
        #expect(await owner.close() == [control.ticket.id, media.ticket.id])
        #expect(await owner.close().isEmpty)
        await #expect(throws: DAVESessionError.closed) { try await mediaTask.value }
        await #expect(throws: DAVESessionError.closed) { try await controlTask.value }
        let beforeRelease = await owner.snapshot()
        #expect(beforeRelease.closed && beforeRelease.pending == 0 && beforeRelease.active == active.ticket.id)
        #expect(beforeRelease.order == [active.ticket.id])
        await #expect(throws: DAVESessionError.closed) { try await owner.reserve(control: true) }
        active.release.open()
        try await activeTask.value
        #expect(await owner.snapshot().active == nil)
    }
}

/// Test-owned operation body gates around the real production scheduling reducer.
/// Reservation precedes task launch, so task scheduling cannot change admitted order.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor DAVEAdmissionPolicyHarness {
    struct Handle: Sendable {
        let ticket: DAVEOperationAdmissionPolicy.Ticket
        let granted: TestBarrier
        let waiting: TestBarrier
        let entered: TestBarrier
        let release: TestBarrier
    }

    struct Snapshot: Sendable {
        let order: [UInt64]
        let pending: Int
        let active: UInt64?
        let closed: Bool
    }

    private var policy: DAVEOperationAdmissionPolicy
    private var handles: [UInt64: Handle] = [:]
    private var cancelled: Set<UInt64> = []
    private var order: [UInt64] = []

    /// Creates finite scheduling state; no task begins until the test calls execute.
    /// - Parameter maximumPendingOperations: Real production policy bound under test.
    /// - Throws: The production policy's invalid-configuration error.
    init(maximumPendingOperations: Int) throws {
        policy = try DAVEOperationAdmissionPolicy(maximumPendingOperations: maximumPendingOperations)
    }

    /// Reserves using the production reducer, then creates finite operation-observation gates.
    /// - Parameter control: Actual control/media priority passed unchanged to production policy.
    /// - Returns: Ticket and one-shot barriers; immediate tickets start with an open grant.
    /// - Throws: Production cancellation, closure or class-specific capacity errors.
    func reserve(control: Bool) throws -> Handle {
        let result = try policy.reserve(control: control)
        let waiting = TestBarrier()
        let grant = TestBarrier(onWaitScheduled: { waiting.open() })
        let handle = Handle(ticket: result.ticket, granted: grant, waiting: waiting,
                            entered: TestBarrier(), release: TestBarrier())
        handles[result.ticket.id] = handle
        if result.admitted { grant.open() }
        return handle
    }

    /// Waits for the real policy's selected grant, holds its body, then releases exactly once.
    /// - Parameter handle: Previously reserved ticket and independent body gates.
    /// - Throws: Cancellation, terminal closure or invalid grant ownership. Queued failures
    ///   never release another ticket; an entered body releases even if its task is cancelled.
    func execute(_ handle: Handle) async throws {
        try await handle.granted.wait()
        if cancelled.remove(handle.ticket.id) != nil { throw CancellationError() }
        guard !policy.isClosed else { throw DAVESessionError.closed }
        guard policy.active == handle.ticket else { throw DAVESessionError.invalidMessage }
        order.append(handle.ticket.id)
        handle.entered.open()
        defer {
            handles.removeValue(forKey: handle.ticket.id)
            if let next = policy.release() { handles[next.id]?.granted.open() }
        }
        try await handle.release.wait()
    }

    /// Cancels one queued policy ticket and wakes that exact caller with a cancellation result.
    /// - Parameter id: Queued, active or missing ticket identity under test.
    /// - Returns: The production reducer's exact removal result.
    func cancel(_ id: UInt64) -> Bool {
        guard policy.cancel(id) else { return false }
        cancelled.insert(id)
        handles.removeValue(forKey: id)?.granted.open()
        return true
    }

    /// Closes scheduling and wakes precisely the tickets returned by the production reducer.
    /// - Returns: Rejected IDs in real control/FIFO order; the active body remains blocked.
    func close() -> [UInt64] {
        let rejected = policy.close()
        for ticket in rejected { handles.removeValue(forKey: ticket.id)?.granted.open() }
        return rejected.map(\.id)
    }

    /// Reads finite scheduling and observed execution state without timing assumptions.
    /// - Returns: Executed IDs, queued count, active identity and terminal state.
    func snapshot() -> Snapshot {
        Snapshot(order: order, pending: policy.pendingCount, active: policy.active?.id, closed: policy.isClosed)
    }
}
