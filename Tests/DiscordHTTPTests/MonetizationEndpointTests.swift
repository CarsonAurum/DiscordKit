import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact descriptors for all eight written SKU, entitlement and subscription operations.
@Suite struct MonetizationEndpointTests {
    /// Every operation preserves versioned routes, authentication, success/body contracts and conservative mutation policy.
    /// Maximum snowflakes and unknown exact numbers round trip through the original production decoder.
    /// - Throws: Unexpected descriptor, fixture, request or model errors fail the test.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 8)
        let paths = ["applications/18446744073709551615/skus", "applications/18446744073709551615/entitlements",
            "applications/18446744073709551615/entitlements/18446744073709551615",
            "applications/18446744073709551615/entitlements/18446744073709551615/consume",
            "applications/18446744073709551615/entitlements",
            "applications/18446744073709551615/entitlements/18446744073709551615",
            "skus/18446744073709551615/subscriptions",
            "skus/18446744073709551615/subscriptions/18446744073709551615"]
        let routes = ["/applications/{application.id}/skus", "/applications/{application.id}/entitlements",
            "/applications/{application.id}/entitlements/{entitlement.id}",
            "/applications/{application.id}/entitlements/{entitlement.id}/consume",
            "/applications/{application.id}/entitlements", "/applications/{application.id}/entitlements/{entitlement.id}",
            "/skus/{sku.id}/subscriptions", "/skus/{sku.id}/subscriptions/{subscription.id}"]
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            #expect(endpoint.path.joined(separator: "/") == paths[index])
            #expect(endpoint.route == routes[index])
            #expect(endpoint.method == (index == 3 || index == 4 ? "POST" : index == 5 ? "DELETE" : "GET"))
            #expect(endpoint.successStatuses == (index == 3 || index == 5 ? [204] : [200]))
            #expect(endpoint.authentication == (index == 0 || index == 4 ? .bot : .botOrBearer))
            #expect(endpoint.retrySafety == (Self.readIndices.contains(index) ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == Self.readIndices.contains(index))
            #expect(endpoint.invalidates == (Self.readIndices.contains(index) ? [] : ["entitlement-catalog"]))
            #expect(endpoint.majorParameter == nil && endpoint.usesGlobalLimit)
            #expect(endpoint.auditReason == nil && endpoint.bulk == nil && endpoint.headers.isEmpty)
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString.hasPrefix("https://discord.com/api/v10/" + paths[index]))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            #expect(try endpoint.decode(bytes) == bytes)
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: .none, userAgent: "test")
            }
            if index == 0 || index == 4 {
                #expect(throws: DiscordError.validation(.missingValue)) {
                    try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test")
                }
            } else {
                #expect(try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test")
                    .headers.contains { $0.name == "Authorization" && $0.value == "Bearer synthetic" })
            }
            #expect((endpoint.body != nil) == (index == 4))
            if index == 4 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object([
                    "sku_id": .string("18446744073709551615"), "owner_id": .string("18446744073709551615"),
                    "owner_type": .number(try JSONNumber(rawValue: "1"))]))
            }
            for malformed in ["null", "{}", "[{}]", #""bad""#] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data(malformed.utf8)) }
            }
        }
        #expect(try SKUEndpoints.list(applicationID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
        #expect(try EntitlementEndpoints.list(applicationID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
        #expect(try SubscriptionEndpoints.list(skuID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
    }

    /// Optional filters preserve absent, empty, false and maximum-ID values; positions remain mutually exclusive.
    /// Pagination defaults are left upstream and query limits include both valid boundaries.
    /// - Throws: Unexpected fixture/descriptor failures fail the test; invalid count/set errors are asserted.
    @Test func queryValidationAndDefaults() throws {
        let app = ApplicationID(rawValue: 1), sku = SKUID(rawValue: 2), user = UserID(rawValue: UInt64.max)
        let endpoint = try EntitlementEndpoints.list(applicationID: app, userID: user,
            skuIDs: [sku, .init(rawValue: UInt64.max)], position: .before(.init(rawValue: UInt64.max)), limit: 100,
            guildID: .init(rawValue: UInt64.max), excludeEnded: false, excludeDeleted: true)
        #expect(endpoint.query == [.init(name: "user_id", value: "18446744073709551615"),
            .init(name: "sku_ids", value: "2,18446744073709551615"), .init(name: "before", value: "18446744073709551615"),
            .init(name: "limit", value: "100"), .init(name: "guild_id", value: "18446744073709551615"),
            .init(name: "exclude_ended", value: "false"), .init(name: "exclude_deleted", value: "true")])
        let alternate = try EntitlementEndpoints.list(applicationID: app, skuIDs: [], position: .after(.init(rawValue: 0)),
            limit: 1, excludeEnded: true, excludeDeleted: false)
        #expect(alternate.query == [.init(name: "sku_ids", value: ""), .init(name: "after", value: "0"),
            .init(name: "limit", value: "1"), .init(name: "exclude_ended", value: "true"),
            .init(name: "exclude_deleted", value: "false")])
        #expect(try EntitlementEndpoints.list(applicationID: app).query.isEmpty)
        #expect(try EntitlementEndpoints.list(applicationID: app, skuIDs: (0..<100).map { .init(rawValue: UInt64($0)) })
            .query.count == 1)
        for ids in [[sku, sku], (0...100).map { SKUID(rawValue: UInt64($0)) }] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try EntitlementEndpoints.list(applicationID: app, skuIDs: ids) }
        }
        for limit in [Int.min, -1, 0, 101, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try EntitlementEndpoints.list(applicationID: app, limit: limit) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try SubscriptionEndpoints.list(skuID: sku, limit: limit) }
        }
        #expect(try SubscriptionEndpoints.list(skuID: sku).query.isEmpty)
        #expect(try SubscriptionEndpoints.list(skuID: sku).authentication == .bearer)
        #expect(try SubscriptionEndpoints.list(skuID: sku, userID: user, position: .before(.init(rawValue: 0)), limit: 1)
            .query == [.init(name: "before", value: "0"), .init(name: "limit", value: "1"),
                       .init(name: "user_id", value: "18446744073709551615")])
        #expect(try SubscriptionEndpoints.list(skuID: sku, position: .after(.init(rawValue: UInt64.max)), limit: 100)
            .query == [.init(name: "after", value: "18446744073709551615"), .init(name: "limit", value: "100")])
        #expect(try SubscriptionEndpoints.get(skuID: sku, subscriptionID: .init(rawValue: 1), userID: user).query ==
            [.init(name: "user_id", value: "18446744073709551615")])
        #expect(try SubscriptionEndpoints.get(skuID: sku, subscriptionID: .init(rawValue: 1)).query.isEmpty)
        let bearerOnly = try SubscriptionEndpoints.list(skuID: sku)
        #expect(throws: DiscordError.validation(.missingValue)) {
            try bearerOnly.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        }
        #expect(try bearerOnly.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test")
            .headers.contains { $0.name == "Authorization" && $0.value == "Bearer synthetic" })
    }

    /// Caller freshness/coalescing choices are preserved exactly and nil disables reuse for every read.
    /// Invalid TTLs fail before I/O; entitlement writes intersect the list/get invalidation tags only.
    /// - Throws: Unexpected descriptor construction fails the test; invalid policies are asserted.
    @Test func readPolicies() throws {
        let app = ApplicationID(rawValue: 1), sku = SKUID(rawValue: 1)
        for policy in [ReadPolicy(coalescing: false, timeToLive: .seconds(5), tags: ["caller"]), nil] {
            let endpoints = try [Self.erase(SKUEndpoints.list(applicationID: app, readPolicy: policy)),
                Self.erase(EntitlementEndpoints.list(applicationID: app, readPolicy: policy)),
                Self.erase(EntitlementEndpoints.get(applicationID: app, entitlementID: .init(rawValue: 1), readPolicy: policy)),
                Self.erase(SubscriptionEndpoints.list(skuID: sku, readPolicy: policy)),
                Self.erase(SubscriptionEndpoints.get(skuID: sku, subscriptionID: .init(rawValue: 1), readPolicy: policy))]
            for (index, endpoint) in endpoints.enumerated() {
                if policy == nil { #expect(endpoint.readPolicy == nil) }
                else {
                    #expect(endpoint.readPolicy?.coalescing == false)
                    #expect(endpoint.readPolicy?.timeToLive == .seconds(5))
                    #expect(endpoint.readPolicy?.tags == ["caller", index == 0 ? "sku-catalog" : index < 3
                        ? "entitlement-catalog" : "subscription-catalog"])
                }
            }
        }
        for ttl in [Duration.zero, .seconds(-1)] {
            let bad = ReadPolicy(timeToLive: ttl)
            #expect(throws: DiscordError.validation(.invalidValue)) { try SKUEndpoints.list(applicationID: app, readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try EntitlementEndpoints.list(applicationID: app, readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try EntitlementEndpoints.get(applicationID: app, entitlementID: .init(rawValue: 1), readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try SubscriptionEndpoints.list(skuID: sku, readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try SubscriptionEndpoints.get(skuID: sku, subscriptionID: .init(rawValue: 1), readPolicy: bad) }
        }
    }

    /// A server cannot exceed the requested/default page cap; array ordering itself remains opaque.
    /// - Throws: Unexpected fixture parsing fails the test; over-limit responses are rejected explicitly.
    @Test func boundedPagesAndPartialCreate() throws {
        let app = ApplicationID(rawValue: 1), sku = SKUID(rawValue: 1)
        let twoEntitlements = Data("[\(Self.entitlementJSON),\(Self.entitlementJSON)]".utf8)
        let twoSubscriptions = Data("[\(Self.subscriptionJSON),\(Self.subscriptionJSON)]".utf8)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try EntitlementEndpoints.list(applicationID: app, limit: 1).decode(twoEntitlements)
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try SubscriptionEndpoints.list(skuID: sku, limit: 1).decode(twoSubscriptions)
        }
        #expect(try EntitlementEndpoints.list(applicationID: app, limit: 2).decode(twoEntitlements).count == 2)
        #expect(try SubscriptionEndpoints.list(skuID: sku, limit: 2).decode(twoSubscriptions).count == 2)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try EntitlementEndpoints.list(applicationID: app).decode(Data(("[" + Array(repeating: Self.entitlementJSON, count: 101).joined(separator: ",") + "]").utf8))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try SubscriptionEndpoints.list(skuID: sku).decode(Data(("[" + Array(repeating: Self.subscriptionJSON, count: 51).joined(separator: ",") + "]").utf8))
        }
        let create = try EntitlementEndpoints.createTest(applicationID: app,
            request: .init(skuID: sku, owner: .user(.init(rawValue: 4))))
        #expect(try create.decode(Data(Self.partialEntitlementJSON.utf8)).startsAt == .absent)
        #expect(try JSONValue.parse(#require(create.body?.storedBodyBytes)) == .object([
            "sku_id": .string("1"), "owner_id": .string("4"), "owner_type": .number(try JSONNumber(rawValue: "2"))]))
    }

    /// Builds the eight production operations with original typed decoders and independent realistic success fixtures.
    /// - Returns: SKU list, entitlement list/get/consume/create/delete and subscription list/get, in stable order.
    /// - Throws: Request JSON, descriptor or fixture validation errors before any I/O.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let app = ApplicationID(rawValue: UInt64.max), sku = SKUID(rawValue: UInt64.max)
        let entitlement = EntitlementID(rawValue: UInt64.max), subscription = SubscriptionID(rawValue: UInt64.max)
        return try [
            (erase(SKUEndpoints.list(applicationID: app)), Data("[\(skuJSON)]".utf8)),
            (erase(EntitlementEndpoints.list(applicationID: app)), Data("[\(entitlementJSON)]".utf8)),
            (erase(EntitlementEndpoints.get(applicationID: app, entitlementID: entitlement)), Data(entitlementJSON.utf8)),
            (erase(EntitlementEndpoints.consume(applicationID: app, entitlementID: entitlement)), Data()),
            (erase(EntitlementEndpoints.createTest(applicationID: app,
                request: .init(skuID: sku, owner: .guild(.init(rawValue: UInt64.max))))), Data(partialEntitlementJSON.utf8)),
            (erase(EntitlementEndpoints.deleteTest(applicationID: app, entitlementID: entitlement)), Data()),
            (erase(SubscriptionEndpoints.list(skuID: sku, userID: .init(rawValue: UInt64.max))), Data("[\(subscriptionJSON)]".utf8)),
            (erase(SubscriptionEndpoints.get(skuID: sku, subscriptionID: subscription)), Data(subscriptionJSON.utf8))
        ]
    }

    /// Retains metadata and the original production schema validator while exposing bytes for catalog integration tests.
    /// - Parameter endpoint: Typed immutable operation with no path-carried credential.
    /// - Returns: Equivalent data descriptor preserving request policy and exact original decoding acceptance.
    /// - Throws: Descriptor validation errors if the source cannot be represented identically.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Safe catalog positions used by reuse tests without relying on method-name inference.
    static let readIndices = [0, 1, 2, 6, 7]
    /// Explicit unsafe entitlement lifecycle operations used by invalidation tests.
    static let mutationIndices = [3, 4, 5]
    /// SKU fixture includes complete written fields, maximum IDs and a future exact number.
    static let skuJSON = #"{"id":"18446744073709551615","type":5,"application_id":"18446744073709551615","name":"Private Premium","slug":"private-premium","flags":128,"future_private":1.234567890123456789e1000}"#
    /// Entitlement fixture keeps nullable lifecycle and optional owner/consumption fields distinct.
    static let entitlementJSON = #"{"id":"18446744073709551615","sku_id":"18446744073709551615","application_id":"18446744073709551615","user_id":"18446744073709551615","type":8,"deleted":false,"starts_at":"2026-10-16T00:00:00+00:00","ends_at":null,"guild_id":"18446744073709551615","consumed":false,"future_private":1.234567890123456789e1000}"#
    /// Written test-create response omits lifecycle fields because the grant is perpetual.
    static let partialEntitlementJSON = #"{"id":"18446744073709551615","sku_id":"18446744073709551615","application_id":"18446744073709551615","user_id":"18446744073709551615","type":4,"deleted":false,"future_private":1.234567890123456789e1000}"#
    /// Subscription fixture includes written nullable arrays/timestamps and private optional country.
    static let subscriptionJSON = #"{"id":"18446744073709551615","user_id":"18446744073709551615","sku_ids":["18446744073709551615"],"entitlement_ids":["18446744073709551615"],"renewal_sku_ids":null,"current_period_start":"2026-10-16T00:00:00+00:00","current_period_end":"2026-11-16T00:00:00+00:00","status":0,"canceled_at":null,"country":"US","future_private":1.234567890123456789e1000}"#
}
