import DiscordCertifiedDevices
import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Local deterministic publication fixtures; no Discord process, network or credentials are used.
@Suite("Certified Devices HTTP publication")
struct CertifiedDeviceHTTPPublisherTests {
    /// Uses a fixed loopback v1 POST and replaces whole arrays without retaining old devices.
    /// Highest-priority-first order, a shared cross-type ID, and empty clearing survive encoding.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func fullReplacementAndEndpoint() async throws {
        let first = try certifiedDevice("First")
        let second = try certifiedDevice("First", type: .audioOutput)
        let expected: [[CertifiedDevice]] = [[first, second], [second], []]
        let transport = try ScriptedHTTPTransport(steps: expected.enumerated().map { index, devices in
            { request in
                #expect(request.method == "POST")
                #expect(request.url.absoluteString == "http://127.0.0.1:6473/rpc?v=1&client_id=18446744073709551615")
                #expect(request.headers.count == 1)
                #expect(request.headers.first?.name == "Content-Type")
                #expect(request.headers.first?.value == "application/json")
                let bytes = try await collectCertifiedBody(request.body)
                let object = try JSONValue.parse(bytes)
                #expect(object == .object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string("n\(index)"),
                    "args": .object(["devices": .array(devices.map(\.jsonValue))])]))
                return try await certifiedAcknowledgement("n\(index)")
            }
        })
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "18446744073709551615", port: 6473, transport: transport)
        #expect(await transport.executionCount == 0)
        for (index, devices) in expected.enumerated() {
            try await publisher.publish(devices, nonce: "n\(index)", context: TransportContext(clock: ManualClock()))
        }
        #expect(await transport.executionCount == 3)
        await publisher.close()
        await publisher.close()
        await #expect(throws: CertifiedDeviceFailure.closed) {
            try await publisher.publish([], context: TransportContext(clock: ManualClock()))
        }
    }

    /// Rejects endpoint and resource-policy errors before an injected transport can execute.
    @Test func configurationValidation() throws {
        let transport = try ScriptedHTTPTransport(steps: [])
        for id in ["", "0", "-1", "+1", " 1", "1&v=2", "18446744073709551616", String(repeating: "1", count: 21)] {
            #expect(throws: CertifiedDeviceFailure.invalidClientID) {
                try CertifiedDeviceHTTPPublisher(clientID: id, port: 6463, transport: transport)
            }
        }
        for port in [Int.min, 0, 6462, 6474, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidPort) {
                try CertifiedDeviceHTTPPublisher(clientID: "1", port: port, transport: transport)
            }
        }
        for value in [Int.min, 0, 1_025, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport, maximumDevices: value)
            }
        }
        for value in [Int.min, 0, 1_048_577, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport, maximumRequestBytes: value)
            }
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport, maximumResponseBytes: value)
            }
        }
        #expect(CertifiedDeviceHTTPPublisher.documentedPorts == 6463...6473)
        _ = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport,
            maximumDevices: 1_024, maximumRequestBytes: 1_048_576, maximumResponseBytes: 1_048_576)
    }

    /// Bounds array identities, serialized bytes and nonces before any transmission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func admissionValidation() async throws {
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport, maximumDevices: 2)
        let input = try certifiedDevice()
        await #expect(throws: CertifiedDeviceFailure.tooManyDevices) {
            try await publisher.publish([input, input, input], context: context)
        }
        await #expect(throws: CertifiedDeviceFailure.duplicateDevice) {
            try await publisher.publish([input, input], context: context)
        }
        for nonce in ["", " ", "bad\n", String(repeating: "a", count: 129)] {
            await #expect(throws: CertifiedDeviceFailure.invalidNonce) {
                try await publisher.publish([], nonce: nonce, context: context)
            }
        }
        let tiny = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport, maximumRequestBytes: 1)
        await #expect(throws: JSONValueError.maximumBytesExceeded) {
            try await tiny.publish([], context: context)
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await publisher.publish([], context: TransportContext(clock: clock, deadline: clock.now))
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await publisher.publish([], context: context)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await transport.executionCount == 0)
    }

    /// Rejects status and malformed/mismatched envelopes, always releasing response bodies.
    /// - Parameter variant: A specific invalid acknowledgement shape or status.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["http", "malformed", "wrongNonce", "wrongCommand", "wrongData", "missingEvent", "missingBody", "oversize"])
    func responseFailures(_ variant: String) async throws {
        let counter = ResourceCounter()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            if variant == "missingBody" { return HTTPResponse(status: 200) }
            var object: [String: JSONValue] = ["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string("n"),
                                             "evt": .null, "data": .null]
            if variant == "wrongNonce" { object["nonce"] = .string("other") }
            if variant == "wrongCommand" { object["cmd"] = .string("OTHER") }
            if variant == "wrongData" { object["data"] = .object([:]) }
            if variant == "missingEvent" { object["evt"] = nil }
            let bytes = variant == "malformed" ? Data("{".utf8) : try JSONValue.object(object).serialized()
            return HTTPResponse(status: variant == "http" ? 403 : 200,
                body: try await certifiedResponseBody(bytes, counter: counter))
        }])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport,
            maximumResponseBytes: variant == "oversize" ? 1 : 65_536)
        do {
            try await publisher.publish([], nonce: "n", context: TransportContext(clock: ManualClock()))
            Issue.record("Expected failed acknowledgement")
        } catch {
            switch variant {
            case "http": #expect(error as? CertifiedDeviceFailure == .httpStatus(403))
            case "malformed": #expect(error is JSONValueError)
            case "oversize": #expect(error as? CertifiedDeviceFailure == .responseTooLarge)
            default: #expect(error as? CertifiedDeviceFailure == .invalidResponse)
            }
        }
        #expect(await transport.executionCount == 1)
        let snapshot = await counter.snapshot()
        #expect(snapshot.live == 0)
        #expect(snapshot.released == (variant == "missingBody" ? 0 : 1))
    }

    /// Returns access/approval errors by numeric code and discards sensitive desktop text.
    /// - Parameter code: Documented unauthenticated/error payload code, or an unknown future code.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [4006, 4000, 9999])
    func remoteAccessFailures(_ code: Int) async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            let object: JSONValue = .object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string("n"),
                "evt": .string("ERROR"), "data": .object(["code": .number(try JSONNumber(rawValue: String(code))),
                                                          "message": .string("sentinel-secret")])])
            return HTTPResponse(status: 200, body: try await certifiedResponseBody(object.serialized()))
        }])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport)
        await #expect(throws: CertifiedDeviceFailure.remoteError(code: code)) {
            try await publisher.publish([], nonce: "n", context: TransportContext(clock: ManualClock()))
        }
        #expect(!String(reflecting: CertifiedDeviceFailure.remoteError(code: code)).contains("sentinel-secret"))
        #expect(await transport.executionCount == 1)
    }

    /// Sanitizes malformed/future ERROR payloads without retaining server message contents.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func remoteErrorWithoutNumericCode() async throws {
        let values: [JSONValue] = [.null, .object([:]), .object(["code": .string("4006")]),
            .object(["code": .number(try JSONNumber(rawValue: "1e1000"))])]
        for data in values {
            let transport = try ScriptedHTTPTransport(steps: [{ _ in
                let bytes = try JSONValue.object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string("n"),
                    "evt": .string("ERROR"), "data": data]).serialized()
                return HTTPResponse(status: 200, body: try await certifiedResponseBody(bytes))
            }])
            let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport)
            await #expect(throws: CertifiedDeviceFailure.remoteError(code: nil)) {
                try await publisher.publish([], nonce: "n", context: TransportContext(clock: ManualClock()))
            }
        }
    }

    /// Accepts exact aggregate byte limits and rejects response producer failure with cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func byteLimitBoundariesAndBodyFailure() async throws {
        let nonce = String(repeating: "n", count: 128)
        let requestBytes = try JSONValue.object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string(nonce),
            "args": .object(["devices": .array([])])]).serialized()
        let responseBytes = try JSONValue.object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string(nonce),
            "evt": .null, "data": .null]).serialized()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            HTTPResponse(status: 200, body: try await certifiedResponseBody(responseBytes))
        }])
        let exact = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport,
            maximumRequestBytes: requestBytes.count, maximumResponseBytes: responseBytes.count)
        try await exact.publish([], nonce: nonce, context: TransportContext(clock: ManualClock()))
        #expect(await transport.executionCount == 1)

        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let failureBody = try BodyStream(maximumChunkBytes: 1,
            next: { throw TestSupportFailure.scripted("sentinel-body-secret") }, close: { await lease.release() })
        let failing = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200, body: failureBody) }])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: failing)
        await #expect(throws: CertifiedDeviceFailure.transportFailure) {
            try await publisher.publish([], context: TransportContext(clock: ManualClock()))
        }
        #expect(await counter.snapshot().released == 1)
        #expect(await counter.snapshot().live == 0)
        #expect(await failing.executionCount == 1)
    }

    /// Rejects overlapping mutation work, cancels/awaits it on close and never retries.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func closeCancelsPendingAndRejectsOverlap() async throws {
        let entered = TestBarrier()
        let gate = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            entered.open()
            try await gate.wait()
            return HTTPResponse(status: 200)
        }])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport)
        let context = TransportContext(clock: ManualClock())
        let pending = Task { try await publisher.publish([], context: context) }
        try await entered.wait()
        await #expect(throws: CertifiedDeviceFailure.operationInProgress) {
            try await publisher.publish([], context: context)
        }
        await publisher.close()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(gate.waitingCount == 0)
        #expect(await transport.executionCount == 1)
    }

    /// Propagates caller cancellation/deadline during body consumption and closes the source.
    /// - Parameter deadline: Whether cancellation comes from injected time or the caller task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cancellationDuringResponse(_ deadline: Bool) async throws {
        let entered = TestBarrier()
        let gate = TestBarrier()
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 1, next: {
            entered.open()
            try await gate.wait()
            return nil
        }, close: { await lease.release() })
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200, body: body) }])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport)
        let context = TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(10)) : nil)
        let pending = Task { try await publisher.publish([], context: context) }
        try await entered.wait()
        if deadline {
            try await scheduled.wait()
            try clock.advance(by: .seconds(10))
            await #expect(throws: TransportFailure.deadlineExceeded) { try await pending.value }
        } else {
            pending.cancel()
            await #expect(throws: CancellationError.self) { try await pending.value }
        }
        #expect(await counter.snapshot().live == 0)
        #expect(await counter.snapshot().released == 1)
        #expect(clock.pendingSleepCount == 0)
        #expect(gate.waitingCount == 0)
    }

    /// Sanitizes opaque transport failure, permits later fresh state and never retries it.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func transportFailureAndRecovery() async throws {
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in throw TestSupportFailure.scripted("ambiguous") },
            { request in
                let object = try JSONValue.parse(await collectCertifiedBody(request.body))
                guard case .object(let fields) = object, case .string(let nonce) = fields["nonce"] else {
                    throw CertifiedDeviceFailure.invalidResponse
                }
                #expect(!nonce.isEmpty)
                return try await certifiedAcknowledgement(nonce)
            },
        ])
        let publisher = try CertifiedDeviceHTTPPublisher(clientID: "1", port: 6463, transport: transport)
        let context = TransportContext(clock: ManualClock())
        await #expect(throws: CertifiedDeviceFailure.transportFailure) { try await publisher.publish([], context: context) }
        #expect(await transport.executionCount == 1)
        try await publisher.publish([], context: context)
        #expect(await transport.executionCount == 2)
    }
}

/// Collects a fixture request under its production stream's ownership contract.
/// - Parameter body: Optional body that is consumed through EOF and closed on failure.
/// - Returns: Concatenated fixture bytes, or empty when no body exists.
/// - Throws: Body producer, cancellation or chunk-limit failures.
func collectCertifiedBody(_ body: BodyStream?) async throws -> Data {
    guard let body else { return Data() }
    do {
        var bytes = Data()
        for try await chunk in body { bytes.append(chunk) }
        return bytes
    } catch {
        await body.close()
        throw error
    }
}

/// Produces a valid correlated null acknowledgement without contacting Discord.
/// - Parameter nonce: Exact nonce expected by the publication under test.
/// - Returns: A 200 response with a finite single-chunk JSON body.
/// - Throws: Serialization or body-construction failures.
func certifiedAcknowledgement(_ nonce: String) async throws -> HTTPResponse {
    let bytes = try JSONValue.object(["cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string(nonce),
                                     "evt": .null, "data": .null, "future": .bool(true)]).serialized()
    return HTTPResponse(status: 200, body: try await certifiedResponseBody(bytes))
}

/// Creates a finite one-chunk fixture body with optional exactly-once resource accounting.
/// - Parameters:
///   - bytes: Complete response bytes, including malformed-response fixtures.
///   - counter: Optional per-test resource counter whose lease is released on close/EOF.
/// - Returns: A single-consumer body that yields bytes once, then EOF.
/// - Throws: Body limit validation errors.
func certifiedResponseBody(_ bytes: Data, counter: ResourceCounter? = nil) async throws -> BodyStream {
    let source = CertifiedResponseSource(bytes)
    let lease = await counter?.acquire()
    return try BodyStream(maximumChunkBytes: max(1, bytes.count), next: { await source.next() },
        close: { await lease?.release() })
}

/// Actor-owned single-chunk fixture storage prevents races between body reads.
actor CertifiedResponseSource {
    var bytes: Data?

    /// Stores one fixture response chunk without producing it yet.
    /// - Parameter bytes: Body bytes returned on the first pull.
    init(_ bytes: Data) { self.bytes = bytes }

    /// Returns the fixture chunk once, then EOF.
    /// - Returns: Stored bytes, or nil after the first read.
    func next() -> Data? { defer { bytes = nil }; return bytes }
}
