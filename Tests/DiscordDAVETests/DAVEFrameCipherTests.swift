import Crypto
import DiscordVoiceCrypto
import Foundation
import Testing
@testable import DiscordDAVE

/// Offline media protection, structural admission, replay, quota, clock and lifetime regressions.
@Suite struct DAVEFrameCipherTests {
    private let secret = Data(0..<16)

    /// Confirms first nonce one, little-endian full nonce, tag truncation and exact footer bytes.
    /// The public AES-GCM baseline independently verifies concatenated plaintext/AAD framing.
    @Test func exactWireAndClearRangeAuthentication() async throws {
        let cipher = try DAVEFrameCipher(baseSecret: secret)
        let opus = Data([0xF8, 0xAA, 0x55])
        let encoded = try await cipher.seal(opus, codec: .opus)
        let envelope = try DAVEFrameEnvelope(frame: encoded)
        #expect(envelope.nonce == 1)
        #expect(envelope.clearRanges.isEmpty)
        #expect(encoded.suffix(4) == Data([1, 12, 0xFA, 0xFA]))
        let key = Data([0x58, 0xFC, 0x01, 0x31, 0x08, 0xDB, 0xF9, 0x96, 0xEF, 0x65, 0x1E, 0x3F, 0x01, 0x65, 0x8B, 0xFB])
        let baseline = try AES.GCM.seal(opus, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: Data(count: 8) + Data([1, 0, 0, 0])))
        #expect(envelope.interleaved == baseline.ciphertext)
        #expect(envelope.tag == baseline.tag.prefix(8))
        // Independent Node 24.13.0/OpenSSL 3.5.4 fixture, generated with createCipheriv
        // (aes-128-gcm), the fixed key/nonce above, and no associated data.
        #expect(encoded.map { String(format: "%02x", $0) }.joined() == "23745657949800aa9185f2010cfafa")
        #expect(try await cipher.open(encoded, mediaType: .audio, now: 0) == opus)
        let vp8 = Data([1, 3, 4, 5])
        let encodedVideo = try await cipher.seal(vp8, codec: .vp8)
        let videoEnvelope = try DAVEFrameEnvelope(frame: encodedVideo)
        #expect(videoEnvelope.nonce == 2)
        #expect(videoEnvelope.clearRanges == [try DAVEClearRange(offset: 0, length: 1)])
        #expect(videoEnvelope.interleaved.first == 1)
        let videoBaseline = try AES.GCM.seal(vp8.dropFirst(), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: DAVEFrameCipher.fullNonce(2)), authenticating: Data([1]))
        #expect(videoEnvelope.interleaved.dropFirst() == videoBaseline.ciphertext)
        #expect(videoEnvelope.tag == videoBaseline.tag.prefix(8))
        #expect(try await cipher.open(encodedVideo, mediaType: .video, now: 1) == vp8)
        #expect(String(describing: cipher) == "DAVEFrameCipher(<redacted>)")
        #expect(cipher.description == cipher.debugDescription)
        #expect(Mirror(reflecting: cipher).children.count == 1)
    }

    /// Covers discontiguous clear ranges, metadata-only frames, padded ULEB128 and Data slices.
    @Test func footerRoundTripsAndReinterleaving() throws {
        let ranges = [try DAVEClearRange(offset: 1, length: 2), try DAVEClearRange(offset: 5, length: 1)]
        let body = Data([0, 1, 2, 3, 4, 5, 6])
        let wire = try DAVEFrameEnvelope.encode(interleaved: body, tag: Data(count: 8), nonce: .max, clearRanges: ranges)
        let parsed = try DAVEFrameEnvelope(frame: (Data([8, 9]) + wire).dropFirst(2))
        #expect(parsed.interleaved == body)
        #expect(parsed.nonce == .max)
        #expect(parsed.clearRanges == ranges)
        let parts = parsed.split()
        #expect(parts.ciphertext == Data([0, 3, 4, 6]))
        #expect(parts.authenticatedData == Data([1, 2, 5]))
        #expect(DAVEFrameEnvelope.merge(original: body, transformed: parts.ciphertext, clearRanges: ranges) == body)
        let full = try DAVEFrameEnvelope(frame: DAVEFrameEnvelope.encode(interleaved: body, tag: Data(count: 8), nonce: 0, clearRanges: [try DAVEClearRange(offset: 0, length: body.count)]))
        #expect(full.split().ciphertext.isEmpty)
        #expect(full.split().authenticatedData == body)
        #expect(DAVEFrameEnvelope.merge(original: body, transformed: Data(), clearRanges: full.clearRanges) == body)
        var padded = try DAVEFrameEnvelope.encode(interleaved: Data([42]), tag: Data(count: 8), nonce: 0, clearRanges: [])
        padded[9] = 0x80; padded.insert(0, at: 10); padded[padded.count - 3] += 1
        #expect(try DAVEFrameEnvelope(frame: padded).nonce == 0)
    }

    /// Rejects footer truncation, corrupt markers/sizes, invalid range pairs and integer overflows.
    @Test func malformedFooterAndConfiguration() throws {
        let valid = try DAVEFrameEnvelope.encode(interleaved: Data([42]), tag: Data(count: 8), nonce: 1, clearRanges: [])
        for count in 0..<valid.count {
            #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope(frame: valid.prefix(count)) }
        }
        for position in [valid.count - 1, valid.count - 2, valid.count - 3] {
            var damaged = valid; damaged[position] = 0
            #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope(frame: damaged) }
        }
        var tooBig = valid; tooBig[tooBig.count - 3] = 255
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope(frame: tooBig) }
        for malformedFields: [UInt8] in [[0x80], [0xFF, 0xFF, 0xFF, 0xFF, 0x10], [1, 0], [1, 0, 0], [1, 1, 1], [1, 0, 2], [1, 0, 1, 0, 1], Array(repeating: 0x80, count: 10)] {
            let wire = Data([42]) + Data(count: 8) + Data(malformedFields) + Data([UInt8(11 + malformedFields.count), 0xFA, 0xFA])
            #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope(frame: wire) }
        }
        #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameEnvelope(frame: valid, maximumFrameBytes: 0) }
        #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameEnvelope(frame: valid, maximumClearRanges: 65) }
        #expect(throws: DAVEError.frameTooLarge) { try DAVEFrameEnvelope(frame: Data(count: 257), maximumFrameBytes: 1) }
        let ranged = try DAVEFrameEnvelope.encode(interleaved: Data([42]), tag: Data(count: 8), nonce: 1, clearRanges: [try DAVEClearRange(offset: 0, length: 1)])
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope(frame: ranged, maximumClearRanges: 0) }
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope.encode(interleaved: Data(), tag: Data(count: 8), nonce: 0, clearRanges: []) }
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope.encode(interleaved: Data([0]), tag: Data(count: 7), nonce: 0, clearRanges: []) }
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope.encode(interleaved: Data([0]), tag: Data(count: 8), nonce: 0, clearRanges: [try DAVEClearRange(offset: 0, length: 2)]) }
        #expect(throws: DAVEError.frameTooLarge) { try DAVEFrameEnvelope.encode(interleaved: Data(count: 524_289), tag: Data(count: 8), nonce: 0, clearRanges: []) }
        let bodyTooLarge = try DAVEFrameEnvelope.encode(interleaved: Data([1, 2]), tag: Data(count: 8), nonce: 1, clearRanges: [])
        #expect(throws: DAVEError.frameTooLarge) { try DAVEFrameEnvelope(frame: bodyTooLarge, maximumFrameBytes: 1) }
        let excessiveRanges = try (0..<65).map { try DAVEClearRange(offset: $0 * 2, length: 1) }
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope.encode(interleaved: Data(count: 130), tag: Data(count: 8), nonce: 0, clearRanges: excessiveRanges) }
        let oversizedFooter = try (0..<64).map { try DAVEClearRange(offset: $0 * 5000, length: 1) }
        #expect(throws: DAVEError.malformedFrame) { try DAVEFrameEnvelope.encode(interleaved: Data(count: 320_000), tag: Data(count: 8), nonce: 0, clearRanges: oversizedFooter) }
    }

    /// Tampering with encrypted bytes, clear bytes, tag or nonce never commits replay state.
    /// Invalid high counters and generations cannot advance or erase authenticated receive keys.
    @Test func tamperDoesNotCommitState() async throws {
        let sender = try DAVEFrameCipher(baseSecret: secret)
        let receiver = try DAVEFrameCipher(baseSecret: secret)
        let frame = Data([1, 8, 7, 6])
        let valid = try await sender.seal(frame, codec: .vp8)
        let parsed = try DAVEFrameEnvelope(frame: valid)
        for index in 0..<(parsed.interleaved.count + 8) {
            var changed = valid; changed[index] ^= 0x40
            await #expect(throws: DAVEError.authenticationFailed) { try await receiver.open(changed, mediaType: .video, now: 0) }
        }
        for nonce: UInt32 in [4096, 1 << 24, 8 << 24] {
            let changed = try DAVEFrameEnvelope.encode(interleaved: parsed.interleaved, tag: parsed.tag, nonce: nonce, clearRanges: parsed.clearRanges)
            await #expect(throws: DAVEError.authenticationFailed) { try await receiver.open(changed, mediaType: .video, now: 0) }
        }
        let tooFar = try DAVEFrameEnvelope.encode(interleaved: parsed.interleaved, tag: parsed.tag, nonce: 9 << 24, clearRanges: parsed.clearRanges)
        await #expect(throws: DAVEError.generationTooFarAhead) { try await receiver.open(tooFar, mediaType: .video, now: 0) }
        #expect(try await receiver.open(valid, mediaType: .video, now: 0) == frame)
        await #expect(throws: DAVEError.replayedFrame) { try await receiver.open(valid, mediaType: .video, now: 0) }
    }

    /// Covers exact replay-window edges, successful out-of-order admission and duplicate rejection.
    @Test func boundedReplayWindow() async throws {
        let sender = try DAVEFrameCipher(baseSecret: secret)
        let receiver = try DAVEFrameCipher(baseSecret: secret, configuration: .init(replayWindow: 4))
        var frames: [Data] = []
        for _ in 0..<10 { frames.append(try await sender.seal(Data([42]), codec: .opus)) }
        #expect(try await receiver.open(frames[4], mediaType: .audio, now: 0) == Data([42]))
        #expect(try await receiver.open(frames[1], mediaType: .audio, now: 0) == Data([42]))
        await #expect(throws: DAVEError.replayedFrame) { try await receiver.open(frames[0], mediaType: .audio, now: 0) }
        await #expect(throws: DAVEError.replayedFrame) { try await receiver.open(frames[1], mediaType: .audio, now: 0) }
        #expect(try await receiver.open(frames[9], mediaType: .audio, now: 0) == Data([42]))
        await #expect(throws: DAVEError.replayedFrame) { try await receiver.open(frames[4], mediaType: .audio, now: 0) }
    }

    /// Exercises key rotation at 2^24 frames and exact ten-second erasure without live timing.
    @Test func generationRotationAndExpiry() async throws {
        let sender = try DAVEFrameCipher(baseSecret: secret, configuration: .standard, initialTransmitNonce: 0xFF_FFFE)
        let receiver = try DAVEFrameCipher(baseSecret: secret)
        let oldFrame = try await sender.seal(Data([1]), codec: .opus)
        let newFrame = try await sender.seal(Data([2]), codec: .opus)
        #expect(try DAVEFrameEnvelope(frame: oldFrame).nonce == 0xFF_FFFF)
        #expect(try DAVEFrameEnvelope(frame: newFrame).nonce == 0x100_0000)
        #expect(try await receiver.open(newFrame, mediaType: .audio, now: 1) == Data([2]))
        // The replay window intentionally excludes ancient frame positions; retention still
        // permits the immediately preceding nonce at the generation boundary.
        #expect(try await receiver.open(oldFrame, mediaType: .audio, now: 10.999) == Data([1]))
        let expiredReceiver = try DAVEFrameCipher(baseSecret: secret)
        #expect(try await expiredReceiver.open(newFrame, mediaType: .audio, now: 1) == Data([2]))
        await #expect(throws: DAVEError.generationTooFarAhead) { try await expiredReceiver.open(oldFrame, mediaType: .audio, now: 11) }
        #expect(try DAVEFrameCipher.unwrapGeneration(0, oldest: 255) == 256)
        #expect(try DAVEFrameCipher.unwrapGeneration(255, oldest: 255) == 255)
        #expect(try DAVEFrameCipher.unwrapGeneration(1, oldest: 256) == 257)
        #expect(throws: DAVEError.nonceExhausted) { try DAVEFrameCipher.unwrapGeneration(0, oldest: .max) }
        #expect(DAVEFrameCipher.fullNonce(0x0123_4567) == Data(count: 8) + Data([0x67, 0x45, 0x23, 1]))
    }

    /// Per-generation failure and total AEAD quotas persist after bad frames and future-key failures.
    @Test func verificationLimits() async throws {
        let sender = try DAVEFrameCipher(baseSecret: secret)
        let valid = try await sender.seal(Data([42]), codec: .opus)
        var bad = valid; bad[0] ^= 1
        let failed = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumDecryptionsPerGeneration: 4, maximumFailedDecryptionsPerGeneration: 2))
        for _ in 0..<2 { await #expect(throws: DAVEError.authenticationFailed) { try await failed.open(bad, mediaType: .audio, now: 0) } }
        await #expect(throws: DAVEError.verificationLimit) { try await failed.open(valid, mediaType: .audio, now: 0) }
        let total = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumDecryptionsPerGeneration: 2, maximumFailedDecryptionsPerGeneration: 2))
        await #expect(throws: DAVEError.authenticationFailed) { try await total.open(bad, mediaType: .audio, now: 0) }
        #expect(try await total.open(valid, mediaType: .audio, now: 0) == Data([42]))
        let next = try await sender.seal(Data([7]), codec: .opus)
        await #expect(throws: DAVEError.verificationLimit) { try await total.open(next, mediaType: .audio, now: 0) }
        let futureReceiver = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumDecryptionsPerGeneration: 1, maximumFailedDecryptionsPerGeneration: 1))
        let envelope = try DAVEFrameEnvelope(frame: valid)
        let future = try DAVEFrameEnvelope.encode(interleaved: envelope.interleaved, tag: envelope.tag, nonce: 1 << 24, clearRanges: [])
        await #expect(throws: DAVEError.authenticationFailed) { try await futureReceiver.open(future, mediaType: .audio, now: 0) }
        await #expect(throws: DAVEError.verificationLimit) { try await futureReceiver.open(future, mediaType: .audio, now: 0) }
        #expect(try await futureReceiver.open(valid, mediaType: .audio, now: 0) == Data([42]))
    }

    /// Requires explicit audio context for exceptional silence; rejects invalid clocks and closed owners.
    @Test func silenceClocksBoundsAndClose() async throws {
        let silence = Data([0xF8, 0xFF, 0xFE])
        let cipher = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumFrameBytes: 3, maximumTransmitNonce: 1))
        await #expect(throws: DAVEError.malformedFrame) { try await cipher.open(silence, mediaType: .audio, now: 1) }
        await #expect(throws: DAVEError.malformedFrame) { try await cipher.open(silence, mediaType: .video, allowOpusSilence: true, now: 1) }
        #expect(try await cipher.open(silence, mediaType: .audio, allowOpusSilence: true, now: 1) == silence)
        for now in [-1.0, .infinity, .nan, 0] {
            await #expect(throws: DAVEError.invalidConfiguration) { try await cipher.open(silence, mediaType: .audio, allowOpusSilence: true, now: now) }
        }
        await #expect(throws: DAVEError.frameTooLarge) { try await cipher.seal(Data(count: 4), codec: .opus) }
        await #expect(throws: DAVEError.malformedFrame) { try await cipher.seal(Data(), codec: .opus) }
        let encoded = try await cipher.seal(Data([1, 2, 3]), codec: .opus)
        #expect(try DAVEFrameEnvelope(frame: encoded).nonce == 1)
        await #expect(throws: DAVEError.nonceExhausted) { try await cipher.seal(Data([42]), codec: .opus) }
        await cipher.close(); await cipher.close()
        await #expect(throws: DAVEError.closed) { try await cipher.seal(Data([42]), codec: .opus) }
        await #expect(throws: DAVEError.closed) { try await cipher.open(encoded, mediaType: .audio, now: 1) }
    }

    /// Structural rejection consumes no AEAD budget; codec normalization and body bounds
    /// apply equally on receiving, including a permitted metadata-only authenticated body.
    @Test func receiveBoundsAndMetadataOnlyFrames() async throws {
        let sender = try DAVEFrameCipher(baseSecret: secret)
        let receiver = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumFrameBytes: 3, maximumDecryptionsPerGeneration: 1, maximumFailedDecryptionsPerGeneration: 1))
        let large = try await sender.seal(Data([1, 2, 3, 4]), codec: .opus)
        await #expect(throws: DAVEError.frameTooLarge) { try await receiver.open(large, mediaType: .audio, now: 0) }
        await #expect(throws: DAVEError.malformedFrame) { try await receiver.open(Data(), mediaType: .audio, now: 0) }
        let valid = try await sender.seal(Data([1, 2, 3]), codec: .opus)
        #expect(try await receiver.open(valid, mediaType: .audio, now: 0) == Data([1, 2, 3]))
        let metadataSender = try DAVEFrameCipher(baseSecret: secret)
        let metadataReceiver = try DAVEFrameCipher(baseSecret: secret)
        let metadata = Data([1]) // One-byte VP8 inter-frame prefix, no coded payload.
        let sealed = try await metadataSender.seal(metadata, codec: .vp8)
        let envelope = try DAVEFrameEnvelope(frame: sealed)
        #expect(envelope.split().ciphertext.isEmpty)
        #expect(try await metadataReceiver.open(sealed, mediaType: .video, now: 0) == metadata)
    }

    /// Validates every security bound including zero and overflow values without runtime traps.
    @Test func invalidSecurityConfiguration() {
        for value in [0, -1, 524_289, Int.max] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumFrameBytes: value) } }
        for value: UInt64 in [0, (1 << 26) + 1, .max] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumDecryptionsPerGeneration: value) } }
        for value: UInt64 in [0, (1 << 17) + 1, .max] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumFailedDecryptionsPerGeneration: value) } }
        #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumDecryptionsPerGeneration: 1, maximumFailedDecryptionsPerGeneration: 2) }
        for value in [-1, 251] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumFutureGenerations: value) } }
        for value in [0, 252] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumRetainedGenerations: value) } }
        for value in [0, 8193] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(replayWindow: value) } }
        for value: Double in [-1, 10.001, .nan, .infinity] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(generationRetentionSeconds: value) } }
        for value: UInt64 in [0, 1 << 56, .max] { #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher.Configuration(maximumTransmitNonce: value) } }
        #expect(throws: DAVEError.invalidSecret) { try DAVEFrameCipher(baseSecret: Data(count: 15)) }
        #expect(throws: DAVEError.invalidConfiguration) { try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumTransmitNonce: 1), initialTransmitNonce: 2) }
    }

    /// Concurrent audio/video callers share one counter; cancelled queued operations consume no state.
    @Test func concurrentNoncesAndCancellation() async throws {
        let cipher = try DAVEFrameCipher(baseSecret: secret)
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await cipher.seal(Data([42]), codec: .opus) }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let nonces = try await withThrowingTaskGroup(of: UInt32.self, returning: Set<UInt32>.self) { group in
            for _ in 0..<257 {
                group.addTask { try DAVEFrameEnvelope(frame: await cipher.seal(Data([42]), codec: .opus)).nonce }
            }
            var values: Set<UInt32> = []
            for try await nonce in group { values.insert(nonce) }; return values
        }
        #expect(nonces == Set(UInt32(1)...257))
        let encoded = try await cipher.seal(Data([1]), codec: .opus)
        let receiver = try DAVEFrameCipher(baseSecret: secret)
        let cancelledOpen = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await receiver.open(encoded, mediaType: .audio, now: 0) }
        await #expect(throws: CancellationError.self) { try await cancelledOpen.value }
        #expect(try await receiver.open(encoded, mediaType: .audio, now: 0) == Data([1]))
    }

    /// Constructs real H265 VCL data whose encrypted payload contains a start code for
    /// each of the first ten nonces. This proves retry exhaustion consumes every nonce
    /// without injecting or replacing the production cryptographic or validation path.
    @Test func h265TenAttemptLimitAndNonceConsumption() async throws {
        let key = Data([0x58, 0xFC, 0x01, 0x31, 0x08, 0xDB, 0xF9, 0x96, 0xEF, 0x65, 0x1E, 0x3F, 0x01, 0x65, 0x8B, 0xFB])
        var payload = Data(repeating: 0x88, count: 128)
        for nonce: UInt32 in 1...10 {
            let keystream = [UInt8](try AES.GCM.seal(Data(count: 128), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: DAVEFrameCipher.fullNonce(nonce))).ciphertext)
            let offset = Int(nonce - 1) * 10
            payload[offset] = keystream[offset]
            payload[offset + 1] = keystream[offset + 1]
            payload[offset + 2] = keystream[offset + 2] ^ 1
        }
        let frame = Data([0, 0, 0, 1, 2, 1]) + payload
        let normalized = try DAVECodecTransform.prepare(frame, codec: .h265)
        #expect(normalized.bytes == frame)
        #expect(normalized.clearRanges == [try DAVEClearRange(offset: 0, length: 6)])
        let cipher = try DAVEFrameCipher(baseSecret: secret, configuration: .init(maximumTransmitNonce: 10))
        await #expect(throws: DAVEError.codecRetryLimit) { try await cipher.seal(frame, codec: .h265) }
        await #expect(throws: DAVEError.nonceExhausted) { try await cipher.seal(Data([42]), codec: .opus) }
        // One forced collision consumes nonce one, then an ordinary H265 payload can succeed.
        let singleCollision = Data([0, 0, 0, 1, 2, 1]) + payload.prefix(3)
        let retrying = try DAVEFrameCipher(baseSecret: secret)
        let sealed = try await retrying.seal(singleCollision, codec: .h265)
        #expect(try DAVEFrameEnvelope(frame: sealed).nonce >= 2)
        let receiver = try DAVEFrameCipher(baseSecret: secret)
        #expect(try await receiver.open(sealed, mediaType: .video, now: 0) == singleCollision)
    }
}
