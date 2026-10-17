import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exercises sticker-specific form framing, independent bounds, replay and redaction without I/O.
@Suite struct StickerUploadTests {
    /// Every supported media label preserves bytes and exposes only redacted diagnostic state.
    /// - Parameter contentType: Every PNG/APNG/GIF/Lottie content label accepted by the helper.
    /// - Throws: Unexpected attachment/form construction failures fail the test.
    @Test(arguments: ["image/png", "image/apng", "image/gif", "application/json"])
    func supportedFile(contentType: String) throws {
        let bytes = Data([0, 255, 13, 10])
        let file = try StickerUploadFile(filename: "sticker.asset", contentType: contentType, bytes: bytes)
        #expect(file.filename == "sticker.asset" && file.contentType == contentType && file.bytes == bytes)
        #expect(String(describing: file) == "StickerUploadFile(redacted)")
        #expect(String(reflecting: file) == "StickerUploadFile(redacted)")
        #expect(Mirror(reflecting: file).children.count == 1)
    }

    /// Four direct form fields, UTF-8, empty descriptions and independent replay retain exact framing.
    /// Closing an unused attempt does not consume the immutable source for later attempts.
    /// - Throws: Unexpected body/stream failures fail the test.
    @Test func framingReplayAndOwnership() async throws {
        let file = try StickerUploadFile(filename: "wave.png", contentType: "image/png", bytes: Data([0, 255]))
        let body = try StickerUpload.body(name: "波形", description: "", tags: "👋", file: file, boundary: "edge")
        var expected = Data(["--edge\r\nContent-Disposition: form-data; name=\"name\"\r\n",
            "Content-Type: text/plain; charset=utf-8\r\n\r\n波形\r\n",
            "--edge\r\nContent-Disposition: form-data; name=\"description\"\r\n",
            "Content-Type: text/plain; charset=utf-8\r\n\r\n\r\n",
            "--edge\r\nContent-Disposition: form-data; name=\"tags\"\r\n",
            "Content-Type: text/plain; charset=utf-8\r\n\r\n👋\r\n",
            "--edge\r\nContent-Disposition: form-data; name=\"file\"; filename=\"wave.png\"\r\n",
            "Content-Type: image/png\r\n\r\n"].joined().utf8)
        expected.append(file.bytes); expected.append(Data("\r\n--edge--\r\n".utf8))
        #expect(body.bytes == expected && body.storedBodyBytes == expected)
        #expect(body.accountedBytes == expected.count && !body.isStreaming)
        #expect(body.contentType == "multipart/form-data; boundary=edge")
        let unused = try body.makeStream(); await unused.close(); await unused.close()
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: expected.count) == expected)
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: expected.count) == expected)
        #expect(try StickerUpload.body(name: "波形", description: "", tags: "👋", file: file,
            maximumRequestBytes: expected.count, boundary: "edge").bytes == expected)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try StickerUpload.body(name: "波形", description: "", tags: "👋", file: file,
                maximumRequestBytes: expected.count - 1, boundary: "edge")
        }
    }

    /// The documented 512-KiB attachment limit is independent of whole-form overhead and metadata bounds.
    /// - Throws: Unexpected construction errors fail the test; limit failures are asserted explicitly.
    @Test func fileAndWholeRequestBounds() throws {
        let file = try StickerUploadFile(filename: "x", contentType: "image/gif", bytes: Data(repeating: 7, count: 524_288))
        let body = try StickerUpload.body(name: String(repeating: "界", count: 30),
            description: String(repeating: "界", count: 100), tags: String(repeating: "界", count: 200), file: file)
        #expect(body.accountedBytes > file.bytes.count && body.accountedBytes < 1_048_576)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try StickerUploadFile(filename: "x", contentType: "image/png", bytes: Data(repeating: 7, count: 524_289))
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try StickerUpload.body(name: "ok", description: "", tags: "", file: file, maximumRequestBytes: 524_288)
        }
        #expect(try StickerUploadFile(filename: String(repeating: "x", count: 1_024), contentType: "image/png", bytes: Data([1])).filename.count == 1_024)
    }

    /// Empty files, header injection, unsupported representations and excessive local filename metadata fail eagerly.
    /// - Throws: Unexpected setup errors fail the test; every invalid value must throw a safe error.
    @Test func invalidFiles() throws {
        for filename in ["", "a\r\nb", "a\"b", "a\\b", String(repeating: "x", count: 1_025)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try StickerUploadFile(filename: filename, contentType: "image/png", bytes: Data([1]))
            }
        }
        for type in ["", "text/plain", "image/jpeg", "image/png\r\nx", "IMAGE/PNG"] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try StickerUploadFile(filename: "x", contentType: type, bytes: Data([1]))
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try StickerUploadFile(filename: "x", contentType: "image/png", bytes: Data())
        }
    }

    /// Invalid text lengths, aggregate caps and boundary collisions are rejected before submission.
    /// - Throws: Unexpected setup errors fail the test; malformed body inputs are explicitly asserted.
    @Test func invalidFieldsAndBoundaries() throws {
        let file = try StickerUploadFile(filename: "x", contentType: "application/json", bytes: Data("collision".utf8))
        for name in ["", "a", String(repeating: "a", count: 31)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StickerUpload.body(name: name, description: "", tags: "", file: file) }
        }
        for description in ["a", String(repeating: "a", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StickerUpload.body(name: "ok", description: description, tags: "", file: file) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try StickerUpload.body(name: "ok", description: "", tags: String(repeating: "a", count: 201), file: file)
        }
        for cap in [0, -1, 1_048_577, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StickerUpload.body(name: "ok", description: "", tags: "", file: file, maximumRequestBytes: cap) }
        }
        for boundary in ["", "bad boundary", "\r\n", "💥", String(repeating: "a", count: 71), "collision", "ok"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StickerUpload.body(name: "ok", description: "", tags: "", file: file, boundary: boundary) }
        }
    }

    /// Cancelling a fresh materialized attempt releases its cursor and leaves later attempts replayable.
    /// - Throws: Unexpected setup or uncancelled replay failures fail the test.
    @Test func cancelledAttempt() async throws {
        let file = try StickerUploadFile(filename: "x", contentType: "image/png", bytes: Data([1]))
        let body = try StickerUpload.body(name: "ok", description: "", tags: "", file: file)
        let stream = try body.makeStream()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = stream.makeAsyncIterator()
            await #expect(throws: CancellationError.self) { try await iterator.next() }
        }
        await task.value
        await stream.close()
        #expect(try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes) == body.bytes)
    }
}
