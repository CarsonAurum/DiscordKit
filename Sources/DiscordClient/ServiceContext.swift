import DiscordCore
import DiscordHTTP

/// Sendable typed REST service access, usable independently of Gateway readiness.
/// Resource models remain immutable snapshots with no hidden client references.
public struct ServiceContext<C: Clock>: Sendable where C.Duration == Duration {
    public let rest: RESTClient<C>
    private let invalidateEntities: @Sendable () async -> Void

    /// Binds explicit service and optional entity invalidation owners without starting work.
    /// - Parameters:
    ///   - rest: Shared authenticated REST executor and rate authority.
    ///   - invalidateEntities: Conservative scope invalidation for local writes, default no cache.
    public init(rest: RESTClient<C>, invalidateEntities: @escaping @Sendable () async -> Void = {}) {
        self.rest = rest; self.invalidateEntities = invalidateEntities
    }

    /// Executes any typed service descriptor under existing HTTP authentication/rate/retry rules.
    /// Local writes invalidate entity projections before and after the operation, including
    /// ambiguous failures. Reads do not invalidate. Direct `rest` access bypasses entity
    /// invalidation and requires explicit cache invalidation by the caller.
    /// - Parameters:
    ///   - endpoint: Typed fetch/mutation descriptor, including its API v10 endpoint contract.
    ///   - deadline: Optional total monotonic deadline in the REST executor's clock domain.
    /// - Returns: Descriptor's decoded immutable result, including explicit empty/null semantics.
    /// - Throws: REST validation, authentication, API, admission, transport, cancellation or
    ///   indeterminate mutation failures. Unsafe mutations are never blindly replayed.
    public func execute<Response: Sendable>(_ endpoint: Endpoint<Response>, deadline: C.Instant? = nil) async throws -> Response {
        let mutation = endpoint.method != "GET" && endpoint.method != "HEAD"
        if mutation { await invalidateEntities() }
        do {
            let result = try await rest.execute(endpoint, deadline: deadline)
            if mutation { await invalidateEntities() }
            return result
        } catch {
            if mutation { await invalidateEntities() }
            throw error
        }
    }
}
