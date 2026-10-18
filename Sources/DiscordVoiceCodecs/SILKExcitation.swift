/// Rejections from bounded, exact SILK excitation reconstruction.
public enum SILKExcitationError: Error, Sendable, Equatable {
    case invalidSeed
    case invalidSampleCount
}

/// The decoded SILK frame category selecting excitation quantization offsets.
public enum SILKSignalType: Int, Sendable, CaseIterable {
    case inactive = 0
    case unvoiced = 1
    case voiced = 2
}

/// The decoded low/high quantization-offset choice for a SILK frame.
public enum SILKQuantizationOffset: Int, Sendable, CaseIterable {
    case low = 0
    case high = 1
}

/// Exact RFC 6716 section 4.2.7.8.6 excitation reconstruction from signed pulses.
///
/// This primitive applies the quantization-level adjustment, the six Table 53
/// offset choices, modulo-2^32 pseudorandom sequence and sample sign inversion.
/// Outputs are signed Q23 integers, with all arithmetic performed exactly. The
/// input pulse locations, LSB magnitudes and signs must already have been decoded;
/// this primitive performs no entropy reading, LPC/LTP filtering or PCM decoding.
///
/// One value belongs to one SILK frame/channel. Retain it across chunks *within*
/// that frame and reset its two-bit seed at every new SILK frame. It retains only
/// the current seed and immutable frame choices; construction starts no I/O/tasks.
public struct SILKExcitationReconstructor: Sendable {
    /// Frame signal type; inactive and unvoiced share the same offset magnitudes.
    public let signalType: SILKSignalType
    /// Frame quantization offset category, independent of the signed pulse values.
    public let quantizationOffset: SILKQuantizationOffset
    /// Current modulo-2^32 seed, including the most recently reconstructed pulse.
    public private(set) var seed: UInt32
    /// Maximum block length: 20 ms at SILK's maximum internal 16 kHz channel rate.
    public static let maximumBlockSamples = 320

    /// Creates a new independently owned frame/channel excitation state.
    /// - Parameters:
    ///   - seed: Decoded two-bit frame seed, in `0...3`; this is not cryptographic RNG.
    ///   - signalType: Previously decoded inactive, unvoiced or voiced frame type.
    ///   - quantizationOffset: Previously decoded low/high Table 53 offset choice.
    /// - Throws: `invalidSeed` above three. Initialization performs no pulse work,
    ///   entropy decoding, allocations proportional to stream length or external work.
    public init(seed: UInt8, signalType: SILKSignalType, quantizationOffset: SILKQuantizationOffset) throws {
        guard seed <= 3 else { throw SILKExcitationError.invalidSeed }
        self.seed = UInt32(seed)
        self.signalType = signalType
        self.quantizationOffset = quantizationOffset
    }

    /// Begins another frame with the same signal/offset choices and a new frame seed.
    /// - Parameter seed: Decoded two-bit seed, in `0...3`. Construct a new value when
    ///   either frame category changes; the previous pseudo-random seed is discarded.
    /// - Throws: `invalidSeed` above three, preserving the current seed on failure.
    public mutating func reset(seed: UInt8) throws {
        guard seed <= 3 else { throw SILKExcitationError.invalidSeed }
        self.seed = UInt32(seed)
    }

    /// Reconstructs exact Q23 excitation and carries the seed across frame chunks.
    /// - Parameter signedPulses: Zero through 320 signed raw pulse/LSB magnitudes.
    ///   All Int16 values are handled without overflow; accepting a value does not
    ///   certify that a legal SILK entropy payload could have produced it.
    /// - Returns: One signed Q23 integer per input sample. Divide by `2^23` for
    ///   normalized residual synthesis. Zero pulses still consume RNG steps and
    ///   emit the signed quantization offset; empty input leaves the seed untouched.
    /// - Throws: `invalidSampleCount` above 320 before changing seed or allocating
    ///   output. Input samples cannot otherwise fail, so mutation is atomic on error.
    /// - Complexity: O(samples) work/output and O(1) retained state. No suspension,
    ///   tasks, cancellation, cryptographic guarantees or native codec linkage.
    public mutating func reconstruct(_ signedPulses: [Int16]) throws -> [Int32] {
        guard signedPulses.count <= Self.maximumBlockSamples else { throw SILKExcitationError.invalidSampleCount }
        let offset: Int32
        switch (signalType, quantizationOffset) {
        case (.voiced, .low): offset = 8
        case (.voiced, .high), (.inactive, .low), (.unvoiced, .low): offset = 25
        case (.inactive, .high), (.unvoiced, .high): offset = 60
        }
        var result: [Int32] = []
        result.reserveCapacity(signedPulses.count)
        for pulse in signedPulses {
            let raw = Int32(pulse)
            let adjustment: Int32 = raw > 0 ? 20 : (raw < 0 ? -20 : 0)
            var excitation = raw * 256 - adjustment + offset
            seed = seed &* 196_314_165 &+ 907_633_515
            if seed & 0x8000_0000 != 0 { excitation = -excitation }
            seed = seed &+ UInt32(bitPattern: raw)
            result.append(excitation)
        }
        return result
    }
}
