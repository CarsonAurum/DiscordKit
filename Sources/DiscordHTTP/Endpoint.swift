import DiscordCore
import DiscordTransport
import Foundation

/// Authentication accepted by a descriptor; path-carried tokens need dedicated future endpoints.
public enum AuthenticationPolicy: String, Sendable, Hashable {
    case none, bot, bearer, botOrBearer
}

/// Whether an ambiguous send can be replayed under this operation's documented semantics.
public enum RetrySafety: String, Sendable, Hashable {
    /// The operation is demonstrably safe to repeat, independently of its HTTP method.
    case safe
    /// A send failure may represent a completed mutation and requires reconciliation.
    case unsafe
}

/// Explicit opt-in read reduction metadata; a GET method alone grants no eligibility.
public struct ReadPolicy: Sendable, Hashable {
    public let coalescing: Bool
    public let timeToLive: Duration?
    public let tags: Set<String>

    /// Describes read reuse without creating or consulting any cache.
    /// - Parameters:
    ///   - coalescing: Whether equivalent in-flight reads may share response bytes, default `true`.
    ///   - timeToLive: Optional positive monotonic freshness bound; `nil` disables completed-result caching.
    ///   - tags: Resource/visibility invalidation tags, scoped by the client's opaque authentication identity.
    ///
    /// Invalid TTLs are rejected by endpoint construction. Snapshots never establish current authorization;
    /// unobserved external changes can remain stale until expiry.
    public init(coalescing: Bool = true, timeToLive: Duration? = nil, tags: Set<String> = []) {
        self.coalescing = coalescing; self.timeToLive = timeToLive; self.tags = tags
    }
}

/// Describes a documented bulk operation without automatically combining mutations.
public struct BulkOperationMetadata: Sendable, Hashable {
    public let maximumItems: Int
    public let preservesOrder: Bool
    public let permitsPartialResults: Bool
    public let documentationURL: URL

    /// Records a concrete upstream contract; validation occurs when an endpoint adopts it.
    /// - Parameters:
    ///   - maximumItems: Positive operation-specific item limit.
    ///   - preservesOrder: Whether upstream promises input order in its returned results.
    ///   - permitsPartialResults: Whether callers must handle a mixture of successes and failures.
    ///   - documentationURL: Official source for the bulk contract; this metadata triggers no fetch.
    public init(maximumItems: Int, preservesOrder: Bool, permitsPartialResults: Bool, documentationURL: URL) {
        self.maximumItems = maximumItems; self.preservesOrder = preservesOrder
        self.permitsPartialResults = permitsPartialResults; self.documentationURL = documentationURL
    }
}

/// A typed operation pinned to Discord's explicitly versioned HTTPS API origin.
/// Descriptors are immutable and transport independent. Ordinary diagnostics redact paths,
/// queries, headers and bodies. Raw relative routes use this exact construction pipeline.
public struct Endpoint<Response: Sendable>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let method: String
    public let path: [String]
    public let route: String
    public let query: [QueryItem]
    public let authentication: AuthenticationPolicy
    public let successStatuses: Set<Int>
    public let majorParameter: String?
    /// Whether Discord's credential-global budget applies; interaction callbacks explicitly opt out.
    public let usesGlobalLimit: Bool
    public let auditReason: String?
    public let body: RequestBody?
    public let headers: [HTTPHeader]
    public let retrySafety: RetrySafety
    public let readPolicy: ReadPolicy?
    public let invalidates: Set<String>
    public let bulk: BulkOperationMetadata?
    /// Accounted retained descriptor text bytes, excluding bodies and runtime/container overhead.
    public let accountedMetadataBytes: Int
    public let decode: @Sendable (Data) throws -> Response

    /// Validates an operation without executing it or inspecting credentials.
    /// - Parameters:
    ///   - method: Uppercase HTTP token; no retry/cache policy is inferred from it.
    ///   - path: Unescaped path segments. Empty, dot, slash, backslash and control-containing segments fail.
    ///   - route: Stable normalized rate-limit route template; defaults to the literal path.
    ///   - query: Ordered raw fields; repeated keys and bare fields are retained.
    ///   - authentication: Accepted credential category, default `.botOrBearer`.
    ///   - successStatuses: Explicit HTTP success statuses, default `[200]`; values must be in `200...299`.
    ///   - majorParameter: Opaque major-resource partition key, or `nil` when none applies. Never include a token.
    ///   - usesGlobalLimit: Whether the ordinary credential-global budget applies, default `true`.
    ///     Set `false` only for an officially documented exempt operation, such as an interaction callback.
    ///   - auditReason: Optional reason, at most 512 Unicode scalars, encoded once for the audit header.
    ///   - body: Optional replayable, already bounded body.
    ///   - headers: Additional representation headers. Authentication and framing overrides are rejected.
    ///   - retrySafety: Explicit replay semantics; defaults to `.unsafe`.
    ///   - readPolicy: Optional eligible-read metadata. Positive TTL and `.safe` are required for read reuse.
    ///   - invalidates: Authentication-scoped tags invalidated by a successful mutation.
    ///   - bulk: Optional documented upstream bulk contract; no request merging is performed.
    ///   - maximumQueryItems: Local descriptor query-field cap in `1...2,048`, default `256`.
    ///     Larger documented search arrays may opt in; this does not change Discord's per-field limits.
    ///   - maximumMetadataBytes: Local retained UTF-8 descriptor-text cap in `1...1,048,576`,
    ///     default `65,536` bytes (64 KiB). Counted bytes remain included in aggregate and
    ///     per-identity coordinator reservations; raising this cap never bypasses scheduling budgets.
    ///   - decode: Synchronous, sendable complete-body decoder. Empty/204 handling belongs to this closure.
    /// - Throws: `DiscordError.validation(.invalidValue)` for unsafe paths, metadata, headers or policies.
    ///   Descriptor text defaults to 64 KiB and 256 query fields, with explicit bounded opt-ins
    ///   above. There are at most 64 path segments, 128 headers and 128 tags of each kind.
    ///   Read-reuse bodies are materialized and at most 16 KiB.
    ///   Excess aggregate text throws `.limitExceeded`; normalized rate routes are at most 1,024 bytes
    ///   and major-resource keys at most 256 bytes. Runtime/container/closure-capture overhead is not byte-accounted.
    public init(
        method: String, path: [String], route: String? = nil, query: [QueryItem] = [],
        authentication: AuthenticationPolicy = .botOrBearer, successStatuses: Set<Int> = [200],
        majorParameter: String? = nil, usesGlobalLimit: Bool = true, auditReason: String? = nil, body: RequestBody? = nil,
        headers: [HTTPHeader] = [], retrySafety: RetrySafety = .unsafe, readPolicy: ReadPolicy? = nil,
        invalidates: Set<String> = [], bulk: BulkOperationMetadata? = nil,
        maximumQueryItems: Int = 256, maximumMetadataBytes: Int = 65_536,
        decode: @escaping @Sendable (Data) throws -> Response
    ) throws {
        let token = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        let reserved: Set<String> = ["authorization", "proxy-authorization", "host", "content-length", "transfer-encoding", "user-agent", "content-type", "x-audit-log-reason"]
        guard (1...2_048).contains(maximumQueryItems), (1...1_048_576).contains(maximumMetadataBytes),
              path.count <= 64, query.count <= maximumQueryItems, headers.count <= 128, invalidates.count <= 128,
              (readPolicy?.tags.count ?? 0) <= 128, method.utf8.count <= 32,
              (majorParameter?.utf8.count ?? 0) <= 256
        else { throw DiscordError.validation(.invalidValue) }
        let resolvedRoute = route ?? "/" + path.joined(separator: "/")
        let metadata = path + [method, resolvedRoute, majorParameter ?? "", auditReason ?? "", bulk?.documentationURL.absoluteString ?? ""] + query.flatMap { [$0.name, $0.value ?? ""] } +
            headers.flatMap { [$0.name, $0.value] } + Array(invalidates) + Array(readPolicy?.tags ?? [])
        var metadataBytes = 0
        for field in metadata {
            guard field.utf8.count <= maximumMetadataBytes - metadataBytes else { throw DiscordError.validation(.limitExceeded) }
            metadataBytes += field.utf8.count
        }
        guard (body?.accountedBytes ?? 0) <= Int.max - metadataBytes else { throw DiscordError.validation(.limitExceeded) }
        guard !method.isEmpty, method.utf8.allSatisfy({ token.contains($0) }), !path.isEmpty,
              !resolvedRoute.isEmpty, resolvedRoute.utf8.count <= 1_024,
              path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") &&
                  !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) }),
              !successStatuses.isEmpty, successStatuses.allSatisfy({ (200...299).contains($0) }),
              headers.allSatisfy({ header in
                  !header.name.isEmpty && header.name.utf8.allSatisfy({ token.contains($0) || (97...122).contains($0) }) &&
                  !reserved.contains(header.name.lowercased()) && !header.value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
              }),
              auditReason.map({ $0.unicodeScalars.count <= 512 && !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) }) ?? true,
              readPolicy == nil || retrySafety == .safe,
              readPolicy == nil || invalidates.isEmpty,
              readPolicy == nil || body?.isStreaming != true,
              readPolicy == nil || (body?.bytes.count ?? 0) <= 16_384,
              readPolicy?.timeToLive.map({ $0 > .zero }) ?? true,
              bulk.map({ $0.maximumItems > 0 }) ?? true
        else { throw DiscordError.validation(.invalidValue) }
        self.method = method; self.path = path; self.route = resolvedRoute
        self.query = query; self.authentication = authentication; self.successStatuses = successStatuses
        self.majorParameter = majorParameter; self.usesGlobalLimit = usesGlobalLimit
        self.auditReason = auditReason; self.body = body; self.headers = headers
        self.retrySafety = retrySafety; self.readPolicy = readPolicy; self.invalidates = invalidates; self.bulk = bulk; self.decode = decode
        accountedMetadataBytes = metadataBytes
    }

    /// Creates a request for one attempt and attaches credentials only to Discord's fixed origin.
    /// - Parameters:
    ///   - credential: Bot or bearer credential accepted by this operation; `.none` policies omit it entirely.
    ///   - userAgent: Nonempty control-free DiscordBot library identification supplied by the client.
    /// - Returns: A version-10 request with newly owned replayable-body stream.
    /// - Throws: Safe validation errors for credential-policy mismatch or invalid user-agent text.
    public func makeRequest(credential: Credential, userAgent: String) throws -> HTTPRequest {
        guard !userAgent.isEmpty, !userAgent.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw DiscordError.validation(.invalidValue) }
        var wireHeaders = [HTTPHeader(name: "User-Agent", value: userAgent)] + headers
        switch (authentication, credential) {
        case (.none, _): break
        case (.bot, .bot(let token)), (.botOrBearer, .bot(let token)):
            wireHeaders.append(token.withUnsafeValue { HTTPHeader(name: "Authorization", value: "Bot " + $0) })
        case (.bearer, .bearer(let token)), (.botOrBearer, .bearer(let token)):
            wireHeaders.append(token.withUnsafeValue { HTTPHeader(name: "Authorization", value: "Bearer " + $0) })
        default: throw DiscordError.validation(.missingValue)
        }
        if let auditReason { wireHeaders.append(HTTPHeader(name: "X-Audit-Log-Reason", value: percentEncode(auditReason))) }
        if let body { wireHeaders.append(HTTPHeader(name: "Content-Type", value: body.contentType)) }
        let pathText = path.map { percentEncode($0).replacingOccurrences(of: "%40", with: "@") }.joined(separator: "/")
        let queryText = query.map { field in percentEncode(field.name) + (field.value.map { "=" + percentEncode($0) } ?? "") }.joined(separator: "&")
        guard let url = URL(string: "https://discord.com/api/v10/" + pathText + (query.isEmpty ? "" : "?" + queryText))
        else { throw DiscordError.validation(.invalidValue) }
        return HTTPRequest(method: method, url: url, headers: wireHeaders, body: try body?.makeStream())
    }

    /// Builds a raw escape-hatch descriptor while rejecting origin changes and encoded traversal.
    /// - Parameters:
    ///   - method: Uppercase method token.
    ///   - relativeRoute: Leading-slash relative path, excluding query, fragment, authority and version prefix.
    ///     Percent escapes are decoded once and re-encoded; encoded delimiters/traversal fail.
    ///   - query: Separately supplied raw query fields, preserving order and repeats.
    ///   - authentication: Credential category accepted by this operation.
    ///   - successStatuses: Explicit expected successful statuses, default `[200]`.
    ///   - body: Optional bounded replayable body.
    ///   - retrySafety: Explicit operation replay policy, default `.unsafe`.
    ///   - decode: Complete-body decoder; raw access makes no endpoint-parity claim.
    /// - Returns: A descriptor following the same authentication/rate/retry pipeline as typed operations.
    /// - Throws: Safe validation errors for malformed, escaping or absolute routes.
    public static func raw(
        method: String, relativeRoute: String, query: [QueryItem] = [],
        authentication: AuthenticationPolicy = .botOrBearer, successStatuses: Set<Int> = [200],
        body: RequestBody? = nil, retrySafety: RetrySafety = .unsafe,
        decode: @escaping @Sendable (Data) throws -> Response
    ) throws -> Self {
        guard relativeRoute.hasPrefix("/"), !relativeRoute.hasPrefix("//"),
              !relativeRoute.contains("?"), !relativeRoute.contains("#"), !relativeRoute.contains(":")
        else { throw DiscordError.validation(.invalidValue) }
        let segments = relativeRoute.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        var path: [String] = []
        for segment in segments {
            guard let decoded = String(segment).removingPercentEncoding, !decoded.contains("%")
            else { throw DiscordError.validation(.invalidValue) }
            path.append(decoded)
        }
        return try Self(method: method, path: path, query: query, authentication: authentication,
                        successStatuses: successStatuses, body: body, retrySafety: retrySafety, decode: decode)
    }

    /// An unambiguous request/response-contract identity for authentication-scoped byte reuse.
    /// Contains sensitive path/query/body data and must never be emitted as diagnostics or metric labels.
    /// Expected success statuses are included because reuse stores response bytes after status validation.
    /// The client must separately partition by credential identity and scope generation, then invoke
    /// each caller's decoder on the reused bytes; decoder closures are deliberately not compared.
    /// Descriptors sharing this identity must use equivalent decoder validation: the initiating
    /// decoder validates a shared exchange before its bytes become reusable. Disable reuse or use
    /// distinct response wrapper types when custom decoders accept incompatible payloads.
    public var cacheIdentity: String {
        let fields = [method, String(reflecting: Response.self), authentication.rawValue, String(path.count)] + path + ["?", String(query.count)] +
            query.flatMap { [$0.name, $0.value == nil ? "nil" : "value", $0.value ?? ""] } +
            ["success", String(successStatuses.count)] + successStatuses.sorted().map(String.init) +
            ["headers", String(headers.count)] + headers.flatMap { [$0.name.lowercased(), $0.value] } +
            ["body", body == nil ? "nil" : "value", body?.isStreaming == true ? "stream" : "stored", body?.contentType ?? "", body?.bytes.base64EncodedString() ?? "", auditReason == nil ? "nil" : "value", auditReason ?? ""]
        return fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    /// Redacts all request-specific values during ordinary formatting.
    public var description: String { "Endpoint(redacted)" }
    /// Uses the same safe marker during debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing stored request or decode captures.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
