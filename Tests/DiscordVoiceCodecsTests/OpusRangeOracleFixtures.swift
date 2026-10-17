// Compact independent oracle output generated from unmodified official libopus 1.6.1.
// https://opus-codec.org/release/stable/2026/01/14/libopus-1_6_1.html
// Source archive SHA256: 6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1.
// Generated 2026-10-17 by invoking ec_encode/ec_enc_bit_logp/ec_enc_uint/ec_enc_bits,
// recording ec_tell/ec_tell_frac/rng after each call and frame bytes after ec_enc_done.
// Oracle source and executable are development-only temporary files, never linked here.
// These are entropy vectors, not full Opus decoded-PCM conformance vectors.

enum OpusEntropyOperation: Sendable {
    case symbol(Int, [UInt32])
    case bit(Bool, Int)
    case uniform(UInt32, UInt32)
    case raw(UInt32, Int)
}

struct OpusEntropyFixture: Sendable {
    let name: String
    let bytes: [UInt8]
    let operations: [OpusEntropyOperation]
    let states: [(range: UInt32, bits: Int, fractional: Int)]
}

enum OpusEntropyOracleFixtures {
    static let all: [OpusEntropyFixture] = [
        OpusEntropyFixture(name: "empty",
            bytes: [],
            operations: [
            ],
            states: [
                (2147483648, 1, 8),
            ]),
        OpusEntropyFixture(name: "intervalsAndZeroFrequencies",
            bytes: [21, 13, 86, 128, 0, 0, 0, 0],
            operations: [
                .symbol(0, [2, 0, 3, 5, 1]), .symbol(2, [2, 0, 3, 5, 1]), .symbol(4, [2, 0, 3, 5, 1]), .symbol(3, [2, 0, 3, 5, 1]),
                .symbol(0, [65534, 1]), .symbol(1, [65534, 1]), .symbol(1, [0, 1, 0]),
            ],
            states: [
                (2147483648, 1, 8), (390451574, 4, 28), (106486791, 6, 43),
                (9680617, 9, 71), (1126471680, 10, 80), (1126454492, 10, 80),
                (1126432768, 26, 208), (1126432768, 26, 208),
            ]),
        OpusEntropyFixture(name: "sharedFinalByte",
            bytes: [171],
            operations: [
                .bit(true, 1), .raw(43, 6),
            ],
            states: [
                (2147483648, 1, 8), (1073741824, 2, 16), (1073741824, 8, 64),
            ]),
        OpusEntropyFixture(name: "uniformExtremes",
            bytes: [127, 213, 128, 42, 255, 192, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 87, 155, 223, 255, 255, 253, 252],
            operations: [
                .uniform(0, 2), .uniform(2, 3), .uniform(254, 255), .uniform(1, 256),
                .uniform(256, 257), .uniform(65534, 65535), .uniform(4294967294, 4294967295), .raw(28036591, 25),
            ],
            states: [
                (2147483648, 1, 8), (1073741824, 2, 16), (357913941, 4, 29),
                (359317504, 12, 93), (359317504, 20, 157), (713064192, 28, 221),
                (713064192, 44, 349), (713064192, 76, 605), (713064192, 101, 805),
            ]),
        OpusEntropyFixture(name: "mixedContexts",
            bytes: [55, 255, 143, 221, 127, 29, 224, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 173, 230, 138, 241],
            operations: [
                .symbol(0, [56, 100, 0, 100]), .bit(false, 15), .raw(17, 5), .symbol(3, [56, 100, 0, 100]),
                .uniform(999, 1000), .bit(true, 15), .symbol(1, [56, 100, 0, 100]), .raw(0, 0),
                .uniform(123456789, 4294967295), .raw(33554431, 25), .bit(false, 1), .symbol(3, [2, 0, 3, 5, 1]),
                .uniform(0, 257), .bit(true, 2), .symbol(0, [2, 0, 3, 5, 1]),
            ],
            states: [
                (2147483648, 1, 8), (469762048, 4, 26), (469747712, 4, 26),
                (469747712, 9, 66), (183495200, 10, 77), (187898880, 20, 157),
                (375783424, 35, 277), (146790400, 36, 287), (146790400, 36, 287),
                (146790400, 68, 543), (146790400, 93, 743), (73395200, 94, 751),
                (33361450, 96, 761), (66234880, 104, 825), (16558720, 106, 841),
                (770733568, 108, 860),
            ]),
        OpusEntropyFixture(name: "carryPropagation",
            bytes: [255, 255, 255, 255, 255, 255, 255, 255, 127, 255, 255, 255, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 85],
            operations: [
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(false, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(true, 1), .bit(true, 1), .bit(true, 1),
                .bit(true, 1), .bit(false, 1), .symbol(1, [1, 65534]), .raw(85, 7),
            ],
            states: [
                (2147483648, 1, 8), (1073741824, 2, 16), (536870912, 3, 24),
                (268435456, 4, 32), (134217728, 5, 40), (67108864, 6, 48),
                (33554432, 7, 56), (16777216, 8, 64), (2147483648, 9, 72),
                (1073741824, 10, 80), (536870912, 11, 88), (268435456, 12, 96),
                (134217728, 13, 104), (67108864, 14, 112), (33554432, 15, 120),
                (16777216, 16, 128), (2147483648, 17, 136), (1073741824, 18, 144),
                (536870912, 19, 152), (268435456, 20, 160), (134217728, 21, 168),
                (67108864, 22, 176), (33554432, 23, 184), (16777216, 24, 192),
                (2147483648, 25, 200), (1073741824, 26, 208), (536870912, 27, 216),
                (268435456, 28, 224), (134217728, 29, 232), (67108864, 30, 240),
                (33554432, 31, 248), (16777216, 32, 256), (2147483648, 33, 264),
                (1073741824, 34, 272), (536870912, 35, 280), (268435456, 36, 288),
                (134217728, 37, 296), (67108864, 38, 304), (33554432, 39, 312),
                (16777216, 40, 320), (2147483648, 41, 328), (1073741824, 42, 336),
                (536870912, 43, 344), (268435456, 44, 352), (134217728, 45, 360),
                (67108864, 46, 368), (33554432, 47, 376), (16777216, 48, 384),
                (2147483648, 49, 392), (1073741824, 50, 400), (536870912, 51, 408),
                (268435456, 52, 416), (134217728, 53, 424), (67108864, 54, 432),
                (33554432, 55, 440), (16777216, 56, 448), (2147483648, 57, 456),
                (1073741824, 58, 464), (536870912, 59, 472), (268435456, 60, 480),
                (134217728, 61, 488), (67108864, 62, 496), (33554432, 63, 504),
                (16777216, 64, 512), (2147483648, 65, 520), (1073741824, 66, 528),
                (536870912, 67, 536), (268435456, 68, 544), (134217728, 69, 552),
                (67108864, 70, 560), (33554432, 71, 568), (16777216, 72, 576),
                (2147483648, 73, 584), (1073741824, 74, 592), (536870912, 75, 600),
                (268435456, 76, 608), (134217728, 77, 616), (67108864, 78, 624),
                (33554432, 79, 632), (16777216, 80, 640), (2147483648, 81, 648),
                (1073741824, 82, 656), (536870912, 83, 664), (268435456, 84, 672),
                (134217728, 85, 680), (67108864, 86, 688), (33554432, 87, 696),
                (16777216, 88, 704), (2147483648, 89, 712), (1073741824, 90, 720),
                (536870912, 91, 728), (268435456, 92, 736), (134217728, 93, 744),
                (67108864, 94, 752), (33554432, 95, 760), (16777216, 96, 768),
                (2147483648, 97, 776), (1073741824, 98, 784), (536870912, 99, 792),
                (536854528, 100, 793), (536854528, 107, 849),
            ]),
    ]
}
