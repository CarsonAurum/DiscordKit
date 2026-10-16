import Foundation

/// One ordered HTTP header. Duplicate names and original casing are preserved.
public struct HTTPHeader: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let name: String
    public let value: String

    /// Stores wire header text without endpoint policy or authentication inference.
    /// - Parameters:
    ///   - name: Header field name; adapters must reject invalid wire syntax.
    ///   - value: Header value; may contain secrets and must never be logged raw.
    public init(name: String, value: String) { self.name = name; self.value = value }

    /// Returns a safe diagnostic without exposing header names or secret values.
    public var description: String { "HTTPHeader(redacted)" }

    /// Returns the same redacted value for debug formatting.
    public var debugDescription: String { description }

    /// Prevents reflection-based diagnostics from expanding raw header storage.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// An HTTP request owned by one execution. URL/authentication policy belongs upstream.
public struct HTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let method: String
    public let url: URL
    public let headers: [HTTPHeader]
    public let body: BodyStream?

    /// Creates an unexecuted request, retaining duplicate headers and body ownership.
    /// - Parameters:
    ///   - method: HTTP token; adapters validate wire syntax before sending.
    ///   - url: Destination including query; may contain secrets.
    ///   - headers: Ordered fields, empty by default; sensitive values must be redacted.
    ///   - body: Single-use body, or `nil` for no body. Execution owns its cleanup.
    public init(method: String, url: URL, headers: [HTTPHeader] = [], body: BodyStream? = nil) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }

    /// Redacts methods, URLs, query values, headers and body sources in diagnostics.
    public var description: String { "HTTPRequest(redacted)" }

    /// Uses safe formatting even when an error or test failure requests debug output.
    public var debugDescription: String { description }

    /// Prevents generic reflection from discovering URL, header or body credentials.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Response metadata and a body whose ownership transfers to the caller.
public struct HTTPResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let status: Int
    public let headers: [HTTPHeader]
    public let body: BodyStream?

    /// Stores response metadata without interpreting API status or retry policy.
    /// - Parameters:
    ///   - status: Wire status code; adapters validate protocol-specific validity.
    ///   - headers: Ordered headers, preserving duplicates; empty by default.
    ///   - body: Optional response body. Caller must consume to EOF or close it.
    public init(status: Int, headers: [HTTPHeader] = [], body: BodyStream? = nil) {
        self.status = status; self.headers = headers; self.body = body
    }

    /// Includes only numeric status, redacting response headers and body sources.
    public var description: String { "HTTPResponse(status: \(status), redacted)" }

    /// Uses the same redacted representation during debug formatting.
    public var debugDescription: String { description }

    /// Exposes only status to reflection-based diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["status": status]) }
}

/// A cancellable HTTP exchange with no Discord routes, authentication, or retry policy.
public protocol HTTPTransport: Sendable {
    /// Sends once and transfers successful response-body ownership to the caller.
    ///
    /// Cancellation/deadline failure must terminate pending adapter I/O and close the
    /// request body and any untransferred response body. An ambiguous mutation must
    /// not be replayed. Adapter pools outlive individual calls and are separately owned.
    /// - Parameters:
    ///   - request: Single-use request; this execution owns its body cleanup.
    ///   - context: Injected clock, cancellation and optional inclusive deadline.
    /// - Returns: Response headers and a bounded pull body, if present.
    /// - Throws: Cancellation, deadline, validation or adapter transport failures.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
        where C.Duration == Duration
}
