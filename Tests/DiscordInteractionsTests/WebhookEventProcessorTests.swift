import Crypto
import DiscordCore
import DiscordLogging
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordInteractions

/// Verifies durable-before-204 event ingress independently of interaction PONG or callback state.
@Suite struct WebhookEventProcessorTests {
    /// Signed webhook PING acknowledges empty 204, and identical authenticated event retries cause one durable admission.
    /// - Throws: Unexpected key, signature, projection or configuration errors fail the test.
    @Test func signedPingAndDuplicateRetry() async throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
        let verifier = try SignedRequestVerifier(publicKey: Self.hex(key.publicKey.rawRepresentation),
            replayPolicy: .allowIdenticalRetries, now: { 1_000 })
        let store = WebhookAdmissionProbe()
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, digest in
            try await store.admit(envelope, body: body, key: digest)
        }
        for body in [Data(#"{"version":1,"application_id":"1","type":0}"#.utf8), Self.body()] {
            var message = Data("1000".utf8); message.append(body)
            let signature = try key.signature(for: message)
            let headers = [HTTPHeader(name: "X-Signature-Ed25519", value: Self.hex(signature)),
                HTTPHeader(name: "X-Signature-Timestamp", value: "1000")]
            let first = try await verifier.verify(headers: headers, body: body)
            let retry = try await verifier.verify(headers: headers, body: body)
            #expect(!first.isReplay && retry.isReplay)
            for request in [first, retry] {
                let response = await processor.process(request)
                #expect(response.status == 204 && response.body == nil)
                #expect(response.headers == [HTTPHeader(name: "Content-Type", value: "application/json")])
            }
        }
        #expect(await store.count() == 1)
        #expect(await store.lastBody() == Self.body())
        #expect(await store.keys().first?.count == 64)
        let otherProcess = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, digest in
            try await store.admit(envelope, body: body, key: digest)
        }
        #expect(await otherProcess.process(Self.request()).status == 204)
        #expect(await store.count() == 2)
        #expect(await store.keys().count == 1)
    }

    /// The first reservation remains unacknowledged until durable work is committed; duplicates and global overload retry.
    /// - Throws: Unexpected configuration/fixture failures fail the test.
    @Test func durableBoundaryConcurrentDuplicateAndOverload() async throws {
        let store = WebhookAdmissionProbe(blocked: true)
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1), maximumConcurrentAdmissions: 1) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        let first = Task { await processor.process(Self.request()) }
        await store.waitForCall()
        #expect(await store.committedCount() == 0)
        #expect(await processor.process(Self.request()).status == 503)
        #expect(await processor.process(Self.request("second")).status == 503)
        #expect(await store.count() == 1)
        await store.release()
        #expect(await first.value.status == 204)
        #expect(await store.committedCount() == 1)
        #expect(await processor.process(Self.request()).status == 204)
        #expect(await processor.process(Self.request("second")).status == 204)
        #expect(await store.count() == 2)
    }

    /// Errors release reservations without caching failure; cancellation before/during admission permits safe retries.
    /// - Throws: Unexpected configuration/fixture errors fail the test.
    @Test func failureCancellationAndRecovery() async throws {
        let store = WebhookAdmissionProbe(failures: 1)
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1), maximumConcurrentAdmissions: 1) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        #expect(await processor.process(Self.request()).status == 503)
        #expect(await processor.process(Self.request()).status == 204)
        #expect(await store.count() == 2)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await processor.process(Self.request("before"))
        }
        #expect(await canceled.value.status == 503)
        #expect(await store.count() == 2)
        let blocking = WebhookAdmissionProbe(blocked: true)
        let pending = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, key in
            try await blocking.admit(envelope, body: body, key: key)
        }
        let work = Task { await pending.process(Self.request()) }
        await blocking.waitForCall()
        work.cancel()
        await blocking.release()
        #expect(await work.value.status == 503)
        #expect(await pending.process(Self.request()).status == 204)
        #expect(await blocking.count() == 2)
    }

    /// Cancellation stays diagnostic while genuine durable-store degradation remains a warning.
    /// - Parameter outcome: Explicit cancellation, cancelled-task failure or ordinary storage failure.
    /// - Throws: Unexpected processor configuration errors fail the test.
    @Test(arguments: ["cancellation", "cancelled_task", "failure"])
    func persistenceFailureLogging(_ outcome: String) async throws {
        let recorder = LogRecorder()
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { _, _, _ in
            if outcome == "cancellation" { throw CancellationError() }
            if outcome == "cancelled_task" { withUnsafeCurrentTask { $0?.cancel() } }
            throw DiscordError.validation(.invalidValue)
        }
        let response = await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            await Task { await processor.process(Self.request("private_webhook_payload")) }.value
        }
        #expect(response.status == 503)
        let entries = recorder.entries
        let failure = try #require(entries.first { $0.metadata["dk.event"] == "interactions.webhook.persistence_failed" })
        #expect(failure.level == (outcome == "failure" ? .warning : .debug))
        #expect(failure.metadata["dk.cancelled"]?.description == (outcome == "failure" ? "false" : "true"))
        #expect(entries.suffix(3).compactMap { $0.metadata["dk.event"]?.description } == [
            "interactions.webhook.persistence_failed", "interactions.webhook.response_prepared",
            "interactions.webhook.released",
        ])
        #expect(entries.last?.metadata["dk.active"]?.description == "0")
        if outcome != "failure" { #expect(entries.allSatisfy { $0.level < .warning }) }
        #expect(!String(describing: entries.map { ($0.message, $0.metadata) }).contains("private_webhook_payload"))
        #expect(entries.allSatisfy { $0.label == "discordkit.interactions.webhooks" })
    }

    /// A durable commit followed by an uncertain error returns 503; a retry resolves the existing marker without duplicate effects.
    /// - Throws: Unexpected configuration errors fail the test.
    @Test func ambiguousDurableCommitRetry() async throws {
        let store = WebhookAdmissionProbe(failures: 1, failAfterCommit: true)
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        #expect(await processor.process(Self.request()).status == 503)
        #expect(await store.committedCount() == 1)
        #expect(await processor.process(Self.request()).status == 204)
        #expect(await store.count() == 2)
        #expect(await store.committedCount() == 1)
    }

    /// Successful commit despite cancellation remains marked; the next retry acknowledges without repeating admission.
    /// - Throws: Unexpected configuration errors fail the test.
    @Test func commitAfterCancellationIsDuplicateSafe() async throws {
        let store = WebhookAdmissionProbe(blocked: true, observeCancellation: false)
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        let task = Task { await processor.process(Self.request()) }
        await store.waitForCall()
        task.cancel()
        await store.release()
        #expect(await task.value.status == 503)
        #expect(await processor.process(Self.request()).status == 204)
        #expect(await store.count() == 1)
        #expect(await store.committedCount() == 1)
    }

    /// Finite local FIFO eviction and disabled retention always defer retry authority to durable storage.
    /// - Throws: Unexpected configuration errors fail the test.
    @Test func boundedRetentionAndDisabledOptimization() async throws {
        let store = WebhookAdmissionProbe()
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1), maximumRememberedDeliveries: 1) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        for name in ["one", "two", "two", "one"] { #expect(await processor.process(Self.request(name)).status == 204) }
        #expect(await store.count() == 3)
        #expect(await store.keys().count == 2)
        let noMemory = try WebhookEventProcessor(applicationID: .init(rawValue: 1), maximumRememberedDeliveries: 0) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        for _ in 0..<2 { #expect(await noMemory.process(Self.request()).status == 204) }
        #expect(await store.count() == 5)
    }

    /// Different original JSON spellings intentionally have different retry keys; semantic idempotency belongs to the consumer.
    /// - Throws: Unexpected configuration errors fail the test.
    @Test func deliveryKeysUseOriginalBytes() async throws {
        let store = WebhookAdmissionProbe()
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        #expect(await processor.process(Self.request()).status == 204)
        var body = Data(" \n".utf8); body.append(Self.body())
        #expect(await processor.process(.init(rawBody: body, timestamp: 1_000, isReplay: false)).status == 204)
        #expect(await store.keys().count == 2)
    }

    /// Malformed/unrecognized outer schemas and wrong applications reject before durable work; future event names admit safely.
    /// - Throws: Unexpected configuration/fixture errors fail the test.
    @Test func malformedUnsupportedAndBounds() async throws {
        let store = WebhookAdmissionProbe()
        let processor = try WebhookEventProcessor(applicationID: .init(rawValue: 1)) { envelope, body, key in
            try await store.admit(envelope, body: body, key: key)
        }
        for input in ["invalid", #"{}"#, #"{"version":1,"application_id":"2","type":0}"#,
                      #"{"version":2,"application_id":"1","type":0}"#, #"{"version":1,"application_id":"1","type":99}"#,
                      #"{"version":1,"application_id":"1","type":1}"#,
                      #"{"version":1,"application_id":"1","type":1,"event":{"type":"ENTITLEMENT_CREATE","timestamp":"x","data":{}}}"#] {
            #expect(await processor.process(.init(rawBody: Data(input.utf8), timestamp: 1_000, isReplay: false)).status == 400)
        }
        #expect(await store.count() == 0)
        #expect(await processor.process(Self.request()).status == 204)
        let bounded = try WebhookEventProcessor(applicationID: .init(rawValue: 1), limits: .init(maximumBytes: 5)) { _, _, _ in
            Issue.record("Over-limit event reached durable storage"); return .accepted
        }
        #expect(await bounded.process(Self.request()).status == 400)
        for (concurrent, retention, limits) in [(0, 0, JSONLimits.default), (1, -1, .default),
            (1, 1, .init(maximumBytes: 0)), (1, 1, .init(maximumDepth: 129)), (1, 1, .init(maximumNodes: 0))] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try WebhookEventProcessor(applicationID: .init(rawValue: 1), maximumConcurrentAdmissions: concurrent,
                    maximumRememberedDeliveries: retention, limits: limits) { _, _, _ in .accepted }
            }
        }
    }

    /// Builds a trusted-module request fixture; the separate signed test proves public authentication integration.
    /// - Parameter name: Synthetic future-event name used to distinguish delivery bodies.
    /// - Returns: A verified token manufactured only via testable module access, without live credentials.
    private static func request(_ name: String = "future") -> VerifiedDiscordRequest {
        .init(rawBody: body(name), timestamp: 1_000, isReplay: false)
    }

    /// Creates an independently authored future-event envelope for deterministic delivery/retry tests.
    /// - Parameter name: Synthetic ASCII event name; callers use constant nonescaped values.
    /// - Returns: Original UTF-8 bytes with no real user data, credentials or external URLs.
    private static func body(_ name: String = "future") -> Data {
        Data("{\"version\":1,\"application_id\":\"1\",\"type\":1,\"event\":{\"type\":\"\(name)\",\"timestamp\":\"2026-10-17T12:00:00Z\",\"data\":{}}}".utf8)
    }

    /// Encodes synthetic Ed25519 key/signature bytes in Discord's hexadecimal wire format.
    /// - Parameter bytes: Public key or signature bytes belonging to the fixed test key.
    /// - Returns: Lowercase two-digit hexadecimal without separators.
    private static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// Actor-owned test durable store with explicit barriers, atomic duplicate detection and injected transient errors.
private actor WebhookAdmissionProbe {
    private var calls = 0
    private var bodies: [Data] = []
    private var committed = Set<String>()
    private var blocked: Bool
    private var failures: Int
    private let failAfterCommit: Bool
    private let observeCancellation: Bool
    private var gate: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?

    /// Creates a deterministic store fixture without starting work.
    /// - Parameters:
    ///   - blocked: Whether admission suspends at an explicit commit barrier, default false.
    ///   - failures: Number of transient errors to inject before successful admission, default zero.
    ///   - observeCancellation: Whether to throw cancellation before commit, default true.
    ///   - failAfterCommit: Whether injected failures happen after committing, simulating an uncertain result.
    init(blocked: Bool = false, failures: Int = 0, observeCancellation: Bool = true, failAfterCommit: Bool = false) {
        self.blocked = blocked; self.failures = failures; self.observeCancellation = observeCancellation
        self.failAfterCommit = failAfterCommit
    }

    /// Atomically commits a body/digest after explicit test synchronization and injected failure checks.
    /// - Parameters:
    ///   - envelope: Typed event expected to match application one.
    ///   - body: Exact signed body retained for assertion.
    ///   - key: Stable opaque digest used as the durable duplicate marker.
    /// - Returns: Accepted for a newly committed key, alreadyAccepted for a committed duplicate.
    /// - Throws: Injected invalid-value errors before/after commit according to policy, or cooperative CancellationError before commit.
    func admit(_ envelope: WebhookEventEnvelope, body: Data, key: String) async throws -> WebhookEventAdmission {
        #expect(envelope.applicationID.rawValue == 1)
        calls += 1; bodies.append(body)
        ready?.resume(); ready = nil
        if blocked { await withCheckedContinuation { gate = $0 } }
        if observeCancellation { try Task.checkCancellation() }
        if failures > 0, !failAfterCommit { failures -= 1; throw DiscordError.validation(.invalidValue) }
        let inserted = committed.insert(key).inserted
        if failures > 0 { failures -= 1; throw DiscordError.validation(.invalidValue) }
        return inserted ? .accepted : .alreadyAccepted
    }

    /// Waits for the first durable call using a continuation rather than a timing-sensitive sleep.
    func waitForCall() async {
        if calls > 0 { return }
        await withCheckedContinuation { ready = $0 }
    }

    /// Opens the commit barrier and resumes its sole bounded pending test admission.
    func release() { blocked = false; gate?.resume(); gate = nil }

    /// Returns the number of attempted durable admissions, including failures and duplicates.
    /// - Returns: Exact actor-isolated invocation count.
    func count() -> Int { calls }

    /// Returns the number of unique durable markers actually committed.
    /// - Returns: Exact count independent of attempted/blocked admissions.
    func committedCount() -> Int { committed.count }

    /// Exposes committed opaque keys for bounded-retention and cross-process retry assertions.
    /// - Returns: Unordered stable digests; no credentials are included.
    func keys() -> Set<String> { committed }

    /// Returns the most recently received exact body for authentication-boundary assertions.
    /// - Returns: Original bytes or nil before the first admission attempt.
    func lastBody() -> Data? { bodies.last }
}
