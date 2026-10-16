import DiscordTransport
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit application-level resource limits for one Foundation adapter instance.
///
/// HTTP uploads are collected within the request limit before transmission. Responses
/// are pulled using Foundation's native byte sequence. Foundation owns socket pools,
/// TLS and its private buffers; these limits do not claim a bound on those buffers.
public struct FoundationTransportConfiguration: Sendable, Equatable {
    public let maximumConcurrentOperations: Int
    public let maximumRequestBodyBytes: Int
    public let maximumResponseBodyBytes: Int
    public let responseChunkBytes: Int
    public let maximumWebSocketMessageBytes: Int
    public let networkTimeout: TimeInterval

    /// Validates limits without allocating sessions or beginning network work.
    /// - Parameters:
    ///   - maximumConcurrentOperations: Positive aggregate admission count, including
    ///     transferred HTTP bodies and live WebSockets; excess work fails immediately.
    ///     Also bounds queued writers per connection, in addition to its active writer.
    ///   - maximumRequestBodyBytes: Positive upload collection ceiling, in bytes.
    ///   - maximumResponseBodyBytes: Positive total consumed response ceiling, in bytes.
    ///   - responseChunkBytes: Positive maximum returned chunk, no larger than the
    ///     response ceiling. A short final chunk is allowed.
    ///   - maximumWebSocketMessageBytes: Positive text UTF-8 or binary message ceiling.
    ///   - networkTimeout: Finite positive Foundation request/resource timeout in
    ///     seconds. An operation's injected deadline may expire earlier.
    /// - Throws: `TransportFailure.invalidLimit` for an invalid limit or timeout.
    public init(
        maximumConcurrentOperations: Int = 32,
        maximumRequestBodyBytes: Int = 8 * 1_024 * 1_024,
        maximumResponseBodyBytes: Int = 8 * 1_024 * 1_024,
        responseChunkBytes: Int = 16 * 1_024,
        maximumWebSocketMessageBytes: Int = 1_024 * 1_024,
        networkTimeout: TimeInterval = 60
    ) throws {
        guard maximumConcurrentOperations > 0, maximumRequestBodyBytes > 0,
              maximumResponseBodyBytes > 0, responseChunkBytes > 0,
              responseChunkBytes <= maximumResponseBodyBytes,
              maximumWebSocketMessageBytes > 0, networkTimeout.isFinite,
              networkTimeout > 0 else { throw TransportFailure.invalidLimit }
        self.maximumConcurrentOperations = maximumConcurrentOperations
        self.maximumRequestBodyBytes = maximumRequestBodyBytes
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
        self.responseChunkBytes = responseChunkBytes
        self.maximumWebSocketMessageBytes = maximumWebSocketMessageBytes
        self.networkTimeout = networkTimeout
    }
}

/// Redacted adapter failures; associated values never retain URLs, headers or bodies.
public enum FoundationTransportFailure: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case admissionRejected
    case bodyLimitExceeded(limit: Int)
    case messageLimitExceeded(limit: Int)
    case network(code: Int)
    case unavailableCapability
}

/// Converts platform errors to stable numeric diagnostics without NSError userInfo.
/// - Parameter error: Original failure, potentially containing a sensitive URL.
/// - Returns: Cancellation and owned failures unchanged, otherwise a numeric failure.
func foundationFailure(_ error: any Error) -> any Error {
    if error is CancellationError || error is TransportFailure || error is FoundationTransportFailure {
        return error
    }
    if Task.isCancelled { return CancellationError() }
    return FoundationTransportFailure.network(code: (error as NSError).code)
}

/// Validates request syntax before URLSession can normalize or transmit it.
///
/// Foundation cannot preserve duplicate header fields in its response metadata.
/// Duplicate request fields are rejected, rather than silently joined. Endpoint
/// authentication and origin eligibility remain the caller's responsibility.
/// - Parameters:
///   - request: Untrusted wire metadata; body ownership is handled by the caller.
///   - webSocket: Whether only GET and a ws/wss URL are permitted.
/// - Returns: A validated platform request with caching and cookies disabled.
/// - Throws: `FoundationTransportFailure.invalidRequest` for invalid syntax, embedded
///   URL credentials/fragments, unsupported schemes or duplicate/managed headers.
func foundationRequest(_ request: HTTPRequest, webSocket: Bool) throws -> URLRequest {
    let token = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
    let methodBytes = request.method.utf8
    let schemes = webSocket ? ["ws", "wss"] : ["http", "https"]
    guard !methodBytes.isEmpty, methodBytes.allSatisfy({ token.contains($0) }),
          let scheme = request.url.scheme?.lowercased(), schemes.contains(scheme),
          request.url.host?.isEmpty == false, request.url.user == nil,
          request.url.password == nil, request.url.fragment == nil,
          !webSocket || (request.method == "GET" && request.body == nil)
    else { throw FoundationTransportFailure.invalidRequest }
    var names: Set<String> = []
    var result = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData)
    result.httpMethod = request.method
    result.httpShouldHandleCookies = false
    for header in request.headers {
        let name = header.name.lowercased()
        guard !header.name.isEmpty, header.name.utf8.allSatisfy({ token.contains($0) }),
              header.value.utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) }),
              names.insert(name).inserted,
              !["host", "content-length", "transfer-encoding", "connection", "upgrade"].contains(name),
              !name.hasPrefix("sec-websocket-")
        else { throw FoundationTransportFailure.invalidRequest }
        result.setValue(header.value, forHTTPHeaderField: header.name)
    }
    return result
}
