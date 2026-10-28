// File: Tests/DiscordApplePlatformTests/AppleAudioTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(AVFoundation) && canImport(os)
import AVFoundation
@testable import DiscordApplePlatform
import DiscordMedia
import DiscordTestSupport
import Testing
import os

/// Deterministic native-boundary ownership and synthetic layout tests; never opens a device.
@MainActor @Suite("Apple audio ownership")
struct AppleAudioTests {
    /// Existing injected backends report unsupported discovery without opening native hardware.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func defaultBackendDiscoveryIsExplicitlyUnsupported() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        #expect(throws: AppleAudioError.unsupportedDeviceSelection) { try device.availableDevices() }
        #expect(backend.startCount == 0 && backend.statusCount == 0 && backend.stopCount == 0)
    }

    /// Invalid direction/channel/frame/budget values fail before any native backend is constructed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func configurationValidation() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        #expect(throws: AppleAudioError.invalidConfiguration) {
            try AppleAudioConfiguration(captureEnabled: false, playbackEnabled: false, playbackFormat: format)
        }
        for channelCount in [-1, 0, 3, Int.max] {
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(captureChannelCount: channelCount, playbackFormat: format)
            }
        }
        for limit in [-1, 0, 4097, Int.max] {
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(captureBufferFrames: limit, playbackFormat: format)
            }
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, maximumCaptureBlocks: limit)
            }
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, maximumPlaybackBlocks: limit)
            }
        }
        for limit in [-1, 0, 67_108_865, Int.max] {
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, maximumCaptureBytes: limit)
            }
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, maximumPlaybackBytes: limit)
            }
        }
        let maximum = try AppleAudioConfiguration(captureBufferFrames: 4096, playbackFormat: format,
                                                 maximumCaptureBlocks: 4096, maximumCaptureBytes: 67_108_864,
                                                 maximumPlaybackBlocks: 4096, maximumPlaybackBytes: 67_108_864,
                                                 sessionPolicy: .exclusiveForeground)
        #expect(maximum.sessionPolicy == .exclusiveForeground)
        #expect(maximum.captureEnabled && maximum.playbackEnabled)
    }

    /// Construction is inert, permission queries are explicit, and denied capture never starts hardware.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [AppleAudioPermission.undetermined, .denied, .restricted])
    func permissionRequiredWithoutImplicitPrompt(_ permission: AppleAudioPermission) async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        backend.permission = permission
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        #expect(backend.startCount == 0 && backend.statusCount == 0 && backend.requestCount == 0)
        #expect(device.snapshot().state == .idle)
        #expect(device.recordingPermission() == permission)
        #expect(backend.statusCount == 1)
        #expect(throws: AppleAudioError.microphonePermissionRequired(permission)) { try device.start() }
        #expect(backend.startCount == 0 && backend.requestCount == 0)
        await #expect(throws: AppleAudioError.notRunning) { try await device.read() }
        await #expect(throws: AppleAudioError.notRunning) {
            try await device.write(PCMBuffer(format: format, samples: [0]))
        }
    }

    /// Playback-only operation never inspects microphone authorization, including when denied.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func playbackOnlyAndEmptyBlocks() async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: nil)
        backend.permission = .denied
        let configuration = try AppleAudioConfiguration(captureEnabled: false, playbackFormat: format)
        let device = AppleAudioDevice(configuration: configuration, backend: backend)
        #expect(try device.start() == nil)
        #expect(backend.statusCount == 0)
        #expect(throws: AppleAudioError.alreadyRunning) { try device.start() }
        try await device.write(PCMBuffer(format: format, samples: []))
        #expect(backend.playbackCount == 0)
        let callbacks = try #require(backend.callbacks.last)
        #expect(!callbacks.capture(try PCMBuffer(format: format, samples: [0])))
        #expect(try await device.read() == nil)
        device.stop()
        #expect(device.snapshot().captureFormat == nil)
        #expect(device.snapshot().state == .stopped(.requested))
    }

    /// Capture FIFO budgets reject new/mismatched blocks without evicting accepted audio.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func captureBudgetsFormatAndFIFO() async throws {
        let format = try PCMFormat(sampleRate: 44_100, channelCount: 1)
        let configuration = try AppleAudioConfiguration(playbackFormat: format, maximumCaptureBlocks: 2,
                                                       maximumCaptureBytes: 12)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: configuration, backend: backend)
        #expect(try device.start() == format)
        let callback = try #require(backend.callbacks.last)
        let first = try PCMBuffer(format: format, samples: [0.25, 0.5])
        let second = try PCMBuffer(format: format, samples: [-0.25])
        #expect(callback.capture(first))
        #expect(!callback.capture(first))
        #expect(callback.capture(second))
        #expect(!callback.capture(try PCMBuffer(format: format, samples: [])))
        #expect(device.snapshot().captureBlocks == 2 && device.snapshot().captureBytes == 12)
        #expect(device.snapshot().droppedCaptureBlocks == 2)
        #expect(try await device.read() == first)
        #expect(device.snapshot().captureBytes == 4)
        #expect(try await device.read() == second)
        #expect(try await device.read() == nil)
        let wrongRate = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let wrongChannels = try PCMFormat(sampleRate: 44_100, channelCount: 2)
        #expect(!callback.capture(try PCMBuffer(format: wrongRate, samples: [0])))
        #expect(!callback.capture(try PCMBuffer(format: wrongChannels, samples: [0, 0])))
        #expect(device.snapshot().captureBytes == 0)
        #expect(device.snapshot().droppedCaptureBlocks == 4)
        device.stop()
        #expect(!callback.capture(first))
    }

    /// Native scheduled payload remains charged until completion; repeated/stale callbacks release nothing.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func playbackBudgetsFailureAndCompletionFencing() async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let configuration = try AppleAudioConfiguration(playbackFormat: format, maximumPlaybackBlocks: 2,
                                                       maximumPlaybackBytes: 12)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: configuration, backend: backend)
        try device.start()
        let first = try PCMBuffer(format: format, samples: [0.25, 0.5])
        let second = try PCMBuffer(format: format, samples: [-0.25])
        try await device.write(first)
        await #expect(throws: AppleAudioError.queueFull) { try await device.write(first) }
        try await device.write(second)
        await #expect(throws: AppleAudioError.queueFull) { try await device.write(second) }
        #expect(device.snapshot().playbackBlocks == 2 && device.snapshot().playbackBytes == 12)
        let oldCompletion = backend.completions[0]
        oldCompletion()
        oldCompletion()
        #expect(device.snapshot().playbackBytes == 4)
        backend.failPlayback = true
        await #expect(throws: AppleAudioError.nativeFailure) { try await device.write(first) }
        #expect(device.snapshot().playbackBlocks == 1 && device.snapshot().playbackBytes == 4)
        backend.failPlayback = false
        let wrong = try PCMBuffer(format: PCMFormat(sampleRate: 48_000, channelCount: 2), samples: [0, 0])
        await #expect(throws: AppleAudioError.incompatibleFormat) { try await device.write(wrong) }
        let staleCompletion = backend.completions[1]
        device.stop()
        #expect(device.snapshot().playbackBytes == 0)
        try device.start()
        try await device.write(first)
        staleCompletion()
        #expect(device.snapshot().playbackBytes == 8)
        backend.completions.last?()
        #expect(device.snapshot().playbackBlocks == 0 && device.snapshot().playbackBytes == 0)
        try await device.write(first)
        let concurrentCompletion = try #require(backend.completions.last)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { concurrentCompletion() } }
        }
        #expect(device.snapshot().playbackBlocks == 0 && device.snapshot().playbackBytes == 0)
    }

    /// Every backend invalidation clears both directions and requires explicit generation-fenced restart.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [AppleAudioStopReason.interruption, .routeChanged, .configurationChanged, .mediaServicesReset])
    func lifecycleStopsAndExplicitRestart(_ reason: AppleAudioStopReason) async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        try device.start()
        let callbacks = try #require(backend.callbacks.last)
        let buffer = try PCMBuffer(format: format, samples: [0.5])
        #expect(callbacks.capture(buffer))
        try await device.write(buffer)
        callbacks.stopped(reason)
        #expect(device.snapshot().state == .stopped(reason))
        #expect(device.snapshot().captureBlocks == 0 && device.snapshot().playbackBlocks == 0)
        #expect(backend.stopCount == 1 && backend.startCount == 1)
        #expect(!callbacks.capture(buffer))
        await #expect(throws: AppleAudioError.notRunning) { try await device.read() }
        try device.start()
        callbacks.stopped(.failed)
        #expect(device.snapshot().state == .running)
        #expect(!callbacks.capture(buffer))
        let fresh = try #require(backend.callbacks.last)
        #expect(fresh.capture(buffer))
        #expect(try await device.read() == buffer)
        device.stop()
        device.stop()
        #expect(device.snapshot().captureBytes == 0 && device.snapshot().playbackBytes == 0)
    }

    /// Partial native failures and inconsistent formats stop resources and discard early callback media.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func failedStartCleanupAndFormatValidation() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        backend.captureDuringStart = try PCMBuffer(format: format, samples: [0.5])
        backend.failStart = true
        #expect(throws: AppleAudioError.nativeFailure) { try device.start() }
        #expect(backend.stopCount == 1)
        #expect(device.snapshot().captureBytes == 0 && device.snapshot().state == .stopped(.failed))
        backend.failStart = false
        backend.format = nil
        #expect(throws: AppleAudioError.unavailableFormat) { try device.start() }
        backend.format = try PCMFormat(sampleRate: 48_000, channelCount: 2)
        #expect(throws: AppleAudioError.unavailableFormat) { try device.start() }
        backend.format = try PCMFormat(sampleRate: 44_100, channelCount: 1)
        #expect(throws: AppleAudioError.unavailableFormat) { try device.start() }
        backend.captureDuringStart = nil
        #expect(try device.start() == backend.format)
        #expect(device.snapshot().captureBlocks == 0)
    }

    /// Permission requests do not accumulate; cancellation waits for an outstanding native response.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func permissionSerializationAndCancellation() async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        backend.permission = .undetermined
        backend.permissionEntered = TestBarrier()
        backend.suspendPermission = true
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        let request = Task { try await device.requestRecordingPermission() }
        try await backend.permissionEntered?.wait()
        #expect(backend.requestCount == 1 && backend.startCount == 0)
        await #expect(throws: AppleAudioError.permissionRequestInProgress) { try await device.requestRecordingPermission() }
        request.cancel()
        await #expect(throws: AppleAudioError.permissionRequestInProgress) { try await device.requestRecordingPermission() }
        backend.permission = .granted
        backend.finishPermission()
        await #expect(throws: CancellationError.self) { try await request.value }
        backend.suspendPermission = false
        #expect(try await device.requestRecordingPermission() == .granted)
        #expect(backend.startCount == 0)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await device.requestRecordingPermission() }
        }
        await cancelled.value
        #expect(backend.requestCount == 2)
    }

    /// Cancellation before admission preserves buffers; cancellation during native start closes resources.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationBeforeAdmissionAndDuringStart() async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        let cancelledStart = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try device.start() }
        }
        await cancelledStart.value
        #expect(backend.startCount == 0)
        try device.start()
        let buffer = try PCMBuffer(format: format, samples: [0.5])
        #expect(backend.callbacks.last?.capture(buffer) == true)
        let cancelledMedia = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await device.read() }
            await #expect(throws: CancellationError.self) { try await device.write(buffer) }
            device.stop()
        }
        await cancelledMedia.value
        #expect(backend.playbackCount == 0 && device.snapshot().captureBlocks == 0)
        backend.cancelDuringStart = true
        let cancelledDuringStart = Task {
            #expect(throws: CancellationError.self) { try device.start() }
        }
        _ = await cancelledDuringStart.value
        #expect(device.snapshot().state == .stopped(.failed))
        #expect(backend.stopCount == 2)
    }

    /// Concurrent capture callbacks respect one budget without actor tasks or over-admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentCallbacksAndCaptureOnlyPlaybackRejection() async throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        let configuration = try AppleAudioConfiguration(playbackEnabled: false, playbackFormat: format,
                                                       maximumCaptureBlocks: 4, maximumCaptureBytes: 16)
        let device = AppleAudioDevice(configuration: configuration, backend: backend)
        try device.start()
        let callbacks = try #require(backend.callbacks.last)
        let buffer = try PCMBuffer(format: format, samples: [0.25])
        let admitted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 { group.addTask { callbacks.capture(buffer) } }
            var count = 0
            for await result in group { if result { count += 1 } }
            return count
        }
        #expect(admitted == 4)
        #expect(device.snapshot().captureBytes == 16 && device.snapshot().droppedCaptureBlocks == 96)
        await #expect(throws: AppleAudioError.notRunning) { try await device.write(buffer) }
        device.stop()
        #expect(device.snapshot().captureBytes == 0)
    }

    /// Releasing the owner performs cleanup even when an embedding app omitted its explicit stop.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deinitializationStopsBackend() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let backend = AudioTestBackend(format: format)
        var device: AppleAudioDevice? = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format),
                                                        backend: backend)
        try device?.start()
        let callbacks = try #require(backend.callbacks.last)
        weak let weakDevice = device
        device = nil
        #expect(weakDevice == nil)
        #expect(backend.stopCount == 1)
        #expect(!callbacks.capture(try PCMBuffer(format: format, samples: [0])))
    }

    /// Native observer storms occupy one deferred slot and never tear down on the observer's stack.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deferredNativeInvalidationCoalescingAndGenerations() throws {
        let delivery = AudioTestDelivery()
        let bridge = AppleAudioInvalidationBridge { action in delivery.enqueue(action) }
        let first = bridge.begin()
        let callbacks = AppleAudioCallbacks(capture: { _ in false }, stopped: { reason in
            delivery.reasons.append(reason)
        })
        for _ in 0..<100 { bridge.enqueue(.configurationChanged, callbacks: callbacks, generation: first) }
        bridge.enqueue(.routeChanged, callbacks: callbacks, generation: first)
        #expect(delivery.reasons.isEmpty)
        #expect(delivery.pendingCount() == 1)
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged])
        bridge.enqueue(.interruption, callbacks: callbacks, generation: first)
        bridge.end()
        let second = bridge.begin()
        bridge.enqueue(.failed, callbacks: callbacks, generation: first)
        #expect(delivery.pendingCount() == 1)
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged])
        bridge.enqueue(.mediaServicesReset, callbacks: callbacks, generation: second)
        bridge.end()
        let third = bridge.begin()
        bridge.enqueue(.interruption, callbacks: callbacks, generation: third)
        #expect(delivery.pendingCount() == 1)
        delivery.runNext()
        #expect(delivery.reasons == [.routeChanged, .interruption])
        bridge.end()
    }

    /// Benign configuration readback cannot overwrite a pending unconditional native stop in
    /// either arrival order; all cases retain one deferred slot and the original stop callback.
    /// - Parameters:
    ///   - reason: Unconditional native route/interruption/reset/failure event to preserve.
    ///   - configurationFirst: Whether a benign setup event also precedes the required stop.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [AppleAudioStopReason.routeChanged, .interruption, .mediaServicesReset, .failed], [false, true])
    func configurationCannotEraseRequiredInvalidation(_ reason: AppleAudioStopReason,
                                                      _ configurationFirst: Bool) {
        let delivery = AudioTestDelivery()
        let bridge = AppleAudioInvalidationBridge { action in delivery.enqueue(action) }
        let generation = bridge.begin()
        let required = AppleAudioCallbacks(capture: { _ in false }, stopped: { delivery.reasons.append($0) })
        let benign = AppleAudioCallbacks(capture: { _ in false }, stopped: { _ in })
        if configurationFirst { bridge.enqueue(.configurationChanged, callbacks: benign, generation: generation) }
        bridge.enqueue(reason, callbacks: required, generation: generation)
        for _ in 0..<10 { bridge.enqueue(.configurationChanged, callbacks: benign, generation: generation) }
        #expect(delivery.pendingCount() == 1 && delivery.reasons.isEmpty)
        delivery.runNext()
        #expect(delivery.reasons == [reason] && delivery.pendingCount() == 0)
        bridge.end()
    }

    /// Synthetic planar/interleaved native buffers round-trip channels without device access.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func nativePCMLayoutConversion(_ interleaved: Bool) throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 2)
        let nativeFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                     channels: 2, interleaved: interleaved))
        let portable = try PCMBuffer(format: format, samples: [1, -1, 0.25, -0.5, 0, 0.75])
        let native = try AppleAudioPCMConversion.playbackBuffer(portable, format: nativeFormat)
        #expect(native.frameLength == 3)
        #expect(try AppleAudioPCMConversion.captureBuffer(native, channelCount: 2, frameOffset: 0, frameCount: 3) == portable)
        let mono = try AppleAudioPCMConversion.captureBuffer(native, channelCount: 1, frameOffset: 1, frameCount: 2)
        #expect(mono.samples == [0.25, 0])
        let empty = try AppleAudioPCMConversion.captureBuffer(native, channelCount: 2, frameOffset: 3, frameCount: 0)
        #expect(empty.samples.isEmpty)
        let emptyNative = try AppleAudioPCMConversion.playbackBuffer(empty, format: nativeFormat)
        #expect(emptyNative.frameLength == 0)
        let channels = try #require(native.floatChannelData)
        channels[0][0] = .infinity
        if interleaved { channels[0][1] = -2 }
        else { channels[1][0] = -2 }
        let clipped = try AppleAudioPCMConversion.captureBuffer(native, channelCount: 2, frameOffset: 0, frameCount: 1)
        #expect(clipped.samples == [0, -1])
    }

    /// Native conversion rejects invalid channel/range/type/size before reading outside supplied storage.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nativePCMConversionFailures() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let nativeFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let native = try #require(AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: 961))
        native.frameLength = 961
        for (offset, count, channels) in [(-1, 1, 1), (0, -1, 1), (962, 0, 1), (960, 2, 1),
                                           (0, 1, 0), (0, 1, 2), (Int.max, Int.max, 1)] {
            #expect(throws: AppleAudioError.unavailableFormat) {
                try AppleAudioPCMConversion.captureBuffer(native, channelCount: channels, frameOffset: offset, frameCount: count)
            }
        }
        #expect(throws: MediaError.bufferTooLarge) {
            try AppleAudioPCMConversion.captureBuffer(native, channelCount: 1, frameOffset: 0, frameCount: 961)
        }
        let buffer = try PCMBuffer(format: format, samples: [0])
        let wrongRate = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        #expect(throws: AppleAudioError.incompatibleFormat) {
            try AppleAudioPCMConversion.playbackBuffer(buffer, format: wrongRate)
        }
        let integer = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8_000,
                                                channels: 1, interleaved: false))
        let integerBuffer = try #require(AVAudioPCMBuffer(pcmFormat: integer, frameCapacity: 1))
        integerBuffer.frameLength = 1
        #expect(throws: AppleAudioError.unavailableFormat) {
            try AppleAudioPCMConversion.captureBuffer(integerBuffer, channelCount: 1, frameOffset: 0, frameCount: 1)
        }
        #expect(throws: AppleAudioError.incompatibleFormat) {
            try AppleAudioPCMConversion.playbackBuffer(buffer, format: integer)
        }
    }
}

/// Inert MainActor fake exposing native lifecycle/admission outcomes without microphone/output calls.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor private final class AudioTestBackend: AppleAudioBackend {
    var permission: AppleAudioPermission = .granted
    var format: PCMFormat?
    var statusCount = 0
    var requestCount = 0
    var startCount = 0
    var stopCount = 0
    var playbackCount = 0
    var failStart = false
    var failPlayback = false
    var cancelDuringStart = false
    var captureDuringStart: PCMBuffer?
    var callbacks: [AppleAudioCallbacks] = []
    var completions: [@Sendable () -> Void] = []
    var permissionEntered: TestBarrier?
    var suspendPermission = false
    private var permissionWaiter: CheckedContinuation<Void, Never>?

    /// Stores a synthetic native format and leaves every observed side-effect count at zero.
    /// - Parameter format: Returned capture layout; nil simulates playback-only or inconsistent backend.
    init(format: PCMFormat?) { self.format = format }

    /// Records an explicit permission inspection without opening any real system API.
    /// - Returns: Test-controlled permission state.
    func recordingPermission() -> AppleAudioPermission { statusCount += 1; return permission }

    /// Records an explicit request and optionally suspends on an uncancellable synthetic prompt.
    /// - Returns: Test-controlled state when finishPermission releases the native response.
    func requestRecordingPermission() async -> AppleAudioPermission {
        requestCount += 1
        permissionEntered?.open()
        if suspendPermission { await withCheckedContinuation { permissionWaiter = $0 } }
        return permission
    }

    /// Completes the one synthetic native prompt without creating a task or requesting real permission.
    /// Repeated calls are harmless and release no more than one continuation.
    func finishPermission() {
        let waiter = permissionWaiter
        permissionWaiter = nil
        waiter?.resume()
    }

    /// Records current-generation callbacks and optionally simulates early capture/failure/cancellation.
    /// - Parameters:
    ///   - configuration: Validated owner policy; no native interpretation is needed by this fake.
    ///   - callbacks: Retained only for bounded deterministic stale-generation tests.
    /// - Returns: Test-controlled capture layout.
    /// - Throws: Synthetic error before success when failStart is enabled.
    func start(configuration: AppleAudioConfiguration, callbacks: AppleAudioCallbacks) throws -> PCMFormat? {
        startCount += 1
        self.callbacks.append(callbacks)
        if let captureDuringStart { _ = callbacks.capture(captureDuringStart) }
        if cancelDuringStart { withUnsafeCurrentTask { $0?.cancel() } }
        if failStart { throw AudioTestFailure.synthetic }
        return format
    }

    /// Records native scheduling and retains its accounting callback unless failure is injected.
    /// - Parameters:
    ///   - buffer: Owner-validated PCM payload; the fake intentionally retains no payload.
    ///   - completion: Manually invoked by tests to prove exact, repeated and stale release behavior.
    /// - Throws: Synthetic error before retaining a completion when failPlayback is enabled.
    func enqueuePlayback(_ buffer: PCMBuffer, completion: @escaping @Sendable () -> Void) throws {
        if failPlayback { throw AudioTestFailure.synthetic }
        playbackCount += 1
        completions.append(completion)
    }

    /// Records cleanup without invoking saved stale callbacks, so tests control their arrival order.
    func stop() { stopCount += 1 }
}

/// Synthetic backend failure has no associated native error text or device identifiers.
private enum AudioTestFailure: Error { case synthetic }

/// Manual MainActor delivery queue proving native observer return precedes teardown.
@MainActor private final class AudioTestDelivery {
    nonisolated private let actions = OSAllocatedUnfairLock(initialState: [@MainActor @Sendable () -> Void]())
    var reasons: [AppleAudioStopReason] = []

    /// Creates empty deterministic storage without queuing any main-dispatch work.
    init() {}

    /// Runs one queued native-event delivery after the test has returned from its simulated observer.
    /// An empty queue is a no-op, allowing safe repeated delivery in lifecycle boundary tests.
    func runNext() {
        let action = actions.withLock { queue -> (@MainActor @Sendable () -> Void)? in
            guard !queue.isEmpty else { return nil }
            return queue.removeFirst()
        }
        action?()
    }

    /// Retains one callback from a native thread without executing it on that observer stack.
    /// - Parameter action: Future MainActor delivery, bounded by the bridge scheduling slot.
    nonisolated func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
        actions.withLock { $0.append(action) }
    }

    /// Reports the number of deferred deliveries for burst and restart capacity assertions.
    /// - Returns: Pending callback count, expected to remain zero or one.
    nonisolated func pendingCount() -> Int { actions.withLock { $0.count } }
}
#endif
