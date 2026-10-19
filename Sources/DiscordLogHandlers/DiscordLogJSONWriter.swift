import Foundation
import Logging

/// A per-call JSON encoder that fails before retaining more than the configured output bytes.
///
/// Strings are escaped scalar by scalar, preserving Unicode without constructing an
/// unbounded escaped copy. Metadata recursion/count is checked before traversal or
/// sorting. Application-defined `CustomStringConvertible` implementations remain
/// responsible for their own execution/allocation costs.
struct DiscordLogJSONWriter {
    private let configuration: DiscordFileLogConfiguration
    private var data = Data()
    private var metadataValues = 0

    /// Creates an empty bounded serializer without inspecting the record or allocating its maximum capacity.
    /// - Parameter configuration: Limits already validated by the owning sink.
    init(configuration: DiscordFileLogConfiguration) {
        self.configuration = configuration
    }

    /// Encodes the complete stable NDJSON schema and trailing newline.
    /// - Parameter record: Observation whose metadata remains structurally typed in JSON.
    /// - Returns: UTF-8 JSON object plus exactly one newline, within the configured record limit.
    /// - Throws: Sanitized record-byte, metadata or nonfinite-timestamp errors.
    mutating func encode(_ record: DiscordLogRecord) throws -> Data {
        let milliseconds = record.timestamp.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite else { throw DiscordFileLogError.invalidRecord }
        try append("{\"file\":")
        try string(record.file)
        try append(",\"function\":")
        try string(record.function)
        try append(",\"hasError\":\(record.hasError),\"label\":")
        try string(record.label)
        try append(",\"level\":")
        try string(record.level.rawValue)
        try append(",\"line\":\(record.line),\"message\":")
        try string(record.message)
        try append(",\"metadata\":")
        try value(.dictionary(record.metadata), depth: 1)
        try append(",\"source\":")
        try string(record.source)
        try append(",\"timestamp\":\(milliseconds)}\n")
        return data
    }

    /// Appends a small literal or scalar while enforcing the exact UTF-8 bound.
    /// - Parameter text: JSON syntax or scalar spelling to append verbatim.
    /// - Throws: `.recordTooLarge` before the configured capacity would be exceeded.
    private mutating func append(_ text: String) throws {
        guard text.utf8.count <= configuration.maximumRecordBytes - data.count else {
            throw DiscordFileLogError.recordTooLarge
        }
        data.append(contentsOf: text.utf8)
    }

    /// Escapes JSON syntax/control scalars and preserves all other Unicode scalars exactly.
    /// - Parameter text: Unescaped Unicode content; embedded line breaks never create extra NDJSON lines.
    /// - Throws: `.recordTooLarge` as soon as the bounded output is exhausted.
    private mutating func string(_ text: String) throws {
        try append("\"")
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 34: try append("\\\"")
            case 92: try append("\\\\")
            case 0...31:
                let digits = String(scalar.value, radix: 16)
                try append("\\u" + String(repeating: "0", count: 4 - digits.count) + digits)
            default: try append(String(scalar))
            }
        }
        try append("\"")
    }

    /// Encodes one metadata node with a shared finite count and container-depth budget.
    /// - Parameters:
    ///   - value: SwiftLog metadata, including nested arrays/dictionaries or a Sendable description value.
    ///   - depth: Container depth at this position; scalar values do not consume another level.
    /// - Throws: `.metadataLimitExceeded` before traversing an excessive container, or `.recordTooLarge`.
    private mutating func value(_ value: Logger.Metadata.Value, depth: Int) throws {
        guard metadataValues < configuration.maximumMetadataValues else {
            throw DiscordFileLogError.metadataLimitExceeded
        }
        metadataValues += 1
        switch value {
        case .string(let text): try string(text)
        case .stringConvertible(let description): try string(description.description)
        case .array(let values):
            guard depth <= configuration.maximumMetadataDepth,
                  values.count <= configuration.maximumMetadataValues - metadataValues else {
                throw DiscordFileLogError.metadataLimitExceeded
            }
            try append("[")
            for (index, element) in values.enumerated() {
                if index > 0 { try append(",") }
                try self.value(element, depth: depth + 1)
            }
            try append("]")
        case .dictionary(let dictionary):
            guard depth <= configuration.maximumMetadataDepth,
                  dictionary.count <= configuration.maximumMetadataValues - metadataValues else {
                throw DiscordFileLogError.metadataLimitExceeded
            }
            try append("{")
            for (index, key) in dictionary.keys.sorted().enumerated() {
                if index > 0 { try append(",") }
                try string(key)
                try append(":")
                if let element = dictionary[key] { try self.value(element, depth: depth + 1) }
            }
            try append("}")
        }
    }
}
