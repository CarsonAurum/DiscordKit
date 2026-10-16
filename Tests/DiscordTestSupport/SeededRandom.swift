/// Reproducible SplitMix64 randomness for jitter tests; never use for credentials.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Initializes a deterministic sequence. Every UInt64 seed, including zero, is valid.
    /// - Parameter seed: Initial sequence state; equal seeds produce equal sequences.
    public init(seed: UInt64) { state = seed }

    /// Advances one SplitMix64 step with deliberately wrapping UInt64 arithmetic.
    /// - Returns: A deterministic UInt64; independent instances share no state.
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
