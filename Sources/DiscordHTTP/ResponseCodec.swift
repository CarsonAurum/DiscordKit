import DiscordCore
import DiscordTransport
import Foundation

/// Complete-body collection shared by typed and raw HTTP operations.
public enum ResponseBody {
    /// Pulls a response under an explicit total-byte cap and always relinquishes ownership.
    /// - Parameters:
    ///   - stream: Optional single-consumer response body; `nil` yields empty data.
    ///   - maximumBytes: Positive complete-body byte cap, including error bodies.
    /// - Returns: Ordered bytes, empty for absent/empty bodies. No partial data escapes on failure.
    /// - Throws: Cancellation, producer failures, or safe validation/limit errors. The stream is
    ///   closed after EOF, cancellation, invalid configuration, oversized data and producer failure.
    public static func collect(_ stream: BodyStream?, maximumBytes: Int) async throws -> Data {
        do {
            guard maximumBytes > 0 else { throw DiscordError.validation(.invalidValue) }
            try Task.checkCancellation()
            var bytes = Data()
            if let stream {
                for try await chunk in stream {
                    guard chunk.count <= maximumBytes - bytes.count else { throw DiscordError.transport(.limitExceeded) }
                    bytes.append(chunk)
                }
                await stream.close()
            }
            try Task.checkCancellation()
            return bytes
        } catch {
            await stream?.close()
            throw error
        }
    }
}

/// An explicitly empty successful result, suitable for `204 No Content` descriptors.
public struct EmptyResponse: Sendable, Equatable {
    /// Accepts an empty response, rejecting unexpected payload bytes rather than silently discarding them.
    /// - Parameter data: Complete response bytes; must be empty.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for a nonempty body.
    public init(data: Data) throws {
        guard data.isEmpty else { throw DiscordError.transport(.invalidResponse) }
    }
}

/// A safe API failure retaining bounded server evidence for deliberate inspection.
/// Numeric Discord codes remain open; nested `_errors` structures are preserved exactly
/// through `JSONValue`, including unknown keys and arbitrary numeric lexemes. Ordinary
/// string/debug/reflection diagnostics never expose server text, headers or body bytes.
public struct APIResponseError: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let status: Int
    public let headers: [HTTPHeader]
    public let code: Int?
    public let bodyWasTruncated: Bool
    private let body: Data
    private let payload: JSONValue?

    /// Retains at most 1 MiB of error evidence and tolerates non-JSON/malformed responses.
    /// - Parameters:
    ///   - status: Wire HTTP status, retained even if the response is malformed.
    ///   - headers: Ordered response headers; values can contain secrets and require deliberate handling.
    ///   - body: Already collected bytes; this value defensively caps retention to 1 MiB.
    ///
    /// Invalid or deeply nested JSON is retained as bytes with `code == nil`; parsing failure
    /// never replaces the HTTP error with an unsafe decoder description. Truncation is explicit.
    public init(status: Int, headers: [HTTPHeader], body: Data) {
        self.status = status; self.headers = headers
        bodyWasTruncated = body.count > 1_048_576
        self.body = Data(body.prefix(1_048_576))
        payload = try? JSONValue.parse(self.body)
        if case .object(let object) = payload, case .number(let number) = object["code"] {
            code = Int(number.rawValue)
        } else { code = nil }
    }

    /// Explicitly lends raw error bytes to a caller-controlled synchronous operation.
    /// - Parameter operation: Inspector responsible for preventing secrets from reaching diagnostics.
    /// - Returns: The inspector's result; an empty/malformed body remains inspectable.
    /// - Throws: Rethrows only inspector failures, without wrapping or logging them.
    public func withUnsafeBody<Value>(_ operation: (Data) throws -> Value) rethrows -> Value { try operation(body) }

    /// Explicitly lends the parsed error tree, including untrusted messages and nested validation paths.
    /// - Parameter operation: Inspector receiving exact parsed JSON, or `nil` for malformed/bounded-out JSON.
    /// - Returns: The inspector's result; no field or message is normalized or discarded on successful parse.
    /// - Throws: Rethrows only inspector failures. The inspector owns any logging/redaction decision.
    public func withUnsafePayload<Value>(_ operation: (JSONValue?) throws -> Value) rethrows -> Value { try operation(payload) }

    /// Reports only numeric status/code and a fixed failure category.
    public var description: String { "Discord API failure (HTTP \(status), code \(code.map(String.init) ?? "unknown"))" }
    /// Uses the same safe numeric summary during debug formatting.
    public var debugDescription: String { description }
    /// Conceals retained response evidence from recursive reflection.
    public var customMirror: Mirror { Mirror(self, children: ["status": status, "code": code.map(String.init) ?? "unknown"]) }
}
