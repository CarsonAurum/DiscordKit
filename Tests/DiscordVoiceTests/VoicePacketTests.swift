import Foundation
import Testing
import DiscordTransport
import DiscordVoiceCodecs
import DiscordVoiceCrypto
@testable import DiscordVoice

/// RTP/discovery/reorder tests use synthetic bytes, no sockets, timing sleeps or credentials.
@Suite struct VoicePacketTests {
    /// Confirms fixed fields, all optional RTP sections, padding canonicalization and slice support.
    @Test func packetRoundTrip() throws {
        let ext = try RTPExtension(profile: 0xbede, bytes: Data([1, 2, 3, 4]))
        let packet = try RTPPacket(payloadType: 127, marker: true, sequence: .max, timestamp: .max,
                                   ssrc: 0x01020304, contributingSources: [0, .max], headerExtension: ext,
                                   payload: Data([9, 8, 7]), paddingCount: 3)
        let wire = packet.serialized()
        #expect(Array(wire.prefix(12)) == [0xb2, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 1, 2, 3, 4])
        #expect(try RTPPacket.authenticatedHeaderLength(in: wire) == 24)
        #expect(try RTPPacket(bytes: wire) == packet)
        let wrapped = Data([99]) + wire
        #expect(try RTPPacket(bytes: wrapped.dropFirst()) == packet)
        #expect(packet.description == "RTPPacket(redacted)")
        #expect(packet.debugDescription == packet.description)
        #expect(packet.customMirror.children.count == 1)
    }

    /// Rejects malformed RTP variants before indexing untrusted header/extension/padding bytes.
    @Test func malformedPackets() throws {
        let packet = try RTPPacket(sequence: 1, timestamp: 2, ssrc: 3, payload: Data([4]))
        let valid = packet.serialized()
        for length in 0..<12 {
            #expect(throws: VoicePacketError.malformedPacket) { try RTPPacket(bytes: valid.prefix(length)) }
        }
        for first: UInt8 in [0, 0x40, 0xc0, 0x8f, 0x90, 0xa0] {
            var invalid = valid; invalid[0] = first
            if first == 0xa0 { invalid[12] = 0 }
            #expect(throws: VoicePacketError.malformedPacket) { try RTPPacket(bytes: invalid) }
        }
        let extensionHeader = Data([0x90, 120, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0xbe, 0xde, 0xff, 0xff])
        #expect(try RTPPacket.authenticatedHeaderLength(in: extensionHeader) == 16)
        #expect(throws: VoicePacketError.malformedPacket) { try RTPPacket(bytes: extensionHeader) }
        #expect(throws: VoicePacketError.malformedPacket) { try RTPExtension(profile: 0, bytes: Data([1])) }
        #expect(throws: VoicePacketError.malformedPacket) { try RTPPacket(payloadType: 128, sequence: 0, timestamp: 0, ssrc: 0, payload: Data()) }
        #expect(throws: VoicePacketError.malformedPacket) { try RTPPacket(sequence: 0, timestamp: 0, ssrc: 0, contributingSources: Array(repeating: 0, count: 16), payload: Data()) }
        #expect(throws: VoicePacketError.packetTooLarge) { try RTPPacket(sequence: 0, timestamp: 0, ssrc: 0, payload: Data(repeating: 0, count: 65_496)) }
        #expect(throws: VoicePacketError.packetTooLarge) { try RTPPacket.authenticatedHeaderLength(in: Data(repeating: 0, count: 65_508)) }
        let empty = try RTPPacket(sequence: 0, timestamp: 0, ssrc: 0, payload: Data(), paddingCount: 1)
        #expect(try RTPPacket(bytes: empty.serialized()) == empty)
    }

    /// Confirms parsed Opus duration drives timestamps and invalid input cannot consume RTP counters.
    @Test func opusClockAndSilence() throws {
        var packetizer = OpusRTPPacketizer(ssrc: 9, sequence: .max, timestamp: .max - 100)
        let first = try packetizer.silencePacket()
        #expect(first.sequence == .max)
        #expect(first.timestamp == UInt32.max - 100)
        #expect(first.payload == Data([0xf8, 0xff, 0xfe]))
        #expect(packetizer.nextSequence == 0)
        #expect(packetizer.nextTimestamp == 859)
        #expect(throws: (any Error).self) { try packetizer.packetize(Data()) }
        #expect(packetizer.nextSequence == 0)
        for _ in 0..<4 { _ = try packetizer.silencePacket() }
        #expect(packetizer.nextSequence == 4)
        #expect(packetizer.nextTimestamp == 4699)
        let short = try packetizer.packetize(Data([0x80]), marker: true)
        #expect(short.marker)
        #expect(packetizer.nextTimestamp == 4819)
    }

    /// Tests deterministic loss/reorder/duplicate/rollover and failure-atomic byte bounds.
    @Test func jitterWindow() throws {
        var buffer = try VoiceJitterBuffer(ssrc: 9, nextSequence: .max, capacity: 3, maximumBytes: 26)
        let last = try RTPPacket(sequence: .max, timestamp: 0, ssrc: 9, payload: Data([1]))
        let zero = try RTPPacket(sequence: 0, timestamp: 960, ssrc: 9, payload: Data([2]))
        try buffer.insert(zero)
        #expect(buffer.peek() == nil)
        try buffer.insert(last)
        #expect(buffer.peek() == last)
        #expect(buffer.bufferedBytes == 26)
        #expect(throws: VoicePacketError.duplicateOrLate) { try buffer.insert(zero) }
        let wrong = try RTPPacket(sequence: 1, timestamp: 0, ssrc: 8, payload: Data())
        #expect(throws: VoicePacketError.wrongStream) { try buffer.insert(wrong) }
        let full = try RTPPacket(sequence: 1, timestamp: 1920, ssrc: 9, payload: Data())
        #expect(throws: VoicePacketError.capacityExceeded) { try buffer.insert(full) }
        #expect(buffer.pop() == .packet(last))
        #expect(buffer.peek() == zero)
        #expect(buffer.pop() == .packet(zero))
        #expect(buffer.pop() == .missing(sequence: 1))
        #expect(buffer.bufferedBytes == 0)
        #expect(buffer.peek() == nil)
        #expect(throws: VoicePacketError.duplicateOrLate) { try buffer.insert(full) }
        let distant = try RTPPacket(sequence: 5, timestamp: 0, ssrc: 9, payload: Data())
        #expect(throws: VoicePacketError.capacityExceeded) { try buffer.insert(distant) }
        buffer.reset(nextSequence: 5)
        try buffer.insert(distant)
        buffer.reset()
        #expect(buffer.nextSequence == 5)
        #expect(buffer.bufferedBytes == 0)
        #expect(buffer.pop() == .missing(sequence: 5))
        #expect(throws: VoicePacketError.invalidConfiguration) { try VoiceJitterBuffer(ssrc: 0, nextSequence: 0, capacity: 32_768) }
        #expect(throws: VoicePacketError.invalidConfiguration) { try VoiceJitterBuffer(ssrc: 0, nextSequence: 0, maximumBytes: 0) }
    }

    /// Verifies current discovery framing, SSRC binding, IPv4/IPv6 literals and hostile address rejection.
    @Test func discovery() throws {
        let request = VoiceDiscovery.request(ssrc: 0x01020304)
        #expect(request.count == 74)
        #expect(Array(request.prefix(8)) == [0, 1, 0, 70, 1, 2, 3, 4])
        for address in ["127.0.0.1", "2001:db8::1", "2001:db8::", "::", "::ffff:192.0.2.1", "1:2:3:4:5:6:7:8", "1:2:3:4:5:6:192.0.2.1"] {
            let response = discoveryResponse(address: address)
            #expect(try VoiceDiscovery.response(response, ssrc: 0x01020304) == DatagramAddress(host: address, port: 5000))
            #expect(throws: VoicePacketError.wrongStream) { try VoiceDiscovery.response(response, ssrc: 0) }
        }
        for address in ["", "example.com", "256.1.1.1", "01.2.3.4", ":::", "1::2::3", "1:2:3", "::1:", "1::2:", ":1::", ":1::2", "192.0.2.1::", "::ffff:192.0.2.999", "fe80::1%en0", "1:2:3:4:5:6::192.0.2.1", "1:2:3:4:5:6:7:8:9"] {
            #expect(throws: VoicePacketError.malformedPacket) { try VoiceDiscovery.response(discoveryResponse(address: address), ssrc: 0x01020304) }
        }
        var response = discoveryResponse(address: "127.0.0.1")
        response[1] = 1
        #expect(throws: VoicePacketError.malformedPacket) { try VoiceDiscovery.response(response, ssrc: 0x01020304) }
        response[1] = 2; response[72] = 0; response[73] = 0
        #expect(throws: VoicePacketError.malformedPacket) { try VoiceDiscovery.response(response, ssrc: 0x01020304) }
        #expect(throws: VoicePacketError.malformedPacket) { try VoiceDiscovery.response(Data(), ssrc: 0) }
        response.replaceSubrange(8..<72, with: repeatElement(UInt8(65), count: 64))
        #expect(throws: VoicePacketError.malformedPacket) { try VoiceDiscovery.response(response, ssrc: 0x01020304) }
    }

    /// Rejects structurally valid Opus whose padding exceeds the complete RTP UDP bound.
    /// Parsing succeeds first, so the failure specifically proves packet construction is
    /// atomic with respect to both packetizer counters even after codec validation.
    @Test func oversizedValidOpusPreservesCounters() throws {
        let opus = Data([0x83, 0x41]) + Data(repeating: 255, count: 256) + Data([217]) + Data(count: 65_241)
        #expect(opus.count == 65_500)
        #expect(try OpusPacket(opus).sampleCount == 120)
        var packetizer = OpusRTPPacketizer(ssrc: 9, sequence: 123, timestamp: 456)
        #expect(throws: VoicePacketError.packetTooLarge) { try packetizer.packetize(opus) }
        #expect(packetizer.nextSequence == 123)
        #expect(packetizer.nextTimestamp == 456)
    }

    /// Exercises complete synthetic RTP transport protection with encrypted extension words in both modes.
    /// This is transport-only evidence; it does not send DAVE, contact Discord or certify voice.
    /// - Parameter mode: Each current Discord rtpsize transport cipher.
    @Test(arguments: [VoiceEncryptionMode.aeadAES256GCMRTPSize, .aeadXChaCha20Poly1305RTPSize])
    func encryptedRTP(mode: VoiceEncryptionMode) async throws {
        let cipher = try VoiceTransportCipher(mode: mode, key: Data(repeating: 0x61, count: 32))
        let receiver = try VoiceTransportCipher(mode: mode, key: Data(repeating: 0x61, count: 32))
        let packet = try RTPPacket(sequence: .max, timestamp: 123, ssrc: 4,
                                   contributingSources: [7], headerExtension: RTPExtension(profile: 0xbede, bytes: Data([1, 0, 0, 0])),
                                   payload: Data([0xf8, 0xff, 0xfe]), paddingCount: 2)
        let wire = packet.serialized()
        let headerLength = try RTPPacket.authenticatedHeaderLength(in: wire)
        let header = Data(wire.prefix(headerLength))
        let sealed = try await cipher.seal(payload: Data(wire.dropFirst(headerLength)), authenticatedHeader: header)
        #expect(sealed != Data(wire.dropFirst(headerLength)))
        let plaintext = try await receiver.open(sealedPayload: sealed, authenticatedHeader: header)
        #expect(try RTPPacket(bytes: header + plaintext) == packet)
        await cipher.close()
        await receiver.close()
    }

    /// Produces a fixed valid response whose address is varied by discovery-negative tests.
    /// - Parameter address: ASCII text of at most 63 bytes, NUL-padded by this fixture.
    /// - Returns: Type-two response with SSRC 0x01020304 and port 5000.
    private func discoveryResponse(address: String) -> Data {
        var bytes = Array(VoiceDiscovery.request(ssrc: 0x01020304))
        bytes[1] = 2
        for (index, byte) in address.utf8.enumerated() { bytes[8 + index] = byte }
        bytes[72] = 0x13; bytes[73] = 0x88
        return Data(bytes)
    }
}
