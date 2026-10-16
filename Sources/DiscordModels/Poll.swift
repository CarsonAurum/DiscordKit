import DiscordCore
import Foundation

extension ResourceObject {
    /// Retains an already bounded object without reparsing or copying each recursive subtree.
    /// - Parameters:
    ///   - verifiedFields: Fields from a JSON tree whose complete root already passed JSONLimits.
    ///   - limits: The same bounds used at that root; scalar decoding keeps exact integer validation.
    /// No validation, I/O, or suspension occurs here. This internal initializer must never
    /// receive unbounded external trees; public tree entry points enforce bounds first.
    init(verifiedFields: [String: JSONValue], limits: JSONLimits) {
        fields = verifiedFields
        self.limits = limits
    }
}

/// Internal exact-tree projection shared by poll and component models. Outer parsing
/// establishes document bounds. Nested objects share the immutable original tree,
/// avoiding repeated parsing and depth-multiplied retention of raw payloads.
struct PayloadObject {
    let resource: ResourceObject
    let limits: JSONLimits

    /// Requires an object and reuses sanitized, exact-integer scalar decoding.
    /// - Parameters:
    ///   - value: Already bounded JSON subtree, including its unknown fields.
    ///   - limits: Caller-selected byte, depth, and node bounds.
    /// - Throws: Bounded JSON errors or safe invalid-response errors for nonobjects.
    init(_ value: JSONValue, limits: JSONLimits) throws {
        guard case .object(let fields) = value else { throw DiscordError.transport(.invalidResponse) }
        resource = ResourceObject(verifiedFields: fields, limits: limits)
        self.limits = limits
    }

    /// Decodes a required scalar using exact integer lexemes and sanitized errors.
    /// - Parameters:
    ///   - name: Required wire key.
    ///   - type: Expected scalar or scalar-array type.
    /// - Returns: The present nonnull value.
    /// - Throws: Invalid-response errors for absent, null, malformed, or out-of-range values.
    func required<T: Decodable>(_ name: String, _ type: T.Type) throws -> T {
        try resource.required(name, as: type)
    }

    /// Decodes optional scalar presence without collapsing omission into null.
    /// - Parameters:
    ///   - name: Wire key to inspect.
    ///   - type: Expected nonnull scalar type.
    ///   - nullable: Whether explicit null is permitted; defaults to false.
    /// - Returns: Absent, permitted null, or a validated value.
    /// - Throws: Safe invalid-response errors for forbidden null or incompatible values.
    func field<T: Decodable>(_ name: String, _ type: T.Type, nullable: Bool = false) throws -> Field<T> {
        try resource.field(name, as: type, nullable: nullable)
    }

    /// Projects optional nested values without a lossy JSON Codable bridge.
    /// - Parameters:
    ///   - name: Wire key to inspect.
    ///   - nullable: Whether explicit null is accepted; defaults to false.
    ///   - transform: Synchronous typed projection receiving the original JSON subtree.
    /// - Returns: Original presence with a typed present value.
    /// - Throws: Safe errors for forbidden null, or any sanitized projection/bounds error.
    func nested<T>(_ name: String, nullable: Bool = false, transform: (JSONValue) throws -> T) throws -> Field<T> {
        guard let value = resource.fields[name] else { return .absent }
        if value == .null {
            guard nullable else { throw DiscordError.transport(.invalidResponse) }
            return .null
        }
        return .value(try transform(value))
    }

    /// Projects an optional ordered array, rejecting scalar roots and invalid elements.
    /// - Parameters:
    ///   - name: Wire key for the optional, nonnull array.
    ///   - transform: Synchronous projection applied once to each original element.
    /// - Returns: Absent or an ordered typed array, including an empty array.
    /// - Throws: Invalid-response or element projection errors; explicit null is forbidden.
    func array<T>(_ name: String, transform: (JSONValue) throws -> T) throws -> Field<[T]> {
        try nested(name) { value in
            guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
            return try values.map(transform)
        }
    }
}

/// Known poll layouts; raw wrappers retain future integral layouts in responses.
public enum PollLayoutType: Int, Sendable {
    /// The currently documented poll layout.
    case `default` = 1
}

/// A partial emoji shared by poll media and components; optional nullable IDs/names retain all presence states.
public struct PartialEmoji: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Custom emoji decimal snowflake; absent/null for Unicode emoji.
    public let id: Field<String>
    /// Unicode emoji or custom emoji name; absent/null remain distinct.
    public let name: Field<String>
    /// Whether the custom emoji is animated; absent uses the server default.
    public let animated: Field<Bool>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.field("id", String.self, nullable: true)
        name = try object.field("name", String.self, nullable: true)
        animated = try object.field("animated", Bool.self)
        if case .value(let id) = id {
            guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(id) != nil
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PartialEmoji(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Poll question/answer media. Future nullable text is retained; emoji is optional and nonnull when present.
public struct PollMedia: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Optional text; explicit null is retained for the documented future extensibility.
    public let text: Field<String>
    /// Optional typed emoji; omission differs from an empty object.
    public let emoji: Field<PartialEmoji>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        text = try object.field("text", String.self, nullable: true)
        emoji = try object.nested("emoji") { try PartialEmoji(value: $0, limits: limits) }
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PollMedia(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension PollMedia {
    /// Constructs poll answer media for later request validation; question text uses PollCreate's string parameter.
    /// - Parameters:
    ///   - text: Answer text; omission/null survive here but PollCreate rejects them for current requests.
    ///   - emoji: Optional partial emoji object, containing a custom `id` or Unicode `name`; null is rejected.
    /// - Throws: Safe invalid-response errors for incompatible emoji values or default JSON bounds errors.
    public init(text: Field<String> = .absent, emoji: Field<JSONValue> = .absent) throws {
        var fields: [String: JSONValue] = [:]
        switch text { case .absent: break; case .null: fields["text"] = .null; case .value(let value): fields["text"] = .string(value) }
        switch emoji { case .absent: break; case .null: fields["emoji"] = .null; case .value(let value): fields["emoji"] = value }
        let value = JSONValue.object(fields)
        _ = try value.serialized()
        try self.init(value: value, limits: .default)
    }
}

/// A response answer. Answer IDs are opaque integers; no sequential numbering assumption is made.
public struct PollAnswer: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Response-only answer identifier; not a positional index.
    public let answerID: Int
    /// Typed answer media, retaining future unknown fields.
    public let pollMedia: PollMedia
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        answerID = try object.required("answer_id", Int.self)
        guard let media = object.resource.fields["poll_media"] else { throw DiscordError.transport(.invalidResponse) }
        pollMedia = try PollMedia(value: media, limits: limits)
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PollAnswer(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// One poll tally. An omitted answer in the results array means zero votes for that answer.
public struct PollAnswerCount: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Opaque answer identifier matching answer_id.
    public let id: Int
    /// Nonnegative exact vote count; native overflow is rejected.
    public let count: UInt64
    /// Whether the current user voted for this answer.
    public let meVoted: Bool
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", Int.self)
        count = try object.required("count", UInt64.self)
        meVoted = try object.required("me_voted", Bool.self)
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PollAnswerCount(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Poll tally snapshot; counts may be approximate until isFinalized becomes true.
public struct PollResults: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// True only once Discord has completed the final accurate tally.
    public let isFinalized: Bool
    /// Ordered available tallies; an empty array is meaningful zero votes.
    public let answerCounts: [PollAnswerCount]
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        isFinalized = try object.required("is_finalized", Bool.self)
        guard case .value(let counts) = try object.array("answer_counts", transform: { try PollAnswerCount(value: $0, limits: limits) })
        else { throw DiscordError.transport(.invalidResponse) }
        answerCounts = counts
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PollResults(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Complete documented poll response for API v10, verified 2026-10-16. Absence of results means unknown results, never zero votes.
public struct Poll: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Question media; only text is currently supported for creation.
    public let question: PollMedia
    /// Answers in server order, retaining opaque answer identifiers.
    public let answers: [PollAnswer]
    /// Required nullable ISO8601 expiry text; no local timezone conversion is performed.
    public let expiry: Nullable<String>
    /// Whether voters may select multiple answers.
    public let allowMultiselect: Bool
    /// Known or future integral layout identifier.
    public let layoutType: RawValue<PollLayoutType>
    /// Absent means unknown results; explicit null is forbidden by the current schema.
    public let results: Field<PollResults>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guard let questionValue = object.resource.fields["question"] else { throw DiscordError.transport(.invalidResponse) }
        question = try PollMedia(value: questionValue, limits: limits)
        guard case .value(let values) = try object.array("answers", transform: { try PollAnswer(value: $0, limits: limits) })
        else { throw DiscordError.transport(.invalidResponse) }
        answers = values
        expiry = try object.required("expiry", Nullable<String>.self)
        allowMultiselect = try object.required("allow_multiselect", Bool.self)
        layoutType = try object.required("layout_type", RawValue<PollLayoutType>.self)
        results = try object.nested("results") { try PollResults(value: $0, limits: limits) }
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "Poll(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated poll creation payload. Poll creation requires SEND_POLLS and cannot be
/// combined with Components V2. Endpoints own rate admission; this value performs no requests.
public struct PollCreate: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Complete validated wire object; omitted defaults remain omitted.
    public let rawFields: [String: JSONValue]

    /// Validates current API v10 poll creation constraints without mutating caller values.
    /// - Parameters:
    ///   - question: Nonempty question text, at most 300 Unicode scalars.
    ///   - answers: One through ten answers, each with nonempty text of at most 55 Unicode scalars.
    ///     Answer emoji requests contain exactly one custom `id` or Unicode `name` key.
    ///   - duration: Optional hours in 1...768 (32 days); nil leaves Discord's 24-hour default.
    ///   - allowMultiselect: Optional selection policy; nil leaves Discord's false default.
    ///   - layoutType: Optional known layout 1; nil leaves Discord's default. Unknown request layouts are rejected.
    /// - Throws: `DiscordError.validation(.invalidValue)` for invalid text, counts, duration, layout,
    ///   null answer fields, response-only media fields, or malformed emoji request shapes.
    public init(question: String, answers: [PollMedia], duration: Int? = nil,
                allowMultiselect: Bool? = nil, layoutType: Int? = nil) throws {
        guard (1...300).contains(question.unicodeScalars.count), (1...10).contains(answers.count),
              duration.map({ (1...768).contains($0) }) ?? true, layoutType.map({ $0 == 1 }) ?? true
        else { throw DiscordError.validation(.invalidValue) }
        for answer in answers {
            guard case .value(let text) = answer.text, (1...55).contains(text.unicodeScalars.count),
                  Set(answer.rawFields.keys).isSubset(of: ["text", "emoji"])
            else { throw DiscordError.validation(.invalidValue) }
            if case .value(let emoji) = answer.emoji {
                let fields = emoji.rawFields
                guard fields.count == 1,
                      (fields["id"].map { if case .string(let id) = $0 { return !id.isEmpty }; return false } ?? false)
                        || (fields["name"].map { if case .string(let name) = $0 { return !name.isEmpty }; return false } ?? false)
                else { throw DiscordError.validation(.invalidValue) }
            }
        }
        var fields: [String: JSONValue] = [
            "question": .object(["text": .string(question)]),
            "answers": .array(answers.map { .object(["poll_media": .object($0.rawFields)]) })
        ]
        if let duration { fields["duration"] = .number(try JSONNumber(rawValue: String(duration))) }
        if let allowMultiselect { fields["allow_multiselect"] = .bool(allowMultiselect) }
        if let layoutType { fields["layout_type"] = .number(try JSONNumber(rawValue: String(layoutType))) }
        rawFields = fields
    }

    /// Returns the validated exact JSON tree for composition into a message request.
    /// - Returns: An immutable poll creation object; no response-only answer IDs or expiry are emitted.
    public func jsonValue() throws -> JSONValue { .object(rawFields) }

    /// Serializes the validated payload deterministically under explicit output bounds.
    /// - Parameter limits: Output byte, node, and depth bounds; defaults to the library's bounded JSON policy.
    /// - Returns: UTF-8 JSON bytes with sorted object keys and preserved caller string scalars.
    /// - Throws: JSON limits errors; no I/O, rate admission, or credential access occurs.
    public func serialized(limits: JSONLimits = .default) throws -> Data {
        try jsonValue().serialized(limits: limits)
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "PollCreate(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
