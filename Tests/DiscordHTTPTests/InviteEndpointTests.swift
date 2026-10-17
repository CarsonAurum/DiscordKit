import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies all nine Invite REST descriptors against independent API v10 wire fixtures and bounded allowlist contracts.
@Suite struct InviteEndpointTests {
    /// Every route preserves opaque code, exact snowflakes, explicit statuses/authentication and conservative replay policy.
    /// - Throws: Unexpected descriptor, credential or response fixture errors fail the test.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 9)
        let methods = ["GET", "DELETE", "GET", "PUT", "DELETE", "PUT", "POST", "POST", "GET"]
        let suffixes = ["", "", "/target-users", "/target-users/18446744073709551615", "/target-users/18446744073709551615",
            "/target-users", "/target-users/bulk-add", "/target-users/bulk-delete", "/target-users/job-status"]
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(endpoint.method == methods[index])
            #expect(request.url.absoluteString == "https://discord.com/api/v10/invites/secret-code" + suffixes[index])
            #expect(endpoint.authentication == (index == 0 ? .none : .bot))
            #expect(request.headers.contains { $0.name == "Authorization" } == (index != 0))
            #expect(endpoint.successStatuses == ((3...7).contains(index) ? [204] : [200]))
            #expect(endpoint.retrySafety == (methods[index] == "GET" ? .safe : .unsafe))
            #expect(endpoint.majorParameter == nil && endpoint.usesGlobalLimit)
            #expect(endpoint.query.isEmpty && endpoint.auditReason == nil)
            #expect(endpoint.readPolicy?.coalescing == ([0, 2].contains(index) ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.invalidates == (methods[index] == "GET" ? [] : inviteTags))
            #expect(endpoint.bulk?.maximumItems == ([6, 7].contains(index) ? 1_000 : nil))
            #expect(!endpoint.route.contains("secret-code") && !endpoint.route.contains("18446744073709551615"))
            #expect(!String(reflecting: endpoint).contains("secret-code"))
            #expect(try endpoint.decode(bytes) == bytes)
            for malformed in [Data("null".utf8), Data("{}".utf8), Data("[]".utf8)] {
                #expect(throws: (any Error).self) { try endpoint.decode(malformed) }
            }
        }
        let privateRead = try InviteEndpoints.get(code: "code", authenticated: true)
        #expect(privateRead.authentication == .bot)
        #expect(throws: DiscordError.validation(.missingValue)) { try privateRead.makeRequest(credential: .none, userAgent: "test") }
        #expect(throws: DiscordError.validation(.missingValue)) { try privateRead.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test") }
    }

    /// Optional query flags preserve false/absence and complete UInt64 IDs; reuse keeps caller scope/freshness choices.
    /// - Throws: Unexpected descriptor/request validation errors fail the test.
    @Test func queryPoliciesAuditAndValidation() throws {
        let endpoint = try InviteEndpoints.get(code: "opaque +日本", withCounts: false,
            guildScheduledEventID: .init(rawValue: UInt64.max), targetChannelID: .init(rawValue: UInt64.max),
            targetMessageID: .init(rawValue: UInt64.max), readPolicy: ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["caller"]))
        #expect(endpoint.query == [QueryItem(name: "with_counts", value: "false"),
            QueryItem(name: "guild_scheduled_event_id", value: "18446744073709551615"),
            QueryItem(name: "target_channel_id", value: "18446744073709551615"),
            QueryItem(name: "target_message_id", value: "18446744073709551615")])
        #expect(endpoint.readPolicy?.coalescing == false && endpoint.readPolicy?.timeToLive == .seconds(2))
        #expect(endpoint.readPolicy?.tags == inviteTags.union(["caller"]))
        #expect(try InviteEndpoints.get(code: "c", withCounts: true).query == [QueryItem(name: "with_counts", value: "true")])
        #expect(try InviteEndpoints.get(code: "c", readPolicy: nil).readPolicy == nil)
        #expect(try InviteEndpoints.targetUsers(code: "c", readPolicy: nil).readPolicy == nil)
        #expect(try InviteEndpoints.targetUsers(code: "c", maximumBytes: 1).readPolicy == nil)
        #expect(try InviteEndpoints.targetUsers(code: "c", maximumUsers: 1).readPolicy == nil)
        #expect(try InviteEndpoints.targetUsers(code: "c", readPolicy: ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["caller"])).readPolicy?.tags.contains("caller") == true)
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.get(code: "c", readPolicy: ReadPolicy(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.targetUsers(code: "c", readPolicy: ReadPolicy(timeToLive: ttl)) }
        }
        let reason = "why +&日本"
        let deleted = try InviteEndpoints.delete(code: "c", auditReason: reason)
        let request = try deleted.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(request.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "why%20%2B%26%E6%97%A5%E6%9C%AC" })
        #expect(!String(reflecting: deleted).contains(reason))
        #expect(try InviteEndpoints.delete(code: "c", auditReason: String(repeating: "a", count: 512)).auditReason?.count == 512)
        for bad in ["\n", String(repeating: "a", count: 513)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.delete(code: "c", auditReason: bad) }
        }
        for code in ["", ".", "..", "a/b", "a\\b", "a\nb"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.get(code: code) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.delete(code: code) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.targetUsersJob(code: code) }
        }
    }

    /// Bulk operations preserve all IDs and legal group boundaries; CSV replacement contains only its required form field.
    /// - Throws: Unexpected descriptor/body validation failures fail the test.
    @Test func bulkAndCSVRequestBodies() async throws {
        for removing in [false, true] {
            let ids: [UserID] = [.init(rawValue: UInt64.max), .init(rawValue: 42), .init(rawValue: 42)]
            let endpoint = try removing ? InviteEndpoints.bulkDeleteTargetUsers(code: "c", userIDs: ids) : InviteEndpoints.bulkAddTargetUsers(code: "c", userIDs: ids)
            #expect(try JSONValue.parse(#require(endpoint.body?.bytes)) == .object(["user_ids": .array([.string("18446744073709551615"), .string("42"), .string("42")])]))
            #expect(endpoint.bulk?.preservesOrder == false && endpoint.bulk?.permitsPartialResults == false)
            let maximum = (0..<1_000).map { UserID(rawValue: UInt64($0)) }
            _ = try removing ? InviteEndpoints.bulkDeleteTargetUsers(code: "c", userIDs: maximum) : InviteEndpoints.bulkAddTargetUsers(code: "c", userIDs: maximum)
            for illegal in [[], Array(repeating: UserID(rawValue: 1), count: 1_001)] {
                #expect(throws: DiscordError.validation(.invalidValue)) {
                    try removing ? InviteEndpoints.bulkDeleteTargetUsers(code: "c", userIDs: illegal) : InviteEndpoints.bulkAddTargetUsers(code: "c", userIDs: illegal)
                }
            }
        }
        let csv = Data("18446744073709551615\r\n42\r\n42\r\n".utf8)
        let endpoint = try InviteEndpoints.updateTargetUsers(code: "c", csv: csv)
        let body = try #require(endpoint.body)
        let wire = String(decoding: body.bytes, as: UTF8.self)
        #expect(wire.contains("name=\"target_users_file\"; filename=\"users.csv\""))
        #expect(!wire.contains("payload_json"))
        #expect(wire.contains(String(decoding: csv, as: UTF8.self)))
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: 1_048_576) == body.bytes)
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: 1_048_576) == body.bytes)
        #expect(try InviteEndpoints.updateTargetUsers(code: "c", csv: csv, maximumBytes: body.bytes.count).body?.bytes == body.bytes)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try InviteEndpoints.updateTargetUsers(code: "c", csv: csv, maximumBytes: body.bytes.count - 1) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try InviteEndpoints.updateTargetUsers(code: "c", csv: csv, maximumBytes: 1) }
        for invalid in ["", "user_id\n1", "1,2", "\"1\"", "1\n\n", "1\r", "-1", "18446744073709551616", "\u{FEFF}1"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.updateTargetUsers(code: "c", csv: Data(invalid.utf8)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.updateTargetUsers(code: "c", csv: Data([255])) }
        for cap in [0, -1, 8_388_609, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.updateTargetUsers(code: "c", csv: Data("1".utf8), maximumBytes: cap) }
        }
    }

    /// CSV export accepts exact documented headers, full-range IDs, empty files of users, duplicate rows and safe diagnostics.
    /// - Parameter newline: Both documented interoperable line-ending forms.
    /// - Throws: Unexpected CSV validation errors fail the test.
    @Test(arguments: ["\n", "\r\n"]) func exportedCSV(newline: String) throws {
        let data = Data(("user_id" + newline + "18446744073709551615" + newline + "0" + newline + "42" + newline + "42").utf8)
        let csv = try InviteTargetUsersCSV(data: data, maximumBytes: data.count, maximumUsers: 4)
        #expect(csv.bytes == data && csv.userIDs.map(\.rawValue) == [UInt64.max, 0, 42, 42])
        #expect(try InviteTargetUsersCSV(data: Data((String(decoding: data, as: UTF8.self) + newline).utf8)).userIDs == csv.userIDs)
        #expect(try InviteTargetUsersCSV(data: Data("user_id".utf8)).userIDs.isEmpty)
        #expect(try InviteTargetUsersCSV(data: Data(("user_id" + newline).utf8)).userIDs.isEmpty)
        #expect(!String(describing: csv).contains("18446744073709551615"))
        #expect(!String(reflecting: csv).contains("18446744073709551615"))
        #expect(csv.customMirror.children.count == 1)
        #expect(throws: DiscordError.transport(.limitExceeded)) { try InviteTargetUsersCSV(data: data, maximumBytes: data.count - 1) }
        #expect(throws: DiscordError.transport(.limitExceeded)) { try InviteTargetUsersCSV(data: data, maximumUsers: 3) }
        #expect(throws: DiscordError.transport(.limitExceeded)) { try InviteTargetUsersCSV(data: Data("user_id\n1\n2\n".utf8), maximumUsers: 1) }
        for cap in [0, -1, 8_388_609, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteTargetUsersCSV(data: data, maximumBytes: cap) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.targetUsers(code: "c", maximumBytes: cap) }
        }
        for cap in [0, -1, 1_000_001, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteTargetUsersCSV(data: data, maximumUsers: cap) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try InviteEndpoints.targetUsers(code: "c", maximumUsers: cap) }
        }
    }

    /// Headerless, multi-column, quoted, blank, overflow and malformed newline exports fail with sanitized transport categories.
    /// - Parameter input: Independently malformed response file including header and integer boundaries.
    /// - Throws: Unexpected fixture errors fail the test; expected parser failures are asserted.
    @Test(arguments: ["", "1", "user_ids\n1", "user_id,other\n1", "user_id\r", "user_id\n\n", "user_id\n1\n\n",
                      "user_id\n-1", "user_id\n18446744073709551616", "user_id\n1,2", "user_id\n\"1\"", "user_id\n 1",
                      "user_id\n1 ", "user_id\n1\r2", "user_id\n1\r", "\u{FEFF}user_id\n1", "user_id\n1e2"])
    func malformedCSV(input: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try InviteTargetUsersCSV(data: Data(input.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try InviteTargetUsersCSV(data: Data([255])) }
    }

    /// Builds each current Invite operation with an independent success fixture while preserving its original typed decoder.
    /// - Returns: Stable get/delete/export/single-add/single-remove/replace/bulk-add/bulk-delete/job order.
    /// - Throws: Unexpected fixture or descriptor validation errors before I/O.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let code = "secret-code", user = UserID(rawValue: UInt64.max)
        let invite = Data(inviteJSON.utf8)
        return [
            (try erase(InviteEndpoints.get(code: code)), invite),
            (try erase(InviteEndpoints.delete(code: code)), invite),
            (try erase(InviteEndpoints.targetUsers(code: code)), Data("user_id\n18446744073709551615\n".utf8)),
            (try erase(InviteEndpoints.addTargetUser(code: code, userID: user)), Data()),
            (try erase(InviteEndpoints.removeTargetUser(code: code, userID: user)), Data()),
            (try erase(InviteEndpoints.updateTargetUsers(code: code, csv: Data("18446744073709551615\n".utf8))), Data()),
            (try erase(InviteEndpoints.bulkAddTargetUsers(code: code, userIDs: [user])), Data()),
            (try erase(InviteEndpoints.bulkDeleteTargetUsers(code: code, userIDs: [user])), Data()),
            (try erase(InviteEndpoints.targetUsersJob(code: code)), Data(jobJSON.utf8)),
        ]
    }

    /// Retains original response validation while giving mixed catalog fixtures one Sendable response type.
    /// - Parameter endpoint: Already validated immutable typed descriptor.
    /// - Returns: Equivalent metadata and bytes only after the original decoder succeeds.
    /// - Throws: Ordinary descriptor validation errors; no network or credential access occurs.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    static let inviteJSON = #"{"type":0,"code":"secret-code","channel":{"id":"18446744073709551615","type":0},"expires_at":null}"#
    static let jobJSON = #"{"status":2,"total_users":1,"processed_users":1,"created_at":"2026-10-16T12:00:00Z","completed_at":"2026-10-16T12:00:01Z","error_message":null}"#
}
