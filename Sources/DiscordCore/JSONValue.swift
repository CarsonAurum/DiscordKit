import Foundation

/// Explicit resource bounds for parsing and serializing untrusted JSON.
///
/// A container at the root has depth one; a scalar at the root has depth zero.
/// Every scalar and container counts as one node; object keys do not count as nodes.
/// Limits apply to the UTF-8 input or output, rather than Foundation's internal allocation size.
public struct JSONLimits: Sendable, Hashable {
    /// Default bounds: 1 MiB of UTF-8, 64 nested containers, and 100,000 values.
    public static let `default` = JSONLimits()
    /// Maximum UTF-8 input/output bytes, including whitespace in parsed input.
    public let maximumBytes: Int
    /// Maximum nested arrays/objects. Values outside `1...128` are rejected when used.
    public let maximumDepth: Int
    /// Maximum total scalar and container values. Must be positive when used.
    public let maximumNodes: Int

    /// Configures deterministic bounds without allocating a parser or validating input.
    /// - Parameters:
    ///   - maximumBytes: Positive UTF-8 byte limit; defaults to 1,048,576 bytes.
    ///   - maximumDepth: Nested-container limit in `1...128`; defaults to 64. The hard
    ///     upper bound prevents callers from accidentally enabling unbounded recursive parsing.
    ///   - maximumNodes: Positive node limit; defaults to 100,000.
    ///
    /// Invalid configurations are retained and produce `JSONValueError.invalidLimits`
    /// when parsing or serializing, rather than causing a process precondition failure.
    public init(maximumBytes: Int = 1_048_576, maximumDepth: Int = 64, maximumNodes: Int = 100_000) {
        self.maximumBytes = maximumBytes
        self.maximumDepth = maximumDepth
        self.maximumNodes = maximumNodes
    }

    /// Rejects nonsensical or unsafe parser/writer configurations before processing data.
    /// - Throws: `JSONValueError.invalidLimits` if bytes/nodes are nonpositive or depth is outside `1...128`.
    fileprivate func validate() throws {
        guard maximumBytes > 0, (1...128).contains(maximumDepth), maximumNodes > 0 else {
            throw JSONValueError.invalidLimits
        }
    }
}

/// Deterministic errors from the bounded JSON parser, writer, or number validator.
public enum JSONValueError: Error, Sendable, Equatable {
    /// Limits are invalid; supply positive byte/node limits and a depth within `1...128`.
    case invalidLimits
    /// The input or output exceeds the configured UTF-8 byte limit.
    case maximumBytesExceeded
    /// The document contains more nested containers than allowed.
    case maximumDepthExceeded
    /// The document contains more values than allowed.
    case maximumNodesExceeded
    /// Malformed JSON at a zero-based UTF-8 byte offset; no input content is included.
    case malformed(byteOffset: Int)
    /// An object repeats a decoded key; dictionaries cannot preserve both members losslessly.
    case duplicateKey(byteOffset: Int)
    /// A number is not a complete RFC 8259 JSON number, including nonfinite or empty spellings.
    case invalidNumber
}

/// An arbitrary-precision JSON numeric lexeme, preserved exactly rather than converted to `Double`.
///
/// This representation validates JSON grammar, not a bounded numeric range. Thus
/// huge integers, tiny exponents, trailing fractional zeros, and negative zero all
/// survive parse/serialization. Equality and hashing compare spelling, not arithmetic
/// value. No arithmetic or interpretation of unknown numeric values is implied.
public struct JSONNumber: Sendable, Hashable {
    /// The exact valid JSON number spelling, without surrounding whitespace.
    public let rawValue: String

    /// Validates a standalone JSON number without rounding or normalizing it.
    /// - Parameter rawValue: A complete ASCII JSON number, such as `-0`, `1.2300`, or `1e1000`.
    /// - Throws: `JSONValueError.invalidNumber` for whitespace, leading plus/zeros,
    ///   missing fractional/exponent digits, nonfinite values, or other malformed input.
    ///
    /// Validation is linear in the lexeme length. For untrusted complete documents,
    /// use `JSONValue.parse(_:limits:)` to enforce an overall byte limit as well.
    public init(rawValue: String) throws {
        let bytes = Array(rawValue.utf8)
        var index = 0
        if bytes.first == 45 { index += 1 }
        guard index < bytes.count else { throw JSONValueError.invalidNumber }
        if bytes[index] == 48 {
            index += 1
        } else {
            guard (49...57).contains(bytes[index]) else { throw JSONValueError.invalidNumber }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            let start = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard index > start else { throw JSONValueError.invalidNumber }
        }
        if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            let start = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard index > start else { throw JSONValueError.invalidNumber }
        }
        guard index == bytes.count else { throw JSONValueError.invalidNumber }
        self.rawValue = rawValue
    }
}

/// A portable JSON tree that preserves unknown fields, variants, and arbitrary numeric spellings.
///
/// `parse` and `serialized` form the lossless semantic path: numbers preserve exact
/// lexemes and strings preserve Unicode scalar content; object ordering, whitespace,
/// escape choices, and duplicate keys are not retained. Duplicate keys, including
/// canonically equivalent Unicode keys under Swift string equality, are rejected.
/// Serialization sorts object keys for deterministic output. Mutable state exists
/// only in local parser/writer values, so trees are safe to pass across isolation domains.
///
/// The Codable bridge is intentionally asymmetric. Decoder protocols do not expose
/// original number tokens, and even integer decoding can silently round fractional
/// tokens: decoding therefore rejects **all numbers**. Encoding accepts only
/// canonical decimal `Int64`/`UInt64` integers. Use `parse`/`serialized` for any
/// numeric payload or a complete lossless round trip. Codable does not apply
/// `JSONLimits`; bound the outer decoder's input separately.
public indirect enum JSONValue: Sendable, Hashable {
    /// JSON null.
    case null
    /// A JSON boolean, distinct from numeric zero or one.
    case bool(Bool)
    /// A validated numeric lexeme of arbitrary size or exponent.
    case number(JSONNumber)
    /// A Unicode string.
    case string(String)
    /// An ordered list of values.
    case array([JSONValue])
    /// Unique decoded string keys and their values; original member ordering is not retained.
    case object([String: JSONValue])

    /// Parses one complete UTF-8 JSON document under explicit resource bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON bytes, optionally surrounded by JSON whitespace.
    ///     BOMs, malformed Unicode, duplicate keys, and trailing documents are rejected.
    ///   - limits: Byte, nesting, and node limits; defaults to `JSONLimits.default`.
    /// - Returns: The complete value tree, including exact unknown number lexemes.
    /// - Throws: `JSONValueError` for malformed syntax, duplicate keys, or exceeded/invalid limits.
    ///
    /// Parsing is synchronous and linear in input bytes, apart from dictionary
    /// hashing; it performs no I/O and cannot be cooperatively cancelled mid-parse.
    public static func parse(_ data: Data, limits: JSONLimits = .default) throws -> JSONValue {
        try limits.validate()
        guard data.count <= limits.maximumBytes else { throw JSONValueError.maximumBytesExceeded }
        var parser = JSONParser(bytes: Array(data), limits: limits)
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else {
            throw JSONValueError.malformed(byteOffset: parser.index)
        }
        return value
    }

    /// Parses a complete Swift string through the same bounded UTF-8 path as byte input.
    /// - Parameters:
    ///   - text: A complete JSON document, including any surrounding whitespace.
    ///   - limits: UTF-8 byte, nesting, and node limits, with the standard defaults.
    /// - Returns: A lossless semantic tree with numeric lexemes preserved.
    /// - Throws: `JSONValueError` for invalid JSON or limits. Byte offsets refer to UTF-8, not character indices.
    public static func parse(_ text: String, limits: JSONLimits = .default) throws -> JSONValue {
        guard text.utf8.count <= limits.maximumBytes else {
            try limits.validate()
            throw JSONValueError.maximumBytesExceeded
        }
        return try parse(Data(text.utf8), limits: limits)
    }

    /// Serializes a compact JSON document without converting stored number lexemes.
    /// - Parameter limits: Output byte, container-depth, and node bounds; defaults to the standard limits.
    /// - Returns: UTF-8 JSON with deterministic sorted object keys and JSON-escaped strings.
    /// - Throws: `JSONValueError` for invalid/exceeded limits; Foundation encoding errors
    ///   if a string cannot be encoded. No partial output escapes on failure.
    ///
    /// Runtime is linear in output size plus object-key sorting. String escaping
    /// uses a fresh Foundation encoder and no globally shared mutable state.
    public func serialized(limits: JSONLimits = .default) throws -> Data {
        try limits.validate()
        var writer = JSONWriter(limits: limits)
        try writer.write(self, depth: 0)
        return Data(writer.bytes)
    }
}

extension JSONValue: Codable {
    /// Decodes a numeric-free JSON tree through the restricted Codable bridge.
    /// - Parameter decoder: Any decoder whose scalar/container representations match JSON.
    /// - Throws: Decoder errors or `DecodingError.dataCorrupted` for every numeric
    ///   payload, including nested numbers. Input byte/nesting limits are the caller's responsibility.
    ///
    /// This bridge cannot preserve the spelling of a numeric token. Use `parse`
    /// for arbitrary-precision numbers, unknown payload round trips, or untrusted data.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let values = try? container.decode([JSONValue].self) { self = .array(values) }
        else if let values = try? container.decode([String: JSONValue].self) { self = .object(values) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSONValue Codable decoding rejects numbers; use JSONValue.parse for lossless JSON.")
        }
    }

    /// Encodes the restricted Codable representation while refusing lossy numeric conversions.
    /// - Parameter encoder: The destination encoder.
    /// - Throws: `EncodingError.invalidValue` for noncanonical or out-of-range number
    ///   lexemes, or errors propagated from encoding other values.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        case .number(let number):
            if let value = Int64(number.rawValue), String(value) == number.rawValue { try container.encode(value) }
            else if let value = UInt64(number.rawValue), String(value) == number.rawValue { try container.encode(value) }
            else {
                throw EncodingError.invalidValue(number, .init(codingPath: encoder.codingPath,
                    debugDescription: "Numeric spelling requires JSONValue.serialized for lossless encoding."))
            }
        }
    }
}

/// Local bounded recursive-descent parser; array indices always address UTF-8 bytes.
private struct JSONParser {
    let bytes: [UInt8]
    let limits: JSONLimits
    var index = 0
    var nodes = 0

    /// Skips exactly the four whitespace bytes allowed by RFC 8259.
    ///
    /// Bounds checks precede all reads. Other Unicode whitespace remains invalid
    /// syntax and is reported by the next parser operation.
    mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    /// Parses one value and advances the cursor past it, preserving its number token.
    /// - Parameter depth: Current ancestor-container count; zero at the document root.
    /// - Returns: The parsed subtree.
    /// - Throws: Syntax, duplicate-key, or node/depth-limit errors before descending beyond the configured bound.
    mutating func value(depth: Int) throws -> JSONValue {
        whitespace()
        nodes += 1
        guard nodes <= limits.maximumNodes else { throw JSONValueError.maximumNodesExceeded }
        guard index < bytes.count else { throw JSONValueError.malformed(byteOffset: index) }
        switch bytes[index] {
        case 110: try literal("null"); return .null
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 34: return .string(try string())
        case 91, 123:
            guard depth < limits.maximumDepth else { throw JSONValueError.maximumDepthExceeded }
            return bytes[index] == 91 ? try array(depth: depth + 1) : try object(depth: depth + 1)
        case 45, 48...57:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            do { return .number(try JSONNumber(rawValue: String(decoding: bytes[start..<index], as: UTF8.self))) }
            catch { throw JSONValueError.malformed(byteOffset: start) }
        default: throw JSONValueError.malformed(byteOffset: index)
        }
    }

    /// Consumes a fixed literal token after checking every byte.
    /// - Parameter token: One of the ASCII JSON literals `null`, `true`, or `false`.
    /// - Throws: A malformed-input error at the token start if the spelling is incomplete or incorrect.
    mutating func literal(_ token: String) throws {
        let expected = Array(token.utf8)
        guard bytes.count - index >= expected.count,
              bytes[index..<(index + expected.count)].elementsEqual(expected) else {
            throw JSONValueError.malformed(byteOffset: index)
        }
        index += expected.count
    }

    /// Scans a quoted token and delegates Unicode/escape validation to Foundation's string decoder.
    /// - Returns: Decoded Unicode content; escape spelling itself is intentionally not retained.
    /// - Throws: A malformed-input error for unterminated strings, control bytes, invalid escapes, or invalid Unicode.
    mutating func string() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            guard byte >= 32 else { throw JSONValueError.malformed(byteOffset: index) }
            index += 1
            if byte == 92 {
                guard index < bytes.count else { throw JSONValueError.malformed(byteOffset: index) }
                index += 1
            } else if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                catch { throw JSONValueError.malformed(byteOffset: start) }
            }
        }
        throw JSONValueError.malformed(byteOffset: start)
    }

    /// Parses an array including its delimiters, preserving element order.
    /// - Parameter depth: Container depth including this array, already checked by `value`.
    /// - Returns: An array value, possibly empty.
    /// - Throws: Child parsing failures or malformed delimiters/trailing commas.
    mutating func array(depth: Int) throws -> JSONValue {
        index += 1
        whitespace()
        var values: [JSONValue] = []
        if index < bytes.count, bytes[index] == 93 { index += 1; return .array(values) }
        while true {
            values.append(try value(depth: depth))
            whitespace()
            guard index < bytes.count else { throw JSONValueError.malformed(byteOffset: index) }
            let delimiter = bytes[index]
            index += 1
            if delimiter == 93 { return .array(values) }
            guard delimiter == 44 else { throw JSONValueError.malformed(byteOffset: index - 1) }
        }
    }

    /// Parses an object with unique decoded keys, rejecting duplicates to avoid data loss.
    /// - Parameter depth: Container depth including this object, already checked by `value`.
    /// - Returns: An object value, possibly empty; original key order is not retained.
    /// - Throws: Duplicate-key errors, child parsing errors, or malformed keys/delimiters.
    mutating func object(depth: Int) throws -> JSONValue {
        index += 1
        whitespace()
        var values: [String: JSONValue] = [:]
        if index < bytes.count, bytes[index] == 125 { index += 1; return .object(values) }
        while true {
            whitespace()
            guard index < bytes.count, bytes[index] == 34 else { throw JSONValueError.malformed(byteOffset: index) }
            let keyOffset = index
            let key = try string()
            guard values[key] == nil else { throw JSONValueError.duplicateKey(byteOffset: keyOffset) }
            whitespace()
            guard index < bytes.count, bytes[index] == 58 else { throw JSONValueError.malformed(byteOffset: index) }
            index += 1
            values[key] = try value(depth: depth)
            whitespace()
            guard index < bytes.count else { throw JSONValueError.malformed(byteOffset: index) }
            let delimiter = bytes[index]
            index += 1
            if delimiter == 125 { return .object(values) }
            guard delimiter == 44 else { throw JSONValueError.malformed(byteOffset: index - 1) }
        }
    }
}

/// Local compact writer applying the same depth/node model as the parser.
private struct JSONWriter {
    let limits: JSONLimits
    var bytes: [UInt8] = []
    var nodes = 0

    /// Appends bytes only when the complete append fits the remaining output budget.
    /// - Parameter data: Next UTF-8 fragment or punctuation; must already be valid JSON syntax in context.
    /// - Throws: `JSONValueError.maximumBytesExceeded` before the bounded output array grows past its limit.
    mutating func append(_ data: some Collection<UInt8>) throws {
        guard data.count <= limits.maximumBytes - bytes.count else { throw JSONValueError.maximumBytesExceeded }
        bytes.append(contentsOf: data)
    }

    /// Escapes and appends one JSON string using an isolated Foundation encoder.
    /// - Parameter value: Unicode scalar content to quote; includes object keys as well as string values.
    /// - Throws: Byte-limit errors or Foundation string-encoding errors. No string contents appear in limit diagnostics.
    mutating func string(_ value: String) throws {
        guard value.utf8.count <= limits.maximumBytes - bytes.count else { throw JSONValueError.maximumBytesExceeded }
        try append(JSONEncoder().encode(value))
    }

    /// Writes a subtree with deterministic key order and original numeric spellings.
    /// - Parameters:
    ///   - value: Tree to serialize.
    ///   - depth: Ancestor-container count, zero at the root.
    /// - Throws: Node/depth/byte-limit errors or string-encoding errors; partial output stays private to this writer.
    mutating func write(_ value: JSONValue, depth: Int) throws {
        nodes += 1
        guard nodes <= limits.maximumNodes else { throw JSONValueError.maximumNodesExceeded }
        switch value {
        case .null: try append("null".utf8)
        case .bool(let value): try append((value ? "true" : "false").utf8)
        case .number(let value): try append(value.rawValue.utf8)
        case .string(let value): try string(value)
        case .array(let values):
            guard depth < limits.maximumDepth else { throw JSONValueError.maximumDepthExceeded }
            try append([91])
            for (index, child) in values.enumerated() {
                if index > 0 { try append([44]) }
                try write(child, depth: depth + 1)
            }
            try append([93])
        case .object(let values):
            guard depth < limits.maximumDepth else { throw JSONValueError.maximumDepthExceeded }
            try append([123])
            for (index, key) in values.keys.sorted().enumerated() {
                if index > 0 { try append([44]) }
                try string(key)
                try append([58])
                if let child = values[key] { try write(child, depth: depth + 1) }
            }
            try append([125])
        }
    }
}
