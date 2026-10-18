import Crypto
import Foundation

/// RFC 9420 cipher suite 0x0002: P-256, HKDF-SHA256, AES-128-GCM, and ECDSA-SHA256.
///
/// These synchronous primitives allocate no tasks or network resources. Secrets are explicit
/// caller-owned bytes; Swift `Data` copies do not provide a guaranteed physical erasure boundary.
/// This implementation has not received an independent cryptographic security audit.
public enum MLSCipherSuite2 {
    /// Cipher suite identifier registered in RFC 9420 section 17.1.
    public static let identifier: UInt16 = 2
    /// SHA-256 output and MLS secret length, in bytes.
    public static let hashLength = 32
    /// AES-128-GCM key length, in bytes.
    public static let keyLength = 16
    /// AES-GCM nonce length, in bytes.
    public static let nonceLength = 12
    /// Per-operation plaintext and additional-data ceiling, in bytes; wire objects may be smaller.
    public static let maximumPayloadBytes = 1_048_576

    /// Hashes exact bytes with SHA-256; no framing or text normalization is applied.
    /// - Parameter data: Arbitrary input, including empty data.
    /// - Returns: The 32-byte digest.
    public static func hash(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// Applies HKDF-Extract with explicitly ordered salt and input material.
    /// - Parameters:
    ///   - salt: HKDF salt; an empty salt follows RFC 5869 zero-padding behavior.
    ///   - ikm: Input key material, including an empty value when specified by the protocol.
    /// - Returns: The 32-byte pseudorandom key.
    public static func extract(salt: Data, ikm: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt)))
    }

    /// Computes the suite's HMAC-SHA256 authentication tag over exact bytes.
    /// - Parameters:
    ///   - key: MAC key owned by the caller.
    ///   - content: Complete authenticated content, including protocol framing where required.
    /// - Returns: A 32-byte tag; does not change ownership of either argument.
    public static func mac(key: Data, content: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: content, using: SymmetricKey(data: key)))
    }

    /// Validates a complete HMAC tag using the cryptographic backend's fixed-time comparison.
    /// - Parameters:
    ///   - key: The expected MAC key.
    ///   - content: Exact authenticated bytes.
    ///   - tag: A received complete 32-byte tag; other lengths return false.
    /// - Returns: Whether the tag authenticates the content.
    public static func verifyMAC(key: Data, content: Data, tag: Data) -> Bool {
        guard tag.count == hashLength else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: content, using: SymmetricKey(data: key))
    }

    /// Expands a suite secret using RFC 9420's prefixed KDFLabel and a UTF-8 label.
    /// - Parameters:
    ///   - secret: A 32-byte HKDF pseudorandom key.
    ///   - label: Protocol label without the `MLS 1.0 ` prefix.
    ///   - context: Exact context bytes, empty when required by the protocol.
    ///   - length: Output length in bytes, from zero through 8160 (HKDF-SHA256's bound).
    /// - Returns: Exactly `length` derived bytes.
    /// - Throws: `MLSError.invalidConfiguration` for a secret or output length violation,
    ///   or a wire encoding capacity error for oversized label/context input.
    public static func expandWithLabel(secret: Data, label: String, context: Data, length: Int) throws -> Data {
        try expandWithLabel(secret: secret, label: Data(label.utf8), context: context, length: length)
    }

    /// Expands a suite secret with an arbitrary byte label, preserving exporter label bytes.
    /// - Parameters:
    ///   - secret: A 32-byte HKDF pseudorandom key.
    ///   - label: Label bytes without the `MLS 1.0 ` prefix; not required to be UTF-8.
    ///   - context: Exact KDF context.
    ///   - length: Requested output bytes in 0...8160.
    /// - Returns: HKDF-Expand output with an MLS KDFLabel.
    /// - Throws: `MLSError.invalidConfiguration` for invalid lengths, or codec capacity errors.
    public static func expandWithLabel(secret: Data, label: Data, context: Data, length: Int) throws -> Data {
        guard secret.count == hashLength, (0...255 * hashLength).contains(length) else {
            throw MLSError.invalidConfiguration
        }
        var writer = MLSWriter()
        writer.write(UInt16(length))
        try writer.writeVector(Data("MLS 1.0 ".utf8) + label)
        try writer.writeVector(context)
        if length == 0 { return Data() }
        let key = HKDF<SHA256>.expand(pseudoRandomKey: secret, info: writer.data, outputByteCount: length)
        return key.withUnsafeBytes { Data($0) }
    }

    /// Derives a new 32-byte secret with an empty context, per RFC 9420 section 8.
    /// - Parameters:
    ///   - secret: A 32-byte parent secret.
    ///   - label: Unprefixed UTF-8 protocol label.
    /// - Returns: The independently labeled derived secret.
    /// - Throws: Invalid-secret or codec-capacity errors; performs no I/O.
    public static func deriveSecret(_ secret: Data, label: String) throws -> Data {
        try expandWithLabel(secret: secret, label: label, context: Data(), length: hashLength)
    }

    /// Derives a ratchet value with a network-byte-order uint32 generation context.
    /// - Parameters:
    ///   - secret: Current 32-byte ratchet secret.
    ///   - label: Ratchet purpose, normally `key`, `nonce`, or `secret`.
    ///   - generation: Exact generation index, including zero.
    ///   - length: Requested output bytes in 0...8160.
    /// - Returns: RFC 9420 section 9.1 DeriveTreeSecret output.
    /// - Throws: Invalid-secret, length, or encoding-capacity errors.
    public static func deriveTreeSecret(_ secret: Data, label: String, generation: UInt32, length: Int) throws -> Data {
        var writer = MLSWriter(); writer.write(generation)
        return try expandWithLabel(secret: secret, label: label, context: writer.data, length: length)
    }

    /// Computes the RFC 9420 section 5.2 reference hash using the exact supplied label.
    /// - Parameters:
    ///   - label: Full reference label; unlike signing/KDF labels this gains no MLS prefix.
    ///   - value: Complete serialized referenced object.
    /// - Returns: The 32-byte hash of the two vector-framed fields.
    /// - Throws: Wire encoding capacity errors for oversized inputs.
    public static func refHash(label: String, value: Data) throws -> Data {
        var writer = MLSWriter()
        try writer.writeVector(Data(label.utf8)); try writer.writeVector(value)
        return hash(writer.data)
    }

    /// Creates an MLS domain-separated DER ECDSA signature using P-256/SHA-256.
    /// - Parameters:
    ///   - privateKey: A valid 32-byte P-256 private scalar.
    ///   - label: Unprefixed MLS signature label, such as `KeyPackage`.
    ///   - content: Exact serialized to-be-signed bytes.
    /// - Returns: A DER-encoded ECDSA signature. Fresh randomness is backend-owned.
    /// - Throws: `MLSError.invalidConfiguration` for an invalid private key or backend failure,
    ///   or a codec capacity error. Error descriptions never include key bytes.
    public static func signWithLabel(privateKey: Data, label: String, content: Data) throws -> Data {
        guard privateKey.count == 32 else { throw MLSError.invalidConfiguration }
        let framed = try labeledContent(label: label, content: content)
        do { return try P256.Signing.PrivateKey(rawRepresentation: privateKey).signature(for: framed).derRepresentation }
        catch { throw MLSError.invalidConfiguration }
    }

    /// Verifies a suite signature over MLS domain-separated content.
    /// - Parameters:
    ///   - publicKey: A valid 65-byte uncompressed P-256 point.
    ///   - label: The exact unprefixed label used to sign.
    ///   - content: Exact signed object bytes.
    ///   - signature: Received DER ECDSA signature.
    /// - Returns: False for invalid keys, malformed signatures, or authentication failure.
    /// - Throws: Codec capacity errors if framing exceeds configured bounds.
    public static func verifyWithLabel(publicKey: Data, label: String, content: Data, signature: Data) throws -> Bool {
        let framed = try labeledContent(label: label, content: content)
        guard publicKey.count == 65, publicKey.first == 4,
              let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
        return key.isValidSignature(parsed, for: framed)
    }

    /// Derives an RFC 9180 DHKEM(P-256, HKDF-SHA256) key pair by rejection sampling.
    /// - Parameter ikm: Nonempty input key material, at most one MiB; MLS supplies a
    ///   32-byte node/external secret.
    /// - Returns: Serialized private scalar and uncompressed public point. Never truncates or
    ///   reduces a candidate modulo the curve order, preserving the RFC's exact derivation.
    /// - Throws: `MLSError.invalidConfiguration` for empty input or exhausted 256 candidates.
    public static func deriveHPKEKeyPair(_ ikm: Data) throws -> MLSHPKEKeyPair {
        guard !ikm.isEmpty, ikm.count <= maximumPayloadBytes else { throw MLSError.invalidConfiguration }
        let suiteID = Data([0x4b, 0x45, 0x4d, 0x00, 0x10])
        let prk = extract(salt: Data(), ikm: Data("HPKE-v1".utf8) + suiteID + Data("dkp_prk".utf8) + ikm)
        for counter in UInt16(0)...255 {
            let info = Data([0, 32]) + Data("HPKE-v1".utf8) + suiteID + Data("candidate".utf8) + Data([UInt8(counter)])
            let candidate = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: info, outputByteCount: 32)
            let bytes = candidate.withUnsafeBytes { Data($0) }
            if let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: bytes) {
                return MLSHPKEKeyPair(privateKey: bytes, publicKey: key.publicKey.x963Representation)
            }
        }
        throw MLSError.invalidConfiguration
    }

    /// Encrypts one independently encapsulated MLS HPKE base-mode message.
    /// - Parameters:
    ///   - publicKey: Recipient's 65-byte uncompressed P-256 HPKE key.
    ///   - label: Unprefixed encryption label, for example `Welcome` or `UpdatePathNode`.
    ///   - context: Exact EncryptContext bytes, which are authenticated as HPKE info.
    ///   - plaintext: Message bytes, at most one MiB; the HPKE authenticated-data input is
    ///     empty by specification.
    /// - Returns: Fresh encapsulated public key and ciphertext with its 16-byte AEAD tag.
    ///   Explicit full-curve key generation matches Swift Crypto's HPKE P-256
    ///   constructor without depending on platform overloads or compact-key filtering.
    /// - Throws: `MLSError.invalidConfiguration` for an invalid recipient or backend failure,
    ///   or a framing capacity error. No keys are included in errors.
    public static func encryptWithLabel(publicKey: Data, label: String, context: Data, plaintext: Data) throws -> MLSHPKECiphertext {
        let info = try labeledContent(label: label, content: context)
        guard publicKey.count == 65, publicKey.first == 4, plaintext.count <= maximumPayloadBytes else { throw MLSError.invalidConfiguration }
        do {
            let key = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
            let ephemeral = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
            let enc = ephemeral.publicKey.x963Representation
            let dh = try ephemeral.sharedSecretFromKeyAgreement(with: key).withUnsafeBytes { Data($0) }
            let shared = try hpkeSharedSecret(dh: dh, kemContext: enc + publicKey)
            let material = try hpkeBaseKeys(sharedSecret: shared, info: info)
            return try MLSHPKECiphertext(kemOutput: enc, ciphertext: seal(key: material.key, nonce: material.nonce, plaintext: plaintext, authenticatedData: Data()))
        } catch { throw MLSError.invalidConfiguration }
    }

    /// Authenticates and decrypts one MLS HPKE base-mode message.
    /// - Parameters:
    ///   - privateKey: Recipient's valid 32-byte private scalar.
    ///   - label: Expected unprefixed label; a mismatch fails authentication.
    ///   - context: Expected exact EncryptContext bytes.
    ///   - encrypted: Encapsulated key and complete ciphertext with tag.
    /// - Returns: Authenticated plaintext only; no unauthenticated bytes escape on failure.
    /// - Throws: `MLSError.authenticationFailed` for invalid keys, tampering, context/label
    ///   mismatch, truncated ciphertext, or backend rejection; codec capacity errors separately.
    public static func decryptWithLabel(privateKey: Data, label: String, context: Data, encrypted: MLSHPKECiphertext) throws -> Data {
        let info = try labeledContent(label: label, content: context)
        guard privateKey.count == 32, encrypted.kemOutput.count == 65, encrypted.kemOutput.first == 4,
              (16...maximumPayloadBytes + 16).contains(encrypted.ciphertext.count) else { throw MLSError.authenticationFailed }
        do {
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
            let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: encrypted.kemOutput)
            let dh = try key.sharedSecretFromKeyAgreement(with: ephemeral).withUnsafeBytes { Data($0) }
            let shared = try hpkeSharedSecret(dh: dh, kemContext: encrypted.kemOutput + key.publicKey.x963Representation)
            let material = try hpkeBaseKeys(sharedSecret: shared, info: info)
            return try open(key: material.key, nonce: material.nonce, ciphertext: encrypted.ciphertext, authenticatedData: Data())
        } catch { throw MLSError.authenticationFailed }
    }

    /// Encrypts AES-128-GCM content without placing the nonce in the returned bytes.
    /// - Parameters:
    ///   - key: Exactly 16 key bytes.
    ///   - nonce: Exactly 12 nonce bytes; caller must ensure uniqueness for this key.
    ///   - plaintext: Exact plaintext content, including empty messages, at most one MiB.
    ///   - authenticatedData: Additional authenticated bytes, never encrypted, at most one MiB.
    /// - Returns: Ciphertext followed by a 16-byte tag, in RFC 5116 format.
    /// - Throws: `MLSError.invalidConfiguration` for key/nonce sizes or backend failure.
    public static func seal(key: Data, nonce: Data, plaintext: Data, authenticatedData: Data) throws -> Data {
        guard key.count == keyLength, nonce.count == nonceLength, plaintext.count <= maximumPayloadBytes,
              authenticatedData.count <= maximumPayloadBytes else { throw MLSError.invalidConfiguration }
        do {
            let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: authenticatedData)
            var result = Data()
            result.append(box.ciphertext); result.append(box.tag)
            return result
        } catch { throw MLSError.invalidConfiguration }
    }

    /// Authenticates AES-128-GCM ciphertext before returning plaintext.
    /// - Parameters:
    ///   - key: Exactly 16 key bytes.
    ///   - nonce: Exactly 12 nonce bytes matching encryption.
    ///   - ciphertext: Ciphertext of at most one MiB followed by a 16-byte authentication tag.
    ///   - authenticatedData: Exact AAD used during encryption, at most one MiB.
    /// - Returns: Authenticated plaintext, including an empty result for a valid empty message.
    /// - Throws: `MLSError.authenticationFailed` for size, tamper, AAD, or backend failures.
    public static func open(key: Data, nonce: Data, ciphertext: Data, authenticatedData: Data) throws -> Data {
        guard key.count == keyLength, nonce.count == nonceLength,
              (16...maximumPayloadBytes + 16).contains(ciphertext.count), authenticatedData.count <= maximumPayloadBytes else { throw MLSError.authenticationFailed }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext.dropLast(16), tag: ciphertext.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: authenticatedData)
        } catch { throw MLSError.authenticationFailed }
    }

    /// Applies RFC 9180 LabeledExtract for a specified KEM or complete HPKE suite.
    /// - Parameters:
    ///   - salt: Extract salt, empty where the RFC supplies an empty string.
    ///   - suiteID: Exact RFC suite identifier including its ASCII domain marker.
    ///   - label: RFC label, without the `HPKE-v1` prefix.
    ///   - ikm: Exact input key material.
    /// - Returns: A 32-byte pseudorandom key; no state is retained.
    private static func hpkeExtract(salt: Data, suiteID: Data, label: String, ikm: Data) -> Data {
        extract(salt: salt, ikm: Data("HPKE-v1".utf8) + suiteID + Data(label.utf8) + ikm)
    }

    /// Applies RFC 9180 LabeledExpand to fixed internal protocol lengths.
    /// - Parameters:
    ///   - prk: Exactly 32 extracted bytes.
    ///   - suiteID: Exact RFC suite identifier.
    ///   - label: Unprefixed RFC label.
    ///   - info: Exact labeled expansion context.
    ///   - length: Output byte count from 1 through 8160.
    /// - Returns: The requested HKDF-Expand bytes.
    /// - Throws: `MLSError.invalidConfiguration` if an internal size invariant is violated.
    private static func hpkeExpand(prk: Data, suiteID: Data, label: String, info: Data, length: Int) throws -> Data {
        guard prk.count == 32, (1...8160).contains(length) else { throw MLSError.invalidConfiguration }
        let framed = Data([UInt8(length >> 8), UInt8(truncatingIfNeeded: length)]) + Data("HPKE-v1".utf8) + suiteID + Data(label.utf8) + info
        return HKDF<SHA256>.expand(pseudoRandomKey: prk, info: framed, outputByteCount: length).withUnsafeBytes { Data($0) }
    }

    /// Derives the DHKEM shared secret from ECDH output and recipient-bound KEM context.
    /// - Parameters:
    ///   - dh: Validated P-256 ECDH shared bytes from Swift Crypto.
    ///   - kemContext: Encapsulated point followed by recipient point, in base-mode order.
    /// - Returns: The 32-byte RFC 9180 DHKEM shared secret.
    /// - Throws: Internal derivation-size invariant errors.
    private static func hpkeSharedSecret(dh: Data, kemContext: Data) throws -> Data {
        let suiteID = Data([0x4b, 0x45, 0x4d, 0, 0x10])
        let eae = hpkeExtract(salt: Data(), suiteID: suiteID, label: "eae_prk", ikm: dh)
        return try hpkeExpand(prk: eae, suiteID: suiteID, label: "shared_secret", info: kemContext, length: 32)
    }

    /// Derives the RFC 9180 base-mode sequence-zero key and nonce for a single-shot seal.
    /// - Parameters:
    ///   - sharedSecret: The 32-byte DHKEM shared secret.
    ///   - info: MLS EncryptContext bytes; authenticated by the HPKE schedule.
    /// - Returns: AES-128 key and 12-byte nonce. No exporter or subsequent sequence is retained.
    /// - Throws: Internal HKDF-size errors; no backend state survives the call.
    private static func hpkeBaseKeys(sharedSecret: Data, info: Data) throws -> (key: Data, nonce: Data) {
        let suiteID = Data([0x48, 0x50, 0x4b, 0x45, 0, 0x10, 0, 1, 0, 1])
        let pskHash = hpkeExtract(salt: Data(), suiteID: suiteID, label: "psk_id_hash", ikm: Data())
        let infoHash = hpkeExtract(salt: Data(), suiteID: suiteID, label: "info_hash", ikm: info)
        let context = Data([0]) + pskHash + infoHash
        let secret = hpkeExtract(salt: sharedSecret, suiteID: suiteID, label: "secret", ikm: Data())
        return try (hpkeExpand(prk: secret, suiteID: suiteID, label: "key", info: context, length: 16),
                    hpkeExpand(prk: secret, suiteID: suiteID, label: "base_nonce", info: context, length: 12))
    }

    /// Frames the common MLS signing/encryption domain separation structure.
    /// - Parameters:
    ///   - label: Unprefixed UTF-8 label.
    ///   - content: Exact second field, used as signed content or HPKE context.
    /// - Returns: Canonically vector-framed label and content.
    /// - Throws: Wire capacity errors; no external work occurs.
    private static func labeledContent(label: String, content: Data) throws -> Data {
        var writer = MLSWriter()
        try writer.writeVector(Data(("MLS 1.0 " + label).utf8)); try writer.writeVector(content)
        return writer.data
    }
}

/// Explicitly owned serialized HPKE key pair; diagnostics redact private material.
public struct MLSHPKEKeyPair: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Caller-owned 32-byte private scalar; never log or transmit it.
    public let privateKey: Data
    /// Uncompressed 65-byte P-256 public point.
    public let publicKey: Data
    /// Constructs serialized key material produced by the suite derivation.
    /// - Parameters:
    ///   - privateKey: Private scalar bytes; validation occurs when used by the crypto backend.
    ///   - publicKey: Matching public point, validated by the caller when independently supplied.
    public init(privateKey: Data, publicKey: Data) { self.privateKey = privateKey; self.publicKey = publicKey }
    /// Redacted diagnostic representation; never includes either key's bytes.
    public var description: String { "MLSHPKEKeyPair(<redacted>)" }
    /// Redacted debug representation, matching ordinary diagnostics.
    public var debugDescription: String { description }
    /// Redacted reflection excludes every retained secret from `dump` and mirror diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }
}

/// RFC 9420 HPKECiphertext fields; does not expose plaintext or private keys.
public struct MLSHPKECiphertext: Sendable, Equatable {
    /// HPKE encapsulated public key, serialized as an uncompressed P-256 point.
    public let kemOutput: Data
    /// Ciphertext followed by its authentication tag.
    public let ciphertext: Data
    /// Creates an untrusted ciphertext container for subsequent authenticated decoding.
    /// - Parameters:
    ///   - kemOutput: Received encapsulated key; structural validation occurs when decrypted.
    ///   - ciphertext: Received ciphertext and tag; never trusted before authentication.
    public init(kemOutput: Data, ciphertext: Data) { self.kemOutput = kemOutput; self.ciphertext = ciphertext }
}

/// RFC 9420 section 8 epoch key schedule, including Welcome and exporter branches.
///
/// Callers must promptly discard the schedule once secret-tree operation starts, retaining
/// only secrets still required for the epoch. Value copies and `Data` cannot guarantee erasure.
public struct MLSKeySchedule: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Commit-derived secret distributed to authorized joining members; empty at group creation.
    public let joinerSecret: Data
    /// Welcome branch used to encrypt GroupInfo; empty at fresh group creation.
    public let welcomeSecret: Data
    /// Root 32-byte secret for this epoch; discard when its required branches are materialized.
    public let epochSecret: Data
    /// Secret retained for deriving the next authenticated epoch.
    public let initSecret: Data
    /// Epoch secret branch for private-message sender metadata encryption.
    public let senderDataSecret: Data
    /// Secret-tree root; discard after the secret-tree owner adopts it.
    public let encryptionSecret: Data
    /// Epoch-bound application exporter root.
    public let exporterSecret: Data
    /// Root used to derive the external HPKE key pair.
    public let externalSecret: Data
    /// Key authenticating the confirmed transcript hash.
    public let confirmationKey: Data
    /// Key authenticating member public messages.
    public let membershipKey: Data
    /// Epoch resumption secret; retention requires a separately bounded caller policy.
    public let resumptionPSK: Data
    /// Epoch-view authenticator for an application-managed out-of-band comparison.
    public let epochAuthenticator: Data

    /// Advances the prior epoch's initialization secret using a commit and optional PSK secret.
    /// - Parameters:
    ///   - initSecret: Exactly 32 initialization bytes from the previous epoch.
    ///   - commitSecret: Exactly 32 commit bytes; all-zero when the RFC permits an absent path.
    ///   - pskSecret: Exactly 32 aggregated PSK bytes; defaults to the RFC all-zero no-PSK value.
    ///   - groupContext: Exact canonical serialized new GroupContext, authenticated by the caller.
    /// - Throws: `MLSError.invalidConfiguration` for incorrect secret sizes, or encoding errors.
    public init(initSecret: Data, commitSecret: Data, pskSecret: Data = Data(repeating: 0, count: 32), groupContext: Data) throws {
        guard initSecret.count == 32, commitSecret.count == 32 else { throw MLSError.invalidConfiguration }
        let extracted = MLSCipherSuite2.extract(salt: initSecret, ikm: commitSecret)
        let joiner = try MLSCipherSuite2.expandWithLabel(secret: extracted, label: "joiner", context: groupContext, length: 32)
        try self.init(joinerSecret: joiner, pskSecret: pskSecret, groupContext: groupContext)
    }

    /// Initializes a joining member's key schedule from its authenticated Welcome secret.
    /// - Parameters:
    ///   - joinerSecret: Exactly 32 bytes decrypted from GroupSecrets.
    ///   - pskSecret: Exactly 32 aggregated PSK bytes, defaulting to zero for no PSKs.
    ///   - groupContext: Exact canonical context from authenticated GroupInfo.
    /// - Throws: Invalid-secret or wire-encoding errors. GroupInfo authentication remains caller-owned.
    public init(joinerSecret: Data, pskSecret: Data = Data(repeating: 0, count: 32), groupContext: Data) throws {
        guard joinerSecret.count == 32, pskSecret.count == 32 else { throw MLSError.invalidConfiguration }
        let member = MLSCipherSuite2.extract(salt: joinerSecret, ikm: pskSecret)
        let epoch = try MLSCipherSuite2.expandWithLabel(secret: member, label: "epoch", context: groupContext, length: 32)
        try self.init(epochSecret: epoch, joinerSecret: joinerSecret, welcomeSecret: MLSCipherSuite2.deriveSecret(member, label: "welcome"))
    }

    /// Creates an initial group from the fresh random epoch secret required by RFC 9420 section 11.
    /// - Parameter epochSecret: Exactly 32 cryptographically random bytes from an injected owner.
    /// - Throws: `MLSError.invalidConfiguration` for an incorrect length.
    /// - Note: Joiner and Welcome secrets are empty because group creation has neither branch.
    public init(epochSecret: Data) throws { try self.init(epochSecret: epochSecret, joinerSecret: Data(), welcomeSecret: Data()) }

    /// Derives the named epoch branches after validating the epoch secret.
    /// - Parameters:
    ///   - epochSecret: Exactly 32 secret bytes.
    ///   - joinerSecret: Joiner branch bytes, or empty for a fresh group.
    ///   - welcomeSecret: Welcome branch bytes, or empty for a fresh group.
    /// - Throws: Invalid-secret or encoding errors; no external effects occur.
    private init(epochSecret: Data, joinerSecret: Data, welcomeSecret: Data) throws {
        guard epochSecret.count == 32 else { throw MLSError.invalidConfiguration }
        self.epochSecret = epochSecret; self.joinerSecret = joinerSecret; self.welcomeSecret = welcomeSecret
        initSecret = try MLSCipherSuite2.deriveSecret(epochSecret, label: "init")
        senderDataSecret = try MLSCipherSuite2.deriveSecret(epochSecret, label: "sender data")
        encryptionSecret = try MLSCipherSuite2.deriveSecret(epochSecret, label: "encryption")
        exporterSecret = try MLSCipherSuite2.deriveSecret(epochSecret, label: "exporter")
        externalSecret = try MLSCipherSuite2.deriveSecret(epochSecret, label: "external")
        confirmationKey = try MLSCipherSuite2.deriveSecret(epochSecret, label: "confirm")
        membershipKey = try MLSCipherSuite2.deriveSecret(epochSecret, label: "membership")
        resumptionPSK = try MLSCipherSuite2.deriveSecret(epochSecret, label: "resumption")
        epochAuthenticator = try MLSCipherSuite2.deriveSecret(epochSecret, label: "authentication")
    }

    /// Exports an application secret bound to this epoch, label, and hashed context.
    /// - Parameters:
    ///   - label: Application-specific UTF-8 purpose without an MLS prefix.
    ///   - context: Application context, hashed using the suite hash before expansion.
    ///   - length: Output bytes in 0...8160.
    /// - Returns: RFC 9420 MLS-Exporter output; callers own storage and erasure.
    /// - Throws: Invalid length or encoding-capacity errors.
    public func export(label: String, context: Data, length: Int) throws -> Data {
        try export(label: Data(label.utf8), context: context, length: length)
    }

    /// Exports using arbitrary application label bytes without text re-encoding.
    /// - Parameters:
    ///   - label: Exact application label bytes.
    ///   - context: Exact application context bytes, hashed before expansion.
    ///   - length: Output bytes in 0...8160.
    /// - Returns: Exported secret bound to this epoch and purpose.
    /// - Throws: Invalid length or encoding-capacity errors.
    public func export(label: Data, context: Data, length: Int) throws -> Data {
        let derived = try MLSCipherSuite2.expandWithLabel(secret: exporterSecret, label: label, context: Data(), length: 32)
        return try MLSCipherSuite2.expandWithLabel(secret: derived, label: "exported", context: MLSCipherSuite2.hash(context), length: length)
    }

    /// Redacts all schedule branches from ordinary diagnostics.
    public var description: String { "MLSKeySchedule(<redacted>)" }
    /// Redacts all schedule branches from debug diagnostics.
    public var debugDescription: String { description }
    /// Redacted reflection excludes every retained secret from `dump` and mirror diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["secret": "<redacted>"]) }
}
