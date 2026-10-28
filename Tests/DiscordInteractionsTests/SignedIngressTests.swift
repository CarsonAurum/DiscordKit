// File: Tests/DiscordInteractionsTests/SignedIngressTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordHTTP
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordInteractions

/// Verifies real Ed25519 authentication and bounded ingress without sockets or Discord credentials.
@Suite(.timeLimit(.minutes(1))) struct SignedIngressTests {
    /// A fixed test key signs deterministic request bytes; no production key or token is used.
    /// - Returns: A reproducible Ed25519 key.
    /// - Throws: Crypto failure constructing the fixed 32-byte private representation.
    static func key() throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
    }

    /// Encodes bytes for Discord's exact hexadecimal header/key representation.
    /// - Parameter bytes: Raw key/signature bytes.
    /// - Returns: Lowercase hexadecimal with two characters per byte.
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Signs the exact original timestamp prefix and body, including whitespace.
    /// - Parameters:
    ///   - body: Unmodified bytes.
    ///   - timestamp: Original decimal string, default 1000.
    /// - Returns: Two signature fields using deliberately mixed casing.
    /// - Throws: Crypto setup/signing failure.
    static func headers(_ body: Data, timestamp: String = "1000") throws -> [HTTPHeader] {
        let signature = try Self.key().signature(for: Data(timestamp.utf8) + body)
        return [HTTPHeader(name: "X-SIGNATURE-Ed25519", value: hex(signature)),
                HTTPHeader(name: "x-signature-timestamp", value: timestamp)]
    }

    /// Creates a verifier whose wall time remains fixed and whose policy can be varied per test.
    /// - Parameters:
    ///   - policy: Exact-byte retry policy.
    ///   - cap: Maximum replay entries.
    ///   - now: Deterministic wall seconds.
    /// - Returns: An independently owned authentication authority.
    /// - Throws: Invalid fixture key/policy errors.
    static func verifier(_ policy: SignedReplayPolicy = .rejectIdentical, cap: Int = 8,
                         now: @escaping @Sendable () -> Int64 = { 1000 }) throws -> SignedRequestVerifier {
        try SignedRequestVerifier(publicKey: hex(Self.key().publicKey.rawRepresentation), maximumReplayEntries: cap,
                                  replayPolicy: policy, now: now)
    }

    /// A valid signature preserves original bytes and exposes only constant redacted diagnostics.
    /// - Throws: Unexpected signing or authentication errors fail the test.
    @Test func authenticatesExactOriginalBytes() async throws {
        let body = Data(" {\n\"type\":1, \"value\":\"☃\" } ".utf8)
        let result = try await Self.verifier().verify(headers: Self.headers(body), body: body)
        #expect(result.rawBody == body)
        #expect(result.timestamp == 1000)
        #expect(!result.isReplay)
        #expect(String(describing: result) == "VerifiedDiscordRequest(redacted)")
        #expect(String(reflecting: result) == result.description)
        #expect(Mirror(reflecting: result).children.count == 1)
    }

    /// Reformatting a signed body, changing signed timestamp bytes or using another key fails authentication.
    /// - Throws: Unexpected setup errors fail the test; every tampered request is rejected.
    @Test func tamperingAndWrongKeys() async throws {
        let body = Data(#"{"type":1}"#.utf8), verifier = try Self.verifier()
        let headers = try Self.headers(body)
        await #expect(throws: SignedIngressFailure.invalidSignature) {
            try await verifier.verify(headers: headers, body: body + Data([32]))
        }
        await #expect(throws: SignedIngressFailure.invalidSignature) {
            try await verifier.verify(headers: [headers[0], HTTPHeader(name: headers[1].name, value: "1001")], body: body)
        }
        let other = Curve25519.Signing.PrivateKey()
        let wrong = try SignedRequestVerifier(publicKey: Self.hex(other.publicKey.rawRepresentation), now: { 1000 })
        await #expect(throws: SignedIngressFailure.invalidSignature) { try await wrong.verify(headers: headers, body: body) }
        #expect(await verifier.replayEntryCount() == 0)
    }

    /// Missing, duplicate, whitespace, nonhex, Unicode and overflowing fields never reach signature verification.
    /// - Parameter value: Malformed signature/timestamp representation.
    /// - Throws: Unexpected fixture errors fail the test.
    @Test(arguments: ["", " ", "-1", "+1000", "1.0", "1000 ", "١٠٠٠", "9223372036854775808"])
    func malformedTimestamp(value: String) async throws {
        let verifier = try Self.verifier(), body = Data()
        let signed = try Self.headers(body)
        await #expect(throws: SignedIngressFailure.malformedHeaders) {
            try await verifier.verify(headers: [signed[0], HTTPHeader(name: signed[1].name, value: value)], body: body)
        }
    }

    /// Cardinality checks reject ambiguous signature headers, and key/policy errors fail at construction.
    /// - Throws: Unexpected fixture errors fail the test.
    @Test func malformedHeadersAndConfiguration() async throws {
        let body = Data(), verifier = try Self.verifier(), fields = try Self.headers(body)
        for invalid in [[], [fields[0]], [fields[1]], fields + [fields[0]], fields + [fields[1]],
                        [HTTPHeader(name: fields[0].name, value: String(repeating: "z", count: 128)), fields[1]],
                        [HTTPHeader(name: fields[0].name, value: "00"), fields[1]]] {
            await #expect(throws: SignedIngressFailure.malformedHeaders) { try await verifier.verify(headers: invalid, body: body) }
        }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: "00") }
        let key = try Self.hex(Self.key().publicKey.rawRepresentation)
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: key, maximumBodyBytes: 0) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: key, maximumAgeSeconds: -1) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: key, maximumFutureSkewSeconds: 86401) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: key, maximumReplayEntries: 0) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try DiscordSignedIngress(verifier: verifier, maximumConcurrentRequests: 0) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try DiscordSignedIngress(verifier: verifier, maximumBodyBytes: 0) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try DiscordSignedIngress(verifier: verifier, maximumHeaderBytes: 0) }
    }

    /// Oversized direct key/signature input fails the fixed-length check before allocating decoded byte arrays.
    /// Unicode with a superficially plausible character count also fails exact ASCII hexadecimal validation.
    /// - Throws: Unexpected synthetic signing/configuration errors fail the test.
    @Test func oversizedDirectHexInput() async throws {
        let huge = String(repeating: "0", count: 1_048_576)
        #expect(throws: SignedIngressFailure.invalidConfiguration) { try SignedRequestVerifier(publicKey: huge) }
        #expect(throws: SignedIngressFailure.invalidConfiguration) {
            try SignedRequestVerifier(publicKey: String(repeating: "é", count: 32))
        }
        let verifier = try Self.verifier(), body = Data(), fields = try Self.headers(body)
        for signature in [huge, String(repeating: "é", count: 64)] {
            await #expect(throws: SignedIngressFailure.malformedHeaders) {
                try await verifier.verify(headers: [HTTPHeader(name: fields[0].name, value: signature), fields[1]], body: body)
            }
        }
        #expect(await verifier.replayEntryCount() == 0)
        #expect(try await verifier.verify(headers: fields, body: body).rawBody.isEmpty)
    }

    /// Uppercase A-F key/signature nibbles authenticate identically to lowercase bytes, while an
    /// invalid low nibble rejects before replay insertion or any partial decoded value is accepted.
    /// - Throws: Unexpected synthetic signing or valid uppercase authentication errors fail the test.
    @Test func uppercaseHexAndInvalidLowNibble() async throws {
        let publicKey = try Self.hex(Self.key().publicKey.rawRepresentation).uppercased()
        let verifier = try SignedRequestVerifier(publicKey: publicKey, now: { 1_000 })
        let body = Data("uppercase".utf8), original = try Self.headers(body)
        let signature = original[0].value.uppercased()
        #expect(publicKey.utf8.contains(where: { (65...70).contains($0) }))
        #expect(signature.utf8.contains(where: { (65...70).contains($0) }))
        let fields = [HTTPHeader(name: original[0].name, value: signature), original[1]]
        #expect(try await verifier.verify(headers: fields, body: body).rawBody == body)
        let invalidSignature = "0z" + signature.dropFirst(2)
        await #expect(throws: SignedIngressFailure.malformedHeaders) {
            try await verifier.verify(headers: [HTTPHeader(name: original[0].name, value: invalidSignature), original[1]], body: body)
        }
        #expect(throws: SignedIngressFailure.invalidConfiguration) {
            try SignedRequestVerifier(publicKey: "0z" + publicKey.dropFirst(2))
        }
        #expect(await verifier.replayEntryCount() == 1)
    }

    /// Timestamp edges are inclusive; extremely old/new values fail without arithmetic overflow.
    /// - Parameter timestamp: Signed test timestamp relative to fixed now=1000.
    /// - Throws: Unexpected signature errors fail accepted boundary cases.
    @Test(arguments: ["0", "699", "700", "1000", "1030", "1031", "9223372036854775807"])
    func timestampBoundaries(timestamp: String) async throws {
        let verifier = try Self.verifier(), body = Data(), headers = try Self.headers(body, timestamp: timestamp)
        if ["700", "1000", "1030"].contains(timestamp) {
            #expect(try await verifier.verify(headers: headers, body: body).timestamp == Int64(timestamp))
        } else {
            await #expect(throws: SignedIngressFailure.staleTimestamp) { try await verifier.verify(headers: headers, body: body) }
        }
        let invalidClock = try Self.verifier(now: { -1 })
        await #expect(throws: SignedIngressFailure.staleTimestamp) { try await invalidClock.verify(headers: headers, body: body) }
    }

    /// Reject mode fails closed at capacity; retry mode identifies retries and bounds its advisory window.
    /// - Throws: Unexpected fixture or authentication errors fail the test.
    @Test func boundedReplayPolicies() async throws {
        let one = Data([1]), two = Data([2]), strict = try Self.verifier(cap: 1)
        let firstHeaders = try Self.headers(one)
        _ = try await strict.verify(headers: firstHeaders, body: one)
        await #expect(throws: SignedIngressFailure.replay) { try await strict.verify(headers: firstHeaders, body: one) }
        await #expect(throws: SignedIngressFailure.replayCapacity) { try await strict.verify(headers: Self.headers(two), body: two) }
        let retries = try Self.verifier(.allowIdenticalRetries, cap: 1)
        #expect(!(try await retries.verify(headers: firstHeaders, body: one)).isReplay)
        #expect(try await retries.verify(headers: firstHeaders, body: one).isReplay)
        _ = try await retries.verify(headers: Self.headers(two), body: two)
        #expect(await retries.replayEntryCount() == 1)
        #expect(!(try await retries.verify(headers: firstHeaders, body: one)).isReplay)
    }

    /// Advancing virtual wall time prunes stale entries and recovers capacity without sleeps.
    /// - Throws: Unexpected clock/authentication errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func replayExpiry() async throws {
        let clock = ManualClock(), verifier = try Self.verifier(cap: 1, now: { 1000 + clock.now.offset.components.seconds })
        let bytes = Data()
        _ = try await verifier.verify(headers: Self.headers(bytes), body: bytes)
        try clock.advance(by: .seconds(301))
        _ = try await verifier.verify(headers: Self.headers(bytes, timestamp: "1301"), body: bytes)
        #expect(await verifier.replayEntryCount() == 1)
        let bounded = try SignedRequestVerifier(publicKey: Self.hex(Self.key().publicKey.rawRepresentation), maximumBodyBytes: 1)
        await #expect(throws: SignedIngressFailure.bodyTooLarge) { try await bounded.verify(headers: [], body: Data([1, 2])) }
    }

    /// Makes a single-use request body through the production request-body materializer.
    /// - Parameters:
    ///   - data: Original bytes supplied to the stream.
    ///   - fields: Original signature/header fields.
    ///   - method: Incoming HTTP method, default POST.
    /// - Returns: Unexecuted local fixture request; caller owns body closure.
    /// - Throws: Request/body materialization errors.
    static func request(_ data: Data, fields: [HTTPHeader], method: String = "POST") throws -> HTTPRequest {
        let body = try RequestBody(bytes: data, contentType: "application/json").makeStream()
        return HTTPRequest(method: method, url: URL(string: "https://example.test/interactions")!, headers: fields, body: body)
    }

    /// Authentication precedes handler dispatch; method/size/header/error paths release admission and streams.
    /// - Throws: Unexpected setup or transport errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ingressStatusesAndDispatch() async throws {
        let body = Data(#"{"type":1}"#.utf8), context = TransportContext(clock: ManualClock())
        let ingress = try DiscordSignedIngress(verifier: Self.verifier(.allowIdenticalRetries), maximumBodyBytes: 100)
        let response = try await ingress.process(request: Self.request(body, fields: Self.headers(body)), context: context) { verified in
            #expect(verified.rawBody == body)
            return HTTPResponse(status: 204)
        }
        #expect(response.status == 204)
        let invalid = try await ingress.process(request: Self.request(body, fields: []), context: context) { _ in
            Issue.record("Unauthenticated handler invoked"); return HTTPResponse(status: 204)
        }
        #expect(invalid.status == 401)
        let wrongMethod = try await ingress.process(request: Self.request(body, fields: [], method: "GET"), context: context) { _ in HTTPResponse(status: 204) }
        #expect(wrongMethod.status == 405)
        let large = try await ingress.process(request: Self.request(Data(repeating: 0, count: 101), fields: []), context: context) { _ in HTTPResponse(status: 204) }
        #expect(large.status == 413)
        let headerLimit = try DiscordSignedIngress(verifier: Self.verifier(), maximumHeaderBytes: 1)
        let bigHeader = try await headerLimit.process(request: Self.request(body, fields: Self.headers(body)), context: context) { _ in HTTPResponse(status: 204) }
        #expect(bigHeader.status == 431)
        let failed = try await ingress.process(request: Self.request(body, fields: Self.headers(body)), context: context) { _ in throw TestSupportFailure.scripted("private") }
        #expect(failed.status == 500)
        #expect(await ingress.activeRequestCount() == 0)
    }

    /// One suspended handler saturates the finite admission budget; cancellation returns it to zero.
    /// - Throws: Unexpected setup, cancellation or synchronization errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func overloadCancellationAndExchange() async throws {
        let body = Data(), context = TransportContext(clock: ManualClock()), entered = TestBarrier(), gate = TestBarrier()
        let ingress = try DiscordSignedIngress(verifier: Self.verifier(.allowIdenticalRetries), maximumConcurrentRequests: 1)
        let firstRequest = try Self.request(body, fields: Self.headers(body))
        let task = Task {
            try await ingress.process(request: firstRequest, context: context) { _ in
                entered.open(); try await gate.wait(); return HTTPResponse(status: 204)
            }
        }
        try await entered.wait()
        #expect(await ingress.activeRequestCount() == 1)
        let refusal = try await ingress.process(request: Self.request(body, fields: Self.headers(body)), context: context) { _ in HTTPResponse(status: 204) }
        #expect(refusal.status == 503)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await ingress.activeRequestCount() == 0)
        let responder = ScriptedHTTPResponder { response in #expect(response.status == 204) }
        try await ingress.handle(HTTPExchange(request: Self.request(body, fields: Self.headers(body)), responder: responder), context: context) { _ in HTTPResponse(status: 204) }
        #expect(await responder.completionCount == 1)
        let failing = ScriptedHTTPResponder { _ in throw TestSupportFailure.scripted("failure") }
        await #expect(throws: TestSupportFailure.self) {
            try await ingress.handle(HTTPExchange(request: Self.request(body, fields: Self.headers(body)), responder: failing), context: context) { _ in HTTPResponse(status: 204) }
        }
        #expect(await failing.reservationCount == 1)
    }

    /// A handler deliberately returns an owned body after observing cancellation, reproducing a result
    /// discarded by TransportContext.run. Both cancellation and virtual deadline races must await closure.
    /// - Parameter deadline: True expires virtual time; false cancels the caller without a configured deadline.
    /// - Throws: Unexpected setup or synchronization failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func lateHandlerResponseCleanup(deadline: Bool) async throws {
        let clock = ManualClock(), entered = TestBarrier(), blocked = TestBarrier()
        let context = TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(3)) : nil)
        let requestResources = ResourceCounter(), responseResources = ResourceCounter()
        let requestBody = try await Self.trackedEmptyBody(requestResources)
        let responseBody = try await Self.trackedEmptyBody(responseResources)
        let ingress = try DiscordSignedIngress(verifier: Self.verifier())
        let request = HTTPRequest(method: "POST", url: URL(string: "https://example.test/interactions")!,
            headers: try Self.headers(Data()), body: requestBody)
        let task = Task {
            try await ingress.process(request: request, context: context) { _ in
                entered.open()
                do { try await blocked.wait() } catch is CancellationError { /* Deliberately finish late. */ }
                return HTTPResponse(status: 200, body: responseBody)
            }
        }
        try await entered.wait()
        #expect(await requestResources.snapshot().live == 0)
        #expect(await responseResources.snapshot().live == 1)
        if deadline {
            try clock.advance(by: .seconds(3))
            await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        } else {
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(await requestResources.snapshot().released == 1)
        #expect(await responseResources.snapshot().released == 1)
        #expect(await responseResources.snapshot().live == 0)
        #expect(await ingress.activeRequestCount() == 0)
        #expect(clock.pendingSleepCount == 0 && blocked.waitingCount == 0)
    }

    /// Successful process transfer leaves a response body open for the caller, while responder failure
    /// closes the transferred body exactly once. Request-body cleanup occurs before either handler runs.
    /// - Throws: Unexpected setup, processing or resource-cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func responseOwnershipTransferAndFailedTransmission() async throws {
        let requestResources = ResourceCounter(), responseResources = ResourceCounter()
        let context = TransportContext(clock: ManualClock())
        let ingress = try DiscordSignedIngress(verifier: Self.verifier(.allowIdenticalRetries))
        let requestBody = try await Self.trackedEmptyBody(requestResources)
        let responseBody = try await Self.trackedEmptyBody(responseResources)
        let request = HTTPRequest(method: "POST", url: URL(string: "https://example.test/interactions")!,
            headers: try Self.headers(Data()), body: requestBody)
        let response = try await ingress.process(request: request, context: context) { _ in
            #expect(await requestResources.snapshot().live == 0)
            return HTTPResponse(status: 200, body: responseBody)
        }
        #expect(response.status == 200)
        #expect(await responseResources.snapshot().live == 1)
        await response.body?.close()
        await response.body?.close()
        #expect(await responseResources.snapshot().released == 1)
        let secondRequestBody = try await Self.trackedEmptyBody(requestResources)
        let secondResponseBody = try await Self.trackedEmptyBody(responseResources)
        let secondRequest = HTTPRequest(method: "POST", url: URL(string: "https://example.test/interactions")!,
            headers: try Self.headers(Data()), body: secondRequestBody)
        let responder = ScriptedHTTPResponder { _ in throw TestSupportFailure.scripted("transmission") }
        await #expect(throws: TestSupportFailure.self) {
            try await ingress.handle(HTTPExchange(request: secondRequest, responder: responder), context: context) { _ in
                return HTTPResponse(status: 200, body: secondResponseBody)
            }
        }
        #expect(await requestResources.snapshot().released == 2)
        #expect(await responseResources.snapshot().released == 2)
        #expect(await responseResources.snapshot().live == 0)
        #expect(await responder.reservationCount == 1)
        #expect(await ingress.activeRequestCount() == 0)
    }

    /// Once signature verification succeeds, handler errors stay application failures even when they
    /// reuse authentication/admission error types; request ownership and admission always release.
    /// - Parameter failure: Every SignedIngressFailure case thrown by an already authenticated handler.
    /// - Throws: Unexpected signing/body/configuration errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [SignedIngressFailure.invalidConfiguration, .malformedHeaders, .invalidSignature,
        .staleTimestamp, .replay, .replayCapacity, .bodyTooLarge])
    func authenticatedHandlerFailureClassification(failure: SignedIngressFailure) async throws {
        let resources = ResourceCounter()
        let body = try await Self.trackedEmptyBody(resources)
        let request = HTTPRequest(method: "POST", url: URL(string: "https://example.test/interactions")!,
            headers: try Self.headers(Data()), body: body)
        let ingress = try DiscordSignedIngress(verifier: Self.verifier())
        let response = try await ingress.process(request: request, context: TransportContext(clock: ManualClock())) { _ in
            throw failure
        }
        #expect(response.status == 500 && response.body == nil)
        #expect(await resources.snapshot().released == 1)
        #expect(await resources.snapshot().live == 0)
        #expect(await ingress.activeRequestCount() == 0)
    }

    /// Creates an empty single-consumer body with explicit resource accounting on EOF or close.
    /// - Parameter counter: Per-test resource owner; each call records one acquisition and one eventual release.
    /// - Returns: A fresh body whose cleanup is idempotent across all copies and cancellation paths.
    /// - Throws: BodyStream configuration errors; the constant one-byte chunk bound is valid.
    static func trackedEmptyBody(_ counter: ResourceCounter) async throws -> BodyStream {
        let lease = await counter.acquire()
        return try BodyStream(maximumChunkBytes: 1, next: { nil }, close: { await lease.release() })
    }
}
