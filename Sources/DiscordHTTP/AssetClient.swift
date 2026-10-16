import DiscordCore
import DiscordTransport
import Foundation

/// Credential-free HTTPS asset retrieval, deliberately separate from authenticated REST execution.
/// The supplied send-once transport must reject/fail redirects rather than follow them silently,
/// as the owned Foundation and NIO adapters do. No authorization/header customization is exposed.
public struct AssetClient<T: HTTPTransport>: Sendable {
    private let transport: T
    private let maximumBytes: Int

    /// Stores a send-once transport and a complete-response byte bound.
    /// - Parameters:
    ///   - transport: Injectable transport; pools remain owned by its creator.
    ///   - maximumBytes: Positive per-asset cap, default 8 MiB.
    /// - Throws: Safe validation errors for a nonpositive response bound.
    public init(transport: T, maximumBytes: Int = 8_388_608) throws {
        guard maximumBytes > 0 else { throw DiscordError.validation(.invalidValue) }
        self.transport = transport; self.maximumBytes = maximumBytes
    }

    /// Retrieves one bounded HTTPS asset without attaching Discord credentials.
    /// - Parameters:
    ///   - url: Absolute HTTPS URL with a host and no username, password or fragment.
    ///   - context: Caller-owned clock, cancellation and optional absolute deadline.
    /// - Returns: Complete asset bytes for HTTP 200; empty assets are permitted.
    /// - Throws: Safe URL validation failures, transport/cancellation/deadline failures,
    ///   body-limit errors, or `APIResponseError` for every non-200 status including redirects.
    ///
    /// There is one exchange, no redirect following, no retry and no implicit asset cache.
    /// Asset requests intentionally do not participate in authenticated REST rate budgets.
    public func get<C: Clock>(_ url: URL, context: TransportContext<C>) async throws -> Data where C.Duration == Duration {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil
        else { throw DiscordError.validation(.invalidValue) }
        let transport = self.transport
        let maximumBytes = self.maximumBytes
        return try await context.run {
            let response = try await transport.execute(HTTPRequest(method: "GET", url: url), context: context)
            let bytes = try await ResponseBody.collect(response.body, maximumBytes: maximumBytes)
            guard response.status == 200 else { throw APIResponseError(status: response.status, headers: response.headers, body: bytes) }
            return bytes
        }
    }
}
