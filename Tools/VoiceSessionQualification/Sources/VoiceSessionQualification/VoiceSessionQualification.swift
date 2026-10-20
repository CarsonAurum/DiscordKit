import DiscordCore
import DiscordDAVE
import DiscordLogging
import DiscordMLS
import DiscordMedia
import DiscordModels
import DiscordNIOTransport
import DiscordTransport
import DiscordVoice
import DiscordVoiceCodecs
import DiscordVoiceCrypto
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Redacted failures of this local synthetic qualification executable.
enum QualificationFailure: Error { case invalidArguments, invariant, unsupportedRSS }

/// One actual resident-memory observation during the measured, post-warmup interval.
struct ResidentMeasurement: Codable {
    var elapsedSeconds: Double
    var residentBytes: UInt64
}

/// The bounded evidence emitted by one actual-wall-clock localhost duplex run.
struct QualificationReport: Codable {
    var schemaVersion = 2
    var scope = "actual-wall-clock localhost UDP; synthetic PCM and authenticated MLS/DAVE signaling; no audio devices or Discord"
    var startedAt: String
    var requestedSeconds: Double
    var elapsedSeconds: Double
    var warmupFramesPerDirection: Int
    var warmupElapsedSeconds: Double
    var warmupDecodedSampleFrames: Int
    var lifetimeTotalSentPackets: UInt64
    var lifetimeTotalReceivedPackets: UInt64
    var framesPerDirection: Int
    var totalSentPackets: UInt64
    var totalReceivedPackets: UInt64
    var decodedSampleFrames: Int
    var concealedPackets: UInt64
    var processingP50Milliseconds: Double
    var processingP95Milliseconds: Double
    var processingP99Milliseconds: Double
    var processingMaximumMilliseconds: Double
    var processingBudgetOverruns: Int
    var scheduleUnderruns: Int
    var peakBufferedMediaBytes: Int
    var finalBufferedMediaBytes: Int
    var rssInitialBytes: UInt64
    var rssFinalBytes: UInt64
    var rssSampledHighBytes: UInt64
    var coldRSSBytes: UInt64
    var rssGrowthAfterWarmupBytes: Int64
    var rssFirstMinuteMedianBytes: UInt64
    var rssLastMinuteMedianBytes: UInt64
    var rssAfterResourceCloseBytes: UInt64
    var rssMeasurements: [ResidentMeasurement]
    var timingSampleAccountedBytes: Int
    var configuredMediaBufferCapacityBytes: Int
    var configuredUDPPendingPayloadCapacityBytes: Int
    var sampledMaximumPendingDAVEOperations: Int
    var closedMediaOwners: Int
    var closedDAVEOwners: Int
    var closedDatagramOwners: Int
    var successful: Bool
}

/// Runs an explicitly paced, bounded real localhost full-duplex media exchange.
/// Fixed private keys are public test fixtures and never authenticate Discord.
@main struct VoiceSessionQualification {
    /// Parses finite CLI policy, runs the exchange, and emits one JSON evidence object.
    /// `--seconds` defaults to 600 measured seconds and accepts 0.02...3600; a
    /// separate 100-frame/two-second warmup precedes measurement. `--output`
    /// optionally writes the same report atomically. Errors terminate nonzero after cleanup.
    /// Process-owned SwiftLog diagnostics go to stderr, preserving stdout JSON.
    /// - Throws: Invalid CLI input, local networking, cryptographic, codec or file errors.
    static func main() async throws {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        var seconds = 600.0
        var output: String?
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw QualificationFailure.invalidArguments }
            switch arguments[index] {
            case "--seconds":
                guard let value = Double(arguments[index + 1]), value.isFinite, (0.02...3600).contains(value) else {
                    throw QualificationFailure.invalidArguments
                }
                seconds = value
            case "--output": output = arguments[index + 1]
            default: throw QualificationFailure.invalidArguments
            }
            index += 2
        }
        let report = try await run(seconds: seconds)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(report)
        if let output { try bytes.write(to: URL(fileURLWithPath: output), options: .atomic) }
        print(String(decoding: bytes, as: UTF8.self))
        guard report.successful else { throw QualificationFailure.invariant }
    }

    /// Creates matched synthetic credentials through the production two-event rendezvous.
    /// - Parameter user: Nonzero fixture participant ID.
    /// - Returns: Exact inert Voice identity; no Gateway request or socket is created.
    /// - Throws: Fixture decoding/rendezvous failures.
    private static func credentials(_ user: UInt64) throws -> VoiceConnectionCredentials {
        var join = try VoiceJoinRendezvous(guildID: .init(rawValue: 5), userID: .init(rawValue: user), channelID: .init(rawValue: 6))
        let state = try VoiceState(data: Data("{\"guild_id\":\"5\",\"channel_id\":\"6\",\"user_id\":\"\(user)\",\"session_id\":\"localhost-\(user)\",\"deaf\":false,\"mute\":false,\"self_deaf\":false,\"self_mute\":false,\"self_video\":false,\"suppress\":false,\"request_to_speak_timestamp\":null}".utf8))
        _ = try join.receive(state: state, generation: join.generation)
        let server = try GatewayVoiceServerUpdate(data: Data(#"{"guild_id":"5","token":"public-fixture-token","endpoint":"localhost.invalid"}"#.utf8))
        guard let result = try join.receive(server: server, generation: join.generation) else { throw QualificationFailure.invariant }
        return result
    }

    /// Builds one synthetic authenticated-server JSON control from exact data fields.
    /// - Parameters:
    ///   - opcode: Documented server opcode.
    ///   - fields: Complete bounded JSON data object.
    /// - Returns: Parsed direction-validated Voice frame.
    /// - Throws: JSON or frame-shape failures.
    private static func json(_ opcode: UInt8, _ fields: [String: JSONValue]) throws -> VoiceGatewayFrame {
        let value = try JSONValue.object(["op": .number(JSONNumber(rawValue: String(opcode))), "d": .object(fields)]).serialized()
        return try VoiceGatewayFrame(.text(String(decoding: value, as: UTF8.self)))
    }

    /// Adds server binary sequence/opcode framing without inventing MLS body lengths.
    /// - Parameters:
    ///   - opcode: DAVE server opcode.
    ///   - body: Complete body excluding sequence/opcode.
    /// - Returns: Parsed server-direction frame with fixture sequence one.
    /// - Throws: Voice framing failures.
    private static func binary(_ opcode: UInt8, _ body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([0, 1, opcode]) + body))
    }

    /// Starts an inert DAVE owner and delivers trusted synthetic membership/sender controls.
    /// - Parameters:
    ///   - owner: Fresh exact-session adapter.
    ///   - sender: Expected MLS external authority, fixed public fixture only.
    /// - Returns: Signed public KeyPackage; private key material remains owner-scoped.
    /// - Throws: DAVE signaling, MLS wire or invariant failures.
    private static func initialize(_ owner: DAVEVoiceSession, sender: MLSExternalSender) async throws -> MLSKeyPackage {
        let commands = try await owner.start(protocolVersion: 1)
        guard commands.count == 1, commands[0].opcode == 26, case .binary(let bytes) = commands[0].payload else {
            throw QualificationFailure.invariant
        }
        _ = try await owner.receive(json(11, ["user_ids": .array([.string("1"), .string("2")])]), now: 0)
        _ = try await owner.receive(binary(25, sender.encoded()), now: 0)
        return try MLSKeyPackage.decode(bytes, messageWrapped: false)
    }

    /// Establishes a real two-member MLS epoch through public adapter signaling methods.
    /// - Parameters:
    ///   - first: Creator's exact-session DAVE owner.
    ///   - second: Joining participant's independent exact-session DAVE owner.
    ///   - sender: Trusted public fixture external authority.
    ///   - externalKey: Public fixture scalar signing the authenticated external Add.
    /// - Throws: MLS/signaling failures or invalid expected transition responses.
    private static func establish(_ first: DAVEVoiceSession, _ second: DAVEVoiceSession,
                                  sender: MLSExternalSender, externalKey: Data) async throws {
        _ = try await initialize(first, sender: sender)
        let package = try await initialize(second, sender: sender)
        let proposal = try MLSProposal.add(package).externalMessage(groupID: Data([0, 0, 0, 0, 0, 0, 0, 6]),
            epoch: 0, signaturePrivateKey: externalKey)
        var envelope = MLSWriter(); envelope.write(UInt8(0)); try envelope.writeVector(proposal)
        let commands = try await first.receive(binary(27, envelope.data), now: 0)
        guard commands.count == 1, commands[0].opcode == 28, case .binary(let bytes) = commands[0].payload else {
            throw QualificationFailure.invariant
        }
        let candidate = try MLSTentativeCommit.decodeDAVECommitWelcome(bytes)
        guard let welcome = candidate.welcome else { throw QualificationFailure.invariant }
        let firstReady = try await first.receive(binary(29, Data([0, 7]) + candidate.commit), now: 0)
        let secondReady = try await second.receive(binary(30, Data([0, 7]) + welcome.dropFirst(4)), now: 0)
        guard firstReady.map(\.opcode) == [23], secondReady.map(\.opcode) == [23] else { throw QualificationFailure.invariant }
        for owner in [first, second] {
            _ = try await owner.receive(json(22, ["transition_id": .number(JSONNumber(rawValue: "7"))]), now: 0)
            try await owner.bindSSRC(111, userID: .init(rawValue: 1))
            try await owner.bindSSRC(222, userID: .init(rawValue: 2))
        }
    }

    /// Produces an awaiting-E2EE reducer so pipeline admission uses real epoch authorization.
    /// - Parameter credentials: Exact adapter account/guild/channel/session/generation.
    /// - Returns: Reducer suspended after transport Session Description.
    /// - Throws: Voice framing, negotiation or fixture errors.
    private static func suspended(_ credentials: VoiceConnectionCredentials) throws -> VoiceGatewaySessionState {
        var state = try VoiceGatewaySessionState(credentials: credentials, maximumDAVEProtocolVersion: 1)
        _ = try state.receive(json(8, ["heartbeat_interval": .number(JSONNumber(rawValue: "1000"))]))
        _ = try state.receive(json(2, ["ssrc": .number(JSONNumber(rawValue: "111")), "ip": .string("127.0.0.1"),
            "port": .number(JSONNumber(rawValue: "50000")), "modes": .array([.string("aead_xchacha20_poly1305_rtpsize")])]))
        _ = try state.selectProtocol(address: "127.0.0.1", port: 50000)
        _ = try state.receive(json(4, ["mode": .string("aead_xchacha20_poly1305_rtpsize"),
            "secret_key": .array(Array(repeating: .number(JSONNumber(rawValue: "1")), count: 32)),
            "dave_protocol_version": .number(JSONNumber(rawValue: "1"))]))
        return state
    }

    /// Measures current resident memory using the host OS rather than allocator accounting.
    /// - Returns: Actual resident bytes on supported macOS/Linux; unsupported hosts fail.
    /// - Throws: `unsupportedRSS` if the native gauge cannot be obtained.
    private static func residentBytes() throws -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw QualificationFailure.unsupportedRSS }
        return UInt64(info.resident_size)
        #elseif canImport(Glibc)
        let text = try String(contentsOfFile: "/proc/self/statm", encoding: .utf8)
        guard let pages = text.split(separator: " ").dropFirst().first.flatMap({ UInt64($0) }) else {
            throw QualificationFailure.unsupportedRSS
        }
        return pages * UInt64(sysconf(Int32(_SC_PAGESIZE)))
        #else
        throw QualificationFailure.unsupportedRSS
        #endif
    }

    /// Converts continuous elapsed duration to seconds without consulting wall time.
    /// - Parameter duration: Monotonic measured duration.
    /// - Returns: Fractional seconds, including subsecond attosecond components.
    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// Selects a nearest-rank percentile from a nonempty sorted finite timing sample.
    /// - Parameters:
    ///   - sorted: Ascending nonempty processing-time milliseconds.
    ///   - fraction: Requested quantile from zero through one.
    /// - Returns: Nearest-rank sample; zero for empty input as a defensive report fallback.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
    }

    /// Runs real paced localhost UDP duplex with bounded media/DAVE/socket ownership.
    /// - Parameter seconds: Finite measured actual-wall-clock duration, 0.02...3600,
    ///   following a separate 100-frame/two-second warmup without resetting key/codec state.
    /// - Returns: Measured and lifetime packet counters, processing latencies, cold and
    ///   post-warmup RSS traces, buffer bounds, and evidence after sockets/keys close.
    /// - Throws: Native loopback, crypto, codec, invariant or RSS errors after cleanup.
    private static func run(seconds requestedSeconds: Double) async throws -> QualificationReport {
        let clock = ContinuousClock()
        let origin = clock.now
        let now: @Sendable () -> TimeInterval = { seconds(origin.duration(to: clock.now)) }
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
        let externalKey = Data(repeating: 1, count: 32)
        let fixtureOwner = try MLSKeyPackageOwner(userID: 99)
        let leaf = try MLSLeafNode.generate(identity: Data("localhost-fixture-external".utf8),
            signaturePrivateKey: externalKey, encryptionKey: fixtureOwner.keyPackage.leafNode.encryptionKey)
        let sender = try MLSExternalSender(signatureKey: leaf.signatureKey, credential: leaf.credential)
        await fixtureOwner.close()
        let firstCredentials = try credentials(1), secondCredentials = try credentials(2)
        let group = Data([0, 0, 0, 0, 0, 0, 0, 6])
        let firstDAVE = try DAVEVoiceSession(identity: firstCredentials.identity, groupID: group,
            signaturePrivateKey: Data(repeating: 2, count: 32), externalSender: sender, maximumParticipants: 2, now: now)
        let secondDAVE = try DAVEVoiceSession(identity: secondCredentials.identity, groupID: group,
            signaturePrivateKey: Data(repeating: 3, count: 32), externalSender: sender, maximumParticipants: 2, now: now)
        var firstSocket: NIODatagramTransport?
        var secondSocket: NIODatagramTransport?
        var firstMedia: VoiceMediaPipeline<ContinuousClock>?
        var secondMedia: VoiceMediaPipeline<ContinuousClock>?
        var cipher: VoiceTransportCipher?
        do {
            try await establish(firstDAVE, secondDAVE, sender: sender, externalKey: externalKey)
            let firstUDP = try await NIODatagramTransport.bind(maximumDatagramBytes: 4_096,
                maximumPendingDatagrams: 8, maximumPendingBytes: 32_768, context: context)
            firstSocket = firstUDP
            let secondUDP = try await NIODatagramTransport.bind(maximumDatagramBytes: 4_096,
                maximumPendingDatagrams: 8, maximumPendingBytes: 32_768, context: context)
            secondSocket = secondUDP
            // Every same-key transmitter shares one counter authority; no counter domain is reset.
            let transportCipher = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize,
                key: Data(repeating: 23, count: 32), maximumReceiveStreams: 2)
            cipher = transportCipher
            let first = try VoiceMediaPipeline(clock: clock, transport: firstUDP, peer: secondUDP.localAddress,
                cipher: transportCipher, transformer: firstDAVE, ssrc: 111, encoder: OpusAudioEncoder(),
                maximumReceiveStreams: 1, maximumBufferedBytes: 16_384)
            firstMedia = first
            let second = try VoiceMediaPipeline(clock: clock, transport: secondUDP, peer: firstUDP.localAddress,
                cipher: transportCipher, transformer: secondDAVE, ssrc: 222, encoder: OpusAudioEncoder(),
                maximumReceiveStreams: 1, maximumBufferedBytes: 16_384)
            secondMedia = second
            try await first.registerReceiveStream(ssrc: 222, capacity: 8, maximumBytes: 16_384)
            try await second.registerReceiveStream(ssrc: 111, capacity: 8, maximumBytes: 16_384)
            guard try await firstDAVE.authorizeGateway(suspended(firstCredentials)).phase == .ready,
                  try await secondDAVE.authorizeGateway(suspended(secondCredentials)).phase == .ready else {
                throw QualificationFailure.invariant
            }
            await first.setAuthorized(true); await second.setAuthorized(true)
            let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
            let pcm = try PCMBuffer(format: format, samples: (0..<960).map {
                Float(sin(Double($0) * 2 * .pi * 440 / 48_000) * 0.2)
            })
            let frameCount = Int(ceil(requestedSeconds * 50))
            let warmupFrames = 100
            var timings: [Double] = []; timings.reserveCapacity(frameCount)
            var rssMeasurements: [ResidentMeasurement] = []
            rssMeasurements.reserveCapacity(Int(ceil(requestedSeconds)) + 2)
            var overruns = 0, underruns = 0, decoded = 0, peakBuffered = 0, maximumPending = 0
            let coldRSS = try residentBytes()
            var rssInitial: UInt64 = 0, rssHigh: UInt64 = 0
            var startedAt = ""
            let warmupStart = clock.now
            var warmupElapsed = 0.0
            var start = warmupStart
            for index in 0..<(warmupFrames + frameCount) {
                if index == warmupFrames {
                    try await clock.sleep(until: warmupStart.advanced(by: .seconds(2)), tolerance: .zero)
                    warmupElapsed = seconds(warmupStart.duration(to: clock.now))
                    rssInitial = try residentBytes(); rssHigh = rssInitial
                    startedAt = ISO8601DateFormatter().string(from: Date())
                    start = clock.now
                    rssMeasurements.append(.init(elapsedSeconds: 0, residentBytes: rssInitial))
                }
                let measuring = index >= warmupFrames
                let measuredIndex = index - warmupFrames
                let slotIndex = measuring ? measuredIndex : index
                let slotOrigin = measuring ? start : warmupStart
                let deadline = slotOrigin.advanced(by: .milliseconds(Int64(slotIndex) * 20))
                try await clock.sleep(until: deadline, tolerance: .zero)
                if measuring, deadline.duration(to: clock.now) > .milliseconds(20) { underruns += 1 }
                let operationStart = clock.now
                let operationContext = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(2)))
                async let firstSent = first.send(pcm, context: operationContext)
                async let secondSent = second.send(pcm, context: operationContext)
                let sent = try await (firstSent, secondSent)
                guard sent.0, sent.1 else { throw QualificationFailure.invariant }
                async let firstInput = firstUDP.receiveDatagram(context: operationContext)
                async let secondInput = secondUDP.receiveDatagram(context: operationContext)
                let input = try await (firstInput, secondInput)
                guard let a = input.0, let b = input.1 else { throw QualificationFailure.invariant }
                try await first.receive(a); try await second.receive(b)
                let buffered = await first.snapshot().bufferedBytes + second.snapshot().bufferedBytes
                if measuring { peakBuffered = max(peakBuffered, buffered) }
                guard let firstPCM = try await first.playout(ssrc: 222),
                      let secondPCM = try await second.playout(ssrc: 111),
                      !firstPCM.concealed, !secondPCM.concealed,
                      firstPCM.pcm.frameCount == 960, secondPCM.pcm.frameCount == 960,
                      firstPCM.pcm.samples.allSatisfy(\.isFinite), secondPCM.pcm.samples.allSatisfy(\.isFinite) else {
                    throw QualificationFailure.invariant
                }
                if measuring {
                    decoded += firstPCM.pcm.frameCount + secondPCM.pcm.frameCount
                    let elapsed = seconds(operationStart.duration(to: clock.now)) * 1_000
                    timings.append(elapsed)
                    if elapsed > 20 { overruns += 1 }
                }
                if measuring, measuredIndex > 0, measuredIndex.isMultiple(of: 50) {
                    let resident = try residentBytes()
                    rssHigh = max(rssHigh, resident)
                    rssMeasurements.append(.init(elapsedSeconds: seconds(start.duration(to: clock.now)), residentBytes: resident))
                    let a = await firstDAVE.snapshot().pendingOperationCount
                    let b = await secondDAVE.snapshot().pendingOperationCount
                    maximumPending = max(maximumPending, a + b)
                }
            }
            try await clock.sleep(until: start.advanced(by: .seconds(requestedSeconds)), tolerance: .zero)
            let elapsed = seconds(start.duration(to: clock.now))
            let firstSnapshot = await first.snapshot(), secondSnapshot = await second.snapshot()
            let rssFinal = try residentBytes(); rssHigh = max(rssHigh, rssFinal)
            rssMeasurements.append(.init(elapsedSeconds: elapsed, residentBytes: rssFinal))
            await first.close(); await second.close(); await transportCipher.close()
            await firstDAVE.close(); await secondDAVE.close()
            await firstUDP.close(); await secondUDP.close()
            let closedA = await first.snapshot(), closedB = await second.snapshot()
            let daveA = await firstDAVE.snapshot(), daveB = await secondDAVE.snapshot()
            let eofA = try await firstUDP.receiveDatagram(context: .init(clock: clock)) == nil
            let eofB = try await secondUDP.receiveDatagram(context: .init(clock: clock)) == nil
            let rssAfterClose = try residentBytes()
            timings.sort()
            let firstMinuteRSS = rssMeasurements.filter { $0.elapsedSeconds <= 60 }.map(\.residentBytes).sorted()
            let lastMinuteRSS = rssMeasurements.filter { $0.elapsedSeconds >= max(0, elapsed - 60) }.map(\.residentBytes).sorted()
            let lifetimeFrames = UInt64(warmupFrames + frameCount)
            let successful = firstSnapshot.sentPackets == lifetimeFrames && secondSnapshot.sentPackets == lifetimeFrames
                && firstSnapshot.receivedPackets == lifetimeFrames && secondSnapshot.receivedPackets == lifetimeFrames
                && firstSnapshot.bufferedBytes == 0 && secondSnapshot.bufferedBytes == 0
                && closedA.closed && closedB.closed && daveA.isClosed && daveB.isClosed && eofA && eofB
            return QualificationReport(startedAt: startedAt, requestedSeconds: requestedSeconds, elapsedSeconds: elapsed,
                warmupFramesPerDirection: warmupFrames, warmupElapsedSeconds: warmupElapsed,
                warmupDecodedSampleFrames: warmupFrames * 960 * 2,
                lifetimeTotalSentPackets: firstSnapshot.sentPackets + secondSnapshot.sentPackets,
                lifetimeTotalReceivedPackets: firstSnapshot.receivedPackets + secondSnapshot.receivedPackets,
                framesPerDirection: frameCount, totalSentPackets: firstSnapshot.sentPackets + secondSnapshot.sentPackets - UInt64(warmupFrames * 2),
                totalReceivedPackets: firstSnapshot.receivedPackets + secondSnapshot.receivedPackets - UInt64(warmupFrames * 2),
                decodedSampleFrames: decoded, concealedPackets: firstSnapshot.concealedPackets + secondSnapshot.concealedPackets,
                processingP50Milliseconds: percentile(timings, 0.5), processingP95Milliseconds: percentile(timings, 0.95),
                processingP99Milliseconds: percentile(timings, 0.99), processingMaximumMilliseconds: timings.last ?? 0,
                processingBudgetOverruns: overruns, scheduleUnderruns: underruns, peakBufferedMediaBytes: peakBuffered,
                finalBufferedMediaBytes: firstSnapshot.bufferedBytes + secondSnapshot.bufferedBytes,
                rssInitialBytes: rssInitial, rssFinalBytes: rssFinal, rssSampledHighBytes: rssHigh,
                coldRSSBytes: coldRSS, rssGrowthAfterWarmupBytes: Int64(rssFinal) - Int64(rssInitial),
                rssFirstMinuteMedianBytes: firstMinuteRSS[firstMinuteRSS.count / 2],
                rssLastMinuteMedianBytes: lastMinuteRSS[lastMinuteRSS.count / 2], rssAfterResourceCloseBytes: rssAfterClose,
                rssMeasurements: rssMeasurements, timingSampleAccountedBytes: timings.capacity * MemoryLayout<Double>.stride,
                configuredMediaBufferCapacityBytes: 32_768, configuredUDPPendingPayloadCapacityBytes: 65_536,
                sampledMaximumPendingDAVEOperations: maximumPending, closedMediaOwners: [closedA.closed, closedB.closed].filter { $0 }.count,
                closedDAVEOwners: [daveA.isClosed, daveB.isClosed].filter { $0 }.count,
                closedDatagramOwners: [eofA, eofB].filter { $0 }.count, successful: successful)
        } catch {
            await firstMedia?.close(); await secondMedia?.close(); await cipher?.close()
            await firstDAVE.close(); await secondDAVE.close()
            await firstSocket?.close(); await secondSocket?.close()
            throw error
        }
    }
}
