// File: Sources/DiscordCommands/CommandDefinition.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// A finite, typed command definition. Construction never registers commands or starts tasks.
/// The underlying validated model covers every current API v10 option, localization, permission,
/// installation context and entry-point field; no compiler macro or Gateway dependency is required.
public struct CommandDefinition: Sendable {
    /// Complete validated registration, available for advanced fields and explicit REST operations.
    public let request: ApplicationCommandCreate

    /// Adopts a complete validated registration without changing its omission or null semantics.
    /// - Parameter request: Existing typed registration; command scope is checked by the reconciler before I/O.
    public init(_ request: ApplicationCommandCreate) { self.request = request }

    /// Builds a slash command from validated options using ordinary Swift result-builder syntax.
    /// Options retain their existing ordering, localization, choices, autocomplete and nesting validation.
    /// - Parameters:
    ///   - name: Lowercase Discord command name, 1...32 Unicode scalars.
    ///   - description: Explanation of 1...100 scalars; all localized command text shares an 8000-scalar budget.
    ///   - nameLocalizations: Omitted, null to clear, or complete locale/name dictionary.
    ///   - descriptionLocalizations: Omitted, null to clear, or complete locale/description dictionary.
    ///   - defaultMemberPermissions: Omitted, null for unrestricted, or exact nonnegative decimal permission bits.
    ///   - integrationTypes: Optional explicit global installation contexts; omitted settings remain application-owned.
    ///   - contexts: Optional explicit global invocation contexts; guild reconciliation rejects global-only settings.
    ///   - nsfw: Optional age-restriction flag; omission uses Discord's false default.
    ///   - options: Synchronous throwing builder, default empty, producing at most 25 unique ordered options.
    /// - Returns: An immutable definition, without request transmission or registration side effects.
    /// - Throws: Builder errors, invalid names/locales/options/permissions, or a command text-budget violation.
    public static func slash(name: String, description: String,
        nameLocalizations: Field<[String: String]> = .absent,
        descriptionLocalizations: Field<[String: String]> = .absent,
        defaultMemberPermissions: Field<String> = .absent,
        integrationTypes: [ApplicationIntegrationType]? = nil, contexts: [InteractionContextType]? = nil,
        nsfw: Bool? = nil,
        @CommandOptionsBuilder options: () throws -> [ApplicationCommandOptionCreate] = { [] }) throws -> Self {
        Self(try ApplicationCommandCreate(name: name, description: description,
            nameLocalizations: nameLocalizations, descriptionLocalizations: descriptionLocalizations,
            options: options(), defaultMemberPermissions: defaultMemberPermissions,
            integrationTypes: integrationTypes, contexts: contexts, nsfw: nsfw))
    }

    /// Builds a user or message context-menu command without accepting slash-only descriptions/options.
    /// - Parameters:
    ///   - name: Display name of 1...32 scalars; spaces and mixed case are permitted.
    ///   - type: Exactly user or message; other kinds fail validation before any I/O.
    ///   - nameLocalizations: Omitted, null to clear, or validated complete translated names.
    ///   - defaultMemberPermissions: Omitted, unrestricted null, or exact nonnegative permission digits.
    ///   - integrationTypes: Optional global install kinds; omission leaves application defaults unmanaged during sync.
    ///   - contexts: Optional global interaction contexts; omitted settings are unmanaged during sync.
    ///   - nsfw: Optional age-restriction flag, default omitted/false.
    /// - Returns: Complete immutable context-menu definition; permissions are still enforced by Discord.
    /// - Throws: Invalid-value for unsupported kind, names/locales/permissions/contexts; text budget errors.
    public static func contextMenu(name: String, type: ApplicationCommandType,
        nameLocalizations: Field<[String: String]> = .absent,
        defaultMemberPermissions: Field<String> = .absent,
        integrationTypes: [ApplicationIntegrationType]? = nil, contexts: [InteractionContextType]? = nil,
        nsfw: Bool? = nil) throws -> Self {
        guard type == .user || type == .message else { throw DiscordError.validation(.invalidValue) }
        return Self(try ApplicationCommandCreate(name: name, type: type, nameLocalizations: nameLocalizations,
            defaultMemberPermissions: defaultMemberPermissions, integrationTypes: integrationTypes,
            contexts: contexts, nsfw: nsfw))
    }

    /// Builds an Activity entry point with explicit handler selection and no hidden eligibility check.
    /// - Parameters:
    ///   - name: Entry-point display name of 1...32 scalars.
    ///   - description: Description of 1...100 scalars.
    ///   - handler: App callback or Discord Activity launch handler; server Activity eligibility remains required.
    /// - Returns: A global-only typed definition. Wrap ApplicationCommandCreate directly for localized advanced fields.
    /// - Throws: Invalid name/description or cumulative text-budget errors; no network work occurs.
    public static func entryPoint(name: String, description: String, handler: ApplicationCommandHandler) throws -> Self {
        Self(try ApplicationCommandCreate(name: name, type: .primaryEntryPoint, description: description, handler: handler))
    }
}

/// Macro-free collection syntax for already validated command options.
/// Final command/subcommand validation enforces bounds, ordering and unique names; the builder preserves source order.
@resultBuilder public enum CommandOptionsBuilder {
    /// Collects an ordered block, including an empty block, without creating any tasks.
    /// - Parameter components: Option arrays emitted by each statement in source order.
    /// - Returns: Flattened values; the enclosing validated request enforces the 25-option limit.
    public static func buildBlock(_ components: [ApplicationCommandOptionCreate]...) -> [ApplicationCommandOptionCreate] {
        components.flatMap { $0 }
    }

    /// Adopts one validated option expression without copying or changing its fields.
    /// - Parameter expression: A leaf, subcommand or group built with ApplicationCommandOptionCreate.
    /// - Returns: One ordered builder component; invalid nesting is rejected by the enclosing command.
    public static func buildExpression(_ expression: ApplicationCommandOptionCreate) -> [ApplicationCommandOptionCreate] { [expression] }

    /// Adopts an explicit option array, including empty arrays, as one ordered component.
    /// - Parameter expression: Finite caller-owned validated options; final request validation applies.
    /// - Returns: The supplied option sequence unchanged.
    public static func buildExpression(_ expression: [ApplicationCommandOptionCreate]) -> [ApplicationCommandOptionCreate] { expression }

    /// Includes a conditional block only when its source branch was selected.
    /// - Parameter component: Nil for an omitted if branch or its ordered option sequence.
    /// - Returns: Selected options or an empty sequence for nil.
    public static func buildOptional(_ component: [ApplicationCommandOptionCreate]?) -> [ApplicationCommandOptionCreate] { component ?? [] }

    /// Preserves the first branch of an if/else without evaluating the other branch.
    /// - Parameter component: Ordered options produced by the selected first branch.
    /// - Returns: The branch component unchanged.
    public static func buildEither(first component: [ApplicationCommandOptionCreate]) -> [ApplicationCommandOptionCreate] { component }

    /// Preserves the second branch of an if/else without evaluating the other branch.
    /// - Parameter component: Ordered options produced by the selected second branch.
    /// - Returns: The branch component unchanged.
    public static func buildEither(second component: [ApplicationCommandOptionCreate]) -> [ApplicationCommandOptionCreate] { component }

    /// Collects a finite for-loop in iteration order; the enclosing request validates its complete size.
    /// - Parameter components: Per-iteration option sequences, including empty iterations.
    /// - Returns: Flattened options in source order; no iteration is asynchronous or registered implicitly.
    public static func buildArray(_ components: [[ApplicationCommandOptionCreate]]) -> [ApplicationCommandOptionCreate] { components.flatMap { $0 } }
}
