// File: Tests/DiscordCacheTests/PermissionResolverTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordBits
import DiscordCore
import DiscordModels
import Testing
@testable import DiscordCache

/// Deterministic permission arithmetic over independent complete/partial snapshots.
/// Fixtures use no cache, credentials, networking, clocks, or time-dependent sleeps.
@Suite struct PermissionResolverTests {
    /// Exact known/high-bit construction shared by fixtures; inputs stay below default resource bounds.
    /// - Parameter values: Zero-based bit indices; duplicates are harmless.
    /// - Returns: Arbitrary-width bitset preserving every requested position.
    /// - Throws: Bitset validation errors for invalid fixture positions.
    private func bits(_ values: [Int]) throws -> UnsignedBitSet {
        try UnsignedBitSet(bits: values)
    }

    /// Builds a coherent guild fixture with known ownership and an explicit everyone role.
    /// - Parameters:
    ///   - everyone: Exact base permissions, default zero.
    ///   - roles: Additional exact role masks; fixtures may replace everyone deliberately.
    ///   - owner: Known guild owner, default user 99; nil tests incomplete ownership.
    /// - Returns: Guild 1 with deterministic merged role data.
    private func guild(_ everyone: UnsignedBitSet = .init(), roles: [RoleID: UnsignedBitSet] = [:],
                       owner: UserID? = .init(rawValue: 99)) -> PermissionGuildState {
        var all = [RoleID(rawValue: 1): everyone]
        all.merge(roles) { _, new in new }
        return .init(id: .init(rawValue: 1), ownerID: owner, roles: all)
    }

    /// Builds member facts while exposing missing-role and timeout branches explicitly.
    /// - Parameters:
    ///   - roles: Complete role set, empty by default; nil means incomplete.
    ///   - timeout: Known inactive by default; nil means current timeout is unknown.
    ///   - user: Evaluated user, default 2; user 99 exercises ownership.
    ///   - scope: Guild ID, default 1; alternate values exercise scope mismatch.
    /// - Returns: Immutable supplied membership facts without permission inference.
    private func member(roles: Set<RoleID>? = [], timeout: Bool? = false,
                        user: UInt64 = 2, scope: UInt64 = 1) -> PermissionMemberState {
        .init(guildID: .init(rawValue: scope), userID: .init(rawValue: user),
              roleIDs: roles, timeoutActive: timeout)
    }

    /// Builds a known-type channel with complete empty overwrites and thread metadata.
    /// - Parameters:
    ///   - type: Known kind, default text.
    ///   - overwrites: Complete overwrite list, empty by default; nil means incomplete.
    ///   - parent: Optional thread/category parent, absent by default.
    ///   - membership: Known private membership, unknown by default.
    ///   - locked: Known lock state, false by default; nil means incomplete.
    ///   - archived: Known archive state, false by default; nil means incomplete.
    ///   - id: Channel ID, default 10; parents use a different ID.
    ///   - scope: Guild ID, default 1; alternate values test invalid scope.
    ///   - obfuscated: Whether overwrite facts are synthetic, false by default.
    /// - Returns: Pure channel permission facts without cache coupling.
    private func channel(_ type: ChannelType = .guildText, overwrites: [PermissionOverwrite]? = [],
                         parent: UInt64? = nil, membership: Bool? = nil,
                         locked: Bool? = false, archived: Bool? = false,
                         id: UInt64 = 10, scope: UInt64 = 1, obfuscated: Bool = false) -> PermissionChannelState {
        .init(id: .init(rawValue: id), guildID: .init(rawValue: scope), type: .init(type),
              overwrites: overwrites, isObfuscated: obfuscated,
              parentID: parent.map { ChannelID(rawValue: $0) }, threadMember: membership,
              threadLocked: locked, threadArchived: archived)
    }

    /// Extracts successful arithmetic and turns an unexpected indeterminate branch into test failure.
    /// - Parameter resolution: Result being asserted by the caller's meaningful bit/state checks.
    /// - Returns: The exact resolved value.
    /// - Throws: A fixture error when resolution did not succeed.
    private func resolved(_ resolution: PermissionResolution) throws -> ResolvedPermissions {
        guard case .resolved(let value) = resolution else { throw UnexpectedResolution.indeterminate }
        return value
    }

    /// An unexpected resolver failure should fail the enclosing test without hiding payloads.
    private enum UnexpectedResolution: Error { case indeterminate }

    /// Construction preserves known, absent, empty, future and unsigned-ID facts without normalization.
    @Test func suppliedFactsPreserveTheirExactSemantics() throws {
        let huge = UInt64.max
        let overwrite = PermissionOverwrite(target: .unknown(type: 77, id: huge))
        #expect(overwrite.allow.isEmpty && overwrite.deny.isEmpty)
        let supplied = PermissionChannelState(id: .init(rawValue: huge), guildID: .init(rawValue: 1),
                                             type: .init(rawValue: 99))
        #expect(supplied.id.rawValue == huge && supplied.type.rawValue == 99)
        #expect(supplied.overwrites == nil && supplied.parentID == nil)
        #expect(supplied.threadMember == nil && supplied.threadLocked == nil && supplied.threadArchived == nil)
        #expect(!supplied.isObfuscated)
        let suppliedGuild = PermissionGuildState(id: .init(rawValue: 1), ownerID: nil)
        #expect(suppliedGuild.ownerID == nil && suppliedGuild.roles.isEmpty)
        #expect(member(roles: nil, timeout: nil).roleIDs == nil)
        let limits = PermissionResolutionLimits.default
        #expect(limits.maximumRoles == 1_024 && limits.maximumOverwrites == 1_024)
        #expect(limits.maximumBitWidth == 65_536 && limits.maximumTotalBitWidth == 1_048_576)
    }

    /// Empty but complete guild state produces zero and includes the empty requirement only.
    @Test func completeEmptyPermissions() throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(), member: member()))
        #expect(value.rawPermissions.isEmpty && value.permissions.isEmpty && !value.unrestricted)
        #expect(value.includes(.init()))
        #expect(!value.includes(try bits([10])))
        #expect(PermissionResolver.resolve(guild: guild(), member: member()) == .resolved(value))
    }

    /// Everyone and assigned roles union once; unrelated roles cannot grant permissions and high bits survive.
    @Test func guildRoleUnionPreservesArbitraryWidth() throws {
        let value = try resolved(PermissionResolver.resolve(
            guild: guild(try bits([10, 16, 100]), roles: [.init(rawValue: 3): try bits([11, 300]),
                                                        .init(rawValue: 4): try bits([5, 400])]),
            member: member(roles: [.init(rawValue: 1), .init(rawValue: 3)])))
        #expect(value.permissions == (try bits([10, 11, 16, 100, 300])))
        #expect(value.rawPermissions == value.permissions)
        #expect(value.includes(try bits([100, 300])))
        #expect(!value.includes(try bits([400])))
    }

    /// Ownership establishes unbounded bypass even when role, timeout and channel facts are absent.
    @Test func ownerBypassNeedsNoOtherPermissionFacts() throws {
        let value = try resolved(PermissionResolver.resolve(
            guild: .init(id: .init(rawValue: 1), ownerID: .init(rawValue: 99)),
            member: member(roles: nil, timeout: nil, user: 99),
            channel: channel(.privateThread, overwrites: nil, obfuscated: true)))
        #expect(value.unrestricted && value.rawPermissions.isEmpty)
        #expect(value.includes(try bits([1_000])))
    }

    /// A known assigned administrator role bypasses missing owner/other-role/channel/timeout facts.
    @Test func administratorBypassDoesNotInventFiniteAllMask() throws {
        let value = try resolved(PermissionResolver.resolve(
            guild: .init(id: .init(rawValue: 1), ownerID: nil,
                         roles: [.init(rawValue: 3): try bits([3, 500])]),
            member: member(roles: [.init(rawValue: 3), .init(rawValue: 4)], timeout: nil),
            channel: channel(.publicThread)))
        #expect(value.unrestricted && value.rawPermissions.contains(500))
        #expect(!value.permissions.contains(1_000))
        #expect(value.includes(try bits([1_000])))
        let everyoneAdmin = try resolved(PermissionResolver.resolve(guild: guild(try bits([3]), owner: nil),
            member: member(roles: nil, timeout: nil)))
        #expect(everyoneAdmin.unrestricted)
    }

    /// Missing ownership, assigned roles, role masks and timeout are explicitly indeterminate.
    @Test func incompleteGuildFactsNeverBecomeZeroPermissions() throws {
        #expect(PermissionResolver.resolve(guild: guild(owner: nil), member: member()) == .indeterminate(.missingOwner))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(roles: nil)) == .indeterminate(.missingMemberRoles))
        #expect(PermissionResolver.resolve(guild: .init(id: .init(rawValue: 1), ownerID: .init(rawValue: 99)),
                                           member: member()) == .indeterminate(.missingRole))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(roles: [.init(rawValue: 3)])) == .indeterminate(.missingRole))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(timeout: nil)) == .indeterminate(.missingTimeout))
    }

    /// Guild, member, channel and parent scopes must agree even for otherwise unrestricted owners.
    @Test func scopesRemainIndependentOfBypass() {
        #expect(PermissionResolver.resolve(guild: guild(), member: member(scope: 2)) == .indeterminate(.inconsistentScope))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(user: 99),
                                           channel: channel(scope: 2)) == .indeterminate(.inconsistentScope))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           parentChannel: channel(scope: 2)) == .indeterminate(.inconsistentScope))
    }

    /// Aggregate role allows beat another role's deny; member overwrite then has final precedence.
    @Test func overwritePrecedenceAggregatesRolesBeforeMember() throws {
        let role3 = RoleID(rawValue: 3), role4 = RoleID(rawValue: 4)
        let overwrites: [PermissionOverwrite] = [
            .init(target: .member(.init(rawValue: 2)), allow: try bits([16]), deny: try bits([11])),
            .init(target: .role(role3), deny: try bits([11, 16, 200])),
            .init(target: .role(.init(rawValue: 1)), deny: try bits([11, 16, 200])),
            .init(target: .role(role4), allow: try bits([11, 200])),
        ]
        let scope = guild(try bits([10, 11, 16, 200]), roles: [role3: .init(), role4: .init()])
        let subject = member(roles: [role3, role4])
        let value = try resolved(PermissionResolver.resolve(guild: scope, member: subject,
                                                            channel: channel(overwrites: overwrites)))
        #expect(value.rawPermissions == (try bits([10, 16, 200])))
        #expect(value.permissions == value.rawPermissions)
        let reversed = try resolved(PermissionResolver.resolve(guild: scope, member: subject,
                                                               channel: channel(overwrites: overwrites.reversed())))
        #expect(value == reversed)
    }

    /// Each stage applies deny then allow, and unrelated role/member overwrites have no effect.
    @Test func overwriteAllowWinsSameStageAndUnrelatedTargetsAreIgnored() throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 11])), member: member(),
            channel: channel(overwrites: [
                .init(target: .role(.init(rawValue: 1)), allow: try bits([16]), deny: try bits([16])),
                .init(target: .member(.init(rawValue: 2)), allow: try bits([200]), deny: try bits([200])),
                .init(target: .role(.init(rawValue: 3)), allow: try bits([3]), deny: try bits([10])),
                .init(target: .member(.init(rawValue: 3)), allow: try bits([3]), deny: try bits([10])),
            ])))
        #expect(value.permissions == (try bits([10, 11, 16, 200])))
        #expect(!value.unrestricted)
    }

    /// An overwrite can add the numeric administrator bit without establishing guild-level bypass.
    @Test func overwrittenAdministratorDoesNotBypassFurtherDenials() throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(), member: member(),
            channel: channel(overwrites: [.init(target: .role(.init(rawValue: 1)), allow: try bits([3, 11]))])))
        #expect(!value.unrestricted && value.permissions.contains(3))
        #expect(!value.permissions.contains(11))
    }

    /// Unknown types and duplicate overwrite targets cannot be accepted as complete permission state.
    @Test func inconsistentOverwritesAreIndeterminate() {
        let duplicate = PermissionOverwrite(target: .role(.init(rawValue: 1)))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           channel: channel(overwrites: [duplicate, duplicate])) == .indeterminate(.inconsistentOverwrites))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           channel: channel(overwrites: [.init(target: .unknown(type: 7, id: 2))])) == .indeterminate(.inconsistentOverwrites))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           channel: channel(overwrites: nil)) == .indeterminate(.missingOverwrites))
    }

    /// Known nonguild/directory and future channel kinds are rejected without calculating guessed semantics.
    /// - Parameter rawType: Each known unsupported or unknown channel discriminator.
    @Test(arguments: [1, 3, 14, 99]) func unsupportedChannelTypes(rawType: Int) {
        let target = PermissionChannelState(id: .init(rawValue: 10), guildID: .init(rawValue: 1),
                                            type: .init(rawValue: rawType), overwrites: [])
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: target) == .indeterminate(.unsupportedChannel))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(user: 99), channel: target) == .indeterminate(.unsupportedChannel))
    }

    /// Obfuscated channels and parents carry synthetic overwrites and must not calculate another user's permissions.
    @Test func obfuscatedMetadataIsExplicitlyIndeterminate() {
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           channel: channel(obfuscated: true)) == .indeterminate(.obfuscatedChannel))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(),
                                           channel: channel(.publicThread, parent: 20),
                                           parentChannel: channel(id: 20, obfuscated: true)) == .indeterminate(.obfuscatedChannel))
    }

    /// Denied viewing clears known channel capabilities while retaining guild and unknown permissions verbatim.
    @Test func implicitViewDenialPreservesGuildAndUnknownBits() throws {
        let raw = try bits([1, 4, 6, 11, 13, 16, 20, 28, 31, 34, 38, 42, 50, 51, 52, 400])
        let value = try resolved(PermissionResolver.resolve(guild: guild(raw), member: member(), channel: channel()))
        #expect(value.rawPermissions == raw)
        #expect(value.permissions == (try bits([1, 400])))
    }

    /// Send-dependent message capabilities disappear when base sending is denied; history/reactions persist.
    @Test func implicitSendDenial() throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(try bits([6, 10, 12, 14, 15, 16, 17, 46, 49, 500])),
                                                            member: member(), channel: channel()))
        #expect(value.permissions == (try bits([6, 10, 16, 500])))
        #expect(value.rawPermissions.contains(12))
    }

    /// Voice/stage connection denial suppresses connection-dependent actions without removing channel chat.
    /// - Parameter type: Both guild voice and Stage variants share the CONNECT restriction.
    /// - Throws: Fixture bitset validation or unexpected indeterminate-result errors.
    @Test(arguments: [ChannelType.guildVoice, .guildStageVoice])
    func implicitConnectDenial(type: ChannelType) throws {
        let raw = try bits([4, 8, 9, 10, 11, 16, 21, 22, 23, 24, 25, 32, 39, 42, 45, 48, 500])
        let value = try resolved(PermissionResolver.resolve(guild: guild(raw), member: member(), channel: channel(type)))
        #expect(value.permissions == (try bits([10, 11, 16, 500])))
        let connected = try resolved(PermissionResolver.resolve(guild: guild(raw.union(try bits([20]))), member: member(), channel: channel(type)))
        #expect(connected.permissions == raw.union(try bits([20])))
    }

    /// Category parents never recursively overwrite a child's independently supplied synchronized permissions.
    @Test func categorySyncIsNotInheritance() throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 11])), member: member(),
            channel: channel(parent: 20),
            parentChannel: channel(.guildCategory, overwrites: [.init(target: .role(.init(rawValue: 1)), deny: try bits([10]))], id: 20)))
        #expect(value.permissions == (try bits([10, 11])))
        let category = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 11])), member: member(), channel: channel(.guildCategory)))
        #expect(category.permissions.contains(10))
    }

    /// Timeout removes every known and future bit except existing view/history, without granting absent bits.
    @Test func timeoutRestrictsGuildAndChannelWithoutInventingView() throws {
        let source = guild(try bits([1, 10, 11, 16, 400]))
        let guildValue = try resolved(PermissionResolver.resolve(guild: source, member: member(timeout: true)))
        #expect(guildValue.permissions == (try bits([10, 16])))
        #expect(guildValue.rawPermissions.contains(400))
        let denied = try resolved(PermissionResolver.resolve(guild: source, member: member(timeout: true),
            channel: channel(overwrites: [.init(target: .member(.init(rawValue: 2)), deny: try bits([10]))])))
        #expect(denied.permissions.isEmpty)
        let admin = try resolved(PermissionResolver.resolve(guild: guild(try bits([3])), member: member(timeout: true)))
        #expect(admin.unrestricted)
    }

    /// Valid public/announcement thread parent pairs inherit parent overwrites and use thread-specific sending.
    /// - Parameters:
    ///   - thread: Public or announcement thread kind under test.
    ///   - parent: Each compatible text, forum, media or announcement parent.
    /// - Throws: Fixture bitset validation or unexpected indeterminate-result errors.
    @Test(arguments: [(ChannelType.publicThread, ChannelType.guildText), (.publicThread, .guildForum),
                      (.publicThread, .guildMedia), (.announcementThread, .guildAnnouncement)])
    func threadParentPermissions(thread: ChannelType, parent: ChannelType) throws {
        let value = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 14, 15])), member: member(),
            channel: channel(thread, overwrites: nil, parent: 20),
            parentChannel: channel(parent, overwrites: [.init(target: .role(.init(rawValue: 1)), allow: try bits([38]))], id: 20)))
        #expect(value.permissions == (try bits([10, 14, 15, 38])))
        #expect(value.rawPermissions == value.permissions)
    }

    /// Parent SEND_MESSAGES neither grants thread sending nor removes independent thread payload capabilities.
    @Test func threadSendingDoesNotInheritSendMessages() throws {
        let unable = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 11, 12, 14, 15, 17])), member: member(),
            channel: channel(.publicThread, parent: 20), parentChannel: channel(id: 20)))
        #expect(unable.permissions == (try bits([10])))
        #expect(unable.rawPermissions.contains(11))
        let able = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 12, 14, 15, 17, 38])), member: member(),
            channel: channel(.publicThread, parent: 20), parentChannel: channel(id: 20)))
        #expect(able.permissions == (try bits([10, 12, 14, 15, 17, 38])))
    }

    /// Missing, mismatched, self-referential and incompatible thread parents are rejected explicitly.
    @Test func invalidThreadParentFacts() {
        let target = channel(.publicThread, parent: 20)
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: target) == .indeterminate(.missingParent))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: channel(.publicThread),
                                           parentChannel: channel(id: 20)) == .indeterminate(.missingParent))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: target,
                                           parentChannel: channel(id: 30)) == .indeterminate(.inconsistentScope))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: channel(.publicThread, parent: 10),
                                           parentChannel: channel(id: 10)) == .indeterminate(.inconsistentScope))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: target,
                                           parentChannel: channel(.guildCategory, id: 20)) == .indeterminate(.unsupportedChannel))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: channel(.privateThread, parent: 20),
                                           parentChannel: channel(.guildForum, id: 20)) == .indeterminate(.unsupportedChannel))
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: channel(.announcementThread, parent: 20),
                                           parentChannel: channel(id: 20)) == .indeterminate(.unsupportedChannel))
    }

    /// Private access needs known membership unless MANAGE_THREADS is present, and still requires parent view.
    @Test func privateThreadMembershipAndModeratorRules() throws {
        let source = guild(try bits([10, 16, 38]))
        let target = channel(.privateThread, parent: 20)
        let parent = channel(id: 20)
        #expect(PermissionResolver.resolve(guild: source, member: member(), channel: target,
                                           parentChannel: parent) == .indeterminate(.missingThreadMembership))
        let joined = try resolved(PermissionResolver.resolve(guild: source, member: member(),
            channel: channel(.privateThread, parent: 20, membership: true), parentChannel: parent))
        #expect(joined.permissions == (try bits([10, 16, 38])))
        let absent = try resolved(PermissionResolver.resolve(guild: source, member: member(),
            channel: channel(.privateThread, parent: 20, membership: false), parentChannel: parent))
        #expect(absent.permissions.isEmpty)
        let moderator = try resolved(PermissionResolver.resolve(guild: guild(try bits([10, 16, 34, 38])), member: member(),
            channel: target, parentChannel: parent))
        #expect(moderator.permissions == (try bits([10, 16, 34, 38])))
        let hidden = try resolved(PermissionResolver.resolve(guild: guild(try bits([16, 34, 38])), member: member(),
            channel: channel(.privateThread, parent: 20, membership: true), parentChannel: parent))
        #expect(hidden.permissions.isEmpty)
    }

    /// Thread metadata absence remains distinct from known unlocked/active state.
    @Test func missingThreadMetadata() {
        for target in [channel(.publicThread, parent: 20, locked: nil),
                       channel(.publicThread, parent: 20, archived: nil)] {
            #expect(PermissionResolver.resolve(guild: guild(), member: member(), channel: target,
                                               parentChannel: channel(id: 20)) == .indeterminate(.missingThreadMetadata))
        }
    }

    /// Locking denies nonmoderator sends even when active; unlocked archived sends can automatically unarchive.
    /// - Parameters:
    ///   - locked: Known thread lock state, covering both alternatives.
    ///   - archived: Known archive state, crossed with each lock state.
    /// - Throws: Fixture bitset validation or unexpected indeterminate-result errors.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func threadLockAndArchiveRestrictions(locked: Bool, archived: Bool) throws {
        let source = try bits([6, 10, 14, 31, 38])
        let value = try resolved(PermissionResolver.resolve(guild: guild(source), member: member(),
            channel: channel(.publicThread, parent: 20, locked: locked, archived: archived), parentChannel: channel(id: 20)))
        #expect(value.permissions.contains(38) == !locked)
        #expect(value.permissions.contains(14) == !locked)
        #expect(value.permissions.contains(6) == !archived)
        #expect(value.permissions.contains(31) == !archived)
        #expect(value.rawPermissions == source)
        let moderator = try resolved(PermissionResolver.resolve(guild: guild(source.union(try bits([34]))), member: member(),
            channel: channel(.publicThread, parent: 20, locked: locked, archived: archived), parentChannel: channel(id: 20)))
        #expect(moderator.permissions.contains(38))
    }

    /// Invalid count and width configurations reject before arithmetic and cannot overflow signed integers.
    /// - Parameter limits: Negative, zero-width and above-hard-cap configurations.
    @Test(arguments: [
        PermissionResolutionLimits(maximumRoles: -1), PermissionResolutionLimits(maximumRoles: 65_537),
        PermissionResolutionLimits(maximumOverwrites: -1), PermissionResolutionLimits(maximumOverwrites: Int.max),
        PermissionResolutionLimits(maximumBitWidth: 0), PermissionResolutionLimits(maximumBitWidth: 1_048_577),
        PermissionResolutionLimits(maximumTotalBitWidth: 0), PermissionResolutionLimits(maximumTotalBitWidth: Int.max),
    ]) func invalidLimits(limits: PermissionResolutionLimits) {
        #expect(PermissionResolver.resolve(guild: guild(), member: member(), limits: limits) == .indeterminate(.invalidLimits))
    }

    /// Counts, widths, aggregate width and even irrelevant supplied masks honor exact inclusive budgets.
    @Test func resourceBoundsAreEnforcedBeforeArithmetic() throws {
        let source = guild(try bits([7]))
        #expect(PermissionResolver.resolve(guild: source, member: member(),
                                           limits: .init(maximumRoles: 0)) == .indeterminate(.resourceLimit))
        #expect(PermissionResolver.resolve(guild: source, member: member(roles: [.init(rawValue: 3), .init(rawValue: 4)]),
                                           limits: .init(maximumRoles: 1)) == .indeterminate(.resourceLimit))
        #expect(PermissionResolver.resolve(guild: source, member: member(),
                                           limits: .init(maximumBitWidth: 7)) == .indeterminate(.resourceLimit))
        #expect(PermissionResolver.resolve(guild: source, member: member(),
                                           limits: .init(maximumTotalBitWidth: 7)) == .indeterminate(.resourceLimit))
        let exact = try resolved(PermissionResolver.resolve(guild: source, member: member(),
            limits: .init(maximumRoles: 1, maximumOverwrites: 0, maximumBitWidth: 8, maximumTotalBitWidth: 8)))
        #expect(exact.permissions == (try bits([7])))
        let overwrite = PermissionOverwrite(target: .member(.init(rawValue: 3)), allow: try bits([7]), deny: try bits([7]))
        #expect(PermissionResolver.resolve(guild: source, member: member(), channel: channel(overwrites: [overwrite]),
                                           limits: .init(maximumOverwrites: 0)) == .indeterminate(.resourceLimit))
        #expect(PermissionResolver.resolve(guild: source, member: member(), parentChannel: channel(overwrites: [overwrite]),
                                           limits: .init(maximumOverwrites: 0)) == .indeterminate(.resourceLimit))
        #expect(PermissionResolver.resolve(guild: source, member: member(), channel: channel(overwrites: [overwrite]),
                                           limits: .init(maximumTotalBitWidth: 23)) == .indeterminate(.resourceLimit))
        let exactAggregate = try resolved(PermissionResolver.resolve(guild: source, member: member(),
            channel: channel(overwrites: [overwrite]), limits: .init(maximumTotalBitWidth: 24)))
        #expect(exactAggregate.rawPermissions == (try bits([7])))
        let wide = PermissionOverwrite(target: .member(.init(rawValue: 3)), allow: try bits([100]))
        #expect(PermissionResolver.resolve(guild: source, member: member(), channel: channel(overwrites: [wide]),
                                           limits: .init(maximumBitWidth: 100)) == .indeterminate(.resourceLimit))
        let excessive = guild(try bits([65_536]))
        #expect(PermissionResolver.resolve(guild: excessive, member: member()) == .indeterminate(.resourceLimit))
    }

    /// Wide roles and overwrites aggregate with many narrow masks within the same exact input-width budget.
    /// This regression uses caller-raised bounds without timing assertions: the highest input
    /// arrives before narrow overwrite masks, whose role denies still aggregate before allows.
    /// - Throws: Bitset construction or unexpected indeterminate resolution failures.
    @Test func wideAndNarrowMasksShareBoundedAggregation() throws {
        let highest = 1_048_575, count = 4_096
        let narrow = try bits([0, 1])
        var suppliedRoles: [RoleID: UnsignedBitSet] = [.init(rawValue: 1): try bits([10, highest])]
        var assignments: Set<RoleID> = []
        var overwrites: [PermissionOverwrite] = []
        for index in 2...count {
            let id = RoleID(rawValue: UInt64(index))
            assignments.insert(id)
            suppliedRoles[id] = narrow
            overwrites.append(.init(target: .role(id),
                allow: index == 2 ? try bits([highest - 1]) : try bits([0]),
                deny: index == 2 ? try bits([0]) : try bits([1])))
        }
        let result = try resolved(PermissionResolver.resolve(
            guild: .init(id: .init(rawValue: 1), ownerID: .init(rawValue: 99), roles: suppliedRoles),
            member: member(roles: assignments), channel: channel(overwrites: overwrites),
            limits: .init(maximumRoles: count, maximumOverwrites: count,
                          maximumBitWidth: highest + 1, maximumTotalBitWidth: 3_000_000)))
        #expect(result.rawPermissions == (try bits([0, 10, highest - 1, highest])))
        #expect(result.permissions == result.rawPermissions && !result.unrestricted)
    }

    /// Independent concurrent calculations share no mutable state and produce the same exact high bits.
    @Test func concurrentPureCalculationsAreDeterministic() async throws {
        let source = guild(try bits([10, 11, 500]))
        let subject = member(), target = channel()
        let expected = PermissionResolver.resolve(guild: source, member: subject, channel: target)
        await withTaskGroup(of: PermissionResolution.self) { group in
            for _ in 0..<32 {
                group.addTask { PermissionResolver.resolve(guild: source, member: subject, channel: target) }
            }
            for await value in group { #expect(value == expected) }
        }
    }
}
