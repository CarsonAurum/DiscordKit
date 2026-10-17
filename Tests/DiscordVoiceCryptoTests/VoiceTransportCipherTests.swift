import Crypto
import Foundation
import Testing
@testable import DiscordVoiceCrypto

/// Offline transport tests exercise authenticated state transitions under both current modes.
@Suite struct VoiceTransportCipherTests {
    private let key = Data(repeating: 0x55, count: 32)
    private let header = Data([0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7])

    /// Verifies wire overhead, zero-based counters, full-header authentication and empty frames.
    /// AES256 is additionally checked against an independently assembled public GCM box.
    /// - Parameter mode: Each currently supported wire encryption mode.
    @Test(arguments: VoiceEncryptionMode.allCases)
    func transportWireAndRoundTrip(mode: VoiceEncryptionMode) async throws {
        let sender = try VoiceTransportCipher(mode: mode, key: key)
        let receiver = try VoiceTransportCipher(mode: mode, key: key, maximumReceiveStreams: 1)
        #expect(sender.mode == mode)
        let plaintext = Data([1, 2, 3, 4])
        let sealed = try await sender.seal(payload: plaintext, authenticatedHeader: header)
        #expect(sealed.startIndex == 0)
        #expect(sealed.count == plaintext.count + 20)
        #expect(sealed.suffix(4) == Data([0, 0, 0, 0]))
        if mode == .aeadAES256GCMRTPSize {
            let baseline = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: Data(count: 12)), authenticating: header)
            #expect(sealed == baseline.ciphertext + baseline.tag + Data(count: 4))
        }
        #expect(try await receiver.open(sealedPayload: sealed, authenticatedHeader: header) == plaintext)
        let slicedReceiver = try VoiceTransportCipher(mode: mode, key: key)
        let backedPayload = Data([1, 2]) + sealed
        let backedHeader = Data([1, 2]) + header
        #expect(try await slicedReceiver.open(sealedPayload: backedPayload.dropFirst(2), authenticatedHeader: backedHeader.dropFirst(2)) == plaintext)
        let empty = try await sender.seal(payload: Data(), authenticatedHeader: header)
        #expect(empty.suffix(4) == Data([0, 0, 0, 1]))
        #expect(try await receiver.open(sealedPayload: empty, authenticatedHeader: header).isEmpty)
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await receiver.open(sealedPayload: sealed, authenticatedHeader: header) }
        #expect(mode.rawValue.hasSuffix("_rtpsize"))
        #expect(VoiceEncryptionMode(rawValue: "xsalsa20_poly1305") == nil)
    }

    /// Covers tampered ciphertext, tag, nonce and header, proving failed auth does not consume a nonce.
    /// Forged high counters cannot advance the receive window or exclude a subsequent valid packet.
    /// - Parameter mode: Each currently supported wire encryption mode.
    @Test(arguments: VoiceEncryptionMode.allCases)
    func transportTamperDoesNotCommitReplay(mode: VoiceEncryptionMode) async throws {
        let sender = try VoiceTransportCipher(mode: mode, key: key)
        let receiver = try VoiceTransportCipher(mode: mode, key: key, maximumReceiveStreams: 1)
        let sealed = try await sender.seal(payload: Data([1, 2, 3]), authenticatedHeader: header)
        let wrongKey = try VoiceTransportCipher(mode: mode, key: Data(count: 32))
        await #expect(throws: VoiceCryptoError.authenticationFailed) { try await wrongKey.open(sealedPayload: sealed, authenticatedHeader: header) }
        for index in sealed.indices {
            var changed = sealed
            changed[index] ^= 0x40
            await #expect(throws: VoiceCryptoError.authenticationFailed) { try await receiver.open(sealedPayload: changed, authenticatedHeader: header) }
        }
        for index in header.indices {
            var changed = header
            changed[index] ^= 1
            await #expect(throws: VoiceCryptoError.authenticationFailed) { try await receiver.open(sealedPayload: sealed, authenticatedHeader: changed) }
        }
        #expect(try await receiver.open(sealedPayload: sealed, authenticatedHeader: header) == Data([1, 2, 3]))
    }

    /// Exercises both replay bitmap branches and the exact 63/64 displacement boundary.
    /// A jump beyond the bitmap drops old entries, while independent SSRC state stays bounded.
    /// - Parameter mode: Each currently supported wire encryption mode.
    @Test(arguments: VoiceEncryptionMode.allCases)
    func replayOrderingAndStreamCapacity(mode: VoiceEncryptionMode) async throws {
        let sender = try VoiceTransportCipher(mode: mode, key: key)
        let receiver = try VoiceTransportCipher(mode: mode, key: key, maximumReceiveStreams: 1)
        var packets: [Data] = []
        for _ in 0..<130 { packets.append(try await sender.seal(payload: Data([42]), authenticatedHeader: header)) }
        #expect(try await receiver.open(sealedPayload: packets[64], authenticatedHeader: header) == Data([42]))
        #expect(try await receiver.open(sealedPayload: packets[1], authenticatedHeader: header) == Data([42]))
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await receiver.open(sealedPayload: packets[0], authenticatedHeader: header) }
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await receiver.open(sealedPayload: packets[1], authenticatedHeader: header) }
        #expect(try await receiver.open(sealedPayload: packets[65], authenticatedHeader: header) == Data([42]))
        #expect(try await receiver.open(sealedPayload: packets[129], authenticatedHeader: header) == Data([42]))
        await #expect(throws: VoiceCryptoError.replayedPacket) { try await receiver.open(sealedPayload: packets[65], authenticatedHeader: header) }
        var secondHeader = header
        secondHeader[11] = 8
        // Independent synthetic peers deliberately repeat public fixture keys; a real
        // session must never reconstruct a transmit owner with an existing key.
        let secondSource = try VoiceTransportCipher(mode: mode, key: key)
        let second = try await secondSource.seal(payload: Data([7]), authenticatedHeader: secondHeader)
        await #expect(throws: VoiceCryptoError.receiveStreamLimit) { try await receiver.open(sealedPayload: second, authenticatedHeader: secondHeader) }
        await #expect(throws: VoiceCryptoError.receiveStreamLimit) { try await receiver.open(sealedPayload: second, authenticatedHeader: secondHeader) }
        let spacious = try VoiceTransportCipher(mode: mode, key: key, maximumReceiveStreams: 2)
        #expect(try await spacious.open(sealedPayload: packets[129], authenticatedHeader: header) == Data([42]))
        #expect(try await spacious.open(sealedPayload: second, authenticatedHeader: secondHeader) == Data([7]))
    }

    /// Tests packet budget exhaustion, byte boundaries, invalid headers, idempotent close and redaction.
    /// Rejected bounds never reserve a counter; a fresh session key is required after close.
    /// - Parameter mode: Each currently supported wire encryption mode.
    @Test(arguments: VoiceEncryptionMode.allCases)
    func transportBudgetsAndClose(mode: VoiceEncryptionMode) async throws {
        let cipher = try VoiceTransportCipher(mode: mode, key: key, maximumPacketBytes: 33, maximumPackets: 2)
        await #expect(throws: VoiceCryptoError.payloadTooLarge) { try await cipher.seal(payload: Data(count: 2), authenticatedHeader: header) }
        await #expect(throws: VoiceCryptoError.invalidHeader) { try await cipher.seal(payload: Data(), authenticatedHeader: header.dropLast()) }
        let sealed = try await cipher.seal(payload: Data([7]), authenticatedHeader: header)
        #expect(sealed.suffix(4) == Data(count: 4))
        #expect(try await cipher.open(sealedPayload: sealed, authenticatedHeader: header) == Data([7]))
        await #expect(throws: VoiceCryptoError.payloadTooLarge) { try await cipher.open(sealedPayload: sealed + Data([0]), authenticatedHeader: header) }
        await #expect(throws: VoiceCryptoError.invalidHeader) { try await cipher.open(sealedPayload: sealed, authenticatedHeader: Data(count: 11)) }
        for count in 0..<20 {
            await #expect(throws: VoiceCryptoError.malformedPacket) { try await cipher.open(sealedPayload: Data(count: count), authenticatedHeader: header) }
        }
        _ = try await cipher.seal(payload: Data(), authenticatedHeader: header)
        await #expect(throws: VoiceCryptoError.nonceExhausted) { try await cipher.seal(payload: Data(), authenticatedHeader: header) }
        #expect(String(describing: cipher) == "VoiceTransportCipher([REDACTED])")
        #expect(String(reflecting: cipher) == "VoiceTransportCipher([REDACTED])")
        #expect(Mirror(reflecting: cipher).children.count == 1)
        #expect(Mirror(reflecting: cipher).children.first?.value as? String == "[REDACTED]")
        #expect(cipher.description == cipher.debugDescription)
        await cipher.close()
        await cipher.close()
        await #expect(throws: VoiceCryptoError.nonceExhausted) { try await cipher.open(sealedPayload: sealed, authenticatedHeader: header) }
        await #expect(throws: VoiceCryptoError.nonceExhausted) { try await cipher.seal(payload: Data(), authenticatedHeader: header) }
    }

    /// Validates each constructor parameter without allocating resources for rejected configuration.
    @Test func invalidConfiguration() throws {
        for count in [0, 16, 31, 33, 64] {
            #expect(throws: VoiceCryptoError.invalidKeySize) { try VoiceTransportCipher(mode: .aeadAES256GCMRTPSize, key: Data(count: count)) }
        }
        for count in [0, 31, 65_508, Int.max] {
            #expect(throws: VoiceCryptoError.invalidConfiguration) { try VoiceTransportCipher(mode: .aeadAES256GCMRTPSize, key: key, maximumPacketBytes: count) }
        }
        for count in [0, -1, 65_537] {
            #expect(throws: VoiceCryptoError.invalidConfiguration) { try VoiceTransportCipher(mode: .aeadAES256GCMRTPSize, key: key, maximumReceiveStreams: count) }
        }
        for count in [UInt64(0), 4_294_967_297, .max] {
            #expect(throws: VoiceCryptoError.invalidConfiguration) { try VoiceTransportCipher(mode: .aeadAES256GCMRTPSize, key: key, maximumPackets: count) }
        }
    }

    /// Confirms concurrent actor callers reserve distinct counters and cancellation consumes no nonce.
    /// Counter 256 explicitly exercises network byte order beyond one-byte values.
    /// - Parameter mode: Each currently supported wire encryption mode.
    @Test(arguments: VoiceEncryptionMode.allCases)
    func concurrentCountersAndCancellation(mode: VoiceEncryptionMode) async throws {
        let cipher = try VoiceTransportCipher(mode: mode, key: key)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cipher.seal(payload: Data(), authenticatedHeader: header)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let nonces = try await withThrowingTaskGroup(of: Data.self, returning: Set<Data>.self) { group in
            for _ in 0..<257 {
                group.addTask { Data(try await cipher.seal(payload: Data(), authenticatedHeader: header).suffix(4)) }
            }
            var results: Set<Data> = []
            for try await nonce in group { results.insert(nonce) }
            return results
        }
        #expect(nonces.count == 257)
        #expect(nonces.contains(Data([0, 0, 0, 0])))
        #expect(nonces.contains(Data([0, 0, 1, 0])))
        let receiver = try VoiceTransportCipher(mode: mode, key: key)
        let sealed = try await cipher.seal(payload: Data([9]), authenticatedHeader: header)
        let cancelledOpen = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await receiver.open(sealedPayload: sealed, authenticatedHeader: header)
        }
        await #expect(throws: CancellationError.self) { try await cancelledOpen.value }
        #expect(try await receiver.open(sealedPayload: sealed, authenticatedHeader: header) == Data([9]))
    }
}
