import DiscordCore
import DiscordTransport
import Foundation

/// Atomic nonblocking admission for a bot's resource-scoped Gateway commands.
public enum GatewayCommandAdmission: Sendable, Equatable {
    case admitted
    case limited(retryAfter: Duration)
}

/// Shared per-bot command authority, independent of HTTP and Identify scheduling.
/// Distributed implementations must atomically preserve all-member guild cooldowns across
/// workers and topology handoffs, fail closed on outage, and never log command payloads.
public protocol GatewayCommandCoordinator: Sendable {
    /// Reserves an application command before its possibly ambiguous write.
    /// - Parameters:
    ///   - command: Validated command; all-member requests consume one guild allowance.
    ///   - shard: Current fenced owner, used to validate bot identity and guild routing.
    /// - Returns: Immediate admission or a positive caller-visible retry delay; no queue is created.
    /// - Throws: Cancellation, invalid scope, bounded metadata exhaustion or coordinator outage.
    func reserve(_ command: GatewayCommand, for shard: ShardIdentity) async throws -> GatewayCommandAdmission

    /// Retains a server-reported opcode/resource cooldown without shortening an existing one.
    /// - Parameters:
    ///   - opcode: Rate-limited opcode, including future numeric values.
    ///   - guildID: Resource scope when the server supplies it; nil means opcode-wide.
    ///   - retryAfter: Finite positive delay of at most one day, in monotonic time.
    /// - Throws: Cancellation, invalid delay, metadata exhaustion or coordinator outage.
    func recordLimit(opcode: GatewayOpcode, guildID: GuildID?, retryAfter: Duration) async throws
}

/// Bounded in-process command authority. Share one instance per bot across all shard
/// owners and replacements; a fresh instance cannot recover historical allowances.
public actor InProcessGatewayCommandCoordinator<C: Clock>: GatewayCommandCoordinator where C.Duration == Duration {
    private struct Key: Hashable {
        let opcode: Int
        let guildID: GuildID?
        var fullMembersOnly = false
    }
    private let botID: UserID
    private let clock: C
    private let maximumEntries: Int
    private var deadlines: [Key: C.Instant] = [:]

    /// Stores one bot's finite monotonic cooldown map without launching work.
    /// - Parameters:
    ///   - botID: Nonsecret identity shared by every participating shard.
    ///   - clock: Injected monotonic time; must share the owner's time domain.
    ///   - maximumEntries: Positive resource/opcode metadata cap, default 4,096.
    /// - Throws: `GatewayFailure.invalidConfiguration` for a nonpositive cap.
    public init(botID: UserID, clock: C, maximumEntries: Int = 4_096) throws {
        guard maximumEntries > 0 else { throw GatewayFailure.invalidConfiguration }
        self.botID = botID; self.clock = clock; self.maximumEntries = maximumEntries
    }

    /// Atomically checks all applicable server limits and the documented one-per-guild,
    /// per-bot 30-second all-member allowance. Cancellation never refunds admission.
    /// - Parameters:
    ///   - command: Validated command; only empty-query/zero-limit members consume this allowance.
    ///   - shard: Matching bot and correct guild shard; wrong routing fails before mutation.
    /// - Returns: Immediate admission or remaining cooldown, without suspending for time.
    /// - Throws: Cancellation, invalid scope or finite metadata exhaustion.
    public func reserve(_ command: GatewayCommand, for shard: ShardIdentity) throws -> GatewayCommandAdmission {
        try Task.checkCancellation()
        guard shard.botID == botID, command.guildIDs.allSatisfy({ shard.routes($0) }) else {
            throw GatewayFailure.invalidConfiguration
        }
        prune()
        var keys = [Key(opcode: command.opcode.rawValue, guildID: nil)]
            + command.guildIDs.map { Key(opcode: command.opcode.rawValue, guildID: $0) }
        if command.requestsAllGuildMembers, let guild = command.guildIDs.first {
            keys.append(Key(opcode: command.opcode.rawValue, guildID: nil, fullMembersOnly: true))
            keys.append(Key(opcode: command.opcode.rawValue, guildID: guild, fullMembersOnly: true))
        }
        if let deadline = keys.compactMap({ deadlines[$0] }).max() {
            return .limited(retryAfter: clock.now.duration(to: deadline))
        }
        if command.requestsAllGuildMembers, let guild = command.guildIDs.first {
            try retain(Key(opcode: command.opcode.rawValue, guildID: guild, fullMembersOnly: true), until: clock.now.advanced(by: .seconds(30)))
        }
        return .admitted
    }

    /// Applies known opcode-eight cooldowns to full-list requests only; other opcode metadata
    /// applies conservatively to its entire supplied scope and remains bounded.
    /// - Parameters:
    ///   - opcode: Exact numeric opcode.
    ///   - guildID: Optional resource scope supplied by RATE_LIMITED.
    ///   - retryAfter: Positive delay through 86,400 seconds; larger/untrusted values fail closed.
    /// - Throws: Cancellation, invalid payload or bounded metadata exhaustion.
    public func recordLimit(opcode: GatewayOpcode, guildID: GuildID?, retryAfter: Duration) throws {
        try Task.checkCancellation()
        guard retryAfter > .zero, retryAfter <= .seconds(86_400) else { throw GatewayFailure.invalidPayload }
        prune()
        try retain(Key(opcode: opcode.rawValue, guildID: guildID, fullMembersOnly: opcode == .requestGuildMembers), until: clock.now.advanced(by: retryAfter))
    }

    /// Reports live cooldown metadata after removing expired records, for resource accounting.
    /// - Returns: Retained records, always at or below the configured cap.
    public func retainedEntryCount() -> Int { prune(); return deadlines.count }

    /// Removes expired metadata on demand without timers or background tasks.
    private func prune() { deadlines = deadlines.filter { $0.value > clock.now } }

    /// Extends one record atomically after checking the aggregate cap.
    /// - Parameters:
    ///   - key: Bot-local resource/opcode key.
    ///   - deadline: Monotonic expiry; an existing later expiry wins.
    /// - Throws: `GatewayFailure.commandCapacityExceeded` when a new record exceeds the cap.
    private func retain(_ key: Key, until deadline: C.Instant) throws {
        guard deadlines[key] != nil || deadlines.count < maximumEntries else { throw GatewayFailure.commandCapacityExceeded }
        deadlines[key] = max(deadlines[key] ?? deadline, deadline)
    }
}
