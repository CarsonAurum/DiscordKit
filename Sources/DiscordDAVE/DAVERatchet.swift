import Crypto
import DiscordMLS
import Foundation

/// DAVE's bounded MLS HashRatchet for one sender and one MLS exporter key domain.
///
/// Generation zero starts with the sixteen-byte DAVE exporter; later secrets are
/// SHA-256-sized. Keys use RFC 9420 DeriveTreeSecret with the labels `key` and
/// `secret` and a big-endian uint32 generation. The unused MLS nonce derivation
/// does not affect either value. Copies duplicate secrets and must never become
/// independent transmit owners. Logical erasure does not guarantee physical
/// erasure of Swift `Data` storage. Construction performs no I/O or background work.
public struct DAVEKeyRatchet: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var secret: Data
    private var nextGeneration: UInt64 = 0
    private var keys: [UInt32: Data] = [:]
    /// Maximum generations derived by one request; bounded to libdave's 250-generation gap.
    public let maximumForwardDistance: Int
    /// Maximum cached generation keys; oldest keys are erased as this bound is reached.
    public let maximumRetainedKeys: Int

    /// Constructs a lazy sender ratchet from the exact MLS exporter output.
    /// - Parameters:
    ///   - baseSecret: Exactly sixteen bytes exported using `Discord Secure Frames v0`,
    ///     the sender's little-endian uint64 user ID, and output length sixteen.
    ///   - maximumForwardDistance: Maximum forward gap, in 0...250; default eight.
    ///   - maximumRetainedKeys: Cache capacity in 1...251; default sixteen. A request
    ///     that derives more keys retains only the newest keys within this capacity.
    /// - Throws: `invalidSecret` or `invalidConfiguration`; retains no resources on failure.
    public init(baseSecret: Data, maximumForwardDistance: Int = 8, maximumRetainedKeys: Int = 16) throws {
        guard baseSecret.count == 16 else { throw DAVEError.invalidSecret }
        guard (0...250).contains(maximumForwardDistance), (1...251).contains(maximumRetainedKeys) else { throw DAVEError.invalidConfiguration }
        secret = baseSecret.withUnsafeBytes { Data($0) }
        self.maximumForwardDistance = maximumForwardDistance; self.maximumRetainedKeys = maximumRetainedKeys
    }

    /// Returns a generation's sixteen-byte AES key, deriving at most the configured gap.
    /// - Parameter generation: Absolute generation, including values above 255 after nonce wrap.
    /// - Returns: The same key for repeated requests until explicitly erased.
    /// - Throws: `generationExpired` for erased past generations, `generationTooFarAhead`
    ///   for excessive forward work, or MLS wire encoding errors. Failure is transactional.
    public mutating func key(for generation: UInt32) throws -> Data {
        if let key = keys[generation] { return key }
        guard UInt64(generation) >= nextGeneration else { throw DAVEError.generationExpired }
        guard UInt64(generation) - nextGeneration <= maximumForwardDistance else { throw DAVEError.generationTooFarAhead }
        var candidate = self
        while candidate.nextGeneration <= UInt64(generation) {
            let current = UInt32(candidate.nextGeneration)
            candidate.keys[current] = try Self.derive(secret: candidate.secret, label: "key", generation: current, length: 16)
            candidate.secret = try Self.derive(secret: candidate.secret, label: "secret", generation: current, length: 32)
            candidate.nextGeneration += 1
            if candidate.keys.count > maximumRetainedKeys, let oldest = candidate.keys.keys.min() {
                candidate.keys.removeValue(forKey: oldest)
            }
        }
        self = candidate
        return keys[generation]!
    }

    /// Logically discards cached keys older than an absolute generation.
    /// - Parameter generation: Inclusive lower bound of the keys to retain; zero erases none.
    /// - Note: Erased generations cannot be rederived because parent secrets have been replaced.
    public mutating func erase(before generation: UInt32) {
        keys = keys.filter { $0.key >= generation }
    }

    /// Reports cache size for bounded-resource accounting without exposing secret values.
    public var retainedKeyCount: Int { keys.count }
    /// Redacted diagnostics containing only the retained-key count.
    public var description: String { "DAVEKeyRatchet(keys: \(keys.count), <redacted>)" }
    /// Redacted debug diagnostics containing no secret or derived-key bytes.
    public var debugDescription: String { description }
    /// Redacted reflection prevents accidental key disclosure through `dump`.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }

    /// Applies RFC 9420 KDFLabel framing while accepting DAVE's sixteen-byte initial PRK.
    /// - Parameters:
    ///   - secret: Sixteen-byte initial exporter or thirty-two-byte successor PRK.
    ///   - label: Internal `key` or `secret` purpose without the MLS prefix.
    ///   - generation: Big-endian uint32 DeriveTreeSecret context.
    ///   - length: Internal output size, sixteen or thirty-two bytes.
    /// - Returns: HKDF-SHA256 expansion with no HKDF-Extract step.
    /// - Throws: MLS writer capacity errors; the fixed internal fields always fit.
    private static func derive(secret: Data, label: String, generation: UInt32, length: Int) throws -> Data {
        var context = MLSWriter(); context.write(generation)
        var writer = MLSWriter(); writer.write(UInt16(length))
        try writer.writeVector(Data(("MLS 1.0 " + label).utf8)); try writer.writeVector(context.data)
        let result = HKDF<SHA256>.expand(pseudoRandomKey: secret, info: writer.data, outputByteCount: length)
        return result.withUnsafeBytes { Data($0) }
    }
}
