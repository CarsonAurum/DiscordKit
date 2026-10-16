import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exercises descriptors, bounded codecs, credential separation and lazy operation helpers without live I/O.
@Suite struct HTTPContractTests {
    /// Builds a versioned request with repeated query keys, encoded segments, audit text and replayable JSON.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func encodedRequestAndReplay() async throws {
        let body = try RequestBody.json(["text": "hello"])
        let endpoint = try Endpoint<Data>(method: "POST", path: ["channels", "snow ☃", "messages"],
                                         route: "/channels/{channel.id}/messages", query: [QueryItem(name: "a b", value: "x+y&"), QueryItem(name: "a b", value: ""), QueryItem(name: "bare", value: nil)],
                                         authentication: .bot, successStatuses: [200, 201], majorParameter: "channel:1", usesGlobalLimit: false,
                                         auditReason: "because + / ☃", body: body, headers: [HTTPHeader(name: "Accept", value: "application/json")], decode: { $0 })
        let request = try endpoint.makeRequest(credential: .bot(BotToken("sentinel")), userAgent: "DiscordBot (https://example.test, 0.1)")
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://discord.com/api/v10/channels/snow%20%E2%98%83/messages?a%20b=x%2By%26&a%20b=&bare")
        #expect(request.headers.contains(HTTPHeader(name: "Authorization", value: "Bot sentinel")))
        #expect(request.headers.contains(HTTPHeader(name: "X-Audit-Log-Reason", value: "because%20%2B%20%2F%20%E2%98%83")))
        #expect(request.headers.contains(HTTPHeader(name: "Content-Type", value: "application/json")))
        #expect(endpoint.route == "/channels/{channel.id}/messages")
        #expect(endpoint.majorParameter == "channel:1")
        #expect(endpoint.accountedMetadataBytes > endpoint.path.joined().utf8.count)
        #expect(!endpoint.usesGlobalLimit)
        #expect(endpoint.successStatuses == [200, 201])
        #expect(try await ResponseBody.collect(request.body, maximumBytes: 100) == body.bytes)
        let replay = try endpoint.makeRequest(credential: .bot(BotToken("sentinel")), userAgent: "test")
        #expect(try await ResponseBody.collect(replay.body, maximumBytes: 100) == body.bytes)
        #expect(try endpoint.decode(body.bytes) == body.bytes)
        #expect(String(describing: endpoint) == "Endpoint(redacted)")
        #expect(String(reflecting: endpoint) == "Endpoint(redacted)")
        #expect(Mirror(reflecting: endpoint).children.count == 1)
    }

    /// Credentials attach only for explicitly accepted categories; unauthenticated descriptors always omit them.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func authenticationPolicies() throws {
        let bot = Credential.bot(try BotToken("bot-secret"))
        let bearer = Credential.bearer(try BearerToken("bearer-secret"))
        for policy in [AuthenticationPolicy.bot, .bearer, .botOrBearer, .none] {
            let endpoint = try Endpoint<Data>(method: "GET", path: ["users", "@me"], authentication: policy, decode: { $0 })
            for credential in [bot, bearer, .none, .interaction(try InteractionToken("path-secret")), .webhook(WebhookID(rawValue: 1), try WebhookToken("webhook-secret"))] {
                let accepted: Bool
                switch (policy, credential) {
                case (.none, _), (.bot, .bot), (.bearer, .bearer), (.botOrBearer, .bot), (.botOrBearer, .bearer): accepted = true
                default: accepted = false
                }
                if accepted {
                    let request = try endpoint.makeRequest(credential: credential, userAgent: "test")
                    #expect(request.url.host == "discord.com")
                    #expect(request.headers.filter { $0.name == "Authorization" }.count == (policy == .none ? 0 : 1))
                } else {
                    #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: credential, userAgent: "test") }
                }
            }
        }
        let endpoint = try Endpoint<Data>(method: "GET", path: ["x"], authentication: .none, decode: { $0 })
        #expect(throws: DiscordError.validation(.invalidValue)) { try endpoint.makeRequest(credential: .none, userAgent: "bad\r\nvalue") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try endpoint.makeRequest(credential: .none, userAgent: "") }
    }

    /// Raw access accepts relative routes and prevents absolute origins, traversal, delimiters and malformed escapes.
    /// - Parameter route: Unsafe raw route rejected before any transport can be called.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["https://evil.test/x", "//evil.test/x", "/../x", "/%2e%2e/x", "/%252e%252e/x", "/x%2Fy", "/x%5cy", "/x?token=secret", "/x#fragment", "/x//y", "/x/", "/%ZZ", "/", "/x\u{0}"])
    func rejectsUnsafeRawRoutes(route: String) {
        #expect(throws: DiscordError.self) { try Endpoint<Data>.raw(method: "GET", relativeRoute: route, decode: { $0 }) }
    }

    /// Already escaped segments decode/re-encode once and retain authentication and endpoint response policy.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func validRawRoute() throws {
        let endpoint = try Endpoint<Data>.raw(method: "GET", relativeRoute: "/users/%40me", query: [QueryItem(name: "same", value: "a"), QueryItem(name: "same", value: "b")], authentication: .none, decode: { $0 })
        #expect(endpoint.path == ["users", "@me"])
        #expect(try endpoint.makeRequest(credential: .none, userAgent: "test").url.absoluteString == "https://discord.com/api/v10/users/@me?same=a&same=b")
        #expect(endpoint.readPolicy == nil)
        #expect(endpoint.retrySafety == .unsafe)
    }

    /// Disallows authentication and framing overrides regardless of header-name casing.
    /// - Parameter name: Reserved request header controlled by the execution pipeline.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["Authorization", "aUtHoRiZaTiOn", "Proxy-Authorization", "Host", "Content-Length", "Transfer-Encoding", "User-Agent", "Content-Type", "X-Audit-Log-Reason"])
    func rejectsHeaderOverrides(name: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try Endpoint<Data>(method: "GET", path: ["x"], headers: [HTTPHeader(name: name, value: "secret")], decode: { $0 })
        }
    }

    /// Validates finite descriptor metadata, explicit read eligibility and documented bulk constraints.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func descriptorLimitsAndMetadata() throws {
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "get", path: ["x"], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: [".."], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x/y"], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: [], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [302], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], auditReason: String(repeating: "a", count: 513), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], headers: [HTTPHeader(name: "bad name", value: "x")], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], headers: [HTTPHeader(name: "Accept", value: "x\nsecret")], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], readPolicy: ReadPolicy(), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], retrySafety: .safe, readPolicy: ReadPolicy(timeToLive: .zero), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], retrySafety: .safe, readPolicy: ReadPolicy(), invalidates: ["tag"], decode: { $0 }) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try Endpoint<Data>(method: "GET", path: [String(repeating: "a", count: 65_537)], decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: Array(repeating: "x", count: 65), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], query: Array(repeating: QueryItem(name: "x", value: "y"), count: 257), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], route: String(repeating: "x", count: 1_025), decode: { $0 }) }
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "GET", path: ["x"], majorParameter: String(repeating: "x", count: 257), decode: { $0 }) }
        let hugeStream = try RequestBody.stream(contentType: "x", maximumBytes: Int.max) { try RequestBody(bytes: Data(), contentType: "x").makeStream() }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try Endpoint<Data>(method: "POST", path: ["x"], body: hugeStream, decode: { $0 }) }
        let url = try #require(URL(string: "https://docs.discord.com/developers/resources/message#bulk-delete-messages"))
        let bulk = BulkOperationMetadata(maximumItems: 100, preservesOrder: false, permitsPartialResults: true, documentationURL: url)
        let endpoint = try Endpoint<Data>(method: "POST", path: ["bulk"], invalidates: ["messages"], bulk: bulk, decode: { $0 })
        #expect(endpoint.bulk?.maximumItems == 100)
        #expect(endpoint.bulk?.preservesOrder == false)
        #expect(endpoint.bulk?.permitsPartialResults == true)
        #expect(endpoint.bulk?.documentationURL == url)
        #expect(endpoint.invalidates == ["messages"])
        #expect(throws: DiscordError.self) { try Endpoint<Data>(method: "POST", path: ["bulk"], bulk: BulkOperationMetadata(maximumItems: 0, preservesOrder: false, permitsPartialResults: false, documentationURL: url), decode: { $0 }) }
        let read = ReadPolicy(coalescing: false, timeToLive: .seconds(5), tags: ["me"])
        #expect(read.coalescing == false)
        #expect(read.timeToLive == .seconds(5))
        #expect(read.tags == ["me"])
        #expect(Set([read, read]).count == 1)
    }

    /// Reuse identities include request/status contracts, ignore set order and distinguish absent from empty values.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func representationIdentity() throws {
        let base = try Endpoint<Data>(method: "GET", path: ["x"], decode: { $0 })
        let variants = [
            try Endpoint<Data>(method: "GET", path: ["y"], decode: { $0 }),
            try Endpoint<Data>(method: "POST", path: ["x"], decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "x", value: nil)], decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], query: [QueryItem(name: "x", value: "")], decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], authentication: .none, decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [201], decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [200, 201], decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], auditReason: "", decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], body: RequestBody(bytes: Data(), contentType: "text/plain"), decode: { $0 }),
            try Endpoint<Data>(method: "GET", path: ["x"], headers: [HTTPHeader(name: "Accept-Language", value: "en")], decode: { $0 }),
        ]
        #expect(Set(([base] + variants).map(\.cacheIdentity)).count == variants.count + 1)
        #expect(base.cacheIdentity == (try Endpoint<Data>(method: "GET", path: ["x"], decode: { $0 })).cacheIdentity)
        let first = try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [200, 201, 204], decode: { $0 })
        let reordered = try Endpoint<Data>(method: "GET", path: ["x"], successStatuses: [204, 201, 200], decode: { $0 })
        #expect(first.cacheIdentity == reordered.cacheIdentity)
    }

    /// Covers exact form encoding, JSON, multipart binary preservation, header injection and framing/size bounds.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bodyFormatsAndBounds() async throws {
        let form = try RequestBody.form([QueryItem(name: "a b", value: "+☃"), QueryItem(name: "a b", value: ""), QueryItem(name: "bare", value: nil)])
        #expect(String(decoding: form.bytes, as: UTF8.self) == "a+b=%2B%E2%98%83&a+b=&bare")
        #expect(form.contentType == "application/x-www-form-urlencoded")
        #expect(try RequestBody.form([]).bytes.isEmpty)
        let part = try MultipartPart(name: "files[0]", filename: "attachment.bin", contentType: "application/octet-stream", bytes: Data([0, 255, 10]))
        let body = try RequestBody.multipart([part], boundary: "boundary_123")
        #expect(body.bytes.range(of: Data([0, 255, 10])) != nil)
        #expect(body.bytes.suffix(18) == Data("--boundary_123--\r\n".utf8))
        #expect(body.contentType == "multipart/form-data; boundary=boundary_123")
        #expect(try RequestBody.multipart([], boundary: "b").bytes == Data("--b--\r\n".utf8))
        #expect(throws: DiscordError.self) { try MultipartPart(name: "x\r\nInjected", bytes: Data()) }
        #expect(throws: DiscordError.self) { try MultipartPart(name: "x", filename: "a\".txt", bytes: Data()) }
        #expect(throws: DiscordError.self) { try MultipartPart(name: "x", contentType: "x\ny", bytes: Data()) }
        #expect(throws: DiscordError.self) { try RequestBody.multipart([part], boundary: "bad boundary") }
        #expect(throws: DiscordError.self) { try RequestBody.multipart([part], boundary: "") }
        #expect(throws: DiscordError.self) { try RequestBody.multipart([part], boundary: "b", maximumBytes: 1) }
        #expect(throws: DiscordError.self) { try RequestBody.multipart([MultipartPart(name: "x", bytes: Data("collision".utf8))], boundary: "collision") }
        #expect(throws: DiscordError.self) { try RequestBody(bytes: Data(), contentType: "", maximumBytes: 1) }
        #expect(throws: DiscordError.self) { try RequestBody(bytes: Data(), contentType: "x", maximumBytes: 0) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try RequestBody(bytes: Data([1, 2]), contentType: "x", maximumBytes: 1) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try RequestBody.json(["a": "b"], maximumBytes: 1) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try RequestBody.form([QueryItem(name: "x", value: "y")], maximumBytes: 1) }
        #expect(try await ResponseBody.collect(form.makeStream(), maximumBytes: 100) == form.bytes)
        let abandoned = try form.makeStream(); await abandoned.close()
        #expect(try await ResponseBody.collect(abandoned, maximumBytes: 100).isEmpty)
        #expect(String(describing: body) == "RequestBody(redacted)")
        #expect(String(reflecting: body) == "RequestBody(redacted)")
        #expect(Mirror(reflecting: body).children.count == 1)
    }

    /// Fresh stream factories replay content while reserving/enforcing their full cap and propagating cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func streamingReplayAndBounds() async throws {
        let body = try RequestBody.stream(contentType: "application/octet-stream", maximumBytes: 3) {
            let source = BodyProbe(chunks: [Data([1]), Data([2, 3])])
            return try BodyStream(maximumChunkBytes: 2, next: { await source.next() }, close: { await source.close() })
        }
        #expect(body.isStreaming)
        #expect(body.storedBodyBytes == nil)
        #expect(body.accountedBytes == 3)
        #expect(body.bytes.isEmpty)
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: 3) == Data([1, 2, 3]))
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: 3) == Data([1, 2, 3]))
        let stored = try RequestBody(bytes: Data([1]), contentType: "x")
        #expect(!stored.isStreaming)
        #expect(stored.storedBodyBytes == Data([1]))
        #expect(stored.accountedBytes == 1)
        let source = BodyProbe(chunks: [Data([1, 2]), Data([3, 4])])
        let excessive = try RequestBody.stream(contentType: "x", maximumBytes: 3) {
            try BodyStream(maximumChunkBytes: 2, next: { await source.next() }, close: { await source.close() })
        }
        await #expect(throws: DiscordError.transport(.limitExceeded)) { try await ResponseBody.collect(excessive.makeStream(), maximumBytes: 10) }
        #expect(await source.closeCount == 1)
        #expect(throws: DiscordError.validation(.invalidValue)) { try RequestBody.stream(contentType: "x", maximumBytes: 0) { try stored.makeStream() } }
        let failingFactory = try RequestBody.stream(contentType: "x", maximumBytes: 1) { throw DiscordError.transport(.disconnected) }
        #expect(throws: DiscordError.transport(.disconnected)) { try failingFactory.makeStream() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try Endpoint<Data>(method: "GET", path: ["x"], body: body, retrySafety: .safe, readPolicy: ReadPolicy(), decode: { $0 }) }
    }

    /// Pre-cancelled and actively cancelled collectors relinquish ownership before returning failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func collectorCancellationClosesSources() async throws {
        let source = BodyProbe(chunks: [Data([1])])
        let preCancelled = try BodyStream(maximumChunkBytes: 1, next: { await source.next() }, close: { await source.close() })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ResponseBody.collect(preCancelled, maximumBytes: 1)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await source.closeCount == 1)
        #expect(await source.pulls == 0)
        let entered = TestBarrier()
        let gate = TestBarrier()
        let active = BodyProbe(chunks: [])
        let streaming = try RequestBody.stream(contentType: "x", maximumBytes: 2) {
            try BodyStream(maximumChunkBytes: 1, next: {
                entered.open(); try await gate.wait(); return Data([1])
            }, close: { await active.close(); gate.open() })
        }
        let activeTask = Task { try await ResponseBody.collect(streaming.makeStream(), maximumBytes: 2) }
        try await entered.wait(); activeTask.cancel()
        await #expect(throws: CancellationError.self) { try await activeTask.value }
        #expect(await active.closeCount == 1)
    }

    /// Collects empty/chunked bodies, enforcing aggregate limits and cleanup after invalid configuration or producer failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func boundedCollectionAndCleanup() async throws {
        #expect(try await ResponseBody.collect(nil, maximumBytes: 1).isEmpty)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try EmptyResponse(data: Data([1])) }
        #expect(try EmptyResponse(data: Data()) == EmptyResponse(data: Data()))
        let state = BodyProbe(chunks: [Data(), Data([1, 2]), Data([3])])
        let stream = try BodyStream(maximumChunkBytes: 2, next: { await state.next() }, close: { await state.close() })
        #expect(try await ResponseBody.collect(stream, maximumBytes: 3) == Data([1, 2, 3]))
        #expect(await state.closeCount == 1)
        let overflow = BodyProbe(chunks: [Data([1, 2]), Data([3, 4])])
        let overflowStream = try BodyStream(maximumChunkBytes: 2, next: { await overflow.next() }, close: { await overflow.close() })
        await #expect(throws: DiscordError.transport(.limitExceeded)) { try await ResponseBody.collect(overflowStream, maximumBytes: 3) }
        #expect(await overflow.closeCount == 1)
        let invalid = BodyProbe(chunks: [Data([1])])
        let invalidStream = try BodyStream(maximumChunkBytes: 1, next: { await invalid.next() }, close: { await invalid.close() })
        await #expect(throws: DiscordError.validation(.invalidValue)) { try await ResponseBody.collect(invalidStream, maximumBytes: 0) }
        #expect(await invalid.closeCount == 1)
        #expect(await invalid.pulls == 0)
        let failed = BodyProbe(chunks: [])
        let failedStream = try BodyStream(maximumChunkBytes: 1, next: { throw TransportFailure.closed }, close: { await failed.close() })
        await #expect(throws: TransportFailure.closed) { try await ResponseBody.collect(failedStream, maximumBytes: 1) }
        #expect(await failed.closeCount == 1)
    }

    /// Error diagnostics conceal untrusted validation paths/messages while opt-in inspection retains exact nested data.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func errorEvidenceAndRedaction() throws {
        let data = Data("""
        {"code":999999,"message":"secret token","errors":{"activities":{"0":{"platform":{"_errors":[{"code":"FUTURE_CODE","message":"private"}]}}}},"future":1e1000}
        """.utf8)
        let error = APIResponseError(status: 400, headers: [HTTPHeader(name: "secret", value: "private")], body: data)
        #expect(error.code == 999_999)
        #expect(error.status == 400)
        #expect(error.headers.count == 1)
        #expect(!error.bodyWasTruncated)
        #expect(error.withUnsafeBody { $0 } == data)
        #expect(error.withUnsafePayload { $0 } == (try JSONValue.parse(data)))
        #expect(!String(describing: error).contains("secret"))
        #expect(!String(reflecting: error).contains("private"))
        #expect(Mirror(reflecting: error).children.count == 2)
        let malformed = APIResponseError(status: 502, headers: [], body: Data("<html>private</html>".utf8))
        #expect(malformed.code == nil)
        #expect(malformed.withUnsafePayload { $0 } == nil)
        let huge = APIResponseError(status: 500, headers: [], body: Data(repeating: 0, count: 1_048_577))
        #expect(huge.bodyWasTruncated)
        #expect(huge.withUnsafeBody { $0.count } == 1_048_576)
        #expect(APIResponseError(status: 400, headers: [], body: Data("{\"code\":1.5}".utf8)).code == nil)
    }

    /// Typed endpoint factories pin current routes, correct authentication, explicit safe retry and partial model decoding.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func typedEndpointsAndEmptyResponse() throws {
        let user = try DiscordEndpoints.currentUser()
        #expect(user.path == ["users", "@me"])
        #expect(user.authentication == .botOrBearer)
        #expect(user.retrySafety == .safe)
        #expect(user.readPolicy?.coalescing == true)
        #expect(user.readPolicy?.timeToLive == nil)
        #expect(try user.decode(Data("{\"id\":\"1\",\"username\":\"u\",\"discriminator\":\"0\",\"global_name\":null,\"avatar\":null}".utf8)).id == UserID(rawValue: 1))
        let application = try DiscordEndpoints.currentApplication(readPolicy: nil)
        #expect(application.path == ["applications", "@me"])
        #expect(application.authentication == .bot)
        #expect(application.readPolicy == nil)
        #expect(try application.decode(Data("{\"id\":\"2\",\"name\":\"App\",\"icon\":null,\"description\":\"\",\"bot_public\":true,\"bot_require_code_grant\":false,\"verify_key\":\"key\",\"team\":null}".utf8)).id == ApplicationID(rawValue: 2))
        #expect(throws: DiscordError.self) { try DiscordEndpoints.currentApplication(readPolicy: ReadPolicy(timeToLive: .seconds(-1))) }
        #expect(throws: DiscordError.self) { try DiscordEndpoints.currentUser(readPolicy: ReadPolicy(timeToLive: .zero)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try EmptyResponse(data: Data([1])) }
    }

    /// A CDN/foreign HTTPS origin receives zero authorization, and redirects surface without a follow-up exchange.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func assetCredentialSeparation() async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.url.host == "cdn.discordapp.com")
            #expect(request.headers.isEmpty)
            return HTTPResponse(status: 200, body: try RequestBody(bytes: Data([1, 2]), contentType: "x").makeStream())
        }, { request in
            #expect(request.headers.isEmpty)
            return HTTPResponse(status: 302, headers: [HTTPHeader(name: "Location", value: "https://foreign.test")])
        }])
        let client = try AssetClient(transport: transport, maximumBytes: 2)
        let url = try #require(URL(string: "https://cdn.discordapp.com/avatars/a.png"))
        #expect(try await client.get(url, context: TransportContext(clock: ManualClock())) == Data([1, 2]))
        await #expect(throws: APIResponseError.self) { try await client.get(url, context: TransportContext(clock: ManualClock())) }
        #expect(await transport.executionCount == 2)
        for invalid in ["http://foreign.test/a", "https://user:pass@foreign.test/a", "https://foreign.test/a#fragment"] {
            let invalidURL = try #require(URL(string: invalid))
            await #expect(throws: DiscordError.validation(.invalidValue)) { try await client.get(invalidURL, context: TransportContext(clock: ManualClock())) }
        }
        #expect(await transport.executionCount == 2)
        #expect(throws: DiscordError.validation(.invalidValue)) { try AssetClient(transport: transport, maximumBytes: 0) }
    }

    /// Asset size failures close their response, and pre-cancellation/inclusive deadlines perform no send.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func assetLimitsAndCancellation() async throws {
        let probe = BodyProbe(chunks: [Data([1, 2, 3])])
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 3,
                next: { await probe.next() }, close: { await probe.close() }))
        }])
        let client = try AssetClient(transport: transport, maximumBytes: 2)
        let url = try #require(URL(string: "https://foreign.test/asset"))
        let clock = ManualClock()
        await #expect(throws: DiscordError.transport(.limitExceeded)) { try await client.get(url, context: TransportContext(clock: clock)) }
        #expect(await probe.closeCount == 1)
        await #expect(throws: TransportFailure.deadlineExceeded) { try await client.get(url, context: TransportContext(clock: clock, deadline: clock.now)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.get(url, context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 1)
    }

    /// Empty/short pages keep their explicit next cursor, no fetch starts before demand, and iterator state is independent.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lazyCursorPagination() async throws {
        let probe = CursorProbe()
        let pages = try CursorPagination<Int, String, ManualClock>(context: TransportContext(clock: ManualClock())) { cursor in
            await probe.record(cursor)
            if cursor == nil { return CursorPage(items: [], nextCursor: "next") }
            if cursor == "next" { return CursorPage(items: [1], nextCursor: "last") }
            return CursorPage(items: [2], nextCursor: nil)
        }
        #expect(await probe.cursors.isEmpty)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next() == [])
        #expect(await probe.cursors.count == 1)
        #expect(try await iterator.next() == [1])
        #expect(try await iterator.next() == [2])
        #expect(try await iterator.next() == nil)
        #expect(await probe.cursors == [nil, "next", "last"])
        var another = pages.makeAsyncIterator()
        #expect(try await another.next() == [])
        #expect(await probe.cursors.count == 4)
    }

    /// Repeated cursors, exhausted page budgets, fetch errors, pre-cancellation and inclusive deadlines stop pagination.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func paginationFailureAndCancellation() async throws {
        let clock = ManualClock()
        let repeating = try CursorPagination<Int, String, ManualClock>(initialCursor: "same", context: TransportContext(clock: clock)) { _ in CursorPage(items: [1], nextCursor: "same") }
        var repeated = repeating.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await repeated.next() }
        #expect(try await repeated.next() == nil)
        let limited = try CursorPagination<Int, String, ManualClock>(maximumPages: 1, context: TransportContext(clock: clock)) { _ in CursorPage(items: [], nextCursor: "next") }
        var iterator = limited.makeAsyncIterator()
        #expect(try await iterator.next() == [])
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await iterator.next() }
        let expired = try CursorPagination<Int, String, ManualClock>(context: TransportContext(clock: clock, deadline: clock.now)) { _ in Issue.record("expired pagination fetched"); return CursorPage(items: [1], nextCursor: nil) }
        var expiredIterator = expired.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expiredIterator.next() }
        let failing = try CursorPagination<Int, String, ManualClock>(context: TransportContext(clock: clock)) { _ in throw DiscordError.transport(.disconnected) }
        var failingIterator = failing.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.disconnected)) { try await failingIterator.next() }
        #expect(try await failingIterator.next() == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try CursorPagination<Int, String, ManualClock>(maximumPages: 0, context: TransportContext(clock: clock)) { _ in CursorPage(items: [], nextCursor: nil) } }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = repeating.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let entered = TestBarrier()
        let release = TestBarrier()
        let suspended = try CursorPagination<Int, String, ManualClock>(context: TransportContext(clock: clock)) { _ in
            entered.open(); try await release.wait(); return CursorPage(items: [1], nextCursor: nil)
        }
        let active = Task {
            var iterator = suspended.makeAsyncIterator()
            return try await iterator.next()
        }
        try await entered.wait(); active.cancel()
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(release.waitingCount == 0)
    }

    /// Polling uses explicit completion and virtual-time delays; finite attempts never add an extra final sleep.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pollingVirtualTimeAndBudget() async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let probe = PollProbe()
        let task = Task {
            try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 2, interval: .seconds(5)) {
                let count = await probe.increment()
                return count == 1 ? PollingState<Int>.pending : .complete(42)
            }
        }
        try await sleeping.wait()
        #expect(await probe.count == 1)
        try clock.advance(by: .seconds(5))
        #expect(try await task.value == 42)
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: DiscordError.validation(.limitExceeded)) {
            let _: Int = try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 1, interval: .seconds(1)) { .pending }
        }
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: DiscordError.validation(.invalidValue)) {
            let _: Int = try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 0, interval: .seconds(1)) { .complete(1) }
        }
        await #expect(throws: DiscordError.validation(.invalidValue)) {
            let _: Int = try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 1, interval: .zero) { .complete(1) }
        }
    }

    /// Cancellation while polling sleeps removes virtual-clock waiters, and expired jobs perform no read.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pollingCancellationAndDeadline() async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let task = Task {
            let value: Int = try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 3, interval: .seconds(10)) { .pending }
            return value
        }
        try await sleeping.wait(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: TransportFailure.deadlineExceeded) {
            let _: Int = try await PollingOperation.poll(context: TransportContext(clock: clock, deadline: clock.now), maximumAttempts: 2, interval: .seconds(1)) {
                Issue.record("expired polling executed"); return .complete(1)
            }
        }
        await #expect(throws: DiscordError.transport(.disconnected)) {
            let _: Int = try await PollingOperation.poll(context: TransportContext(clock: clock), maximumAttempts: 2, interval: .seconds(1)) { throw DiscordError.transport(.disconnected) }
        }
    }
}

/// Finite body producer recording pull and cleanup ownership for codec tests.
private actor BodyProbe {
    let chunks: [Data]
    private(set) var pulls = 0
    private(set) var closeCount = 0
    /// Retains a finite chunk script without beginning production.
    /// - Parameter chunks: Ordered chunks, including empty ones; EOF follows the last.
    init(chunks: [Data]) { self.chunks = chunks }
    /// Returns the next scripted chunk and records the pull, including EOF.
    /// - Returns: Next bytes or `nil` when exhausted.
    func next() -> Data? { defer { pulls += 1 }; return pulls < chunks.count ? chunks[pulls] : nil }
    /// Records source cleanup; the enclosing BodyStream guarantees exactly-once calls.
    func close() { closeCount += 1 }
}

/// Captures exact optional cursors without timing assumptions or network access.
private actor CursorProbe {
    private(set) var cursors: [String?] = []
    /// Appends one requested cursor in actor order.
    /// - Parameter cursor: Exact request cursor; `nil` is a meaningful initial request.
    func record(_ cursor: String?) { cursors.append(cursor) }
}

/// Counts sequential polling attempts without shared mutable test state.
private actor PollProbe {
    private(set) var count = 0
    /// Increments and returns the next polling attempt number.
    /// - Returns: One-based count of completed increments.
    func increment() -> Int { count += 1; return count }
}
