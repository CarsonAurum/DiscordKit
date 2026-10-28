// File: Packages/DiscordDSLMacros/Tests/GeneratedDocumentationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordDSLMacrosPlugin
import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import Testing

/// Audits actual emitted syntax rather than treating documentation inside generator strings as evidence.
/// These checks establish callable comment and signature coverage; accuracy still requires source review.
@Suite struct GeneratedDocumentationTests {
    /// Expands empty and populated argument models at each supported witness visibility.
    /// The throwing getter and private initializer must document their own callable contracts.
    /// - Parameters:
    ///   - access: Authored visibility retained by the generated schema witness.
    ///   - populated: Whether invocation construction includes ordinary and escaped identifier fields.
    /// - Throws: Invalid fixture syntax or unexpected expansion errors fail this deterministic check.
    @Test(arguments: ["", "public", "package"], [false, true])
    func argumentCallableDocumentation(access: String, populated: Bool) throws {
        let fields = populated ? """
        @Option(description: "Person") let person: String
        @Option(description: "Class") var `class`: Int? = nil
        """ : ""
        let (declaration, attribute) = try fixture("@CommandArguments \(access) struct Input { \(fields) }")
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration,
            conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        let callables = try generatedCallables(members)
        #expect(callables.map(\.name) == ["get", "init"])
        #expect(callables.allSatisfy { $0.documentationFailures.isEmpty })
        #expect(callables.first?.throwing == true)
        #expect(callables.last?.parameters == (populated ? ["_discordValidated", "person", "`class`"] : ["_discordValidated"]))
    }

    /// Checks every command family's real expansion, including each author-selected response contract.
    /// Generated metadata getters and contribution/group factories retain separate adjacent comments.
    /// - Parameters:
    ///   - family: Package-owned macro family, including the slash grouped-leaf factory.
    ///   - ownership: Explicit typed response protocol suffix, or the default manual contract.
    /// - Throws: Unexpected parsing or macro-expansion failures fail the fixture.
    @Test(arguments: [
        ("Slash", ""), ("Slash", "Immediate"), ("Slash", "Deferred"), ("Slash", "Manual"), ("Slash", "Modal"),
        ("User", ""), ("User", "Immediate"), ("User", "Deferred"), ("User", "Manual"),
        ("Message", ""), ("Message", "Immediate"), ("Message", "Deferred"), ("Message", "Manual"),
    ])
    func commandCallableDocumentation(family: String, ownership: String) throws {
        let protocolPrefix = ownership == "Immediate" ? "" : ownership
        let inheritance = ownership.isEmpty ? "" : ": DiscordCommandDSL.\(protocolPrefix)\(family)CommandHandler"
        let metadata = family == "Slash" ? "\"inspect\", description: \"Inspect target\"" : "\"Inspect Target\""
        let arguments = family == "Slash" ? "typealias Arguments = Input" : ""
        let (declaration, attribute) = try fixture("@\(family)Command(\(metadata)) public struct Handler\(inheritance) { \(arguments) }")
        let context = BasicMacroExpansionContext()
        let members: [DeclSyntax]
        switch family {
        case "Slash":
            members = try SlashCommandMacro.expansion(of: attribute, providingMembersOf: declaration,
                conformingTo: [], in: context)
        case "User":
            members = try UserCommandMacro.expansion(of: attribute, providingMembersOf: declaration,
                conformingTo: [], in: context)
        default:
            members = try MessageCommandMacro.expansion(of: attribute, providingMembersOf: declaration,
                conformingTo: [], in: context)
        }
        #expect(context.diagnostics.isEmpty)
        let callables = try generatedCallables(members)
        #expect(callables.map(\.name) == (family == "Slash" ? ["get", "contribution", "slashSubcommand"] : ["get", "contribution"]))
        #expect(callables.allSatisfy { $0.documentationFailures.isEmpty })
        #expect(callables.filter(\.throwing).count == (family == "Slash" ? 2 : 1))
        #expect(callables.first { $0.name == "contribution" }?.parameters == ["id", "source"])
    }

    /// Proves enclosing property docs and unrelated signature tags cannot hide missing callable contracts.
    /// - Throws: Unexpected parsing failures fail this negative control for the expansion audit helper.
    @Test func documentationChecksRejectIncompleteCallableComments() throws {
        let source = DeclSyntax(stringLiteral: """
        /// Property documentation must not cover its getter.
        var schema: Int { get throws { 0 } }
        /// Merely a summary.
        func contribution(id: String) throws -> Int { 0 }
        """)
        let callables = try generatedCallables([source])
        #expect(callables.map(\.name) == ["get", "contribution"])
        #expect(callables[0].documentationFailures == ["missing callable documentation", "missing throws documentation"])
        #expect(callables[1].documentationFailures == ["missing parameter documentation: id", "missing throws documentation", "missing return documentation"])
    }

    /// Parses one original macro fixture without compiling or executing author work.
    /// - Parameter source: One valid macro-marked struct declaration.
    /// - Returns: The original struct and its first attached macro marker.
    /// - Throws: Swift Testing requirement failures for malformed or incorrectly shaped test fixtures.
    private func fixture(_ source: String) throws -> (StructDeclSyntax, AttributeSyntax) {
        let tree = Parser.parse(source: source)
        #expect(!tree.hasError)
        let declaration = try #require(tree.statements.first?.item.as(StructDeclSyntax.self))
        return (declaration, try #require(declaration.attributes.first?.as(AttributeSyntax.self)))
    }

    /// Reparses real expansion output and inventories callable signatures with their owning trivia.
    /// - Parameter members: Actual members returned by a package-owned macro's expansion entry point.
    /// - Returns: Source-ordered callables; initializer and accessor visibility never suppresses coverage.
    /// - Throws: Swift Testing requirement failures if expansion emits malformed Swift syntax.
    private func generatedCallables(_ members: [DeclSyntax]) throws -> [GeneratedCallableDocumentation] {
        let source = "struct Expanded {\n" + members.map(\.description).joined(separator: "\n") + "\n}"
        let tree = Parser.parse(source: source)
        try #require(!tree.hasError)
        let visitor = GeneratedCallableDocumentationVisitor()
        visitor.walk(tree)
        return visitor.callables
    }
}

/// Signature-derived expectations independent of macro templates; no runtime source or values are retained.
private struct GeneratedCallableDocumentation {
    let name: String
    let comment: String
    let parameters: [String]
    let throwing: Bool
    let returning: Bool

    /// Identifies absent callable text or signature sections without claiming semantic completeness.
    var documentationFailures: [String] {
        var failures: [String] = []
        if comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append("missing callable documentation")
        }
        for parameter in parameters where !comment.contains("- \(parameter):") {
            failures.append("missing parameter documentation: \(parameter)")
        }
        if throwing && !comment.contains("- Throws:") { failures.append("missing throws documentation") }
        if returning && !comment.contains("- Returns:") { failures.append("missing return documentation") }
        return failures
    }
}

/// Source-accurate visitor that checks the callable node's own documentation after real template expansion.
private final class GeneratedCallableDocumentationVisitor: SyntaxVisitor {
    var callables: [GeneratedCallableDocumentation] = []

    /// Includes all emitted callable syntax regardless of access, while preserving comment ownership.
    init() { super.init(viewMode: .sourceAccurate) }

    /// Records generated factory methods and derives their parameter/error/return obligations from syntax.
    /// - Parameter node: Function emitted by the actual command macro implementation.
    /// - Returns: Child traversal so future nested explicit callables also enter the gate.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        callables.append(GeneratedCallableDocumentation(name: node.name.text,
            comment: node.leadingTrivia.docCommentValue ?? "",
            parameters: node.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text },
            throwing: node.signature.effectSpecifiers?.throwsClause != nil,
            returning: node.signature.returnClause != nil))
        return .visitChildren
    }

    /// Records private invocation construction and every field parameter supplied to the initializer.
    /// - Parameter node: Initializer emitted by the actual argument macro implementation.
    /// - Returns: Child traversal without inheriting documentation from its enclosing declaration.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        callables.append(GeneratedCallableDocumentation(name: "init", comment: node.leadingTrivia.docCommentValue ?? "",
            parameters: node.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text },
            throwing: node.signature.effectSpecifiers?.throwsClause != nil, returning: false))
        return .visitChildren
    }

    /// Records explicit getters independently of any comment on the containing generated property.
    /// - Parameter node: Generated metadata or throwing argument-schema accessor.
    /// - Returns: Child traversal, retaining future nested explicit callable coverage.
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        callables.append(GeneratedCallableDocumentation(name: node.accessorSpecifier.text,
            comment: node.leadingTrivia.docCommentValue ?? "", parameters: [],
            throwing: node.effectSpecifiers?.throwsClause != nil, returning: false))
        return .visitChildren
    }
}
