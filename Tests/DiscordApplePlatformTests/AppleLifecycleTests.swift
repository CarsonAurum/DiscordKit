// File: Tests/DiscordApplePlatformTests/AppleLifecycleTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordApplePlatform
import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Testing

/// Conservative host-policy checks and deterministic resource drain/restart behavior.
@Suite("Apple lifecycle")
struct AppleLifecycleTests {
    /// Every unqualified host/capability remains explicit; compiling is not availability.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func qualificationAndPolicyMatrix() async throws {
        for host in AppleHost.allCases {
            let lifecycle = try AppleLifecycle(host: host)
            for capability in PlatformCapability.allCases {
                #expect(await lifecycle.availability(of: capability) != .available)
            }
        }
        let unqualified = try AppleLifecycle(host: .macOS)
        #expect(await unqualified.availability(of: .http) == .unavailable(.notQualified))
        let host = AppleHost.current
        #expect(AppleHost.allCases.contains(host))
        let watch = try AppleLifecycle(host: .watchOS, qualifiedCapabilities: Set(PlatformCapability.allCases))
        #expect(await watch.availability(of: .http) == .available)
        for capability in PlatformCapability.allCases where capability != .http {
            #expect(await watch.availability(of: capability) != .available)
        }
        let other = try AppleLifecycle(host: .other, qualifiedCapabilities: [.http])
        #expect(await other.availability(of: .http) == .unavailable(.unsupportedPlatform))
        for host in [AppleHost.iOS, .tvOS, .visionOS] {
            let lifecycle = try AppleLifecycle(host: host, qualifiedCapabilities: [.http, .webSocket, .localIPC, .httpIngress])
            #expect(await lifecycle.availability(of: .http) == .available)
            #expect(await lifecycle.availability(of: .webSocket) == .available)
            #expect(await lifecycle.availability(of: .localIPC) == .unavailable(.restrictedByHost))
            #expect(await lifecycle.availability(of: .httpIngress) == .unavailable(.restrictedByHost))
            await lifecycle.transition(to: .background)
            #expect(await lifecycle.availability(of: .http) == .unavailable(.restrictedByHost))
        }
    }

    /// Bounds registration and leaves ownership with callers on validation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func limitsAndFailedRetention() async throws {
        #expect(throws: AppleLifecycleFailure.invalidLimit) { try AppleLifecycle(maximumResources: 0) }
        let lifecycle = try AppleLifecycle(host: .macOS, qualifiedCapabilities: [.http], maximumResources: 1)
        let resource = CountingResource()
        let registration = try await lifecycle.retain(resource, requiring: .http)
        await #expect(throws: AppleLifecycleFailure.resourceLimit) {
            try await lifecycle.retain(CountingResource(), requiring: .http)
        }
        await #expect(throws: DiscordError.capabilityUnavailable(.notImplemented)) {
            try await lifecycle.retain(CountingResource(), requiring: .audioCapture)
        }
        #expect(await lifecycle.retainedResourceCount() == 1)
        await lifecycle.release(registration)
        await lifecycle.release(registration)
        #expect(await resource.closeCount() == 1)
        #expect(await lifecycle.retainedResourceCount() == 0)
    }

    /// Foreground state changes preserve resources; suspension closes once and permits restart.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lifecycleDrainAndRestart() async throws {
        let lifecycle = try AppleLifecycle(host: .macOS, qualifiedCapabilities: [.http])
        let first = CountingResource()
        _ = try await lifecycle.retain(first, requiring: .http)
        await lifecycle.transition(to: .inactive)
        await lifecycle.transition(to: .background)
        #expect(await first.closeCount() == 0)
        await lifecycle.transition(to: .suspended)
        #expect(await first.closeCount() == 1)
        #expect(await lifecycle.retainedResourceCount() == 0)
        #expect(await lifecycle.availability(of: .http) == .unavailable(.restrictedByHost))
        await lifecycle.transition(to: .active)
        let second = CountingResource()
        _ = try await lifecycle.retain(second, requiring: .http)
        await lifecycle.close()
        await lifecycle.close()
        #expect(await first.closeCount() == 1)
        #expect(await second.closeCount() == 1)
        #expect(await lifecycle.retainedResourceCount() == 0)
    }

    /// Admission closes before cleanup suspension; competing closes release each resource once.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func suspendedCleanupAndConcurrentClose() async throws {
        let entered = TestBarrier()
        let finish = TestBarrier()
        let resource = CountingResource(entered: entered, finish: finish)
        let lifecycle = try AppleLifecycle(host: .iOS, qualifiedCapabilities: [.webSocket])
        _ = try await lifecycle.retain(resource, requiring: .webSocket)
        let first = Task { await lifecycle.transition(to: .background) }
        try await entered.wait()
        #expect(await lifecycle.availability(of: .webSocket) == .unavailable(.restrictedByHost))
        await #expect(throws: DiscordError.capabilityUnavailable(.restrictedByHost)) {
            try await lifecycle.retain(CountingResource(), requiring: .webSocket)
        }
        let second = Task { await lifecycle.close() }
        finish.open()
        await first.value
        await second.value
        #expect(await resource.closeCount() == 1)
        #expect(await lifecycle.retainedResourceCount() == 0)
    }

    /// Cancellation prevents admission, while stopped cleanup still releases owned resources.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndCleanup() async throws {
        let lifecycle = try AppleLifecycle(host: .macOS, qualifiedCapabilities: [.http])
        let resource = CountingResource()
        _ = try await lifecycle.retain(resource, requiring: .http)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) {
                try await lifecycle.retain(CountingResource(), requiring: .http)
            }
            await lifecycle.close()
        }
        await task.value
        #expect(await resource.closeCount() == 1)
        #expect(await lifecycle.retainedResourceCount() == 0)
    }
}

/// Test resource whose optional barriers expose cleanup ownership without wall-time sleeps.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor CountingResource: TransportResource {
    private var count = 0
    private let entered: TestBarrier?
    private let finish: TestBarrier?

    /// Stores optional cleanup barriers without starting work.
    /// - Parameters:
    ///   - entered: Opened as soon as cleanup begins; nil omits the notification.
    ///   - finish: Cleanup waits here when provided; nil closes immediately.
    init(entered: TestBarrier? = nil, finish: TestBarrier? = nil) {
        self.entered = entered
        self.finish = finish
    }

    /// Records cleanup and optionally suspends until the test permits completion.
    /// Cancellation is ignored intentionally to model cleanup that must finish.
    func close() async {
        count += 1
        entered?.open()
        if let finish { try? await finish.wait() }
    }

    /// Reports the number of cleanup invocations for ownership assertions.
    /// - Returns: Total calls, including any erroneous duplicate invocation.
    func closeCount() -> Int { count }
}
