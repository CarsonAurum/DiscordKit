// File: Sources/DiscordMLS/MLSCredentials.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import Foundation

/// RFC 9420 basic credential: an assertion that an application must authenticate.
///
/// A valid leaf signature proves possession of the asserted signing key. It does
/// not establish that the key belongs to the identity. Callers must bind this pair
/// to their trusted authentication service before admitting a member.
public struct MLSCredential: Sendable, Equatable {
    public let identity: Data

    /// Creates a bounded basic credential without contacting an authentication service.
    /// - Parameter identity: Nonempty application identity, at most 1024 opaque bytes.
    /// - Throws: `invalidCredential` for an empty or excessive identity.
    public init(identity: Data) throws {
        guard !identity.isEmpty, identity.count <= 1024 else { throw MLSError.invalidCredential }
        self.identity = identity
    }

    /// Creates the exact eight-byte big-endian Discord DAVE basic identity.
    /// - Parameter userID: Nonzero authenticated Discord snowflake; large IDs are preserved.
    /// - Returns: A basic credential with no textual/JSON identity conversion.
    /// - Throws: `invalidCredential` for zero.
    public static func discord(userID: UInt64) throws -> Self {
        guard userID != 0 else { throw MLSError.invalidCredential }
        var writer = MLSWriter(); writer.write(userID); return try Self(identity: writer.data)
    }

    /// Encodes basic credential type 1 and its opaque identity vector.
    /// - Returns: RFC 9420 Credential bytes.
    /// - Throws: Capacity errors from the bounded encoder.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); try writer.writeVector(identity); return writer.data
    }

    /// Decodes a basic credential from a containing object.
    /// - Parameter reader: Cursor advanced through credential type and identity.
    /// - Returns: A structurally valid basic credential, still requiring external authentication.
    /// - Throws: `invalidCredential` for non-basic types/identities, or wire errors.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        guard try reader.readUInt16() == 1 else { throw MLSError.invalidCredential }
        return try Self(identity: reader.readVector())
    }
}

/// Leaf validity interval as unsigned Unix seconds; evaluation uses an injected clock.
public struct MLSLifetime: Sendable, Equatable {
    public let notBefore: UInt64
    public let notAfter: UInt64

    /// Stores an interval whose ordering is checked when the leaf is constructed.
    /// - Parameters:
    ///   - notBefore: Inclusive earliest Unix second.
    ///   - notAfter: Inclusive latest Unix second, which must not precede `notBefore`.
    public init(notBefore: UInt64, notAfter: UInt64) { self.notBefore = notBefore; self.notAfter = notAfter }
}

/// RFC 9420 feature advertisements, retaining unknown/GREASE values.
public struct MLSCapabilities: Sendable, Equatable {
    public let versions: [UInt16]
    public let cipherSuites: [UInt16]
    public let extensions: [UInt16]
    public let proposals: [UInt16]
    public let credentials: [UInt16]

    /// Advertises explicitly supported versions, suites, and credential types.
    /// - Parameters:
    ///   - versions: Unique protocol versions; default MLS 1.0.
    ///   - cipherSuites: Unique cipher suites; default suite 2.
    ///   - extensions: Unique nondefault extension IDs; RFC default IDs 1...5 are prohibited.
    ///   - proposals: Unique nondefault proposal IDs; default IDs 1...7 are prohibited.
    ///   - credentials: Unique credential IDs; default basic credential 1.
    /// - Throws: `invalidConfiguration` for duplicates, prohibited defaults, missing
    ///   mandatory advertisements, or more than 128 entries per list.
    public init(versions: [UInt16] = [1], cipherSuites: [UInt16] = [2],
                extensions: [UInt16] = [], proposals: [UInt16] = [], credentials: [UInt16] = [1]) throws {
        for list in [versions, cipherSuites, extensions, proposals, credentials] {
            guard list.count <= 128, Set(list).count == list.count else { throw MLSError.invalidConfiguration }
        }
        guard versions.contains(1), cipherSuites.contains(2), credentials.contains(1),
              !extensions.contains(where: { (1...5).contains($0) }),
              !proposals.contains(where: { (1...7).contains($0) }) else { throw MLSError.invalidConfiguration }
        self.versions = versions; self.cipherSuites = cipherSuites; self.extensions = extensions
        self.proposals = proposals; self.credentials = credentials
    }

    /// Serializes the five canonical vectors of sixteen-bit capability identifiers.
    /// - Returns: RFC 9420 Capabilities bytes in declaration order.
    /// - Throws: Encoder capacity errors.
    public func encoded() throws -> Data {
        var writer = MLSWriter()
        for list in [versions, cipherSuites, extensions, proposals, credentials] {
            var body = MLSWriter(); for value in list { body.write(value) }; try writer.writeVector(body.data)
        }
        return writer.data
    }

    /// Parses bounded capabilities, preserving unknown values but rejecting malformed lists.
    /// - Parameter reader: Cursor advanced through all five vectors.
    /// - Returns: Structurally valid suite-2/basic capability advertisement.
    /// - Throws: Wire errors or `invalidConfiguration` for incompatible advertisements.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        var lists: [[UInt16]] = []
        for _ in 0..<5 {
            var body = try MLSReader(reader.readVector()); var list: [UInt16] = []
            guard body.remainingCount <= 256, body.remainingCount.isMultiple(of: 2) else { throw MLSError.malformedEncoding }
            while !body.isAtEnd { list.append(try body.readUInt16()) }; lists.append(list)
        }
        return try Self(versions: lists[0], cipherSuites: lists[1], extensions: lists[2], proposals: lists[3], credentials: lists[4])
    }

    /// Checks a GroupContext required_capabilities extension against this advertisement.
    /// - Parameter data: Three canonical vectors of required extension, proposal, and credential IDs.
    /// - Throws: `invalidCredential` for unsupported required capabilities, or wire errors.
    ///   RFC default extensions/proposals are implicit; credential support is always explicit.
    public func validateRequired(_ data: Data) throws {
        var reader = try MLSReader(data)
        for (index, supported) in [extensions, proposals, credentials].enumerated() {
            var body = try MLSReader(reader.readVector())
            guard body.remainingCount <= 256, body.remainingCount.isMultiple(of: 2) else { throw MLSError.malformedEncoding }
            while !body.isAtEnd {
                let value = try body.readUInt16()
                let isDefault = (index == 0 && (1...5).contains(value)) || (index == 1 && (1...7).contains(value))
                guard isDefault || supported.contains(value) else { throw MLSError.invalidCredential }
            }
        }
        try reader.requireEnd()
    }
}

/// Signature context selector from RFC 9420, Section 7.2.
public enum MLSLeafNodeSource: UInt8, Sendable { case keyPackage = 1, update = 2, commit = 3 }

/// Signed RFC 9420 suite-2 leaf, with immutable authenticated fields.
public struct MLSLeafNode: Sendable, Equatable {
    public let encryptionKey: Data
    public let signatureKey: Data
    public let credential: MLSCredential
    public let capabilities: MLSCapabilities
    public let source: MLSLeafNodeSource
    public let lifetime: MLSLifetime?
    public let parentHash: Data?
    public let extensions: [MLSExtension]
    public let signature: Data

    /// Creates a structurally checked leaf; call `validate` before admission.
    /// - Parameters:
    ///   - encryptionKey: Valid uncompressed P-256 HPKE public key, 65 bytes.
    ///   - signatureKey: Valid uncompressed P-256 ECDSA public key, 65 bytes.
    ///   - credential: Application-authenticated basic identity assertion.
    ///   - capabilities: Explicit compatible capabilities; defaults to suite-2/basic.
    ///   - source: Key-package, update, or commit signature context.
    ///   - lifetime: Required only for key-package leaves; interval must be ordered.
    ///   - parentHash: Required only for commit leaves; empty for a one-member tree or SHA-256 sized.
    ///   - extensions: Unique extensions; nondefault types must be advertised.
    ///   - signature: DER ECDSA signature, or empty while preparing a leaf for signing.
    /// - Throws: `invalidCredential` for invalid keys, source-specific fields, or
    ///   capabilities; extension wire/capacity errors for excessive/duplicate lists.
    ///   This initializer neither signs nor authenticates the object.
    public init(encryptionKey: Data, signatureKey: Data, credential: MLSCredential,
                capabilities: MLSCapabilities? = nil, source: MLSLeafNodeSource = .keyPackage,
                lifetime: MLSLifetime? = nil, parentHash: Data? = nil,
                extensions: [MLSExtension] = [], signature: Data = Data()) throws {
        guard encryptionKey.count == 65, signatureKey.count == 65,
              (try? P256.KeyAgreement.PublicKey(x963Representation: encryptionKey)) != nil,
              (try? P256.Signing.PublicKey(x963Representation: signatureKey)) != nil,
              signature.count <= 80 else { throw MLSError.invalidCredential }
        let capabilities = try capabilities ?? MLSCapabilities()
        switch source {
        case .keyPackage:
            guard let lifetime, lifetime.notBefore <= lifetime.notAfter, parentHash == nil else { throw MLSError.invalidCredential }
        case .update:
            guard lifetime == nil, parentHash == nil else { throw MLSError.invalidCredential }
        case .commit:
            guard lifetime == nil, let parentHash, parentHash.isEmpty || parentHash.count == 32 else { throw MLSError.invalidCredential }
        }
        for item in extensions where !(1...5).contains(item.type) {
            guard capabilities.extensions.contains(item.type) else { throw MLSError.invalidCredential }
        }
        _ = try MLSExtension.encodeList(extensions)
        self.encryptionKey = encryptionKey; self.signatureKey = signatureKey; self.credential = credential
        self.capabilities = capabilities; self.source = source; self.lifetime = lifetime
        self.parentHash = parentHash; self.extensions = extensions; self.signature = signature
    }

    /// Constructs and signs a leaf from caller-owned keys, without generating randomness.
    /// - Parameters:
    ///   - identity: Nonempty basic identity, externally authenticated by the caller.
    ///   - signaturePrivateKey: Thirty-two-byte P-256 signing scalar.
    ///   - encryptionKey: Uncompressed P-256 HPKE public key; its private part stays with the caller.
    ///   - source: Leaf context; defaults to a publishable key-package leaf.
    ///   - lifetime: Key-package lifetime, defaulting to the full unsigned interval
    ///     required by DAVE; use nil for update/commit leaves.
    ///   - parentHash: Commit leaf parent hash; nil otherwise.
    ///   - groupID: Required group binding for update/commit leaves, absent for key-package leaves.
    ///   - leafIndex: Required leaf binding for update/commit leaves, absent otherwise.
    /// - Returns: A signed immutable leaf.
    /// - Throws: Key, credential, context, or signing errors. No key material is persisted.
    public static func generate(identity: Data, signaturePrivateKey: Data, encryptionKey: Data,
                                source: MLSLeafNodeSource = .keyPackage,
                                lifetime: MLSLifetime? = MLSLifetime(notBefore: 0, notAfter: .max),
                                parentHash: Data? = nil, groupID: Data? = nil, leafIndex: UInt32? = nil) throws -> Self {
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(rawRepresentation: signaturePrivateKey) }
        catch { throw MLSError.invalidCredential }
        let leaf = try Self(encryptionKey: encryptionKey, signatureKey: key.publicKey.x963Representation,
                            credential: MLSCredential(identity: identity), source: source, lifetime: lifetime, parentHash: parentHash)
        return try leaf.signed(privateKey: signaturePrivateKey, groupID: groupID, leafIndex: leafIndex)
    }

    /// Serializes all leaf fields except signature and optional group signature binding.
    /// - Returns: RFC LeafNode bytes before the signature vector.
    /// - Throws: Wire capacity errors from encoded fields/extensions.
    private func unsignedEncoding() throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(encryptionKey); try writer.writeVector(signatureKey)
        try writer.writeRaw(credential.encoded()); try writer.writeRaw(capabilities.encoded()); writer.write(source.rawValue)
        switch source {
        case .keyPackage:
            guard let lifetime else { throw MLSError.invalidCredential }
            writer.write(lifetime.notBefore); writer.write(lifetime.notAfter)
        case .update: break
        case .commit:
            guard let parentHash else { throw MLSError.invalidCredential }; try writer.writeVector(parentHash)
        }
        try writer.writeRaw(MLSExtension.encodeList(extensions)); return writer.data
    }

    /// Creates the exact RFC LeafNodeTBS signature input, including group/index binding.
    /// - Parameters:
    ///   - groupID: Nonempty group identifier for update/commit; nil for key packages.
    ///   - leafIndex: Group-relative leaf index for update/commit; nil for key packages.
    /// - Returns: Unsigned leaf bytes and source-specific signature context.
    /// - Throws: `invalidCredential` for missing/unexpected context, or wire errors.
    public func signatureInput(groupID: Data? = nil, leafIndex: UInt32? = nil) throws -> Data {
        var writer = MLSWriter(); try writer.writeRaw(unsignedEncoding())
        if source == .keyPackage {
            guard groupID == nil, leafIndex == nil else { throw MLSError.invalidCredential }
        } else {
            guard let groupID, !groupID.isEmpty, groupID.count <= 255, let leafIndex else { throw MLSError.invalidCredential }
            try writer.writeVector(groupID); writer.write(leafIndex)
        }
        return writer.data
    }

    /// Signs a leaf with its matching P-256 key using RFC label `LeafNodeTBS`.
    /// - Parameters:
    ///   - privateKey: Thirty-two-byte private scalar matching `signatureKey`.
    ///   - groupID: Source-specific group signature context; absent for key packages.
    ///   - leafIndex: Source-specific leaf index; absent for key packages.
    /// - Returns: A copy with the DER signature replaced; the original remains unchanged.
    /// - Throws: `invalidCredential` for key mismatch, context errors, or crypto errors.
    public func signed(privateKey: Data, groupID: Data? = nil, leafIndex: UInt32? = nil) throws -> Self {
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: privateKey),
              key.publicKey.x963Representation == signatureKey else { throw MLSError.invalidCredential }
        let signature = try MLSCipherSuite2.signWithLabel(privateKey: privateKey, label: "LeafNodeTBS",
                                                        content: signatureInput(groupID: groupID, leafIndex: leafIndex))
        return try Self(encryptionKey: encryptionKey, signatureKey: signatureKey, credential: credential,
                        capabilities: capabilities, source: source, lifetime: lifetime, parentHash: parentHash,
                        extensions: extensions, signature: signature)
    }

    /// Verifies signature, optional identity binding, required capabilities and lifetime.
    /// - Parameters:
    ///   - now: Injected unsigned Unix seconds; no system clock is read.
    ///   - groupID: Required signature group binding for update/commit leaves.
    ///   - leafIndex: Required signature leaf binding for update/commit leaves.
    ///   - expectedIdentity: Exact trusted reference identity, or nil when caller
    ///     separately authenticates the credential/key pair.
    ///   - maximumLifetime: Application's maximum total key-package lifetime in seconds.
    ///   - validateLifetime: Whether to enforce current/max lifetime; DAVE v1 uses
    ///     the full-range lifetime and disables this application expiry policy.
    ///   - requiredCapabilities: Optional encoded required_capabilities extension data.
    /// - Throws: `invalidCredential` for identity/lifetime/capability mismatch,
    ///   `invalidSignature` for authentication failure, or wire/crypto errors.
    ///   Success does not replace trusted identity-to-signing-key authentication.
    public func validate(now: UInt64, groupID: Data? = nil, leafIndex: UInt32? = nil,
                         expectedIdentity: Data? = nil, maximumLifetime: UInt64 = 604_800,
                         validateLifetime: Bool = true, requiredCapabilities: Data? = nil) throws {
        if let expectedIdentity, expectedIdentity != credential.identity { throw MLSError.invalidCredential }
        if validateLifetime, let lifetime {
            guard lifetime.notBefore <= now, now <= lifetime.notAfter,
                  lifetime.notAfter - lifetime.notBefore <= maximumLifetime else { throw MLSError.invalidCredential }
        }
        if let requiredCapabilities { try capabilities.validateRequired(requiredCapabilities) }
        guard try MLSCipherSuite2.verifyWithLabel(publicKey: signatureKey, label: "LeafNodeTBS",
                                                content: signatureInput(groupID: groupID, leafIndex: leafIndex), signature: signature) else {
            throw MLSError.invalidSignature
        }
    }

    /// Encodes the leaf including its signature; unsigned leaves remain representable for preparation.
    /// - Returns: Canonical RFC 9420 LeafNode bytes.
    /// - Throws: Wire capacity errors.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); try writer.writeRaw(unsignedEncoding()); try writer.writeVector(signature); return writer.data
    }

    /// Decodes one complete leaf, rejecting trailing bytes without authenticating it.
    /// - Parameter data: Exactly one bounded LeafNode encoding.
    /// - Returns: Structurally validated leaf; callers must invoke `validate`.
    /// - Throws: Wire, unsupported-source, or credential/key errors.
    public static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let result = try decode(&reader); try reader.requireEnd(); return result
    }

    /// Decodes an embedded leaf with strict source-specific fields and key validation.
    /// - Parameter reader: Enclosing cursor advanced through the signature vector.
    /// - Returns: Unauthenticated immutable leaf.
    /// - Throws: `malformedEncoding` for an unknown source, or wire/credential errors.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        let encryptionKey = try reader.readVector(); let signatureKey = try reader.readVector()
        let credential = try MLSCredential.decode(&reader); let capabilities = try MLSCapabilities.decode(&reader)
        guard let source = MLSLeafNodeSource(rawValue: try reader.readUInt8()) else { throw MLSError.malformedEncoding }
        var lifetime: MLSLifetime?; var parentHash: Data?
        switch source {
        case .keyPackage: lifetime = try MLSLifetime(notBefore: reader.readUInt64(), notAfter: reader.readUInt64())
        case .update: break
        case .commit: parentHash = try reader.readVector()
        }
        let extensions = try MLSExtension.decodeList(&reader); let signature = try reader.readVector()
        return try Self(encryptionKey: encryptionKey, signatureKey: signatureKey, credential: credential,
                        capabilities: capabilities, source: source, lifetime: lifetime, parentHash: parentHash,
                        extensions: extensions, signature: signature)
    }
}

/// Signed MLS 1.0 ciphersuite-2 invitation package, distinct from a client's leaf HPKE key.
public struct MLSKeyPackage: Sendable, Equatable {
    public let initKey: Data
    public let leafNode: MLSLeafNode
    public let extensions: [MLSExtension]
    public let signature: Data

    /// Creates a structurally valid package; call `validate` before member admission.
    /// - Parameters:
    ///   - initKey: Valid uncompressed P-256 HPKE public key, distinct from leaf encryption key.
    ///   - leafNode: A key-package-source leaf with a lifetime and compatible capabilities.
    ///   - extensions: Unique package extensions advertised by the leaf.
    ///   - signature: DER ECDSA signature, or empty during preparation.
    /// - Throws: `invalidKeyPackage` for invalid/duplicate keys, source or extensions;
    ///   extension wire/capacity errors for excessive data. No authenticity is implied.
    public init(initKey: Data, leafNode: MLSLeafNode, extensions: [MLSExtension] = [], signature: Data = Data()) throws {
        guard initKey.count == 65, initKey != leafNode.encryptionKey, leafNode.source == .keyPackage,
              (try? P256.KeyAgreement.PublicKey(x963Representation: initKey)) != nil,
              signature.count <= 80 else { throw MLSError.invalidKeyPackage }
        for item in extensions where !(1...5).contains(item.type) {
            guard leafNode.capabilities.extensions.contains(item.type) else { throw MLSError.invalidKeyPackage }
        }
        _ = try MLSExtension.encodeList(extensions)
        self.initKey = initKey; self.leafNode = leafNode; self.extensions = extensions; self.signature = signature
    }

    /// Builds a signed publishable package from caller-owned signing and HPKE public keys.
    /// - Parameters:
    ///   - identity: Application-authenticated identity; DAVE requires eight-byte user ID.
    ///   - signaturePrivateKey: Thirty-two-byte P-256 signing scalar.
    ///   - leafEncryptionKey: Uncompressed leaf HPKE public key.
    ///   - initKey: Independent one-use HPKE public key; never reuse across published packages.
    ///   - lifetime: Inclusive lifetime; full range defaults to the DAVE v1 profile.
    /// - Returns: A leaf-signed and package-signed KeyPackage.
    /// - Throws: Credential/key/signing errors. Callers retain private-key ownership
    ///   and must enforce one-use init-key publication across invocations.
    public static func generate(identity: Data, signaturePrivateKey: Data, leafEncryptionKey: Data,
                                initKey: Data, lifetime: MLSLifetime = MLSLifetime(notBefore: 0, notAfter: .max)) throws -> Self {
        let leaf = try MLSLeafNode.generate(identity: identity, signaturePrivateKey: signaturePrivateKey,
                                            encryptionKey: leafEncryptionKey, lifetime: lifetime)
        return try Self(initKey: initKey, leafNode: leaf).signed(privateKey: signaturePrivateKey)
    }

    /// Produces the RFC 9420 KeyPackageTBS unsigned encoding.
    /// - Returns: Explicit version 1, suite 2, init key, signed leaf and extensions.
    /// - Throws: Wire capacity errors from nested fields.
    public func signatureInput() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); writer.write(UInt16(2))
        try writer.writeVector(initKey); try writer.writeRaw(leafNode.encoded())
        try writer.writeRaw(MLSExtension.encodeList(extensions)); return writer.data
    }

    /// Signs all package fields with the leaf's matching P-256 signing key.
    /// - Parameter privateKey: Thirty-two-byte signing scalar matching the leaf key.
    /// - Returns: Signed immutable copy.
    /// - Throws: `invalidCredential` for key mismatch, or crypto/wire errors.
    public func signed(privateKey: Data) throws -> Self {
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: privateKey),
              key.publicKey.x963Representation == leafNode.signatureKey else { throw MLSError.invalidCredential }
        let signature = try MLSCipherSuite2.signWithLabel(privateKey: privateKey, label: "KeyPackageTBS", content: signatureInput())
        return try Self(initKey: initKey, leafNode: leafNode, extensions: extensions, signature: signature)
    }

    /// Validates the leaf and package signatures, identity, and application expiry policy.
    /// - Parameters:
    ///   - now: Injected Unix second; no system clock is read.
    ///   - expectedIdentity: Exact trusted identity assertion, or nil for separate AS validation.
    ///   - maximumLifetime: Maximum allowed interval, default seven days for ordinary MLS.
    ///   - validateLifetime: False for DAVE's mandated full-range lifetime.
    /// - Throws: Leaf validation failures or `invalidSignature` for the package signature.
    ///   Caller must additionally authenticate identity/key ownership and enforce init-key freshness.
    public func validate(now: UInt64, expectedIdentity: Data? = nil, maximumLifetime: UInt64 = 604_800,
                         validateLifetime: Bool = true) throws {
        try leafNode.validate(now: now, expectedIdentity: expectedIdentity, maximumLifetime: maximumLifetime, validateLifetime: validateLifetime)
        guard try MLSCipherSuite2.verifyWithLabel(publicKey: leafNode.signatureKey, label: "KeyPackageTBS",
                                                content: signatureInput(), signature: signature) else { throw MLSError.invalidSignature }
    }

    /// Computes the exact RFC 9420 domain-separated KeyPackageRef.
    /// - Returns: Thirty-two-byte reference to the complete signed KeyPackage, without MLSMessage wrapper.
    /// - Throws: Wire/crypto errors while serializing or hashing the package.
    public func reference() throws -> Data {
        try MLSCipherSuite2.refHash(label: "MLS 1.0 KeyPackage Reference", value: encoded())
    }

    /// Encodes the signed package or its optional MLSMessage wrapper.
    /// - Parameter messageWrapped: Include MLSMessage version 1 and key_package format 5.
    /// - Returns: Canonical encoded package.
    /// - Throws: Wire capacity errors from nested data.
    public func encoded(messageWrapped: Bool = false) throws -> Data {
        var writer = MLSWriter()
        if messageWrapped { writer.write(UInt16(1)); writer.write(UInt16(5)) }
        try writer.writeRaw(signatureInput()); try writer.writeVector(signature); return writer.data
    }

    /// Decodes a complete package, checking explicit version/suite and wrapper consistency.
    /// - Parameters:
    ///   - data: Exactly one encoded KeyPackage or MLSMessage.
    ///   - messageWrapped: Expect MLSMessage version 1 and format 5 when true.
    /// - Returns: Structurally valid package; caller must verify signatures using `validate`.
    /// - Throws: Unsupported version/suite, malformed wrapper/trailing data, key or wire errors.
    public static func decode(_ data: Data, messageWrapped: Bool = false) throws -> Self {
        var reader = try MLSReader(data)
        if messageWrapped {
            guard try reader.readUInt16() == 1 else { throw MLSError.unsupportedVersion }
            guard try reader.readUInt16() == 5 else { throw MLSError.malformedEncoding }
        }
        let result = try decode(&reader); try reader.requireEnd(); return result
    }

    /// Decodes an embedded KeyPackage, preserving extension order and signed bytes.
    /// - Parameter reader: Cursor advanced through the complete signed package.
    /// - Returns: Unauthenticated structurally valid package.
    /// - Throws: Unsupported version/suite, invalid key/source, or malformed-wire errors.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        guard try reader.readUInt16() == 1 else { throw MLSError.unsupportedVersion }
        guard try reader.readUInt16() == 2 else { throw MLSError.unsupportedCipherSuite }
        let initKey = try reader.readVector(); let leaf = try MLSLeafNode.decode(&reader)
        let extensions = try MLSExtension.decodeList(&reader); let signature = try reader.readVector()
        return try Self(initKey: initKey, leafNode: leaf, extensions: extensions, signature: signature)
    }
}

/// Authenticated delivery-service sender declaration from a GroupContext extension.
public struct MLSExternalSender: Sendable, Equatable {
    public let signatureKey: Data
    public let credential: MLSCredential

    /// Validates an injected external sender declaration without admitting it to a group.
    /// - Parameters:
    ///   - signatureKey: Uncompressed 65-byte P-256 ECDSA public key.
    ///   - credential: Trusted basic identity assigned to this external sender.
    /// - Throws: `invalidCredential` for an invalid signing public key.
    public init(signatureKey: Data, credential: MLSCredential) throws {
        guard signatureKey.count == 65,
              (try? P256.Signing.PublicKey(x963Representation: signatureKey)) != nil else { throw MLSError.invalidCredential }
        self.signatureKey = signatureKey; self.credential = credential
    }

    /// Encodes one RFC external sender without its enclosing vector.
    /// - Returns: SignaturePublicKey and Credential encoding.
    /// - Throws: Wire capacity errors.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(signatureKey); try writer.writeRaw(credential.encoded()); return writer.data
    }

    /// Decodes one complete external sender package, rejecting suffixes.
    /// - Parameter data: Exactly one ExternalSender representation.
    /// - Returns: Structurally valid sender requiring trusted delivery-service authentication.
    /// - Throws: Key/credential or wire errors.
    public static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let result = try decode(&reader); try reader.requireEnd(); return result
    }

    /// Decodes one sender embedded in an external_senders vector.
    /// - Parameter reader: Cursor advanced past signing key and credential.
    /// - Returns: Structurally valid declaration.
    /// - Throws: Key/credential or wire errors.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        try Self(signatureKey: reader.readVector(), credential: MLSCredential.decode(&reader))
    }

    /// Constructs the DAVE-required external_senders GroupContext extension with one sender.
    /// - Returns: Extension type 5 containing exactly this declaration in a vector.
    /// - Throws: Wire capacity errors.
    public func groupExtension() throws -> MLSExtension {
        var writer = MLSWriter(); try writer.writeVector(encoded()); return try MLSExtension(type: 5, data: writer.data)
    }
}
