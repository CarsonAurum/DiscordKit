// File: Examples/DSLEvents/Tests/DSLEventsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@testable import DSLEvents
import Testing

/// Independently compiles handwritten modules outside the root runtime package and executes no I/O.
@Suite("External typed Gateway modules", .timeLimit(.minutes(1)))
struct DSLEventsTests {
    /// Two distinct module types must share one subscription, retain raw fields and preserve source order.
    /// - Throws: Unexpected offline model, compilation, subscription, execution or cleanup failures.
    @Test func typedModulesShareOnePipelineAndReleaseEveryOwner() async throws {
        let result = try await DSLEvents.runOffline()
        #expect(result.labels == ["welcome", "audit"])
        #expect(result.callbacksBeforeRun == 0)
        #expect(result.subscriptionsCreated == 1)
        #expect(result.payloadParity)
        #expect(result.cleanup.subscriptions == 0)
        #expect(result.cleanup.bufferedEvents == 0)
        #expect(result.cleanup.bufferedBytes == 0)
        #expect(result.cleanup.waitingConsumers == 0)
        #expect(result.cleanup.activeHandlers == 0)
        #expect(result.cleanup.waitingHandlers == 0)
        #expect(result.cleanup.isEmpty)
    }

    /// A handler failure must wake the completion stream, join the run and retain its original error.
    /// `runOffline` checks every cleanup counter before allowing the injected error to escape.
    @Test func callbackFailureWakesWaiterAndJoinsPipeline() async {
        await #expect(throws: EventDemoFailure.callback) { try await DSLEvents.runOffline(failSecond: true) }
    }

    /// Cancellation before admission must terminate without starting callbacks or retaining queues.
    @Test func cancellationBeforeAdmissionIsObservable() async {
        let run = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await DSLEvents.runOffline()
        }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }
}
