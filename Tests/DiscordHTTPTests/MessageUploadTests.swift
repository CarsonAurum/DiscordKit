// File: Tests/DiscordHTTPTests/MessageUploadTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Checks message upload admission, replay, source ownership and framing without filesystem or network I/O.
@Suite(.timeLimit(.minutes(1))) struct MessageUploadTests {
    /// JSON-only messages retain exact bytes, account their stored size and honor caller byte caps.
    @Test func jsonBodyAndInvalidLimits() throws {
        let payload = JSONValue.object(["content": .string("hello")])
        let bytes = try payload.serialized()
        let body = try MessageUpload.body(payload: payload, limits: .init(maximumRequestBytes: bytes.count))
        #expect(body.storedBodyBytes == bytes)
        #expect(body.accountedBytes == bytes.count)
        #expect(!body.isStreaming)
        #expect(body.contentType == "application/json")
        for limits in [MessageUploadLimits(maximumFileBytes: 0), .init(maximumRequestBytes: 0),
                       .init(maximumRequestBytes: 25 * 1_048_576 + 1), .init(maximumChunkBytes: 0)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUpload.body(payload: payload, limits: limits) }
        }
        #expect(throws: (any Error).self) { try MessageUpload.body(payload: payload, limits: .init(maximumRequestBytes: bytes.count - 1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUpload.body(payload: .array([])) }
    }

    /// Empty files and noncontiguous placeholders preserve exact multipart framing and bounded chunks.
    @Test func materializedFramingAndExactReservation() async throws {
        let payload = JSONValue.object(["content": .string("hi")])
        let files = [try MessageUploadFile(id: 42, filename: "a.txt", contentType: "text/plain", bytes: Data("abc".utf8)),
                     try MessageUploadFile(id: 0, filename: "empty", bytes: Data())]
        let body = try MessageUpload.body(payload: payload, files: files, limits: .init(maximumChunkBytes: 7), boundary: "edge")
        let expected = Data(("--edge\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n" +
            "{\"content\":\"hi\"}\r\n--edge\r\nContent-Disposition: form-data; name=\"files[42]\"; filename=\"a.txt\"\r\n" +
            "Content-Type: text/plain\r\n\r\nabc\r\n--edge\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"empty\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n\r\n--edge--\r\n").utf8)
        #expect(body.isStreaming)
        #expect(body.storedBodyBytes == nil)
        #expect(body.accountedBytes == expected.count)
        var actual = Data()
        for try await chunk in try body.makeStream() { #expect(chunk.count <= 7); actual.append(chunk) }
        #expect(actual == expected)
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: expected.count) == expected)
        let exact = try MessageUpload.body(payload: payload, files: files,
            limits: .init(maximumFileBytes: 3, maximumRequestBytes: expected.count), boundary: "edge")
        #expect(exact.accountedBytes == expected.count)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try MessageUpload.body(payload: payload, files: files,
                limits: .init(maximumFileBytes: 3, maximumRequestBytes: expected.count - 1), boundary: "edge")
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try MessageUpload.body(payload: payload, files: files, limits: .init(maximumFileBytes: 2), boundary: "edge")
        }
        #expect(String(describing: files[0]) == "MessageUploadFile(redacted)")
        #expect(String(reflecting: files[0]) == "MessageUploadFile(redacted)")
        #expect(Mirror(reflecting: files[0]).children.count == 1)
    }

    /// Metadata, placeholder duplication/count and boundary injection fail before a source is opened.
    @Test func invalidMetadataAndBoundaries() throws {
        for name in ["", "a\r\nb", "quote\"", "slash\\"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUploadFile(id: 0, filename: name, bytes: Data()) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUploadFile(id: -1, filename: "x", bytes: Data()) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUploadFile(id: 0, filename: "x", contentType: "a\r\nb", bytes: Data()) }
        let file = try MessageUploadFile(id: 0, filename: "x", bytes: Data())
        for boundary in ["", "bad boundary", "\r\n", String(repeating: "a", count: 71), "💥"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUpload.body(payload: .object([:]), files: [file], boundary: boundary) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUpload.body(payload: .object([:]), files: [file, file]) }
        let many = try (0...10).map { try MessageUploadFile(id: $0, filename: "x", bytes: Data()) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageUpload.body(payload: .object([:]), files: many) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageUpload.body(payload: .object(["content": .string("collision")]), files: [file], boundary: "collision")
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageUploadFile(id: 0, filename: "x", maximumBytes: 0) { try file.makeStreamForTest() }
        }
    }

    /// Fresh factories reopen only when pulled, reserve declared caps and close exactly once at EOF.
    @Test func lazyReplayAndIndependentLimits() async throws {
        let probe = UploadProbe()
        let file = try MessageUploadFile(id: 0, filename: "stream", maximumBytes: 3) {
            let source = UploadSource(chunks: [Data(), Data([1]), Data([2, 3])], probe: probe)
            return try BodyStream(maximumChunkBytes: 2, next: { await source.next() }, close: { await source.close() })
        }
        let body = try MessageUpload.body(payload: .object([:]), files: [file], boundary: "edge")
        #expect(await probe.reads == 0)
        let abandoned = try body.makeStream(); await abandoned.close()
        #expect(await probe.closes == 0)
        let first = try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes)
        #expect(first.count == body.accountedBytes)
        #expect(await probe.closes == 1)
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes) == first)
        #expect(await probe.closes == 2)
        #expect(await probe.reads == 8)
        let tooSmall = try MessageUploadFile(id: 1, filename: "overflow", maximumBytes: 2) {
            let source = UploadSource(chunks: [Data([1, 2, 3])], probe: probe)
            return try BodyStream(maximumChunkBytes: 3, next: { await source.next() }, close: { await source.close() })
        }
        let overflow = try MessageUpload.body(payload: .object([:]), files: [tooSmall], boundary: "edge")
        await #expect(throws: DiscordError.transport(.limitExceeded)) {
            try await ResponseBody.collect(overflow.makeStream(), maximumBytes: overflow.accountedBytes)
        }
        #expect(await probe.closes == 3)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try MessageUpload.body(payload: .object([:]), files: [file], limits: .init(maximumFileBytes: 2))
        }
    }

    /// Boundary detection spans chunk boundaries, and producer/factory errors release only owned resources.
    @Test func sourceFailuresAndSplitBoundary() async throws {
        let probe = UploadProbe()
        let collision = try MessageUploadFile(id: 0, filename: "x", maximumBytes: 5) {
            let source = UploadSource(chunks: [Data("ab".utf8), Data("cde".utf8)], probe: probe)
            return try BodyStream(maximumChunkBytes: 3, next: { await source.next() }, close: { await source.close() })
        }
        let body = try MessageUpload.body(payload: .object([:]), files: [collision], boundary: "bc")
        await #expect(throws: DiscordError.validation(.invalidValue)) { try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes) }
        #expect(await probe.closes == 1)
        let failing = try MessageUploadFile(id: 0, filename: "x", maximumBytes: 3) {
            try BodyStream(maximumChunkBytes: 1, next: { throw TransportFailure.closed }, close: { await probe.closed() })
        }
        let failedBody = try MessageUpload.body(payload: .object([:]), files: [failing], boundary: "edge")
        await #expect(throws: TransportFailure.closed) { try await ResponseBody.collect(failedBody.makeStream(), maximumBytes: failedBody.accountedBytes) }
        #expect(await probe.closes == 2)
        let factoryFailure = try MessageUploadFile(id: 0, filename: "x", maximumBytes: 1) { throw TransportFailure.closed }
        let failedFactoryBody = try MessageUpload.body(payload: .object([:]), files: [factoryFailure], boundary: "edge")
        await #expect(throws: TransportFailure.closed) { try await ResponseBody.collect(failedFactoryBody.makeStream(), maximumBytes: failedFactoryBody.accountedBytes) }
        #expect(await probe.closes == 2)
    }

    /// Cancellation before first pull opens no source; cancellation/close during reads propagates cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndInFlightClose() async throws {
        let entered = TestBarrier(), gate = TestBarrier(), probe = UploadProbe()
        let file = try MessageUploadFile(id: 0, filename: "x", maximumBytes: 1) {
            try BodyStream(maximumChunkBytes: 1, next: {
                entered.open(); try await gate.wait(); return Data([1])
            }, close: { await probe.closed(); gate.open() })
        }
        let body = try MessageUpload.body(payload: .object([:]), files: [file], boundary: "edge")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await probe.closes == 0)
        let active = Task { try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes) }
        try await entered.wait(); active.cancel()
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(await probe.closes == 1)

        let enteredClose = TestBarrier(), gateClose = TestBarrier()
        let delayed = try MessageUploadFile(id: 0, filename: "late", maximumBytes: 1) {
            try BodyStream(maximumChunkBytes: 1, next: {
                enteredClose.open(); try await gateClose.wait(); return Data([9])
            }, close: { await probe.closed(); gateClose.open() })
        }
        let closeBody = try MessageUpload.body(payload: .object([:]), files: [delayed], boundary: "edge")
        let stream = try closeBody.makeStream()
        let reader = Task { try await ResponseBody.collect(stream, maximumBytes: closeBody.accountedBytes) }
        try await enteredClose.wait(); await stream.close()
        let received = try await reader.value
        #expect(!received.contains(9))
        #expect(await probe.closes == 2)
        await stream.close(); #expect(await probe.closes == 2)
    }
}

/// Counts observable source pulls/cleanup without sharing mutable state between tests.
private actor UploadProbe {
    var reads = 0
    var closes = 0
    /// Records one producer pull, including EOF.
    func read() { reads += 1 }
    /// Records cleanup, which BodyStream must invoke exactly once per opened attempt.
    func closed() { closes += 1 }
}

/// Deterministic ordered source that reports demand and cleanup to an isolated probe.
private actor UploadSource {
    var chunks: [Data]
    let probe: UploadProbe
    /// Retains the finite source script for one independent attempt.
    /// - Parameters:
    ///   - chunks: Ordered data, including permitted empty chunks.
    ///   - probe: Per-test read/close observer.
    init(chunks: [Data], probe: UploadProbe) { self.chunks = chunks; self.probe = probe }
    /// Removes one scripted chunk only when the downstream consumer requests it.
    /// - Returns: The next chunk or EOF after exhaustion.
    func next() async -> Data? { await probe.read(); return chunks.isEmpty ? nil : chunks.removeFirst() }
    /// Releases unread chunks and records terminal ownership exactly once through BodyStream.
    func close() async { chunks = []; await probe.closed() }
}

private extension MessageUploadFile {
    /// Creates an empty stream solely for validating the rejected zero-cap factory branch.
    /// - Returns: An empty, independently owned body stream; this factory must never be invoked by the test.
    /// - Throws: Underlying stream-construction validation errors.
    func makeStreamForTest() throws -> BodyStream { try RequestBody(bytes: Data(), contentType: "x").makeStream() }
}
