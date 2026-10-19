import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates slash metadata and an explicit factory while preserving one author-selected response family.
public struct SlashCommandMacro: MemberMacro, ExtensionMacro {
    /// Validates finite metadata and emits documented inert members; execute remains author-owned.
    /// - Parameters:
    ///   - node: Attribute containing literal root name and description.
    ///   - declaration: Nongeneric handler struct with explicit Arguments and execute implementation.
    ///   - protocols: Compiler-requested conformances; explicit typed or manual contracts remain unchanged.
    ///   - context: Compiler diagnostics and location authority.
    /// - Returns: Command metadata, explicit-source contribution and grouped-leaf factories, or none on error.
    /// - Throws: Syntax construction errors are propagated; author errors are emitted as diagnostics.
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let structure = AuthoringSyntax.structure(declaration, reserved: ["command", "contribution", "slashSubcommand"], context: context),
              case .argumentList(let arguments) = node.arguments, arguments.count == 2,
              arguments.first?.label == nil, let nameExpression = arguments.first?.expression,
              let name = AuthoringSyntax.literal(nameExpression), AuthoringSyntax.validName(name),
              arguments.last?.label?.text == "description", let descriptionExpression = arguments.last?.expression,
              let description = AuthoringSyntax.literal(descriptionExpression),
              (1...100).contains(description.unicodeScalars.count) else {
            AuthoringSyntax.diagnose(context, node, "literal-metadata", "@SlashCommand requires a valid literal name and 1...100 character literal description without escapes or interpolation")
            return []
        }
        guard structure.memberBlock.members.contains(where: { member in
            member.decl.as(TypeAliasDeclSyntax.self)?.name.text == "Arguments"
        }) else {
            AuthoringSyntax.diagnose(context, node, "missing-arguments", "@SlashCommand requires an explicit Arguments typealias conforming to CommandArguments")
            return []
        }
        guard AuthoringSyntax.handlerFamilies(structure).count <= 1 else {
            AuthoringSyntax.diagnose(context, node, "multiple-handler-families", "@SlashCommand requires exactly one immediate, deferred or manual handler family")
            return []
        }
        let access = structure.modifiers.first(where: { ["public", "package"].contains($0.name.text) }).map { $0.name.text + " " } ?? ""
        return [DeclSyntax(stringLiteral: """
        /// Finite API v10 registration metadata; reading it never invokes the selected handler.
        \(access)var command: DiscordCommandDSL.SlashCommandMetadata {
            /// Returns immutable author metadata without tasks, I/O or response ownership changes.
            get { DiscordCommandDSL.SlashCommandMetadata(name: \(nameExpression), description: \(descriptionExpression)) }
        }
        """), DeclSyntax(stringLiteral: """
        /// Validates and retains this slash handler without executing, registering or responding.
        /// - Parameters:
        ///   - id: Explicit stable declaration identity; admitted by structural compilation.
        ///   - source: Author coordinate for bounded schema and command diagnostics.
        /// - Returns: The existing runtime contribution with matching definition and route snapshots.
        /// - Throws: Existing ArgumentDiagnostic or CommandCompilationDiagnostic validation errors.
        \(access)func contribution(id: String, source: DiscordDSL.DefinitionSourceLocation) throws -> DiscordCommandDSL.SlashCommand<Self> {
            try DiscordCommandDSL.SlashCommand(id: id, handler: self, source: source)
        }
        """), DeclSyntax(stringLiteral: """
        /// Validates this handler as a leaf of an explicitly authored slash-command tree.
        /// - Returns: A retained subcommand with the same typed arguments and response ownership.
        /// - Throws: Existing schema or metadata diagnostics, including root-only settings on a leaf.
        /// Construction performs synchronous validation and starts no handler, registration or I/O.
        \(access)func slashSubcommand() throws -> DiscordCommandDSL.SlashSubcommand {
            try DiscordCommandDSL.SlashSubcommand(handler: self)
        }
        """)]
    }

    /// Preserves explicit typed/manual contracts and adds the manual protocol only when none is named.
    /// - Parameters:
    ///   - node: Original slash attribute.
    ///   - declaration: Original struct inspected for syntactic conformance duplication.
    ///   - type: Compiler-qualified extended type, including enclosing scopes.
    ///   - protocols: Compiler-requested conformances, unused because explicit inheritance is preserved.
    ///   - context: Compiler expansion authority; no diagnostics are duplicated in this role.
    /// - Returns: A single empty manual-handler extension, or none for an explicit family/unsupported root.
    /// - Throws: SwiftSyntax construction errors, propagated to the compiler.
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self), structure.genericParameterClause == nil,
              AuthoringSyntax.handlerFamilies(structure).isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): DiscordCommandDSL.ManualSlashCommandHandler {}")]
    }
}

/// Shared finite context-menu syntax admission; Swift checks imported target and response types.
private enum ContextMenuAuthoring {
    /// Finds directly spelled immediate, deferred and manual contracts for one target kind.
    /// - Parameters:
    ///   - declaration: Original nongeneric handler declaration; imported refinements are not inspected.
    ///   - family: The package-owned `User` or `Message` target prefix.
    /// - Returns: Directly named contracts in stable immediate/deferred/manual order.
    static func families(_ declaration: StructDeclSyntax, family: String) -> [String] {
        ["\(family)CommandHandler", "Deferred\(family)CommandHandler", "Manual\(family)CommandHandler"].filter {
            AuthoringSyntax.inherits(declaration, $0)
        }
    }

    /// Emits inert context-menu metadata and a contribution factory after finite literal admission.
    /// - Parameters:
    ///   - node: Original attribute containing exactly one simple literal registration name.
    ///   - declaration: Handler struct inspected for reserved members and exclusive response ownership.
    ///   - family: The package-owned `User` or `Message` target prefix, never interaction data.
    ///   - context: Compiler diagnostic authority; no imported sources or filesystem paths are read.
    /// - Returns: Two documented members, or none after an author-facing diagnostic.
    /// - Throws: This implementation never throws; runtime constructors remain responsible for validation.
    static func members(of node: AttributeSyntax, declaration: some DeclGroupSyntax, family: String,
                        context: some MacroExpansionContext) -> [DeclSyntax] {
        guard let structure = AuthoringSyntax.structure(declaration, reserved: ["command", "contribution"], context: context),
              case .argumentList(let arguments) = node.arguments, arguments.count == 1,
              let argument = arguments.first, argument.label == nil,
              let name = AuthoringSyntax.literal(argument.expression),
              (1...32).contains(name.unicodeScalars.count) else {
            AuthoringSyntax.diagnose(context, node, "literal-metadata", "@\(family)Command requires a 1...32 character literal name without escapes or interpolation")
            return []
        }
        guard families(structure, family: family).count <= 1 else {
            AuthoringSyntax.diagnose(context, node, "multiple-handler-families", "@\(family)Command requires exactly one immediate, deferred or manual \(family.lowercased()) handler family")
            return []
        }
        let access = structure.modifiers.first(where: { ["public", "package"].contains($0.name.text) }).map { $0.name.text + " " } ?? ""
        return [DeclSyntax(stringLiteral: """
        /// API v10 context-menu metadata; reading it never resolves a target or invokes behavior.
        \(access)var command: DiscordCommandDSL.ContextMenuCommandMetadata {
            /// Returns the immutable registration name without tasks, registration or I/O.
            get { DiscordCommandDSL.ContextMenuCommandMetadata(name: \(argument.expression)) }
        }
        """), DeclSyntax(stringLiteral: """
        /// Validates and retains this context-menu handler without resolving targets or executing work.
        /// - Parameters:
        ///   - id: Explicit stable declaration identity admitted by structural compilation.
        ///   - source: Author coordinate for bounded registration and declaration diagnostics.
        /// - Returns: One typed \(family.lowercased()) command contribution with exact registration and routing metadata.
        /// - Throws: Existing command compilation or registration diagnostics; no partial result escapes.
        \(access)func contribution(id: String, source: DiscordDSL.DefinitionSourceLocation) throws -> DiscordCommandDSL.\(family)Command<Self> {
            try DiscordCommandDSL.\(family)Command(id: id, handler: self, source: source)
        }
        """)]
    }

    /// Preserves a directly selected family and otherwise adds the established manual ownership default.
    /// - Parameters:
    ///   - declaration: Original handler declaration, accepted only as a nongeneric struct.
    ///   - type: Compiler-qualified extended type, including its enclosing scopes.
    ///   - family: Package-owned target prefix, never submitted invocation data.
    /// - Returns: One empty manual conformance, or none when explicit ownership already exists.
    /// - Throws: SwiftSyntax construction errors propagated to the compiler host.
    static func extensions(declaration: some DeclGroupSyntax, type: some TypeSyntaxProtocol,
                           family: String) throws -> [ExtensionDeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self), structure.genericParameterClause == nil,
              families(structure, family: family).isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): DiscordCommandDSL.Manual\(raw: family)CommandHandler {}")]
    }
}

/// Generates user-target context-menu metadata without owning target resolution or response handling.
public struct UserCommandMacro: MemberMacro, ExtensionMacro {
    /// Generates two documented members after checking the literal name and exclusive response family.
    /// - Parameters:
    ///   - node: Original `@UserCommand` marker containing one literal context-menu name.
    ///   - declaration: Nongeneric handler struct with an author-owned execute method.
    ///   - protocols: Compiler-requested conformances; explicit ownership remains author-selected.
    ///   - context: Compiler diagnostic and expansion authority; no external source is loaded.
    /// - Returns: Inert metadata and explicit contribution factory, or none after diagnostics.
    /// - Throws: This implementation never throws; Swift checks target and response signatures.
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        ContextMenuAuthoring.members(of: node, declaration: declaration, family: "User", context: context)
    }

    /// Adds manual user-target ownership only when no supported direct family name is present.
    /// - Parameters:
    ///   - node: Original marker; diagnostics are emitted only by member expansion.
    ///   - declaration: Handler declaration inspected without resolving imported refinements.
    ///   - type: Compiler-qualified extended type.
    ///   - protocols: Compiler-requested conformances, unused because direct inheritance is authoritative.
    ///   - context: Compiler expansion authority; this role emits no duplicate diagnostics.
    /// - Returns: One manual-handler conformance, or none for explicit/unsupported declarations.
    /// - Throws: SwiftSyntax construction errors propagated to the compiler.
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try ContextMenuAuthoring.extensions(declaration: declaration, type: type, family: "User")
    }
}

/// Generates message-target context-menu metadata while retaining the author's explicit response contract.
public struct MessageCommandMacro: MemberMacro, ExtensionMacro {
    /// Generates two documented members after checking the literal name and exclusive response family.
    /// - Parameters:
    ///   - node: Original `@MessageCommand` marker containing one literal context-menu name.
    ///   - declaration: Nongeneric handler struct with an author-owned execute method.
    ///   - protocols: Compiler-requested conformances; direct inheritance retains response ownership.
    ///   - context: Compiler diagnostic authority; expansion performs no registration or I/O.
    /// - Returns: Inert metadata and explicit contribution factory, or none after diagnostics.
    /// - Throws: This implementation never throws; Swift checks target and response signatures.
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        ContextMenuAuthoring.members(of: node, declaration: declaration, family: "Message", context: context)
    }

    /// Adds manual message-target ownership only when no supported direct family is selected.
    /// - Parameters:
    ///   - node: Original marker; member expansion owns diagnostics.
    ///   - declaration: Handler declaration inspected syntactically without imported-source lookup.
    ///   - type: Compiler-qualified extended type.
    ///   - protocols: Compiler-requested conformances, unused because direct inheritance is preserved.
    ///   - context: Compiler expansion authority; this role creates no diagnostics or runtime work.
    /// - Returns: One empty manual conformance, or none for explicit/unsupported declarations.
    /// - Throws: SwiftSyntax construction errors propagated to the compiler host.
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try ContextMenuAuthoring.extensions(declaration: declaration, type: type, family: "Message")
    }
}
