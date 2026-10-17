import Foundation

/// Codec labels carried as metadata; no encoder or decoder is implied by a case.
public enum MediaCodec: String, Sendable, Equatable, Hashable {
    case opus
    case h264
    case vp8
    case vp9
    case av1
}

/// Bounded opaque encoded audio with explicit timing and layout metadata.
public struct EncodedAudioFrame: Sendable, Equatable {
    public let codec: MediaCodec
    public let bytes: Data
    public let timestamp: MediaTime
    public let duration: MediaTime
    public let sampleRate: Int
    public let channelCount: Int

    /// Owns an encoded audio block after validating metadata and allocation limits.
    ///
    /// A bounded owned byte copy avoids retaining excess caller capacity or slice backing storage.
    /// Payload syntax is deliberately not parsed here; use a codec parser before network
    /// publication. This value does not establish authentication or negotiated capabilities.
    /// - Parameters:
    ///   - codec: Must be `.opus`; other enum cases describe video only.
    ///   - bytes: Nonempty encoded payload, at most 65,536 bytes.
    ///   - timestamp: Nonnegative caller-owned presentation timestamp.
    ///   - duration: Positive duration no longer than 120ms, compared with integer arithmetic.
    ///   - sampleRate: PCM rate metadata in `8_000...192_000`; defaults to Opus's 48kHz clock.
    ///   - channelCount: One or two output channels; defaults to stereo.
    /// - Throws: `MediaError.invalidEncodedFrame` for unsupported codec, size or duration;
    ///   `invalidFormat` for invalid PCM layout. No I/O or asynchronous work occurs.
    public init(codec: MediaCodec = .opus, bytes: Data, timestamp: MediaTime, duration: MediaTime,
                sampleRate: Int = 48_000, channelCount: Int = 2) throws {
        _ = try PCMFormat(sampleRate: sampleRate, channelCount: channelCount)
        guard codec == .opus, !bytes.isEmpty, bytes.count <= 65_536,
              duration.value > 0,
              duration.value <= Int64(duration.timescale) * 120 / 1_000 else {
            throw MediaError.invalidEncodedFrame
        }
        self.codec = codec
        self.bytes = bytes.withUnsafeBytes { Data($0) }
        self.timestamp = timestamp
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

/// Opaque encoded video access unit; codecs, capture, decode and RTP packetization are external.
public struct EncodedVideoFrame: Sendable, Equatable {
    public let codec: MediaCodec
    public let bytes: Data
    public let timestamp: MediaTime
    public let width: Int
    public let height: Int
    public let isKeyFrame: Bool

    /// Validates bounded encoded-video metadata without inspecting codec syntax.
    /// A bounded owned byte copy avoids retaining excess caller capacity or slice backing storage.
    /// - Parameters:
    ///   - codec: H.264, VP8, VP9 or AV1; `.opus` is rejected.
    ///   - bytes: Nonempty opaque access unit, at most 4,194,304 bytes.
    ///   - timestamp: Nonnegative caller-owned presentation time.
    ///   - width: Positive coded width no greater than 8,192 pixels.
    ///   - height: Positive coded height no greater than 8,192 pixels.
    ///   - isKeyFrame: Caller-asserted random-access metadata; not verified against the payload.
    /// - Throws: `MediaError.invalidEncodedFrame` for an audio codec, empty/oversize payload,
    ///   or invalid dimensions. No capture, codec, task or network resources are acquired.
    public init(codec: MediaCodec, bytes: Data, timestamp: MediaTime,
                width: Int, height: Int, isKeyFrame: Bool) throws {
        guard codec != .opus, !bytes.isEmpty, bytes.count <= 4_194_304,
              (1...8_192).contains(width), (1...8_192).contains(height) else {
            throw MediaError.invalidEncodedFrame
        }
        self.codec = codec
        self.bytes = bytes.withUnsafeBytes { Data($0) }
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.isKeyFrame = isKeyFrame
    }
}

/// Pull-based source; consumers own pacing, repeated polling and lifecycle supervision.
public protocol PCMSource: Sendable {
    /// Retrieves one currently available block without creating background production work.
    /// - Returns: The next block, or nil when no block is currently available; nil alone
    ///   does not distinguish an idle source from a finished source.
    /// - Throws: Cancellation or an implementation-specific source failure. Implementations
    ///   document their bounds and must not retain unbounded pending reads.
    func read() async throws -> PCMBuffer?
}

/// Explicit-admission sink; producers own pacing and retry/drop decisions.
public protocol PCMSink: Sendable {
    /// Offers a whole block atomically, preserving its interleaved layout.
    /// - Parameter buffer: Immutable bounded PCM to transfer to the sink.
    /// - Throws: Cancellation, capacity or closed-sink failures. A failed offer must not
    ///   partially retain a block; implementations document ordering and capacity policy.
    func write(_ buffer: PCMBuffer) async throws
}

/// Actor-isolated FIFO source/sink with hard block/PCM-byte bounds and fail-fast overflow.
///
/// Construction starts no tasks or I/O. Read/write operations contain no suspension inside
/// isolation and are linearizable in actor admission order. Empty reads return immediately;
/// no waiting producer/consumer continuations are retained. Bounds account PCM payload bytes,
/// while the block limit also bounds empty-buffer and format metadata. Callers sharing an
/// aggregate budget must choose limits across queues; this queue does not coordinate identities.
public actor PCMFrameQueue: PCMSource, PCMSink {
    public let maximumBlocks: Int
    public let maximumBytes: Int
    public private(set) var accountedBytes = 0
    public private(set) var isFinished = false
    private var buffers: [PCMBuffer] = []

    /// Creates an empty queue with independent block and PCM storage bounds.
    /// - Parameters:
    ///   - maximumBlocks: Queue block capacity in `1...4096`.
    ///   - maximumBytes: PCM payload capacity in `1...67_108_864` bytes.
    /// - Throws: `MediaError.invalidCapacity` for capacities outside these ranges.
    ///   Capacity is not preallocated; memory grows only after successful writes.
    public init(maximumBlocks: Int = 8, maximumBytes: Int = 1_048_576) throws {
        guard (1...4_096).contains(maximumBlocks), (1...67_108_864).contains(maximumBytes) else {
            throw MediaError.invalidCapacity
        }
        self.maximumBlocks = maximumBlocks
        self.maximumBytes = maximumBytes
    }

    /// Atomically admits a block after checking cancellation, lifecycle and both budgets.
    /// - Parameter buffer: Complete block; successful admission retains value ownership.
    /// - Throws: `CancellationError` if cancelled at entry, `MediaError.closed` after finish,
    ///   or `queueFull` if either bound would be exceeded. Failures retain no input block.
    ///   No waiting or implicit dropping occurs; callers choose whether to retry or discard.
    public func write(_ buffer: PCMBuffer) throws {
        try Task.checkCancellation()
        guard !isFinished else { throw MediaError.closed }
        guard buffers.count < maximumBlocks, buffer.accountedBytes <= maximumBytes - accountedBytes else {
            throw MediaError.queueFull
        }
        buffers.append(buffer)
        accountedBytes += buffer.accountedBytes
    }

    /// Removes the oldest queued block immediately, including after a draining finish.
    /// - Returns: The next FIFO block, or nil if currently empty. Successful removal releases
    ///   this queue's byte accounting. Array shifting is bounded by `maximumBlocks`.
    /// - Throws: `CancellationError` if cancelled at entry; a cancelled read removes nothing.
    public func read() throws -> PCMBuffer? {
        try Task.checkCancellation()
        guard !buffers.isEmpty else { return nil }
        let buffer = buffers.removeFirst()
        accountedBytes -= buffer.accountedBytes
        return buffer
    }

    /// Stops future writes; optionally discards retained blocks and releases their accounting.
    /// - Parameter discardingBuffered: False preserves queued blocks for subsequent reads;
    ///   true discards them immediately. Repeated finish calls are safe, and a later true call
    ///   may discard blocks retained by an earlier false call. No task or device needs closing.
    public func finish(discardingBuffered: Bool = false) {
        isFinished = true
        if discardingBuffered {
            buffers.removeAll(keepingCapacity: false)
            accountedBytes = 0
        }
    }
}
