import DiscordLogging
import Crypto
import DiscordMLS
import DiscordVoice
import Foundation

/// Bounded public session diagnostics without identities, keys, or wire payloads.
public struct DAVESessionSnapshot: Sendable, Equatable {
    public let protocolVersion: UInt16?
    public let activeEpoch: UInt64?
    public let pendingTransition: UInt16?
    public let retainedEpochCount: Int
    public let expectedParticipantCount: Int
    public let isClosed: Bool
}

/// Owns DAVE v1 MLS/signaling and encoded-frame encryption for one exact Voice session.
///
/// Construction starts no tasks, transport, devices or persistence. The caller delivers
/// authenticated Voice controls in socket order and writes returned commands once.
/// Control and media calls reject overlap while a cross-actor operation is in progress;
/// this bounds admission without creating an implicit task queue. No ambiguous mutation
/// is automatically replayed. Channel/server replacement requires a new owner.
/// The underlying owned crypto and this protocol require independent review before
/// production qualification. Swift storage cannot guarantee physical secret erasure.
public actor DAVEProtocolSession: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private struct Epoch: Sendable {
        let id: UInt64
        let ciphers: [UInt64: DAVEFrameCipher]
        let identities: [UInt64: Data]
        let authenticator: Data
    }
    private let identity: VoiceConnectionIdentity
    private let groupID: Data
    private let trustedExternalSender: MLSExternalSender
    private let maximumMembers: Int
    private let cipherConfiguration: DAVEFrameCipher.Configuration
    private let verificationStore: DAVEVerificationStore?
    private let verificationSessionID: UInt64
    private var signingKey: Data?
    private var version: UInt16?
    private var expectedParticipants: Set<UInt64>
    private var externalSenderReceived = false
    private var package: MLSKeyPackageOwner?
    private var group: MLSGroup?
    private var active: Epoch?
    private var pending: Epoch?
    private var retired: (epoch: Epoch, expires: TimeInterval)?
    private var transition: UInt16?
    private var busy = false
    private var closed = false
    private var lastTime: TimeInterval = 0

    /// Binds one inert owner to authenticated call context and a shared identity key.
    /// - Parameters:
    ///   - identity: Entire matched Voice identity, including account/channel/session/generation.
    ///   - groupID: Agreed MLS group ID, 1...255 bytes. For Discord use the authenticated
    ///     call/stream snowflake encoded as eight big-endian bytes, as in libdave.
    ///   - signaturePrivateKey: Valid P-256 raw private scalar, shared across simultaneous
    ///     related media sessions and preserved during fresh-package recovery.
    ///   - externalSender: Exact expected external basic credential and public key,
    ///     obtained through the authenticated Voice connection's trust boundary.
    ///   - maximumMembers: Participant and MLS proposal budget, 1...1024, default 256.
    ///   - cipherConfiguration: Per-sender frame, counter, ratchet and verification limits.
    ///   - verificationStore: Optional ephemeral human verification owner for this exact account;
    ///     a store bound to another user is rejected before retaining key material.
    ///   - verificationSessionID: Nonzero caller-unique store identifier, default one;
    ///     sharing a store requires distinct IDs for all simultaneous session owners.
    /// - Throws: Invalid configuration or key errors. No cryptographic material is logged.
    public init(identity: VoiceConnectionIdentity, groupID: Data, signaturePrivateKey: Data,
                externalSender: MLSExternalSender, maximumMembers: Int = 256,
                cipherConfiguration: DAVEFrameCipher.Configuration = .standard,
                verificationStore: DAVEVerificationStore? = nil, verificationSessionID: UInt64 = 1) throws {
        guard identity.userID.rawValue > 0, !groupID.isEmpty, groupID.count <= 255,
              (1...1024).contains(maximumMembers), verificationSessionID > 0,
              verificationStore == nil || verificationStore?.localUserID == identity.userID.rawValue else {
            throw DAVESessionError.invalidConfiguration
        }
        _ = try P256.Signing.PrivateKey(rawRepresentation: signaturePrivateKey)
        self.identity = identity; self.groupID = groupID.withUnsafeBytes { Data($0) }
        self.signingKey = signaturePrivateKey.withUnsafeBytes { Data($0) }
        trustedExternalSender = try MLSExternalSender(signatureKey: externalSender.signatureKey.withUnsafeBytes { Data($0) },
            credential: MLSCredential(identity: externalSender.credential.identity.withUnsafeBytes { Data($0) }))
        self.maximumMembers = maximumMembers
        self.cipherConfiguration = cipherConfiguration; self.verificationStore = verificationStore
        self.verificationSessionID = verificationSessionID; expectedParticipants = [identity.userID.rawValue]
    }

    /// Begins negotiated DAVE v1 and publishes one fresh KeyPackage command.
    /// - Parameter protocolVersion: Exact Session Description version; only one is supported.
    /// - Returns: Opcode 26 containing the bare TLS KeyPackage used by native libdave and Voice integrations.
    /// - Throws: Downgrade/version/transition, cancellation or package errors. Unsupported
    ///   versions close the owner. Repeated start never resets counters or reuses a package.
    public func start(protocolVersion: UInt16) async throws -> [VoiceGatewayFrame] {
        try begin(); defer { busy = false }
        let logger = DiscordLog.makeLogger("dave")
        logger.trace("DAVE establishment started", metadata: ["dk.event": "dave.session.started"])
        do {
            try validateVersion(protocolVersion)
            guard version == nil else { throw DAVESessionError.invalidTransition }
            version = protocolVersion
            let commands = [try await freshPackage()]
            logger.debug("DAVE key package prepared", metadata: ["dk.event": "dave.session.package_prepared"])
            return commands
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("DAVE establishment cancelled", metadata: ["dk.event": "dave.session.cancelled"])
            } else {
                logger.error("DAVE establishment failed", metadata: ["dk.event": "dave.session.failed"])
            }
            await dispose(); throw error
        }
    }

    /// Reduces one authenticated server control and returns bounded outbound commands.
    /// - Parameters:
    ///   - frame: A DAVE or membership frame from this exact authenticated Voice socket.
    ///   - now: Finite monotonically nondecreasing seconds, injected by the connection owner.
    /// - Returns: Zero or more client commands in order, at most an invalid notification
    ///   followed by a fresh package, or one commit/acknowledgement. No socket writes occur.
    /// - Throws: Cancellation before admission, overlap, clock/version/transition or wire
    ///   failures. Invalid Commit/Welcome instead resets secrets and returns recovery commands.
    ///   Other admitted failures close all secrets. A caller must serialize and process
    ///   complete results before sending another control. Lost results require a rejoin.
    public func receive(_ frame: VoiceGatewayFrame, now: TimeInterval) async throws -> [VoiceGatewayFrame] {
        try begin(); defer { busy = false }
        let logger = DiscordLog.makeLogger("dave")
        logger.trace("DAVE control admitted", metadata: ["dk.event": "dave.control.admitted"])
        do {
            try await expire(now)
            guard version != nil else { throw DAVESessionError.invalidTransition }
            let message = try DAVESignaling.decode(frame, maximumMembers: maximumMembers)
            return try await consume(message, now: now)
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("DAVE control cancelled", metadata: ["dk.event": "dave.control.cancelled"])
            } else {
                logger.error("DAVE control failed", metadata: ["dk.event": "dave.control.failed"])
            }
            await dispose(); throw error
        }
    }

    /// Protects a complete encoded frame using the active local sender epoch.
    /// - Parameters:
    ///   - frame: Reassembled encoded bytes within configured per-frame bounds.
    ///   - codec: Negotiated codec determining authenticated clear header ranges.
    /// - Returns: DAVE frame to packetize, then transport-encrypt. The active nonce is
    ///   owned by exactly one actor and is never reset by unrelated controls.
    /// - Throws: Overlap/cancellation, unavailable media, closed state or cipher/codec
    ///   errors. Old-epoch sending continues until execute, as required by DAVE.
    public func seal(_ frame: Data, codec: DAVECodec) async throws -> Data {
        try begin(); defer { busy = false }
        guard let cipher = active?.ciphers[identity.userID.rawValue] else { throw DAVESessionError.mediaUnavailable }
        return try await cipher.seal(frame, codec: codec)
    }

    /// Authenticates one complete received DAVE frame against bounded epoch candidates.
    /// - Parameters:
    ///   - frame: Reassembled frame after transport authentication and depacketization.
    ///   - senderID: User associated with the authenticated transport SSRC by the caller.
    ///   - mediaType: Audio or video; the decryptor otherwise remains codec independent.
    ///   - allowOpusSilence: Explicitly permit only the documented exact F8FFFE audio exception.
    ///   - now: Finite monotonic seconds; expired epochs are closed before authentication.
    /// - Returns: Authenticated encoded media, or explicitly admitted exceptional silence.
    /// - Throws: Overlap, cancellation, clock, membership, replay, verification or authentication
    ///   errors. Attempts include pending/active/one retired epoch; no plaintext passthrough exists.
    public func open(_ frame: Data, senderID: UInt64, mediaType: DAVEMediaType,
                     allowOpusSilence: Bool = false, now: TimeInterval) async throws -> Data {
        try begin(); defer { busy = false }
        try await expire(now)
        guard expectedParticipants.contains(senderID) else { throw DAVESessionError.mediaUnavailable }
        let candidates = [pending, active, retired?.epoch].compactMap { $0?.ciphers[senderID] }
        guard !candidates.isEmpty else { throw DAVESessionError.mediaUnavailable }
        var rejection: DAVEError = .authenticationFailed
        for cipher in candidates {
            do { return try await cipher.open(frame, mediaType: mediaType, allowOpusSilence: allowOpusSilence, now: now) }
            catch DAVEError.authenticationFailed { continue }
            catch DAVEError.generationExpired { continue }
            catch DAVEError.generationTooFarAhead { continue }
            catch DAVEError.replayedFrame { rejection = .replayedFrame; continue }
            catch DAVEError.verificationLimit { rejection = .verificationLimit; continue }
        }
        throw rejection
    }

    /// Reauthorizes a copied Voice reducer only while this actor has an active MLS epoch.
    /// - Parameter state: Suspended Voice reducer for this exact session and negotiated version.
    /// - Returns: Updated reducer whose `VoiceE2EEReadiness` check matched actual current state.
    /// - Throws: Closed/overlap/unavailable context or the reducer's exact identity/version failure.
    ///   No reusable readiness token escapes. Actual media must still pass this actor's gates.
    public func authorizeGateway(_ state: VoiceGatewaySessionState) throws -> VoiceGatewaySessionState {
        guard !closed else { throw DAVESessionError.closed }
        guard !busy else { throw DAVESessionError.operationInProgress }
        guard version == 1, externalSenderReceived, active != nil else { throw DAVESessionError.mediaUnavailable }
        var next = state
        try next.authorizeMedia(using: Readiness(identity: identity))
        return next
    }

    /// Returns bounded nonsecret state without traversing MLS, frames or identities.
    /// - Returns: Current negotiated version, active epoch, transition and retained counts.
    public func snapshot() -> DAVESessionSnapshot {
        DAVESessionSnapshot(protocolVersion: version, activeEpoch: active?.id, pendingTransition: transition,
            retainedEpochCount: [active, pending, retired?.epoch].compactMap { $0 }.count,
            expectedParticipantCount: expectedParticipants.count, isClosed: closed)
    }

    /// Closes all key owners and invalidates optional human verification state.
    /// - Throws: `operationInProgress` if an admitted cross-actor call has not finished;
    ///   await that call and retry. Repeated closure succeeds and cancellation cannot prevent it.
    public func close() async throws {
        guard !busy else { throw DAVESessionError.operationInProgress }
        busy = true; defer { busy = false }
        if !closed {
            DiscordLog.makeLogger("dave").debug("DAVE session closing", metadata: ["dk.event": "dave.session.closing"])
        }
        await dispose()
    }

    /// Keeps all retained identity, wire and key material out of ordinary logs.
    public nonisolated var description: String { "DAVEProtocolSession([REDACTED])" }
    /// Uses the same fixed redaction for explicit debug formatting.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflection from revealing the retained session and epoch owners.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Bridges synchronous Voice readiness only within the owning session actor's call.
    private struct Readiness: VoiceE2EEReadiness {
        let identity: VoiceConnectionIdentity
        /// Matches complete identity and supported version after actor-local epoch validation.
        /// - Parameters:
        ///   - protocolVersion: Version requested by the suspended Voice reducer.
        ///   - identity: Exact reducer identity including session/generation.
        /// - Throws: `e2eeUnavailable` on any mismatch; performs no I/O or suspension.
        func validateSession(protocolVersion: UInt16, identity: VoiceConnectionIdentity) throws {
            guard protocolVersion == 1, identity == self.identity else { throw VoiceControlFailure.e2eeUnavailable }
        }
    }

    /// Reserves one bounded operation before its first suspension.
    /// - Throws: Closed, cancellation or overlap without altering the admitted operation.
    private func begin() throws {
        guard !closed else { throw DAVESessionError.closed }
        try Task.checkCancellation()
        guard !busy else { throw DAVESessionError.operationInProgress }
        busy = true
    }

    /// Enforces the implemented wire version and forbids transport-only downgrades.
    /// - Parameter proposed: Authenticated server version; zero always fails closed.
    /// - Throws: `downgradeRejected` for zero; `unsupportedVersion` for versions above one.
    private func validateVersion(_ proposed: UInt16) throws {
        guard proposed != 0 else { throw DAVESessionError.downgradeRejected }
        guard proposed == 1 else { throw DAVESessionError.unsupportedVersion }
    }

    /// Builds current trusted MLS admission bounds from authenticated connected participants.
    /// - Returns: Exact external-sender and membership policy, with no network authority added.
    /// - Throws: MLS configuration errors when a caller-selected resource bound is inconsistent.
    private func policy() throws -> MLSGroupPolicy {
        try MLSGroupPolicy(externalSender: trustedExternalSender, expectedParticipants: expectedParticipants,
            maximumMembers: maximumMembers, maximumProposals: maximumMembers)
    }

    /// Publishes fresh HPKE keys while preserving this account's shared signing identity.
    /// - Returns: One bare KeyPackage command; creates a pending epoch-zero group
    ///   when the trusted external sender has already been received.
    /// - Throws: Key generation, policy or wire errors; caller closes on failure.
    private func freshPackage() async throws -> VoiceGatewayFrame {
        guard let signingKey else { throw DAVESessionError.closed }
        let owner = try MLSKeyPackageOwner(userID: identity.userID.rawValue, signaturePrivateKey: signingKey)
        package = owner
        if externalSenderReceived { group = try await owner.createGroup(groupID: groupID, policy: policy(), retainForWelcome: true) }
        return try DAVESignaling.binaryCommand(opcode: 26, body: owner.keyPackage.encoded(messageWrapped: false))
    }

    /// Executes one parsed control under the actor's exclusive bounded admission.
    /// - Parameters:
    ///   - message: Parsed control from this authenticated Voice connection.
    ///   - now: Already checked monotonic seconds used for epoch expiry.
    /// - Returns: Ordered client commands; invalid MLS selection produces fresh-package recovery.
    /// - Throws: Invalid transition, membership, version, signature or capacity errors.
    private func consume(_ message: DAVESignaling, now: TimeInterval) async throws -> [VoiceGatewayFrame] {
        switch message {
        case .connected(let ids):
            let next = expectedParticipants.union(ids)
            guard next.count <= maximumMembers else { throw DAVESessionError.capacityExceeded }
            expectedParticipants = next; try await group?.setExpectedParticipants(next); return []
        case .disconnected(let id):
            guard id != identity.userID.rawValue else { await dispose(); return [] }
            expectedParticipants.remove(id); try await group?.setExpectedParticipants(expectedParticipants)
            await verificationStore?.removeSession(sessionID: verificationSessionID)
            return []
        case .externalSender(let sender):
            guard sender == trustedExternalSender else { throw DAVESessionError.externalSenderMismatch }
            if !externalSenderReceived {
                externalSenderReceived = true
                guard let package else { throw DAVESessionError.invalidTransition }
                group = try await package.createGroup(groupID: groupID, policy: policy(), retainForWelcome: true)
            }
            return []
        case .prepareEpoch(let epoch, let proposed):
            try validateVersion(proposed)
            if epoch == 1 { return [try await recover()] }
            guard let group, await group.snapshot().epoch == epoch else { throw DAVESessionError.invalidTransition }
            return []
        case .prepareTransition(let id, let proposed):
            try validateVersion(proposed)
            guard transition == nil || transition == id else { throw DAVESessionError.invalidTransition }
            if id == 0 {
                // The documented sole-member initialization may activate the local epoch-zero group.
                guard let group, active == nil, pending == nil, expectedParticipants.count == 1 else {
                    throw DAVESessionError.invalidTransition
                }
                pending = try await makeEpoch(group, allowInitial: true)
                transition = 0; try await activate(now: now); return []
            }
            guard pending != nil || active != nil else { throw DAVESessionError.invalidTransition }
            transition = id
            return [try DAVESignaling.transitionCommand(opcode: 23, transitionID: id)]
        case .executeTransition(let id):
            guard transition == id else { throw DAVESessionError.invalidTransition }
            try await activate(now: now); return []
        case .appendProposals(let messages):
            guard transition == nil else { throw DAVESessionError.invalidTransition }
            guard let group else { return [] }
            for bytes in messages { _ = try await group.cacheProposal(bytes) }
            return try await prepareCommit(group)
        case .revokeProposals(let references):
            guard transition == nil else { throw DAVESessionError.invalidTransition }
            guard let group else { return [] }
            for reference in references { try await group.revokeProposal(reference) }
            return try await prepareCommit(group)
        case .commit(let id, let bytes):
            do {
                guard transition == nil, let group else { throw DAVESessionError.invalidTransition }
                if try await group.acceptCommit(bytes) == .removed { return [try await recover()] }
                pending = try await makeEpoch(group)
                await package?.close(); package = nil
                return try await acknowledge(id, now: now)
            } catch { return try await invalidSelection(id) }
        case .welcome(let id, let bytes):
            do {
                guard externalSenderReceived, transition == nil, let package else { throw DAVESessionError.invalidTransition }
                await group?.close(); group = nil
                let joined = try await package.join(welcome: bytes, expectedGroupID: groupID, policy: policy())
                group = joined; self.package = nil
                pending = try await makeEpoch(joined)
                return try await acknowledge(id, now: now)
            } catch { return try await invalidSelection(id) }
        }
    }

    /// Emits the current complete candidate only when unrevoked proposals remain.
    /// - Parameter group: Current local group; candidate bytes are idempotent until invalidated.
    /// - Returns: Empty when no proposals remain, otherwise opcode 28 with a bare Welcome suffix.
    /// - Throws: MLS proposal/commit or bounded framing errors; current state is not advanced.
    private func prepareCommit(_ group: MLSGroup) async throws -> [VoiceGatewayFrame] {
        guard await group.snapshot().pendingProposalCount > 0 else { return [] }
        // A member proposed for removal cannot commit its own removal; another member must win.
        let candidate: MLSTentativeCommit
        do { candidate = try await group.prepareCommit() }
        catch MLSError.invalidProposal { return [] }
        var bytes = candidate.commit
        if let welcome = candidate.welcome { bytes.append(welcome.dropFirst(4)) }
        return [try DAVESignaling.binaryCommand(opcode: 28, body: bytes)]
    }

    /// Creates bounded sender-domain owners from an authenticated MLS exporter.
    /// - Parameters:
    ///   - group: Valid current group after successful commit/Welcome validation.
    ///   - allowInitial: Only true for documented sole-member epoch-zero initialization.
    /// - Returns: Fresh receive/send domains for exactly this epoch's admitted members.
    /// - Throws: MLS/cipher errors. Partially created inert domains are released on failure.
    private func makeEpoch(_ group: MLSGroup, allowInitial: Bool = false) async throws -> Epoch {
        guard let epoch = await group.snapshot().epoch else { throw DAVESessionError.mediaUnavailable }
        let identities: [UInt64: Data]
        if epoch == 0 && allowInitial, let signingKey {
            identities = [identity.userID.rawValue: try P256.Signing.PrivateKey(rawRepresentation: signingKey).publicKey.x963Representation]
        } else { identities = try await group.memberIdentities() }
        var ciphers: [UInt64: DAVEFrameCipher] = [:]
        for user in identities.keys {
            let context = Data((0..<8).map { UInt8(truncatingIfNeeded: user >> ($0 * 8)) })
            let secret = try await group.export(label: "Discord Secure Frames v0", context: context, length: 16)
            ciphers[user] = try DAVEFrameCipher(baseSecret: secret, configuration: cipherConfiguration)
        }
        return try await Epoch(id: epoch, ciphers: ciphers, identities: identities, authenticator: group.epochAuthenticator())
    }

    /// Marks a validated epoch ready, or immediately activates initialization transition zero.
    /// - Parameters:
    ///   - id: Server-selected transition identifier.
    ///   - now: Monotonic seconds for retirement deadlines.
    /// - Returns: Opcode 23 except for immediate zero initialization.
    /// - Throws: Activation or frame construction errors; caller initiates recovery.
    private func acknowledge(_ id: UInt16, now: TimeInterval) async throws -> [VoiceGatewayFrame] {
        transition = id
        if id == 0 { try await activate(now: now); return [] }
        return [try DAVESignaling.transitionCommand(opcode: 23, transitionID: id)]
    }

    /// Switches transmit epoch exactly once and caps old receive retention at ten seconds.
    /// - Parameter now: Monotonic seconds; no timer is created and expiry is checked on input.
    /// - Throws: Invalid transition or verification-store errors. Identical-epoch transitions
    ///   reuse the existing cipher owners so counters cannot reset.
    private func activate(now: TimeInterval) async throws {
        if let pending {
            if let retired { await closeEpoch(retired.epoch); self.retired = nil }
            if let active { retired = (active, now + 10) }
            active = pending; self.pending = nil
        }
        guard let active else { throw DAVESessionError.invalidTransition }
        transition = nil
        DiscordLog.makeLogger("dave").debug("DAVE epoch activated", metadata: ["dk.event": "dave.epoch.activated"])
        if active.id > 0 {
            try await verificationStore?.replaceSession(sessionID: verificationSessionID, epoch: active.id,
                identities: active.identities, epochAuthenticator: active.authenticator)
        }
    }

    /// Resets invalid MLS state and emits the required notification followed by a new package.
    /// - Parameter id: Failed server selection's transition ID, retained only in outgoing command.
    /// - Returns: Opcodes 31 then 26; no old media may continue during recovery.
    /// - Throws: Encoding, fresh-key generation or policy errors, requiring a new session.
    private func invalidSelection(_ id: UInt16) async throws -> [VoiceGatewayFrame] {
        let invalid = try DAVESignaling.transitionCommand(opcode: 31, transitionID: id)
        return [invalid, try await recover()]
    }

    /// Closes old epochs/group/package and produces fresh HPKE keys with the same identity.
    /// - Returns: New KeyPackage command; negotiated version and authenticated membership survive.
    /// - Throws: New key or policy errors. Cleared secrets cannot be restored after failure.
    private func recover() async throws -> VoiceGatewayFrame {
        DiscordLog.makeLogger("dave").warning("DAVE key establishment recovering", metadata: ["dk.event": "dave.session.recovering"])
        await clearEpochs(); await group?.close(); group = nil
        await package?.close(); package = nil; transition = nil
        await verificationStore?.removeSession(sessionID: verificationSessionID)
        return try await freshPackage()
    }

    /// Checks injected monotonic time and releases expired receive-only epoch references.
    /// - Parameter now: Finite seconds greater than or equal to the previous observation.
    /// - Throws: `invalidClock` before any expiry mutation for invalid/backward time.
    private func expire(_ now: TimeInterval) async throws {
        guard now.isFinite, now >= lastTime else { throw DAVESessionError.invalidClock }
        lastTime = now
        if let retired, now >= retired.expires { self.retired = nil; await closeEpoch(retired.epoch) }
    }

    /// Releases every sender's logical key state for one obsolete epoch.
    /// - Parameter epoch: Disjoint sender owners; none may remain an active transmit domain.
    private func closeEpoch(_ epoch: Epoch) async {
        for cipher in epoch.ciphers.values { await cipher.close() }
    }

    /// Drops all epoch references before awaiting idempotent cipher cleanup.
    private func clearEpochs() async {
        let epochs = [active, pending, retired?.epoch].compactMap { $0 }
        active = nil; pending = nil; retired = nil
        for epoch in epochs { await closeEpoch(epoch) }
    }

    /// Permanently invalidates admission before releasing every subordinate key owner.
    /// Cleanup ignores task cancellation and is safe to invoke repeatedly.
    private func dispose() async {
        closed = true; signingKey = nil; version = nil; transition = nil
        expectedParticipants.removeAll(); externalSenderReceived = false
        await clearEpochs(); await group?.close(); group = nil
        await package?.close(); package = nil
        await verificationStore?.removeSession(sessionID: verificationSessionID)
    }
}
