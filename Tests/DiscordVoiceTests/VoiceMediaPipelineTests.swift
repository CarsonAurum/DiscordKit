// File: Tests/DiscordVoiceTests/VoiceMediaPipelineTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordMedia
import DiscordTestSupport
import DiscordTransport
import DiscordVoiceCodecs
import DiscordVoiceCrypto
import Foundation
import Testing
@testable import DiscordVoice

/// Synthetic full-duplex media tests use manual clocks, bounded peers and explicit fake E2EE.
@Suite struct VoiceMediaPipelineTests {
    /// Verifies encode/E2EE/RTP/AEAD ordering, sequence rollover, decoded recording and two sinks.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func authenticatedRoundTripAndLoss() async throws {
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let transform = PipelineTransform()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform,
                                        initialSequence: .max, initialTimestamp: .max - 100)
        let playback = try PCMFrameQueue()
        let recording = try PCMFrameQueue()
        try await pipeline.registerReceiveStream(ssrc: 7, playback: playback, recording: recording)
        await pipeline.setAuthorized(true)
        #expect(try await pipeline.playout(ssrc: 7) == nil)
        #expect(try await pipeline.send(pcm(), context: TransportContext(clock: clock)))
        let first = try #require(await transport.packets.first)
        #expect(first.bytes.count > 32)
        #expect(first.bytes[2] == 0xFF && first.bytes[3] == 0xFF)
        try await pipeline.receive(first)
        let played = try #require(try await pipeline.playout(ssrc: 7))
        #expect(played.sequence == .max)
        #expect(!played.concealed)
        #expect(played.pcm.frameCount == 960)
        #expect(played.pcm.format.sampleRate == 48_000)
        let sealed = await transform.sealed.first
        #expect(played.encodedOpus == sealed)
        #expect(try await playback.read() == played.pcm)
        #expect(try await recording.read() == played.pcm)
        let loss = try #require(try await pipeline.playout(ssrc: 7))
        #expect(loss.sequence == 0 && loss.concealed)
        #expect(loss.encodedOpus == nil && loss.pcm.frameCount == 960)
        let snapshot = await pipeline.snapshot()
        #expect(snapshot.sentPackets == 1 && snapshot.receivedPackets == 1)
        #expect(snapshot.concealedPackets == 1 && snapshot.bufferedBytes == 0)
        #expect(await transform.opened.count == 1)
    }

    /// Stream count, duplicate registration, format and byte budgets are independent hard limits.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func configurationAndRegistrationBounds() async throws {
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let transform = PipelineTransform()
        for count in [0, 4_097, Int.max] {
            #expect(throws: VoiceMediaPipelineError.invalidConfiguration) {
                try makePipeline(clock: clock, transport: transport, transformer: transform,
                                 maximumReceiveStreams: count)
            }
        }
        for bytes in [0, 67_108_865, Int.max] {
            #expect(throws: VoiceMediaPipelineError.invalidConfiguration) {
                try makePipeline(clock: clock, transport: transport, transformer: transform,
                                 maximumBufferedBytes: bytes)
            }
        }
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform,
                                        maximumReceiveStreams: 1)
        for count in [0, 121, 5_761, Int.max] {
            await #expect(throws: VoiceMediaPipelineError.invalidConfiguration) {
                try await pipeline.registerReceiveStream(ssrc: 7, packetSampleCount: count)
            }
        }
        await #expect(throws: CELTSynthesisError.invalidChannelCount) {
            try await pipeline.registerReceiveStream(ssrc: 7, channelCount: 3)
        }
        await #expect(throws: VoicePacketError.invalidConfiguration) {
            try await pipeline.registerReceiveStream(ssrc: 7, capacity: 0)
        }
        await #expect(throws: VoicePacketError.invalidConfiguration) {
            try await pipeline.registerReceiveStream(ssrc: 7, maximumBytes: 0)
        }
        try await pipeline.registerReceiveStream(ssrc: 7, nextSequence: 0)
        await #expect(throws: VoiceMediaPipelineError.streamExists) {
            try await pipeline.registerReceiveStream(ssrc: 7)
        }
        await #expect(throws: VoiceMediaPipelineError.capacityExceeded) {
            try await pipeline.registerReceiveStream(ssrc: 8)
        }
        await pipeline.removeReceiveStream(ssrc: 7)
        await pipeline.removeReceiveStream(ssrc: 7)
        try await pipeline.registerReceiveStream(ssrc: 8)
        #expect(await pipeline.snapshot().receiveStreamCount == 1)
    }

    /// Unauthorized, expired, invalid-format and cancelled sends consume no UDP operation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func admissionCancellationAndClose() async throws {
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: PipelineTransform())
        await #expect(throws: VoiceMediaPipelineError.unauthorized) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        await pipeline.setAuthorized(true)
        let wrong = try PCMBuffer(format: PCMFormat(sampleRate: 24_000, channelCount: 1),
                                  samples: Array(repeating: 0, count: 480))
        await #expect(throws: VoiceMediaPipelineError.invalidPCM) {
            try await pipeline.send(wrong, context: TransportContext(clock: clock))
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock, deadline: clock.now))
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await transport.packets.isEmpty)
        await pipeline.close()
        await pipeline.close()
        await pipeline.setAuthorized(true)
        let snapshot = await pipeline.snapshot()
        #expect(snapshot.closed && !snapshot.authorized && snapshot.receiveStreamCount == 0)
        await #expect(throws: VoiceMediaPipelineError.closed) {
            try await pipeline.registerReceiveStream(ssrc: 9)
        }
        await #expect(throws: VoiceMediaPipelineError.closed) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        #expect(await !transport.closed)
    }

    /// A suspended E2EE call cannot cross revocation, reauthorization, or overlap another send.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func suspendedSendRevocationAndConcurrency() async throws {
        let started = TestBarrier()
        let release = TestBarrier()
        let transform = PipelineTransform(started: started, release: release)
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform)
        await pipeline.setAuthorized(true)
        let first = Task { try await pipeline.send(pcm(), context: TransportContext(clock: clock)) }
        try await started.wait()
        await #expect(throws: VoiceMediaPipelineError.concurrentSend) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        await pipeline.setAuthorized(false)
        await pipeline.setAuthorized(true)
        release.open()
        await #expect(throws: VoiceMediaPipelineError.staleOperation) { try await first.value }
        #expect(await transport.packets.isEmpty)
        try clock.advance(by: .milliseconds(20))
        #expect(try await pipeline.send(pcm(), context: TransportContext(clock: clock)))
        let sent = try #require(await transport.packets.first)
        #expect(sent.bytes[3] == 1)
    }

    /// Pacing cancellation removes its sole sleeper, frees admission and sends no second packet.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pacingCancellation() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let transport = PipelineDatagrams()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        _ = try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        let second = Task { try await pipeline.send(pcm(), context: TransportContext(clock: clock)) }
        try await scheduled.wait()
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(clock.pendingSleepCount == 0)
        #expect(await transport.packets.count == 1)
        try clock.advance(by: .milliseconds(20))
        _ = try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        #expect(await transport.packets.count == 2)
    }

    /// Idle construction and a later interruption cannot accumulate immediately sendable slots.
    /// Both PCM and encoded entry points reserve one fresh interval while retaining RTP/nonce order.
    /// - Parameter encoded: True exercises complete encoded Opus; false exercises PCM encoding.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func idlePacingReanchorsWithoutCatchUp(encoded: Bool) async throws {
        let events = AsyncStream<PipelinePacingEvent>.makeStream(bufferingPolicy: .bufferingOldest(16))
        defer { events.continuation.finish() }
        let clock = ManualClock(onSleepScheduled: { events.continuation.yield(.sleep) })
        let transport = PipelineDatagrams(onSend: { events.continuation.yield(.sent) })
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: PipelineTransform())
        var observed = events.stream.makeAsyncIterator()
        await pipeline.setAuthorized(true)
        try clock.advance(by: .seconds(10))
        try await sendFrame(pipeline, encoded: encoded, clock: clock)
        #expect(await observed.next() == .sent)
        let second = Task { try await sendFrame(pipeline, encoded: encoded, clock: clock) }
        defer { second.cancel() }
        try #require(await observed.next() == .sleep)
        #expect(await transport.packets.count == 1)
        try clock.advance(by: .milliseconds(20))
        try #require(clock.pendingSleepCount == 0)
        try await second.value
        #expect(await observed.next() == .sent)
        try clock.advance(by: .seconds(60))
        try await sendFrame(pipeline, encoded: encoded, clock: clock)
        #expect(await observed.next() == .sent)
        let fourth = Task { try await sendFrame(pipeline, encoded: encoded, clock: clock) }
        defer { fourth.cancel() }
        try #require(await observed.next() == .sleep)
        #expect(await transport.packets.count == 3)
        try clock.advance(by: .milliseconds(19))
        #expect(clock.pendingSleepCount == 1)
        #expect(await transport.packets.count == 3)
        try clock.advance(by: .milliseconds(1))
        try #require(clock.pendingSleepCount == 0)
        try await fourth.value
        #expect(await observed.next() == .sent)
        let packets = await transport.packets
        #expect(packets.map { $0.bytes[3] } == [0, 1, 2, 3])
        #expect(packets.map { Array($0.bytes.suffix(4)) } == [[0, 0, 0, 0], [0, 0, 0, 1],
                                                           [0, 0, 0, 2], [0, 0, 0, 3]])
        #expect(Array(packets[3].bytes[4..<8]) == [0, 0, 11, 64])
    }

    /// Sub-frame lateness preserves cadence, but a delayed wake reserves a full fresh interval.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pacingRetainsSmallLatenessAndReanchorsDelayedWake() async throws {
        let events = AsyncStream<PipelinePacingEvent>.makeStream(bufferingPolicy: .bufferingOldest(16))
        defer { events.continuation.finish() }
        let clock = ManualClock(onSleepScheduled: { events.continuation.yield(.sleep) })
        let transport = PipelineDatagrams(onSend: { events.continuation.yield(.sent) })
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: PipelineTransform())
        var observed = events.stream.makeAsyncIterator()
        await pipeline.setAuthorized(true)
        try await sendFrame(pipeline, encoded: true, clock: clock)
        #expect(await observed.next() == .sent)
        try clock.advance(by: .milliseconds(25))
        try await sendFrame(pipeline, encoded: true, clock: clock)
        #expect(await observed.next() == .sent)
        let third = Task { try await sendFrame(pipeline, encoded: true, clock: clock) }
        defer { third.cancel() }
        try #require(await observed.next() == .sleep)
        try clock.advance(by: .milliseconds(15))
        try #require(clock.pendingSleepCount == 0)
        try await third.value
        #expect(await observed.next() == .sent)
        let fourth = Task { try await sendFrame(pipeline, encoded: true, clock: clock) }
        defer { fourth.cancel() }
        try #require(await observed.next() == .sleep)
        try clock.advance(by: .seconds(10))
        try await fourth.value
        #expect(await observed.next() == .sent)
        let fifth = Task { try await sendFrame(pipeline, encoded: true, clock: clock) }
        defer { fifth.cancel() }
        try #require(await observed.next() == .sleep)
        #expect(await transport.packets.count == 4)
        try clock.advance(by: .milliseconds(20))
        try #require(clock.pendingSleepCount == 0)
        try await fifth.value
        #expect(await transport.packets.count == 5)
    }

    /// Speaking restarts begin immediately; an old revoked sleeper cannot restore its deadline.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pacingRestartsAndStaleWaitCannotCommit() async throws {
        let events = AsyncStream<PipelinePacingEvent>.makeStream(bufferingPolicy: .bufferingOldest(16))
        defer { events.continuation.finish() }
        let clock = ManualClock(onSleepScheduled: { events.continuation.yield(.sleep) })
        let transport = PipelineDatagrams(onSend: { events.continuation.yield(.sent) })
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: PipelineTransform())
        var observed = events.stream.makeAsyncIterator()
        await pipeline.setAuthorized(true)
        try await sendFrame(pipeline, encoded: true, clock: clock)
        #expect(await observed.next() == .sent)
        await pipeline.setSendingAllowed(false)
        await pipeline.setSendingAllowed(true)
        try await sendFrame(pipeline, encoded: true, clock: clock)
        #expect(await observed.next() == .sent)
        let stale = Task { try await sendFrame(pipeline, encoded: true, clock: clock) }
        defer { stale.cancel() }
        try #require(await observed.next() == .sleep)
        await pipeline.setAuthorized(false)
        await pipeline.setAuthorized(true)
        try clock.advance(by: .milliseconds(20))
        await #expect(throws: VoiceMediaPipelineError.staleOperation) { try await stale.value }
        #expect(await transport.packets.count == 2)
        try await sendFrame(pipeline, encoded: true, clock: clock)
        #expect(await observed.next() == .sent)
        let next = Task { try await sendFrame(pipeline, encoded: true, clock: clock) }
        defer { next.cancel() }
        try #require(await observed.next() == .sleep)
        try clock.advance(by: .milliseconds(20))
        try #require(clock.pendingSleepCount == 0)
        try await next.value
        #expect(await transport.packets.count == 4)
        #expect(await transport.packets.map { $0.bytes[3] } == [0, 1, 2, 3])
    }

    /// Authentication, sender registration and expected-peer checks precede jitter admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func tamperReplayUnknownAndBudget() async throws {
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let transform = PipelineTransform()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform,
                                        maximumBufferedBytes: 20)
        await pipeline.setAuthorized(true)
        let sender = try cipher()
        let packet = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 0, cipher: sender)
        await #expect(throws: VoiceMediaPipelineError.unknownStream) { try await pipeline.receive(packet) }
        try await pipeline.registerReceiveStream(ssrc: 7, maximumBytes: 20)
        let other = Datagram(bytes: packet.bytes, peer: DatagramAddress(host: "wrong", port: 5000))
        await #expect(throws: VoiceMediaPipelineError.unexpectedPeer) { try await pipeline.receive(other) }
        var damaged = packet.bytes
        damaged[damaged.count - 5] ^= 1
        await #expect(throws: VoiceCryptoError.authenticationFailed) {
            try await pipeline.receive(Datagram(bytes: damaged, peer: peer))
        }
        try await pipeline.receive(packet)
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await pipeline.receive(packet) }
        let second = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 1, cipher: sender)
        await #expect(throws: VoiceMediaPipelineError.capacityExceeded) { try await pipeline.receive(second) }
        #expect(await pipeline.snapshot().bufferedBytes == 15)
        await pipeline.setAuthorized(false)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
        await pipeline.setAuthorized(true)
        // Outer replay state survives the jitter reset.
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await pipeline.receive(second) }
        let third = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 5_000, cipher: sender)
        try await pipeline.receive(third)
        #expect(await pipeline.snapshot().receivedPackets == 2)
        await pipeline.removeReceiveStream(ssrc: 7)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
        await #expect(throws: VoiceMediaPipelineError.unknownStream) { try await pipeline.playout(ssrc: 7) }
    }

    /// DTX advances timestamps without RTP sequence gaps and termination uses five E2EE frames.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func dtxAndTerminationSilence() async throws {
        let events = AsyncStream<PipelinePacingEvent>.makeStream(bufferingPolicy: .bufferingOldest(16))
        defer { events.continuation.finish() }
        let clock = ManualClock(onSleepScheduled: { events.continuation.yield(.sleep) })
        let transport = PipelineDatagrams(onSend: { events.continuation.yield(.sent) })
        var observed = events.stream.makeAsyncIterator()
        let transform = PipelineTransform()
        let encoder = try OpusAudioEncoder(dtx: OpusDTXPolicy(hangoverMilliseconds: 0))
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform,
                                        encoder: encoder)
        await pipeline.setAuthorized(true)
        #expect(try await pipeline.send(pcm(), context: TransportContext(clock: clock)))
        #expect(await observed.next() == .sent)
        try clock.advance(by: .milliseconds(20))
        #expect(try await !pipeline.send(pcm(), context: TransportContext(clock: clock)))
        try clock.advance(by: .seconds(1))
        let termination = Task { try await pipeline.sendTerminationSilence(context: TransportContext(clock: clock)) }
        defer { termination.cancel() }
        for index in 0..<5 {
            try #require(await observed.next() == .sent)
            if index < 4 {
                try #require(await observed.next() == .sleep)
                #expect(await transport.packets.count == index + 2)
                try clock.advance(by: .milliseconds(20))
                try #require(clock.pendingSleepCount == 0)
            }
        }
        try await termination.value
        let packets = await transport.packets
        #expect(packets.count == 6)
        #expect(await transform.sealed.suffix(5).allSatisfy { $0 == Data([0xF8, 0xFF, 0xFE]) })
        #expect(packets[1].bytes[3] == 1)
        #expect(Array(packets[1].bytes[4..<8]) == [0, 0, 7, 128])
    }

    /// An E2EE failure never emits plaintext; an ambiguous UDP failure is never retried.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func transformAndTransportFailures() async throws {
        let clock = ManualClock()
        let transform = PipelineTransform()
        let transport = PipelineDatagrams()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform)
        await pipeline.setAuthorized(true)
        await transform.setFailing(true)
        await #expect(throws: PipelineFixtureError.transform) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        #expect(await transport.packets.isEmpty)
        await transform.setFailing(false)
        await transport.setFailing(true)
        try clock.advance(by: .milliseconds(20))
        await #expect(throws: PipelineFixtureError.transport) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        #expect(await transport.attempts == 1)
        #expect(await pipeline.snapshot().sentPackets == 0)
    }

    /// Encoded input retains parsed durations, rejects malformed audio and honors speaking gates.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func encodedSourceAndSpeakingAdmission() async throws {
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let transform = PipelineTransform()
        let pipeline = try makePipeline(clock: clock, transport: transport, transformer: transform)
        await pipeline.setAuthorized(true)
        await pipeline.setSendingAllowed(false)
        await #expect(throws: VoiceMediaPipelineError.unauthorized) {
            try await pipeline.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: TransportContext(clock: clock))
        }
        await #expect(throws: VoiceMediaPipelineError.unauthorized) {
            try await pipeline.send(pcm(), context: TransportContext(clock: clock))
        }
        await #expect(throws: VoiceMediaPipelineError.unauthorized) {
            try await pipeline.sendTerminationSilence(context: TransportContext(clock: clock))
        }
        // Speaking admission is outbound-only; cold registered receive playout remains available.
        try await pipeline.registerReceiveStream(ssrc: 8, nextSequence: 10)
        #expect(try await pipeline.playout(ssrc: 8)?.concealed == true)
        await pipeline.setSendingAllowed(true)
        for invalid in [Data(), Data([0x83, 0]), Data([0x83, 49]), Data(repeating: 0, count: 65_537)] {
            await #expect(throws: (any Error).self) {
                try await pipeline.sendOpus(invalid, context: TransportContext(clock: clock))
            }
        }
        try await pipeline.sendOpus(Data([0x80]), context: TransportContext(clock: clock))
        try clock.advance(by: .milliseconds(3))
        try await pipeline.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: TransportContext(clock: clock))
        let packets = await transport.packets
        #expect(packets.count == 2 && packets[0].bytes[3] == 0 && packets[1].bytes[3] == 1)
        #expect(Array(packets[1].bytes[4..<8]) == [0, 0, 0, 120])
        #expect(await transform.sealed == [Data([0x80]), Data([0xF8, 0xFF, 0xFE])])
        await pipeline.close()
        await pipeline.setSendingAllowed(true)
        #expect(await !pipeline.snapshot().sendingAllowed)
    }

    /// Independent outbound revocation invalidates a suspended frame while preserving receive gates.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func speakingRevocationDuringEncodedSend() async throws {
        let started = TestBarrier()
        let release = TestBarrier()
        let clock = ManualClock()
        let transport = PipelineDatagrams()
        let pipeline = try makePipeline(clock: clock, transport: transport,
                                        transformer: PipelineTransform(started: started, release: release))
        await pipeline.setAuthorized(true)
        let sending = Task {
            try await pipeline.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: TransportContext(clock: clock))
        }
        try await started.wait()
        await #expect(throws: VoiceMediaPipelineError.concurrentSend) {
            try await pipeline.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: TransportContext(clock: clock))
        }
        await pipeline.setSendingAllowed(false)
        await pipeline.setSendingAllowed(true)
        release.open()
        await #expect(throws: VoiceMediaPipelineError.staleOperation) { try await sending.value }
        #expect(await transport.packets.isEmpty)
        #expect(await pipeline.snapshot().authorized)
    }

    /// Reordered authenticated streams retain separate decoder, sequence and bounded byte state.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func independentReceiveStreamsAndReorder() async throws {
        let clock = ManualClock()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7, nextSequence: .max)
        try await pipeline.registerReceiveStream(ssrc: 8, nextSequence: 42, channelCount: 2)
        let sender = try cipher()
        let silence = Data([0xF8, 0xFF, 0xFE])
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 0, timestamp: 960, cipher: sender))
        try await pipeline.receive(wire(opus: silence, ssrc: 8, sequence: 42, cipher: sender))
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: .max, timestamp: 0, cipher: sender))
        let last = try #require(try await pipeline.playout(ssrc: 7))
        let other = try #require(try await pipeline.playout(ssrc: 8))
        let zero = try #require(try await pipeline.playout(ssrc: 7))
        #expect(last.sequence == .max && zero.sequence == 0 && other.sequence == 42)
        #expect(other.pcm.format.channelCount == 2 && other.pcm.samples.count == 1_920)
        #expect(!last.concealed && !zero.concealed && !other.concealed)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
    }

    /// Removing/replacing a registration during E2EE cannot restore stale receive history.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func suspendedReceiveCannotRecreateStream() async throws {
        let started = TestBarrier()
        let release = TestBarrier()
        let clock = ManualClock()
        let transform = PipelineTransform(started: started, release: release, gatesOpening: true)
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: transform)
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7)
        let packet = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 0, cipher: cipher())
        let receiving = Task { try await pipeline.receive(packet) }
        try await started.wait()
        await #expect(throws: VoiceMediaPipelineError.concurrentReceive) { try await pipeline.receive(packet) }
        await pipeline.removeReceiveStream(ssrc: 7)
        try await pipeline.registerReceiveStream(ssrc: 7)
        release.open()
        await #expect(throws: VoiceMediaPipelineError.staleOperation) { try await receiving.value }
        #expect(await pipeline.snapshot().receiveStreamCount == 1)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
    }

    /// Sink backpressure allows receive work and fails overlapping playout without queuing tasks.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func boundedSinkConcurrencyAndRemoval() async throws {
        let started = TestBarrier()
        let release = TestBarrier()
        let playback = PipelineSink(started: started, release: release)
        let recording = try PCMFrameQueue()
        let clock = ManualClock()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7, nextSequence: 0, playback: playback, recording: recording)
        let first = Task { try await pipeline.playout(ssrc: 7) }
        try await started.wait()
        await #expect(throws: VoiceMediaPipelineError.concurrentPlayout) { try await pipeline.playout(ssrc: 7) }
        let packet = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 1, cipher: cipher())
        try await pipeline.receive(packet)
        #expect(await pipeline.snapshot().bufferedBytes == 15)
        await pipeline.removeReceiveStream(ssrc: 7)
        release.open()
        await #expect(throws: VoiceMediaPipelineError.staleOperation) { try await first.value }
        #expect(try await recording.read() == nil)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
    }

    /// Idle PLC retains RTP sequence across DTX, accepts later losses and respects timestamp wrap.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func receiveDTXAndTimestampWrap() async throws {
        let clock = ManualClock()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7)
        let sender = try cipher()
        let silence = Data([0xF8, 0xFF, 0xFE])
        let origin = UInt32.max - 959
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: .max,
                                        timestamp: origin, cipher: sender))
        #expect(try await pipeline.playout(ssrc: 7)?.sequence == .max)
        for _ in 0..<3 {
            let idle = try #require(try await pipeline.playout(ssrc: 7))
            #expect(idle.concealed && idle.sequence == 0)
        }
        // Three suppressed intervals consumed media time but no RTP sequence.
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 0,
                                        timestamp: 2_880, cipher: sender))
        let refresh = try #require(try await pipeline.playout(ssrc: 7))
        #expect(!refresh.concealed && refresh.sequence == 0)
        _ = try await pipeline.playout(ssrc: 7)
        // A transmitted packet was lost; the returning sequence can advance after idle PLC.
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 2,
                                        timestamp: 4_800, cipher: sender))
        let afterLoss = try #require(try await pipeline.playout(ssrc: 7))
        #expect(!afterLoss.concealed && afterLoss.sequence == 2)
        // Authenticated packets whose media interval already played remain late.
        let late = try await wire(opus: silence, ssrc: 7, sequence: 1, timestamp: 3_840, cipher: sender)
        await #expect(throws: VoicePacketError.duplicateOrLate) { try await pipeline.receive(late) }
    }

    /// A future DTX refresh waits in jitter while bounded PLC fills its timestamp gap.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func futureTimestampDoesNotPlayEarly() async throws {
        let clock = ManualClock()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7)
        let sender = try cipher()
        let silence = Data([0xF8, 0xFF, 0xFE])
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 0, timestamp: 0, cipher: sender))
        _ = try await pipeline.playout(ssrc: 7)
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 1, timestamp: 2_040, cipher: sender))
        let fullGap = try #require(try await pipeline.playout(ssrc: 7))
        let shortGap = try #require(try await pipeline.playout(ssrc: 7))
        let refresh = try #require(try await pipeline.playout(ssrc: 7))
        #expect(fullGap.concealed && fullGap.pcm.frameCount == 960)
        #expect(shortGap.concealed && shortGap.pcm.frameCount == 120)
        #expect(!refresh.concealed && refresh.sequence == 1)
        #expect(await pipeline.snapshot().bufferedBytes == 0)
    }

    /// Authenticated wrong types, invalid timestamps and inner failures never enter decoder queues.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedAndInnerAuthenticationAdmission() async throws {
        let clock = ManualClock()
        let transform = PipelineTransform()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: transform)
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7)
        let sender = try cipher()
        let silence = Data([0xF8, 0xFF, 0xFE])
        let wrongType = try await wire(opus: silence, ssrc: 7, sequence: 0, payloadType: 119, cipher: sender)
        await #expect(throws: VoiceMediaPipelineError.unexpectedPayloadType) { try await pipeline.receive(wrongType) }
        await transform.setFailing(true)
        let rejected = try await wire(opus: silence, ssrc: 7, sequence: 0, cipher: sender)
        await #expect(throws: PipelineFixtureError.transform) { try await pipeline.receive(rejected) }
        await transform.setFailing(false)
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await pipeline.receive(rejected) }
        try await pipeline.receive(wire(opus: silence, ssrc: 7, sequence: 0, cipher: sender))
        _ = try await pipeline.playout(ssrc: 7)
        let badTimestamp = try await wire(opus: silence, ssrc: 7, sequence: 1, timestamp: 961, cipher: sender)
        await #expect(throws: VoicePacketError.malformedPacket) { try await pipeline.receive(badTimestamp) }
        #expect(await pipeline.snapshot().bufferedBytes == 0)
        #expect(await pipeline.snapshot().receivedPackets == 1)
    }

    /// Sink failure consumes a decoded packet once and releases its queue accounting before throwing.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func failedSinkConsumesSlot() async throws {
        let clock = ManualClock()
        let playback = try PCMFrameQueue()
        await playback.finish()
        let pipeline = try makePipeline(clock: clock, transport: PipelineDatagrams(), transformer: PipelineTransform())
        await pipeline.setAuthorized(true)
        try await pipeline.registerReceiveStream(ssrc: 7, playback: playback)
        let packet = try await wire(opus: Data([0xF8, 0xFF, 0xFE]), ssrc: 7, sequence: 0, cipher: cipher())
        try await pipeline.receive(packet)
        await #expect(throws: MediaError.closed) { try await pipeline.playout(ssrc: 7) }
        #expect(await pipeline.snapshot().bufferedBytes == 0)
        // Retrying playout produces a new PLC interval rather than repeating packet delivery.
        await #expect(throws: MediaError.closed) { try await pipeline.playout(ssrc: 7) }
        #expect(await pipeline.snapshot().concealedPackets == 1)
    }

    /// Produces a fresh synthetic exact-session cipher with no network or native state.
    /// - Returns: AES256-GCM rtpsize nonce authority with the test's fixed 32-byte key.
    /// - Throws: Cipher configuration errors if the fixture's constants are invalid.
    private func cipher() throws -> VoiceTransportCipher {
        try VoiceTransportCipher(mode: .aeadAES256GCMRTPSize, key: Data(repeating: 7, count: 32))
    }

    /// Builds a pipeline whose injected peers expose every network and E2EE side effect.
    /// - Parameters:
    ///   - clock: Manually advanced pacing clock.
    ///   - transport: Recording, fail-fast synthetic datagram peer.
    ///   - transformer: Explicit fake whole-frame authenticated boundary.
    ///   - maximumReceiveStreams: Stream bound under test; default 64.
    ///   - maximumBufferedBytes: Aggregate bound under test; default four MiB.
    ///   - initialSequence: Outbound rollover position under test; default zero.
    ///   - initialTimestamp: Outbound timestamp position under test; default zero.
    ///   - encoder: Optional preconfigured DTX encoder; nil selects ordinary mono CELT.
    /// - Returns: Initially unauthorized local stream with SSRC seven.
    /// - Throws: Codec, cipher or pipeline configuration errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func makePipeline(clock: ManualClock, transport: PipelineDatagrams,
                              transformer: PipelineTransform, maximumReceiveStreams: Int = 64,
                              maximumBufferedBytes: Int = 4_194_304, initialSequence: UInt16 = 0,
                              initialTimestamp: UInt32 = 0, encoder: OpusAudioEncoder? = nil) throws -> VoiceMediaPipeline<ManualClock> {
        try VoiceMediaPipeline(clock: clock, transport: transport, peer: peer, cipher: cipher(),
                               transformer: transformer, ssrc: 7, encoder: encoder ?? OpusAudioEncoder(),
                               maximumReceiveStreams: maximumReceiveStreams,
                               maximumBufferedBytes: maximumBufferedBytes, initialSequence: initialSequence,
                               initialTimestamp: initialTimestamp)
    }

    /// Creates one exact twenty-millisecond normalized mono 48kHz silence block.
    /// - Returns: 960 zero sample frames, with no device or timestamp dependency.
    /// - Throws: PCM format/buffer errors if the fixture's constants are invalid.
    private func pcm() throws -> PCMBuffer {
        try PCMBuffer(format: PCMFormat(sampleRate: 48_000, channelCount: 1),
                      samples: Array(repeating: 0, count: 960))
    }

    /// Sends one twenty-millisecond test slot through the selected production source path.
    /// - Parameters:
    ///   - pipeline: Authorized finite media owner whose transport records send observations.
    ///   - encoded: True supplies complete Opus silence; false encodes normalized PCM silence.
    ///   - clock: Same manual timing source injected into the pipeline.
    /// - Throws: Production pacing/admission/codec/transport errors; PCM must transmit once.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func sendFrame(_ pipeline: VoiceMediaPipeline<ManualClock>, encoded: Bool,
                           clock: ManualClock) async throws {
        if encoded {
            try await pipeline.sendOpus(Data([0xF8, 0xFF, 0xFE]), context: TransportContext(clock: clock))
        } else {
            #expect(try await pipeline.send(pcm(), context: TransportContext(clock: clock)))
        }
    }

    /// Wraps a synthetic E2EE packet using real transport AEAD with a fresh nonce reservation.
    /// - Parameters:
    ///   - opus: Complete packet, used for valid silence or malformed-codec fixtures.
    ///   - ssrc: Trusted/untrusted stream registration under test.
    ///   - sequence: RTP sequence under test; timestamp uses its fixed twenty-millisecond slot.
    ///   - timestamp: Explicit RTP timing fixture, or nil to use sequence times 960.
    ///   - payloadType: Negotiated type or malformed-type fixture; default Opus 120.
    ///   - cipher: Shared sending authority; repeated calls never reset its nonce.
    /// - Returns: One complete encrypted packet from the expected peer.
    /// - Throws: RTP validation or real AEAD errors.
    private func wire(opus: Data, ssrc: UInt32, sequence: UInt16, timestamp: UInt32? = nil, payloadType: UInt8 = 120,
                      cipher: VoiceTransportCipher) async throws -> Datagram {
        let packet = try RTPPacket(payloadType: payloadType, sequence: sequence, timestamp: timestamp ?? UInt32(sequence) * 960,
                                   ssrc: ssrc, payload: Data([0xD1]) + opus)
        let bytes = packet.serialized()
        let header = Data(bytes.prefix(12))
        let sealed = try await cipher.seal(payload: Data(bytes.dropFirst(12)), authenticatedHeader: header)
        return Datagram(bytes: header + sealed, peer: peer)
    }

    /// Exact synthetic peer shared by recorded outbound packets and injected inbound packets.
    private var peer: DatagramAddress { DatagramAddress(host: "127.0.0.1", port: 5000) }
}

private enum PipelineFixtureError: Error { case transform, transport }

/// Observes actual sleep/send entry so regressions fail without depending on task start order.
private enum PipelinePacingEvent: Sendable, Equatable { case sleep, sent }

/// Explicit test-only framing; production never installs an automatic plaintext transform.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor PipelineTransform: VoiceFrameTransformer {
    var sealed: [Data] = []
    var opened: [Data] = []
    private var failing = false
    private let started: TestBarrier?
    private let release: TestBarrier?
    private let gatesOpening: Bool

    /// Stores optional deterministic suspension gates without spawning tasks.
    /// - Parameters:
    ///   - started: Opened after a seal begins; nil omits this notification.
    ///   - release: Seal waits here when supplied; nil makes sealing immediate.
    ///   - gatesOpening: True applies gates to open instead of seal; default false.
    init(started: TestBarrier? = nil, release: TestBarrier? = nil, gatesOpening: Bool = false) {
        self.started = started
        self.release = release
        self.gatesOpening = gatesOpening
    }

    /// Toggles a fixture failure at the exact E2EE boundary.
    /// - Parameter value: True makes subsequent seal/open calls fail before transformation.
    func setFailing(_ value: Bool) { failing = value }

    /// Records complete codec packets and adds an unmistakable test-only marker.
    /// - Parameters:
    ///   - opus: Complete codec packet; retained only in this finite test fixture.
    ///   - ssrc: Ignored test stream; production adapters validate participant identity.
    /// - Returns: Marker byte followed by unchanged codec bytes.
    /// - Throws: Scripted failure or gate cancellation.
    func seal(_ opus: Data, ssrc: UInt32) async throws -> Data {
        guard !failing else { throw PipelineFixtureError.transform }
        if !gatesOpening {
            started?.open()
            if let release { try await release.wait() }
        }
        sealed.append(opus)
        return Data([0xD1]) + opus
    }

    /// Verifies the test-only marker and records successful whole-frame opens.
    /// - Parameters:
    ///   - frame: Marker-prefixed complete packet.
    ///   - ssrc: Ignored fixture stream identity.
    /// - Returns: Complete ordinary Opus packet with the marker removed.
    /// - Throws: Scripted failure or a missing marker; plaintext never passes implicitly.
    func open(_ frame: Data, ssrc: UInt32) async throws -> Data {
        guard !failing, frame.first == 0xD1 else { throw PipelineFixtureError.transform }
        if gatesOpening {
            started?.open()
            if let release { try await release.wait() }
        }
        opened.append(frame)
        return Data(frame.dropFirst())
    }
}

/// A bounded one-call PCM fixture used to expose playout suspension and removal races.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor PipelineSink: PCMSink {
    private let started: TestBarrier
    private let release: TestBarrier

    /// Stores caller-controlled admission and release gates without starting work.
    /// - Parameters:
    ///   - started: Opened after write enters the sink.
    ///   - release: Awaited before completing the write.
    init(started: TestBarrier, release: TestBarrier) {
        self.started = started
        self.release = release
    }

    /// Holds one caller's PCM transfer until deterministic release.
    /// - Parameter buffer: Ignored immutable PCM; the pipeline owns the bounded value.
    /// - Throws: Cancellation while waiting for release.
    func write(_ buffer: PCMBuffer) async throws {
        started.open()
        try await release.wait()
    }
}

/// A single-test synthetic UDP peer which records exactly once and never opens a socket.
private actor PipelineDatagrams: DatagramTransport {
    var packets: [Datagram] = []
    var closed = false
    var attempts = 0
    private var failing = false
    private let onSend: @Sendable () -> Void

    /// Creates an inert recording peer with an optional synchronous send-observation hook.
    /// - Parameter onSend: Invoked after a successful recorded send; must not block. The
    ///   default performs no work. Tests use a finite stream to observe pacing order.
    init(onSend: @escaping @Sendable () -> Void = {}) { self.onSend = onSend }

    /// Toggles a deterministic send failure with an observable attempt count.
    /// - Parameter value: True makes sends throw after counting one attempt.
    func setFailing(_ value: Bool) { failing = value }

    /// Records a complete send once after checking cancellation and the inclusive deadline.
    /// - Parameters:
    ///   - datagram: Complete encrypted packet to record.
    ///   - context: Caller-owned clock and cancellation/deadline policy.
    /// - Throws: Expiration, cancellation, closed state or a scripted ambiguous send failure.
    func sendDatagram<C: Clock>(_ datagram: Datagram, context: TransportContext<C>) throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        attempts += 1
        guard !failing else { throw PipelineFixtureError.transport }
        packets.append(datagram)
        onSend()
    }

    /// Returns immediate EOF; inbound pipeline tests inject owned datagrams explicitly.
    /// - Parameter context: Checked deadline/cancellation policy.
    /// - Returns: Nil without storing waiters or creating read tasks.
    /// - Throws: Expiration or cancellation.
    func receiveDatagram<C: Clock>(context: TransportContext<C>) throws -> Datagram? where C.Duration == Duration {
        try context.check()
        return nil
    }

    /// Marks this fixture closed; pipeline close deliberately leaves caller-owned peers open.
    func close() { closed = true }
}
