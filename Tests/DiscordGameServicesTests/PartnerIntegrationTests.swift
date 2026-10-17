import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordGameServices

/// Real shared REST admission/decoding tests for all new partner wire descriptors, with no sockets or live credentials.
@Suite(.timeLimit(.minutes(1))) struct PartnerIntegrationTests {
    /// Every operation transmits its exact API v10 method/body/header policy and decodes the original response contract.
    /// - Parameter index: Bot/external token, bot/external unmerge, publisher child and console merge catalog position.
    /// - Throws: Unexpected setup/admission/transport/decoding failure fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<6) func success(index: Int) async throws {
        let (endpoint, bytes) = try Self.catalog(index)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == "POST" && request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            let auth = request.headers.first { $0.name.lowercased() == "authorization" }
            #expect(auth?.value == (endpoint.authentication == .bot ? "Bot synthetic" : nil))
            let sent = try await ResponseBody.collect(request.body, maximumBytes: 65_536)
            #expect(sent == endpoint.body?.storedBodyBytes)
            return try Self.response(bytes, status: 200)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: endpoint.authentication == .bot ? .bot(try BotToken("synthetic")) : .none,
            identity: RateLimitIdentity(), transport: transport, coordinator: coordinator, clock: clock,
            retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// Rejected credentials/permission/rate responses remain sanitized API errors; submitted server errors stay indeterminate.
    /// - Parameters:
    ///   - index: All six partner operations, including explicit destructive unmerge.
    ///   - status: Scripted authentication, permission, rate or server rejection with a one-attempt budget.
    /// - Throws: Unexpected setup/execution errors fail the test; expected precise API/uncertainty categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<6, [401, 403, 429, 500]) func failure(index: Int, status: Int) async throws {
        let (endpoint, _) = try Self.catalog(index)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data(#"{"code":530007,"message":"sensitive-server-detail"}"#.utf8), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: endpoint.authentication == .bot ? .bot(try BotToken("synthetic")) : .none,
            identity: RateLimitIdentity(), transport: transport, coordinator: coordinator, clock: clock,
            retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("expected rejected operation") }
        catch let error as APIResponseError {
            #expect(status < 500 && error.status == status && error.code == 530007)
            #expect(!String(reflecting: error).contains("sensitive-server-detail"))
        } catch let error as DiscordError {
            #expect(status == 500 && error == .unknownMutationOutcome(.serverErrorAfterSubmission))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Cancellation before entry sends no partner mutation and leaves admission with no retained resources.
    /// - Parameter index: Every new partner descriptor.
    /// - Throws: Unexpected setup failures fail the test; CancellationError is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<6) func cancellation(index: Int) async throws {
        let (endpoint, _) = try Self.catalog(index)
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: endpoint.authentication == .bot ? .bot(try BotToken("synthetic")) : .none,
            identity: RateLimitIdentity(), transport: transport, coordinator: coordinator, clock: clock)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(endpoint)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Builds the complete bounded catalog, erasing only result type while retaining original strict decoders.
    /// - Parameter index: One of the six known operation positions supplied by the parameterized tests.
    /// - Returns: Endpoint and its valid response bytes; no requests execute during construction.
    /// - Throws: Descriptor or request validation errors, propagated to the test.
    private static func catalog(_ index: Int) throws -> (Endpoint<Data>, Data) {
        let app = ApplicationID(rawValue: UInt64.max), secret = try ClientSecret("synthetic-client")
        let proof = try ExternalAccountToken("synthetic-proof")
        let token = Data(PartnerAccountTests.tokenJSON.utf8)
        switch index {
        case 0: return try (erase(PartnerAccountEndpoints.provisionalBot(externalUserID: "game-account")), token)
        case 1: return try (erase(PartnerAccountEndpoints.provisionalExternal(applicationID: app, clientSecret: secret,
            externalAuthType: "OIDC", externalAuthToken: proof)), token)
        case 2: return try (erase(PartnerAccountEndpoints.unmergeBot(externalUserID: "game-account")), Data())
        case 3: return try (erase(PartnerAccountEndpoints.unmergeExternal(applicationID: app, clientSecret: secret,
            externalAuthType: "OIDC", externalAuthToken: proof)), Data())
        case 4: return try (erase(PartnerAccountEndpoints.publisherChild(parentAccessToken: .init("synthetic-parent"),
            childApplicationID: app, parentClientSecret: secret)), token)
        default: return try (erase(PartnerAccountEndpoints.mergeDeviceCode(applicationID: app, clientSecret: secret,
            deviceCode: .init("synthetic-device"), externalAuthType: "OIDC", externalAuthToken: proof)), token)
        }
    }

    /// Erases a typed result while preserving its decoding validation at the real REST execution boundary.
    /// - Parameter endpoint: Original descriptor whose response decoder must run before bytes are returned.
    /// - Returns: Equivalent immutable descriptor returning exact validated body bytes.
    /// - Throws: Descriptor validation errors, without I/O or task creation.
    private static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            body: endpoint.body, retrySafety: endpoint.retrySafety, decode: { bytes in
                _ = try endpoint.decode(bytes); return bytes
            })
    }

    /// Wraps finite synthetic response bytes in a real owned body stream.
    /// - Parameters:
    ///   - bytes: Exact JSON body or empty success payload.
    ///   - status: Explicit scripted status independent of response-body validity.
    /// - Returns: Finite response; REST execution owns and closes the optional stream.
    /// - Throws: Body validation errors for invalid local fixture bounds.
    private static func response(_ bytes: Data, status: Int) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [],
            body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
