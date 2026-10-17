import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// All five written identity/profile operations, including exact routes, tuple scope and bodyless profile successes.
@Suite struct ApplicationIdentityEndpointTests {
    /// Descriptors preserve exact versioned routes, mandatory bot auth, explicit success/retry policies and invalidation.
    /// - Throws: Unexpected descriptor, request or decoder errors fail the test.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        let app = "18446744073709551615"
        let paths = ["users/\(app)/application-identities/\(app)", "applications/\(app)/application-identities/FUTURE/external%雪",
            "users/\(app)/application-identities/\(app)/FUTURE/external%雪/delete",
            "applications/\(app)/users/\(app)/identities/external%雪/profile", "applications/\(app)/users/\(app)/identities/external%雪/profile"]
        let routes = ["/users/{user.id}/application-identities/{application.id}",
            "/applications/{application.id}/application-identities/{provider.type}/{provider.issued.user.id}",
            "/users/{user.id}/application-identities/{application.id}/{provider.type}/{provider.issued.user.id}/delete",
            "/applications/{application.id}/users/{user.id}/identities/{provider.issued.user.id}/profile",
            "/applications/{application.id}/users/{user.id}/identities/{provider.issued.user.id}/profile"]
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            #expect(endpoint.path.joined(separator: "/") == paths[index] && endpoint.route == routes[index])
            #expect(endpoint.method == (index == 2 ? "POST" : index == 4 ? "PATCH" : "GET"))
            #expect(endpoint.successStatuses == (index == 2 ? [204] : index == 4 ? [201, 204] : [200]))
            #expect(endpoint.authentication == .bot && endpoint.majorParameter == nil && endpoint.usesGlobalLimit)
            #expect(endpoint.retrySafety == (index == 2 || index == 4 ? .unsafe : .safe))
            #expect((endpoint.readPolicy != nil) == (index != 2 && index != 4))
            #expect(endpoint.invalidates == (index == 2 || index == 4 ? ["application-identity-catalog", "application-identity-profile-catalog"] : []))
            #expect(endpoint.auditReason == nil && endpoint.bulk == nil && endpoint.headers.isEmpty)
            #expect(try endpoint.decode(bytes) == bytes)
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString.hasPrefix("https://discord.com/api/v10/"))
            if index > 0 { #expect(request.url.absoluteString.contains("external%25%E9%9B%AA")) }
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            for credential in [Credential.none, .bearer(try BearerToken("synthetic"))] {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: credential, userAgent: "test") }
            }
            #expect((endpoint.body != nil) == (index == 2 || index == 4))
        }
    }

    /// Provider disambiguation is a query only for external lookups and optional JSON only for POST deletion.
    /// - Throws: Unexpected descriptor/key/body construction fails the test.
    @Test func disambiguationAndReplacementBodies() throws {
        let app = ApplicationID(rawValue: 1), user = UserID(rawValue: 2)
        for provider in [nil, "", "opaque&雪/?#"] as [String?] {
            let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: "external", providerID: provider)
            let lookup = try ApplicationIdentityEndpoints.byExternal(applicationID: app, key: key)
            #expect(lookup.query == (provider.map { [.init(name: "provider_id", value: $0)] } ?? []))
            #expect(lookup.body == nil)
            let deletion = try ApplicationIdentityEndpoints.delete(applicationID: app, userID: user, key: key)
            #expect(deletion.query.isEmpty)
            if let provider { #expect(try JSONValue.parse(#require(deletion.body?.storedBodyBytes)) == .object(["provider_id": .string(provider)])) }
            else { #expect(deletion.body == nil) }
        }
        let patch = try ApplicationIdentityProfileEndpoints.update(applicationID: app, userID: user, providerIssuedUserID: "x",
            request: .init(data: .value(.init())))
        #expect(try JSONValue.parse(#require(patch.body?.storedBodyBytes)) == .object(["data": .object([:])]))
        #expect(try ApplicationIdentityProfileEndpoints.update(applicationID: app, userID: user, providerIssuedUserID: "x", request: .init())
            .body?.storedBodyBytes == Data("{}".utf8))
        let get = try ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: "x")
        #expect(get.query.isEmpty && get.body == nil)
    }

    /// Profile updates accept empty 201/204 responses and validate present bodies instead of requiring a fabricated success object.
    /// Every other read validates its own complete schema and deletion strictly requires empty data.
    /// - Throws: Unexpected descriptor/model parsing fails the test.
    @Test func responseContracts() throws {
        let app = ApplicationID(rawValue: 1), user = UserID(rawValue: 2)
        let update = try ApplicationIdentityProfileEndpoints.update(applicationID: app, userID: user, providerIssuedUserID: "x", request: .init())
        #expect(try update.decode(Data()) == .null)
        #expect(try update.decode(Data(Self.profileJSON.utf8)) == .value(try ApplicationIdentityProfile(data: Data(Self.profileJSON.utf8))))
        let get = try ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: "x")
        let deletion = try ApplicationIdentityEndpoints.delete(applicationID: app, userID: user,
            key: .init(providerType: "NONE", providerIssuedUserID: "x"))
        #expect(try deletion.decode(Data()) == EmptyResponse(data: Data()))
        for invalid in ["null", "{}", "[]", #"{"username":null,"metadata":null}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try update.decode(Data(invalid.utf8)) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try get.decode(Data(invalid.utf8)) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try deletion.decode(Data(invalid.utf8)) }
        }
        for index in [0, 1] {
            let endpoint = try Self.catalog()[index].0
            #expect(try endpoint.decode(Data(#"{"identities":[]}"#.utf8)) == Data(#"{"identities":[]}"#.utf8))
            for invalid in ["null", "{}", "[]", #"{"identities":[{}]}"#] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data(invalid.utf8)) }
            }
        }
    }

    /// Caller-selected coalescing/TTL/tags remain intact; nil disables reuse and invalid TTL/path values fail before I/O.
    /// - Throws: Unexpected policy/descriptor construction fails the test.
    @Test func reuseAndPathValidation() throws {
        let app = ApplicationID(rawValue: 1), user = UserID(rawValue: 2)
        let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: "x")
        for policy in [ReadPolicy(coalescing: false, timeToLive: .seconds(5), tags: ["caller"]), nil] {
            let endpoints = try [MonetizationEndpointTests.erase(ApplicationIdentityEndpoints.byUser(applicationID: app, userID: user, readPolicy: policy)),
                MonetizationEndpointTests.erase(ApplicationIdentityEndpoints.byExternal(applicationID: app, key: key, readPolicy: policy)),
                MonetizationEndpointTests.erase(ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: "x", readPolicy: policy))]
            for (index, endpoint) in endpoints.enumerated() {
                if policy == nil { #expect(endpoint.readPolicy == nil) }
                else {
                    #expect(endpoint.readPolicy?.coalescing == false && endpoint.readPolicy?.timeToLive == .seconds(5))
                    #expect(endpoint.readPolicy?.tags == ["caller", index == 2 ? "application-identity-profile-catalog" : "application-identity-catalog"])
                }
            }
        }
        for ttl in [Duration.zero, .seconds(-1)] {
            let bad = ReadPolicy(timeToLive: ttl)
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityEndpoints.byUser(applicationID: app, userID: user, readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityEndpoints.byExternal(applicationID: app, key: key, readPolicy: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: "x", readPolicy: bad) }
        }
        for bad in ["", ".", "..", "a/b", "a\\b", "a\n", String(repeating: "a", count: 4_097)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: bad) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileEndpoints.update(applicationID: app, userID: user, providerIssuedUserID: bad, request: .init()) }
        }
    }

    /// Builds all five operations with maximum snowflakes, opaque path values, explicit provider disambiguation and typed decoders.
    /// - Returns: Metadata-preserving erased descriptors and valid success fixture bytes in stable operation order.
    /// - Throws: Unexpected descriptor, key, body or erasure errors fail the caller's test.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let app = ApplicationID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        let key = try ApplicationIdentityKey(providerType: "FUTURE", providerIssuedUserID: "external%雪", providerID: "provider&雪")
        return try [
            (MonetizationEndpointTests.erase(ApplicationIdentityEndpoints.byUser(applicationID: app, userID: user)), Data(Self.listJSON.utf8)),
            (MonetizationEndpointTests.erase(ApplicationIdentityEndpoints.byExternal(applicationID: app, key: key)), Data(Self.listJSON.utf8)),
            (MonetizationEndpointTests.erase(ApplicationIdentityEndpoints.delete(applicationID: app, userID: user, key: key)), Data()),
            (MonetizationEndpointTests.erase(ApplicationIdentityProfileEndpoints.get(applicationID: app, userID: user, providerIssuedUserID: key.providerIssuedUserID)), Data(Self.profileJSON.utf8)),
            (MonetizationEndpointTests.erase(ApplicationIdentityProfileEndpoints.update(applicationID: app, userID: user,
                providerIssuedUserID: key.providerIssuedUserID, request: .init(username: .value("same"), data: .value(.init())))), Data(Self.profileJSON.utf8))
        ]
    }

    /// Complete nullable profile with future exact numeric metadata.
    static let profileJSON = #"{"username":"same","metadata":{"future":1e1000},"data":null}"#
    /// Wrapped identity lookup includes the written examples' Discord user ID and open provider strings.
    static let listJSON = #"{"identities":[{"provider_type":"FUTURE","provider_id":"provider&雪","provider_issued_user_id":"external%雪","user_id":"18446744073709551615"}]}"#
}
