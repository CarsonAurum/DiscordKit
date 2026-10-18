import Foundation

/// DAVE v1's permitted MLS proposals; arbitrary MLS proposal types are rejected.
/// These values are untrusted until the external sender's framed signature and
/// application participant authorization have both been checked.
public enum MLSProposal: Sendable, Equatable {
    case add(MLSKeyPackage)
    case remove(UInt32)

    /// Encodes a proposal without an MLSMessage envelope.
    /// - Returns: RFC 9420 proposal type followed by its exact body.
    /// - Throws: Bounded encoding errors from embedded key packages.
    public func encoded() throws -> Data {
        var writer = MLSWriter()
        switch self {
        case .add(let package): writer.write(UInt16(1)); try writer.writeRaw(package.encoded())
        case .remove(let leaf): writer.write(UInt16(3)); writer.write(leaf)
        }
        return writer.data
    }

    /// Parses only the proposal types established by DAVE v1's MLS profile.
    /// - Parameter reader: Cursor over a containing framed-content object.
    /// - Returns: Add or Remove; unsupported types are never treated as opaque valid proposals.
    /// - Throws: `invalidProposal`, malformed encoding, or key-package structural errors.
    static func decode(_ reader: inout MLSReader) throws -> Self {
        switch try reader.readUInt16() {
        case 1: return try .add(MLSKeyPackage.decode(&reader))
        case 3: return try .remove(reader.readUInt32())
        default: throw MLSError.invalidProposal
        }
    }

    /// Signs an external proposal for an already trusted external-sender key.
    /// This helper performs no delivery, authorization, or group-state mutation.
    /// - Parameters:
    ///   - groupID: Exact destination group ID, 1...255 bytes.
    ///   - epoch: Destination MLS epoch; recipients require an exact match.
    ///   - signaturePrivateKey: External sender's 32-byte P-256 signing scalar.
    ///   - authenticatedData: Optional application-associated bytes, included in the signature.
    /// - Returns: Versioned MLS public-message bytes with external sender index zero.
    /// - Throws: Key, signature or bounded-encoding errors.
    public func externalMessage(groupID: Data, epoch: UInt64, signaturePrivateKey: Data,
                                authenticatedData: Data = Data()) throws -> Data {
        guard !groupID.isEmpty, groupID.count <= 255 else { throw MLSError.invalidConfiguration }
        let unsigned = MLSPublicMessage(groupID: groupID, epoch: epoch, sender: .external(0),
                                        authenticatedData: authenticatedData, body: .proposal(self))
        let signature = try MLSCipherSuite2.signWithLabel(privateKey: signaturePrivateKey,
            label: "FramedContentTBS", content: unsigned.signatureInput(context: nil))
        var message = unsigned; message.signature = signature
        return try message.encoded()
    }
}

/// MLS public sender forms required by DAVE; new-member/external commits are not allowed.
enum MLSSender: Sendable, Equatable {
    case member(UInt32)
    case external(UInt32)

    /// Serializes sender type and its unsigned index into the containing frame.
    /// - Parameter writer: Bounded parent encoder, mutated synchronously.
    func write(to writer: inout MLSWriter) {
        switch self {
        case .member(let index): writer.write(UInt8(1)); writer.write(index)
        case .external(let index): writer.write(UInt8(2)); writer.write(index)
        }
    }

    /// Reads the two allowed sender variants without accepting unknown types.
    /// - Parameter reader: Parent cursor advanced past the sender.
    /// - Returns: Member or external sender with a complete 32-bit index.
    /// - Throws: `invalidCommit` for excluded forms or wire errors for truncation.
    static func decode(_ reader: inout MLSReader) throws -> Self {
        switch try reader.readUInt8() {
        case 1: return try .member(reader.readUInt32())
        case 2: return try .external(reader.readUInt32())
        default: throw MLSError.invalidCommit
        }
    }
}

/// A DAVE-profile commit contains only previously authenticated proposal references.
struct MLSCommit: Sendable {
    let references: [Data]
    let path: MLSUpdatePath?

    /// Encodes reference-only proposals and the optional RFC UpdatePath.
    /// - Returns: Commit bytes excluding its FramedContent wrapper.
    /// - Throws: `invalidCommit` for excessive/invalid references, or encoding errors.
    func encoded() throws -> Data {
        guard references.count <= 1024, references.allSatisfy({ $0.count == 32 }),
              Set(references).count == references.count else { throw MLSError.invalidCommit }
        var writer = MLSWriter(); var list = MLSWriter()
        for reference in references { list.write(UInt8(2)); try list.writeVector(reference) }
        try writer.writeVector(list.data); writer.write(UInt8(path == nil ? 0 : 1))
        if let path { try writer.writeRaw(path.encoded()) }
        return writer.data
    }

    /// Reads reference-only proposals, refusing inline bodies and duplicate references.
    /// - Parameter reader: Cursor positioned at Commit.proposals.
    /// - Returns: Bounded parsed commit, not yet authenticated or applied.
    /// - Throws: `invalidCommit` for duplicate/inline/excessive entries or malformed encoding.
    static func decode(_ reader: inout MLSReader) throws -> Self {
        var list = try MLSReader(reader.readVector()); var references: [Data] = []
        while !list.isAtEnd {
            guard references.count < 1024, try list.readUInt8() == 2 else { throw MLSError.invalidCommit }
            let reference = try list.readVector()
            guard reference.count == 32, !references.contains(reference) else { throw MLSError.invalidCommit }
            references.append(reference)
        }
        let present = try reader.readUInt8()
        guard present <= 1 else { throw MLSError.malformedEncoding }
        return try Self(references: references, path: present == 1 ? MLSUpdatePath.read(from: &reader) : nil)
    }
}

/// The two DAVE-profile public handshake bodies; application data uses media exporters.
enum MLSHandshakeBody: Sendable {
    case proposal(MLSProposal)
    case commit(MLSCommit)
}

/// Exact RFC 9420 framing shared by externally signed proposals and member commits.
/// Authentication is explicit; decoding alone never authorizes a message.
struct MLSPublicMessage: Sendable {
    let groupID: Data
    let epoch: UInt64
    let sender: MLSSender
    var authenticatedData = Data()
    let body: MLSHandshakeBody
    var signature = Data()
    var confirmationTag = Data()
    var membershipTag = Data()

    /// Encodes FramedContent, including application-associated bytes and content selector.
    /// - Returns: Bytes bound by the framed-content signature and proposal reference.
    /// - Throws: Bounded field/body encoding errors.
    func framedContent() throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(groupID); writer.write(epoch)
        sender.write(to: &writer); try writer.writeVector(authenticatedData)
        switch body {
        case .proposal(let proposal): writer.write(UInt8(2)); try writer.writeRaw(proposal.encoded())
        case .commit(let commit): writer.write(UInt8(3)); try writer.writeRaw(commit.encoded())
        }
        return writer.data
    }

    /// Encodes version, public wire format, frame and sender-dependent GroupContext.
    /// - Parameter context: Required for member messages and absent for external proposals.
    /// - Returns: FramedContentTBS, used with the RFC FramedContentTBS signature label.
    /// - Throws: `invalidCommit` for inconsistent sender/context or encoding errors.
    func signatureInput(context: MLSGroupContext?) throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); writer.write(UInt16(1))
        try writer.writeRaw(framedContent())
        switch sender {
        case .member:
            guard let context else { throw MLSError.invalidCommit }; try writer.writeRaw(context.encoded())
        case .external:
            guard context == nil else { throw MLSError.invalidProposal }
        }
        return writer.data
    }

    /// Encodes signature and, for commits, the new epoch's confirmation MAC.
    /// - Returns: FramedContentAuthData; empty signatures are only useful while constructing.
    /// - Throws: Bounded encoding errors.
    func authData() throws -> Data {
        var writer = MLSWriter(); try writer.writeVector(signature)
        if case .commit = body { try writer.writeVector(confirmationTag) }
        return writer.data
    }

    /// Produces the MAC input proving membership in the pre-commit epoch.
    /// - Parameter context: Current authenticated group context.
    /// - Returns: Exact AuthenticatedContentTBM bytes, excluding membership tag itself.
    /// - Throws: Sender/context or bounded encoding errors.
    func membershipInput(context: MLSGroupContext) throws -> Data {
        try signatureInput(context: context) + authData()
    }

    /// Encodes AuthenticatedContent for reference hashing, excluding membership MAC.
    /// - Returns: WireFormat followed by content and auth data, as RFC 9420 requires.
    /// - Throws: Bounded encoding errors.
    func authenticatedContent() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); try writer.writeRaw(framedContent())
        try writer.writeRaw(authData()); return writer.data
    }

    /// Encodes the confirmed-transcript contribution through the commit signature.
    /// - Returns: Public wire format, content and signature vector; no confirmation tag.
    /// - Throws: Bounded encoding errors.
    func transcriptInput() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); try writer.writeRaw(framedContent())
        try writer.writeVector(signature); return writer.data
    }

    /// Wraps the public handshake in an MLS 1.0 MLSMessage.
    /// - Returns: Complete wire bytes suitable for an injected delivery service.
    /// - Throws: Bounded encoding errors.
    func encoded() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); writer.write(UInt16(1))
        try writer.writeRaw(framedContent()); try writer.writeRaw(authData())
        if case .member = sender { try writer.writeVector(membershipTag) }
        return writer.data
    }

    /// Parses one bounded public handshake, requiring complete consumption.
    /// - Parameter data: MLSMessage bytes; private/application/unknown types are rejected.
    /// - Returns: Unauthenticated parsed content; callers must verify before mutation.
    /// - Throws: Unsupported version, invalid message/profile, or malformed wire errors.
    static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data)
        let result = try decode(&reader)
        try reader.requireEnd(); return result
    }

    /// Consumes exactly one self-delimiting public MLSMessage from a delivery vector.
    /// - Parameter reader: Bounded cursor, advanced through this message only.
    /// - Returns: Unauthenticated content; its containing group must authenticate it.
    /// - Throws: Unsupported framing, oversized fields, or malformed content. No state is changed.
    static func decode(_ reader: inout MLSReader) throws -> Self {
        guard try reader.readUInt16() == 1 else { throw MLSError.unsupportedVersion }
        guard try reader.readUInt16() == 1 else { throw MLSError.invalidCommit }
        let groupID = try reader.readVector(); let epoch = try reader.readUInt64()
        let sender = try MLSSender.decode(&reader); let associated = try reader.readVector()
        let body: MLSHandshakeBody
        switch try reader.readUInt8() {
        case 2: body = try .proposal(MLSProposal.decode(&reader))
        case 3: body = try .commit(MLSCommit.decode(&reader))
        default: throw MLSError.invalidCommit
        }
        var result = Self(groupID: groupID, epoch: epoch, sender: sender, authenticatedData: associated, body: body)
        result.signature = try reader.readVector()
        if case .commit = body { result.confirmationTag = try reader.readVector() }
        if case .member = sender { result.membershipTag = try reader.readVector() }
        guard result.signature.count <= 80, result.confirmationTag.count <= 32,
              result.membershipTag.count <= 32 else { throw MLSError.malformedEncoding }
        return result
    }
}
