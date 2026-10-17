import Foundation

/// Validation and bounded-admission failures for portable media values and queues.
public enum MediaError: Error, Sendable, Equatable {
    case invalidTime
    case invalidFormat
    case invalidSamples
    case bufferTooLarge
    case invalidGain
    case incompatibleBuffers
    case invalidThreshold
    case invalidCapacity
    case queueFull
    case closed
    case invalidEncodedFrame
}

/// A nonnegative timestamp or duration expressed as integer ticks over a positive timescale.
///
/// Fractions retain their supplied representation, so equality compares ticks and timescale,
/// not mathematical equivalence. No floating-point clock or wall-clock ownership is implied.
public struct MediaTime: Sendable, Equatable, Hashable {
    public let value: Int64
    public let timescale: Int32

    /// Creates an exact media time without reducing its fraction or starting any work.
    /// - Parameters:
    ///   - value: Nonnegative number of ticks, including zero.
    ///   - timescale: Positive number of ticks per second.
    /// - Throws: `MediaError.invalidTime` for negative ticks or a nonpositive timescale.
    public init(value: Int64, timescale: Int32) throws {
        guard value >= 0, timescale > 0 else { throw MediaError.invalidTime }
        self.value = value
        self.timescale = timescale
    }
}

/// Interleaved normalized floating-point PCM format; independent of devices and codecs.
public struct PCMFormat: Sendable, Equatable, Hashable {
    public let sampleRate: Int
    public let channelCount: Int

    /// Validates a portable mono or stereo PCM format.
    /// - Parameters:
    ///   - sampleRate: Integer sample frames per second, from 8,000 through 192,000.
    ///     These storage bounds do not promise a device or codec supports every rate.
    ///   - channelCount: One for mono or two for stereo; channel order is preserved.
    /// - Throws: `MediaError.invalidFormat` outside these ranges.
    public init(sampleRate: Int = 48_000, channelCount: Int = 2) throws {
        guard (8_000...192_000).contains(sampleRate), (1...2).contains(channelCount) else {
            throw MediaError.invalidFormat
        }
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

/// An immutable interleaved PCM block bounded to 120 milliseconds, including empty blocks.
///
/// Samples are finite values in `-1...1`. Construction performs synchronous linear validation
/// and makes a dense owned sample copy so excess caller-reserved capacity is not retained.
/// No device or background work starts; callers own scheduling and timestamps separately.
public struct PCMBuffer: Sendable, Equatable {
    public let format: PCMFormat
    public let samples: [Float]
    public let frameCount: Int
    public let duration: MediaTime
    public let accountedBytes: Int

    /// Validates normalized interleaved samples and derives exact duration and storage cost.
    /// - Parameters:
    ///   - format: Sample rate and mono/stereo layout; no implicit channel conversion occurs.
    ///   - samples: Whole interleaved frames; every value must be finite and in `-1...1`.
    ///     Empty input is valid. At most `floor(sampleRate * 0.120)` frames are accepted.
    /// - Throws: `MediaError.bufferTooLarge` above 120ms, or `invalidSamples` for partial
    ///   frames, out-of-range samples or NaN/infinity. Validation completes before retention.
    public init(format: PCMFormat, samples: [Float]) throws {
        guard samples.count <= format.sampleRate * 120 / 1_000 * format.channelCount else {
            throw MediaError.bufferTooLarge
        }
        guard samples.count.isMultiple(of: format.channelCount),
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
            throw MediaError.invalidSamples
        }
        self.format = format
        self.samples = samples.withUnsafeBufferPointer { Array($0) }
        self.frameCount = samples.count / format.channelCount
        self.duration = try MediaTime(value: Int64(frameCount), timescale: Int32(format.sampleRate))
        self.accountedBytes = samples.count * MemoryLayout<Float>.stride
    }

    /// Converts signed 16-bit little-endian PCM into normalized floats.
    /// - Parameters:
    ///   - format: Layout of the incoming interleaved samples.
    ///   - pcm16LittleEndian: At most 120ms of complete frames; little-endian signed samples.
    /// - Throws: `MediaError.invalidSamples` for incomplete sample/frame bytes, or
    ///   `bufferTooLarge` above the duration bound. The original byte array is not retained.
    public init(format: PCMFormat, pcm16LittleEndian: [UInt8]) throws {
        guard pcm16LittleEndian.count <= format.sampleRate * 120 / 1_000 * format.channelCount * 2 else {
            throw MediaError.bufferTooLarge
        }
        guard pcm16LittleEndian.count.isMultiple(of: 2 * format.channelCount) else {
            throw MediaError.invalidSamples
        }
        var converted = [Float]()
        converted.reserveCapacity(pcm16LittleEndian.count / 2)
        for index in stride(from: 0, to: pcm16LittleEndian.count, by: 2) {
            let bits = UInt16(pcm16LittleEndian[index]) | UInt16(pcm16LittleEndian[index + 1]) << 8
            converted.append(Float(Int16(bitPattern: bits)) / 32_768)
        }
        try self.init(format: format, samples: converted)
    }

    /// Quantizes normalized samples to signed 16-bit little-endian PCM, with saturation.
    ///
    /// Uses nearest rounding with ties away from zero and a 32768 scale, mapping `-1`
    /// to -32768 and `1` to 32767. No dithering is applied. Runtime and output are linear
    /// in the bounded input; the buffer is unchanged.
    /// - Returns: Owned interleaved bytes, or an empty array for an empty block.
    public func pcm16LittleEndian() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let quantized = Int16(max(-32_768, min(32_767, Int((Double(sample) * 32_768).rounded()))))
            let bits = UInt16(bitPattern: quantized)
            bytes.append(UInt8(truncatingIfNeeded: bits))
            bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return bytes
    }

    /// Applies a nonnegative linear gain and clips each resulting sample to `-1...1`.
    /// - Parameter gain: Finite multiplier in `0...64`; zero produces silence.
    /// - Returns: A new buffer with unchanged format and frame count; this buffer is unchanged.
    /// - Throws: `MediaError.invalidGain` for negative, nonfinite or greater-than-64 gain.
    ///   Processing is synchronous, linear and bounded to the existing block size.
    public func applyingGain(_ gain: Float) throws -> PCMBuffer {
        guard gain.isFinite, (0...64).contains(gain) else { throw MediaError.invalidGain }
        return try PCMBuffer(format: format, samples: samples.map { max(-1, min(1, $0 * gain)) })
    }

    /// Sums two aligned blocks, clipping once after addition for each sample.
    /// - Parameter other: A buffer with exactly the same format and frame count.
    /// - Returns: A new summed block; no normalization or timestamp alignment is inferred.
    /// - Throws: `MediaError.incompatibleBuffers` for differing formats or frame counts.
    ///   Execution is synchronous and linear; both source blocks remain unchanged.
    public func mixing(_ other: PCMBuffer) throws -> PCMBuffer {
        guard format == other.format, frameCount == other.frameCount else {
            throw MediaError.incompatibleBuffers
        }
        return try PCMBuffer(format: format, samples: zip(samples, other.samples).map { max(-1, min(1, $0 + $1)) })
    }

    /// Converts one block with deterministic linear interpolation and a held final sample.
    ///
    /// This basic converter has no antialias filter, retained phase or streaming continuity;
    /// it is suitable for bounded fixtures and simple previews, not production downsampling
    /// quality claims. Callers needing a streaming resampler must inject one separately.
    /// - Parameter sampleRate: Destination rate in `8_000...192_000`; channels are preserved.
    /// - Returns: `floor(inputFrames * destinationRate / sourceRate)` frames, possibly empty.
    ///   Equal rates return the unchanged value. Output cannot exceed 120ms.
    /// - Throws: `MediaError.invalidFormat` for a rate outside the supported storage bounds.
    public func resampled(to sampleRate: Int) throws -> PCMBuffer {
        let destination = try PCMFormat(sampleRate: sampleRate, channelCount: format.channelCount)
        if sampleRate == format.sampleRate { return self }
        let outputCount = frameCount * sampleRate / format.sampleRate
        var output = [Float]()
        output.reserveCapacity(outputCount * format.channelCount)
        for frame in 0..<outputCount {
            let numerator = frame * format.sampleRate
            let lower = min(frameCount - 1, numerator / sampleRate)
            let upper = min(frameCount - 1, lower + 1)
            let weight = Float(numerator % sampleRate) / Float(sampleRate)
            for channel in 0..<format.channelCount {
                let first = samples[lower * format.channelCount + channel]
                let second = samples[upper * format.channelCount + channel]
                output.append(max(-1, min(1, first + (second - first) * weight)))
            }
        }
        return try PCMBuffer(format: destination, samples: output)
    }

    /// Classifies a block using its root-mean-square amplitude across all channels.
    ///
    /// This stateless energy gate is not a speech classifier, noise suppressor or hangover
    /// detector; music/noise above the threshold also passes. No timing or task is retained.
    /// - Parameter threshold: Finite normalized RMS threshold in `0...1`, inclusive.
    /// - Returns: Whether a nonempty block's RMS is greater than or equal to the threshold.
    ///   Empty blocks always return false, including a zero threshold.
    /// - Throws: `MediaError.invalidThreshold` for nonfinite or out-of-range thresholds.
    public func passesEnergyGate(threshold: Float) throws -> Bool {
        guard threshold.isFinite, (0...1).contains(threshold) else { throw MediaError.invalidThreshold }
        guard !samples.isEmpty else { return false }
        let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return energy / Double(samples.count) >= Double(threshold) * Double(threshold)
    }
}
