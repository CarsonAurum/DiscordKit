import DiscordVoiceCrypto
import Foundation

/// Parsed DAVE v1 media frame; parsing validates structure but does not authenticate bytes.
public struct DAVEFrameEnvelope: Sendable, Equatable {
    /// Interleaved media body, retaining clear bytes at their original positions.
    public let interleaved: Data
    /// Eight-byte truncated AES128-GCM authentication tag.
    public let tag: Data
    /// Truncated synchronization nonce; its high byte carries the generation modulo 256.
    public let nonce: UInt32
    /// Ordered, nonoverlapping clear ranges authenticated as concatenated associated data.
    public let clearRanges: [DAVEClearRange]

    /// Parses a bounded footer without consulting codecs or consuming cryptographic state.
    /// - Parameters:
    ///   - frame: Complete encoded transform output, including its footer and marker.
    ///   - maximumFrameBytes: Maximum media-body bytes, in 1...524288; default 524288.
    ///   - maximumClearRanges: Maximum range pairs, in 0...64; default sixty-four.
    /// - Throws: `invalidConfiguration`, `frameTooLarge`, or `malformedFrame` for invalid
    ///   markers, lengths, integer overflow, truncated ULEB128, or invalid clear ranges.
    public init(frame: Data, maximumFrameBytes: Int = 524_288, maximumClearRanges: Int = 64) throws {
        guard (1...524_288).contains(maximumFrameBytes), (0...64).contains(maximumClearRanges) else { throw DAVEError.invalidConfiguration }
        guard frame.count <= maximumFrameBytes + 255 else { throw DAVEError.frameTooLarge }
        let bytes = [UInt8](frame)
        guard bytes.count >= 13, bytes[bytes.count - 2] == 0xFA, bytes[bytes.count - 1] == 0xFA else { throw DAVEError.malformedFrame }
        let size = Int(bytes[bytes.count - 3])
        guard size >= 12, size < bytes.count else { throw DAVEError.malformedFrame }
        let bodyCount = bytes.count - size
        guard bodyCount <= maximumFrameBytes else { throw DAVEError.frameTooLarge }
        let end = bytes.count - 3
        var offset = bodyCount + 8
        let nonceValue = try Self.readULEB(bytes, offset: &offset, end: end, maximum: UInt64(UInt32.max))
        var ranges: [DAVEClearRange] = []
        var previousEnd = 0
        while offset < end {
            guard ranges.count < maximumClearRanges else { throw DAVEError.malformedFrame }
            let start = Int(try Self.readULEB(bytes, offset: &offset, end: end, maximum: UInt64(bodyCount)))
            let length = Int(try Self.readULEB(bytes, offset: &offset, end: end, maximum: UInt64(bodyCount)))
            guard start >= previousEnd, length > 0, length <= bodyCount - start else { throw DAVEError.malformedFrame }
            ranges.append(try DAVEClearRange(offset: start, length: length)); previousEnd = start + length
        }
        interleaved = Data(bytes[..<bodyCount]); tag = Data(bytes[bodyCount..<(bodyCount + 8)])
        nonce = UInt32(nonceValue); clearRanges = ranges
    }

    /// Serializes validated media, tag, nonce and absolute clear-range offset/length pairs.
    /// - Parameters:
    ///   - interleaved: Nonempty encoded body, at most 524288 bytes.
    ///   - tag: Exactly eight authentication-tag bytes.
    ///   - nonce: Synchronization nonce, serialized in unsigned LEB128.
    ///   - clearRanges: At most sixty-four sorted disjoint in-body ranges.
    /// - Returns: Interleaved bytes followed by the complete footer, size byte and `FAFA` marker.
    /// - Throws: `malformedFrame` for invalid sizes/ranges or a footer exceeding 255 bytes,
    ///   or `frameTooLarge` for an oversized body. It performs no encryption.
    public static func encode(interleaved: Data, tag: Data, nonce: UInt32, clearRanges: [DAVEClearRange]) throws -> Data {
        guard !interleaved.isEmpty, tag.count == 8, clearRanges.count <= 64 else { throw DAVEError.malformedFrame }
        guard interleaved.count <= 524_288 else { throw DAVEError.frameTooLarge }
        var previousEnd = 0
        var footer = Data(tag); writeULEB(UInt64(nonce), to: &footer)
        for range in clearRanges {
            guard range.offset >= previousEnd, range.offset <= interleaved.count,
                  range.length <= interleaved.count - range.offset else { throw DAVEError.malformedFrame }
            writeULEB(UInt64(range.offset), to: &footer); writeULEB(UInt64(range.length), to: &footer)
            previousEnd = range.offset + range.length
        }
        guard footer.count + 3 <= 255 else { throw DAVEError.malformedFrame }
        footer.append(UInt8(footer.count + 3)); footer.append(contentsOf: [0xFA, 0xFA])
        return Data(interleaved) + footer
    }

    /// Concatenates ciphertext and clear bytes separately in original body order.
    /// - Returns: Ciphertext without tag and associated data; clear-range metadata is not AAD
    ///   in the upstream v1 protocol. All ranges have already been checked before slicing.
    func split() -> (ciphertext: Data, authenticatedData: Data) {
        Self.split(interleaved, clearRanges: clearRanges)
    }

    /// Splits an already validated media-body/range pair without interpreting codec bytes.
    /// - Parameters:
    ///   - bytes: Nonempty zero-indexed media data.
    ///   - clearRanges: Sorted disjoint valid ranges as supplied by the codec or footer parser.
    /// - Returns: All encrypted segments concatenated and all clear segments concatenated.
    static func split(_ bytes: Data, clearRanges: [DAVEClearRange]) -> (ciphertext: Data, authenticatedData: Data) {
        var encrypted = Data(); var clear = Data(); var cursor = 0
        for range in clearRanges {
            encrypted.append(bytes[cursor..<range.offset]); clear.append(bytes[range.offset..<(range.offset + range.length)])
            cursor = range.offset + range.length
        }
        encrypted.append(bytes[cursor..<bytes.count])
        return (encrypted, clear)
    }

    /// Restores encrypted or decrypted segments to the positions around validated clear ranges.
    /// - Parameters:
    ///   - original: The original normalized media body with its clear bytes intact.
    ///   - transformed: Concatenated replacement bytes for every nonclear position.
    ///   - clearRanges: Validated ranges into `original`.
    /// - Returns: Reinterleaved body with exactly the original byte count.
    static func merge(original: Data, transformed: Data, clearRanges: [DAVEClearRange]) -> Data {
        var result = Data(); var cursor = 0; var transformedOffset = 0
        result.reserveCapacity(original.count)
        for range in clearRanges {
            let count = range.offset - cursor
            result.append(transformed[transformedOffset..<(transformedOffset + count)])
            result.append(original[range.offset..<(range.offset + range.length)])
            cursor = range.offset + range.length; transformedOffset += count
        }
        result.append(transformed[transformedOffset..<transformed.count]); return result
    }

    /// Reads a bounded uint64 ULEB128 value without integer overflow or crossing its footer.
    /// - Parameters:
    ///   - bytes: Zero-indexed complete input bytes.
    ///   - offset: Current read position, advanced on success or failure.
    ///   - end: Exclusive end of the nonce/range field section.
    ///   - maximum: Inclusive value bound, checked before returning.
    /// - Returns: Parsed integer, accepting valid padded ULEB128 encodings up to ten bytes.
    /// - Throws: `malformedFrame` for truncation, overflow, or an out-of-bound value.
    private static func readULEB(_ bytes: [UInt8], offset: inout Int, end: Int, maximum: UInt64) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard offset < end else { throw DAVEError.malformedFrame }
            let byte = bytes[offset]; offset += 1
            if index == 9, byte > 1 { throw DAVEError.malformedFrame }
            value |= UInt64(byte & 0x7F) << (index * 7)
            if byte & 0x80 == 0 {
                guard value <= maximum else { throw DAVEError.malformedFrame }; return value
            }
        }
        throw DAVEError.malformedFrame
    }

    /// Appends the minimal unsigned LEB128 encoding of an integer.
    /// - Parameters:
    ///   - value: Nonnegative integer, including zero.
    ///   - output: Caller-owned output to which one through ten bytes are appended.
    private static func writeULEB(_ value: UInt64, to output: inout Data) {
        var remainder = value
        repeat {
            var byte = UInt8(remainder & 0x7F); remainder >>= 7
            if remainder != 0 { byte |= 0x80 }; output.append(byte)
        } while remainder != 0
    }
}

/// Single sender/epoch nonce and receive-policy owner for DAVE v1 AES128-GCM frames.
///
/// The application must install one owner per key domain and must never recreate a
/// transmit owner from the same exporter. Audio/video and all SSRCs for that sender
/// share this actor's nonce. There are no suspension points inside transformations;
/// concurrent callers serialize, and cancellation before admission consumes no nonce.
/// Construction starts no I/O. This does not provide a live voice session or an audit.
public actor DAVEFrameCipher: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Security and allocation bounds for one sender key domain.
    public struct Configuration: Sendable, Equatable {
        /// Maximum combined ciphertext plus associated data, after codec normalization.
        public let maximumFrameBytes: Int
        /// Maximum actual AES-GCM opens per generation, including successes and failures.
        public let maximumDecryptionsPerGeneration: UInt64
        /// Independent maximum failed tag verifications per generation.
        public let maximumFailedDecryptionsPerGeneration: UInt64
        /// Forward ratchet-work bound; generation wrap is resolved against the oldest live key.
        public let maximumFutureGenerations: Int
        /// Maximum cached keys and accounting states retained behind the newest generation.
        public let maximumRetainedGenerations: Int
        /// Largest accepted distance behind the newest authenticated absolute nonce.
        public let replayWindow: Int
        /// Old-generation retention in seconds, never greater than ten seconds.
        public let generationRetentionSeconds: TimeInterval
        /// Inclusive absolute transmit-counter cap; first emitted nonce is one.
        public let maximumTransmitNonce: UInt64

        /// Creates validated bounds; larger supported video frames use the same conservative cap.
        /// - Parameters:
        ///   - maximumFrameBytes: 1...524288 bytes; default 16384. The universal 2^26
        ///     decryption cap enforces NIST SP800-38D Appendix C Table 2's 2^19-byte row.
        ///   - maximumDecryptionsPerGeneration: 1...2^26 actual AEAD attempts; default 2^26.
        ///   - maximumFailedDecryptionsPerGeneration: 1...min(total,2^17); default 2^17.
        ///   - maximumFutureGenerations: 0...250 generations; default eight.
        ///   - maximumRetainedGenerations: 1...251 generation keys; default sixteen.
        ///   - replayWindow: 1...8192 absolute nonce positions; default 1024.
        ///   - generationRetentionSeconds: Finite seconds in 0...10; default ten.
        ///   - maximumTransmitNonce: 1...2^56-1; default the complete uint32-generation lifetime.
        /// - Throws: `invalidConfiguration` if any independently bounded setting is invalid.
        /// - Note: Applications that duplicate receive owners for one domain must coordinate
        ///   attempt budgets across them; these are per-owner counters, not distributed quotas.
        public init(maximumFrameBytes: Int = 16_384, maximumDecryptionsPerGeneration: UInt64 = 1 << 26,
                    maximumFailedDecryptionsPerGeneration: UInt64 = 1 << 17, maximumFutureGenerations: Int = 8,
                    maximumRetainedGenerations: Int = 16, replayWindow: Int = 1024,
                    generationRetentionSeconds: TimeInterval = 10, maximumTransmitNonce: UInt64 = (1 << 56) - 1) throws {
            guard (1...524_288).contains(maximumFrameBytes), (1...(1 << 26)).contains(maximumDecryptionsPerGeneration),
                  maximumFailedDecryptionsPerGeneration >= 1,
                  maximumFailedDecryptionsPerGeneration <= min(maximumDecryptionsPerGeneration, 1 << 17),
                  (0...250).contains(maximumFutureGenerations), (1...251).contains(maximumRetainedGenerations),
                  (1...8192).contains(replayWindow), generationRetentionSeconds.isFinite,
                  (0...10).contains(generationRetentionSeconds), (1...((1 << 56) - 1)).contains(maximumTransmitNonce) else { throw DAVEError.invalidConfiguration }
            self.maximumFrameBytes = maximumFrameBytes; self.maximumDecryptionsPerGeneration = maximumDecryptionsPerGeneration
            self.maximumFailedDecryptionsPerGeneration = maximumFailedDecryptionsPerGeneration; self.maximumFutureGenerations = maximumFutureGenerations
            self.maximumRetainedGenerations = maximumRetainedGenerations; self.replayWindow = replayWindow
            self.generationRetentionSeconds = generationRetentionSeconds; self.maximumTransmitNonce = maximumTransmitNonce
        }
        /// Fixed validated defaults; initialization cannot fail because each literal is in range.
        public static let standard = try! Configuration()
    }

    private struct VerificationCounts: Sendable { var total: UInt64 = 0; var failed: UInt64 = 0 }
    /// Configuration selected at construction; immutable across the whole key domain.
    public let configuration: Configuration
    private var sendRatchet: DAVEKeyRatchet?
    private var receiveRatchet: DAVEKeyRatchet?
    private var transmitNonce: UInt64 = 0
    private var newestGeneration: UInt32 = 0
    private var oldestGeneration: UInt32 = 0
    private var expiries: [UInt32: TimeInterval] = [:]
    private var verifications: [UInt32: VerificationCounts] = [:]
    private var acceptedNonces: Set<UInt64> = []
    private var newestNonce: UInt64?
    private var lastTime: TimeInterval = 0

    /// Redacted actor diagnostics that never traverse sender or receiver key material.
    public nonisolated var description: String { "DAVEFrameCipher(<redacted>)" }
    /// Redacted debug diagnostics containing no secret or nonce state.
    public nonisolated var debugDescription: String { description }
    /// Redacted reflection excludes actor-isolated cryptographic state from generic dumping.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }

    /// Creates one actor owning a sender's domain; does not perform any cryptographic operation yet.
    /// - Parameters:
    ///   - baseSecret: Exact sixteen-byte sender secret from the authenticated MLS epoch exporter.
    ///   - configuration: Validated allocation, ratchet, lifetime, and verification policies.
    /// - Throws: `invalidSecret`; the actor owns no transport, devices, clocks, or tasks.
    public init(baseSecret: Data, configuration: Configuration = .standard) throws {
        self.configuration = configuration
        sendRatchet = try DAVEKeyRatchet(baseSecret: baseSecret, maximumForwardDistance: 0, maximumRetainedKeys: 1)
        receiveRatchet = try DAVEKeyRatchet(baseSecret: baseSecret, maximumForwardDistance: configuration.maximumFutureGenerations,
                                          maximumRetainedKeys: configuration.maximumRetainedGenerations)
    }

    /// Creates a test-only counter fixture while retaining ordinary key derivation and limits.
    /// - Parameters:
    ///   - baseSecret: Exact sixteen-byte exporter secret.
    ///   - configuration: Validated production configuration.
    ///   - initialTransmitNonce: Last consumed absolute nonce; must not exceed the configured cap.
    /// - Throws: `invalidSecret` or `invalidConfiguration`. Never expose this entry point to consumers.
    init(baseSecret: Data, configuration: Configuration, initialTransmitNonce: UInt64) throws {
        guard initialTransmitNonce <= configuration.maximumTransmitNonce else { throw DAVEError.invalidConfiguration }
        self.configuration = configuration; transmitNonce = initialTransmitNonce
        sendRatchet = try DAVEKeyRatchet(baseSecret: baseSecret, maximumForwardDistance: 250, maximumRetainedKeys: 1)
        receiveRatchet = try DAVEKeyRatchet(baseSecret: baseSecret, maximumForwardDistance: configuration.maximumFutureGenerations,
                                          maximumRetainedKeys: configuration.maximumRetainedGenerations)
    }

    /// Encrypts one codec-normalized frame and consumes a distinct shared sender nonce per attempt.
    /// - Parameters:
    ///   - frame: Nonempty encoded frame; normalization must fit `maximumFrameBytes`.
    ///   - codec: Explicit encoded format, used only on this send path.
    /// - Returns: Complete DAVE frame. H26x may consume up to ten nonces to avoid start codes.
    /// - Throws: Cancellation before admission, `closed`, codec/frame errors, `nonceExhausted`,
    ///   or `codecRetryLimit`. Once encryption starts, a consumed nonce is never rolled back.
    public func seal(_ frame: Data, codec: DAVECodec) throws -> Data {
        try Task.checkCancellation()
        guard sendRatchet != nil else { throw DAVEError.closed }
        let prepared = try DAVECodecTransform.prepare(frame, codec: codec, maximumFrameBytes: configuration.maximumFrameBytes)
        let split = DAVEFrameEnvelope.split(prepared.bytes, clearRanges: prepared.clearRanges)
        for _ in 0..<10 {
            guard transmitNonce < configuration.maximumTransmitNonce else { throw DAVEError.nonceExhausted }
            transmitNonce += 1
            let generation = UInt32(transmitNonce >> 24)
            let nonce = UInt32(truncatingIfNeeded: transmitNonce)
            let key = try sendRatchet!.key(for: generation)
            sendRatchet!.erase(before: generation)
            let sealed = try TruncatedAESGCM.seal(payload: split.ciphertext, key: key, nonce: Self.fullNonce(nonce), authenticatedData: split.authenticatedData)
            let body = DAVEFrameEnvelope.merge(original: prepared.bytes, transformed: Data(sealed.dropLast(8)), clearRanges: prepared.clearRanges)
            let result = try DAVEFrameEnvelope.encode(interleaved: body, tag: Data(sealed.suffix(8)), nonce: nonce, clearRanges: prepared.clearRanges)
            if try !DAVECodecTransform.containsUnexpectedStartCode(in: result, clearRanges: prepared.clearRanges, codec: codec) { return result }
        }
        throw DAVEError.codecRetryLimit
    }

    /// Authenticates a codec-agnostic frame before publishing plaintext or advancing replay state.
    /// - Parameters:
    ///   - frame: Complete DAVE frame, or the exact explicit exceptional silence packet.
    ///   - mediaType: Audio or video context supplied by the authenticated stream owner.
    ///   - allowOpusSilence: Default false; only explicit audio context permits `F8 FF FE` plaintext.
    ///   - now: Finite nonnegative monotonic seconds from an injected clock; backward time is rejected.
    /// - Returns: Authenticated normalized encoded frame, or explicitly permitted synthetic silence.
    /// - Throws: Cancellation before admission, `closed`, structural/time/budget/ratchet errors,
    ///   `authenticationFailed`, or `replayedFrame`. Failed authentication consumes verification
    ///   quota but never changes the accepted nonce window or canonical ratchet generation.
    public func open(_ frame: Data, mediaType: DAVEMediaType, allowOpusSilence: Bool = false, now: TimeInterval) throws -> Data {
        try Task.checkCancellation()
        guard receiveRatchet != nil else { throw DAVEError.closed }
        guard now.isFinite, now >= lastTime, now >= 0 else { throw DAVEError.invalidConfiguration }
        lastTime = now; expire(at: now)
        if mediaType == .audio, allowOpusSilence, frame == Data([0xF8, 0xFF, 0xFE]) { return Data(frame) }
        let envelope = try DAVEFrameEnvelope(frame: frame, maximumFrameBytes: configuration.maximumFrameBytes)
        let generation = try Self.unwrapGeneration(UInt32(envelope.nonce >> 24), oldest: oldestGeneration)
        guard generation >= oldestGeneration else { throw DAVEError.generationExpired }
        guard UInt64(generation) <= UInt64(newestGeneration) + UInt64(configuration.maximumFutureGenerations) else { throw DAVEError.generationTooFarAhead }
        let bigNonce = UInt64(generation) << 24 | UInt64(envelope.nonce & 0xFF_FFFF)
        if let newestNonce, bigNonce <= newestNonce {
            guard newestNonce - bigNonce < UInt64(configuration.replayWindow), !acceptedNonces.contains(bigNonce) else { throw DAVEError.replayedFrame }
        }
        var counts = verifications[generation] ?? VerificationCounts()
        guard counts.total < configuration.maximumDecryptionsPerGeneration,
              counts.failed < configuration.maximumFailedDecryptionsPerGeneration else { throw DAVEError.verificationLimit }
        var candidate = receiveRatchet!
        let key = try candidate.key(for: generation)
        let split = envelope.split()
        counts.total += 1; verifications[generation] = counts
        let plaintext: Data
        do {
            plaintext = try TruncatedAESGCM.open(sealedPayload: split.ciphertext + envelope.tag, key: key,
                                               nonce: Self.fullNonce(envelope.nonce), authenticatedData: split.authenticatedData)
        } catch {
            counts.failed += 1; verifications[generation] = counts; throw DAVEError.authenticationFailed
        }
        receiveRatchet = candidate
        if generation > newestGeneration {
            let floor = generation >= UInt32(configuration.maximumRetainedGenerations - 1) ? generation - UInt32(configuration.maximumRetainedGenerations - 1) : 0
            oldestGeneration = max(oldestGeneration, floor)
            for prior in oldestGeneration..<generation { expiries[prior] = min(expiries[prior] ?? .infinity, now + configuration.generationRetentionSeconds) }
            newestGeneration = generation; prune()
        }
        acceptedNonces.insert(bigNonce); newestNonce = max(newestNonce ?? bigNonce, bigNonce)
        if let newestNonce { acceptedNonces = acceptedNonces.filter { newestNonce - $0 < UInt64(configuration.replayWindow) } }
        return DAVEFrameEnvelope.merge(original: envelope.interleaved, transformed: plaintext, clearRanges: envelope.clearRanges)
    }

    /// Permanently releases logical keys, verification counters, and replay state; idempotent.
    /// No physical erasure of existing Swift `Data` copies is promised. Already executing
    /// transforms finish before this serialized call; later transformations fail `closed`.
    public func close() {
        sendRatchet = nil; receiveRatchet = nil; expiries.removeAll(); verifications.removeAll(); acceptedNonces.removeAll(); newestNonce = nil
    }

    /// Reconstructs a full GCM nonce with eight zero bytes followed by the little-endian uint32.
    /// - Parameter nonce: Truncated synchronization nonce from the frame footer.
    /// - Returns: Exactly twelve bytes; the endianness matches libdave's supported wire behavior.
    static func fullNonce(_ nonce: UInt32) -> Data {
        Data(repeating: 0, count: 8) + Data([UInt8(truncatingIfNeeded: nonce), UInt8(truncatingIfNeeded: nonce >> 8), UInt8(truncatingIfNeeded: nonce >> 16), UInt8(truncatingIfNeeded: nonce >> 24)])
    }

    /// Resolves the nonce generation modulo 256 against the oldest generation still available.
    /// - Parameters:
    ///   - truncated: High nonce byte, in 0...255.
    ///   - oldest: Earliest usable absolute generation.
    /// - Returns: The smallest matching absolute generation no older than `oldest`.
    /// - Throws: `nonceExhausted` if the uint32 generation space would overflow.
    static func unwrapGeneration(_ truncated: UInt32, oldest: UInt32) throws -> UInt32 {
        let value = UInt64(oldest / 256) * 256 + UInt64(truncated) + (truncated < oldest % 256 ? 256 : 0)
        guard value <= UInt64(UInt32.max) else { throw DAVEError.nonceExhausted }; return UInt32(value)
    }

    /// Advances the oldest-key floor when immutable ten-second generation deadlines expire.
    /// - Parameter now: Validated monotonic seconds; equality expires a key without extending it.
    private func expire(at now: TimeInterval) {
        if let lastExpired = expiries.filter({ $0.value <= now }).keys.max() {
            oldestGeneration = max(oldestGeneration, lastExpired + 1); prune()
        }
    }

    /// Removes expired or capacity-evicted keys and all matching accounting metadata.
    /// Future verification budgets remain retained within the configured forward gap, so
    /// retrying an unauthenticated future generation never resets its failure allowance.
    private func prune() {
        receiveRatchet?.erase(before: oldestGeneration)
        expiries = expiries.filter { $0.key >= oldestGeneration }
        verifications = verifications.filter { $0.key >= oldestGeneration }
        acceptedNonces = acceptedNonces.filter { $0 >> 24 >= UInt64(oldestGeneration) }
    }
}
