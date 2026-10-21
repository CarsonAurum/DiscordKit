import DiscordTestSupport
import DiscordLogging
import Crypto
import DiscordCore
import DiscordMLS
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordDAVE
@testable import DiscordVoice

/// Recovery and fail-closed protocol ownership using independently owned MLS
/// peers and synthetic authenticated Voice controls. No network/device I/O occurs.
@Suite struct DAVEProtocolSessionTests {
    private struct Fixture: Sendable {
        let session: DAVEProtocolSession
        let externalKey: Data
        let sender: MLSExternalSender
        let signingKey: Data
        let groupID: Data
        let credentials: VoiceConnectionCredentials
    }

    /// Creates one independent bounded local session with a trusted synthetic sender.
    /// - Parameters:
    ///   - maximumMembers: Membership/proposal budget for the scenario, default four.
    ///   - store: Optional shared ephemeral verification owner, default absent.
    ///   - cipherConfiguration: Optional strict per-generation attempt budget.
    /// - Returns: Local owner and explicit test authorities for independent peer messages.
    /// - Throws: Configuration or key construction errors.
    private func fixture(maximumMembers: Int = 4, store: DAVEVerificationStore? = nil,
                         cipherConfiguration: DAVEFrameCipher.Configuration = .standard) throws -> Fixture {
        let external = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: external.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data("gateway".utf8)))
        let signing = P256.Signing.PrivateKey(compactRepresentable: false)
        let credentials = VoiceConnectionCredentials(guildID: GuildID(rawValue: 3), userID: UserID(rawValue: 1),
            channelID: ChannelID(rawValue: 4), sessionID: "synthetic-session", token: "synthetic-token",
            endpoint: "voice.discord.media", generation: 7)
        let groupID = Data([0, 0, 0, 0, 0, 0, 0, 4])
        let session = try DAVEProtocolSession(identity: credentials.identity, groupID: groupID,
            signaturePrivateKey: signing.rawRepresentation, externalSender: sender,
            maximumMembers: maximumMembers, cipherConfiguration: cipherConfiguration, verificationStore: store)
        return Fixture(session: session, externalKey: external.rawRepresentation, sender: sender,
                       signingKey: signing.rawRepresentation, groupID: groupID, credentials: credentials)
    }

    /// Constructs a complete server JSON control with exact integer spellings.
    /// - Parameters:
    ///   - opcode: Documented server JSON opcode.
    ///   - data: Complete DAVE data object.
    /// - Returns: Admitted Voice frame in server direction.
    /// - Throws: JSON/Voice framing errors.
    private func json(_ opcode: UInt8, _ data: JSONValue) throws -> VoiceGatewayFrame {
        let bytes = try JSONValue.object(["op": .number(JSONNumber(rawValue: String(opcode))), "d": data]).serialized()
        return try VoiceGatewayFrame(.text(String(decoding: bytes, as: UTF8.self)))
    }

    /// Constructs a server binary control with a synthetic transport sequence.
    /// - Parameters:
    ///   - opcode: Documented server binary opcode.
    ///   - body: Exact payload excluding the transport sequence and opcode.
    /// - Returns: Admitted server Voice frame with sequence one.
    /// - Throws: Voice framing/size errors.
    private func binary(_ opcode: UInt8, _ body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([0, 1, opcode]) + body))
    }

    /// Starts protocol v1 and decodes its exact native-compatible bare public package.
    /// - Parameter setup: Fresh unstarted local session.
    /// - Returns: Valid signed public package; no owner secret escapes.
    /// - Throws: Session or package errors and fixture assertion failures.
    private func start(_ setup: Fixture) async throws -> MLSKeyPackage {
        let commands = try await setup.session.start(protocolVersion: 1)
        #expect(commands.count == 1)
        let frame = try #require(commands.first)
        #expect(frame.opcode == 26)
        guard case .binary(let bytes) = frame.payload else { throw DAVESessionError.invalidMessage }
        let package = try MLSKeyPackage.decode(bytes, messageWrapped: false)
        try package.validate(now: 0, validateLifetime: false)
        #expect(try package.leafNode.signatureKey == P256.Signing.PrivateKey(rawRepresentation: setup.signingKey).publicKey.x963Representation)
        return package
    }

    /// Opcode 26 publishes the bare native KeyPackage, with no nested MLSMessage or server sequence prefix.
    /// The published whitepaper sketch differs; libdave and complete Discord.js/Davey send paths use this form.
    @Test func keyPackageCommandMatchesNativeBareWireContract() async throws {
        let setup = try fixture()
        let commands = try await setup.session.start(protocolVersion: 1)
        let command = try #require(commands.first)
        #expect(commands.count == 1 && command.opcode == 26)
        guard case .binary(let wire) = try command.message() else { throw DAVESessionError.invalidMessage }
        #expect(wire.prefix(5) == Data([26, 0, 1, 0, 2]))
        let body = Data(wire.dropFirst())
        let package = try MLSKeyPackage.decode(body, messageWrapped: false)
        try package.validate(now: 0, expectedIdentity: Data([0, 0, 0, 0, 0, 0, 0, 1]), validateLifetime: false)
        #expect(try package.encoded(messageWrapped: false) == body)
        #expect(command.payload == .binary(body))
        #expect(throws: (any Error).self) { try MLSKeyPackage.decode(body, messageWrapped: true) }
        let wrapped = Data([0, 1, 0, 5]) + body
        #expect(throws: (any Error).self) { try MLSKeyPackage.decode(wrapped, messageWrapped: false) }
        #expect(try MLSKeyPackage.decode(wrapped, messageWrapped: true) == package)
        try await setup.session.close()
    }

    /// Creates a real remote MLS creator and its selected first-epoch Welcome.
    /// - Parameters:
    ///   - setup: Local expected group ID and trusted external signing authority.
    ///   - package: Local public KeyPackage to address in the Welcome.
    ///   - sender: Optional alternate trusted sender for an invalid-group regression.
    ///   - externalKey: Optional signing scalar matching the alternate sender.
    ///   - groupID: Optional alternate destination group ID for a mismatch regression.
    /// - Returns: Established remote group and its original public commit/Welcome.
    /// - Throws: MLS construction/authentication errors.
    private func remoteWelcome(_ setup: Fixture, package: MLSKeyPackage, sender: MLSExternalSender? = nil,
                               externalKey: Data? = nil, groupID: Data? = nil) async throws -> (MLSGroup, MLSTentativeCommit) {
        let owner = try MLSKeyPackageOwner(userID: 2)
        let policy = try MLSGroupPolicy(externalSender: sender ?? setup.sender, expectedParticipants: [1, 2])
        let id = groupID ?? setup.groupID
        let group = try await owner.createGroup(groupID: id, policy: policy)
        let proposal = try MLSProposal.add(package).externalMessage(groupID: id, epoch: 0,
                                                                    signaturePrivateKey: externalKey ?? setup.externalKey)
        _ = try await group.cacheProposal(proposal)
        let candidate = try await group.prepareCommit()
        #expect(try await group.acceptCommit(candidate.commit) == .advanced)
        return (group, candidate)
    }

    /// Delivers membership, trusted sender and a valid Welcome, then executes its
    /// transition so subsequent regressions begin with authenticated live media.
    /// - Parameter setup: Fresh local session with participant capacity at least two.
    /// - Returns: Established remote MLS group and selected initial commit bytes.
    /// - Throws: Session/MLS errors or fixture assertion failures.
    private func establish(_ setup: Fixture) async throws -> (MLSGroup, Data) {
        let package = try await start(setup)
        _ = try await setup.session.receive(json(11, .object(["user_ids": .array([.string("2")])])), now: 0)
        _ = try await setup.session.receive(binary(25, setup.sender.encoded()), now: 0)
        let (peer, candidate) = try await remoteWelcome(setup, package: package)
        let welcome = try #require(candidate.welcome)
        let ready = try await setup.session.receive(binary(30, Data([0, 7]) + welcome.dropFirst(4)), now: 1)
        #expect(ready.map(\.opcode) == [23])
        #expect(await setup.session.snapshot().activeEpoch == nil)
        _ = try await setup.session.receive(json(22, .object(["transition_id": .number(JSONNumber(rawValue: "7"))])), now: 1)
        #expect(await setup.session.snapshot().activeEpoch == 1)
        return (peer, candidate.commit)
    }

    /// Builds the separate Voice v8 reducer through transport negotiation, leaving
    /// media suspended until an actual current DAVE owner validates its exact scope.
    /// - Parameters:
    ///   - credentials: Synthetic matched account/channel/session/generation tuple.
    ///   - version: Advertised/supported DAVE version, default one.
    /// - Returns: A reducer in awaitingE2EE, with no network or media resources.
    /// - Throws: Reducer, JSON or framing errors.
    private func suspendedReducer(_ credentials: VoiceConnectionCredentials, version: UInt16 = 1) throws -> VoiceGatewaySessionState {
        var reducer = try VoiceGatewaySessionState(credentials: credentials, maximumDAVEProtocolVersion: version)
        _ = try reducer.receive(json(8, .object(["heartbeat_interval": .number(JSONNumber(rawValue: "1000"))])))
        _ = try reducer.receive(json(2, .object(["ssrc": .number(JSONNumber(rawValue: "7")),
            "ip": .string("127.0.0.1"), "port": .number(JSONNumber(rawValue: "50000")),
            "modes": .array([.string("aead_xchacha20_poly1305_rtpsize")])])))
        _ = try reducer.selectProtocol(address: "127.0.0.1", port: 50000)
        _ = try reducer.receive(json(4, .object(["mode": .string("aead_xchacha20_poly1305_rtpsize"),
            "secret_key": .array(Array(repeating: .number(JSONNumber(rawValue: "1")), count: 32)),
            "dave_protocol_version": .number(JSONNumber(rawValue: String(version)))])))
        #expect(reducer.phase == .awaitingE2EE)
        return reducer
    }

    /// Readiness comes from the current live epoch and exact account, guild,
    /// channel, session, generation and protocol version. A copied reducer cannot
    /// be authorized before group establishment or after the owner is closed.
    @Test func readinessMatchesExactCurrentReducerAndRemainsOwned() async throws {
        let setup = try fixture()
        let suspended = try suspendedReducer(setup.credentials)
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await setup.session.authorizeGateway(suspended) }
        let (peer, _) = try await establish(setup)
        let ready = try await setup.session.authorizeGateway(suspended)
        #expect(ready.phase == .ready)
        #expect(suspended.phase == .awaitingE2EE)
        let original = setup.credentials
        let variants = [
            VoiceConnectionCredentials(guildID: GuildID(rawValue: 9), userID: original.userID,
                channelID: original.channelID, sessionID: original.sessionID, token: "synthetic",
                endpoint: original.endpoint, generation: original.generation),
            VoiceConnectionCredentials(guildID: original.guildID, userID: UserID(rawValue: 9),
                channelID: original.channelID, sessionID: original.sessionID, token: "synthetic",
                endpoint: original.endpoint, generation: original.generation),
            VoiceConnectionCredentials(guildID: original.guildID, userID: original.userID,
                channelID: ChannelID(rawValue: 9), sessionID: original.sessionID, token: "synthetic",
                endpoint: original.endpoint, generation: original.generation),
            VoiceConnectionCredentials(guildID: original.guildID, userID: original.userID,
                channelID: original.channelID, sessionID: "replacement-session", token: "synthetic",
                endpoint: original.endpoint, generation: original.generation),
            VoiceConnectionCredentials(guildID: original.guildID, userID: original.userID,
                channelID: original.channelID, sessionID: original.sessionID, token: "synthetic",
                endpoint: original.endpoint, generation: 8)
        ]
        for credentials in variants {
            let mismatched = try suspendedReducer(credentials)
            await #expect(throws: VoiceControlFailure.e2eeUnavailable) { try await setup.session.authorizeGateway(mismatched) }
            #expect(mismatched.phase == .awaitingE2EE)
        }
        let mismatchedVersion = try suspendedReducer(original, version: 2)
        await #expect(throws: VoiceControlFailure.e2eeUnavailable) { try await setup.session.authorizeGateway(mismatchedVersion) }
        await #expect(throws: VoiceControlFailure.invalidTransition) { try await setup.session.authorizeGateway(ready) }
        #expect(await setup.session.snapshot().activeEpoch == 1)
        try await setup.session.close()
        await #expect(throws: DAVESessionError.closed) { try await setup.session.authorizeGateway(suspended) }
        await peer.close()
    }

    /// Invalid selected commits/Welcome trigger exactly notification then fresh
    /// package, preserve the shared signing identity, clear old media and remain open.
    @Test func invalidSelectionsRecoverWithFreshPackagesAndNoOldMedia() async throws {
        let store = try DAVEVerificationStore(localUserID: 1)
        let setup = try fixture(store: store)
        let (peer, staleCommit) = try await establish(setup)
        let fingerprint = try await store.fingerprint(sessionID: 1, userID: 2)
        try await store.confirm(sessionID: 1, userID: 2, fingerprint: fingerprint)
        #expect(await store.status(userID: 2) == .verified)
        let recovery = try await setup.session.receive(binary(29, Data([0, 8]) + staleCommit), now: 2)
        #expect(recovery.map(\.opcode) == [31, 26])
        #expect(try recovery[0].payload == .json(.object(["transition_id": .number(JSONNumber(rawValue: "8"))])))
        guard case .binary(let freshBytes) = recovery[1].payload else { throw DAVESessionError.invalidMessage }
        let fresh = try MLSKeyPackage.decode(freshBytes, messageWrapped: false)
        #expect(try fresh.leafNode.signatureKey == P256.Signing.PrivateKey(rawRepresentation: setup.signingKey).publicKey.x963Representation)
        #expect(await store.status(userID: 2) == .unavailable)
        let snapshot = await setup.session.snapshot()
        #expect(!snapshot.isClosed && snapshot.activeEpoch == nil && snapshot.retainedEpochCount == 0)
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await setup.session.seal(Data([1]), codec: .opus) }
        let repeated = try await setup.session.receive(binary(30, Data([0, 9, 0xAA])), now: 3)
        #expect(repeated.map(\.opcode) == [31, 26])
        guard case .binary(let laterBytes) = repeated[1].payload else { throw DAVESessionError.invalidMessage }
        let later = try MLSKeyPackage.decode(laterBytes, messageWrapped: false)
        #expect(later.initKey != fresh.initKey)
        #expect(later.leafNode.encryptionKey != fresh.leafNode.encryptionKey)
        #expect(later.leafNode.signatureKey == fresh.leafNode.signatureKey)
        try await setup.session.close(); await peer.close()
    }

    /// Structurally valid addressed Welcomes cannot smuggle a different group ID
    /// or external authority into the session. Each failure regenerates fresh keys.
    @Test func authenticatedWelcomeGroupAndSenderMismatchRecover() async throws {
        for wrongSender in [false, true] {
            let setup = try fixture()
            let package = try await start(setup)
            _ = try await setup.session.receive(json(11, .object(["user_ids": .array([.string("2")])])), now: 0)
            _ = try await setup.session.receive(binary(25, setup.sender.encoded()), now: 0)
            let rogue = P256.Signing.PrivateKey(compactRepresentable: false)
            let sender = try MLSExternalSender(signatureKey: rogue.publicKey.x963Representation,
                                               credential: MLSCredential(identity: Data("other".utf8)))
            let (peer, candidate) = try await remoteWelcome(setup, package: package,
                sender: wrongSender ? sender : nil, externalKey: wrongSender ? rogue.rawRepresentation : nil,
                groupID: wrongSender ? nil : Data([9]))
            let welcome = try #require(candidate.welcome)
            let result = try await setup.session.receive(binary(30, Data([0, 1]) + welcome.dropFirst(4)), now: 1)
            #expect(result.map(\.opcode) == [31, 26])
            #expect(await setup.session.snapshot().activeEpoch == nil)
            #expect(await setup.session.snapshot().isClosed == false)
            await peer.close(); try await setup.session.close()
        }
    }

    /// An absent/wrong trusted-sender package cannot enable media. Proposals before
    /// the sender package are ignored; a mismatched sender permanently closes keys.
    @Test func missingAndWrongExternalSenderFailClosed() async throws {
        let setup = try fixture()
        let package = try await start(setup)
        let empty = Data([0, 0])
        #expect(try await setup.session.receive(binary(27, empty), now: 0).isEmpty)
        _ = try await setup.session.receive(json(11, .object(["user_ids": .array([.string("2")])])), now: 0)
        let (peer, candidate) = try await remoteWelcome(setup, package: package)
        let result = try await setup.session.receive(binary(30, Data([0, 0]) + #require(candidate.welcome).dropFirst(4)), now: 0)
        #expect(result.map(\.opcode) == [31, 26])
        await #expect(throws: DAVESessionError.mediaUnavailable) { try await setup.session.seal(Data([1]), codec: .opus) }
        let rogue = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: rogue.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data("gateway".utf8)))
        await #expect(throws: DAVESessionError.externalSenderMismatch) {
            try await setup.session.receive(binary(25, sender.encoded()), now: 0)
        }
        #expect(await setup.session.snapshot().isClosed)
        await #expect(throws: DAVESessionError.closed) { try await setup.session.start(protocolVersion: 1) }
        await peer.close(); try await setup.session.close()
    }

    /// Unknown transition execution and protocol downgrade/version changes release
    /// all secrets. The failure cannot leave a send-capable active epoch behind.
    @Test func staleTransitionsDowngradesAndUnsupportedVersionsClose() async throws {
        for opcode: UInt8 in [21, 24] {
            for version in ["0", "2", "65535"] {
                let setup = try fixture()
                _ = try await start(setup)
                let field = opcode == 21 ? "transition_id" : "epoch"
                let frame = try json(opcode, .object([field: .number(JSONNumber(rawValue: "1")),
                    "protocol_version": .number(JSONNumber(rawValue: version))]))
                await #expect(throws: version == "0" ? DAVESessionError.downgradeRejected : .unsupportedVersion) {
                    try await setup.session.receive(frame, now: 1)
                }
                #expect(await setup.session.snapshot().isClosed)
                await #expect(throws: DAVESessionError.closed) { try await setup.session.seal(Data([1]), codec: .opus) }
            }
        }
        let setup = try fixture()
        let (peer, _) = try await establish(setup)
        await #expect(throws: DAVESessionError.invalidTransition) {
            try await setup.session.receive(json(22, .object(["transition_id": .number(JSONNumber(rawValue: "7"))])), now: 2)
        }
        let closedSnapshot = await setup.session.snapshot()
        #expect(closedSnapshot.isClosed && closedSnapshot.retainedEpochCount == 0)
        await peer.close()
        for version: UInt16 in [0, 2] {
            let fresh = try fixture()
            await #expect(throws: version == 0 ? DAVESessionError.downgradeRejected : .unsupportedVersion) {
                try await fresh.session.start(protocolVersion: version)
            }
            #expect(await fresh.session.snapshot().isClosed)
        }
    }

    /// Raw participant bounds include the local user; forged or unauthorized
    /// proposals fail before any mutation can produce media or leaked partial results.
    @Test func membershipBoundsAndUnauthorizedProposalsClose() async throws {
        let bound = try fixture(maximumMembers: 1)
        _ = try await start(bound)
        await #expect(throws: DAVESessionError.capacityExceeded) {
            try await bound.session.receive(json(11, .object(["user_ids": .array([.string("2")])])), now: 0)
        }
        #expect(await bound.session.snapshot().isClosed)
        for forged in [false, true] {
            let setup = try fixture()
            _ = try await start(setup)
            _ = try await setup.session.receive(binary(25, setup.sender.encoded()), now: 0)
            let outsider = try MLSKeyPackageOwner(userID: 999)
            let rogue = P256.Signing.PrivateKey(compactRepresentable: false)
            let proposal = try MLSProposal.add(outsider.keyPackage).externalMessage(groupID: setup.groupID, epoch: 0,
                signaturePrivateKey: forged ? rogue.rawRepresentation : setup.externalKey)
            var writer = MLSWriter(); writer.write(UInt8(0)); try writer.writeVector(proposal)
            await #expect(throws: forged ? MLSError.invalidSignature : .invalidCredential) {
                try await setup.session.receive(binary(27, writer.data), now: 1)
            }
            #expect(await setup.session.snapshot().isClosed)
        }
    }

    /// Independent epochs may reuse the same truncated nonce. Replay or exhausted
    /// attempt state in the pending candidate must not block authenticated active
    /// media; every candidate still enforces its own replay and attempt budgets.
    @Test func pendingReplayAndBudgetDoNotBlockIndependentActiveEpoch() async throws {
        let configuration = try DAVEFrameCipher.Configuration(maximumDecryptionsPerGeneration: 2,
            maximumFailedDecryptionsPerGeneration: 2)
        let setup = try fixture(cipherConfiguration: configuration)
        let (peer, _) = try await establish(setup)
        let senderContext = Data([2, 0, 0, 0, 0, 0, 0, 0])
        let previousSecret = try await peer.export(label: "Discord Secure Frames v0", context: senderContext, length: 16)
        let previousSender = try DAVEFrameCipher(baseSecret: previousSecret)
        let oldFirst = try await previousSender.seal(Data([1, 2, 3]), codec: .opus)
        _ = try await previousSender.seal(Data([4, 5, 6]), codec: .opus)
        let oldThird = try await previousSender.seal(Data([7, 8, 9]), codec: .opus)
        let third = try MLSKeyPackageOwner(userID: 3)
        _ = try await setup.session.receive(json(11, .object(["user_ids": .array([.string("3")])])), now: 2)
        try await peer.setExpectedParticipants([1, 2, 3])
        let proposal = try MLSProposal.add(third.keyPackage).externalMessage(groupID: setup.groupID, epoch: 1,
            signaturePrivateKey: setup.externalKey)
        var append = MLSWriter(); append.write(UInt8(0)); try append.writeVector(proposal)
        _ = try await setup.session.receive(binary(27, append.data), now: 2)
        _ = try await peer.cacheProposal(proposal)
        let selected = try await peer.prepareCommit()
        #expect(try await peer.acceptCommit(selected.commit) == .advanced)
        let ready = try await setup.session.receive(binary(29, Data([0, 8]) + selected.commit), now: 2)
        #expect(ready.map(\.opcode) == [23])
        #expect(await setup.session.snapshot().activeEpoch == 1)
        let nextSecret = try await peer.export(label: "Discord Secure Frames v0", context: senderContext, length: 16)
        let nextSender = try DAVEFrameCipher(baseSecret: nextSecret)
        for bytes in [Data([11]), Data([12])] {
            let encrypted = try await nextSender.seal(bytes, codec: .opus)
            #expect(try await setup.session.open(encrypted, senderID: 2, mediaType: .audio, now: 2) == bytes)
        }
        #expect(try await setup.session.open(oldFirst, senderID: 2, mediaType: .audio, now: 2) == Data([1, 2, 3]))
        #expect(try await setup.session.open(oldThird, senderID: 2, mediaType: .audio, now: 2) == Data([7, 8, 9]))
        await #expect(throws: DAVEError.self) {
            try await setup.session.open(oldFirst, senderID: 2, mediaType: .audio, now: 2)
        }
        try await setup.session.close(); await peer.close(); await third.close()
        await previousSender.close(); await nextSender.close()
    }

    /// Control admission rejects overlap without corrupting the admitted operation;
    /// cancellation before admission preserves the actor, and cancelled cleanup
    /// still releases all state. There are no sleeps or test-only production hooks.
    @Test func concurrentAdmissionsCancellationAndCleanup() async throws {
        let setup = try fixture()
        _ = try await start(setup)
        _ = try await setup.session.receive(binary(25, setup.sender.encoded()), now: 0)
        let frame = try json(11, .object(["user_ids": .array([.string("2")])]))
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    do { _ = try await setup.session.receive(frame, now: 1); return true }
                    catch DAVESessionError.operationInProgress { return false }
                    catch { Issue.record("Unexpected concurrent admission failure: \(type(of: error))"); return false }
                }
            }
            var count = 0; for await accepted in group where accepted { count += 1 }; return count
        }
        #expect(successes >= 1)
        #expect(await setup.session.snapshot().expectedParticipantCount == 2)
        #expect(await setup.session.snapshot().isClosed == false)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await setup.session.receive(frame, now: 1) }
            await #expect(throws: CancellationError.self) { try await setup.session.seal(Data([1]), codec: .opus) }
            await #expect(throws: CancellationError.self) { try await setup.session.open(Data([1]), senderID: 2, mediaType: .audio, now: 1) }
            try await setup.session.close()
        }
        try await cancelled.value
        let snapshot = await setup.session.snapshot()
        #expect(snapshot.isClosed && snapshot.retainedEpochCount == 0 && snapshot.expectedParticipantCount == 0)
        #expect(setup.session.description == setup.session.debugDescription)
        #expect(String(reflecting: setup.session) == "DAVEProtocolSession([REDACTED])")
        #expect(Mirror(reflecting: setup.session).children.count == 1)
        try await setup.session.close()
    }

    /// Group recreation discards every active/retired domain and preserves the
    /// shared signing identity; self-disconnect permanently closes the owner.
    @Test func epochResetSelfDisconnectAndClockFailure() async throws {
        let setup = try fixture()
        let (peer, _) = try await establish(setup)
        let reset = try await setup.session.receive(json(24, .object(["epoch": .number(JSONNumber(rawValue: "1")),
            "protocol_version": .number(JSONNumber(rawValue: "1"))])), now: 2)
        #expect(reset.map(\.opcode) == [26])
        #expect(await setup.session.snapshot().activeEpoch == nil)
        guard case .binary(let bytes) = reset[0].payload else { throw DAVESessionError.invalidMessage }
        #expect(try MLSKeyPackage.decode(bytes, messageWrapped: false).leafNode.signatureKey
                == P256.Signing.PrivateKey(rawRepresentation: setup.signingKey).publicKey.x963Representation)
        _ = try await setup.session.receive(json(13, .object(["user_id": .string("1")])), now: 2)
        #expect(await setup.session.snapshot().isClosed)
        await peer.close()
        for time in [Double.nan, .infinity, -1] {
            let fresh = try fixture(); _ = try await start(fresh)
            await #expect(throws: DAVESessionError.invalidClock) {
                try await fresh.session.receive(json(11, .object(["user_ids": .array([])])), now: time)
            }
            #expect(await fresh.session.snapshot().isClosed)
        }
    }
}

extension DAVEProtocolSessionTests {
    /// Captures coarse establishment/epoch/closure and fail-closed downgrade events while keeping
    /// signing authority, session credentials, group IDs and complete media frames out of logs.
    /// - Throws: Unexpected key construction or valid offline establishment failures.
    @Test func structuredLoggingExcludesKeysAndMedia() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let setup = try fixture()
            #expect(recorder.entries.isEmpty)
            let (peer, _) = try await establish(setup)
            let beforeFrame = recorder.entries.count
            _ = try await setup.session.seal(Data([0xf8, 0xff, 0xfe]), codec: .opus)
            #expect(recorder.entries.count == beforeFrame)
            try await setup.session.close()
            await peer.close()
            let rejected = try fixture()
            await #expect(throws: DAVESessionError.downgradeRejected) {
                try await rejected.session.start(protocolVersion: 0)
            }
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.dave.protocol" }
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "dave.session.package_prepared" })
        #expect(entries.contains { $0.level == .info && $0.metadata["dk.event"] == "dave.epoch.activated" })
        #expect(entries.contains { $0.level == .error && $0.metadata["dk.event"] == "dave.session.failed" })
        let rendered = recorder.entries.map { $0.message + String(describing: $0.metadata) }.joined()
        for secret in ["synthetic-token", "synthetic-session", "voice.discord.media", "signaturePrivateKey", "epochAuthenticator"] {
            #expect(!rendered.contains(secret))
        }
        #expect(entries.allSatisfy { Set($0.metadata.keys).isSubset(of: ["dk.event", "dk.subsystem", "dk.module", "dk.opcode", "dk.participants", "dk.commands", "dk.active_epoch", "dk.pending_epoch"]) })
    }
}
