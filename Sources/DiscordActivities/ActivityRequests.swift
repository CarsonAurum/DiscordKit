// File: Sources/DiscordActivities/ActivityRequests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Console levels accepted by the SDK CAPTURE_LOG command. Logging is explicit; no global console interception occurs.
public enum ActivityLogLevel: String, Sendable, CaseIterable { case log, warn, debug, info, error }

/// Supported outgoing orientation locks. Unknown incoming orientation values remain numeric payload values.
public enum ActivityOrientationLockState: Int, Sendable, CaseIterable { case unlocked = 1, portrait = 2, landscape = 3 }

/// Typed outgoing SET_ACTIVITY data, deliberately omitting response-only name, application and flags fields.
/// All SDK optional/nullable fields retain omission and null separately. Construction starts no I/O.
public struct ActivityPresenceUpdate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawFields: [String: JSONValue]

    /// Builds the SDK's reduced Rich Presence mutation shape without inventing REST or native-RPC behavior.
    /// - Parameters:
    ///   - state: Optional nullable status text; defaults to omission.
    ///   - stateURL: Optional nullable absolute URL associated with state; omission is the default.
    ///   - details: Optional nullable detail text; defaults to omission.
    ///   - detailsURL: Optional nullable absolute URL associated with details; omission is the default.
    ///   - timestamps: Optional nullable timestamp object; numbers preserve their original units and spelling.
    ///   - assets: Optional nullable assets object; defaults to omission.
    ///   - party: Optional nullable party object; defaults to omission.
    ///   - secrets: Optional nullable join/match secrets; defaults to omission and diagnostics redact values.
    ///   - instance: Optional nullable instance marker; defaults to omission.
    ///   - type: Optional nonnull numeric Activity type; defaults to omission; unknown numeric values are retained.
    /// - Throws: Invalid-arguments error for null type or malformed associated URLs, or whole-object JSON bounds errors.
    /// This value is not retried automatically. The host enforces rpc.activities.write authorization and rich-presence policy.
    public init(state: Field<String> = .absent, stateURL: Field<String> = .absent,
                details: Field<String> = .absent, detailsURL: Field<String> = .absent,
                timestamps: Field<ActivityTimestamps> = .absent, assets: Field<ActivityAssets> = .absent,
                party: Field<ActivityParty> = .absent, secrets: Field<ActivitySecrets> = .absent,
                instance: Field<Bool> = .absent, type: Field<JSONNumber> = .absent) throws {
        var fields: [String: JSONValue] = [:]
        try activityPut(&fields, "state", state, nullable: true, JSONValue.string)
        try activityPut(&fields, "state_url", stateURL, nullable: true, activityURL)
        try activityPut(&fields, "details", details, nullable: true, JSONValue.string)
        try activityPut(&fields, "details_url", detailsURL, nullable: true, activityURL)
        try activityPut(&fields, "timestamps", timestamps, nullable: true) { .object($0.rawFields) }
        try activityPut(&fields, "assets", assets, nullable: true) { .object($0.rawFields) }
        try activityPut(&fields, "party", party, nullable: true) { .object($0.rawFields) }
        try activityPut(&fields, "secrets", secrets, nullable: true) { .object($0.rawFields) }
        try activityPut(&fields, "instance", instance, nullable: true, JSONValue.bool)
        try activityPut(&fields, "type", type, nullable: false, JSONValue.number)
        _ = try JSONValue.object(fields).serialized()
        rawFields = fields
    }
    /// Conceals Activity text, links and secrets.
    public var description: String { "ActivityPresenceUpdate(redacted)" }
    /// Conceals Activity contents in debugger output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding Activity secrets and unknown fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Name/value option passed to source-only SHARE_INTERACTION.
public struct ActivityShareOption: Sendable, Equatable {
    public let name: String
    public let value: String

    /// Retains a command option verbatim; command-level byte bounds apply when building the request.
    /// - Parameters:
    ///   - name: Option name, with no upstream per-field range stated.
    ///   - value: String option value; no coercion is performed.
    public init(name: String, value: String) { self.name = name; self.value = value }
}

/// Preview image passed to source-only SHARE_INTERACTION.
public struct ActivitySharePreview: Sendable, Equatable {
    public let height: JSONNumber
    public let url: String
    public let width: JSONNumber

    /// Retains the generated schema's numeric dimensions without inferring units or integral-only constraints.
    /// - Parameters:
    ///   - height: Numeric height; the source schema has no minimum or integer constraint.
    ///   - url: Image URL string; final host validation remains authoritative.
    ///   - width: Numeric width with the same source constraints as height.
    public init(height: JSONNumber, url: String, width: JSONNumber) {
        self.height = height; self.url = url; self.width = width
    }
}

/// A button in a source-only SHARE_INTERACTION action row. The source supports styles 1 through 5.
public struct ActivityShareButton: Sendable, Equatable {
    public let style: Int
    public let label: Field<String>
    public let customID: Field<String>

    /// Validates the exact pinned button schema before the command can be emitted.
    /// - Parameters:
    ///   - style: Integral style in 1...5, inclusive.
    ///   - label: Optional nonnull label, at most 80 UTF-16 code units; defaults to omission.
    ///   - customID: Optional nonnull identifier, at most 100 UTF-16 code units; defaults to omission.
    /// - Throws: Invalid-arguments error for an unsupported style, null field or exceeded length.
    public init(style: Int, label: Field<String> = .absent, customID: Field<String> = .absent) throws {
        guard (1...5).contains(style) else { throw ActivityCatalogError.invalidArguments }
        _ = try activityLimited(label, maximum: 80)
        _ = try activityLimited(customID, maximum: 100)
        self.style = style; self.label = label; self.customID = customID
    }
}

/// An action row in SHARE_INTERACTION, with at most five optional buttons.
public struct ActivityShareRow: Sendable, Equatable {
    public let buttons: Field<[ActivityShareButton]>

    /// Validates a generated-schema action row without inventing a minimum button count.
    /// - Parameter buttons: Optional nonnull ordered buttons, at most five; defaults to omission.
    /// - Throws: Invalid-arguments error for null or more than five buttons.
    public init(buttons: Field<[ActivityShareButton]> = .absent) throws {
        if case .null = buttons { throw ActivityCatalogError.invalidArguments }
        if case .value(let values) = buttons, values.count > 5 { throw ActivityCatalogError.invalidArguments }
        self.buttons = buttons
    }
}

/// Typed factories for every exported SDK command. Construction starts no background tasks, connection or authentication.
/// All requests are bounded and immutable, and neither mutations nor purchases are retried automatically.
/// The host remains authoritative for approval, scopes, platform support and user consent.
public enum ActivityRequests {
    /// Requests the web-host hardware-acceleration prompt; unsupported mobile hosts reject execution.
    /// - Returns: A bounded descriptor decoding `ActivityHardwareAcceleration`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func encourageHardwareAcceleration() throws -> ActivityRequest<ActivityHardwareAcceleration> {
        try .init(command: .encourageHardwareAcceleration) { try ActivityHardwareAcceleration(value: $0) }
    }

    /// Reads current channel permissions under guilds.members.read. In a DM/GDM the SDK documents a zero bitset.
    /// - Returns: A bounded descriptor decoding `ActivityPermissions`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getChannelPermissions() throws -> ActivityRequest<ActivityPermissions> {
        try .init(command: .getChannelPermissions) { try ActivityPermissions(value: $0) }
    }

    /// Reads embedded-app entitlement display data. Fulfillment requires independent trusted server verification.
    /// - Returns: A bounded descriptor decoding `ActivityEntitlements`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getEntitlements() throws -> ActivityRequest<ActivityEntitlements> {
        try .init(command: .getEntitlements) { try ActivityEntitlements(value: $0) }
    }

    /// Reads optional platform behavior flags without assuming that any key remains permanently available.
    /// - Returns: A bounded descriptor decoding `ActivityPlatformBehaviors`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getPlatformBehaviors() throws -> ActivityRequest<ActivityPlatformBehaviors> {
        try .init(command: .getPlatformBehaviors) { try ActivityPlatformBehaviors(value: $0) }
    }

    /// Reads embedded-app SKUs for display. It does not authorize fulfillment or grant entitlements.
    /// - Returns: A bounded descriptor decoding `ActivitySKUs`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getSkus() throws -> ActivityRequest<ActivitySKUs> {
        try .init(command: .getSkus) { try ActivitySKUs(value: $0) }
    }

    /// Opens the invite dialog. Guild context and CREATE_INSTANT_INVITE permission are required; the host owns consent.
    /// - Returns: A bounded descriptor decoding `ActivityEmptyResponse`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func openInviteDialog() throws -> ActivityRequest<ActivityEmptyResponse> {
        try .init(command: .openInviteDialog) { try ActivityEmptyResponse(value: $0) }
    }

    /// Reads the current user locale under the identify scope, retaining unknown future locale spellings.
    /// - Returns: A bounded descriptor decoding `ActivityLocale`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func userSettingsGetLocale() throws -> ActivityRequest<ActivityLocale> {
        try .init(command: .userSettingsGetLocale) { try ActivityLocale(value: $0) }
    }

    /// Reads the Activity instance participants using the renamed SDK export and wire command.
    /// - Returns: A bounded descriptor decoding `ActivityParticipants`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getActivityInstanceConnectedParticipants() throws -> ActivityRequest<ActivityParticipants> {
        try .init(command: .getActivityInstanceConnectedParticipants) { try ActivityParticipants(value: $0) }
    }

    /// Reads source-only quest information; host availability and required scopes are unspecified.
    /// - Returns: A bounded descriptor decoding `ActivityQuest`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getQuest() throws -> ActivityRequest<ActivityQuest> {
        try .init(command: .getQuest) { try ActivityQuest(value: $0) }
    }

    /// Reads relationships under relationships.read. Current policy requires accepting Social SDK terms, without extra Discord approval.
    /// - Returns: A bounded descriptor decoding `ActivityRelationships`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func getRelationships() throws -> ActivityRequest<ActivityRelationships> {
        try .init(command: .getRelationships) { try ActivityRelationships(value: $0) }
    }

    /// Prompts the user to upload an image through the host. The returned attachment URL is ephemeral.
    /// - Returns: A bounded descriptor decoding `ActivityImageUpload`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func initiateImageUpload() throws -> ActivityRequest<ActivityImageUpload> {
        try .init(command: .initiateImageUpload) { try ActivityImageUpload(value: $0) }
    }

    /// Refreshes a source-only proxy ticket; host availability and required scopes are unspecified.
    /// - Returns: A bounded descriptor decoding `ActivityProxyTicket`; construction performs no I/O or background work.
    /// - Throws: Whole-arguments JSON bounds errors. Host permission, platform and user-consent errors occur at execution.
    /// This command has no pagination, automatic retry or implicit token exchange.
    public static func requestProxyTicketRefresh() throws -> ActivityRequest<ActivityProxyTicket> {
        try .init(command: .requestProxyTicketRefresh) { try ActivityProxyTicket(value: $0) }
    }

    /// Builds the historical connected-participants API name as a strict alias of the renamed export.
    /// - Returns: The same command, arguments and typed decoder as getActivityInstanceConnectedParticipants().
    /// - Throws: Whole-arguments JSON bounds errors propagated by the canonical factory.
    /// The rename was announced 2026-10-06; removal is deferred to an unspecified future major SDK release.
    @available(*, deprecated, renamed: "getActivityInstanceConnectedParticipants()")
    public static func getInstanceConnectedParticipants() throws -> ActivityRequest<ActivityParticipants> {
        try getActivityInstanceConnectedParticipants()
    }

    /// Builds AUTHORIZE after readiness, requesting a code for caller-owned backend exchange.
    /// - Parameters:
    ///   - clientID: Application ID string, retained exactly.
    ///   - scopes: Ordered OAuth scope names, including future spellings; an empty list is permitted by the source.
    ///   - codeChallenge: Optional nonnull PKCE S256 challenge; defaults to omission.
    ///   - state: Optional nonnull caller-generated CSRF state; defaults to omission.
    ///   - responseTypeCode: Whether to include the only supported response_type, `code`; defaults to true.
    ///   - promptNone: Whether to include the only supported prompt, `none`; defaults to false.
    /// - Returns: A descriptor decoding a redacted authorization-code projection.
    /// - Throws: Invalid-arguments error for forbidden nulls, or whole-arguments bounds errors.
    /// If a PKCE challenge is supplied, code_challenge_method is explicitly S256. OAuth state ownership remains with the caller.
    public static func authorize(clientID: String, scopes: [String], codeChallenge: Field<String> = .absent,
                                 state: Field<String> = .absent, responseTypeCode: Bool = true,
                                 promptNone: Bool = false) throws -> ActivityRequest<ActivityAuthorization> {
        var args: [String: JSONValue] = ["client_id": .string(clientID), "scope": .array(scopes.map(JSONValue.string))]
        try activityPut(&args, "code_challenge", codeChallenge, nullable: false, JSONValue.string)
        if case .value = codeChallenge { args["code_challenge_method"] = .string("S256") }
        try activityPut(&args, "state", state, nullable: false, JSONValue.string)
        if responseTypeCode { args["response_type"] = .string("code") }
        if promptNone { args["prompt"] = .string("none") }
        return try .init(command: .authorize, arguments: args) { try ActivityAuthorization(value: $0) }
    }

    /// Builds AUTHENTICATE using an optional nullable user OAuth token; no token exchange occurs here.
    /// - Parameter accessToken: Omitted by default; explicit null follows the generated SDK contract.
    /// - Returns: A descriptor decoding the token, user, scopes, expiry and application result with redacted diagnostics.
    /// - Throws: Whole-arguments JSON bounds errors. Token values must already pass ActivityUserAccessToken validation.
    public static func authenticate(accessToken: Field<ActivityUserAccessToken> = .absent) throws -> ActivityRequest<ActivityAuthentication> {
        var args: [String: JSONValue] = [:]
        try activityPut(&args, "access_token", accessToken, nullable: true) { .string($0.value) }
        return try .init(command: .authenticate, arguments: args) { try ActivityAuthentication(value: $0) }
    }

    /// Builds CAPTURE_LOG explicitly; it never intercepts global logging or forwards future logs automatically.
    /// - Parameters:
    ///   - level: One of the five SDK console levels.
    ///   - message: Exact message text, subject to whole-request bounds.
    /// - Returns: A nullable empty-object response descriptor.
    /// - Throws: Whole-arguments JSON bounds errors.
    public static func captureLog(level: ActivityLogLevel, message: String) throws -> ActivityRequest<ActivityEmptyResponse> {
        try .init(command: .captureLog, arguments: ["level": .string(level.rawValue), "message": .string(message)]) { try ActivityEmptyResponse(value: $0) }
    }

    /// Builds GET_CHANNEL. Guild channels require guilds; GDM additionally needs approved dm_channels.read.
    /// - Parameter channelID: Exact host channel ID string; no numeric conversion occurs.
    /// - Returns: A complete typed SDK channel response descriptor, including voice states and messages.
    /// - Throws: Whole-arguments JSON bounds errors. The host reports permissions or missing-channel failures at execution.
    public static func getChannel(channelID: String) throws -> ActivityRequest<ActivityChannel> {
        try .init(command: .getChannel, arguments: ["channel_id": .string(channelID)]) { try ActivityChannel(value: $0) }
    }

    /// Builds OPEN_EXTERNAL_LINK; the host owns confirmation and actual navigation.
    /// - Parameter url: Exact external URL string; host policy and scheme support remain authoritative.
    /// - Returns: A typed opened flag, preserving explicit null from older hosts.
    /// - Throws: Whole-arguments JSON bounds errors.
    public static func openExternalLink(url: String) throws -> ActivityRequest<ActivityExternalLink> {
        try .init(command: .openExternalLink, arguments: ["url": .string(url)]) { value in
            if value == .null { return try ActivityExternalLink(value: .object(["opened": .null])) }
            return try ActivityExternalLink(value: value)
        }
    }

    /// Builds SET_ACTIVITY with explicit null to clear Activity state according to the embedded SDK schema.
    /// - Parameter activity: Typed mutation or explicit null. This has no native local-RPC presence-clear semantics.
    /// - Returns: A descriptor decoding the common SDK Activity response.
    /// - Throws: Whole-arguments JSON bounds errors. The host enforces rpc.activities.write and presence restrictions.
    public static func setActivity(activity: Nullable<ActivityPresenceUpdate>) throws -> ActivityRequest<ActivityRichPresence> {
        let value: JSONValue
        switch activity { case .null: value = .null; case .value(let update): value = .object(update.rawFields) }
        return try .init(command: .setActivity, arguments: ["activity": value]) { try ActivityRichPresence(value: $0) }
    }

    /// Builds SET_CONFIG for the documented web host.
    /// - Parameter useInteractivePIP: Whether the host should enable interactive picture-in-picture.
    /// - Returns: A descriptor decoding the accepted configuration.
    /// - Throws: Whole-arguments JSON bounds errors; unsupported-host failures occur during execution.
    public static func setConfig(useInteractivePIP: Bool) throws -> ActivityRequest<ActivityConfig> {
        try .init(command: .setConfig, arguments: ["use_interactive_pip": .bool(useInteractivePIP)]) { try ActivityConfig(value: $0) }
    }

    /// Builds SET_ORIENTATION_LOCK_STATE for iOS/Android with explicit control of the legacy fallback shape.
    /// - Parameters:
    ///   - lockState: Main orientation lock.
    ///   - pictureInPictureLockState: Optional nullable PIP lock, omitted by default.
    ///   - gridLockState: Optional nullable grid lock, omitted by default.
    ///   - omitGridForLegacyHost: Explicitly removes grid_lock_state, default false. No automatic retry is performed.
    /// - Returns: A nullable empty-object response descriptor.
    /// - Throws: Whole-arguments JSON bounds errors.
    /// ActivityClient retries a numeric INVALID_PAYLOAD (4000) once without grid_lock_state under the original timeout.
    /// This descriptor performs no execution; omitGridForLegacyHost lets callers select the legacy shape directly.
    public static func setOrientationLockState(_ lockState: ActivityOrientationLockState,
        pictureInPictureLockState: Field<ActivityOrientationLockState> = .absent,
        gridLockState: Field<ActivityOrientationLockState> = .absent,
        omitGridForLegacyHost: Bool = false) throws -> ActivityRequest<ActivityEmptyResponse> {
        var args: [String: JSONValue] = ["lock_state": try activityInteger(lockState.rawValue)]
        try activityPut(&args, "picture_in_picture_lock_state", pictureInPictureLockState, nullable: true) { try activityInteger($0.rawValue) }
        if !omitGridForLegacyHost {
            try activityPut(&args, "grid_lock_state", gridLockState, nullable: true) { try activityInteger($0.rawValue) }
        }
        return try .init(command: .setOrientationLockState, arguments: args) { try ActivityEmptyResponse(value: $0) }
    }

    /// Builds START_PURCHASE. Client outcomes are advisory and must not grant server entitlement.
    /// - Parameters:
    ///   - skuID: Exact SKU ID string.
    ///   - pid: Optional nonnull numeric process identifier from the SDK schema, omitted by default.
    /// - Returns: A descriptor decoding null or an ordered typed entitlement array.
    /// - Throws: Invalid-arguments error for null pid, or whole-arguments JSON bounds errors.
    /// This purchase request is never retried automatically; after interruption, reconcile via trusted server entitlement verification.
    public static func startPurchase(skuID: String, pid: Field<JSONNumber> = .absent) throws -> ActivityRequest<ActivityPurchaseResponse> {
        var args: [String: JSONValue] = ["sku_id": .string(skuID)]
        try activityPut(&args, "pid", pid, nullable: false, JSONValue.number)
        return try .init(command: .startPurchase, arguments: args) { try ActivityPurchaseResponse(value: $0) }
    }

    /// Builds source-only GET_USER with the generated schema's identifier limit.
    /// - Parameter id: Exact ID string, at most 64 UTF-16 code units.
    /// - Returns: A descriptor decoding an explicit null or typed generated-schema participant.
    /// - Throws: Invalid-arguments error for exceeded length, or whole-arguments bounds errors.
    public static func getUser(id: String) throws -> ActivityRequest<ActivityUserResponse> {
        try activityLength(id, maximum: 64)
        return try .init(command: .getUser, arguments: ["id": .string(id)]) { try ActivityUserResponse(value: $0) }
    }

    /// Builds source-only INVITE_USER_EMBEDDED; host availability and authorization requirements are unspecified.
    /// - Parameters:
    ///   - userID: Exact user ID string.
    ///   - content: Optional nonnull invite message, at most 1024 UTF-16 code units, omitted by default.
    /// - Returns: A nullable empty-object response descriptor.
    /// - Throws: Invalid-arguments error for null/excess content, or whole-arguments bounds errors.
    public static func inviteUserEmbedded(userID: String, content: Field<String> = .absent) throws -> ActivityRequest<ActivityEmptyResponse> {
        var args: [String: JSONValue] = ["user_id": .string(userID)]
        try activityPut(&args, "content", content, nullable: false) { try activityLength($0, maximum: 1024); return .string($0) }
        return try .init(command: .inviteUserEmbedded, arguments: args) { try ActivityEmptyResponse(value: $0) }
    }

    /// Builds OPEN_SHARE_MOMENT_DIALOG on the documented web host.
    /// - Parameter mediaURL: Discord CDN media URL string, at most 1024 UTF-16 code units; the host checks CDN eligibility.
    /// - Returns: A nullable empty-object response descriptor.
    /// - Throws: Invalid-arguments error for excess length, or whole-arguments bounds errors.
    public static func openShareMomentDialog(mediaURL: String) throws -> ActivityRequest<ActivityEmptyResponse> {
        try activityLength(mediaURL, maximum: 1024)
        return try .init(command: .openShareMomentDialog, arguments: ["mediaUrl": .string(mediaURL)]) { try ActivityEmptyResponse(value: $0) }
    }

    /// Builds source-only GET_QUEST_ENROLLMENT_STATUS without inferring undocumented host/scoping rules.
    /// - Parameter questID: Exact quest identifier string.
    /// - Returns: A typed enrollment descriptor preserving missing and null enrollment dates.
    /// - Throws: Whole-arguments JSON bounds errors.
    public static func getQuestEnrollmentStatus(questID: String) throws -> ActivityRequest<ActivityQuestEnrollment> {
        try .init(command: .getQuestEnrollmentStatus, arguments: ["quest_id": .string(questID)]) { try ActivityQuestEnrollment(value: $0) }
    }

    /// Builds source-only QUEST_START_TIMER; automatic retry is deliberately absent.
    /// - Parameter questID: Exact quest identifier string.
    /// - Returns: A typed success result descriptor.
    /// - Throws: Whole-arguments JSON bounds errors.
    public static func questStartTimer(questID: String) throws -> ActivityRequest<ActivitySuccess> {
        try .init(command: .questStartTimer, arguments: ["quest_id": .string(questID)]) { try ActivitySuccess(value: $0) }
    }

    /// Builds SHARE_LINK using the generated schema's current link_id spelling.
    /// - Parameters:
    ///   - message: Message text, at most 1000 UTF-16 code units; an empty string is valid.
    ///   - customID: Optional nonnull custom identifier, at most 64 UTF-16 code units.
    ///   - linkID: Optional nonnull link identifier, at most 64 UTF-16 code units; old referrer_id is not emitted.
    /// - Returns: A descriptor decoding success, copy and send outcome flags independently.
    /// - Throws: Invalid-arguments error for null/excess fields, or whole-arguments JSON bounds errors.
    public static func shareLink(message: String, customID: Field<String> = .absent,
                                 linkID: Field<String> = .absent) throws -> ActivityRequest<ActivityShareLink> {
        try activityLength(message, maximum: 1000)
        var args: [String: JSONValue] = ["message": .string(message)]
        try activityPut(&args, "custom_id", customID, nullable: false) { try activityLength($0, maximum: 64); return .string($0) }
        try activityPut(&args, "link_id", linkID, nullable: false) { try activityLength($0, maximum: 64); return .string($0) }
        return try .init(command: .shareLink, arguments: args) { try ActivityShareLink(value: $0) }
    }

    /// Builds source-only SHARE_INTERACTION with typed options, preview and action rows.
    /// - Parameters:
    ///   - command: Command identifier string, retained exactly.
    ///   - options: Optional nonnull ordered name/value options, omitted by default.
    ///   - content: Optional nonnull content, at most 2000 UTF-16 code units.
    ///   - requireLaunchChannel: Optional nonnull launch-channel constraint, omitted by default.
    ///   - previewImage: Optional nonnull typed preview image, omitted by default.
    ///   - components: Optional nonnull ordered rows, each validated to at most five buttons.
    ///   - pid: Optional nonnull numeric process identifier, omitted by default.
    /// - Returns: A typed success descriptor; no automatic retries or mutation coalescing occur.
    /// - Throws: Invalid-arguments error for forbidden null or excess content, or whole-arguments JSON bounds errors.
    public static func shareInteraction(command: String, options: Field<[ActivityShareOption]> = .absent,
        content: Field<String> = .absent, requireLaunchChannel: Field<Bool> = .absent,
        previewImage: Field<ActivitySharePreview> = .absent, components: Field<[ActivityShareRow]> = .absent,
        pid: Field<JSONNumber> = .absent) throws -> ActivityRequest<ActivitySuccess> {
        var args: [String: JSONValue] = ["command": .string(command)]
        try activityPut(&args, "options", options, nullable: false) { .array($0.map { .object(["name": .string($0.name), "value": .string($0.value)]) }) }
        try activityPut(&args, "content", content, nullable: false) { try activityLength($0, maximum: 2000); return .string($0) }
        try activityPut(&args, "require_launch_channel", requireLaunchChannel, nullable: false, JSONValue.bool)
        try activityPut(&args, "preview_image", previewImage, nullable: false) { .object(["height": .number($0.height), "url": .string($0.url), "width": .number($0.width)]) }
        try activityPut(&args, "components", components, nullable: false) { rows in
            .array(try rows.map { row in
                var fields: [String: JSONValue] = ["type": try activityInteger(1)]
                try activityPut(&fields, "components", row.buttons, nullable: false) { buttons in
                    .array(try buttons.map { button in
                        var item: [String: JSONValue] = ["type": try activityInteger(2), "style": try activityInteger(button.style)]
                        try activityPut(&item, "label", button.label, nullable: false, JSONValue.string)
                        try activityPut(&item, "custom_id", button.customID, nullable: false, JSONValue.string)
                        return .object(item)
                    })
                }
                return .object(fields)
            })
        }
        try activityPut(&args, "pid", pid, nullable: false, JSONValue.number)
        return try .init(command: .shareInteraction, arguments: args) { try ActivitySuccess(value: $0) }
    }
}

/// Inserts a typed field into a request without conflating omission and explicit null.
/// - Parameters:
///   - fields: Mutable local argument object; only this field may be added or replaced.
///   - key: Wire field name.
///   - field: Omitted, null or present value.
///   - nullable: Whether explicit null is permitted by the command schema.
///   - transform: Pure synchronous projection of a present value into bounded JSON.
/// - Throws: Invalid-arguments error for forbidden null, or the transform's validation failure.
func activityPut<T>(_ fields: inout [String: JSONValue], _ key: String, _ field: Field<T>,
                    nullable: Bool, _ transform: (T) throws -> JSONValue) throws {
    switch field {
    case .absent: break
    case .null:
        guard nullable else { throw ActivityCatalogError.invalidArguments }
        fields[key] = .null
    case .value(let value): fields[key] = try transform(value)
    }
}

/// Enforces the JavaScript validator's UTF-16 length semantics without Unicode normalization.
/// - Parameters:
///   - value: Exact outgoing string; empty values are allowed by these source schemas.
///   - maximum: Inclusive UTF-16 code-unit limit.
/// - Throws: Invalid-arguments error when the source limit is exceeded.
func activityLength(_ value: String, maximum: Int) throws {
    guard value.utf16.count <= maximum else { throw ActivityCatalogError.invalidArguments }
}

/// Validates an optional nonnull string before storing it in a typed request component.
/// - Parameters:
///   - field: Omitted or present string; null is rejected.
///   - maximum: Inclusive UTF-16 code-unit limit.
/// - Returns: The unchanged validated presence state.
/// - Throws: Invalid-arguments error for null or exceeded length.
func activityLimited(_ field: Field<String>, maximum: Int) throws -> Field<String> {
    if case .null = field { throw ActivityCatalogError.invalidArguments }
    if case .value(let string) = field { try activityLength(string, maximum: maximum) }
    return field
}

/// Creates an exact JSON integer token for fixed protocol constants.
/// - Parameter value: Finite native integer, with no unit conversion.
/// - Returns: Canonical decimal JSON number.
/// - Throws: JSON number validation error; native Int spellings always satisfy the grammar.
func activityInteger(_ value: Int) throws -> JSONValue { .number(try JSONNumber(rawValue: String(value))) }

/// Validates absolute URLs for the SET_ACTIVITY fields whose pinned schema requires URL syntax.
/// - Parameter text: Exact caller-supplied URL string.
/// - Returns: Unchanged string subtree after validation.
/// - Throws: Invalid-arguments error for missing scheme, an empty network host, malformed URL or an empty string.
/// Network schemes validate host/port with WHATWG-compatible slash handling; valid custom absolute schemes remain allowed.
func activityURL(_ text: String) throws -> JSONValue {
    guard let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty else {
        throw ActivityCatalogError.invalidArguments
    }
    if ["http", "https", "ftp", "ws", "wss"].contains(scheme.lowercased()) {
        // WHATWG special URLs accept omitted or additional slashes and treat backslashes as separators.
        // Normalize only for validation; retain the original spelling in the actual protocol argument.
        let remainder = text.dropFirst(scheme.count + 1).replacingOccurrences(of: "\\", with: "/")
        let authority = remainder.drop(while: { $0 == "/" })
        guard let components = URLComponents(string: scheme + "://" + authority),
              let host = components.host, !host.isEmpty,
              !host.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }),
              components.port == nil || (0...65_535).contains(components.port!) else {
            throw ActivityCatalogError.invalidArguments
        }
    }
    return .string(text)
}

/// Typed outgoing request component with redacted ordinary and reflective diagnostics.
/// Fields remain explicit for protocol encoding, but sensitive user content is never expanded by dump or interpolation.
public protocol ActivityRequestPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension ActivityRequestPayload {
    /// Conceals request component contents, including user-provided option values and media URLs.
    public var description: String { "ActivityRequestPayload(redacted)" }
    /// Conceals request contents in debugger output.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from expanding user content.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension ActivityShareOption: ActivityRequestPayload {}
extension ActivitySharePreview: ActivityRequestPayload {}
extension ActivityShareButton: ActivityRequestPayload {}
extension ActivityShareRow: ActivityRequestPayload {}
