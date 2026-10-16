import DiscordCore
import DiscordTransport
import DiscordHTTP
import Foundation
import Testing
@testable import DiscordGateway

@Suite("Gateway protocol and discovery")
struct GatewayProtocolTests {
    /// Exercises every documented lifecycle phase and the Identify/reconnect/Resume/drain path.
    @Test func lifecycle() throws {
        var state = GatewaySessionState()
        #expect(try state.apply(.start) == .connect)
        #expect(try state.apply(.connected) == .receive)
        #expect(try state.apply(.hello(resumable: false)) == .authenticate(resume: false))
        #expect(try state.apply(.ready) == .receive)
        #expect(try state.apply(.reconnect) == .retry)
        #expect(try state.apply(.start) == .connect)
        #expect(try state.apply(.connected) == .receive)
        #expect(try state.apply(.hello(resumable: true)) == .authenticate(resume: true))
        #expect(try state.apply(.ready) == .receive)
        #expect(try state.apply(.drain) == .close)
        #expect(try state.apply(.closed) == .none)
        #expect(state.phase == .stopped)
        #expect(throws: GatewayFailure.invalidTransition) { try state.apply(.start) }
    }

    /// Checks every phase/signal pair against the explicit transition contract, including invalid edges.
    @Test func transitionTable() throws {
        let paths: [(GatewayPhase, [GatewaySignal])] = [
            (.disconnected, []), (.connecting, [.start]), (.awaitingHello, [.start, .connected]),
            (.identifying, [.start, .connected, .hello(resumable: false)]),
            (.resuming, [.start, .connected, .hello(resumable: true)]),
            (.ready, [.start, .connected, .hello(resumable: false), .ready]),
            (.reconnecting, [.start, .reconnect]), (.draining, [.drain]), (.stopped, [.drain, .closed])]
        let signals: [GatewaySignal] = [.start, .connected, .hello(resumable: false), .hello(resumable: true),
                                      .ready, .reconnect, .drain, .closed, .fatal]
        for (phase, path) in paths {
            var original = GatewaySessionState()
            for edge in path { _ = try original.apply(edge) }
            #expect(original.phase == phase)
            for signal in signals {
                var state = original
                let valid: Bool
                switch signal {
                case .start: valid = phase == .disconnected || phase == .reconnecting
                case .connected: valid = phase == .connecting
                case .hello: valid = phase == .awaitingHello
                case .ready: valid = phase == .identifying || phase == .resuming
                case .reconnect: valid = [.connecting, .awaitingHello, .identifying, .resuming, .ready].contains(phase)
                case .drain: valid = phase != .draining && phase != .stopped
                case .closed: valid = phase == .draining
                case .fatal: valid = phase != .stopped
                }
                if valid { _ = try state.apply(signal); #expect(state.phase != original.phase) }
                else {
                    #expect(throws: GatewayFailure.invalidTransition) { try state.apply(signal) }
                    #expect(state == original)
                }
            }
        }
    }

    /// Covers every current documented Gateway close code, normal closes and unknown/abrupt loss.
    /// - Parameter code: Peer disconnect code compared with the independently enumerated policy.
    @Test(arguments: [4000,4001,4002,4003,4004,4005,4007,4008,4009,4010,4011,4012,4013,4014,1000,1001,4999])
    func closeCodes(_ code: Int) {
        let expected: GatewayCloseDisposition
        if [4004,4010,4011,4012,4013,4014].contains(code) { expected = .fatal }
        else if [4003,4007,4009,1000,1001].contains(code) { expected = .identify }
        else { expected = .resume }
        #expect(GatewayCloseDisposition.classify(code) == expected)
        #expect(GatewayCloseDisposition.classify(nil) == .resume)
    }

    /// Preserves unknown event data and exact large numbers while rejecting malformed envelope fields.
    @Test func envelope() throws {
        let envelope = try GatewayEnvelope(.text(#"{"op":99,"t":"FUTURE","s":9223372036854775807,"d":{"id":18446744073709551615}}"#), maximumBytes: 1024)
        #expect(envelope.opcode == 99)
        #expect(envelope.sequence == Int64.max)
        #expect(envelope.name == "FUTURE")
        #expect(envelope.data == .object(["id": gatewayNumber(UInt64.max)]))
        for text in [#"{"op":-1}"#, #"{"op":"1"}"#, #"{"op":0,"s":-1}"#,
                     #"{"op":0,"s":9223372036854775808}"#, #"{"op":0,"t":3}"#] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayEnvelope(.text(text), maximumBytes: 1024) }
        }
        #expect(throws: GatewayFailure.unsupportedEncoding) { try GatewayEnvelope(.binary(Data()), maximumBytes: 100) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try GatewayEnvelope(.text("{}"), maximumBytes: 1) }
    }

    /// Validates Discord origins and explicit protocol choices before any credential can leave the process.
    @Test func origins() throws {
        #expect(try gatewayURL("wss://gateway.discord.gg/?compress=zlib-stream").absoluteString ==
            "wss://gateway.discord.gg/?v=10&encoding=json")
        for invalid in ["ws://gateway.discord.gg/", "wss://discord.gg/", "wss://gateway.discord.gg.evil.example/",
                        "wss://evil.example/", "wss://token@gateway.discord.gg/", "wss://gateway.discord.gg/#secret",
                        "wss://gateway.discord.gg:80/"] {
            #expect(throws: GatewayFailure.invalidPayload) { try gatewayURL(invalid) }
        }
    }

    /// Tests current discovery decoding, zero-quota allowances, shard subsets and endpoint auth/reuse metadata.
    @Test func discovery() throws {
        let discovery = try makeDiscovery(shards: 4, remaining: 0)
        #expect(discovery.recommendedShardCount == 4)
        #expect(discovery.sessionStartLimit.remaining == 0)
        let shards = try discovery.shards(botID: UserID(rawValue: 1), topologyGeneration: 2, indices: [3, 0])
        #expect(shards.map(\.index) == [0,3])
        #expect(shards.allSatisfy { $0.count == 4 && $0.topologyGeneration == 2 })
        #expect(shards[0].routes(GuildID(rawValue: 0)))
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try discovery.shards(botID: UserID(rawValue: 1), topologyGeneration: 0, indices: [1,1])
        }
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try discovery.shards(botID: UserID(rawValue: 1), topologyGeneration: 0, maximumShards: 3)
        }
        #expect(try discovery.shards(botID: UserID(rawValue: 1), topologyGeneration: 0, indices: []).isEmpty)
        let endpoint = try GatewayEndpoints.bot()
        #expect(endpoint.path == ["gateway", "bot"])
        #expect(endpoint.authentication == .bot)
        #expect(endpoint.retrySafety == .safe)
        #expect(endpoint.readPolicy?.timeToLive == nil)
        #expect(try endpoint.decode(discovery.rawValue.serialized()).recommendedShardCount == 4)
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayDiscovery(json: .object([:])) }
    }

    /// Rejects nonsensical queue/retry/time and server limits before opening any transport.
    @Test func invalidConfiguration() {
        #expect(throws: GatewayFailure.invalidConfiguration) { try GatewayShardConfiguration(maximumFrameBytes: 0) }
        #expect(throws: GatewayFailure.invalidConfiguration) { try GatewayShardConfiguration(maximumReconnectAttempts: 31) }
        #expect(throws: GatewayFailure.invalidConfiguration) { try GatewayShardConfiguration(leaseLifetime: .milliseconds(1)) }
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try GatewaySessionStartLimit(total: 1, remaining: 2, resetAfter: .seconds(1), maxConcurrency: 1)
        }
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .zero, maxConcurrency: 1)
        }
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .milliseconds(2_592_000_001), maxConcurrency: 1)
        }
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try GatewayDiscovery(json: JSONValue.parse(#"{"url":"wss://gateway.discord.gg/","shards":1,"session_start_limit":{"total":1,"remaining":1,"reset_after":9223372036854775807,"max_concurrency":1}}"#))
        }
        #expect(throws: Never.self) {
            _ = try GatewaySessionStartLimit(total: 1, remaining: 1, resetAfter: .seconds(2_592_000), maxConcurrency: 1)
        }
    }

    /// Sanitization preserves closed typed recovery signals and maps parser/dependency failures safely.
    @Test func closedFailureSanitization() {
        #expect(safeGatewayFailure(CancellationError()) is CancellationError)
        #expect(safeGatewayFailure(TransportFailure.closed) as? TransportFailure == .closed)
        #expect(safeGatewayFailure(ShardOwnershipFailure.staleLease) as? ShardOwnershipFailure == .staleLease)
        #expect(safeGatewayFailure(GatewayFailure.fatalClose(4004)) as? GatewayFailure == .fatalClose(4004))
        #expect(safeGatewayFailure(JSONValueError.invalidNumber) as? GatewayFailure == .invalidPayload)
        #expect(safeGatewayFailure(NSError(domain: "secret", code: 1)) as? GatewayFailure == .coordinatorUnavailable)
    }
}

/// Builds a realistic lossless discovery fixture without network requests or credentials.
/// - Parameters:
///   - shards: Positive recommended topology size, default two.
///   - remaining: Current startup allowance, default 100.
/// - Returns: Validated v10 JSON discovery with two five-second startup buckets.
/// - Throws: Fixture JSON or discovery validation errors.
func makeDiscovery(shards: Int = 2, remaining: Int = 100) throws -> GatewayDiscovery {
    try GatewayDiscovery(json: JSONValue.parse("""
    {"url":"wss://gateway.discord.gg/","shards":\(shards),"session_start_limit":
    {"total":100,"remaining":\(remaining),"reset_after":10000,"max_concurrency":2},"future":null}
    """))
}
