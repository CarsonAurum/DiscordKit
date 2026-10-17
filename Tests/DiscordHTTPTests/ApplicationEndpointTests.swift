import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Complete Application endpoint wire contracts, using large identifiers and finite independent offline fixtures.
@Suite struct ApplicationEndpointTests {
    /// All current resource operations retain exact API v10 routes, authentication, safe replay and invalidation policy.
    /// - Throws: Unexpected descriptor, fixture or request failures fail this test; missing/wrong credentials are asserted.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 3)
        for (index, item) in catalog.enumerated() {
            let endpoint = item.0
            #expect(endpoint.method == (index == 1 ? "PATCH" : "GET"))
            #expect(endpoint.route == (index == 2 ? "/applications/{application.id}/activity-instances/{instance.id}" : "/applications/@me"))
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.successStatuses == [200] && endpoint.majorParameter == nil)
            #expect(endpoint.usesGlobalLimit && endpoint.query.isEmpty && endpoint.auditReason == nil && endpoint.bulk == nil)
            #expect(endpoint.retrySafety == (index == 1 ? .unsafe : .safe))
            #expect(endpoint.invalidates == (index == 1 ? ["application-catalog"] : []))
            #expect(endpoint.readPolicy?.tags == (index == 1 ? nil : ["application-catalog"]))
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString == "https://discord.com/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .none, userAgent: "test") }
            #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test") }
            #expect(try endpoint.decode(item.1) == item.1)
            if index == 1 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["description": .string("changed"), "tags": .array([])]))
            } else { #expect(endpoint.body == nil) }
        }
        let original = try DiscordEndpoints.currentApplication()
        let modern = try ApplicationEndpoints.current()
        #expect(original.path == modern.path && original.readPolicy?.tags == modern.readPolicy?.tags)
        #expect(original.retrySafety == modern.retrySafety)
        #expect(try original.decode(Data(Self.applicationJSON.utf8)) == modern.decode(Data(Self.applicationJSON.utf8)))
    }

    /// Default reuse and caller TTL/tags survive both current-application entry points and activity retrieval.
    /// Opaque instance values are encoded as one path segment; invalid path/policy inputs fail without I/O.
    /// - Throws: Unexpected valid descriptor errors fail this test; invalid inputs are asserted.
    @Test func policiesAndOpaqueIdentifiers() throws {
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(4), tags: ["caller"])
        let policies = [try ApplicationEndpoints.current(readPolicy: policy).readPolicy,
            try DiscordEndpoints.currentApplication(readPolicy: policy).readPolicy,
            try ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: 1), instanceID: "opaque", readPolicy: policy).readPolicy]
        for actual in policies {
            #expect(actual?.coalescing == false && actual?.timeToLive == .seconds(4))
            #expect(actual?.tags == ["caller", "application-catalog"])
        }
        #expect(try ApplicationEndpoints.current(readPolicy: nil).readPolicy == nil)
        #expect(try DiscordEndpoints.currentApplication(readPolicy: nil).readPolicy == nil)
        #expect(try ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: 1), instanceID: "i", readPolicy: nil).readPolicy == nil)
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEndpoints.current(readPolicy: .init(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try DiscordEndpoints.currentApplication(readPolicy: .init(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: 1), instanceID: "i", readPolicy: .init(timeToLive: ttl)) }
        }
        for id in ["", ".", "..", "/", "a/b", "a\\b", "\n", String(repeating: "a", count: 152134)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: 1), instanceID: id) }
        }
        let endpoint = try ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: UInt64.max), instanceID: "opaque +?&日本")
        let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(request.url.query == nil && request.url.fragment == nil && request.url.path.hasSuffix("opaque +?&日本"))
        #expect(!String(reflecting: endpoint).contains("opaque"))
    }

    /// Explicit snapshot reconciliation reduces empty/equal selected edits to zero descriptors without fetching state.
    /// Missing fields, explicit null and changed text remain distinct; preview forms are never silently normalized.
    /// - Throws: Unexpected model/request/descriptor failures fail the test.
    @Test func snapshotReconciliation() throws {
        let current = try Application(data: Data(Self.applicationJSON.utf8))
        for request in [try ApplicationModify(), try ApplicationModify(description: .value("private-description")),
                        try ApplicationModify(icon: .null)] {
            #expect(try ApplicationOperations.modifyIfChanged(current: current, request: request) == nil)
        }
        for request in [try ApplicationModify(description: .value("changed")), try ApplicationModify(description: .null),
                        try ApplicationModify(tags: .value([])), try ApplicationModify(icon: .value("AQ==")),
                        try ApplicationModify(localizedDescription: .value(ApplicationLocalizedDescription(defaultValue: "private-description")))] {
            let endpoint = try #require(try ApplicationOperations.modifyIfChanged(current: current, request: request))
            #expect(endpoint.path == ["applications", "@me"] && endpoint.method == "PATCH")
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == request.jsonValue())
        }
        let uploadText = "0123456789abcdef0123456789abcdef"
        let hashSnapshot = try Application(data: Data(Self.applicationJSON.replacingOccurrences(of: "\"icon\":null", with: "\"icon\":\"" + uploadText + "\"").utf8))
        let imageUpload = try ApplicationModify(icon: .value(uploadText), coverImage: .value(uploadText))
        #expect(try ApplicationOperations.modifyIfChanged(current: hashSnapshot, request: imageUpload) != nil)
    }

    /// Builds the complete current Application operation catalog while retaining original authoritative typed decoders.
    /// - Returns: Current read, current PATCH and Activity instance read, with independent complete expected response bytes.
    /// - Throws: Descriptor or validated request errors indicate invalid trusted fixtures.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let app = Data(applicationJSON.utf8)
        return [
            (try erase(ApplicationEndpoints.current()), app),
            (try erase(ApplicationEndpoints.modifyCurrent(request: ApplicationModify(description: .value("changed"), tags: .value([])))), app),
            (try erase(ApplicationEndpoints.activityInstance(applicationID: .init(rawValue: UInt64.max), instanceID: "opaque-instance")), Data(activityJSON.utf8))
        ]
    }

    /// Preserves each production wire/reuse/retry policy and validates its original typed result before exposing fixture bytes.
    /// - Parameter endpoint: Production immutable descriptor with an authoritative typed response decoder.
    /// - Returns: Equivalent fixture descriptor with exact response bytes after typed validation.
    /// - Throws: Descriptor validation errors if production metadata is invalid.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Minimal independent written Application fixture with required nullable team and full-width future response flags.
    static let applicationJSON = #"{"id":"18446744073709551615","name":"private-app","icon":null,"description":"private-description","bot_public":true,"bot_require_code_grant":false,"verify_key":"public-key","team":null,"flags_new":"340282366920938463463374607431768211455"}"#
    /// Complete independent Activity instance fixture preserving all snowflake bits and optional guild absence.
    static let activityJSON = #"{"application_id":"18446744073709551615","instance_id":"opaque-instance","launch_id":"18446744073709551615","location":{"id":"private-channel","kind":"pc","channel_id":"18446744073709551615"},"users":["18446744073709551615"]}"#
}
