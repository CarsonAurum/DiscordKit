// File: Tests/DiscordApplePlatformTests/AppleAudioRoutesTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if os(macOS) && canImport(AVFoundation) && canImport(os)
import CoreAudio
@testable import DiscordApplePlatform
import Foundation
import Testing
import os

/// Exercises startup race rejection and exact route-listener ownership without opening native devices.
@MainActor @Suite("Apple selected-device liveness and route observation")
struct AppleAudioRoutesTests {
    /// Default routes require no selected-ID query; duplex selections read the device exactly once.
    @Test func livenessSelectedDirectionOrderingAndDeduplication() throws {
        let properties = RouteTestLiveness()
        try AppleAudioDeviceLiveness.verify(input: nil, output: nil, using: properties)
        #expect(properties.reads.isEmpty)
        try AppleAudioDeviceLiveness.verify(input: 11, output: nil, using: properties)
        #expect(properties.reads == [11])
        properties.reads = []
        try AppleAudioDeviceLiveness.verify(input: nil, output: 12, using: properties)
        #expect(properties.reads == [12])
        properties.reads = []
        try AppleAudioDeviceLiveness.verify(input: 11, output: 11, using: properties)
        #expect(properties.reads == [11])
        properties.reads = []
        try AppleAudioDeviceLiveness.verify(input: 11, output: 12, using: properties)
        #expect(properties.reads == [11, 12])
    }

    /// A stale but still bound device ID cannot authorize startup after an earlier unobserved unplug.
    /// - Parameter disconnected: Selected input or output to disconnect before the second startup checkpoint.
    @Test(arguments: [AudioDeviceID(11), AudioDeviceID(12)])
    func livenessRejectsEarlierUnplugAndStartupDisconnection(_ disconnected: AudioDeviceID) throws {
        let properties = RouteTestLiveness()
        try AppleAudioDeviceLiveness.verify(input: 11, output: 12, using: properties)
        properties.dead = [disconnected]
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioDeviceLiveness.verify(input: 11, output: 12, using: properties)
        }
        properties.dead = []
        try AppleAudioDeviceLiveness.verify(input: 11, output: 12, using: properties)
        properties.failed = disconnected
        #expect(throws: AppleAudioError.nativeFailure) {
            try AppleAudioDeviceLiveness.verify(input: 11, output: 12, using: properties)
        }
    }

    /// Unknown IDs fail closed without a native query or an unrelated default fallback.
    @Test func livenessRejectsUnknownIDs() throws {
        let properties = RouteTestLiveness()
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioDeviceLiveness.verify(input: 0, output: 11, using: properties)
        }
        #expect(properties.reads.isEmpty)
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioDeviceLiveness.verify(input: nil, output: 0, using: properties)
        }
        #expect(properties.reads.isEmpty)
    }

    /// Default, selected, shared-duplex and disabled directions install only their exact bounded properties.
    @Test func observationPropertiesAndDirectionBounds() throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let topology = AppleAudioRouteProperty(object: system, selector: kAudioHardwarePropertyDevices)
        let defaultInput = AppleAudioRouteProperty(object: system, selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutput = AppleAudioRouteProperty(object: system, selector: kAudioHardwarePropertyDefaultOutputDevice)
        let aliveInput = AppleAudioRouteProperty(object: 11, selector: kAudioDevicePropertyDeviceIsAlive)
        let aliveOutput = AppleAudioRouteProperty(object: 12, selector: kAudioDevicePropertyDeviceIsAlive)
        for (input, output, capture, playback, expected): (AudioDeviceID?, AudioDeviceID?, Bool, Bool,
                                                         [AppleAudioRouteProperty]) in [
            (nil, nil, true, true, [defaultInput, defaultOutput, topology]),
            (11, 12, true, true, [topology, aliveInput, aliveOutput]),
            (11, 11, true, true, [topology, aliveInput]),
            (11, nil, true, true, [defaultOutput, topology, aliveInput]),
            (nil, 12, true, true, [defaultInput, topology, aliveOutput]),
            (nil, nil, true, false, [defaultInput, topology]),
            (nil, nil, false, true, [defaultOutput, topology]),
            (0, 12, false, true, [topology, aliveOutput]),
            (11, 0, true, false, [topology, aliveInput]),
        ] {
            let properties = RouteTestListeners()
            let observation = AppleAudioRouteObservation(properties: properties)
            let bridge = AppleAudioInvalidationBridge()
            try observation.begin(input: input, output: output, captureEnabled: capture, playbackEnabled: playback,
                invalidation: bridge, callbacks: .init(capture: { _ in false }, stopped: { _ in }), generation: bridge.begin())
            #expect(properties.attempts == expected)
            #expect(properties.cancellations.isEmpty)
            observation.stop()
            #expect(properties.cancellations == Array(expected.indices.reversed()))
            observation.stop()
            #expect(properties.cancellations == Array(expected.indices.reversed()))
            bridge.end()
        }
    }

    /// Every possible partial registration failure immediately removes earlier exact listener identities.
    /// - Parameter failureIndex: Zero-based registration attempt to reject, covering every partial-set boundary.
    @Test(arguments: [0, 1, 2])
    func observationPartialFailureRollbackAndRetry(_ failureIndex: Int) throws {
        let properties = RouteTestListeners()
        properties.failAt = failureIndex
        let observation = AppleAudioRouteObservation(properties: properties)
        let bridge = AppleAudioInvalidationBridge()
        let generation = bridge.begin()
        let callbacks = AppleAudioCallbacks(capture: { _ in false }, stopped: { _ in })
        #expect(throws: AppleAudioError.nativeFailure) {
            try observation.begin(input: 11, output: 12, captureEnabled: true, playbackEnabled: true,
                invalidation: bridge, callbacks: callbacks, generation: generation)
        }
        #expect(properties.attempts.count == failureIndex + 1)
        #expect(properties.cancellations == Array((0..<failureIndex).reversed()))
        observation.stop()
        #expect(properties.cancellations.count == failureIndex)
        properties.failAt = nil
        try observation.begin(input: 11, output: 12, captureEnabled: true, playbackEnabled: true,
            invalidation: bridge, callbacks: callbacks, generation: generation)
        #expect(properties.attempts.count == failureIndex + 4)
        observation.stop()
        #expect(properties.cancellations.count == failureIndex + 3)
        bridge.end()
    }

    /// Duplicate begin and unknown IDs retain no extra observers, and deinit removes the owned set.
    @Test func observationDuplicateStartInvalidIDAndDeinit() throws {
        let properties = RouteTestListeners()
        let bridge = AppleAudioInvalidationBridge()
        let generation = bridge.begin()
        let callbacks = AppleAudioCallbacks(capture: { _ in false }, stopped: { _ in })
        var observation: AppleAudioRouteObservation? = AppleAudioRouteObservation(properties: properties)
        for (input, output): (AudioDeviceID?, AudioDeviceID?) in [(0, nil), (nil, 0), (11, 0)] {
            #expect(throws: AppleAudioError.deviceUnavailable) {
                try observation?.begin(input: input, output: output, captureEnabled: true, playbackEnabled: true,
                    invalidation: bridge, callbacks: callbacks, generation: generation)
            }
            #expect(properties.attempts.isEmpty)
        }
        try observation?.begin(input: 11, output: 11, captureEnabled: true, playbackEnabled: true,
            invalidation: bridge, callbacks: callbacks, generation: generation)
        #expect(throws: AppleAudioError.alreadyRunning) {
            try observation?.begin(input: nil, output: nil, captureEnabled: true, playbackEnabled: true,
                invalidation: bridge, callbacks: callbacks, generation: generation)
        }
        #expect(properties.attempts.count == 2)
        weak let weakObservation = observation
        observation = nil
        #expect(weakObservation == nil)
        #expect(properties.cancellations == [1, 0])
        bridge.end()
    }

    /// Concurrent callback bursts use one deferred slot; callbacks retained after stop cannot stop a restart.
    @Test func observationCallbacksAreDeferredBoundedAndGenerationFenced() async throws {
        let properties = RouteTestListeners()
        let delivery = RouteTestDelivery()
        let bridge = AppleAudioInvalidationBridge { action in delivery.enqueue(action) }
        let observation = AppleAudioRouteObservation(properties: properties)
        let callbacks = AppleAudioCallbacks(capture: { _ in false }, stopped: { reason in
            delivery.reasons.append(reason)
        })
        try observation.begin(input: 11, output: 11, captureEnabled: true, playbackEnabled: true,
            invalidation: bridge, callbacks: callbacks, generation: bridge.begin())
        let oldListeners = properties.listeners
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 { group.addTask { oldListeners[index % oldListeners.count]() } }
        }
        #expect(delivery.pendingCount() == 1)
        #expect(delivery.reasons.isEmpty)
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged])
        oldListeners[0]()
        bridge.end()
        observation.stop()
        try observation.begin(input: nil, output: nil, captureEnabled: false, playbackEnabled: true,
            invalidation: bridge, callbacks: callbacks, generation: bridge.begin())
        oldListeners[0]()
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged])
        properties.listeners.last?()
        #expect(delivery.pendingCount() == 1)
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged, .routeChanged])
        bridge.end()
        observation.stop()
        properties.listeners.last?()
        #expect(delivery.pendingCount() == 0)
    }
}

/// Synthetic alive flags can change between native listener registration and engine-start readback.
@MainActor private final class RouteTestLiveness: AppleAudioDeviceLivenessProperties {
    var reads: [AudioDeviceID] = []
    var dead: Set<AudioDeviceID> = []
    var failed: AudioDeviceID?

    /// Creates a bounded empty history without native queries.
    init() {}

    /// Records one selected-device query and supplies its deterministic liveness/error result.
    /// - Parameter device: Synthetic device ID to inspect.
    /// - Returns: False only for IDs in the test's dead-device set.
    /// - Throws: `nativeFailure` when the test selects this ID for a native query failure.
    func deviceIsAlive(_ device: AudioDeviceID) throws -> Bool {
        reads.append(device)
        if device == failed { throw AppleAudioError.nativeFailure }
        return !dead.contains(device)
    }
}

/// Synthetic listener installer retains old callbacks deliberately to exercise cancellation races.
@MainActor private final class RouteTestListeners: AppleAudioRouteListenerProperties {
    var attempts: [AppleAudioRouteProperty] = []
    var listeners: [@Sendable () -> Void] = []
    var cancellations: [Int] = []
    var failAt: Int?

    /// Creates an inert listener registry with no system observers.
    init() {}

    /// Records the exact registration and returns cleanup retaining that registration's index.
    /// - Parameters:
    ///   - property: Synthetic global property identity to record.
    ///   - changed: Deferred-invalidation producer, retained after removal to test native late delivery.
    /// - Returns: Cleanup that records the exact successful registration index.
    /// - Throws: `nativeFailure` at the selected attempt index without retaining its callback.
    func install(_ property: AppleAudioRouteProperty,
                 changed: @escaping @Sendable () -> Void) throws -> @MainActor () -> Void {
        let index = attempts.count
        attempts.append(property)
        if index == failAt { throw AppleAudioError.nativeFailure }
        listeners.append(changed)
        return { self.cancellations.append(index) }
    }
}

/// Manual one-slot scheduler records actions without running lifecycle teardown inside a native observer.
@MainActor private final class RouteTestDelivery: Sendable {
    nonisolated private let actions = OSAllocatedUnfairLock(initialState: [@MainActor @Sendable () -> Void]())
    var reasons: [AppleAudioStopReason] = []

    /// Creates empty manually driven delivery state with no dispatched work.
    init() {}

    /// Records a scheduled action from any simulated native callback thread.
    /// - Parameter action: Deferred MainActor callback; never invoked synchronously here.
    nonisolated func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
        actions.withLock { $0.append(action) }
    }

    /// Copies the queued-action count under the same short lock used by simulated callbacks.
    /// - Returns: Number of pending actions, expected to remain at most one per invalidation bridge.
    nonisolated func pendingCount() -> Int { actions.withLock { $0.count } }

    /// Executes one retained callback on MainActor after its simulated native observer has returned.
    /// Empty queues are harmless; callback reentrancy occurs outside the scheduler lock.
    func runNext() {
        let action = actions.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        action?()
    }
}
#endif
