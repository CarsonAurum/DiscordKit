import DiscordCore
import DiscordGateway
import Foundation

/// Shared credential-scoped startup/opcode ownership, independent of client lifetime.
/// Reuse this same instance for every in-process client using one bot credential.
/// Distributed deployments inject external startup/opcode coordinators and lease stores;
/// this actor never falls back to a fresh authority after coordinator failure.
public actor ClientAuthority<C: Clock> where C.Duration == Duration {
    public nonisolated let botID: UserID
    public nonisolated let cacheIdentity: String
    public nonisolated let budget: ClientResourceBudget
    public nonisolated let commands: any GatewayCommandCoordinator
    private let clock: C
    private var startup: (any GatewayStartupCoordinator)?

    /// Stores authorities without discovery, network I/O or task creation.
    /// - Parameters:
    ///   - botID: Public bot matching the REST credential; the caller verifies that association.
    ///   - clock: Monotonic clock shared with clients and leases.
    ///   - budget: Aggregate ledger, share across identities when bounding the whole process.
    ///   - cacheIdentity: Opaque nonsecret credential-generation identity, default random UUID.
    ///     Rotate this value with credentials; never supply a token.
    ///   - startup: Optional shared external fail-closed startup authority. Nil seeds one local
    ///     coordinator from the first discovery and conservatively refreshes it thereafter.
    ///   - commands: Optional shared external opcode authority; nil creates bounded local state.
    /// - Throws: Local opcode-coordinator configuration validation failures.
    public init(botID: UserID, clock: C, budget: ClientResourceBudget,
                cacheIdentity: String = UUID().uuidString,
                startup: (any GatewayStartupCoordinator)? = nil,
                commands: (any GatewayCommandCoordinator)? = nil) throws {
        self.botID = botID; self.clock = clock; self.budget = budget
        self.cacheIdentity = cacheIdentity; self.startup = startup
        self.commands = try commands ?? InProcessGatewayCommandCoordinator(botID: botID, clock: clock)
    }

    /// Obtains one retained startup ledger; discovery cannot reset active quota/bucket windows.
    /// - Parameter discovery: Current authenticated v10 server allowances.
    /// - Returns: Retained external or in-process shared authority.
    /// - Throws: Conservative local refresh validation failures; no replacement is attempted.
    public func startupCoordinator(discovery: GatewayDiscovery) async throws -> any GatewayStartupCoordinator {
        if let local = startup as? InProcessGatewayStartupCoordinator<C> {
            try await local.refresh(discovery.sessionStartLimit)
            return local
        }
        if let startup { return startup }
        let local = InProcessGatewayStartupCoordinator(botID: botID, limit: discovery.sessionStartLimit, clock: clock)
        startup = local
        return local
    }
}
