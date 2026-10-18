import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros
import DiscordDSLMacrosPlugin
import DiscordInteractions
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import Testing

/// Compiled fixture proving generated witnesses retain Swift package access across the conformance.
@DiscordDSLMacros.CommandArguments
package struct PackageVisibleArguments {
    @DiscordDSLMacros.Option(description: "Name") package let name: String
}

/// Package-visible manual handler with no runtime work until its explicit execution method is invoked.
@DiscordDSLMacros.SlashCommand("package", description: "Package access fixture")
package struct PackageVisibleHandler {
    package typealias Arguments = PackageVisibleArguments

    /// Checks cancellation without responding; the test uses only its inert contribution factory.
    /// - Parameters:
    ///   - context: Existing interaction response owner, retained solely by the explicit runtime route.
    ///   - arguments: Fresh validated invocation state, unused by this package-access fixture.
    /// - Throws: Cancellation from the caller's task; this fixture never acknowledges an interaction.
    package func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        try Task.checkCancellation()
    }
}

/// Syntactic expansion tests independent of runtime consumers, network access and imported-source lookup.
@Suite struct ExpansionTests {
    /// Parses one fixture declaration while retaining the original syntax tree for diagnostics.
    /// - Parameter source: Complete Swift source containing one marked struct.
    /// - Returns: First struct and its first attached attribute.
    /// - Throws: A Swift Testing requirement failure for an invalid test fixture.
    private func fixture(_ source: String) throws -> (StructDeclSyntax, AttributeSyntax) {
        let tree = Parser.parse(source: source)
        let declaration = try #require(tree.statements.first?.item.as(StructDeclSyntax.self))
        let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
        return (declaration, attribute)
    }

    /// Verifies exact typed descriptors, defaults, order, invocation construction and callable documentation.
    /// No codec or initializer executes during this syntax-only check.
    /// - Throws: Unexpected parsing or macro-expansion failures fail the test.
    @Test func argumentExpansionRetainsTypedFieldsAndDefaults() throws {
        let (declaration, attribute) = try fixture("""
        @CommandArguments
        struct Input {
            @Option(description: "Person") let person: String
            @Option(name: "size", description: "Size") var amount: Int? = 2
            @Option(description: "Flavor") var flavor: External.Flavor = .vanilla
        }
        """)
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members.count == 2)
        let schema = try #require(members.first).description
        #expect(schema.contains("ArgumentOption<String>(name: \"person\", description: \"Person\", defaultValue: .none"))
        #expect(schema.contains("ArgumentOption<Int?>(name: \"size\", description: \"Size\", defaultValue: .value(2)"))
        #expect(schema.contains("ArgumentOption<External.Flavor>(name: \"flavor\", description: \"Flavor\", defaultValue: .value(.vanilla)"))
        #expect(schema.contains("options: [option0.erased, option1.erased, option2.erased]"))
        #expect(schema.contains("person: try decoder.value(for: option0), amount: try decoder.value(for: option1), flavor: try decoder.value(for: option2)"))
        #expect(schema.contains("/// - Throws:"))
        let initializer = try #require(members.last).description
        #expect(initializer.contains("private init(_discordValidated: Void, person: String, amount: Int?, flavor: External.Flavor)"))
        #expect(initializer.contains("self.flavor = flavor"))
        #expect(initializer.contains("///   - amount:"))
    }

    /// Empty schemas generate a valid zero-field constructor and retain public witness visibility.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func emptyPublicArgumentsAndExistingConformance() throws {
        let (declaration, attribute) = try fixture("""
        @CommandArguments
        public struct Empty: DiscordCommandDSL.CommandArguments {}
        """)
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members[0].description.contains("public static var schema:"))
        #expect(members[0].description.contains("Self(_discordValidated: ())"))
        #expect(members[0].description.contains("options: []"))
        let extensions = try CommandArgumentsMacro.expansion(of: attribute, attachedTo: declaration,
            providingExtensionsOf: TypeSyntax(stringLiteral: "Empty"), conformingTo: [], in: context)
        #expect(extensions.isEmpty)
    }

    /// Each malformed shape receives a stable targeted diagnostic and no partial generated members.
    /// The fixtures cover unsupported properties, unsafe defaults, invalid metadata and collisions.
    /// - Parameters:
    ///   - property: Source property to place inside the marked struct.
    ///   - diagnostic: Required stable diagnostic suffix.
    /// - Throws: Unexpected parsing or expansion failures fail the test.
    @Test(arguments: [
        ("let name: String", "missing-option"),
        ("@Option(description: \"Name\") var name: String { \"x\" }", "unsupported-property"),
        ("@Option(description: \"Name\") var name = \"x\"", "unsupported-property"),
        ("@Option(description: \"Name\") var name: String, other: String", "unsupported-property"),
        ("@Option(description: \"Name\") let name: String = \"x\"", "initialized-let"),
        ("@Option(description: \"Name\") var name: String = compute()", "dynamic-default"),
        ("@Option(description: \"Name\") var name: String = 42", "incompatible-default"),
        ("@Option(description: dynamic) var name: String", "literal-metadata"),
        ("@Option(description: \"Name\") var Name: String", "literal-metadata"),
        ("@Option(description: \"\") var name: String", "literal-metadata"),
        ("static var schema: Int = 0", "reserved-member"),
        ("@Option(description: \"Static\") static var value: String = \"x\"", "unsupported-property"),
        ("@Option(name: \"marker\", description: \"Marker\") let _discordValidated: String", "reserved-member"),
        ("@Option(description: #\"Raw\"#) let name: String", "literal-metadata"),
        ("@Option(description: \"\"\"\nMultiline\n\"\"\") let name: String", "literal-metadata"),
        ("@Option(description: \"Line\\nBreak\") let name: String", "literal-metadata"),
        ("@Option(description: \"Value\") var name: Int = nil", "incompatible-default"),
        ("@Option(description: \"Value\") var flag: Bool = 1", "incompatible-default"),
        ("@Option(description: \"Value\") var name: String = \"Hi \\(other)\"", "dynamic-default"),
    ])
    func malformedFields(property: String, diagnostic: String) throws {
        let (declaration, attribute) = try fixture("@CommandArguments struct Input { \(property) }")
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
        #expect(members.isEmpty)
        #expect(context.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: diagnostic) })
    }

    /// Duplicate names and the protocol's 25-option bound fail before emitting schema code.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func duplicateAndExcessiveArguments() throws {
        let (duplicate, marker) = try fixture("""
        @CommandArguments struct Input {
            @Option(name: "same", description: "A") let first: String
            @Option(name: "same", description: "B") let second: String
        }
        """)
        let duplicateContext = BasicMacroExpansionContext()
        #expect(try CommandArgumentsMacro.expansion(of: marker, providingMembersOf: duplicate, conformingTo: [], in: duplicateContext).isEmpty)
        #expect(duplicateContext.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "duplicate-option") })
        let properties = (0..<26).map { "@Option(description: \"Item\") let item\($0): String" }.joined(separator: "\n")
        let (excessive, excessMarker) = try fixture("@CommandArguments struct Input { \(properties) }")
        let excessiveContext = BasicMacroExpansionContext()
        #expect(try CommandArgumentsMacro.expansion(of: excessMarker, providingMembersOf: excessive, conformingTo: [], in: excessiveContext).isEmpty)
        #expect(excessiveContext.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "option-limit") })
    }

    /// Manual slash expansion fully qualifies runtime names and preserves the explicit response boundary.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func slashExpansionAndConformance() throws {
        let (declaration, attribute) = try fixture("""
        @SlashCommand("greet", description: "Greet one person")
        public struct Greeting { typealias Arguments = Input }
        """)
        let context = BasicMacroExpansionContext()
        let members = try SlashCommandMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members.count == 2)
        #expect(members[0].description.contains("public var command: DiscordCommandDSL.SlashCommandMetadata"))
        #expect(members[0].description.contains("name: \"greet\", description: \"Greet one person\""))
        #expect(members[1].description.contains("source: DiscordDSL.DefinitionSourceLocation"))
        #expect(members[1].description.contains("DiscordCommandDSL.SlashCommand<Self>"))
        #expect(members[1].description.contains("handler: self, source: source"))
        let extensions = try SlashCommandMacro.expansion(of: attribute, attachedTo: declaration,
            providingExtensionsOf: TypeSyntax(stringLiteral: "Greeting"), conformingTo: [], in: context)
        #expect(extensions.map(\.trimmedDescription) == ["extension Greeting: DiscordCommandDSL.ManualSlashCommandHandler {}"])
    }

    /// Dynamic, empty, uppercase and excessive command metadata fail without generated route behavior.
    /// - Parameter attributeSource: Complete malformed slash attribute spelling.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test(arguments: [
        "@SlashCommand(dynamic, description: \"Hello\")",
        "@SlashCommand(\"Hello\", description: \"Hello\")",
        "@SlashCommand(\"hello\", description: \"\")",
        "@SlashCommand(\"hello\", description: \"\(String(repeating: "x", count: 101))\")",
    ])
    func invalidSlashMetadata(attributeSource: String) throws {
        let (declaration, attribute) = try fixture("\(attributeSource) struct Greeting {}")
        let context = BasicMacroExpansionContext()
        #expect(try SlashCommandMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context).isEmpty)
        #expect(context.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "literal-metadata") })
    }

    /// Generic roots receive a diagnostic while explicit manual-handler inheritance avoids duplication.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func genericRootAndExplicitHandlerConformance() throws {
        let (generic, marker) = try fixture("@CommandArguments struct Input<T> {}")
        let context = BasicMacroExpansionContext()
        #expect(try CommandArgumentsMacro.expansion(of: marker, providingMembersOf: generic, conformingTo: [], in: context).isEmpty)
        #expect(context.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "unsupported-declaration") })
        let (handler, slash) = try fixture("@SlashCommand(\"greet\", description: \"Hello\") struct Greeting: ManualSlashCommandHandler {}")
        #expect(try SlashCommandMacro.expansion(of: slash, attachedTo: handler,
            providingExtensionsOf: TypeSyntax(stringLiteral: "Greeting"), conformingTo: [], in: context).isEmpty)
    }

    /// Markers require their structural owner and slash handlers require an explicit argument alias.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func standaloneMarkerAndMissingAlias() throws {
        let tree = Parser.parse(source: "@Option(description: \"Name\") var name: String")
        let property = try #require(tree.statements.first?.item.as(VariableDeclSyntax.self))
        let marker = try #require(property.attributes.first?.as(AttributeSyntax.self))
        let context = BasicMacroExpansionContext()
        #expect(try OptionMacro.expansion(of: marker, providingPeersOf: property, in: context).isEmpty)
        #expect(context.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "orphan-option") })
        let (handler, slash) = try fixture("@SlashCommand(\"greet\", description: \"Hello\") struct Greeting {}")
        #expect(try SlashCommandMacro.expansion(of: slash, providingMembersOf: handler, conformingTo: [], in: context).isEmpty)
        #expect(context.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "missing-arguments") })
    }

    /// Every supported fallback family is copied verbatim, leaving Swift to validate external codecs.
    /// - Parameters:
    ///   - type: Explicit field type spelling, including optional and imported forms.
    ///   - fallback: Finite literal or member expression retained without evaluation.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test(arguments: [
        ("String", "\"hello\""), ("Bool", "true"), ("Int", "-12"),
        ("Double", "+1.25"), ("Int?", "nil"), ("External.Flavor", "External.Flavor.vanilla"),
    ])
    func finiteDefaults(type: String, fallback: String) throws {
        let (declaration, attribute) = try fixture("@CommandArguments struct Input { @Option(description: \"Value\") var value: \(type) = \(fallback) }")
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration,
            conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members[0].description.contains("defaultValue: .value(\(fallback))"))
    }

    /// An unmarked nearest nested struct cannot borrow an outer macro's marker ownership.
    /// Compiler lexical scopes also admit an ordinary direct child without adding peers.
    /// - Throws: Unexpected parsing or expansion failures fail the test.
    @Test func markerBelongsToNearestStructure() throws {
        let (outer, _) = try fixture("@CommandArguments struct Outer {}")
        let (inner, _) = try fixture("@Other struct Inner {}")
        let propertyTree = Parser.parse(source: "@Option(description: \"Name\") var name: String")
        let property = try #require(propertyTree.statements.first?.item.as(VariableDeclSyntax.self))
        let marker = try #require(property.attributes.first?.as(AttributeSyntax.self))
        let nested = BasicMacroExpansionContext(lexicalContext: [Syntax(inner), Syntax(outer)])
        #expect(try OptionMacro.expansion(of: marker, providingPeersOf: property, in: nested).isEmpty)
        #expect(nested.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "orphan-option") })
        let direct = BasicMacroExpansionContext(lexicalContext: [Syntax(property), Syntax(outer)])
        #expect(try OptionMacro.expansion(of: marker, providingPeersOf: property, in: direct).isEmpty)
        #expect(direct.diagnostics.isEmpty)
        let classTree = Parser.parse(source: "class Inner {}")
        let nestedClass = try #require(classTree.statements.first?.item.as(ClassDeclSyntax.self))
        let classContext = BasicMacroExpansionContext(lexicalContext: [Syntax(property), Syntax(nestedClass), Syntax(outer)])
        #expect(try OptionMacro.expansion(of: marker, providingPeersOf: property, in: classContext).isEmpty)
        #expect(classContext.diagnostics.contains { $0.diagMessage.diagnosticID == .init(domain: "DiscordDSLMacros", id: "orphan-option") })
    }

    /// Real compiler source mapping is retained explicitly for both descriptors and schema admission.
    /// - Throws: Unexpected fixture parsing, source mapping or expansion failures fail the test.
    @Test func explicitSourceCoordinates() throws {
        let tree = Parser.parse(source: """
        @CommandArguments
        struct Input {
            @Option(description: "Name") let name: String
        }
        """)
        let declaration = try #require(tree.statements.first?.item.as(StructDeclSyntax.self))
        let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
        let context = BasicMacroExpansionContext(sourceFiles: [tree: .init(moduleName: "Fixtures", fullFilePath: "/fixtures/Input.swift")])
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration,
            conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members[0].description.contains("fileID: \"Fixtures/Input.swift\""))
        #expect(members[0].description.contains("line: 3"))
        #expect(members[0].description.contains("line: 1"))
    }

    /// Explicit nil option names preserve property inference, and escaped Swift identifiers remain valid.
    /// Ordinary unmarked static metadata is excluded from invocation state without execution.
    /// - Throws: Unexpected fixture parsing or expansion failures fail the test.
    @Test func inferredNilNameAndEscapedIdentifier() throws {
        let (declaration, attribute) = try fixture("""
        @CommandArguments struct Input {
            static let metadata = "constant"
            @Option(name: nil, description: "Class") let `class`: String
        }
        """)
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: attribute, providingMembersOf: declaration,
            conformingTo: [], in: context)
        #expect(context.diagnostics.isEmpty)
        #expect(members[0].description.contains("ArgumentOption<String>(name: \"class\""))
        #expect(!members[0].description.contains("metadata"))
        #expect(members[1].description.contains("self.`class` = `class`"))
    }

    /// Package declarations compile with package protocol witnesses and lower through the existing runtime.
    /// The syntax check also prevents accidental widening or narrowing of generated members.
    /// - Throws: Unexpected schema, contribution or syntax construction failures fail the test.
    @Test func packageVisibilityWitnessesCompile() throws {
        #expect(try PackageVisibleArguments.schema.options.map(\.name) == ["name"])
        let contribution = try PackageVisibleHandler().contribution(id: "package-fixture",
            source: DefinitionSourceLocation(fileID: "Fixture", line: 1, column: 1))
        #expect(contribution.definition.request.name == "package")
        let (arguments, marker) = try fixture("@CommandArguments package struct Input {}")
        let context = BasicMacroExpansionContext()
        let members = try CommandArgumentsMacro.expansion(of: marker, providingMembersOf: arguments,
            conformingTo: [], in: context)
        #expect(members[0].description.contains("package static var schema:"))
        let (handler, slash) = try fixture("@SlashCommand(\"greet\", description: \"Hello\") package struct Handler { typealias Arguments = Input }")
        let handlerMembers = try SlashCommandMacro.expansion(of: slash, providingMembersOf: handler,
            conformingTo: [], in: context)
        #expect(handlerMembers[0].description.contains("package var command:"))
        #expect(handlerMembers[1].description.contains("package func contribution("))
        #expect(context.diagnostics.isEmpty)
    }
}
