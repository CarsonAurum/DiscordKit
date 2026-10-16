import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies configurable descriptor limits remain bounded and fully participate in scheduler byte admission.
@Suite struct EndpointMetadataTests {
    /// Existing descriptors keep their default 256-query and 64-KiB retained-text boundaries.
    @Test func preservedDefaults() throws {
        let queries = Array(repeating: QueryItem(name: "x", value: "y"), count: 256)
        let endpoint = try Endpoint<Data>(method: "GET", path: ["x"], query: queries, decode: { $0 })
        #expect(endpoint.query.count == 256)
        #expect(endpoint.accountedMetadataBytes == 6 + 512)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: queries + [QueryItem(name: "x", value: nil)], decode: { $0 })
        }
        let exact = try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "q", value: String(repeating: "a", count: 65_529))], decode: { $0 })
        #expect(exact.accountedMetadataBytes == 65_536)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "q", value: String(repeating: "a", count: 65_530))], decode: { $0 })
        }
    }

    /// Invalid configurable caps fail safely before subtraction or iteration can overflow.
    /// - Parameter cap: A query-count cap outside the inclusive supported range.
    @Test(arguments: [Int.min, -1, 0, 2_049, Int.max])
    func invalidQueryCaps(cap: Int) {
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], maximumQueryItems: cap, decode: { $0 })
        }
    }

    /// Byte caps are positive and cannot exceed one MiB even when caller-selected inputs are empty.
    /// - Parameter cap: A retained-text cap outside the inclusive supported range.
    @Test(arguments: [Int.min, -1, 0, 1_048_577, Int.max])
    func invalidByteCaps(cap: Int) {
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], maximumMetadataBytes: cap, decode: { $0 })
        }
    }

    /// A reduced local query cap accepts its exact boundary and rejects a single additional bare field.
    @Test func configurableQueryBoundaries() throws {
        let query = [QueryItem(name: "only", value: nil)]
        let endpoint = try Endpoint<Data>(method: "GET", path: ["x"], query: query, maximumQueryItems: 1, decode: { $0 })
        #expect(endpoint.query == query)
        #expect(endpoint.accountedMetadataBytes == 10)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: query + query, maximumQueryItems: 1, decode: { $0 })
        }
        let maximum = Array(repeating: QueryItem(name: "x", value: nil), count: 2_048)
        #expect(try Endpoint<Data>(method: "GET", path: ["x"], query: maximum, maximumQueryItems: 2_048, decode: { $0 }).query.count == 2_048)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: maximum + query, maximumQueryItems: 2_048, decode: { $0 })
        }
    }

    /// Retained-text limits count raw UTF-8 names and values exactly, including multibyte scalars.
    @Test func configurableByteBoundaries() throws {
        let query = [QueryItem(name: "q", value: "😀")]
        let exact = try Endpoint<Data>(method: "GET", path: ["x"], query: query, maximumMetadataBytes: 11, decode: { $0 })
        #expect(exact.accountedMetadataBytes == 11)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: query, maximumMetadataBytes: 10, decode: { $0 })
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try Endpoint<Data>(method: "GET", path: ["x"], maximumMetadataBytes: 1, decode: { $0 })
        }
        let maximum = try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "q", value: String(repeating: "a", count: 1_048_569))],
                                         maximumMetadataBytes: 1_048_576, decode: { $0 })
        #expect(maximum.accountedMetadataBytes == 1_048_576)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "q", value: String(repeating: "a", count: 1_048_570))],
                               maximumMetadataBytes: 1_048_576, decode: { $0 })
        }
    }

    /// All retained metadata sources remain counted when a larger cap permits a documented search payload.
    @Test func metadataSourcesAndLargeSearch() throws {
        let bulkURL = try #require(URL(string: "https://docs.discord.com/developers/resources/message"))
        let endpoint = try Endpoint<Data>(method: "POST", path: ["x"], route: "/r", query: [QueryItem(name: "q", value: "v")],
            majorParameter: "major", auditReason: "audit", headers: [HTTPHeader(name: "Accept", value: "text/plain")],
            invalidates: ["tag"], bulk: .init(maximumItems: 1, preservesOrder: true, permitsPartialResults: false, documentationURL: bulkURL),
            maximumMetadataBytes: 1_048_576, decode: { $0 })
        let expected = ["POST", "x", "/r", "q", "v", "major", "audit", "Accept", "text/plain", "tag", bulkURL.absoluteString]
            .reduce(0) { $0 + $1.utf8.count }
        #expect(endpoint.accountedMetadataBytes == expected)
        let read = try Endpoint<Data>(method: "GET", path: ["x"], retrySafety: .safe, readPolicy: .init(tags: ["tag"]),
                                      maximumMetadataBytes: 1_048_576, decode: { $0 })
        #expect(read.accountedMetadataBytes == 9)
        let query = largeSearchQuery()
        #expect(query.count > 500)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["guilds", "1", "messages", "search"], query: query, decode: { $0 })
        }
        let search = try Endpoint<Data>(method: "GET", path: ["guilds", "1", "messages", "search"], route: "/guilds/{guild.id}/messages/search", query: query,
                                        authentication: .none, maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576, decode: { $0 })
        #expect(search.query == query)
        #expect(search.accountedMetadataBytes > 100_000)
        #expect(search.accountedMetadataBytes < 1_048_576)
        let request = try search.makeRequest(credential: .none, userAgent: "local-test")
        #expect(request.url.absoluteString.contains("filename="))
        #expect(request.url.absoluteString.components(separatedBy: "channel_id=").count - 1 == 500)
    }

    /// Expanding descriptor caps never permits retained metadata plus a streaming reservation to overflow Int.
    @Test func bodyReservationOverflow() throws {
        let small = try Endpoint<Data>(method: "POST", path: ["x"], maximumMetadataBytes: 1_048_576, decode: { $0 })
        #expect(small.accountedMetadataBytes == 7)
        let boundary = try RequestBody.stream(contentType: "x", maximumBytes: Int.max - 7) {
            try BodyStream(maximumChunkBytes: 1, next: { nil }, close: {})
        }
        let accepted = try Endpoint<Data>(method: "POST", path: ["x"], body: boundary, maximumMetadataBytes: 1_048_576, decode: { $0 })
        #expect(accepted.body?.accountedBytes == Int.max - 7)
        let overflow = try RequestBody.stream(contentType: "x", maximumBytes: Int.max - 6) {
            try BodyStream(maximumChunkBytes: 1, next: { nil }, close: {})
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try Endpoint<Data>(method: "POST", path: ["x"], body: overflow, maximumMetadataBytes: 1_048_576, decode: { $0 })
        }
    }

    /// Larger descriptor text is still rejected by the existing aggregate/per-identity queue byte caps.
    /// - Parameter perIdentity: True limits one identity; false limits the whole coordinator.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func expandedMetadataStillConsumesAdmissionBytes(perIdentity: Bool) async throws {
        let endpoint = try Endpoint<Data>(method: "GET", path: ["search"], query: largeSearchQuery(), authentication: .none,
            retrySafety: .safe, maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576, decode: { $0 })
        let bytes = endpoint.accountedMetadataBytes
        #expect(bytes > 65_536)
        let policy = SchedulingPolicy(maximumQueuedBytes: perIdentity ? bytes : bytes - 1,
                                      maximumQueuedBytesPerIdentity: perIdentity ? bytes - 1 : bytes)
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock, policy: policy)
        let transport = try ScriptedHTTPTransport(steps: [])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport, coordinator: coordinator, clock: clock)
        await #expect(throws: RateLimitFailure.queueFull) { _ = try await client.execute(endpoint) }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().queuedBytes == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Builds an ordered local search-sized query containing 500 channels and 100 maximal filename filters.
    /// - Returns: Repeated raw keys and 1,024-character filenames, without credentials or live requests.
    private func largeSearchQuery() -> [QueryItem] {
        let channels = (0..<500).map { QueryItem(name: "channel_id", value: String($0 + 1)) }
        let filenames = (0..<100).map { _ in QueryItem(name: "filename", value: String(repeating: "a", count: 1_024)) }
        let authors = (0..<100).map { QueryItem(name: "author_id", value: String($0 + 1)) }
        return channels + filenames + authors
    }
}
