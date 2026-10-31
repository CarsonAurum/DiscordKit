// File: Sources/DiscordVoice/VoiceMediaPipeline.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordMedia
import DiscordTransport
import DiscordVoiceCodecs
import DiscordVoiceCrypto
import Foundation

/// An authenticated, complete-frame E2EE boundary injected by the application.
///
/// Implementations resolve SSRCs through trusted participant bindings and enforce their
/// negotiated epoch/readiness policy. A missing key, unauthorized sender or unsupported
/// version must throw; implementations must never silently return plaintext as fallback.
/// DiscordVoice deliberately does not import or own a DAVE implementation.
public protocol VoiceFrameTransformer: Sendable {
    /// Protects one complete encoded Opus packet before RTP packetization.
    /// - Parameters:
    ///   - opus: Complete ordinary Opus packet, including TOC and packed frames.
    ///   - ssrc: Negotiated local stream, mapped to the trusted local sender identity.
    /// - Returns: Complete authenticated E2EE frame, including its required footer.
    /// - Throws: Cancellation, unavailable/expired epoch, authorization, nonce-exhaustion
    ///   or implementation-specific cryptographic errors. Reserved nonces cannot be reused.
    func seal(_ opus: Data, ssrc: UInt32) async throws -> Data

    /// Authenticates one complete depacketized frame before any codec processing.
    /// - Parameters:
    ///   - frame: Complete E2EE payload after outer transport authentication.
    ///   - ssrc: Stream mapped through an authenticated participant association.
    /// - Returns: Complete authenticated ordinary Opus packet, including its TOC.
    /// - Throws: Cancellation, unknown sender, unavailable epoch, malformed frame,
    ///   replay, verification-budget or authentication failures; no partial plaintext escapes.
    func open(_ frame: Data, ssrc: UInt32) async throws -> Data
}

/// Admission failures of supervised media; diagnostics contain no media or participant data.
public enum VoiceMediaPipelineError: Error, Sendable, Equatable {
    case invalidConfiguration, unauthorized, closed, unknownStream, streamExists
    case concurrentSend, concurrentReceive, concurrentPlayout, unexpectedPeer
    case invalidPCM, unexpectedPayloadType, capacityExceeded, staleOperation
    /// An injected encoder returned inconsistent framing, geometry, DTX flags or byte bounds.
    case invalidEncoderOutput
}

/// One caller-paced, authenticated receive slot, with explicit packet-loss synthesis.
public struct VoicePCMPlayout: Sendable, Equatable {
    public let ssrc: UInt32
    /// Expected transmitted RTP sequence; idle DTX concealment may repeat this value.
    public let sequence: UInt16
    public let concealed: Bool
    /// Authenticated encoded recording input; nil for an explicitly missing packet.
    public let encodedOpus: Data?
    /// Normalized 48kHz PCM; unclipped decoder output is saturated at the sink boundary.
    public let pcm: PCMBuffer
}

/// Bounded aggregate counters; these contain no SSRCs, media, keys or addresses.
public struct VoiceMediaPipelineSnapshot: Sendable, Equatable {
    public let authorized: Bool
    public let sendingAllowed: Bool
    public let closed: Bool
    public let receiveStreamCount: Int
    public let bufferedBytes: Int
    public let sentPackets: UInt64
    public let receivedPackets: UInt64
    public let concealedPackets: UInt64
    /// Successfully encoded PCM frames, including frames suppressed by the configured DTX policy.
    public let encodedFrameCount: UInt64
    /// Longest synchronous Opus encoding call in monotonic elapsed milliseconds, excluding pacing and I/O.
    public let maximumEncodingDurationMilliseconds: Double
    /// Encoded frames whose synchronous encoding took longer than that frame's audio duration.
    public let encodingDeadlineMissCount: UInt64
    /// Longest interval between successful UDP dispatch starts within an uninterrupted outbound talkspurt.
    public let maximumSendIntervalMilliseconds: Double
    /// Successful UDP dispatch intervals longer than forty milliseconds within an outbound talkspurt.
    /// Long encoded packets and configured DTX can intentionally produce such intervals.
    public let sendIntervalOverrunCount: UInt64
}

/// Fixed-size outbound timing totals with saturating counters and no per-frame history.
struct VoiceMediaPipelineTiming: Sendable {
    /// Successful synchronous encoder invocations, including DTX-suppressed results.
    private(set) var encodedFrameCount: UInt64 = 0
    /// Longest successful synchronous encoding duration, excluding source wait and transport work.
    private(set) var maximumEncodingDurationMilliseconds: Double = 0
    /// Successful encoder calls exceeding their own PCM frame duration.
    private(set) var encodingDeadlineMissCount: UInt64 = 0
    /// Longest successful dispatch interval reported by the owner within one talkspurt.
    private(set) var maximumSendIntervalMilliseconds: Double = 0
    /// Reported successful dispatch intervals strictly longer than forty milliseconds.
    private(set) var sendIntervalOverrunCount: UInt64 = 0

    /// Records one completed encoder call using its exact 48kHz PCM duration as the elapsed-time budget.
    /// - Parameters:
    ///   - duration: Nonnegative monotonic elapsed time around the synchronous encoder alone.
    ///   - frameCount: Validated 48kHz samples per channel; channel count does not change duration.
    mutating func recordEncoding(duration: Duration, frameCount: Int) {
        if encodedFrameCount < .max { encodedFrameCount += 1 }
        maximumEncodingDurationMilliseconds = max(maximumEncodingDurationMilliseconds, Self.milliseconds(duration))
        let frameDuration = Duration.nanoseconds(Int64(frameCount) * 1_000_000_000 / 48_000)
        if duration > frameDuration, encodingDeadlineMissCount < .max { encodingDeadlineMissCount += 1 }
    }

    /// Records a successful dispatch interval without retaining its source instant or packet.
    /// - Parameter duration: Nonnegative elapsed time between successful dispatch starts.
    mutating func recordSendInterval(_ duration: Duration) {
        maximumSendIntervalMilliseconds = max(maximumSendIntervalMilliseconds, Self.milliseconds(duration))
        if duration > .milliseconds(40), sendIntervalOverrunCount < .max { sendIntervalOverrunCount += 1 }
    }

    /// Converts a monotonic duration to fractional milliseconds without reducing it to whole milliseconds.
    /// - Parameter duration: Elapsed time from the same monotonic clock domain.
    /// - Returns: Fractional milliseconds; zero elapsed time remains exactly zero.
    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

/// Caller-supervised full-duplex Opus/E2EE/RTP media over an injected UDP transport.
///
/// Construction starts no tasks, socket, device, read loop or persistence. The session
/// explicitly authorizes this owner only after secure negotiation and revokes it during
/// reconnect/recovery. Generation checks prevent suspended work from crossing revocation,
/// including a revoke/reauthorize cycle. One send and one receive may be in flight; further
/// callers fail immediately. Control traffic is owned separately and never waits for PCM.
///
/// Receive streams must be registered from authenticated signaling. Every stream has an
/// independent jitter/decoder history; both stream count and aggregate retained bytes are
/// bounded. Playout is caller-paced, with one outstanding sink delivery per stream. Its
/// return value supplies authenticated encoded recording data and PCM; optional caller-owned
/// playback/recording sinks receive the same PCM without an unbounded fan-out queue.
///
/// The injected cipher is shared for the exact transport-key lifetime and is never reset by
/// this owner. Failed sends may consume codec, RTP and cryptographic counters and are never
/// replayed. A send already executing inside a transport cannot be recalled by revocation;
/// session shutdown cancels and awaits its caller-owned tasks before closing the transport.
/// Outbound pacing starts on first use and restarts after secure/speaking discontinuities.
/// Sub-frame lateness retains the sample cadence; a whole packet of debt reanchors at the
/// current instant, preventing idle time or a late wakeup from creating catch-up bursts.
public actor VoiceMediaPipeline<C: Clock> where C.Duration == Duration {
    public let ssrc: UInt32
    public let maximumReceiveStreams: Int
    public let maximumBufferedBytes: Int
    private let transport: any DatagramTransport
    private let peer: DatagramAddress
    private let cipher: VoiceTransportCipher
    private let transformer: any VoiceFrameTransformer
    private let clock: C
    private var nextSendDeadline: C.Instant?
    /// Last successful dispatch start in the current uninterrupted outbound talkspurt.
    private var previousSendInstant: C.Instant?
    /// Fixed-size observations only; timing never changes pacing, codec or transport admission.
    private var timing = VoiceMediaPipelineTiming()
    /// Exclusively owned fixed-format encoder; reference-backed implementations must not be shared.
    private var encoder: any OpusPCMEncoding
    /// Admitted channel geometry cannot be changed by a mutable injected implementation.
    private let encoderChannelCount: Int
    /// Admitted 48-kHz frame duration remains fixed for this pipeline's lifetime.
    private let encoderFrameSampleCount: Int
    private var nextSequence: UInt16
    private var nextTimestamp: UInt32
    private var authorized = false
    private var sendingAllowed = true
    private var closed = false
    private var authorizationGeneration: UInt64 = 0
    private var sendingGeneration: UInt64 = 0
    private var nextStreamGeneration: UInt64 = 0
    private var sending = false
    private var receiving = false
    private var streams: [UInt32: ReceiveStream] = [:]
    private var bufferedBytes = 0
    private var sentPackets: UInt64 = 0
    private var receivedPackets: UInt64 = 0
    private var concealedPackets: UInt64 = 0

    private struct ReceiveStream: Sendable {
        let generation: UInt64
        let capacity: Int
        let maximumBytes: Int
        let playback: (any PCMSink)?
        let recording: (any PCMSink)?
        var decoder: OpusAudioDecoder
        var jitter: VoiceJitterBuffer?
        var packetSampleCount: Int
        var nextTimestamp: UInt32?
        var concealedWhileEmpty = false
        var playing = false
    }

    /// Creates an inert, initially unauthorized media owner without taking resource ownership.
    /// - Parameters:
    ///   - clock: Monotonic timing source for sample-count-based outbound pacing.
    ///   - transport: Already opened UDP transport; the session owns its lifetime/read loop.
    ///   - peer: Exact negotiated UDP peer; unexpected source addresses are rejected.
    ///   - cipher: Shared exact-session transport AEAD and nonwrapping nonce authority.
    ///   - transformer: Required authenticated complete-frame E2EE boundary.
    ///   - ssrc: Local synchronization source assigned by Voice Ready.
    ///   - encoder: Exclusively transferred fixed-format 48kHz Opus encoder. Reference-backed
    ///     implementations must be fresh for this pipeline and must not be retained by callers.
    ///   - maximumReceiveStreams: Hard stream-history bound in `1...4096`, default 64.
    ///   - maximumBufferedBytes: Hard aggregate retained RTP byte bound in `1...67108864`.
    ///   - initialSequence: Initial RTP sequence, default zero; wraps independently of crypto.
    ///   - initialTimestamp: Initial 48kHz RTP timestamp, default zero.
    /// - Throws: `invalidConfiguration` for invalid aggregate bounds or encoder geometry.
    public init(clock: C, transport: any DatagramTransport, peer: DatagramAddress,
                cipher: VoiceTransportCipher, transformer: any VoiceFrameTransformer,
                ssrc: UInt32, encoder: any OpusPCMEncoding, maximumReceiveStreams: Int = 64,
                maximumBufferedBytes: Int = 4_194_304, initialSequence: UInt16 = 0,
                initialTimestamp: UInt32 = 0) throws {
        guard (1...4_096).contains(maximumReceiveStreams),
              (1...67_108_864).contains(maximumBufferedBytes),
              (1...2).contains(encoder.channelCount),
              [120, 240, 480, 960].contains(encoder.frameSampleCount) else {
            throw VoiceMediaPipelineError.invalidConfiguration
        }
        self.ssrc = ssrc
        self.clock = clock
        self.transport = transport
        self.peer = peer
        self.cipher = cipher
        self.transformer = transformer
        self.encoder = encoder
        encoderChannelCount = encoder.channelCount
        encoderFrameSampleCount = encoder.frameSampleCount
        self.maximumReceiveStreams = maximumReceiveStreams
        self.maximumBufferedBytes = maximumBufferedBytes
        nextSequence = initialSequence
        nextTimestamp = initialTimestamp
    }

    /// Changes secure-session admission and invalidates all work admitted under an older gate.
    /// - Parameter authorized: True only after the session's authenticated E2EE readiness check.
    ///   False discards queued receive media, retaining decoder and cryptographic histories.
    ///   Revocation also discards the old outbound pacing origin without changing RTP counters.
    ///   Repeated calls preserve the current generation; a closed owner cannot be reopened.
    public func setAuthorized(_ authorized: Bool) {
        guard !closed, self.authorized != authorized else { return }
        self.authorized = authorized
        authorizationGeneration &+= 1
        if !authorized {
            nextSendDeadline = nil
            previousSendInstant = nil
            for id in Array(streams.keys) {
                streams[id]?.jitter = nil
                streams[id]?.nextTimestamp = nil
                streams[id]?.concealedWhileEmpty = false
            }
            bufferedBytes = 0
        }
    }

    /// Gates outbound media independently from receive admission after speaking signaling.
    /// - Parameter allowed: The session sets true only after its Speaking(1) command succeeds
    ///   and false after stopping/revoking local speaking. Standalone owners default to true.
    ///   Changing this flag invalidates suspended sends without discarding receive audio.
    ///   Disabling outbound media drops its pacing origin so a new talkspurt starts immediately.
    ///   A closed owner cannot be reopened. No signaling command or I/O is performed here.
    public func setSendingAllowed(_ allowed: Bool) {
        guard !closed, sendingAllowed != allowed else { return }
        sendingAllowed = allowed
        sendingGeneration &+= 1
        if !allowed {
            nextSendDeadline = nil
            previousSendInstant = nil
        }
    }

    /// Registers a trusted receive stream without inferring identity from untrusted RTP.
    /// - Parameters:
    ///   - ssrc: Stream bound to a participant by authenticated signaling.
    ///   - nextSequence: Expected first sequence, or nil to anchor to the first authenticated packet.
    ///   - channelCount: Fixed decoded output layout, one or two channels; default one.
    ///   - packetSampleCount: Initial missing-slot duration, a multiple of 120 in `120...5760`.
    ///     Successful decode replaces it with the received packet duration.
    ///   - capacity: Forward jitter window in `1...32767`, default 64 packets.
    ///   - maximumBytes: Per-stream retained serialized-RTP bound, default 256 KiB.
    ///   - playback: Optional bounded caller-owned PCM playback sink.
    ///   - recording: Optional bounded caller-owned PCM recording sink, written after playback.
    /// - Throws: `closed`, `streamExists`, `capacityExceeded`, `invalidConfiguration`,
    ///   or decoder/jitter configuration errors. Registration performs no I/O or task creation.
    public func registerReceiveStream(ssrc: UInt32, nextSequence: UInt16? = nil,
                                      channelCount: Int = 1, packetSampleCount: Int = 960,
                                      capacity: Int = 64, maximumBytes: Int = 262_144,
                                      playback: (any PCMSink)? = nil,
                                      recording: (any PCMSink)? = nil) throws {
        guard !closed else { throw VoiceMediaPipelineError.closed }
        guard streams[ssrc] == nil else { throw VoiceMediaPipelineError.streamExists }
        guard streams.count < maximumReceiveStreams else { throw VoiceMediaPipelineError.capacityExceeded }
        guard (120...5_760).contains(packetSampleCount), packetSampleCount.isMultiple(of: 120),
              maximumBytes <= maximumBufferedBytes else { throw VoiceMediaPipelineError.invalidConfiguration }
        let decoder = try OpusAudioDecoder(channelCount: channelCount)
        let jitter = try VoiceJitterBuffer(ssrc: ssrc, nextSequence: nextSequence ?? 0,
                                         capacity: capacity, maximumBytes: maximumBytes)
        nextStreamGeneration &+= 1
        streams[ssrc] = ReceiveStream(generation: nextStreamGeneration, capacity: capacity,
                                     maximumBytes: maximumBytes, playback: playback, recording: recording,
                                     decoder: decoder, jitter: nextSequence == nil ? nil : jitter,
                                     packetSampleCount: packetSampleCount, nextTimestamp: nil)
    }

    /// Removes a participant's buffered media and decoder without closing injected sinks.
    /// - Parameter ssrc: Trusted stream to remove; missing streams are an idempotent no-op.
    ///   In-flight receive/playout work cannot recreate the removed registration.
    public func removeReceiveStream(ssrc: UInt32) {
        if let stream = streams.removeValue(forKey: ssrc) {
            bufferedBytes -= stream.jitter?.bufferedBytes ?? 0
        }
    }

    /// Encodes, paces, E2EE-protects, packetizes, transport-encrypts and sends one PCM frame.
    /// - Parameters:
    ///   - pcm: Exact encoder duration/layout at 48kHz; no implicit resampling occurs.
    ///   - context: Cancellation and inclusive deadline shared by pacing and the single send.
    /// - Returns: True after a single UDP send; false for DTX suppression. Suppressed intervals
    ///   advance media time without consuming RTP sequence or cryptographic nonces.
    /// - Throws: Admission, PCM, deadline, cancellation, codec, E2EE, transport-AEAD or UDP errors.
    ///   No failed or indeterminate send is retried; a consumed input cannot be replayed.
    public func send(_ pcm: PCMBuffer, context: TransportContext<C>) async throws -> Bool {
        try context.check()
        let generation = try admit()
        let outboundGeneration = try admitSending()
        guard !sending else { throw VoiceMediaPipelineError.concurrentSend }
        guard pcm.format.sampleRate == 48_000, pcm.format.channelCount == encoderChannelCount,
              pcm.frameCount == encoderFrameSampleCount else { throw VoiceMediaPipelineError.invalidPCM }
        sending = true
        defer { sending = false }
        try await pace(frameCount: pcm.frameCount, generation: generation,
                       outboundGeneration: outboundGeneration, context: context)
        let encodingClock = ContinuousClock()
        let encodingStarted = encodingClock.now
        let encoded = try encoder.encode(pcm.samples)
        timing.recordEncoding(duration: encodingStarted.duration(to: encodingClock.now), frameCount: pcm.frameCount)
        try validateEncoderOutput(encoded)
        let timestamp = nextTimestamp
        nextTimestamp &+= UInt32(pcm.frameCount)
        guard encoded.shouldTransmit else { return false }
        try await transmit(encoded.data, timestamp: timestamp, generation: generation,
                           outboundGeneration: outboundGeneration, context: context)
        return true
    }

    /// Paces and sends one application-supplied complete encoded Opus packet through both ciphers.
    /// - Parameters:
    ///   - opus: Complete ordinary RFC 6716 packet, including TOC, all packed frames and optional
    ///     padding. Parsing bounds payloads to 1275 bytes each and total audio to 120ms. Caller
    ///     owns encoder/source continuity; this operation does not alter the built-in encoder.
    ///   - context: Shared inclusive deadline/cancellation policy for pacing and one UDP send.
    /// - Throws: Closed/unauthorized/concurrent admission, malformed/oversize Opus, deadline,
    ///   cancellation, E2EE, RTP, transport-AEAD or UDP errors. Invalid packets consume no time
    ///   or RTP state. Accepted sends reserve their parsed 48kHz duration; ambiguous failures
    ///   are never retried, and reserved RTP/cryptographic counters are never rolled back.
    public func sendOpus(_ opus: Data, context: TransportContext<C>) async throws {
        try context.check()
        let generation = try admit()
        let outboundGeneration = try admitSending()
        guard !sending else { throw VoiceMediaPipelineError.concurrentSend }
        let packet = try OpusPacket(opus)
        sending = true
        defer { sending = false }
        try await pace(frameCount: packet.sampleCount, generation: generation,
                       outboundGeneration: outboundGeneration, context: context)
        let timestamp = nextTimestamp
        nextTimestamp &+= UInt32(packet.sampleCount)
        try await transmit(opus, timestamp: timestamp, generation: generation,
                           outboundGeneration: outboundGeneration, context: context)
    }

    /// Sends Discord's five 20ms termination-silence packets through the ordinary secure path.
    /// - Parameter context: Shared deadline/cancellation; each UDP send occurs once.
    /// - Throws: Concurrent/admission, pacing, E2EE, AEAD or transport errors. A partial
    ///   five-packet sequence is observable as failure and is never automatically restarted.
    ///   The session clears its speaking flag only after successful completion.
    public func sendTerminationSilence(context: TransportContext<C>) async throws {
        try context.check()
        let generation = try admit()
        let outboundGeneration = try admitSending()
        guard !sending else { throw VoiceMediaPipelineError.concurrentSend }
        sending = true
        defer { sending = false }
        for _ in 0..<5 {
            try await pace(frameCount: 960, generation: generation,
                           outboundGeneration: outboundGeneration, context: context)
            let timestamp = nextTimestamp
            nextTimestamp &+= 960
            try await transmit(Data([0xF8, 0xFF, 0xFE]), timestamp: timestamp,
                               generation: generation, outboundGeneration: outboundGeneration,
                               context: context)
        }
    }

    /// Authenticates both encryption layers and inserts one trusted stream's bounded RTP slot.
    /// - Parameter datagram: One complete packet from the exact negotiated UDP peer.
    /// - Throws: Closed/unauthorized/concurrent/unknown-stream/source/type/budget failures,
    ///   malformed RTP/Opus, transport AEAD, E2EE authentication or replay errors. Outer and
    ///   inner nonce authorities may consume verified packets even when jitter admission fails.
    ///   No decode, device callback, sink delivery or playout wait occurs here.
    public func receive(_ datagram: Datagram) async throws {
        try Task.checkCancellation()
        let generation = try admit()
        guard !receiving else { throw VoiceMediaPipelineError.concurrentReceive }
        guard datagram.peer == peer else { throw VoiceMediaPipelineError.unexpectedPeer }
        let length = try RTPPacket.authenticatedHeaderLength(in: datagram.bytes)
        let header = Data(datagram.bytes.prefix(length))
        let bytes = Array(header)
        let id = UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])
        guard let registrationGeneration = streams[id]?.generation else { throw VoiceMediaPipelineError.unknownStream }
        receiving = true
        defer { receiving = false }
        let body = try await cipher.open(sealedPayload: Data(datagram.bytes.dropFirst(length)), authenticatedHeader: header)
        try validate(generation)
        let encrypted = try RTPPacket(bytes: header + body)
        guard encrypted.payloadType == 120 else { throw VoiceMediaPipelineError.unexpectedPayloadType }
        let opus = try await transformer.open(encrypted.payload, ssrc: id)
        try validate(generation)
        _ = try OpusPacket(opus)
        guard var stream = streams[id], stream.generation == registrationGeneration else {
            throw VoiceMediaPipelineError.staleOperation
        }
        let packet = try RTPPacket(payloadType: encrypted.payloadType, marker: encrypted.marker,
                                   sequence: encrypted.sequence, timestamp: encrypted.timestamp, ssrc: id,
                                   contributingSources: encrypted.contributingSources,
                                   headerExtension: encrypted.headerExtension, payload: opus,
                                   paddingCount: encrypted.paddingCount)
        if stream.jitter == nil {
            stream.jitter = try VoiceJitterBuffer(ssrc: id, nextSequence: packet.sequence,
                                                capacity: stream.capacity, maximumBytes: stream.maximumBytes)
            stream.nextTimestamp = packet.timestamp
        }
        if let expectedTimestamp = stream.nextTimestamp {
            let distance = packet.timestamp &- expectedTimestamp
            guard distance < 0x8000_0000 else {
                throw VoicePacketError.duplicateOrLate
            }
            guard distance.isMultiple(of: 120) else { throw VoicePacketError.malformedPacket }
        }
        if stream.concealedWhileEmpty, stream.jitter?.bufferedBytes == 0 {
            guard let expectedSequence = stream.jitter?.nextSequence,
                  packet.sequence &- expectedSequence < 0x8000 else { throw VoicePacketError.duplicateOrLate }
            // Empty-window PLC already covered elapsed media time. RTP sequence advances
            // only for transmitted packets, so DTX and lost packets require reanchoring.
            stream.jitter?.reset(nextSequence: packet.sequence)
            stream.concealedWhileEmpty = false
        }
        let count = packet.serialized().count
        guard count <= maximumBufferedBytes - bufferedBytes else { throw VoiceMediaPipelineError.capacityExceeded }
        try stream.jitter?.insert(packet)
        streams[id] = stream
        bufferedBytes += count
        if receivedPackets < .max { receivedPackets += 1 }
    }

    /// Advances one stream's jitter slot, decodes or conceals it, then writes bounded PCM sinks.
    /// - Parameter ssrc: Registered participant stream. An unanchored stream returns nil until
    ///   its first authenticated packet, avoiding invented RTP sequence positions.
    /// - Returns: Packet/PLC output and optional authenticated encoded recording bytes, or nil
    ///   before anchoring. Idle PLC advances media time while retaining the next transmitted
    ///   RTP sequence, allowing DTX refresh without sequence gaps. Future-timestamp packets
    ///   remain queued while PLC fills the interval. Decoder output is saturated to PCM range.
    /// - Throws: Admission, unknown/concurrent stream, codec, cancellation or sink failures.
    ///   Every attempted packet consumes its jitter slot, including codec failures; malformed
    ///   codec bodies cannot stall later audio. Idle/future-timestamp concealment retains the
    ///   next transmitted sequence. Decoder changes commit on successful decode
    ///   before sink suspension. Sink failure consumes this slot and must not be retried.
    ///   Removing/replacing a stream cannot be undone by a resumed call.
    public func playout(ssrc: UInt32) async throws -> VoicePCMPlayout? {
        try Task.checkCancellation()
        let generation = try admit()
        guard var stream = streams[ssrc] else { throw VoiceMediaPipelineError.unknownStream }
        guard !stream.playing else { throw VoiceMediaPipelineError.concurrentPlayout }
        guard var jitter = stream.jitter else { return nil }
        let before = jitter.bufferedBytes
        let slot: VoicePlayout
        var concealSampleCount = stream.packetSampleCount
        if let packet = jitter.peek(), let timestamp = stream.nextTimestamp,
           packet.timestamp &- timestamp > 0, packet.timestamp &- timestamp < 0x8000_0000 {
            let gap = Int(packet.timestamp &- timestamp)
            guard gap.isMultiple(of: 120) else {
                _ = jitter.pop()
                streams[ssrc]?.jitter = jitter
                bufferedBytes -= before - jitter.bufferedBytes
                throw VoicePacketError.malformedPacket
            }
            concealSampleCount = min(concealSampleCount, gap)
            slot = .missing(sequence: jitter.nextSequence)
        } else if jitter.bufferedBytes == 0 {
            slot = .missing(sequence: jitter.nextSequence)
            stream.concealedWhileEmpty = true
        } else {
            slot = jitter.pop()
        }
        streams[ssrc]?.jitter = jitter
        bufferedBytes -= before - jitter.bufferedBytes
        let sequence: UInt16
        let encoded: Data?
        let samples: [Float]
        switch slot {
        case let .packet(packet):
            if let timestamp = stream.nextTimestamp,
               packet.timestamp &- timestamp >= 0x8000_0000 { throw VoicePacketError.duplicateOrLate }
            sequence = packet.sequence
            encoded = packet.payload
            let parsed = try OpusPacket(packet.payload)
            stream.nextTimestamp = packet.timestamp &+ UInt32(parsed.sampleCount)
            streams[ssrc]?.nextTimestamp = stream.nextTimestamp
            let decoded = try stream.decoder.decode(packet.payload)
            samples = decoded.flatMap(\.samples)
            stream.packetSampleCount = stream.decoder.lastPacketDuration
        case let .missing(missing):
            sequence = missing
            encoded = nil
            samples = try stream.decoder.conceal(frameSampleCount: concealSampleCount).samples
            if let timestamp = stream.nextTimestamp {
                stream.nextTimestamp = timestamp &+ UInt32(concealSampleCount)
            }
        }
        let pcm = try PCMBuffer(format: PCMFormat(sampleRate: 48_000, channelCount: stream.decoder.channelCount),
                                samples: samples.map { max(-1, min(1, $0)) })
        let result = VoicePCMPlayout(ssrc: ssrc, sequence: sequence, concealed: encoded == nil,
                                    encodedOpus: encoded, pcm: pcm)
        stream.jitter = jitter
        stream.playing = true
        streams[ssrc] = stream
        if encoded == nil, concealedPackets < .max { concealedPackets += 1 }
        defer {
            if streams[ssrc]?.generation == stream.generation { streams[ssrc]?.playing = false }
        }
        if let playback = stream.playback {
            try validate(generation)
            try await playback.write(pcm)
        }
        if let recording = stream.recording {
            try validate(generation)
            guard streams[ssrc]?.generation == stream.generation else { throw VoiceMediaPipelineError.staleOperation }
            try await recording.write(pcm)
        }
        try validate(generation)
        guard streams[ssrc]?.generation == stream.generation else { throw VoiceMediaPipelineError.staleOperation }
        return result
    }

    /// Returns bounded counters without exposing media or stream identities.
    /// - Returns: Current admission state, retained bytes, saturating counts and fixed-size timing maxima.
    public func snapshot() -> VoiceMediaPipelineSnapshot {
        VoiceMediaPipelineSnapshot(authorized: authorized, sendingAllowed: sendingAllowed, closed: closed,
                                   receiveStreamCount: streams.count, bufferedBytes: bufferedBytes,
                                   sentPackets: sentPackets, receivedPackets: receivedPackets,
                                   concealedPackets: concealedPackets, encodedFrameCount: timing.encodedFrameCount,
                                   maximumEncodingDurationMilliseconds: timing.maximumEncodingDurationMilliseconds,
                                   encodingDeadlineMissCount: timing.encodingDeadlineMissCount,
                                   maximumSendIntervalMilliseconds: timing.maximumSendIntervalMilliseconds,
                                   sendIntervalOverrunCount: timing.sendIntervalOverrunCount)
    }

    /// Permanently revokes admission and releases bounded local receive/codec histories.
    /// Injected transport, cipher, transformer and sinks remain caller-owned. The session
    /// cancels/awaits its media tasks and closes its resources separately. Repeated calls are safe.
    public func close() {
        guard !closed else { return }
        closed = true
        authorized = false
        sendingAllowed = false
        authorizationGeneration &+= 1
        nextSendDeadline = nil
        previousSendInstant = nil
        streams.removeAll(keepingCapacity: false)
        bufferedBytes = 0
        encoder.reset()
    }

    /// Checks secure admission and returns the revocation generation for suspension guards.
    /// - Returns: Current authorization generation, valid until an admission change.
    /// - Throws: `closed`, `unauthorized` or cooperative cancellation before any reservation.
    private func admit() throws -> UInt64 {
        try Task.checkCancellation()
        guard !closed else { throw VoiceMediaPipelineError.closed }
        guard authorized else { throw VoiceMediaPipelineError.unauthorized }
        return authorizationGeneration
    }

    /// Rechecks a suspended operation's admission without restoring any consumed state.
    /// - Parameter generation: Generation captured when the operation was admitted.
    /// - Throws: Cancellation, `closed`, `unauthorized`, or `staleOperation` after reauthorization.
    private func validate(_ generation: UInt64) throws {
        let current = try admit()
        guard generation == current else { throw VoiceMediaPipelineError.staleOperation }
    }

    /// Captures the outbound speaking gate without changing receive/playout admission.
    /// - Returns: Current outbound revocation generation.
    /// - Throws: `unauthorized` while the session has disabled outbound speaking/media.
    private func admitSending() throws -> UInt64 {
        guard sendingAllowed else { throw VoiceMediaPipelineError.unauthorized }
        return sendingGeneration
    }

    /// Verifies both secure-session and outbound-speaking generations after suspension.
    /// - Parameters:
    ///   - generation: Secure-session generation captured at operation admission.
    ///   - outboundGeneration: Speaking/media generation captured at operation admission.
    /// - Throws: Cancellation, closure, unauthorized media or stale generation failures.
    private func validateSending(_ generation: UInt64, outboundGeneration: UInt64) throws {
        try validate(generation)
        guard try admitSending() == outboundGeneration else { throw VoiceMediaPipelineError.staleOperation }
    }

    /// Rejects inconsistent injected encoder results before RTP or cryptographic state changes.
    /// - Parameter encoded: One synchronous codec result for the admitted PCM frame.
    /// - Throws: `invalidEncoderOutput` for empty, oversized, over-budget, malformed or
    ///   geometry-changing data, or inconsistent DTX decisions. Codec and pacing work may
    ///   already have advanced, so callers treat rejection as terminal instead of replaying.
    private func validateEncoderOutput(_ encoded: OpusAudioEncodedPacket) throws {
        guard (1...1_276).contains(encoded.packetByteBudget),
              !encoded.data.isEmpty, encoded.data.count <= encoded.packetByteBudget,
              encoded.shouldTransmit != encoded.isDTX,
              encoder.channelCount == encoderChannelCount,
              encoder.frameSampleCount == encoderFrameSampleCount,
              let packet = try? OpusPacket(encoded.data),
              packet.sampleCount == encoderFrameSampleCount,
              packet.channelCount == encoderChannelCount else {
            throw VoiceMediaPipelineError.invalidEncoderOutput
        }
    }

    /// Reserves one bounded 48kHz interval without accumulating catch-up debt across idle time.
    ///
    /// Opus packets and the fixed encoder use 120-sample quanta, so each duration is an exact
    /// integer number of nanoseconds. The first interval starts at first use, not construction.
    /// Ordinary sub-frame wakeup lateness retains the existing cadence. Lateness of at least
    /// this packet's duration, including after a delayed sleep, moves the origin to now and
    /// reserves a complete next interval. Thus at most one overdue packet starts immediately;
    /// a later packet cannot drain arbitrarily old pacing debt. This is caller-owned scheduling,
    /// not a realtime guarantee, and it does not invent media time for periods without input.
    /// - Parameters:
    ///   - frameCount: Already validated 48kHz Opus duration, a multiple of 120 in `120...5760`.
    ///   - generation: Secure-session generation captured before sending was reserved.
    ///   - outboundGeneration: Speaking generation captured before sending was reserved.
    ///   - context: Inclusive deadline/cancellation policy governing the sole optional sleep.
    /// - Throws: Deadline, cancellation, clock or revoked/stale admission errors. Failure
    ///   reserves no pacing interval; RTP, encoder and cryptographic state remain untouched.
    ///   Gate changes during suspension clear the origin and cannot be overwritten by this call.
    private func pace(frameCount: Int, generation: UInt64, outboundGeneration: UInt64,
                      context: TransportContext<C>) async throws {
        let duration = Duration.nanoseconds(Int64(frameCount) * 1_000_000_000 / 48_000)
        let scheduled = nextSendDeadline ?? clock.now
        if clock.now < scheduled {
            try await context.run { [clock] in try await clock.sleep(until: scheduled, tolerance: .zero) }
        }
        try context.check()
        try validateSending(generation, outboundGeneration: outboundGeneration)
        let now = clock.now
        let start = scheduled.duration(to: now) >= duration ? now : scheduled
        nextSendDeadline = start.advanced(by: duration)
    }

    /// Protects and sends one already paced complete Opus packet, reserving RTP once.
    /// - Parameters:
    ///   - opus: Complete validated encoder output or fixed termination-silence packet.
    ///   - timestamp: Previously reserved 48kHz media timestamp, including DTX intervals.
    ///   - generation: Secure admission generation which must survive every suspension.
    ///   - outboundGeneration: Speaking gate generation which must survive every suspension.
    ///   - context: Shared cancellation/deadline policy for exactly one UDP send.
    /// - Throws: Admission/deadline, E2EE, RTP size, transport AEAD or UDP errors. Sequence and
    ///   crypto reservations are intentionally never rolled back after external processing.
    private func transmit(_ opus: Data, timestamp: UInt32, generation: UInt64,
                          outboundGeneration: UInt64, context: TransportContext<C>) async throws {
        try context.check()
        let sequence = nextSequence
        nextSequence &+= 1
        let protected = try await transformer.seal(opus, ssrc: ssrc)
        try validateSending(generation, outboundGeneration: outboundGeneration)
        try context.check()
        let packet = try RTPPacket(sequence: sequence, timestamp: timestamp, ssrc: ssrc, payload: protected)
        let plain = packet.serialized()
        let header = Data(plain.prefix(12))
        let sealed = try await cipher.seal(payload: Data(plain.dropFirst(12)), authenticatedHeader: header)
        try validateSending(generation, outboundGeneration: outboundGeneration)
        try context.check()
        let dispatched = clock.now
        try await transport.sendDatagram(Datagram(bytes: header + sealed, peer: peer), context: context)
        if sentPackets < .max { sentPackets += 1 }
        if !closed, authorized, sendingAllowed, authorizationGeneration == generation,
           sendingGeneration == outboundGeneration {
            if let previousSendInstant { timing.recordSendInterval(previousSendInstant.duration(to: dispatched)) }
            previousSendInstant = dispatched
        }
    }
}
