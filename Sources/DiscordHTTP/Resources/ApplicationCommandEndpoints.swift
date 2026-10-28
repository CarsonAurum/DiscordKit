// File: Sources/DiscordHTTP/Resources/ApplicationCommandEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// All 15 available API v10 command operations, verified 2026-10-16 against the written command reference
/// and official discord-api-spec preview. Nil guild selects global scope; a guild selects that guild's independent catalog.
/// Commands need no Gateway and use bot or application client-credentials Bearer authorization; Bearer CRUD requires
/// applications.commands.update. Permission replacement requires a user Bearer grant with
/// applications.commands.permissions.update and sufficient MANAGE_GUILD/MANAGE_ROLES/command/target authority.
/// Disabled batch permission editing (2022-04-27 Permissions v2) is deliberately not exposed as an available operation.
/// All writes share bounded HTTP admission/rejected-429 retry policy; ambiguous sends remain indeterminate.
public enum ApplicationCommandEndpoints {
    /// Lists every registered command in one scope without per-command fetches or invented pagination.
    /// - Parameters:
    ///   - applicationID: Parent application; its opaque ID is not invented as a Discord major rate parameter.
    ///   - guildID: Nil for global commands, otherwise guild catalog and major guild partition.
    ///   - withLocalizations: Optional full-dictionary query; true is required for reliable localization reconciliation.
    ///   - readPolicy: Optional credential-scoped reuse, default coalescing without completed caching; nil disables reuse.
    /// - Returns: Safe HTTP 200 GET of an ordered array, including empty, with unknown fields preserved.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/cancellation/schema errors during execution.
    public static func list(applicationID: ApplicationID, guildID: GuildID? = nil,
                            withLocalizations: Bool? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[ApplicationCommand]> {
        try commandEndpoint("GET", applicationID: applicationID, guildID: guildID,
            query: withLocalizations.map { [QueryItem(name: "with_localizations", value: String($0))] } ?? [],
            readPolicy: readPolicy, decode: { try guildArray($0) { try ApplicationCommand(data: $0) } })
    }

    /// Creates/upserts one command; a matching name/type replaces the existing registration.
    /// - Parameters:
    ///   - applicationID: Application owning the authorization token and desired command.
    ///   - guildID: Nil for global scope; guild scope rejects entry points and ordinary global-only fields.
    ///   - request: Complete validated command; daily create quotas and Activity eligibility remain server checks.
    /// - Returns: Unsafe POST accepting both 201 creation and 200 overwrite, returning the registration snapshot.
    /// - Throws: Body/scope/descriptor errors now; auth/limits/API/transport/schema/indeterminate submission later.
    public static func create(applicationID: ApplicationID, guildID: GuildID? = nil,
                              request: ApplicationCommandCreate) throws -> Endpoint<ApplicationCommand> {
        try commandValidateScope(guildID, type: request.type, value: request.jsonValue())
        return try commandEndpoint("POST", applicationID: applicationID, guildID: guildID,
            payload: request.jsonValue(), successStatuses: [200, 201], decode: { try ApplicationCommand(data: $0) })
    }

    /// Retrieves one command snapshot without resolving permissions or fetching related resources.
    /// - Parameters:
    ///   - applicationID: Parent application and token ownership scope.
    ///   - commandID: Exact command ID, including snowflakes above 2^53.
    ///   - guildID: Nil for global scope or the owning guild and major partition.
    ///   - readPolicy: Optional authentication-scoped coalescing/explicit TTL, default no completed caching.
    /// - Returns: Safe HTTP 200 GET with the complete command projection.
    /// - Throws: Descriptor/policy errors now; auth/missing command/API/transport/schema errors on execution.
    public static func get(applicationID: ApplicationID, commandID: ApplicationCommandID,
                           guildID: GuildID? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationCommand> {
        try commandEndpoint("GET", applicationID: applicationID, guildID: guildID, commandID: commandID,
            readPolicy: readPolicy, decode: { try ApplicationCommand(data: $0) })
    }

    /// Edits selected fields, each supplied collection entirely replacing that field; type cannot change.
    /// - Parameters:
    ///   - applicationID: Parent application/token scope.
    ///   - commandID: Existing command to modify; renaming permanently deletes its existing permission overrides.
    ///   - guildID: Nil for global scope; guild scope forbids entry points and global-only ordinary fields.
    ///   - request: Validated edits with explicit existing-kind context; an empty object still sends one PATCH.
    /// - Returns: Unsafe HTTP 200 PATCH with updated command and scoped read invalidation.
    /// - Throws: Local body/scope/descriptor errors now; permissions/API/transport/indeterminate errors during execution.
    public static func modify(applicationID: ApplicationID, commandID: ApplicationCommandID,
                              guildID: GuildID? = nil, request: ApplicationCommandModify) throws -> Endpoint<ApplicationCommand> {
        try commandValidateScope(guildID, type: request.type, value: request.jsonValue())
        return try commandEndpoint("PATCH", applicationID: applicationID, guildID: guildID, commandID: commandID,
            payload: request.jsonValue(), decode: { try ApplicationCommand(data: $0) })
    }

    /// Deletes a registration and its associated permission overrides.
    /// - Parameters:
    ///   - applicationID: Parent application/token scope.
    ///   - commandID: Exact registered command ID; absence is an API error rather than invented success.
    ///   - guildID: Nil for global scope or the owning guild and major partition.
    /// - Returns: Unsafe DELETE requiring strictly empty HTTP 204 success.
    /// - Throws: Descriptor errors now; authorization/API/transport/indeterminate deletion errors during execution.
    public static func delete(applicationID: ApplicationID, commandID: ApplicationCommandID,
                              guildID: GuildID? = nil) throws -> Endpoint<EmptyResponse> {
        try commandEndpoint("DELETE", applicationID: applicationID, guildID: guildID, commandID: commandID,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Explicitly replaces the entire scoped command catalog across every command type in one bounded request.
    /// - Parameters:
    ///   - applicationID: Parent application/token scope.
    ///   - guildID: Nil for global replacement (at most 131); guild replacement rejects entry points (at most 130).
    ///   - request: Complete finite desired catalog; empty intentionally deletes all registrations. No automatic chunking occurs.
    /// - Returns: Unsafe HTTP 200 PUT and command array; response order is not assumed to match input.
    /// - Throws: Scope/body/descriptor errors now; daily create/eligibility/auth/API/transport/indeterminate failures later.
    ///   Written guild bulk fields explicitly permit install/context/DM settings although ordinary guild writes do not.
    public static func bulkOverwrite(applicationID: ApplicationID, guildID: GuildID? = nil,
                                     request: BulkApplicationCommands) throws -> Endpoint<[ApplicationCommand]> {
        for entry in request.commands { try commandValidateScope(guildID, type: entry.command.type, value: entry.command.jsonValue(), bulk: true) }
        return try commandEndpoint("PUT", applicationID: applicationID, guildID: guildID, payload: request.jsonValue(),
            bulk: BulkOperationMetadata(maximumItems: guildID == nil ? 131 : 130, preservesOrder: false,
                permitsPartialResults: false, documentationURL: URL(string: "https://docs.discord.com/developers/interactions/application-commands#bulk-overwrite-global-application-commands")!),
            decode: { try guildArray($0) { try ApplicationCommand(data: $0) } })
    }

    /// Lists command/application permission snapshots for one guild without evaluating effective invocation rights.
    /// - Parameters:
    ///   - applicationID: Parent app/token scope; response entries may use the application ID as a default target.
    ///   - guildID: Exact guild and major partition.
    ///   - readPolicy: Optional credential-scoped reuse; no completed cache by default.
    /// - Returns: Safe HTTP 200 array using bot or scoped Bearer read authorization.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/cancellation/schema errors later.
    public static func listPermissions(applicationID: ApplicationID, guildID: GuildID,
                                       readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildApplicationCommandPermissions]> {
        try commandEndpoint("GET", applicationID: applicationID, guildID: guildID, permissions: true,
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildApplicationCommandPermissions(data: $0) } })
    }

    /// Retrieves one command's guild overrides, preserving explicit target/type allow and deny entries.
    /// - Parameters:
    ///   - applicationID: Application/token scope.
    ///   - guildID: Guild and major rate partition.
    ///   - commandID: Exact command ID, or the application ID represented in this identifier domain for application defaults.
    ///   - readPolicy: Optional authentication-scoped reuse; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET requiring bot or scoped Bearer read authentication.
    /// - Throws: Descriptor errors now; permission/API/transport/schema/cancellation failures during execution.
    public static func permissions(applicationID: ApplicationID, guildID: GuildID, commandID: ApplicationCommandID,
                                   readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildApplicationCommandPermissions> {
        try commandEndpoint("GET", applicationID: applicationID, guildID: guildID, commandID: commandID,
            permissions: true, readPolicy: readPolicy, decode: { try GuildApplicationCommandPermissions(data: $0) })
    }

    /// Replaces one command's overrides using the required user Bearer token; bot authorization is rejected locally.
    /// - Parameters:
    ///   - applicationID: Parent application of the command and OAuth grant.
    ///   - guildID: Guild and major rate partition; Discord checks authenticating-user guild/role/target authority.
    ///   - commandID: Command or application-default target ID, preserving exact 64-bit identity.
    ///   - request: Complete at-most-100-entry replacement; empty clears explicit overrides.
    /// - Returns: Unsafe HTTP 200 PUT and updated overrides; requires applications.commands.permissions.update.
    /// - Throws: Local descriptor/body errors now; insufficient user scopes/permissions, API, transport or indeterminate errors later.
    ///   This is the enabled per-command route; disabled batch-permission editing is never substituted.
    public static func modifyPermissions(applicationID: ApplicationID, guildID: GuildID,
        commandID: ApplicationCommandID, request: ApplicationCommandPermissionsModify) throws -> Endpoint<GuildApplicationCommandPermissions> {
        try commandEndpoint("PUT", applicationID: applicationID, guildID: guildID, commandID: commandID,
            permissions: true, authentication: .bearer, payload: request.jsonValue(),
            decode: { try GuildApplicationCommandPermissions(data: $0) })
    }
}

/// Validates written scope restrictions without guessing current application Activity/install eligibility.
/// - Parameters:
///   - guildID: Nil global or nonnil guild scope.
///   - type: Known command kind; entry points are always global-only.
///   - value: Validated create/edit JSON object.
///   - bulk: True permits the global-setting fields listed explicitly by the written guild bulk table, default false.
/// - Throws: Invalid-value for guild entry points or unsupported ordinary guild-only combinations. No I/O occurs.
private func commandValidateScope(_ guildID: GuildID?, type: ApplicationCommandType, value: JSONValue, bulk: Bool = false) throws {
    guard guildID != nil else { return }
    guard type != .primaryEntryPoint, case .object(let fields) = value,
          bulk || ["dm_permission", "integration_types", "contexts", "handler"].allSatisfy({ fields[$0] == nil })
    else { throw DiscordError.validation(.invalidValue) }
}

/// Builds the immutable shared command route while preserving credential, guild, cache and retry ownership.
/// - Parameters:
///   - method: Explicit HTTP verb; GET is safe and mutations retain unsafe replay semantics.
///   - applicationID: Parent application, encoded as an exact single path segment.
///   - guildID: Optional guild major partition; nil uses global routes without an invented application major.
///   - commandID: Optional individual command; nil selects the collection.
///   - permissions: Whether to append the enabled permissions read/write suffix; default false.
///   - authentication: Bot/Bearer by default; permission writes explicitly require Bearer.
///   - query: Complete ordered list query, default empty.
///   - payload: Optional bounded JSON body; nil sends no body.
///   - successStatuses: Exact accepted statuses, default 200.
///   - readPolicy: Optional safe-read reuse; default nil, with credential-scoped command invalidation tags added.
///   - bulk: Optional explicit replacement metadata; never triggers automatic mutation merging.
///   - decode: Complete bounded typed response decoder.
/// - Returns: Descriptor with application-scoped command/permission invalidation tags and guild rate partition.
/// - Throws: Descriptor/body/policy validation errors before I/O. Construction creates no tasks or reservations.
private func commandEndpoint<T: Sendable>(_ method: String, applicationID: ApplicationID, guildID: GuildID? = nil,
    commandID: ApplicationCommandID? = nil, permissions: Bool = false, authentication: AuthenticationPolicy = .botOrBearer,
    query: [QueryItem] = [], payload: JSONValue? = nil, successStatuses: Set<Int> = [200],
    readPolicy: ReadPolicy? = nil, bulk: BulkOperationMetadata? = nil,
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    let path = ["applications", applicationID.description] + (guildID.map { ["guilds", $0.description] } ?? []) +
        ["commands"] + (commandID.map { [$0.description] } ?? []) + (permissions ? ["permissions"] : [])
    let route = "/applications/{application.id}" + (guildID == nil ? "" : "/guilds/{guild.id}") + "/commands" +
        (commandID == nil ? "" : "/{command.id}") + (permissions ? "/permissions" : "")
    let tags: Set<String> = ["application-commands:\(applicationID)", "application-command-permissions:\(applicationID)"]
    return try Endpoint(method: method, path: path, route: route, query: query, authentication: authentication,
        successStatuses: successStatuses, majorParameter: guildID?.description,
        body: try payload.map { try guildJSON($0) }, retrySafety: method == "GET" ? .safe : .unsafe,
        readPolicy: method == "GET" ? expressionReadPolicy(readPolicy, tags: tags) : nil,
        invalidates: method == "GET" ? [] : tags.union(["audit-log-catalog", "application-catalog"]), bulk: bulk, decode: decode)
}
