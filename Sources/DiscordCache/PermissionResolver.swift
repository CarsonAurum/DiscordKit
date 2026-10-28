// File: Sources/DiscordCache/PermissionResolver.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordBits
import DiscordCore
import DiscordModels

/// Caller-supplied guild permission facts, independent of any particular cache.
/// Missing roles are not interpreted as roles with zero permissions. Callers must
/// supply a coherent, current snapshot; no result establishes server authorization.
public struct PermissionGuildState: Sendable, Equatable {
    /// Guild whose `@everyone` role has the same numeric identifier.
    public let id: GuildID
    /// Known owner, or nil when ownership has not been established.
    public let ownerID: UserID?
    /// Known exact role permissions, including `@everyone`; unrelated roles may be omitted.
    public let roles: [RoleID: UnsignedBitSet]

    /// Stores independently acquired immutable guild facts without fetching missing data.
    /// - Parameters:
    ///   - id: Guild identifier, including all unsigned snowflake bits.
    ///   - ownerID: Known owner or nil for incomplete ownership state.
    ///   - roles: Exact role bitsets. Resolution needs `@everyone` and each member role;
    ///     all unknown high permission bits are retained. Defaults to no known roles.
    /// Construction is synchronous, performs no I/O, and does not validate freshness.
    public init(id: GuildID, ownerID: UserID?, roles: [RoleID: UnsignedBitSet] = [:]) {
        self.id = id
        self.ownerID = ownerID
        self.roles = roles
    }
}

/// Caller-supplied membership and timeout facts for one guild member.
public struct PermissionMemberState: Sendable, Equatable {
    /// Guild establishing the scope of these facts.
    public let guildID: GuildID
    /// User being evaluated; this is not a credential or diagnostic identity.
    public let userID: UserID
    /// Complete assigned role set, or nil when assignments are incomplete.
    public let roleIDs: Set<RoleID>?
    /// Whether the member is currently timed out, or nil when the current state is unknown.
    public let timeoutActive: Bool?

    /// Stores member facts with explicit missing-state semantics.
    /// - Parameters:
    ///   - guildID: Guild containing the member; must match the supplied guild state.
    ///   - userID: Member whose permissions are evaluated.
    ///   - roleIDs: Complete assigned roles, excluding or including `@everyone`;
    ///     an empty set means no additional roles, nil means incomplete.
    ///   - timeoutActive: Caller-evaluated timeout at its chosen instant. False must
    ///     mean known inactive, not merely that a partial payload omitted the field.
    /// No clock is read, no tasks are created, and no freshness guarantee is inferred.
    public init(guildID: GuildID, userID: UserID, roleIDs: Set<RoleID>?, timeoutActive: Bool?) {
        self.guildID = guildID
        self.userID = userID
        self.roleIDs = roleIDs
        self.timeoutActive = timeoutActive
    }
}

/// A channel overwrite with arbitrary-width allow and deny masks.
public struct PermissionOverwrite: Sendable, Equatable {
    /// Distinct role/member target namespaces; future target types cannot be silently ignored.
    public enum Target: Sendable, Hashable {
        /// A guild role, including `@everyone`.
        case role(RoleID)
        /// A guild member.
        case member(UserID)
        /// An unrecognized wire discriminator and exact identifier.
        case unknown(type: Int, id: UInt64)
    }

    /// Exact overwrite target; duplicate targets make a complete list inconsistent.
    public let target: Target
    /// Bits added after removing denied bits; allow wins a same-stage collision.
    public let allow: UnsignedBitSet
    /// Bits removed before applying allowed bits.
    public let deny: UnsignedBitSet

    /// Stores one overwrite, without narrowing, fetching, or establishing authorization.
    /// - Parameters:
    ///   - target: Role, member, or future discriminator retained from the source.
    ///   - allow: Bits to allow, including future high bits; defaults to zero.
    ///   - deny: Bits to deny, including future high bits; defaults to zero.
    /// Both masks may contain a bit; Discord's deny-then-allow ordering applies.
    public init(target: Target, allow: UnsignedBitSet = .init(), deny: UnsignedBitSet = .init()) {
        self.target = target
        self.allow = allow
        self.deny = deny
    }
}

/// Caller-supplied channel permission facts with explicit thread and obfuscation state.
/// Category permissions are synchronized server-side rather than recursively inherited.
public struct PermissionChannelState: Sendable, Equatable {
    /// Channel or thread being evaluated.
    public let id: ChannelID
    /// Guild scope; direct-message channels are outside this resolver's contract.
    public let guildID: GuildID
    /// Exact channel type, retaining future values as indeterminate inputs.
    public let type: RawValue<ChannelType>
    /// Complete overwrite list, or nil for incomplete data; threads use their parent's list.
    public let overwrites: [PermissionOverwrite]?
    /// Whether source metadata was obfuscated and its overwrite list may be synthetic.
    public let isObfuscated: Bool
    /// Required parent identifier for threads; category parent IDs are not inherited.
    public let parentID: ChannelID?
    /// Known private-thread membership of the evaluated user, or nil when unknown.
    public let threadMember: Bool?
    /// Known thread lock state, or nil when unavailable; ignored for nonthreads.
    public let threadLocked: Bool?
    /// Known archive state, or nil when unavailable; ignored for nonthreads.
    public let threadArchived: Bool?

    /// Stores channel facts synchronously, preserving absence without implicit defaults.
    /// - Parameters:
    ///   - id: Exact channel identifier.
    ///   - guildID: Guild containing the channel and optional thread parent.
    ///   - type: Exact response discriminator. Unknown or nonguild types are indeterminate.
    ///   - overwrites: Complete list, including empty, or nil for missing/partial data.
    ///     Thread-local overwrites are ignored because threads inherit the parent list.
    ///   - isObfuscated: True for `CHANNEL_OBFUSCATED`; defaults to false only when
    ///     the caller has established that the supplied facts are unobfuscated.
    ///   - parentID: Thread parent, or optional category for a nonthread; defaults to nil.
    ///   - threadMember: Whether the evaluated member belongs to a private thread;
    ///     defaults to unknown and is unnecessary for public threads or moderators.
    ///   - threadLocked: Thread lock fact; defaults to unknown.
    ///   - threadArchived: Thread archive fact; defaults to unknown.
    /// This value does not prove visibility, membership completeness, or freshness.
    public init(id: ChannelID, guildID: GuildID, type: RawValue<ChannelType>,
                overwrites: [PermissionOverwrite]? = nil, isObfuscated: Bool = false,
                parentID: ChannelID? = nil, threadMember: Bool? = nil,
                threadLocked: Bool? = nil, threadArchived: Bool? = nil) {
        self.id = id
        self.guildID = guildID
        self.type = type
        self.overwrites = overwrites
        self.isObfuscated = isObfuscated
        self.parentID = parentID
        self.threadMember = threadMember
        self.threadLocked = threadLocked
        self.threadArchived = threadArchived
    }
}

/// Synchronous work bounds for supplied permission facts, applied before bitwise work.
public struct PermissionResolutionLimits: Sendable, Equatable {
    /// Maximum supplied role dictionary entries and assigned member role identifiers.
    public let maximumRoles: Int
    /// Maximum overwrites per supplied channel, even for irrelevant targets.
    public let maximumOverwrites: Int
    /// Maximum width in bits of any supplied mask; unknown bits remain supported within this bound.
    public let maximumBitWidth: Int
    /// Maximum sum of all supplied mask widths, bounding aggregate bitwise input work.
    public let maximumTotalBitWidth: Int
    /// Default bounds: 1,024 roles/overwrites, 65,536 bits per mask, 1,048,576 total bits.
    public static let `default` = Self()

    /// Stores resource bounds; invalid configurations resolve to `.invalidLimits`.
    /// - Parameters:
    ///   - maximumRoles: Inclusive nonnegative role count, at most 65,536; defaults to 1,024.
    ///   - maximumOverwrites: Inclusive nonnegative overwrite count, at most 65,536; defaults to 1,024.
    ///   - maximumBitWidth: Positive per-mask bound, at most 1,048,576; defaults to 65,536.
    ///   - maximumTotalBitWidth: Positive aggregate bound, at most 16,777,216; defaults to 1,048,576.
    /// Zero counts intentionally disallow roles or overwrites; zero bit-width bounds
    /// are invalid. Construction performs no allocation proportional to these bounds.
    public init(maximumRoles: Int = 1_024, maximumOverwrites: Int = 1_024,
                maximumBitWidth: Int = 65_536, maximumTotalBitWidth: Int = 1_048_576) {
        self.maximumRoles = maximumRoles
        self.maximumOverwrites = maximumOverwrites
        self.maximumBitWidth = maximumBitWidth
        self.maximumTotalBitWidth = maximumTotalBitWidth
    }
}

/// Why an exact calculation cannot be made from the supplied facts; no identifiers or payloads leak.
public enum PermissionIndeterminacy: Sendable, Equatable {
    /// Invalid or excessive resolver configuration.
    case invalidLimits
    /// Supplied counts, individual bit widths, or aggregate bit widths exceed configured limits.
    case resourceLimit
    /// Member/channel/parent guild IDs disagree or the thread parent relationship is invalid.
    case inconsistentScope
    /// Ownership was not established, so owner bypass cannot be ruled out.
    case missingOwner
    /// Member role assignment is incomplete.
    case missingMemberRoles
    /// `@everyone` or at least one assigned role's permissions are missing.
    case missingRole
    /// Current timeout state has not been established for a nonowner/nonadministrator.
    case missingTimeout
    /// Channel kind is unknown, nonguild, or not a supported thread parent kind.
    case unsupportedChannel
    /// Obfuscated metadata contains synthetic permission facts.
    case obfuscatedChannel
    /// A nonthread channel's full overwrite list has not been supplied.
    case missingOverwrites
    /// Overwrite targets contain an unknown discriminator or duplicate target.
    case inconsistentOverwrites
    /// A thread's matching parent channel is absent.
    case missingParent
    /// Private-thread membership is unknown for a nonmoderator with parent access.
    case missingThreadMembership
    /// Thread lock or archive state is missing.
    case missingThreadMetadata
}

/// Exact arithmetic over caller facts, or an explicit refusal to invent missing state.
public enum PermissionResolution: Sendable, Equatable {
    /// Supplied facts suffice for the implemented calculation; this does not authorize an action.
    case resolved(ResolvedPermissions)
    /// Retry only after establishing the missing facts or correcting invalid input/bounds.
    case indeterminate(PermissionIndeterminacy)
}

/// Permission arithmetic with documented implicit denials, retaining unknown bits.
/// Results describe supplied facts only. Role hierarchy, MFA, verification, member
/// screening, channel visibility exceptions, application-command permissions,
/// quarantines, voice connection state and endpoint-specific constraints remain
/// separate. Cached data may become stale immediately; Discord remains authoritative.
public struct ResolvedPermissions: Sendable, Equatable {
    /// Exact base/overwrite bits before implicit restrictions for ordinary results.
    /// During bypass this retains only observed finite bits needed to establish
    /// ADMINISTRATOR, or zero for ownership; it is never a finite `ALL` mask and
    /// need not include roles whose facts were unnecessary for bypass.
    public let rawPermissions: UnsignedBitSet
    /// Bits after known channel/thread/timeout restrictions; unknown bits survive
    /// except timeout's explicit all-except-VIEW/READ restriction.
    public let permissions: UnsignedBitSet
    /// Owner/administrator bypass, represented without inventing a finite `ALL` mask.
    public let unrestricted: Bool

    /// Records a resolver result without claiming endpoint-level permission.
    /// - Parameters:
    ///   - rawPermissions: Exact observed arithmetic before implicit restrictions.
    ///   - permissions: Calculated bits after the supported restrictions.
    ///   - unrestricted: Whether guild ownership or base ADMINISTRATOR bypasses masks.
    /// Only the resolver creates values, so callers cannot assert trusted completeness.
    fileprivate init(rawPermissions: UnsignedBitSet, permissions: UnsignedBitSet, unrestricted: Bool) {
        self.rawPermissions = rawPermissions
        self.permissions = permissions
        self.unrestricted = unrestricted
    }

    /// Checks arithmetic inclusion, honoring owner/administrator bypass at any bit width.
    /// - Parameter required: Finite required bitset, including unknown high bits or zero.
    /// - Returns: True for bypass, empty requirements, or a subset of `permissions`.
    /// This pure linear bitset operation is not an authorization guarantee. Unknown
    /// bits have no inferred implicit semantics and may carry additional server rules.
    public func includes(_ required: UnsignedBitSet) -> Bool {
        unrestricted || required.isSubset(of: permissions)
    }
}

/// Pure, bounded API v10 guild/channel permission arithmetic with no cache ownership.
/// Verified 2026-10-16 against the official Permissions and Threads references and
/// the 2026-08-12 Channel Obfuscation change (effective 2026-11-16).
/// Sources: <https://docs.discord.com/developers/topics/permissions>,
/// <https://docs.discord.com/developers/topics/threads>,
/// <https://docs.discord.com/developers/change-log#channel-obfuscation-for-users-and-bots>.
/// No REST/Gateway requests, rate admission, retries, I/O, suspension or clock reads
/// occur. Supply fresh coherent facts independently; cached results cannot authorize
/// operations. Every input is immutable and safe for concurrent independent callers.
public enum PermissionResolver {
    /// Known channel-scoped flags from the current reference; future bits are not truncated.
    private static let channelMask = mask([0, 4, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
                                          20, 21, 22, 23, 24, 25, 28, 29, 31, 32, 33, 34, 35,
                                          36, 37, 38, 39, 42, 44, 45, 46, 48, 49, 50, 51, 52])
    /// Documented send-dependent capabilities, plus direct message payload capabilities.
    private static let sendMask = mask([12, 14, 15, 17, 46, 49])
    /// Voice actions requiring connection; guild moderation and text-chat bits are retained.
    private static let connectMask = mask([4, 8, 9, 21, 22, 23, 24, 25, 32, 39, 42, 45, 48])
    /// Timeout explicitly removes every other permission, including future flags.
    private static let timeoutMask = mask([10, 16])

    /// Calculates base roles, owner/admin bypass, overwrites, and supported implicit restrictions.
    /// - Parameters:
    ///   - guild: Ownership and exact known role masks; all referenced roles must be present.
    ///   - member: Complete role assignments and current timeout fact for the same guild.
    ///   - channel: Optional guild channel; nil requests guild-level calculation only.
    ///   - parentChannel: Matching thread parent, required for threads; category
    ///     parents are deliberately ignored because category syncing is not inheritance.
    ///   - limits: Positive bounded work configuration; defaults to conservative limits.
    /// - Returns: Exact supported arithmetic or a sanitized indeterminate reason.
    /// Owner/admin bypass does not require overwrite, timeout or thread facts. Other
    /// members require complete role and timeout state. Channel overwrites apply in
    /// everyone, aggregate-role, then member order, denying before allowing per stage.
    /// Threads inherit parent overwrites and use SEND_MESSAGES_IN_THREADS. Private
    /// access additionally requires membership or MANAGE_THREADS and parent VIEW.
    /// Locked threads suppress sending for nonmoderators; archived threads suppress
    /// new reactions/commands while unlocked sending can automatically unarchive.
    /// Selected masks are folded in ascending width, so bitwise work is linear in
    /// aggregate supplied width rather than role count times the widest mask.
    /// Sorting uses O(n log n) comparisons and bounded O(n) temporary metadata for
    /// selected roles/overwrites. No cache, global state, tasks or ownership changes.
    public static func resolve(guild: PermissionGuildState, member: PermissionMemberState,
                               channel: PermissionChannelState? = nil,
                               parentChannel: PermissionChannelState? = nil,
                               limits: PermissionResolutionLimits = .default) -> PermissionResolution {
        if let failure = validateBounds(guild: guild, member: member, channel: channel,
                                        parent: parentChannel, limits: limits) {
            return .indeterminate(failure)
        }
        guard member.guildID == guild.id,
              channel == nil || channel?.guildID == guild.id,
              parentChannel == nil || parentChannel?.guildID == guild.id else {
            return .indeterminate(.inconsistentScope)
        }
        if let channel {
            guard let type = channel.type.knownValue, supported(type) else {
                return .indeterminate(.unsupportedChannel)
            }
        }
        if guild.ownerID == member.userID { return resolved(.init(), unrestricted: true) }
        let everyone = RoleID(rawValue: guild.id.rawValue)
        let everyonePermissions = guild.roles[everyone] ?? .init()
        if everyonePermissions.contains(3) { return resolved(everyonePermissions, unrestricted: true) }
        guard let roles = member.roleIDs else { return .indeterminate(.missingMemberRoles) }
        var roleMasks = [everyonePermissions]
        var missingRole = guild.roles[everyone] == nil
        for role in roles where role != everyone {
            if let bits = guild.roles[role] { roleMasks.append(bits) }
            else { missingRole = true }
        }
        var permissions = aggregate(roleMasks)
        if permissions.contains(3) { return resolved(permissions, unrestricted: true) }
        guard guild.ownerID != nil else { return .indeterminate(.missingOwner) }
        guard !missingRole else { return .indeterminate(.missingRole) }
        guard let timedOut = member.timeoutActive else { return .indeterminate(.missingTimeout) }
        guard let channel else {
            return resolved(permissions, effective: timedOut ? permissions.intersection(timeoutMask) : permissions)
        }
        guard !channel.isObfuscated else { return .indeterminate(.obfuscatedChannel) }
        guard let type = channel.type.knownValue, supported(type) else {
            return .indeterminate(.unsupportedChannel)
        }
        let thread = isThread(type)
        let source: PermissionChannelState
        if thread {
            guard let parentID = channel.parentID, let parent = parentChannel else {
                return .indeterminate(.missingParent)
            }
            guard parent.id == parentID, parent.id != channel.id else {
                return .indeterminate(.inconsistentScope)
            }
            guard let parentType = parent.type.knownValue, validParent(parentType, thread: type) else {
                return .indeterminate(.unsupportedChannel)
            }
            guard !parent.isObfuscated else { return .indeterminate(.obfuscatedChannel) }
            source = parent
        } else {
            source = channel
        }
        guard let overwrites = source.overwrites else { return .indeterminate(.missingOverwrites) }
        var seen: Set<PermissionOverwrite.Target> = []
        var roleAllows: [UnsignedBitSet] = [], roleDenies: [UnsignedBitSet] = []
        var everyoneOverwrite: PermissionOverwrite?, memberOverwrite: PermissionOverwrite?
        for overwrite in overwrites {
            guard seen.insert(overwrite.target).inserted else { return .indeterminate(.inconsistentOverwrites) }
            switch overwrite.target {
            case .unknown: return .indeterminate(.inconsistentOverwrites)
            case .role(let id) where id == everyone: everyoneOverwrite = overwrite
            case .role(let id) where roles.contains(id):
                roleAllows.append(overwrite.allow)
                roleDenies.append(overwrite.deny)
            case .member(let id) where id == member.userID: memberOverwrite = overwrite
            default: break
            }
        }
        if let overwrite = everyoneOverwrite {
            permissions = permissions.subtracting(overwrite.deny).union(overwrite.allow)
        }
        permissions = permissions.subtracting(aggregate(roleDenies)).union(aggregate(roleAllows))
        if let overwrite = memberOverwrite {
            permissions = permissions.subtracting(overwrite.deny).union(overwrite.allow)
        }
        let raw = permissions
        if thread {
            guard let locked = channel.threadLocked, let archived = channel.threadArchived else {
                return .indeterminate(.missingThreadMetadata)
            }
            let moderator = permissions.contains(34)
            if type == .privateThread, permissions.contains(10), !moderator {
                guard let membership = channel.threadMember else {
                    return .indeterminate(.missingThreadMembership)
                }
                if !membership { permissions = permissions.subtracting(channelMask) }
            }
            // SEND_MESSAGES does not inherit into threads; it never substitutes for bit 38.
            permissions = permissions.subtracting(mask([11]))
            if locked && !moderator { permissions = permissions.subtracting(mask([38])) }
            if archived { permissions = permissions.subtracting(mask([6, 31])) }
        }
        if !permissions.contains(10) { permissions = permissions.subtracting(channelMask) }
        if !permissions.contains(thread ? 38 : 11) { permissions = permissions.subtracting(sendMask) }
        if (type == .guildVoice || type == .guildStageVoice) && !permissions.contains(20) {
            permissions = permissions.subtracting(connectMask)
        }
        if timedOut { permissions = permissions.intersection(timeoutMask) }
        return resolved(raw, effective: permissions)
    }

    /// Validates bounded counts and widths before any growing aggregate operation.
    /// - Parameters:
    ///   - guild: All supplied role masks, including irrelevant roles.
    ///   - member: Assigned role identifiers, including optional incomplete state.
    ///   - channel: Target channel, including its supplied thread-local overwrite masks.
    ///   - parent: Supplied parent; irrelevant parents still count toward the input budget.
    ///   - limits: Configuration to validate and apply.
    /// - Returns: First sanitized bound failure, or nil when all supplied data fits.
    /// Addition is bounded by the aggregate cap before it occurs, preventing overflow.
    private static func validateBounds(guild: PermissionGuildState, member: PermissionMemberState,
                                       channel: PermissionChannelState?, parent: PermissionChannelState?,
                                       limits: PermissionResolutionLimits) -> PermissionIndeterminacy? {
        guard (0...65_536).contains(limits.maximumRoles),
              (0...65_536).contains(limits.maximumOverwrites),
              (1...1_048_576).contains(limits.maximumBitWidth),
              (1...16_777_216).contains(limits.maximumTotalBitWidth) else { return .invalidLimits }
        guard guild.roles.count <= limits.maximumRoles,
              (member.roleIDs?.count ?? 0) <= limits.maximumRoles,
              (channel?.overwrites?.count ?? 0) <= limits.maximumOverwrites,
              (parent?.overwrites?.count ?? 0) <= limits.maximumOverwrites else { return .resourceLimit }
        var remaining = limits.maximumTotalBitWidth
        for bits in guild.roles.values {
            guard bits.bitWidth <= limits.maximumBitWidth, bits.bitWidth <= remaining else { return .resourceLimit }
            remaining -= bits.bitWidth
        }
        for value in [channel, parent] {
            for overwrite in value?.overwrites ?? [] {
                for bits in [overwrite.allow, overwrite.deny] {
                    guard bits.bitWidth <= limits.maximumBitWidth, bits.bitWidth <= remaining else { return .resourceLimit }
                    remaining -= bits.bitWidth
                }
            }
        }
        return nil
    }

    /// Identifies supported guild channel kinds without accepting direct-message/future types.
    /// - Parameter type: Recognized channel discriminator.
    /// - Returns: Whether guild permission arithmetic is meaningful for this kind.
    private static func supported(_ type: ChannelType) -> Bool {
        switch type {
        case .dm, .groupDM, .guildDirectory: false
        default: true
        }
    }

    /// Distinguishes the three thread kinds from ordinary guild channels.
    /// - Parameter type: Recognized channel discriminator.
    /// - Returns: True for announcement, public, or private thread kinds.
    private static func isThread(_ type: ChannelType) -> Bool {
        type == .announcementThread || type == .publicThread || type == .privateThread
    }

    /// Validates current Discord thread-to-parent kinds instead of recursing through arbitrary graphs.
    /// - Parameters:
    ///   - parent: Recognized supplied parent kind.
    ///   - thread: Recognized target thread kind.
    /// - Returns: True only for announcement/announcement, private/text, or public/text/forum/media.
    private static func validParent(_ parent: ChannelType, thread: ChannelType) -> Bool {
        switch thread {
        case .announcementThread: parent == .guildAnnouncement
        case .privateThread: parent == .guildText
        case .publicThread: parent == .guildText || parent == .guildForum || parent == .guildMedia
        default: false
        }
    }

    /// Unions selected masks without repeatedly scanning a wide accumulator for narrow inputs.
    /// - Parameter masks: Known role or same-stage overwrite masks; may be empty, zero,
    ///   repeated or arbitrarily ordered. Count/width limits have already been validated.
    /// - Returns: Exact union, preserving unknown bits and leaving inputs unchanged.
    /// Sorting by ascending width makes each nonempty fold scan only the next input's
    /// width. Bitwise work is therefore linear in aggregate input words, with O(n log n)
    /// comparisons and bounded O(n) temporary references to copy-on-write values.
    private static func aggregate(_ masks: [UnsignedBitSet]) -> UnsignedBitSet {
        var result = UnsignedBitSet()
        for bits in masks.sorted(by: { $0.bitWidth < $1.bitWidth }) where !bits.isEmpty {
            result = result.isEmpty ? bits : result.union(bits)
        }
        return result
    }

    /// Builds small trusted constant masks without parsing or fallible runtime configuration.
    /// - Parameter bits: Internal positions below 64, established by the reviewed permission table.
    /// - Returns: Exact union of these known positions in the arbitrary-width container.
    private static func mask(_ bits: [Int]) -> UnsignedBitSet {
        UnsignedBitSet(bits.reduce(UInt64(0)) { $0 | (UInt64(1) << $1) })
    }

    /// Wraps raw/effective arithmetic in a result while retaining an explicit unbounded bypass.
    /// - Parameters:
    ///   - raw: Exact computed finite bits, or zero when ownership alone establishes bypass.
    ///   - effective: Normalized bits; nil means use raw bits unchanged.
    ///   - unrestricted: Owner/administrator bypass; defaults to false.
    /// - Returns: A resolved value with no authorization or freshness assertion.
    private static func resolved(_ raw: UnsignedBitSet, effective: UnsignedBitSet? = nil,
                                 unrestricted: Bool = false) -> PermissionResolution {
        .resolved(.init(rawPermissions: raw, permissions: effective ?? raw, unrestricted: unrestricted))
    }
}
