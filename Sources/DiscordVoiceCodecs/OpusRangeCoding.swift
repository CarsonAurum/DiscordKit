import Foundation

/// Failures in the bounded, owned RFC 6716 entropy primitive; none imply a complete codec.
public enum OpusRangeCodingError: Error, Sendable, Equatable {
    case invalidFrameByteCount
    case invalidMaximumOperations
    case invalidProbabilityModel
    case invalidSymbol
    case invalidLogProbability
    case invalidRawBitCount
    case invalidRawValue
    case invalidUniformTotal
    case invalidUniformValue
    case operationLimitExceeded
    case frameBudgetExceeded
    case corruptUniformValue
    case finalized
    case unusableState
}

/// Immutable frequency counts for at most 257 symbols, retaining the exact total frequency.
///
/// RFC 6716 contexts with proportional counts but different totals are not interchangeable.
/// The 257-symbol bound admits CELT's maximum triangular stereo/theta context.
/// Zero-frequency symbols are retained in their original positions and cannot be encoded.
/// This value owns its table, performs no I/O, and is safe to share across independent coders.
public struct OpusProbabilityModel: Sendable, Equatable {
    /// Original symbol frequencies; zero denotes an impossible symbol.
    public let frequencies: [UInt32]
    /// Exact context total, in `1...65_535`.
    public let total: UInt32
    fileprivate let cumulative: [UInt32]

    /// Validates an exact context without rescaling or dropping impossible symbols.
    /// Copies the live elements into dense storage, discarding any oversized caller reservation.
    /// - Parameter frequencies: One through 257 counts whose positive sum is at most 65,535.
    /// - Throws: `invalidProbabilityModel` for an empty/oversized table or invalid sum.
    public init(frequencies: [UInt32]) throws {
        guard !frequencies.isEmpty, frequencies.count <= 257 else {
            throw OpusRangeCodingError.invalidProbabilityModel
        }
        var cumulative: [UInt32] = [0]
        var total: UInt64 = 0
        for frequency in frequencies {
            total += UInt64(frequency)
            guard total <= 65_535 else { throw OpusRangeCodingError.invalidProbabilityModel }
            cumulative.append(UInt32(total))
        }
        guard total > 0 else { throw OpusRangeCodingError.invalidProbabilityModel }
        self.frequencies = frequencies.withUnsafeBufferPointer { Array($0) }
        self.total = UInt32(total)
        self.cumulative = cumulative
    }

    /// Converts an RFC 6716 inverse-CDF table into an exact frequency context.
    /// - Parameters:
    ///   - inverseCDF: One through 257 nonincreasing values, ending in zero. The first
    ///     value must be smaller than `2^precision`; equal adjacent values retain an
    ///     impossible symbol. A leading impossible symbol cannot use this representation.
    ///   - precision: Total-frequency exponent in `1...8`, defaulting to eight.
    /// - Throws: `invalidProbabilityModel` for invalid precision, ordering or termination.
    public init(inverseCDF: [UInt8], precision: Int = 8) throws {
        guard (1...8).contains(precision), !inverseCDF.isEmpty, inverseCDF.count <= 257,
              inverseCDF.last == 0 else { throw OpusRangeCodingError.invalidProbabilityModel }
        var previous: UInt32 = 1 << precision
        guard UInt32(inverseCDF[0]) < previous else {
            throw OpusRangeCodingError.invalidProbabilityModel
        }
        var frequencies: [UInt32] = []
        frequencies.reserveCapacity(inverseCDF.count)
        for value in inverseCDF {
            let current = UInt32(value)
            guard current <= previous else { throw OpusRangeCodingError.invalidProbabilityModel }
            frequencies.append(previous - current)
            previous = current
        }
        try self.init(frequencies: frequencies)
    }
}

/// Shared integer arithmetic for the independently owned RFC 6716 range coder.
private enum OpusRangeMath {
    /// Returns the number of significant bits; zero has zero significant bits.
    /// - Parameter value: Unsigned integer whose magnitude is measured.
    /// - Returns: An integer in `0...32`, without floating-point rounding.
    static func integerLog(_ value: UInt32) -> Int { 32 - value.leadingZeroBitCount }

    /// Computes RFC 6716 section 4.1.6.2's exact eighth-bit upper bound.
    /// - Parameters:
    ///   - range: Normalized nonzero range, greater than `2^23`.
    ///   - totalBits: Whole input/output bit accounting including buffered bits.
    /// - Returns: The conservative consumed-bit bound in units of one eighth of a bit.
    static func fractionalUsage(range: UInt32, totalBits: Int) -> Int {
        var logarithm = integerLog(range)
        var fraction = UInt64(range >> (logarithm - 16))
        for _ in 0..<3 {
            fraction = (fraction * fraction) >> 15
            let bit = Int(fraction >> 16)
            logarithm = (logarithm << 1) | bit
            fraction >>= bit
        }
        return totalBits * 8 - logarithm
    }
}

/// Owned RFC 6716 sections 4.1/5.1 entropy encoder for one explicitly sized Opus frame.
///
/// This synchronous value performs no I/O, launches no tasks and imports no native codec.
/// It packs arithmetic-coded symbols at the front and raw bits at the back. Construction
/// bounds frame storage to 1,275 bytes; a separate operation bound limits probability-one
/// symbols. Value copies are independent, so callers serialize mutations of each instance.
/// Invalid arguments and operation-limit rejection preserve state. Exceeding the frame
/// budget makes the instance unusable; discard it and choose a larger frame. Finalization
/// consumes the instance's mutation authority. No SILK/CELT audio encoding is provided.
public struct OpusRangeEncoder: Sendable {
    /// Exact output-frame length, excluding any Opus packet TOC or packing header.
    public let frameByteCount: Int
    /// Maximum successful coding calls, including zero-bit calls; excludes finalization.
    public let maximumOperations: Int
    /// Number of admitted coding calls; a budget-failing call is also counted.
    public private(set) var operationCount = 0
    /// Arithmetic range, normalized after successful calls; compare only usable streams.
    /// The corresponding decoder must reproduce this value after matching operations.
    public var finalRange: UInt32 { range }
    /// Conservative consumed-bit upper bound, including the encoder termination reserve.
    public var bitsUsed: Int { totalBits - OpusRangeMath.integerLog(range) }
    /// Bit-exact conservative consumed-bit upper bound in eighth-bit units.
    public var fractionalBitsUsed: Int { OpusRangeMath.fractionalUsage(range: range, totalBits: totalBits) }

    private var range: UInt32 = 0x8000_0000
    private var value: UInt32 = 0
    private var totalBits = 33
    private var pendingByte: Int = -1
    private var carryBytes = 0
    private var arithmeticBytes: [UInt8] = []
    private var rawBytes: [UInt8]
    private var rawBitCount = 0
    private var isFinalized = false
    private var isFailed = false

    /// Allocates bounded frame storage without starting work or emitting a packet.
    /// - Parameters:
    ///   - frameByteCount: Exact frame length in `0...1_275`. A zero-byte frame permits
    ///     probability-one symbols and zero-bit calls only; decoding uses specified zero extension.
    ///   - maximumOperations: Coding-call limit in `1...1_000_000`, defaulting to 65,536.
    /// - Throws: `invalidFrameByteCount` or `invalidMaximumOperations` before allocation.
    public init(frameByteCount: Int, maximumOperations: Int = 65_536) throws {
        guard (0...1_275).contains(frameByteCount) else { throw OpusRangeCodingError.invalidFrameByteCount }
        guard (1...1_000_000).contains(maximumOperations) else {
            throw OpusRangeCodingError.invalidMaximumOperations
        }
        self.frameByteCount = frameByteCount
        self.maximumOperations = maximumOperations
        rawBytes = Array(repeating: 0, count: frameByteCount)
        arithmeticBytes.reserveCapacity(frameByteCount)
    }

    /// Encodes one possible symbol using the context's exact, unscaled frequency counts.
    /// - Parameters:
    ///   - symbol: Zero-based index with positive frequency in `model`.
    ///   - model: Validated immutable probability context; use the identical context to decode.
    /// - Throws: `invalidSymbol` for an absent/impossible symbol; state, operation and frame
    ///   errors described by this type. Rejected argument validation preserves the stream.
    public mutating func encodeSymbol(_ symbol: Int, model: OpusProbabilityModel) throws {
        guard model.frequencies.indices.contains(symbol), model.frequencies[symbol] > 0 else {
            throw OpusRangeCodingError.invalidSymbol
        }
        try beginOperation()
        try encodeInterval(lower: model.cumulative[symbol], upper: model.cumulative[symbol + 1], total: model.total)
        try checkBudget()
    }

    /// Encodes a Boolean whose true probability is exactly `1 / 2^logProbability`.
    /// - Parameters:
    ///   - bit: Boolean symbol to encode.
    ///   - logProbability: Probability exponent in `1...15`; no context adaptation occurs.
    /// - Throws: `invalidLogProbability`, or state/operation/frame errors. Invalid exponent
    ///   rejection preserves state; a frame-budget failure requires discarding the instance.
    public mutating func encodeBit(_ bit: Bool, logProbability: Int) throws {
        guard (1...15).contains(logProbability) else { throw OpusRangeCodingError.invalidLogProbability }
        try beginOperation()
        let probabilityRange = range >> logProbability
        if bit { value &+= range - probabilityRange }
        range = bit ? probabilityRange : range - probabilityRange
        try normalize()
        try checkBudget()
    }

    /// Encodes one equiprobable unsigned value, splitting totals above 256 into raw low bits.
    /// - Parameters:
    ///   - value: Value smaller than `total`, including its possible zero value.
    ///   - total: Number of possibilities in `2...UInt32.max`; need not be a power of two.
    /// - Throws: `invalidUniformTotal`, `invalidUniformValue`, or state/operation/frame errors.
    ///   This complete split operation consumes one operation, preserving call-bound semantics.
    public mutating func encodeUniform(_ value: UInt32, total: UInt32) throws {
        guard total >= 2 else { throw OpusRangeCodingError.invalidUniformTotal }
        guard value < total else { throw OpusRangeCodingError.invalidUniformValue }
        try beginOperation()
        let lowBits = max(0, OpusRangeMath.integerLog(total - 1) - 8)
        let highTotal = ((total - 1) >> lowBits) + 1
        let highValue = value >> lowBits
        try encodeInterval(lower: highValue, upper: highValue + 1, total: highTotal)
        if lowBits > 0 { try appendRawBits(value & ((1 << lowBits) - 1), count: lowBits) }
        try checkBudget()
    }

    /// Packs low-order raw bits backward from the frame end, least significant bit first.
    /// - Parameters:
    ///   - value: Unsigned value fitting `count` bits; only zero fits a zero-bit field.
    ///   - count: Number of bits in `0...25`, matching ordinary Opus entropy-call bounds.
    /// - Throws: `invalidRawBitCount`, `invalidRawValue`, or state/operation/frame errors.
    ///   Zero-bit calls count toward the operation limit but consume no coding budget.
    public mutating func encodeRawBits(_ value: UInt32, count: Int) throws {
        guard (0...25).contains(count) else { throw OpusRangeCodingError.invalidRawBitCount }
        guard value < (UInt32(1) << count) else { throw OpusRangeCodingError.invalidRawValue }
        try beginOperation()
        if count > 0 {
            try appendRawBits(value, count: count)
            try checkBudget()
        }
    }

    /// Terminates the arithmetic interval and combines raw bits into the exact frame length.
    ///
    /// Uses the RFC 6716 section 5.1.5 shortest valid prefix. Empty space becomes zero;
    /// only proven free low bits of the last arithmetic byte may overlap raw bits.
    /// `bitsUsed`, `fractionalBitsUsed` and `finalRange` remain unchanged. No TOC is added.
    /// - Returns: Owned, zero-indexed frame bytes suitable for a corresponding entropy decoder.
    /// - Throws: `finalized` on repetition; `unusableState` after failure;
    ///   `frameBudgetExceeded` if the final prefix cannot fit. All finalization errors are terminal.
    public mutating func finalize() throws -> Data {
        try checkState()
        isFinalized = true
        var prefixBits = 32 - OpusRangeMath.integerLog(range)
        var mask = UInt32(0x7fff_ffff) >> prefixBits
        var end = (value &+ mask) & ~mask
        if (end | mask) >= value &+ range {
            prefixBits += 1
            mask >>= 1
            end = (value &+ mask) & ~mask
        }
        let requiredPrefixBits = prefixBits
        while prefixBits > 0 {
            try carryOut(Int(end >> 23))
            end = (end << 8) & 0x7fff_ffff
            prefixBits -= 8
        }
        if pendingByte >= 0 || carryBytes > 0 { try carryOut(0) }
        let fullRawBytes = rawBitCount / 8
        let partialRawBits = rawBitCount % 8
        guard arithmeticBytes.count + fullRawBytes <= frameByteCount else {
            isFailed = true
            throw OpusRangeCodingError.frameBudgetExceeded
        }
        if partialRawBits > 0, arithmeticBytes.count + fullRawBytes == frameByteCount {
            let freeBits = (8 - requiredPrefixBits % 8) % 8
            guard partialRawBits <= freeBits else {
                isFailed = true
                throw OpusRangeCodingError.frameBudgetExceeded
            }
        }
        var output = rawBytes
        for index in arithmeticBytes.indices { output[index] |= arithmeticBytes[index] }
        return Data(output)
    }

    /// Rejects finalized/failed instances without mutating diagnostics or allocating storage.
    /// - Throws: `unusableState` after a frame failure, otherwise `finalized` after termination.
    private func checkState() throws {
        guard !isFailed else { throw OpusRangeCodingError.unusableState }
        guard !isFinalized else { throw OpusRangeCodingError.finalized }
    }

    /// Admits one bounded public coding call after its arguments have been validated.
    /// - Throws: State errors or `operationLimitExceeded`; a rejected limit preserves state.
    private mutating func beginOperation() throws {
        try checkState()
        guard operationCount < maximumOperations else { throw OpusRangeCodingError.operationLimitExceeded }
        operationCount += 1
    }

    /// Rejects streams whose conservative accounting exceeds the selected fixed frame budget.
    /// - Throws: `frameBudgetExceeded`, making subsequent coding/finalization unusable.
    private mutating func checkBudget() throws {
        // The specified initial one-bit reserve needs no physical byte for a zero-cost stream.
        guard bitsUsed <= max(1, frameByteCount * 8) else {
            isFailed = true
            throw OpusRangeCodingError.frameBudgetExceeded
        }
    }

    /// Narrows the arithmetic interval using RFC 6716's verified erratum 4853.
    /// - Parameters:
    ///   - lower: Inclusive cumulative frequency, smaller than `upper`.
    ///   - upper: Exclusive cumulative frequency, at most `total`.
    ///   - total: Positive exact frequency total at most 65,535.
    /// - Throws: `frameBudgetExceeded` if normalization cannot retain bounded output.
    private mutating func encodeInterval(lower: UInt32, upper: UInt32, total: UInt32) throws {
        let unit = range / total
        if lower == 0 {
            range -= unit * (total - upper)
        } else {
            value &+= range - unit * (total - lower)
            range = unit * (upper - lower)
        }
        try normalize()
    }

    /// Emits front bytes until the arithmetic range again exceeds `2^23`.
    /// - Throws: `frameBudgetExceeded` when finite arithmetic output storage is exhausted.
    private mutating func normalize() throws {
        while range <= 0x0080_0000 {
            try carryOut(Int(value >> 23))
            value = (value << 8) & 0x7fff_ffff
            range <<= 8
            totalBits += 8
        }
    }

    /// Buffers one nine-bit arithmetic output digit and propagates a resolved carry.
    /// - Parameter digit: Eight data bits plus a possible high carry bit, in `0...511`.
    /// - Throws: `frameBudgetExceeded` if buffered output would exceed frame storage.
    private mutating func carryOut(_ digit: Int) throws {
        if digit == 255 {
            carryBytes += 1
            guard arithmeticBytes.count + carryBytes <= frameByteCount else {
                isFailed = true
                throw OpusRangeCodingError.frameBudgetExceeded
            }
            return
        }
        let carry = digit >> 8
        if pendingByte >= 0 { try appendArithmeticByte(UInt8(pendingByte + carry)) }
        if carryBytes > 0 {
            for _ in 0..<carryBytes { try appendArithmeticByte(carry == 0 ? 255 : 0) }
            carryBytes = 0
        }
        pendingByte = digit & 255
    }

    /// Appends one resolved front byte within the fixed storage cap.
    /// - Parameter byte: Carry-resolved arithmetic output byte.
    /// - Throws: `frameBudgetExceeded`, marking the encoder unusable.
    private mutating func appendArithmeticByte(_ byte: UInt8) throws {
        guard arithmeticBytes.count < frameByteCount else {
            isFailed = true
            throw OpusRangeCodingError.frameBudgetExceeded
        }
        arithmeticBytes.append(byte)
    }

    /// Packs at most 25 raw low bits into the bounded backward byte array.
    /// - Parameters:
    ///   - value: Value already validated to fit `count` bits.
    ///   - count: Positive bit count, at most 25.
    /// - Throws: `frameBudgetExceeded` before any out-of-bounds write; failure is terminal.
    private mutating func appendRawBits(_ value: UInt32, count: Int) throws {
        guard rawBitCount + count <= frameByteCount * 8 else {
            isFailed = true
            throw OpusRangeCodingError.frameBudgetExceeded
        }
        for offset in 0..<count {
            let position = rawBitCount + offset
            let byte = frameByteCount - 1 - position / 8
            rawBytes[byte] |= UInt8((value >> offset) & 1) << (position % 8)
        }
        rawBitCount += count
        totalBits += count
    }
}

/// Owned RFC 6716 section 4.1 entropy decoder for one independently bounded frame.
///
/// Forward entropy reads are zero-extended at this frame's end, and may overlap backward
/// raw reads as the specification requires. `bitsUsed` exposes allocation accounting;
/// the caller's eventual SILK/CELT decoder must enforce its syntax's bit-allocation rules.
/// Raw reads exceeding the actual frame bit count fail, while entropy zero extension is
/// permitted. An operation cap bounds even empty-frame/probability-one decoding. This
/// value creates no I/O/tasks and supplies no PCM, FEC, PLC or complete codec validation.
public struct OpusRangeDecoder: Sendable {
    /// Owned bytes of this entropy frame only, excluding packet headers and other frames.
    public let frame: Data
    /// Maximum admitted public decoding calls.
    public let maximumOperations: Int
    /// Number of admitted calls; a corrupt decoding call is included.
    public private(set) var operationCount = 0
    /// Current normalized range; comparable with the encoder after corresponding symbols.
    public var finalRange: UInt32 { range }
    /// Conservative consumed-bit upper bound, initially one even for an empty frame.
    public var bitsUsed: Int { totalBits - OpusRangeMath.integerLog(range) }
    /// Bit-exact conservative consumed-bit upper bound in eighth-bit units.
    public var fractionalBitsUsed: Int { OpusRangeMath.fractionalUsage(range: range, totalBits: totalBits) }

    private let bytes: [UInt8]
    private var range: UInt32 = 128
    private var value: UInt32 = 0
    private var remainingByte: UInt32 = 0
    private var forwardOffset = 0
    private var rawBitCount = 0
    private var totalBits = 9
    private var isFailed = false

    /// Copies and normalizes exactly one bounded frame, with specified zero extension.
    /// - Parameters:
    ///   - frame: Zero through 1,275 bytes. Sliced Foundation data is densely reindexed.
    ///   - maximumOperations: Call limit in `1...1_000_000`, defaulting to 65,536.
    /// - Throws: `invalidFrameByteCount` or `invalidMaximumOperations` before decoding.
    public init(frame: Data, maximumOperations: Int = 65_536) throws {
        guard frame.count <= 1_275 else { throw OpusRangeCodingError.invalidFrameByteCount }
        guard (1...1_000_000).contains(maximumOperations) else {
            throw OpusRangeCodingError.invalidMaximumOperations
        }
        bytes = Array(frame)
        self.frame = Data(bytes)
        self.maximumOperations = maximumOperations
        remainingByte = readForwardByte()
        value = 127 - (remainingByte >> 1)
        normalize()
    }

    /// Decodes one symbol using the exact matching static frequency context.
    /// - Parameter model: Validated context, retaining impossible-symbol positions and total.
    /// - Returns: Zero-based index of a positive-frequency symbol.
    /// - Throws: `operationLimitExceeded` or `unusableState`. Entropy zero extension alone
    ///   is not a corrupt-frame signal; higher codec syntax must check its bit allocation.
    public mutating func decodeSymbol(model: OpusProbabilityModel) throws -> Int {
        try beginOperation()
        let frequency = cumulativeFrequency(total: model.total)
        var symbol = 0
        while model.cumulative[symbol + 1] <= frequency { symbol += 1 }
        updateInterval(lower: model.cumulative[symbol], upper: model.cumulative[symbol + 1], total: model.total)
        return symbol
    }

    /// Decodes a Boolean whose true probability is exactly `1 / 2^logProbability`.
    /// - Parameter logProbability: Matching exponent in `1...15`.
    /// - Returns: The decoded Boolean, without adapting its probability context.
    /// - Throws: `invalidLogProbability`, `operationLimitExceeded` or `unusableState`.
    public mutating func decodeBit(logProbability: Int) throws -> Bool {
        guard (1...15).contains(logProbability) else { throw OpusRangeCodingError.invalidLogProbability }
        try beginOperation()
        let probabilityRange = range >> logProbability
        let bit = value < probabilityRange
        if !bit { value -= probabilityRange }
        range = bit ? probabilityRange : range - probabilityRange
        normalize()
        return bit
    }

    /// Decodes an equiprobable integer, including the specified raw-bit split for large totals.
    /// - Parameter total: Matching number of possibilities, in `2...UInt32.max`.
    /// - Returns: An unsigned value smaller than `total`.
    /// - Throws: `invalidUniformTotal`, operation/state errors, `frameBudgetExceeded` if raw
    ///   bits exceed actual storage, or `corruptUniformValue` for an unused split codepoint.
    ///   The latter two failures are terminal; concealment belongs to the future codec layer.
    public mutating func decodeUniform(total: UInt32) throws -> UInt32 {
        guard total >= 2 else { throw OpusRangeCodingError.invalidUniformTotal }
        try beginOperation()
        let lowBits = max(0, OpusRangeMath.integerLog(total - 1) - 8)
        let highTotal = ((total - 1) >> lowBits) + 1
        let high = cumulativeFrequency(total: highTotal)
        updateInterval(lower: high, upper: high + 1, total: highTotal)
        let low = lowBits > 0 ? try readRawBits(count: lowBits) : 0
        let result = (high << lowBits) | low
        guard result < total else {
            isFailed = true
            throw OpusRangeCodingError.corruptUniformValue
        }
        return result
    }

    /// Reads backward raw bits, permitting overlap with forward arithmetic read-ahead.
    /// - Parameter count: Number of bits in `0...25`; zero returns zero and counts as a call.
    /// - Returns: Unsigned value assembled least significant bit first from the frame tail.
    /// - Throws: `invalidRawBitCount`, operation/state errors, or `frameBudgetExceeded` if
    ///   aggregate raw-bit requests exceed the frame's actual bits. Storage failure is terminal.
    public mutating func decodeRawBits(count: Int) throws -> UInt32 {
        guard (0...25).contains(count) else { throw OpusRangeCodingError.invalidRawBitCount }
        try beginOperation()
        return try readRawBits(count: count)
    }

    /// Admits one bounded decode call; failed state and exhausted limits preserve the stream.
    /// - Throws: `unusableState` or `operationLimitExceeded` before incrementing the counter.
    private mutating func beginOperation() throws {
        guard !isFailed else { throw OpusRangeCodingError.unusableState }
        guard operationCount < maximumOperations else { throw OpusRangeCodingError.operationLimitExceeded }
        operationCount += 1
    }

    /// Computes a cumulative frequency without changing the arithmetic interval.
    /// - Parameter total: Valid positive context total at most 65,535.
    /// - Returns: A cumulative value in `0..<total`, including the symbol-zero remainder.
    private func cumulativeFrequency(total: UInt32) -> UInt32 {
        total - min(value / (range / total) + 1, total)
    }

    /// Commits a decoded interval and restores the normalized-range invariant.
    /// - Parameters:
    ///   - lower: Inclusive frequency bound selected by `cumulativeFrequency`.
    ///   - upper: Exclusive frequency bound, greater than `lower` and at most `total`.
    ///   - total: Exact context total matching the frequency query.
    private mutating func updateInterval(lower: UInt32, upper: UInt32, total: UInt32) {
        let unit = range / total
        let skipped = unit * (total - upper)
        value -= skipped
        range = lower == 0 ? range - skipped : unit * (upper - lower)
        normalize()
    }

    /// Restores `range > 2^23`, preserving the buffered low bit between input bytes.
    /// Reads beyond the end use zero and never access following frames or packet padding.
    private mutating func normalize() {
        while range <= 0x0080_0000 {
            range <<= 8
            totalBits += 8
            let previous = remainingByte
            remainingByte = readForwardByte()
            let digit = ((previous << 8) | remainingByte) >> 1
            value = ((value << 8) &+ (255 & ~digit)) & 0x7fff_ffff
        }
    }

    /// Reads one dense-indexed forward byte, leaving the bounded offset fixed after exhaustion.
    /// - Returns: The next frame byte or the specified zero-extension byte.
    private mutating func readForwardByte() -> UInt32 {
        guard forwardOffset < bytes.count else { return 0 }
        let result = UInt32(bytes[forwardOffset])
        forwardOffset += 1
        return result
    }

    /// Reads raw bits using an independent backward position, never rejecting legal overlap.
    /// - Parameter count: Validated bit count in `0...25`.
    /// - Returns: Low-order value assembled from actual frame bytes.
    /// - Throws: `frameBudgetExceeded` before out-of-range access; makes the decoder unusable.
    private mutating func readRawBits(count: Int) throws -> UInt32 {
        guard rawBitCount + count <= bytes.count * 8 else {
            isFailed = true
            throw OpusRangeCodingError.frameBudgetExceeded
        }
        var result: UInt32 = 0
        for offset in 0..<count {
            let position = rawBitCount + offset
            let byte = bytes[bytes.count - 1 - position / 8]
            result |= UInt32((byte >> (position % 8)) & 1) << offset
        }
        rawBitCount += count
        totalBits += count
        return result
    }
}
