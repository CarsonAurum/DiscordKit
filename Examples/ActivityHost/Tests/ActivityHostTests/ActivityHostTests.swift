import ActivityBackend
import ActivityHostSupport
import DiscordActivities
import DiscordCommerce
import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordOAuth
import Foundation
import Testing

/// Local host adapter for example orchestration tests. All credentials and protocol frames are synthetic.
actor ExampleActivityPeer: ActivityTransport {
    private var frames: [Data] = []
    private var reader: CheckedContinuation<Data?, Never>?
    private var closed = false
    private let purchase: JSONValue
    private(set) var commands: [String] = []

    /// Stores the chosen purchase acknowledgement without starting work.
    /// - Parameter purchase: Null, empty array or advisory entitlement fixtures.
    init(purchase: JSONValue = .null) { self.purchase = purchase }

    /// Responds deterministically to handshake, authorization, authentication and purchase commands.
    /// - Parameter data: Complete tuple sent by the example client.
    /// - Throws: Fixture/protocol serialization errors; no live requests occur.
    func send(_ data: Data) async throws {
        guard case .array(let tuple) = try JSONValue.parse(data), case .object(let fields) = tuple[1] else { throw ActivityFailure.invalidFrame }
        if tuple[0] == .number(try JSONNumber(rawValue: "2")) { return }
        let value: JSONValue
        if tuple[0] == .number(try JSONNumber(rawValue: "0")) {
            value = try JSONValue.parse(Data(#"[1,{"cmd":"DISPATCH","evt":"READY","nonce":null,"data":{"v":1,"config":{"api_endpoint":"//discord.com/api","environment":"production"}}}]"#.utf8))
        } else {
            guard case .string(let command) = fields["cmd"] else { throw ActivityFailure.invalidFrame }
            commands.append(command)
            let response: JSONValue
            switch command {
            case "AUTHORIZE": response = .object(["code": .string("synthetic-code")])
            case "AUTHENTICATE": response = try JSONValue.parse(Data(#"{"access_token":"synthetic-token","scopes":["identify"],"expires":"2026-10-18T00:00:00Z","user":{"id":"4","username":"test","discriminator":"0","public_flags":0},"application":{"id":"2","name":"test","description":"test"}}"#.utf8))
            case "START_PURCHASE": response = purchase
            default: throw ActivityFailure.invalidFrame
            }
            value = .array([.number(try JSONNumber(rawValue: "1")), .object(["cmd": .string(command), "evt": .null, "nonce": fields["nonce"]!, "data": response])])
        }
        let bytes = try value.serialized()
        if let reader { self.reader = nil; reader.resume(returning: bytes) } else { frames.append(bytes) }
    }

    /// Transfers one scripted host response or waits for the next admitted send/close.
    /// - Returns: Complete bytes or nil after terminal disposal.
    func receive() async throws -> Data? {
        if !frames.isEmpty { return frames.removeFirst() }
        if closed { return nil }
        return await withCheckedContinuation { reader = $0 }
    }

    /// Releases the sole receive continuation and any queued data idempotently.
    func close() async { closed = true; frames.removeAll(); reader?.resume(returning: nil); reader = nil }
}

/// Example-level integration validates client/server separation with synthetic transport and authoritative server fixtures.
@Suite struct ActivityHostTests {
    /// Produces fixed host context and starts a local simulated client; nothing contacts Discord.
    /// - Parameter peer: Exclusively owned scripted adapter.
    /// - Returns: Ready Activity client.
    /// - Throws: Fixture or local handshake validation failure.
    static func client(_ peer: ExampleActivityPeer) async throws -> ActivityClient<ContinuousClock> {
        let host = try ActivityHostParameters(url: #require(URL(string: "https://2.discordsays.com/?frame_id=f&instance_id=i&platform=desktop")))
        let client = try ActivityClient(applicationID: .init(rawValue: 2), host: host, transport: peer, clock: ContinuousClock())
        try await client.start(); return client
    }

    /// Confirms consent/exchange/auth ordering and scoped token forwarding with no secret in client configuration.
    @Test func authenticateThroughBackend() async throws {
        let peer = ExampleActivityPeer(); let client = try await Self.client(peer)
        let authenticated = try await ActivityHostSession.authenticate(client: client, applicationID: .init(rawValue: 2), exchange: { code in
            #expect(code == "synthetic-code"); return try ActivityUserAccessToken(oauthAccessToken: "synthetic-token")
        })
        #expect(authenticated.user.id == "4"); #expect(await peer.commands == ["AUTHORIZE", "AUTHENTICATE"])
        await client.close()
        let failedPeer = ExampleActivityPeer(); let failed = try await Self.client(failedPeer)
        await #expect(throws: OAuthError.invalidGrant) {
            try await ActivityHostSession.authenticate(client: failed, applicationID: .init(rawValue: 2), exchange: { _ in throw OAuthError.invalidGrant })
        }
        #expect(await failedPeer.commands == ["AUTHORIZE"]); await failed.close()
    }

    /// Distinguishes asynchronous/empty/ID purchase hints and returns only the backend verification result.
    @Test(arguments: [JSONValue.null, .array([]), try! JSONValue.parse(Data(#"[{"id":"1","sku_id":"3","application_id":"2","user_id":"4","gift_code_flags":0,"type":1}]"#.utf8))])
    func purchaseHintsRequireBackend(value: JSONValue) async throws {
        let peer = ExampleActivityPeer(purchase: value); let client = try await Self.client(peer)
        let verified = try await ActivityHostSession.purchase(client: client, skuID: "3", verify: { hints in
            if value == .null { #expect(hints == nil) }
            else if value == .array([]) { #expect(hints == []) }
            else { #expect(hints == ["1"]) }
            return "server-verified-result"
        })
        #expect(verified == "server-verified-result"); #expect(await peer.commands == ["START_PURCHASE"]); await client.close()
    }

    /// Exercises server code exchange and fail-closed purchase checks against independent authoritative REST data.
    @Test func authoritativeBackendPolicy() async throws {
        let exchange = try ActivityBackend.exchange(code: OAuthCode("code"), applicationID: .init(rawValue: 2), secret: ClientSecret("server-only"))
        #expect(exchange.path == ["oauth2", "token"] && exchange.retrySafety == .unsafe)
        let requirement = EntitlementRequirement(applicationID: .init(rawValue: 2), skuID: .init(rawValue: 3), owner: .user(.init(rawValue: 4)))
        let now = try DiscordTimestamp(rawValue: "2026-10-17T12:00:00Z")
        let authoritative = try Entitlement(data: Data(#"{"id":"1","application_id":"2","sku_id":"3","user_id":"4","type":1,"deleted":false,"starts_at":null,"ends_at":null,"consumed":false}"#.utf8))
        let verified = try await ActivityBackend.verifyPurchase(hints: ["1"], requirement: requirement, now: { now }, fetch: { endpoint in
            #expect(endpoint.readPolicy == nil); return authoritative
        })
        #expect(verified?.map(\.id) == [.init(rawValue: 1)])
        for hints in [Optional<[String]>.none, .some([])] {
            let result = try await ActivityBackend.verifyPurchase(hints: hints, requirement: requirement, now: { now }, fetch: { _ in Issue.record("No hints must not fetch"); return authoritative })
            #expect(result?.count == hints?.count)
        }
        for hints in [["invalid"], ["1", "01"], Array(repeating: "1", count: 101)] {
            await #expect(throws: EntitlementVerificationError.invalidPurchaseAcknowledgement) {
                try await ActivityBackend.verifyPurchase(hints: hints, requirement: requirement, now: { now }, fetch: { _ in Issue.record("Bad hints must not fetch"); return authoritative })
            }
        }
        await #expect(throws: EntitlementVerificationError.mismatchedGrant) {
            try await ActivityBackend.verifyPurchase(hints: ["1"], requirement: .init(applicationID: .init(rawValue: 2), skuID: .init(rawValue: 9), owner: .user(.init(rawValue: 4))), now: { now }, fetch: { _ in authoritative })
        }
        await #expect(throws: OAuthError.invalidGrant) {
            try await ActivityBackend.verifyPurchase(hints: ["1"], requirement: requirement, now: { now }, fetch: { _ in throw OAuthError.invalidGrant })
        }
    }
}
