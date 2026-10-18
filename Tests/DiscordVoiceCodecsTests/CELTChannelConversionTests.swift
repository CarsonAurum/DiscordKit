import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// RFC 8251 mono downmix suppresses coded stereo intensity inversion without altering entropy.
@Suite("CELT coded stereo output conversion")
struct CELTChannelConversionTests {
    private static let frame = Data([108, 151, 79, 227, 144, 239, 84, 135, 131, 24, 110,
        23, 152, 45, 43, 201, 80, 39, 234, 239, 119, 207, 236, 82, 1, 159, 142, 223, 162, 19, 51])

    /// An actual independently encoded 31-byte transition-redundancy frame contains stereo inversion bits.
    /// Complete libopus 1.6.1 PCM vectors cover both output layouts. Mono output deliberately differs
    /// from averaging independently rendered stereo: RFC 8251 suppresses intensity phase inversion
    /// before denormalization/downmix. This caught a 0.243-sample error despite an exact final range.
    /// - Parameter outputChannels: One or two persistent output channels for the same coded stereo frame.
    /// - Throws: Fixture decoding or owned codec errors indicate invalid evidence or a regression.
    @Test(arguments: [1, 2])
    func independentIntensityInversionVector(outputChannels: Int) throws {
        let records = try JSONDecoder().decode([Vector].self, from: Data(Self.vectors.utf8))
        let record = try #require(records.first { $0.channels == outputChannels })
        let reference = try floats(record.pcm)
        var decoder = try CELTFrameDecoder(channelCount: outputChannels)
        let actual = try decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2)
        #expect(actual.frameSampleCount == 240 && actual.channelCount == outputChannels)
        #expect(actual.finalRange == record.range && actual.finalRange == 19_844_384)
        #expect(actual.samples.count == reference.count && reference.count == 240 * outputChannels)
        for (observed, expected) in zip(actual.samples, reference) {
            #expect(observed.isFinite && abs(observed - expected) < 0.000001)
        }
        var entropy = try OpusRangeDecoder(frame: Self.frame)
        var shared = try CELTFrameDecoder(channelCount: outputChannels)
        #expect(try shared.decode(from: &entropy, frameSampleCount: 240, codedChannelCount: 2) == actual)
        #expect(entropy.finalRange == actual.finalRange)
        var copy = decoder
        #expect(try copy.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2)
            == decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2))
        decoder.reset()
        #expect(try decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2) == actual)
        if outputChannels == 1 {
            let stereo = try floats(try #require(records.first { $0.channels == 2 }).pcm)
            let largest = (0..<240).map { abs(reference[$0] - 0.5 * (stereo[2 * $0] + stereo[2 * $0 + 1])) }.max() ?? 0
            #expect(largest > 0.24)
        }
    }

    /// Invalid coded-channel declarations preserve both the decoder and caller-owned shared entropy.
    /// The subsequent valid coded-stereo frame must match an independent warm stream exactly.
    /// - Throws: Valid-frame decoding errors would indicate an implementation regression.
    @Test func invalidCodedChannelCountsPreserveHistories() throws {
        var decoder = try CELTFrameDecoder()
        _ = try decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2)
        var baseline = decoder
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidChannelCount) {
                try decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: channels)
            }
            var entropy = try OpusRangeDecoder(frame: Self.frame)
            let before = entropy
            #expect(throws: CELTBitAllocationError.invalidChannelCount) {
                try decoder.decode(from: &entropy, frameSampleCount: 240, codedChannelCount: channels)
            }
            #expect(entropy.finalRange == before.finalRange && entropy.bitsUsed == before.bitsUsed
                && entropy.fractionalBitsUsed == before.fractionalBitsUsed)
        }
        #expect(try decoder.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2)
            == baseline.decode(Self.frame, frameSampleCount: 240, codedChannelCount: 2))
    }

    /// Restores the complete exact little-endian float32 reference vector without native codec calls.
    /// - Parameter encoded: Base64 containing one complete independently emitted PCM vector.
    /// - Returns: All samples with their original binary floating-point values.
    /// - Throws: A requirement failure for malformed evidence, before unsafe indexing can occur.
    private func floats(_ encoded: String) throws -> [Float] {
        let bytes = Array(try #require(Data(base64Encoded: encoded)))
        try #require(bytes.count.isMultiple(of: 4))
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            Float(bitPattern: UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24)
        }
    }

    private struct Vector: Decodable { let channels: Int; let range: UInt32; let pcm: String }
    // Source: unmodified pinned libopus 1.6.1 scalar celt_decode_with_ec, with
    // CELT_SET_CHANNELS(2), fresh API output layout 1/2, 48kHz and a 240-sample frame.
    // Archive SHA256: 6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1.
    private static let vectors = #"""
[{"channels":1,"range":19844384,"pcm":"okK+tUn2E7cA8WY1n/yyOD8IljmtDgs6PIIVOpQVnzghOY265Sciu4+8S7tv7Pa6flS/OnDJtzvK0wE8XOjCO2gqFbowfA284/9XvKFmJ7wAGEu32ppGPEBZmDy/sGw8ELCPOtK5Y7ykHK+8dPiGvKhL/7pzCl087P+oPFyDfDxgQpQ6kwZlvPgMs7wgfpy8aVIIvFfFgTs5Ezc8KVomPFgGGjsi2PW7OpJrvLCvgbzJEFW8c5MXvOZi8Lt34Ou7e1HOuxCEJruBXDg7+qylO1D5AbqstV68MSDfvISXAL0Gnaa8MB7pOmOgtjxUZ+U8MZFuPH5fH7x42/C8SmUEvUrFj7wuPZw79W+uPHfiyTxmgYw88m/rO8xv5DoI8ec6qIlNO57E4jrQjPW6tuIhu1D6qzsOfLA8fjYiPYlyRj3tCCI9OHRZPDzom7yASiC9wKkBvTAQsjvmNGU9h9a6PRevrz3XiA89hNAXvcoitb3miau97IycvCoqkT1edgY+SdD3PS0kJj0dc4W91tAIvge+/L26bCW9jF2HPUg7CT6ERQE+z4ZQPVsDP72kf+e9D7zwvdzNhr1UuQs8a5eHPX++qj0wJXc9kKqCPBhg0rwsmkK9qMQ5vVTL1LwQs4S6a4+ePDy++DxC/wY9s2sAPaPW8DxlIOY80w3UPPJUrDyWkmo8BKshPMtuVzySLd885WNMPanBlj2KDrY9LLO2PWQjmT3JWFk9fngSPeVPCD1Syko9RLyiPSKl4z3KcQY+ACAHPuZa6z0rPbo9Rd2XPRflmD109749pOT4PSqEFj73gSM+trQgPog2Ez4+KwQ+13H3PakT+z2rDAg+M3cWPifyIz6r6C0+jn00PpD4OD7/gTs+CP85PgSGMT7zIyI+O9gRPlrECz7VPho++GE+Prxgaz62O4U+vaeDPpf8XT4I5CA+D77hPW931T0LXxU+fgtcPtTQjD6GIZc+Aq6IPiaFVT65Rxw+wCYCPqy5Dz5m0Tc+zBFiPsjDeT4+1Hc+6l1jPkFwSj7ALTk+BC40PiJcOD4jAD8+KmZCPnC3QD4jCzw+M0I4Pi8hOD6IPjs+dvo9PteQOz4NNTE+RGggPgodDz7UGgU+nqwHPhb9FT5gPyg+Fb4yPizBKz6ocxE+5PPYPYHsmT2WQ4U9dWOnPf6i7z1A0xo+XM0mPq2SED6M670909EgPZioxzvGHgU8iKIqPXaXsT38b/I9y/P1PYEwuz2GRD49UP2lO9dtj7wUVoq8ALjgOciLtjzMeBk9"},{"channels":2,"range":19844384,"pcm":"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"}]
"""#
}
