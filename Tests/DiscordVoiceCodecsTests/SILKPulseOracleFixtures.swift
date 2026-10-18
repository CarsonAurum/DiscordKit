// Independent compressed-pulse fixtures from unmodified official libopus 1.6.1.
// Source: https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz
// Archive SHA256: 6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1.
// Encoding: silk_encode_pulses + ec_enc_shrink + ec_enc_done; decoding:
// silk_decode_pulses. Scope: pulse syntax only, no decoded-PCM conformance.
// Reproduce with Tools/DiscordKitTools/scripts/verify_silk_pulse_oracle.py.

/// A deterministic repeated input pattern and independent entropy/byte expectations.
struct SILKPulseOracleFixture: Sendable {
    let signal: Int
    let offset: Int
    let sampleCount: Int
    let pattern: [Int16]
    let rate: Int
    let range: UInt32
    let bits: Int
    let fractional: Int
    let bytes: [UInt8]
}

/// Literal values remain independent of the production encoder and its tables.
enum SILKPulseOracleFixtures {
    static let all: [SILKPulseOracleFixture] = [
        SILKPulseOracleFixture(signal: 0, offset: 0, sampleCount: 80, pattern: [0], rate: 0, range: 1130270720, bits: 10, fractional: 80, bytes: [0,0]),
        SILKPulseOracleFixture(signal: 1, offset: 0, sampleCount: 120, pattern: [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], rate: 1, range: 776591872, bits: 67, fractional: 532, bytes: [33,40,63,165,229,255,255,255,192]),
        SILKPulseOracleFixture(signal: 2, offset: 0, sampleCount: 160, pattern: [1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0], rate: 3, range: 719956224, bits: 123, fractional: 981, bytes: [105,87,48,44,208,1,81,211,42,218,222,25,166,200,235,192]),
        SILKPulseOracleFixture(signal: 0, offset: 1, sampleCount: 240, pattern: [1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0], rate: 4, range: 1694002688, bits: 394, fractional: 3147, bytes: [150,77,234,40,1,168,248,254,111,152,55,188,68,132,56,189,33,73,253,39,253,111,11,237,94,239,181,80,87,135,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,128]),
        SILKPulseOracleFixture(signal: 1, offset: 1, sampleCount: 320, pattern: [1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0], rate: 6, range: 1554434304, bits: 538, fractional: 4300, bytes: [196,117,7,80,212,252,104,37,1,217,143,236,190,199,190,166,14,146,182,77,126,198,80,168,149,2,147,208,217,86,63,232,226,204,42,168,156,210,241,117,167,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,128]),
        SILKPulseOracleFixture(signal: 2, offset: 1, sampleCount: 80, pattern: [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0], rate: 7, range: 382783968, bits: 148, fractional: 1180, bytes: [229,245,153,193,223,151,229,51,22,66,109,200,129,112,247,255,255,255,224]),
        SILKPulseOracleFixture(signal: 0, offset: 0, sampleCount: 120, pattern: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], rate: 8, range: 29260539, bits: 336, fractional: 2682, bytes: [255,40,245,194,143,56,217,94,63,137,121,86,41,206,66,78,15,62,201,217,97,150,109,203,175,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,254]),
        SILKPulseOracleFixture(signal: 1, offset: 0, sampleCount: 160, pattern: [0,-127,0,127], rate: 8, range: 9053616, bits: 1625, fractional: 13000, bytes: [255,255,255,255,255,251,177,127,255,255,255,54,32,79,255,255,219,9,51,255,255,249,59,85,255,255,254,194,190,127,255,255,197,232,183,255,255,245,93,3,127,255,254,13,105,255,255,255,164,181,159,255,255,233,223,196,212,97,128,48,112,223,220,32,221,114,28,228,20,104,96,20,216,227,29,129,21,145,176,114,67,247,249,120,23,156,40,169,111,225,49,14,35,119,243,238,133,223,5,37,131,54,100,25,157,220,211,226,250,123,54,103,0,217,73,83,171,220,193,118,235,153,219,221,94,52,54,78,237,148,105,219,221,192,35,217,103,252,0,101,149,131,237,246,207,33,154,45,225,174,207,192,132,5,11,122,130,124,98,68,226,124,0,16,226,168,97,161,171,245,157,119,61,184,218,206,32,133,202,248,87,184,100,248,205,75,225,189,106,7,141,70,115,21,52,68,187,167,131,12,208,181,240,128]),
        SILKPulseOracleFixture(signal: 2, offset: 0, sampleCount: 240, pattern: [0,1,-1,2,-2,0,8,0], rate: 8, range: 916686540, bits: 1003, fractional: 8018, bytes: [255,246,128,84,142,221,28,225,169,170,222,197,156,188,141,50,243,245,62,238,22,182,18,93,212,87,118,178,15,34,166,92,101,104,252,6,193,38,79,162,253,71,193,75,81,135,46,65,15,45,132,42,74,3,110,150,189,172,154,57,121,213,163,131,61,146,109,78,254,204,128,133,98,176,19,42,112,221,68,220,80,200,251,153,233,99,214,243,87,87,53,249,127,204,80,168,243,201,28,121,98,193,250,158,194,219,115,211,148,174,89,74,64,252,4,226,141,187,127,106,40,71,34,166,248,160]),
        SILKPulseOracleFixture(signal: 0, offset: 1, sampleCount: 320, pattern: [2,0,-3,0,4,0,-5,0], rate: 8, range: 35066115, bits: 1239, fractional: 9912, bytes: [255,248,156,179,139,143,136,67,189,232,99,125,65,4,109,204,74,233,132,181,89,225,24,134,41,149,198,223,231,252,46,122,159,254,163,17,222,42,177,86,244,76,179,145,82,247,237,183,198,24,244,52,69,146,217,6,23,39,188,216,163,172,113,15,246,58,41,216,42,175,130,188,254,7,248,29,228,218,94,239,135,85,128,170,208,19,13,8,216,199,61,113,12,29,144,63,172,170,67,42,34,215,245,253,22,121,224,6,162,90,38,192,251,50,23,95,225,37,209,206,203,230,145,213,169,194,167,18,11,170,89,16,87,20,246,99,182,147,191,97,6,154,41,20,29,168,58,152,77,133,58,245,45,108,12]),
        SILKPulseOracleFixture(signal: 1, offset: 1, sampleCount: 80, pattern: [7,0,-7,1,0,-1,0,3], rate: 8, range: 73181922, bits: 374, fractional: 2992, bytes: [255,252,183,157,132,117,133,188,186,227,173,142,158,188,62,221,34,50,193,33,6,140,138,237,154,102,100,124,63,44,209,140,246,26,79,115,195,51,252,20,222,49,243,139,120,50,20]),
    ]
}
