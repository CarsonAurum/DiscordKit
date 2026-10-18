import Foundation

/// Public RFC Welcome fields. The encrypted bytes reveal no authenticated secrets
/// until the single-use key-package owner validates the complete group state.
struct MLSWelcome: Sendable {
    let secrets: [(reference: Data, encrypted: MLSHPKECiphertext)]
    let encryptedGroupInfo: Data

    /// Wraps ciphersuite 2 Welcome in an MLS 1.0 message.
    /// - Returns: Complete canonical message with at most 1024 addressed recipients.
    /// - Throws: `capacityExceeded` for excessive recipients or encoded bytes.
    func encoded() throws -> Data {
        guard !secrets.isEmpty, secrets.count <= 1024 else { throw MLSError.capacityExceeded }
        var writer = MLSWriter(); writer.write(UInt16(1)); writer.write(UInt16(3)); writer.write(UInt16(2))
        var recipients = MLSWriter()
        for entry in secrets {
            try recipients.writeVector(entry.reference); try recipients.writeVector(entry.encrypted.kemOutput)
            try recipients.writeVector(entry.encrypted.ciphertext)
        }
        try writer.writeVector(recipients.data); try writer.writeVector(encryptedGroupInfo); return writer.data
    }

    /// Parses a complete Welcome without decrypting or publishing candidate state.
    /// - Parameter data: Complete MLSMessage within the one-MiB maximum.
    /// - Returns: Ciphersuite-2 Welcome with unique complete recipient references.
    /// - Throws: Version/suite/wire errors, or `invalidCommit` for wrong message type.
    static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data)
        guard try reader.readUInt16() == 1 else { throw MLSError.unsupportedVersion }
        guard try reader.readUInt16() == 3 else { throw MLSError.invalidCommit }
        guard try reader.readUInt16() == 2 else { throw MLSError.unsupportedCipherSuite }
        var recipients = try MLSReader(reader.readVector())
        var secrets: [(reference: Data, encrypted: MLSHPKECiphertext)] = []
        var references: Set<Data> = []
        while !recipients.isAtEnd {
            guard secrets.count < 1024 else { throw MLSError.capacityExceeded }
            let reference = try recipients.readVector()
            guard reference.count == 32, references.insert(reference).inserted else { throw MLSError.malformedEncoding }
            let encapsulation = try recipients.readVector(); let ciphertext = try recipients.readVector()
            guard encapsulation.count == 65, ciphertext.count >= 16 else { throw MLSError.malformedEncoding }
            secrets.append((reference, MLSHPKECiphertext(kemOutput: encapsulation, ciphertext: ciphertext)))
        }
        guard !secrets.isEmpty else { throw MLSError.malformedEncoding }
        let encryptedGroupInfo = try reader.readVector(); try reader.requireEnd()
        return Self(secrets: secrets, encryptedGroupInfo: encryptedGroupInfo)
    }
}

/// Signed public state encrypted inside Welcome. Ratchet-tree extension is mandatory
/// for this profile; GroupInfo extensions remain extensible per RFC 9420 Section 13.
struct MLSGroupInfo: Sendable {
    let context: MLSGroupContext
    let extensions: [MLSExtension]
    let confirmationTag: Data
    let signer: UInt32
    var signature = Data()

    /// Encodes all authenticated fields except the signature itself.
    /// - Returns: GroupInfoTBS bytes to sign under the RFC GroupInfoTBS label.
    /// - Throws: Bounded encoding errors.
    func signatureInput() throws -> Data {
        var writer = MLSWriter(); try writer.writeRaw(context.encoded())
        try writer.writeRaw(MLSExtension.encodeList(extensions)); try writer.writeVector(confirmationTag)
        writer.write(signer); return writer.data
    }

    /// Appends the signature to its exact signed input.
    /// - Returns: GroupInfo bytes without an MLSMessage wrapper.
    /// - Throws: Bounded encoding errors.
    func encoded() throws -> Data {
        var writer = MLSWriter(); try writer.writeRaw(signatureInput()); try writer.writeVector(signature); return writer.data
    }

    /// Parses a decrypted candidate GroupInfo, without treating it as authenticated.
    /// - Parameter data: AEAD-opened candidate bytes, still requiring signature/tree checks.
    /// - Returns: Structurally complete GroupInfo; unknown information extensions survive.
    /// - Throws: Wire errors or `malformedEncoding` for invalid signature/MAC lengths.
    static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let context = try MLSGroupContext.decode(&reader)
        let extensions = try MLSExtension.decodeList(&reader); let confirmation = try reader.readVector()
        let signer = try reader.readUInt32(); let signature = try reader.readVector(); try reader.requireEnd()
        guard confirmation.count == 32, !signature.isEmpty, signature.count <= 80,
              context.epoch == 0 || context.confirmedTranscriptHash.count == 32 else { throw MLSError.malformedEncoding }
        return Self(context: context, extensions: extensions, confirmationTag: confirmation, signer: signer, signature: signature)
    }
}

/// Secret payload HPKE-encrypted to a single joining key package. This profile has
/// no PSKs and rejects PSK-bearing Welcomes rather than silently omitting them.
struct MLSWelcomeSecrets: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let joinerSecret: Data
    let pathSecret: Data?
    /// Redacts joiner/path secrets from ordinary diagnostic formatting.
    var description: String { "MLSWelcomeSecrets([REDACTED])" }
    /// Uses the same fixed redaction for debug formatting.
    var debugDescription: String { description }
    /// Excludes private decoded GroupSecrets from mirror traversal and `dump`.
    var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Encodes joiner/path secrets and the required empty PSK list.
    /// - Returns: GroupSecrets bytes; callers must not log or persist this temporary buffer.
    /// - Throws: `invalidCommit` for incorrect secret sizes or encoding errors.
    func encoded() throws -> Data {
        guard joinerSecret.count == 32, pathSecret == nil || pathSecret?.count == 32 else { throw MLSError.invalidCommit }
        var writer = MLSWriter(); try writer.writeVector(joinerSecret)
        writer.write(UInt8(pathSecret == nil ? 0 : 1))
        if let pathSecret { try writer.writeVector(pathSecret) }
        try writer.writeVector(Data()); return writer.data
    }

    /// Parses the no-PSK GroupSecrets required for DAVE v1.
    /// - Parameter data: Authenticated HPKE plaintext from the matching init key.
    /// - Returns: Candidate secret material, never exposed by public group APIs.
    /// - Throws: `invalidCommit` for PSKs/secret sizes, or malformed encoding.
    static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let joiner = try reader.readVector(); let present = try reader.readUInt8()
        guard present <= 1 else { throw MLSError.malformedEncoding }
        let path = try present == 1 ? reader.readVector() : nil
        guard try reader.readVector().isEmpty, joiner.count == 32, path == nil || path?.count == 32 else { throw MLSError.invalidCommit }
        try reader.requireEnd(); return Self(joinerSecret: joiner, pathSecret: path)
    }
}

/// Computes transcript state after authenticating the current commit confirmation.
/// - Parameters:
///   - confirmed: The new confirmed hash, or empty only at initial epoch zero.
///   - confirmation: Exactly one confirmation MAC, already computed or verified.
/// - Returns: SHA-256 of the confirmed hash and its encoded confirmation vector.
/// - Throws: Bounded encoding errors; no input is retained.
func mlsInterimTranscript(confirmed: Data, confirmation: Data) throws -> Data {
    var writer = MLSWriter(); try writer.writeVector(confirmation)
    return MLSCipherSuite2.hash(confirmed + writer.data)
}

/// Finds the first shared nonblank node on two leaf direct paths for Welcome.
/// - Parameters:
///   - tree: Final public tree, with the committer's new parent nodes installed.
///   - sender: Commit author's leaf index.
///   - recipient: New member's leaf index, distinct from the author.
/// - Returns: Lowest common ancestor with key material; nil for no shared path.
/// - Throws: `invalidTree` for equal, blank or out-of-range leaf indices, before
///   multiplying indices; tree-math validation errors for an inconsistent tree.
func mlsCommonAncestor(tree: MLSRatchetTree, sender: UInt32, recipient: UInt32) throws -> UInt32? {
    guard sender != recipient, UInt64(sender) < UInt64(tree.leafCount), UInt64(recipient) < UInt64(tree.leafCount),
          tree.leaf(at: sender) != nil, tree.leaf(at: recipient) != nil else { throw MLSError.invalidTree }
    let recipients = Set(try MLSTreeMath.directPath(recipient * 2, leafCount: tree.leafCount))
    return try tree.filteredDirectPath(for: sender).first(where: { recipients.contains($0) && tree.encryptionKey(at: $0) != nil })
}
