import DiscordCore
import Foundation

/// One bounded, immutable guild sticker attachment for API v10 multipart creation.
/// The value opens no files and retains no producers; every transmission uses independent body state.
/// Media labels do not prove image dimensions, animation duration or Lottie guild eligibility.
public struct StickerUploadFile: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Header-safe display filename; no local path is opened or interpreted.
    public let filename: String
    /// Explicit PNG/APNG/GIF/Lottie representation label.
    public let contentType: String
    /// Complete retained attachment, independently bounded to 512 KiB.
    public let bytes: Data

    /// Validates an attachment before any request is constructed or submitted.
    /// - Parameters:
    ///   - filename: Nonempty name of at most 1,024 UTF-8 bytes, a local metadata bound. Controls,
    ///     quotes and backslashes are rejected to prevent multipart header injection.
    ///   - contentType: Exactly `image/png`, `image/apng`, `image/gif` or `application/json`.
    ///     APNG may also use `image/png`; Lottie uses `application/json`.
    ///   - bytes: Nonempty complete file data, at most the documented 524,288-byte sticker limit.
    /// - Throws: `DiscordError.validation(.invalidValue)` for empty content or unsupported/unsafe
    ///   metadata; `.limitExceeded` for an oversized file. Validation is synchronous and performs
    ///   no media decoding. Discord still checks the 320-by-320 dimensions, five-second animation
    ///   duration and VERIFIED/PARTNERED Lottie restriction at execution.
    public init(filename: String, contentType: String, bytes: Data) throws {
        guard !filename.isEmpty, filename.utf8.count <= 1_024, !bytes.isEmpty,
              ["image/png", "image/apng", "image/gif", "application/json"].contains(contentType)
        else { throw DiscordError.validation(.invalidValue) }
        guard bytes.count <= 512 * 1_024 else { throw DiscordError.validation(.limitExceeded) }
        _ = try MultipartPart(name: "file", filename: filename, contentType: contentType, bytes: bytes)
        self.filename = filename; self.contentType = contentType; self.bytes = bytes
    }

    /// Conceals retained names, media metadata and content during ordinary formatting.
    public var description: String { "StickerUploadFile(redacted)" }
    /// Uses the same safe representation during debug formatting.
    public var debugDescription: String { description }
    /// Hides attachment content and metadata from automatic reflection.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Builds the four named form parts required by Create Guild Sticker, independently of Gateway/voice.
/// See the [official sticker reference](https://docs.discord.com/developers/resources/sticker#create-guild-sticker).
public enum StickerUpload {
    /// Creates a bounded replayable multipart body without network activity, tasks or open resources.
    /// - Parameters:
    ///   - name: Sticker name, 2...30 Unicode scalars. The reference says characters without defining
    ///     a Unicode counting unit; this library consistently uses scalars for outgoing validation.
    ///   - description: Required description form field, either empty or 2...100 Unicode scalars.
    ///   - tags: Required suggestion text, at most 200 Unicode scalars; empty is not locally forbidden.
    ///   - file: Independently validated nonempty PNG/APNG/GIF/Lottie attachment of at most 512 KiB.
    ///   - maximumRequestBytes: Positive local whole-body cap, at most 1 MiB and defaulting to 1 MiB.
    ///     Includes every field, filename and boundary byte; it is separate from Discord's file cap.
    ///   - boundary: One retained ASCII multipart boundary, 1...70 letters/digits/dashes/underscores;
    ///     defaults to a fresh UUID. Any collision in text or file content fails before submission.
    /// - Returns: Materialized body with `name`, `description`, `tags`, and `file` parts. Its exact
    ///   retained size is reserved by HTTP scheduling. Fresh streams can be replayed independently;
    ///   replayability does not make sticker creation safe after an ambiguous mutation outcome.
    /// - Throws: Safe invalid-value errors for malformed fields/bounds/boundaries or collisions;
    ///   `.limitExceeded` when complete multipart framing exceeds the requested cap. No server
    ///   capacity, permissions, guild feature, media dimension or duration checks occur here.
    public static func body(name: String, description: String, tags: String, file: StickerUploadFile,
                            maximumRequestBytes: Int = 1_048_576,
                            boundary: String = "DiscordKitSticker-" + UUID().uuidString) throws -> RequestBody {
        guard (2...30).contains(name.unicodeScalars.count),
              description.isEmpty || (2...100).contains(description.unicodeScalars.count),
              tags.unicodeScalars.count <= 200, (1...1_048_576).contains(maximumRequestBytes)
        else { throw DiscordError.validation(.invalidValue) }
        return try RequestBody.multipart([
            MultipartPart(name: "name", contentType: "text/plain; charset=utf-8", bytes: Data(name.utf8)),
            MultipartPart(name: "description", contentType: "text/plain; charset=utf-8", bytes: Data(description.utf8)),
            MultipartPart(name: "tags", contentType: "text/plain; charset=utf-8", bytes: Data(tags.utf8)),
            MultipartPart(name: "file", filename: file.filename, contentType: file.contentType, bytes: file.bytes),
        ], boundary: boundary, maximumBytes: maximumRequestBytes)
    }
}
