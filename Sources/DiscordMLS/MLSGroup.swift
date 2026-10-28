// File: Sources/DiscordMLS/MLSGroup.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import Crypto
import Foundation

/// Resource and authentication policy for the DAVE v1 MLS profile.
///
/// The external sender must come from an authenticated delivery channel. Expected
/// user IDs must come from authenticated session membership, not incoming MLS bytes.
/// This policy authenticates identity authorization through that trusted sender;
/// it does not establish out-of-band human identity verification.
public struct MLSGroupPolicy: Sendable {
    public let externalSender: MLSExternalSender
    public let expectedParticipants: Set<UInt64>
    public let maximumMembers: Int
    public let maximumProposals: Int
    public let maximumProposalBytes: Int
    public let maximumMessageBytes: Int

    /// Creates explicit bounded admission policy without starting I/O or tasks.
    /// - Parameters:
    ///   - externalSender: Exact trusted basic credential and P-256 signing public key.
    ///   - expectedParticipants: Nonzero authorized user IDs, including the local user.
    ///   - maximumMembers: Live members and participant-set budget, 1...1024.
    ///   - maximumProposals: Cached unrevoked proposals, 1...1024.
    ///   - maximumProposalBytes: Aggregate cached wire bytes, 1024...16777216.
    ///   - maximumMessageBytes: Individual inbound/outbound message bytes, 1024...1048576.
    /// - Throws: `invalidConfiguration` for invalid bounds, zero IDs, or excessive participants.
    public init(externalSender: MLSExternalSender, expectedParticipants: Set<UInt64>, maximumMembers: Int = 256,
                maximumProposals: Int = 256, maximumProposalBytes: Int = 1_048_576,
                maximumMessageBytes: Int = 1_048_576) throws {
        guard (1...1024).contains(maximumMembers), (1...1024).contains(maximumProposals),
              (1024...16_777_216).contains(maximumProposalBytes), (1024...1_048_576).contains(maximumMessageBytes),
              expectedParticipants.count <= maximumMembers, !expectedParticipants.contains(0) else { throw MLSError.invalidConfiguration }
        self.externalSender = externalSender; self.expectedParticipants = expectedParticipants
        self.maximumMembers = maximumMembers; self.maximumProposals = maximumProposals
        self.maximumProposalBytes = maximumProposalBytes; self.maximumMessageBytes = maximumMessageBytes
    }
}

/// Wire deliverables for one tentative commit, with no private keys or epoch secrets.
/// The owner retains a single candidate until the delivery service selects a commit.
public struct MLSTentativeCommit: Sendable {
    public let commit: Data
    public let welcome: Data?
    public let epoch: UInt64
}

/// Bounded, nonsecret state suitable for diagnostics without identities or keys.
public struct MLSGroupSnapshot: Sendable, Equatable {
    public let epoch: UInt64?
    public let memberCount: Int
    public let pendingProposalCount: Int
    public let pendingProposalBytes: Int
    public let hasTentativeCommit: Bool
    public let isClosed: Bool
}

/// Signals a fully authenticated epoch advance or authenticated removal of this owner.
public enum MLSCommitOutcome: Sendable, Equatable { case advanced, removed }

/// Minimal retained epoch branches for public DAVE MLS handshakes/exporters.
/// Encryption/Welcome/epoch root secrets are discarded after candidate construction.
struct MLSEpochKeys: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let initialization: Data
    let exporter: Data
    let membership: Data
    let authenticator: Data

    /// Redacts every epoch-secret branch from ordinary diagnostic formatting.
    var description: String { "MLSEpochKeys([REDACTED])" }
    /// Uses the same redaction for debug formatting.
    var debugDescription: String { description }
    /// Excludes retained secret branches from mirror traversal and `dump`.
    var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Retains only branches needed by this public-handshake profile.
    /// - Parameter schedule: Temporary complete schedule; no copy is retained.
    init(_ schedule: MLSKeySchedule) {
        initialization = schedule.initSecret; exporter = schedule.exporterSecret
        membership = schedule.membershipKey
        authenticator = schedule.epochAuthenticator
    }
}

/// Candidate group state; it never escapes a key owner or group actor.
struct MLSEpochState: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let context: MLSGroupContext
    let tree: MLSRatchetTree
    let ownLeaf: UInt32
    let privateKeys: [UInt32: Data]
    let keys: MLSEpochKeys
    let interimTranscript: Data
    /// Redacts private path keys, epoch secrets and group identities from diagnostics.
    var description: String { "MLSEpochState([REDACTED])" }
    /// Uses the same fixed redaction for debug formatting.
    var debugDescription: String { description }
    /// Excludes the entire candidate state from mirror traversal and `dump`.
    var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }
}

/// Single-use ownership of a fresh published KeyPackage and its private keys.
///
/// Actor identity prevents accidental value copies from accepting the same Welcome
/// twice. Successful default group creation or joining consumes private material
/// atomically. Creation with `retainForWelcome: true` preserves the package for a
/// competing creator's Welcome; the caller must close the unused candidate/package.
/// A rejected Welcome does not consume the package; explicit close discards it.
/// Keys use Swift Crypto's CSPRNG. No sockets, devices, tasks or persistence are used.
/// `Data`/Crypto do not promise physical memory erasure; never persist or log secrets.
public actor MLSKeyPackageOwner: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public nonisolated let keyPackage: MLSKeyPackage
    private let userID: UInt64
    private var signingKey: Data?
    private var leafKey: Data?
    private var initKey: Data?
    private var hasCreatedGroup = false

    /// Generates a fresh suite-2 package for the authenticated local Discord identity.
    /// - Parameters:
    ///   - userID: Nonzero local snowflake encoded as eight big-endian bytes.
    ///   - signaturePrivateKey: Optional 32-byte P-256 raw signing private key.
    ///     Supply the same identity key for all related active DAVE media sessions
    ///     and replacement packages after recovery; nil generates a new identity.
    ///     Leaf encryption and initialization keys are always freshly generated.
    ///     The caller owns identity-key lifetime and secure storage; this owner
    ///     retains an independent copy only until package consumption or close.
    /// - Throws: Credential/signature/key-generation errors, including Crypto's
    ///   rejection of malformed or out-of-range private key material. DAVE's
    ///   full-range lifetime is used; publication and authentication belong to the
    ///   caller. Construction starts no tasks, I/O or persistence.
    public init(userID: UInt64, signaturePrivateKey: Data? = nil) throws {
        let credential = try MLSCredential.discord(userID: userID)
        let signing: P256.Signing.PrivateKey
        if let signaturePrivateKey {
            signing = try P256.Signing.PrivateKey(rawRepresentation: signaturePrivateKey)
        } else {
            signing = P256.Signing.PrivateKey(compactRepresentable: false)
        }
        let leaf = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let initial = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        self.keyPackage = try MLSKeyPackage.generate(identity: credential.identity, signaturePrivateKey: signing.rawRepresentation,
            leafEncryptionKey: leaf.publicKey.x963Representation, initKey: initial.publicKey.x963Representation)
        self.userID = userID; signingKey = signing.rawRepresentation; leafKey = leaf.rawRepresentation; initKey = initial.rawRepresentation
    }

    /// Creates at most one epoch-zero candidate after complete local validation.
    /// - Parameters:
    ///   - groupID: Unique application group ID, 1...255 bytes; caller must prevent reuse.
    ///   - policy: Trusted external sender and membership/resource policy containing this user.
    ///   - retainForWelcome: Defaults false, consuming this package on creation. True retains
    ///     its original keys for a competing creator's Welcome during DAVE initialization.
    ///     The owner must close the losing candidate before joining, or close this package
    ///     when its own candidate wins. A second create call always fails.
    /// - Returns: Inert independent group owner with a fresh random epoch secret.
    /// - Throws: `closed` after prior consumption, cancellation before work, or invalid policy/context.
    ///   The actor performs no suspension or external effects; failed creation preserves keys.
    public func createGroup(groupID: Data, policy: MLSGroupPolicy, retainForWelcome: Bool = false) throws -> MLSGroup {
        try Task.checkCancellation()
        guard !hasCreatedGroup, let signingKey, let leafKey, initKey != nil else { throw MLSError.closed }
        guard policy.expectedParticipants.contains(userID) else { throw MLSError.invalidCredential }
        let tree = try MLSRatchetTree(leaf: keyPackage.leafNode, maximumMembers: policy.maximumMembers)
        let context = try MLSGroupContext(groupID: groupID, epoch: 0, treeHash: tree.treeHash(),
            confirmedTranscriptHash: Data(), extensions: [policy.externalSender.groupExtension()])
        let schedule = try MLSKeySchedule(epochSecret: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        let confirmation = MLSCipherSuite2.mac(key: schedule.confirmationKey, content: Data())
        let state = try MLSEpochState(context: context, tree: tree, ownLeaf: 0, privateKeys: [0: leafKey],
            keys: MLSEpochKeys(schedule), interimTranscript: mlsInterimTranscript(confirmed: Data(), confirmation: confirmation))
        let group = MLSGroup(state: state, signingKey: signingKey, userID: userID, policy: policy)
        hasCreatedGroup = true
        if !retainForWelcome { close() }
        DiscordLog.makeLogger("mls.group").debug("MLS candidate group created", metadata: ["dk.event": "mls.group.created"])
        return group
    }

    /// Validates and consumes an addressed Welcome into a new independent group.
    /// No decrypted candidate GroupInfo/secrets are returned if any signature,
    /// confirmation, tree, participant or external-sender check fails.
    /// - Parameters:
    ///   - welcome: Complete versioned ciphersuite-2 Welcome within the policy byte budget.
    ///   - expectedGroupID: Exact unique destination ID, bound out of band by the caller.
    ///   - policy: Trusted external sender and authorized participants including this user.
    /// - Returns: New group only after all authentication checks; package is then consumed.
    /// - Throws: `closed`, cancellation, capacity/wire/authentication/tree errors. Failure
    ///   preserves this fresh package for a corrected Welcome; no callbacks or I/O occur.
    public func join(welcome: Data, expectedGroupID: Data, policy: MLSGroupPolicy) throws -> MLSGroup {
        try Task.checkCancellation()
        guard let signingKey, let leafKey, let initKey else { throw MLSError.closed }
        guard welcome.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }
        guard policy.expectedParticipants.contains(userID) else { throw MLSError.invalidCredential }
        let message = try MLSWelcome.decode(welcome); let reference = try keyPackage.reference()
        guard let addressed = message.secrets.first(where: { $0.reference == reference }) else { throw MLSError.invalidKeyPackage }
        let secretBytes = try MLSCipherSuite2.decryptWithLabel(privateKey: initKey, label: "Welcome",
            context: message.encryptedGroupInfo, encrypted: addressed.encrypted)
        let secrets = try MLSWelcomeSecrets.decode(secretBytes)
        let memberSecret = MLSCipherSuite2.extract(salt: secrets.joinerSecret, ikm: Data(repeating: 0, count: 32))
        let welcomeSecret = try MLSCipherSuite2.deriveSecret(memberSecret, label: "welcome")
        let welcomeKey = try MLSCipherSuite2.expandWithLabel(secret: welcomeSecret, label: "key", context: Data(), length: 16)
        let welcomeNonce = try MLSCipherSuite2.expandWithLabel(secret: welcomeSecret, label: "nonce", context: Data(), length: 12)
        let info = try MLSGroupInfo.decode(MLSCipherSuite2.open(key: welcomeKey, nonce: welcomeNonce,
            ciphertext: message.encryptedGroupInfo, authenticatedData: Data()))
        guard info.context.groupID == expectedGroupID, info.context.epoch > 0 else { throw MLSError.invalidCommit }
        try MLSGroup.validateContext(info.context, policy: policy)
        guard let inlineTree = info.extensions.first(where: { $0.type == 2 }) else { throw MLSError.invalidTree }
        let tree = try MLSRatchetTree.decode(inlineTree.data, maximumMembers: policy.maximumMembers)
        guard try tree.treeHash() == info.context.treeHash else { throw MLSError.invalidTree }
        try MLSGroup.validateTree(tree, context: info.context, participants: policy.expectedParticipants)
        try tree.validateParentHashes()
        guard let signer = tree.leaf(at: info.signer),
              try MLSCipherSuite2.verifyWithLabel(publicKey: signer.signatureKey, label: "GroupInfoTBS",
                content: info.signatureInput(), signature: info.signature) else { throw MLSError.invalidSignature }
        let ownLeaves = (0..<tree.leafCount).filter { tree.leaf(at: UInt32($0)) == keyPackage.leafNode }
        guard ownLeaves.count == 1, let own = ownLeaves.first else { throw MLSError.invalidKeyPackage }
        let ownLeaf = UInt32(own); var privateKeys: [UInt32: Data] = [ownLeaf * 2: leafKey]
        if let secret = secrets.pathSecret {
            guard let ancestor = try mlsCommonAncestor(tree: tree, sender: info.signer, recipient: ownLeaf) else { throw MLSError.invalidTree }
            let derived = try tree.derivePathSecrets(secret, from: ancestor, sender: info.signer)
            privateKeys.merge(derived.privateKeys) { _, new in new }
        }
        try MLSGroup.validatePrivatePath(privateKeys, tree: tree, ownLeaf: ownLeaf)
        let schedule = try MLSKeySchedule(joinerSecret: secrets.joinerSecret, groupContext: info.context.encoded())
        guard MLSCipherSuite2.verifyMAC(key: schedule.confirmationKey, content: info.context.confirmedTranscriptHash,
            tag: info.confirmationTag) else { throw MLSError.confirmationFailed }
        let state = try MLSEpochState(context: info.context, tree: tree, ownLeaf: ownLeaf, privateKeys: privateKeys,
            keys: MLSEpochKeys(schedule), interimTranscript: mlsInterimTranscript(confirmed: info.context.confirmedTranscriptHash, confirmation: info.confirmationTag))
        let group = MLSGroup(state: state, signingKey: signingKey, userID: userID, policy: policy)
        close()
        DiscordLog.makeLogger("mls.group").debug("MLS Welcome authenticated", metadata: ["dk.event": "mls.group.joined"])
        return group
    }

    /// Permanently discards retained keys; repeated closure is harmless.
    /// This is a logical release, not a physical memory-erasure guarantee.
    public func close() { signingKey = nil; leafKey = nil; initKey = nil }
    /// Fixed redacted diagnostic; no identity, key or KeyPackage is included.
    public nonisolated var description: String { "MLSKeyPackageOwner([REDACTED])" }
    /// Uses the same fixed redaction for debug formatting.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflection from revealing retained key material or user identity.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }
}

/// Actor-owned MLS 1.0 group implementing DAVE v1's external Add/Remove profile.
///
/// Constructors start no work. Calls serialize without internal suspension points;
/// all expensive cryptography runs within bounded actor admission. Tentative state
/// becomes current only when a matching authenticated delivery-service commit wins.
/// A remote winner discards the local candidate; failed validation preserves current
/// state. This is experimental protocol code pending independent cryptographic review.
/// It supplies no DAVE signaling, frame transform, network session or production claim.
public actor MLSGroup: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var state: MLSEpochState?
    private var signingKey: Data?
    private let userID: UInt64
    private let policy: MLSGroupPolicy
    private var expectedParticipants: Set<UInt64>
    private var proposals: [Data: (proposal: MLSProposal, bytes: Int)] = [:]
    private var proposalOrder: [Data] = []
    private var proposalBytes = 0
    private var pending: (result: MLSTentativeCommit, state: MLSEpochState)?

    /// Transfers fully validated private state from its single-use package owner.
    /// - Parameters:
    ///   - state: Authenticated epoch and private path; no alternate owner may use it.
    ///   - signingKey: Matching private signing scalar, retained until close/removal.
    ///   - userID: Authenticated local user identity.
    ///   - policy: Initial trusted external sender, authorized membership and resource bounds.
    init(state: MLSEpochState, signingKey: Data, userID: UInt64, policy: MLSGroupPolicy) {
        self.state = state; self.signingKey = signingKey; self.userID = userID; self.policy = policy
        expectedParticipants = policy.expectedParticipants
    }

    /// Returns nonsecret bounded state without exposing keys or participant identifiers.
    /// - Returns: Current epoch/counts; a closed/removed owner reports no epoch or members.
    public func snapshot() -> MLSGroupSnapshot {
        MLSGroupSnapshot(epoch: state?.context.epoch, memberCount: state?.tree.memberCount ?? 0,
            pendingProposalCount: proposals.count, pendingProposalBytes: proposalBytes,
            hasTentativeCommit: pending != nil, isClosed: state == nil)
    }

    /// Retrieves authenticated live member identity keys for media and human verification.
    /// - Returns: Nonzero Discord user IDs mapped to exact P-256 public signing keys,
    ///   including the local member. Epoch zero is excluded because it is not established.
    /// - Throws: `closed`, cancellation, `wrongEpoch` at epoch zero, or invalid credential.
    ///   This explicit sensitive projection performs no I/O and must not be logged.
    public func memberIdentities() throws -> [UInt64: Data] {
        try Task.checkCancellation()
        guard let state else { throw MLSError.closed }
        guard state.context.epoch > 0 else { throw MLSError.wrongEpoch }
        var identities: [UInt64: Data] = [:]
        for index in 0..<state.tree.leafCount {
            if let leaf = state.tree.leaf(at: UInt32(index)) {
                identities[try Self.participantID(leaf.credential)] = leaf.signatureKey
            }
        }
        return identities
    }

    /// Replaces trusted session membership and drops any tentative commit based on it.
    /// Already cached Add proposals are revalidated when a commit is created/applied.
    /// - Parameter participants: Current authenticated participant IDs within the member budget.
    /// - Throws: `closed`, cancellation, or `invalidConfiguration` for zero/excessive IDs.
    public func setExpectedParticipants(_ participants: Set<UInt64>) throws {
        try Task.checkCancellation(); guard state != nil else { throw MLSError.closed }
        guard participants.count <= policy.maximumMembers, !participants.contains(0) else { throw MLSError.invalidConfiguration }
        if participants != expectedParticipants { expectedParticipants = participants; pending = nil }
    }

    /// Verifies one externally signed Add/Remove and caches its RFC proposal reference.
    /// Duplicate byte-identical authenticated proposals are idempotent. Authentication
    /// and participant checks precede mutation; overflow never evicts older proposals.
    /// - Parameter bytes: Complete versioned public external message for the current group/epoch.
    /// - Returns: Thirty-two-byte reference for commit selection or later revocation.
    /// - Throws: `closed`, cancellation, malformed/invalid signature/proposal/identity,
    ///   wrong epoch, or capacity errors. No asynchronous callbacks or network effects occur.
    public func cacheProposal(_ bytes: Data) throws -> Data {
        try Task.checkCancellation(); guard let state else { throw MLSError.closed }
        guard bytes.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }
        DiscordLog.makeLogger("mls.group").trace("MLS proposal envelope decoding", metadata: ["dk.event": "mls.proposal.decoding"])
        let message = try MLSPublicMessage.decode(bytes)
        guard message.groupID == state.context.groupID, message.epoch == state.context.epoch else { throw MLSError.wrongEpoch }
        guard message.sender == .external(0), case .proposal(let proposal) = message.body else { throw MLSError.invalidProposal }
        guard try MLSCipherSuite2.verifyWithLabel(publicKey: policy.externalSender.signatureKey, label: "FramedContentTBS",
            content: message.signatureInput(context: nil), signature: message.signature) else { throw MLSError.invalidSignature }
        try validateProposal(proposal, state: state)
        let reference = try MLSCipherSuite2.refHash(label: "MLS 1.0 Proposal Reference", value: message.authenticatedContent())
        if proposals[reference] != nil { return reference }
        guard proposals.count < policy.maximumProposals, bytes.count <= policy.maximumProposalBytes - proposalBytes else { throw MLSError.capacityExceeded }
        proposals[reference] = (proposal, bytes.count); proposalOrder.append(reference); proposalBytes += bytes.count; pending = nil
        return reference
    }

    /// Revokes a cached proposal on an authenticated delivery-service instruction.
    /// This method does not authenticate that instruction; the calling adapter must.
    /// - Parameter reference: Exact thirty-two-byte reference; unknown references are harmless.
    /// - Throws: `closed`, cancellation, or `invalidProposal` for a malformed reference.
    public func revokeProposal(_ reference: Data) throws {
        try Task.checkCancellation(); guard state != nil else { throw MLSError.closed }
        guard reference.count == 32 else { throw MLSError.invalidProposal }
        if let removed = proposals.removeValue(forKey: reference) {
            proposalBytes -= removed.bytes; proposalOrder.removeAll { $0 == reference }; pending = nil
        }
    }

    /// Creates one tentative next epoch using every unrevoked external proposal.
    /// A repeated call returns the existing candidate without generating more key state.
    /// The method always includes a fresh TreeKEM path, preserving forward secrecy.
    /// - Returns: Signed public commit and optional addressed inline-tree Welcome.
    /// - Throws: `closed`, cancellation, invalid/duplicate membership, self removal,
    ///   missing proposals, epoch exhaustion, or cryptographic/capacity failures. Current
    ///   state is unchanged on all failures; only a complete candidate is retained.
    public func prepareCommit() throws -> MLSTentativeCommit {
        try Task.checkCancellation(); guard let current = state, let signingKey else { throw MLSError.closed }
        if let pending { return pending.result }
        guard current.context.epoch < .max, !proposalOrder.isEmpty else { throw MLSError.invalidCommit }
        let applied = try applyProposals(proposalOrder, to: current, committer: current.ownLeaf)
        var tree = applied.tree
        let leafKey = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
        let generated = try tree.prepareUpdate(leafIndex: current.ownLeaf, leafEncryptionKey: leafKey.publicKey.x963Representation,
            signaturePrivateKey: signingKey, groupID: current.context.groupID,
            initialPathSecret: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        let provisional = try nextContext(current: current, tree: tree, confirmed: current.context.confirmedTranscriptHash)
        let path = try tree.encryptUpdatePath(generated, sender: current.ownLeaf, groupContext: provisional.encoded(), excluding: Set(applied.added.map(\.index)))
        var message = MLSPublicMessage(groupID: current.context.groupID, epoch: current.context.epoch,
            sender: .member(current.ownLeaf), body: .commit(MLSCommit(references: proposalOrder, path: path)))
        message.signature = try MLSCipherSuite2.signWithLabel(privateKey: signingKey, label: "FramedContentTBS",
            content: message.signatureInput(context: current.context))
        let confirmed = try MLSCipherSuite2.hash(current.interimTranscript + message.transcriptInput())
        let context = try nextContext(current: current, tree: tree, confirmed: confirmed)
        try Self.validateTree(tree, context: context, participants: expectedParticipants)
        let schedule = try MLSKeySchedule(initSecret: current.keys.initialization, commitSecret: generated.commitSecret, groupContext: context.encoded())
        message.confirmationTag = MLSCipherSuite2.mac(key: schedule.confirmationKey, content: confirmed)
        message.membershipTag = try MLSCipherSuite2.mac(key: current.keys.membership, content: message.membershipInput(context: current.context))
        let commit = try message.encoded(); guard commit.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }
        var privateKeys = retainedKeys(current.privateKeys, in: tree)
        privateKeys.merge(generated.privateKeys) { _, new in new }; privateKeys[current.ownLeaf * 2] = leafKey.rawRepresentation
        let candidate = try MLSEpochState(context: context, tree: tree, ownLeaf: current.ownLeaf, privateKeys: privateKeys,
            keys: MLSEpochKeys(schedule), interimTranscript: mlsInterimTranscript(confirmed: confirmed, confirmation: message.confirmationTag))
        let welcome = try makeWelcome(added: applied.added, generated: generated, state: candidate, schedule: schedule, confirmation: message.confirmationTag, signingKey: signingKey)
        let result = MLSTentativeCommit(commit: commit, welcome: welcome, epoch: context.epoch)
        pending = (result, candidate); return result
    }

    /// Processes the delivery-service-selected public commit for this exact epoch.
    /// An exact echo of the local candidate atomically selects it. Remote winners
    /// are fully verified and discard local tentative state only after success.
    /// Initial epoch zero accepts only the creator's exact candidate, per DAVE v1.
    /// - Parameter bytes: Complete selected MLS public commit, within the configured bound.
    /// - Returns: `advanced` after confirmation verification, or `removed` after an
    ///   authenticated removal of this owner, which immediately closes all key state.
    /// - Throws: `closed`, cancellation, wrong epoch, invalid signature/MAC/proposals,
    ///   confirmation/tree/capacity errors. Failed remote validation preserves current
    ///   state and candidate. Removed clients cannot verify a next-epoch confirmation,
    ///   so they release secrets after verifying the old-epoch signature/membership.
    public func acceptCommit(_ bytes: Data) throws -> MLSCommitOutcome {
        try Task.checkCancellation(); guard let current = state else { throw MLSError.closed }
        let logger = DiscordLog.makeLogger("mls.group")
        logger.trace("MLS selected commit validation started", metadata: ["dk.event": "mls.commit.started"])
        guard bytes.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }
        logger.trace("MLS commit bounds admitted", metadata: ["dk.event": "mls.commit.admitted",
            "dk.participants": .stringConvertible(expectedParticipants.count), "dk.candidate": .stringConvertible(pending != nil)])
        if let pending, pending.result.commit == bytes {
            try Self.validateTree(pending.state.tree, context: pending.state.context, participants: expectedParticipants)
            state = pending.state; clearPending()
            logger.info("MLS local commit selected", metadata: ["dk.event": "mls.commit.local_selected"])
            return .advanced
        }
        guard current.context.epoch > 0 else { throw MLSError.invalidCommit }
        logger.trace("MLS remote commit envelope decoding", metadata: ["dk.event": "mls.commit.remote.decoding"])
        let message = try MLSPublicMessage.decode(bytes)
        guard message.groupID == current.context.groupID, message.epoch == current.context.epoch else { throw MLSError.wrongEpoch }
        guard case .member(let sender) = message.sender, sender != current.ownLeaf,
              let senderLeaf = current.tree.leaf(at: sender), case .commit(let commit) = message.body else { throw MLSError.invalidCommit }
        guard try MLSCipherSuite2.verifyMAC(key: current.keys.membership, content: message.membershipInput(context: current.context), tag: message.membershipTag) else { throw MLSError.authenticationFailed }
        guard try MLSCipherSuite2.verifyWithLabel(publicKey: senderLeaf.signatureKey, label: "FramedContentTBS",
            content: message.signatureInput(context: current.context), signature: message.signature) else { throw MLSError.invalidSignature }
        logger.trace("MLS commit sender authenticated", metadata: ["dk.event": "mls.commit.sender.authenticated"])
        let applied = try applyProposals(commit.references, to: current, committer: sender)
        logger.trace("MLS commit proposals validated", metadata: ["dk.event": "mls.commit.proposals.validated",
            "dk.added": .stringConvertible(applied.added.count), "dk.removed": .stringConvertible(applied.removed.count)])
        guard let path = commit.path else {
            // This owner always emits a path, but RFC allows its omission for Add-only commits.
            guard applied.added.count == commit.references.count else { throw MLSError.invalidCommit }
            return try acceptWithoutPath(message: message, current: current, tree: applied.tree)
        }
        guard path.leafNode.credential == senderLeaf.credential, path.leafNode.signatureKey == senderLeaf.signatureKey,
              path.leafNode.encryptionKey != senderLeaf.encryptionKey else { throw MLSError.invalidCredential }
        var tree = applied.tree
        try path.leafNode.validate(now: 0, groupID: current.context.groupID, leafIndex: sender, validateLifetime: false)
        let excluding = Set(applied.added.map(\.index)); try tree.mergeUpdatePath(path, sender: sender, excluding: excluding)
        let provisional = try nextContext(current: current, tree: tree, confirmed: current.context.confirmedTranscriptHash)
        try Self.validateTree(tree, context: provisional, participants: expectedParticipants)
        if applied.removed.contains(current.ownLeaf) {
            close()
            logger.notice("MLS local membership removed", metadata: ["dk.event": "mls.group.removed"])
            return .removed
        }
        let retained = retainedKeys(current.privateKeys, in: tree)
        let secrets = try tree.decryptUpdatePath(path, sender: sender, groupContext: provisional.encoded(), privateKeys: retained, excluding: excluding)
        var keys = retained; keys.merge(secrets.privateKeys) { _, new in new }
        return try finishRemote(message: message, current: current, tree: tree, privateKeys: keys, commitSecret: secrets.commitSecret)
    }

    /// Exports an application secret from the current authenticated epoch.
    /// - Parameters:
    ///   - label: Application purpose without an MLS prefix, bounded by the message budget.
    ///   - context: Application-specific binding bytes within the configured message budget.
    ///   - length: Requested bytes, 0...65535 and within HKDF SHA256's 8160-byte limit.
    /// - Returns: Secret bytes; caller owns retention and must not log them.
    /// - Throws: `closed`, cancellation, invalid derivation lengths or capacity errors.
    public func export(label: String, context: Data, length: Int) throws -> Data {
        try Task.checkCancellation(); guard let state else { throw MLSError.closed }
        guard context.count <= policy.maximumMessageBytes, label.utf8.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }
        let derived = try MLSCipherSuite2.deriveSecret(state.keys.exporter, label: label)
        return try MLSCipherSuite2.expandWithLabel(secret: derived, label: "exported", context: MLSCipherSuite2.hash(context), length: length)
    }

    /// Explicitly retrieves the epoch authenticator for out-of-band comparison.
    /// - Returns: Exactly 32 secret bytes, never included in ordinary diagnostics.
    /// - Throws: `closed` after removal/closure, or cancellation before access.
    public func epochAuthenticator() throws -> Data {
        try Task.checkCancellation(); guard let state else { throw MLSError.closed }; return state.keys.authenticator
    }

    /// Releases current/tentative secrets, proposal storage and signing authority.
    /// Idempotent and synchronous inside the actor. Physical memory erasure is not promised.
    /// Recovery requires a fresh `MLSKeyPackageOwner` and an authenticated new Welcome.
    public func close() {
        if state != nil {
            DiscordLog.makeLogger("mls.group").debug("MLS group closing", metadata: ["dk.event": "mls.group.closed"])
        }
        state = nil; signingKey = nil; clearPending()
    }
    /// Fixed diagnostics deliberately omit group IDs, participants and keys.
    public nonisolated var description: String { "MLSGroup([REDACTED])" }
    /// Debug diagnostics use identical fixed redaction.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflected diagnostic traversal of actor-owned state.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Checks the exact single external-sender group extension required by DAVE v1.
    /// - Parameters:
    ///   - context: Candidate context whose version/suite were structurally checked.
    ///   - policy: Expected externally authenticated sender credential/key.
    /// - Throws: `invalidCredential` for any missing, additional or changed context extension.
    static func validateContext(_ context: MLSGroupContext, policy: MLSGroupPolicy) throws {
        guard try context.extensions == [policy.externalSender.groupExtension()] else { throw MLSError.invalidCredential }
    }

    /// Validates every leaf signature, identity, key uniqueness and DAVE leaf profile.
    /// - Parameters:
    ///   - tree: Structurally checked candidate tree, with bounded power-of-two capacity.
    ///   - context: Group ID used to verify update/commit leaf signatures.
    ///   - participants: Authenticated user authorization set, including every retained member.
    /// - Throws: Signature, identity, tree or profile validation errors before state publication.
    static func validateTree(_ tree: MLSRatchetTree, context: MLSGroupContext, participants: Set<UInt64>) throws {
        var identities: Set<Data> = []; var signatures: Set<Data> = []
        for index in 0..<tree.leafCount {
            guard let leaf = tree.leaf(at: UInt32(index)) else { continue }
            let id = try participantID(leaf.credential)
            guard participants.contains(id), leaf.extensions.isEmpty, leaf.source != .update,
                  identities.insert(leaf.credential.identity).inserted, signatures.insert(leaf.signatureKey).inserted else { throw MLSError.invalidCredential }
            try leaf.validate(now: 0, groupID: leaf.source == .keyPackage ? nil : context.groupID,
                leafIndex: leaf.source == .keyPackage ? nil : UInt32(index), validateLifetime: false)
        }
    }

    /// Verifies a joiner's complete ownership of every merged node on its own path.
    /// A missing optional Welcome path secret is valid only when each unavailable
    /// nonblank ancestor explicitly lists this leaf as unmerged. A signed but
    /// inconsistent Welcome must not consume the single-use package or strand its owner.
    /// - Parameters:
    ///   - privateKeys: Candidate node-indexed private scalars, including the own leaf key.
    ///   - tree: Authenticated public tree from GroupInfo.
    ///   - ownLeaf: Unique leaf matching the joiner's signed KeyPackage.
    /// - Throws: `invalidTree` for missing, malformed or mismatched required keys,
    ///   an invalid own leaf, or inconsistent tree math. No state is mutated.
    static func validatePrivatePath(_ privateKeys: [UInt32: Data], tree: MLSRatchetTree, ownLeaf: UInt32) throws {
        guard UInt64(ownLeaf) < UInt64(tree.leafCount), tree.leaf(at: ownLeaf) != nil else { throw MLSError.invalidTree }
        let leafNode = ownLeaf * 2
        let path = try [leafNode] + MLSTreeMath.directPath(leafNode, leafCount: tree.leafCount)
        for node in path {
            guard let publicKey = tree.encryptionKey(at: node) else { continue }
            if case .parent(let parent) = tree.nodes[Int(node)], parent.unmergedLeaves.contains(ownLeaf) { continue }
            guard let privateKey = privateKeys[node], privateKey.count == 32,
                  let parsed = try? P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey),
                  parsed.publicKey.x963Representation == publicKey else { throw MLSError.invalidTree }
        }
    }

    /// Interprets a basic credential as a nonzero Discord big-endian user ID.
    /// - Parameter credential: An untrusted basic identity assertion.
    /// - Returns: Complete unsigned snowflake without precision loss.
    /// - Throws: `invalidCredential` for non-eight-byte or zero identities.
    static func participantID(_ credential: MLSCredential) throws -> UInt64 {
        guard credential.identity.count == 8 else { throw MLSError.invalidCredential }
        let value = credential.identity.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard value != 0 else { throw MLSError.invalidCredential }; return value
    }

    /// Checks a separately authenticated proposal's intrinsic validity and session authority.
    /// - Parameters:
    ///   - proposal: Verified external Add or Remove.
    ///   - state: Current epoch against which Remove indices are interpreted.
    /// - Throws: Invalid package/identity/proposal errors without mutation.
    private func validateProposal(_ proposal: MLSProposal, state: MLSEpochState) throws {
        switch proposal {
        case .add(let package):
            try package.validate(now: 0, validateLifetime: false)
            guard expectedParticipants.contains(try Self.participantID(package.leafNode.credential)),
                  package.leafNode.extensions.isEmpty else { throw MLSError.invalidCredential }
        case .remove(let index): guard state.tree.leaf(at: index) != nil else { throw MLSError.invalidProposal }
        }
    }

    /// Applies complete reference-only membership changes in RFC Update/Remove/Add order.
    /// - Parameters:
    ///   - references: Every currently cached unrevoked reference, unique and nonempty.
    ///   - state: Current authenticated epoch, copied for failure atomicity.
    ///   - committer: Current member author, who cannot remove themselves.
    /// - Returns: Candidate tree, additions in commit order and explicit removed leaf indices.
    /// - Throws: Invalid references, duplicate removals/identities, self-removal, or capacity errors.
    private func applyProposals(_ references: [Data], to state: MLSEpochState, committer: UInt32) throws -> (tree: MLSRatchetTree, added: [(package: MLSKeyPackage, index: UInt32)], removed: Set<UInt32>) {
        guard !references.isEmpty, Set(references).count == references.count,
              Set(references) == Set(proposalOrder) else { throw MLSError.invalidCommit }
        var tree = state.tree; var removes: Set<UInt32> = []; var additions: [MLSKeyPackage] = []
        for reference in references {
            guard let entry = proposals[reference] else { throw MLSError.invalidProposal }
            try validateProposal(entry.proposal, state: state)
            switch entry.proposal {
            case .remove(let index): guard index != committer, removes.insert(index).inserted else { throw MLSError.invalidProposal }
            case .add(let package): additions.append(package)
            }
        }
        for index in removes.sorted(by: >) { try tree.remove(at: index) }
        var added: [(package: MLSKeyPackage, index: UInt32)] = []
        for package in additions { added.append((package, try tree.add(package.leafNode))) }
        // Validation precedes TreeKEM so duplicate identities cannot acquire candidate keys.
        try Self.validateTree(tree, context: state.context, participants: expectedParticipants)
        return (tree, added, removes)
    }

    /// Constructs provisional/final next context while preserving immutable profile extensions.
    /// - Parameters:
    ///   - current: Previous state with a nonexhausted epoch.
    ///   - tree: Candidate updated public tree.
    ///   - confirmed: Previous hash for path HPKE, final new hash for the key schedule.
    /// - Returns: Next-epoch context with exact tree hash.
    /// - Throws: `invalidCommit` at UInt64 epoch exhaustion or context/tree errors.
    private func nextContext(current: MLSEpochState, tree: MLSRatchetTree, confirmed: Data) throws -> MLSGroupContext {
        guard current.context.epoch < .max else { throw MLSError.invalidCommit }
        return try MLSGroupContext(groupID: current.context.groupID, epoch: current.context.epoch + 1,
            treeHash: tree.treeHash(), confirmedTranscriptHash: confirmed, extensions: current.context.extensions)
    }

    /// Removes stale path keys after proposals or an incoming public-path replacement.
    /// - Parameters:
    ///   - keys: Previously retained node-indexed private P-256 scalars.
    ///   - tree: Candidate tree; blanked or changed nodes cannot retain old key material.
    /// - Returns: Only matching node/private-key pairs, including an unchanged local leaf.
    private func retainedKeys(_ keys: [UInt32: Data], in tree: MLSRatchetTree) -> [UInt32: Data] {
        keys.filter { index, key in
            guard let publicKey = tree.encryptionKey(at: index),
                  let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: key) else { return false }
            return privateKey.publicKey.x963Representation == publicKey
        }
    }

    /// Authenticates an Add-only remote commit whose optional path is absent.
    /// - Parameters:
    ///   - message: Old-epoch signature and membership already verified.
    ///   - current: Previous authenticated state.
    ///   - tree: Tree with all additions applied.
    /// - Returns: Successful epoch advancement with the RFC all-zero commit secret.
    /// - Throws: Final transcript/confirmation validation errors; state remains unchanged.
    private func acceptWithoutPath(message: MLSPublicMessage, current: MLSEpochState, tree: MLSRatchetTree) throws -> MLSCommitOutcome {
        try finishRemote(message: message, current: current, tree: tree, privateKeys: retainedKeys(current.privateKeys, in: tree), commitSecret: Data(repeating: 0, count: 32))
    }

    /// Finalizes remote candidate secrets only after confirmation MAC acceptance.
    /// - Parameters:
    ///   - message: Fully signature/membership/path-checked commit.
    ///   - current: Prior epoch supplying init_secret and transcript.
    ///   - tree: Candidate final public tree.
    ///   - privateKeys: Authenticated own leaf/common-path keys only.
    ///   - commitSecret: Fresh path-derived or explicitly allowed all-zero secret.
    /// - Returns: `advanced` after atomic replacement and pending-state cleanup.
    /// - Throws: Confirmation or derivation errors without changing retained state.
    private func finishRemote(message: MLSPublicMessage, current: MLSEpochState, tree: MLSRatchetTree,
                              privateKeys: [UInt32: Data], commitSecret: Data) throws -> MLSCommitOutcome {
        let confirmed = try MLSCipherSuite2.hash(current.interimTranscript + message.transcriptInput())
        let context = try nextContext(current: current, tree: tree, confirmed: confirmed)
        let schedule = try MLSKeySchedule(initSecret: current.keys.initialization, commitSecret: commitSecret, groupContext: context.encoded())
        guard MLSCipherSuite2.verifyMAC(key: schedule.confirmationKey, content: confirmed, tag: message.confirmationTag) else { throw MLSError.confirmationFailed }
        let candidate = try MLSEpochState(context: context, tree: tree, ownLeaf: current.ownLeaf, privateKeys: privateKeys,
            keys: MLSEpochKeys(schedule), interimTranscript: mlsInterimTranscript(confirmed: confirmed, confirmation: message.confirmationTag))
        state = candidate; clearPending()
        DiscordLog.makeLogger("mls.group").info("MLS remote commit authenticated", metadata: ["dk.event": "mls.commit.remote_selected"])
        return .advanced
    }

    /// Builds a signed inline-tree GroupInfo and addressed Welcome for new members.
    /// - Parameters:
    ///   - added: New packages and assigned leaf indices in commit order.
    ///   - generated: Fresh path state, retained only while constructing this candidate.
    ///   - state: Final candidate public context/tree and local signer index.
    ///   - schedule: Temporary complete new schedule supplying joiner/Welcome branches.
    ///   - confirmation: New epoch confirmation MAC.
    ///   - signingKey: Local matching private signing scalar.
    /// - Returns: Complete Welcome or nil for a commit without additions.
    /// - Throws: Signature/HPKE/AEAD, tree or encoding/capacity errors; no state is published.
    private func makeWelcome(added: [(package: MLSKeyPackage, index: UInt32)], generated: MLSGeneratedUpdate,
                             state: MLSEpochState, schedule: MLSKeySchedule, confirmation: Data, signingKey: Data) throws -> Data? {
        guard !added.isEmpty else { return nil }
        var info = try MLSGroupInfo(context: state.context, extensions: [MLSExtension(type: 2, data: state.tree.encoded())],
            confirmationTag: confirmation, signer: state.ownLeaf)
        info.signature = try MLSCipherSuite2.signWithLabel(privateKey: signingKey, label: "GroupInfoTBS", content: info.signatureInput())
        let key = try MLSCipherSuite2.expandWithLabel(secret: schedule.welcomeSecret, label: "key", context: Data(), length: 16)
        let nonce = try MLSCipherSuite2.expandWithLabel(secret: schedule.welcomeSecret, label: "nonce", context: Data(), length: 12)
        let encryptedInfo = try MLSCipherSuite2.seal(key: key, nonce: nonce, plaintext: info.encoded(), authenticatedData: Data())
        var recipients: [(reference: Data, encrypted: MLSHPKECiphertext)] = []
        for addition in added {
            let ancestor = try mlsCommonAncestor(tree: state.tree, sender: state.ownLeaf, recipient: addition.index)
            let secrets = MLSWelcomeSecrets(joinerSecret: schedule.joinerSecret, pathSecret: ancestor.flatMap { generated.pathSecrets[$0] })
            let encrypted = try MLSCipherSuite2.encryptWithLabel(publicKey: addition.package.initKey, label: "Welcome",
                context: encryptedInfo, plaintext: secrets.encoded())
            recipients.append((try addition.package.reference(), encrypted))
        }
        let encoded = try MLSWelcome(secrets: recipients, encryptedGroupInfo: encryptedInfo).encoded()
        guard encoded.count <= policy.maximumMessageBytes else { throw MLSError.capacityExceeded }; return encoded
    }

    /// Releases all tentative/proposal metadata after an accepted epoch or closure.
    /// No resources remain awaiting callbacks; repeated calls are harmless.
    private func clearPending() { pending = nil; proposals.removeAll(); proposalOrder.removeAll(); proposalBytes = 0 }
}
