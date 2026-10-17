import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// All webhook routes traverse the real bounded REST policy with finite injected transports and a manual clock.
@Suite(.timeLimit(.minutes(1))) struct WebhookIntegrationTests {
    /// Every route transmits the exact versioned path/query/header/body and returns its independently typed response.
    /// - Parameter index: Stable index into the complete webhook catalog, including compatibility wait variants.
    /// - Throws: Unexpected descriptor, request, response or resource-cleanup errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<18) func success(index: Int) async throws {
        let (endpoint, bytes) = try WebhookEndpointTests.catalog()[index]
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.map { QueryItem(name: $0.name, value: $0.value) } ?? []
            #expect(query == endpoint.query)
            #expect(request.headers.first { $0.name.lowercased() == "authorization" }?.value == (endpoint.authentication == .bot ? "Bot synthetic" : nil))
            #expect(request.headers.first { $0.name.lowercased() == "x-audit-log-reason" }?.value.removingPercentEncoding == endpoint.auditReason)
            #expect(request.headers.first { $0.name == "X-GitHub-Event" } == endpoint.headers.first { $0.name == "X-GitHub-Event" })
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(bytes, status: endpoint.successStatuses.first!)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: try WebhookEndpointTests.credential(endpoint), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, egress: UUID())
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Validation/authentication/permission/rate errors retain safe API evidence; unsafe submitted server failures remain uncertain.
    /// - Parameters:
    ///   - index: All management/execution/message descriptor variants.
    ///   - status: Scripted documented failure class; 429 uses a single-attempt budget.
    /// - Throws: Unexpected setup/errors fail this test; exact API/indeterminate error categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<18, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try WebhookEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data(#"{"code":50035,"message":"private-token","errors":{"content":{"_errors":[{"code":"BAD","message":"private-token"}]}}}"#.utf8), status: status)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: try WebhookEndpointTests.credential(endpoint), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1), egress: UUID())
        do { _ = try await client.execute(endpoint); Issue.record("Expected API failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status && error.code == 50035)
            #expect(error.withUnsafePayload { $0 != nil })
            #expect(!String(reflecting: error).contains("private-token"))
        } catch let error as DiscordError {
            #expect(status == 500 && endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.serverErrorAfterSubmission))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// All production decoders reject malformed bodies and unrelated 2xx statuses at the client boundary.
    /// - Parameter index: Every route variant, including strict-empty deletes and nullable-string Slack responses.
    /// - Throws: Unexpected setup errors fail this test; sanitized schema and unlisted-status failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<18) func malformedAndUnexpectedStatus(index: Int) async throws {
        let (endpoint, bytes) = try WebhookEndpointTests.catalog()[index]
        for status in [endpoint.successStatuses.first!, 202] {
            let transport = try ScriptedHTTPTransport(steps: [{ request in
                await request.body?.close()
                return try Self.response(status == 202 ? bytes : Data("{}".utf8), status: status)
            }])
            let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
            let client = RESTClient(credential: try WebhookEndpointTests.credential(endpoint), identity: RateLimitIdentity(),
                transport: transport, coordinator: coordinator, clock: clock, egress: UUID())
            do { _ = try await client.execute(endpoint); Issue.record("Expected invalid response/status") }
            catch let error as APIResponseError { #expect(status == 202 && error.status == 202) }
            catch let error as DiscordError { #expect(status != 202 && error == .transport(.invalidResponse)) }
            #expect(await transport.executionCount == 1)
            #expect(await coordinator.snapshot().activeCount == 0)
            #expect(clock.pendingSleepCount == 0)
            await coordinator.close()
        }
    }

    /// A complete 429 rejection permits one bounded replay; both attempts preserve token/header/body policy.
    /// - Parameter index: All catalog variants, including unsafe creates/edits/deletes and compatibility adapters.
    /// - Throws: Unexpected setup/retry errors fail this test; manual time proves admission waits for the rejection budget.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<18) func rejectedRateRetry(index: Int) async throws {
        let (endpoint, bytes) = try WebhookEndpointTests.catalog()[index]
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(Data(#"{"retry_after":0.25,"global":false}"#.utf8), status: 429)
        }, { request in
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(bytes, status: endpoint.successStatuses.first!)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: try WebhookEndpointTests.credential(endpoint), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 2), egress: UUID())
        let task = Task { try await client.execute(endpoint) }
        while true {
            let count = await transport.executionCount, snapshot = await coordinator.snapshot()
            if count == 1 && snapshot.activeCount == 0 && snapshot.queuedCount == 1 { break }
            try Task.checkCancellation(); await Task.yield()
        }
        try clock.advance(by: .milliseconds(249))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(1))
        #expect(try await task.value == bytes)
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Cancellation before execution and expired deadlines create no request, reservation or body producer.
    /// - Parameter index: Every current webhook route and wait variant.
    /// - Throws: Unexpected setup failures fail the test; cancellation and deadline errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<18) func cancellationAndExpiredDeadline(index: Int) async throws {
        let endpoint = try WebhookEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: try WebhookEndpointTests.credential(endpoint), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, egress: UUID())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(endpoint)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await client.execute(endpoint, deadline: clock.now) }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Token routes require matching dedicated credentials and explicit egress before cached data or network admission.
    /// - Throws: Unexpected setup errors fail this test; no production credentials, network or clock sleeps are used.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func missingEgressAndWrongToken() async throws {
        let token = try WebhookToken("private-token"), id = WebhookID(rawValue: 1)
        let endpoint = try WebhookEndpoints.getWithToken(webhookID: id, token: token)
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [])
        let missing = RESTClient(credential: .webhook(id, token), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        await #expect(throws: DiscordError.validation(.missingValue)) { try await missing.execute(endpoint) }
        let wrong = RESTClient(credential: .webhook(id, try WebhookToken("other")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, egress: UUID())
        await #expect(throws: DiscordError.validation(.missingValue)) { try await wrong.execute(endpoint) }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Native execution/edit multipart requests preserve IDs, payload_json, per-file caps and complete edit retention.
    /// - Throws: Unexpected upload/descriptor/body errors fail this test; mismatched retention and caps are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func multipartExecutionAndEdit() async throws {
        let token = try WebhookToken("private-token"), id = WebhookID(rawValue: 1)
        let file = try MessageUploadFile(id: 0, filename: "a.txt", contentType: "text/plain", bytes: Data("upload-content".utf8))
        let attachment = try MessageAttachmentRequest(id: .upload(0), filename: "a.txt")
        let create = try WebhookEndpoints.execute(webhookID: id, token: token,
            request: WebhookExecute(message: MessageCreate(attachments: .value([attachment]))), files: [file])
        let edit = try WebhookEndpoints.editMessage(webhookID: id, token: token, messageID: .init(rawValue: 4),
            request: WebhookMessageEdit(attachments: .value([attachment])), files: [file])
        let fileComponent = try MessageComponent(data: Data(#"{"type":13,"file":{"url":"attachment://a.txt"}}"#.utf8))
        let v2Edit = try WebhookEndpoints.editMessage(webhookID: id, token: token, messageID: .init(rawValue: 4),
            request: WebhookMessageEdit(components: .value([fileComponent]), attachments: .value([attachment]), previousFlags: 1 << 15),
            withComponents: true, files: [file])
        #expect(v2Edit.query == [.init(name: "with_components", value: "true")])
        for body in [try #require(create.body), try #require(edit.body), try #require(v2Edit.body)] {
            #expect(body.isStreaming)
            let bytes = try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes)
            let text = String(decoding: bytes, as: UTF8.self)
            #expect(text.contains("payload_json") && text.contains("files[0]") && text.contains("upload-content"))
            #expect(text.contains(#""attachments":[{"filename":"a.txt","id":0}]"#))
            #expect(bytes.count <= body.accountedBytes)
        }
        let v2Bytes = try await ResponseBody.collect(v2Edit.body?.makeStream(), maximumBytes: 1_048_576)
        let multipartText = String(decoding: v2Bytes, as: UTF8.self)
        let payloadStart = try #require(multipartText.range(of: "\r\n\r\n")?.upperBound)
        let payloadTail = multipartText[payloadStart...]
        let payloadEnd = try #require(payloadTail.range(of: "\r\n--")?.lowerBound)
        let payload = try JSONValue.parse(Data(payloadTail[..<payloadEnd].utf8))
        #expect(payload == (try JSONValue.parse(Data(#"{"components":[{"type":13,"file":{"url":"attachment://a.txt"}}],"attachments":[{"id":0,"filename":"a.txt"}]}"#.utf8))))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookEndpoints.execute(webhookID: id, token: token,
                request: WebhookExecute(message: MessageCreate(attachments: .value([attachment]))), files: [file, file])
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try WebhookEndpoints.execute(webhookID: id, token: token,
                request: WebhookExecute(message: MessageCreate(attachments: .value([attachment]))), files: [file],
                limits: MessageUploadLimits(maximumFileBytes: 1))
        }
        #expect(throws: DiscordError.validation(.missingValue)) {
            try WebhookEndpoints.editMessage(webhookID: id, token: token, messageID: .init(rawValue: 4), request: WebhookMessageEdit(), files: [file])
        }
    }

    /// A canceled in-flight native upload closes the active source exactly once and preserves uncertain mutation evidence.
    /// - Throws: Unexpected setup/resource failures fail the test; cancellation is coordinated by barriers, never sleeps.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inFlightUploadCancellation() async throws {
        let entered = TestBarrier(), release = TestBarrier(), probe = WebhookUploadProbe()
        let file = try MessageUploadFile(id: 0, filename: "a.txt", maximumBytes: 1) {
            try BodyStream(maximumChunkBytes: 1, next: {
                entered.open(); try await release.wait(); return Data([1])
            }, close: { await probe.closed(); release.open() })
        }
        let token = try WebhookToken("private-token"), id = WebhookID(rawValue: 1)
        let endpoint = try WebhookEndpoints.execute(webhookID: id, token: token,
            request: WebhookExecute(message: MessageCreate()), files: [file])
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            _ = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            return try Self.response(Data(), status: 204)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .webhook(id, token), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, egress: UUID())
        let task = Task { try await client.execute(endpoint) }
        try await entered.wait(); task.cancel()
        await #expect(throws: DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)) { try await task.value }
        #expect(await probe.closes == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Produces an independently owned finite response with a learned route budget for deterministic reuse/retry tests.
    /// - Parameters:
    ///   - bytes: Complete success or failure bytes; empty means no response stream.
    ///   - status: Explicit wire status; body presence never determines response semantics.
    /// - Returns: Synthetic response with bounded payload and a finite 100-request, one-second route window.
    /// - Throws: Fixture RequestBody construction errors only.
    private static func response(_ bytes: Data, status: Int) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [.init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"), .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}

/// Tracks exactly-once source cleanup under cancellation without timing-dependent state reads.
private actor WebhookUploadProbe {
    var closes = 0
    /// Records relinquishment of the sole currently open upload source.
    func closed() { closes += 1 }
}
