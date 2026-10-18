import Testing
@testable import DiscordVoiceCodecs

@Suite("Exact SILK excitation reconstruction")
struct SILKExcitationTests {
    /// Verifies every signal/offset/two-bit-seed combination against the excitation
    /// buffer of independently compiled, unmodified official libopus 1.6.1 decode_core.c.
    /// The oracle's Q14 buffer divided by 64 equals the RFC's Q23 representation.
    /// These are intermediate excitation fixtures, not decoded-PCM conformance.
    @Test func officialExcitationFixtures() throws {
        let fixtures: [(Int, Int, UInt8, [Int32])] = [
            (0, 0, 0, [25, -261, -211, -517, 467, -32517, 32723, -25]),
            (0, 0, 1, [25, 261, -211, 517, 467, 32517, -32723, 25]),
            (0, 0, 2, [25, 261, -211, -517, 467, 32517, -32723, 25]),
            (0, 0, 3, [25, -261, -211, 517, 467, -32517, -32723, -25]),
            (0, 1, 0, [60, -296, -176, -552, 432, -32552, 32688, -60]),
            (0, 1, 1, [60, 296, -176, 552, 432, 32552, -32688, 60]),
            (0, 1, 2, [60, 296, -176, -552, 432, 32552, -32688, 60]),
            (0, 1, 3, [60, -296, -176, 552, 432, -32552, -32688, -60]),
            (1, 0, 0, [25, -261, -211, -517, 467, -32517, 32723, -25]),
            (1, 0, 1, [25, 261, -211, 517, 467, 32517, -32723, 25]),
            (1, 0, 2, [25, 261, -211, -517, 467, 32517, -32723, 25]),
            (1, 0, 3, [25, -261, -211, 517, 467, -32517, -32723, -25]),
            (1, 1, 0, [60, -296, -176, -552, 432, -32552, 32688, -60]),
            (1, 1, 1, [60, 296, -176, 552, 432, 32552, -32688, 60]),
            (1, 1, 2, [60, 296, -176, -552, 432, 32552, -32688, 60]),
            (1, 1, 3, [60, -296, -176, 552, 432, -32552, -32688, -60]),
            (2, 0, 0, [8, -244, -228, -500, 484, -32500, 32740, -8]),
            (2, 0, 1, [8, 244, -228, 500, 484, 32500, -32740, 8]),
            (2, 0, 2, [8, 244, -228, -500, 484, 32500, -32740, 8]),
            (2, 0, 3, [8, -244, -228, 500, 484, -32500, -32740, -8]),
            (2, 1, 0, [25, -261, -211, -517, 467, -32517, 32723, -25]),
            (2, 1, 1, [25, 261, -211, 517, 467, 32517, -32723, 25]),
            (2, 1, 2, [25, 261, -211, -517, 467, 32517, -32723, 25]),
            (2, 1, 3, [25, -261, -211, 517, 467, -32517, -32723, -25]),
        ]
        for (signal, offset, seed, expected) in fixtures {
            let signalType = try #require(SILKSignalType(rawValue: signal))
            let quantizationOffset = try #require(SILKQuantizationOffset(rawValue: offset))
            var reconstruction = try SILKExcitationReconstructor(seed: seed, signalType: signalType, quantizationOffset: quantizationOffset)
            #expect(reconstruction.signalType == signalType)
            #expect(reconstruction.quantizationOffset == quantizationOffset)
            #expect(try reconstruction.reconstruct([0, 1, -1, 2, -2, 127, -128, 0]) == expected)
        }
    }

    /// Uses independently widened Int64 arithmetic over all Int16 extremes and a
    /// maximum block to check modulo seed wrapping, signed adjustment, zero-pulse
    /// RNG steps and exact chunk invariance for every frame category/offset.
    @Test func widenedReferenceAndChunking() throws {
        let pulses = (0..<320).map { Int16(($0 * 337) % 65536 - 32768) }
        for type in SILKSignalType.allCases {
            for offset in SILKQuantizationOffset.allCases {
                for initial: UInt8 in 0...3 {
                    var referenceSeed = Int64(initial)
                    let quantization = type == .voiced ? (offset == .low ? 8 : 25) : (offset == .low ? 25 : 60)
                    var expected: [Int32] = []
                    for pulse in pulses {
                        referenceSeed = (196_314_165 * referenceSeed + 907_633_515) & 0xFFFF_FFFF
                        let raw = Int64(pulse)
                        let adjustment: Int64 = raw == 0 ? 0 : (raw < 0 ? -20 : 20)
                        let value = raw * 256 - adjustment + Int64(quantization)
                        expected.append(Int32(referenceSeed >= 0x8000_0000 ? -value : value))
                        referenceSeed = (referenceSeed + raw) & 0xFFFF_FFFF
                    }
                    var whole = try SILKExcitationReconstructor(seed: initial, signalType: type, quantizationOffset: offset)
                    #expect(try whole.reconstruct(pulses) == expected)
                    #expect(whole.seed == UInt32(referenceSeed))
                    var chunked = try SILKExcitationReconstructor(seed: initial, signalType: type, quantizationOffset: offset)
                    var result: [Int32] = []
                    for position in stride(from: 0, to: pulses.count, by: 13) {
                        result += try chunked.reconstruct(Array(pulses[position..<min(position + 13, pulses.count)]))
                    }
                    #expect(result == expected)
                    #expect(chunked.seed == whole.seed)
                    var copy = whole
                    try copy.reset(seed: initial)
                    #expect(copy.seed == UInt32(initial))
                    #expect(whole.seed == UInt32(referenceSeed))
                }
            }
        }
        var extremes = try SILKExcitationReconstructor(seed: 3, signalType: .unvoiced, quantizationOffset: .high)
        #expect(try extremes.reconstruct([.min, .max]) == [-8_388_528, -8_388_392])
        #expect(extremes.seed == 4_169_350_524)
    }

    /// Checks seed bounds, rejected reset/oversize atomicity, empty/no-state work,
    /// and the nonzero offset emitted for a zero raw pulse.
    @Test func validationAndEmptyState() throws {
        for seed: UInt8 in [4, 127, 255] {
            #expect(throws: SILKExcitationError.invalidSeed) {
                try SILKExcitationReconstructor(seed: seed, signalType: .inactive, quantizationOffset: .high)
            }
        }
        var reconstruction = try SILKExcitationReconstructor(seed: 0, signalType: .voiced, quantizationOffset: .low)
        #expect(try reconstruction.reconstruct([]).isEmpty)
        #expect(reconstruction.seed == 0)
        #expect(throws: SILKExcitationError.invalidSampleCount) { try reconstruction.reconstruct(Array(repeating: 0, count: 321)) }
        #expect(throws: SILKExcitationError.invalidSeed) { try reconstruction.reset(seed: 4) }
        #expect(reconstruction.seed == 0)
        #expect(try reconstruction.reconstruct([0]) == [8])
        #expect(reconstruction.seed == 907_633_515)
        try reconstruction.reset(seed: 2)
        #expect(reconstruction.seed == 2)
    }
}
