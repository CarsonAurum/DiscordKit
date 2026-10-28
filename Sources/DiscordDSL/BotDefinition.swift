// File: Sources/DiscordDSL/BotDefinition.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// A synchronous, explicitly expanded piece of a bot's immutable declaration graph.
/// Conformance is an extension point, not executable bot behavior: collection must not invoke
/// handlers, start tasks, perform I/O, register commands or inspect ambient credentials.
/// Custom composites must enter `DefinitionCollector.withStructure(source:_:)` before expanding
/// children so structural admission can stop recursion before the next child is evaluated.
/// Arbitrary user implementation code must terminate cooperatively; compilation cannot sandbox it.
public protocol BotDefinition: Sendable {
    /// Appends this definition's declarations in deterministic source order.
    /// - Parameter collector: Exclusive, synchronous compilation state. Use its admission methods
    ///   before expanding children; do not retain a copy for later or concurrent mutation.
    /// - Throws: A structural or declaration validation failure, or an error from a custom child.
    ///   Propagate failures immediately instead of continuing expansion or retrying side effects.
    func collect(into collector: inout DefinitionCollector) throws
}

/// A reusable, explicitly identified module whose body consists of ordinary Swift definitions.
/// Identity is supplied by the author and is independent of type names, reflection or installation
/// order. Repeated instances need distinct stable IDs or explicit namespaces throughout a compiled plan.
/// Inject dependencies through the conforming type's initializer; body evaluation remains synchronous.
public protocol BotModule: BotDefinition {
    /// Concrete definition body produced by ordinary Swift or `BotBuilder` syntax.
    associatedtype Body: BotDefinition

    /// Stable, explicit identity, unique within the installed explicit namespace.
    var moduleID: String {
        /// Returns the stable author-supplied module identity without deriving or registering it.
        /// - Returns: An identity validated for namespace-local uniqueness, length and controls during compilation.
        get
    }

    /// The module's diagnostic location. The default reports unavailable source coordinates.
    var sourceLocation: DefinitionSourceLocation {
        /// Returns a stored diagnostic coordinate without opening a source file or doing I/O.
        /// - Returns: The authoring location, or the default unknown file with zero line and column.
        get
    }

    /// Ordered child declarations, evaluated after module count/depth admission during collection.
    /// Body construction must be finite and free of tasks, I/O and handler execution.
    @BotBuilder var body: Body {
        /// Constructs or returns finite child declarations after collection admits this module.
        /// - Returns: Child definitions in deterministic source order, without invoking handlers or
        ///   starting tasks, I/O or registration. Swift implementation code must terminate cooperatively.
        get
    }
}

public extension BotModule {
    /// An honest fallback when a conforming module does not store a caller-supplied source location.
    /// Override this property to associate validation failures with an actual authoring location.
    var sourceLocation: DefinitionSourceLocation {
        DefinitionSourceLocation(fileID: "<unknown>", line: 0, column: 0)
    }

    /// Admits this module before evaluating and collecting its body in the module namespace.
    /// - Parameter collector: Exclusive compilation state; namespace/depth cleanup is owned by
    ///   the collector and occurs on success or a thrown child failure.
    /// - Throws: Invalid/duplicate module identity, an exceeded count/depth/text limit, or any
    ///   body validation error. Rejected module bodies are not evaluated.
    func collect(into collector: inout DefinitionCollector) throws {
        try collector.withModule(id: moduleID, source: sourceLocation) { collector in
            try body.collect(into: &collector)
        }
    }
}

/// A public leaf extension point that retains typed authoring information beside raw plan metadata.
/// External command/event declarations may conform without adding a case to a central enum.
/// The metadata accessor must be deterministic, finite and free of execution or I/O; all payloads
/// describe configuration rather than closures to execute during compilation.
public protocol DefinitionContribution: BotDefinition {
    /// Immutable identity, kind, capability requirements, source and bounded payload to validate.
    var declaration: RawDefinitionContribution {
        /// Returns deterministic inert metadata for the collector's common validation path.
        /// - Returns: One immutable raw snapshot, evaluated once per admitted append. This getter
        ///   must not invoke execution behavior, perform I/O or inspect ambient credentials.
        get
    }
}

public extension DefinitionContribution {
    /// Appends this typed contribution through the collector's common validation path.
    /// - Parameter collector: Exclusive state that validates and retains the contribution exactly once.
    /// - Throws: Invalid/duplicate identity, unsupported kind/capability, an exceeded declaration,
    ///   structural or text bound, or invalid payload metadata. No handlers are invoked.
    func collect(into collector: inout DefinitionCollector) throws {
        try collector.append(self)
    }
}

/// An explicitly identified module primitive for composing reusable declarations without a new type.
/// The initializer evaluates only the finite author-supplied builder; this library starts no tasks,
/// network operations, registration or device work. Collection later admits the module before
/// traversing the stored body and retains source order across nested modules.
public struct Module<Body: BotDefinition>: BotModule {
    /// Author-supplied stable identity, unique within the installed explicit namespace.
    public let moduleID: String
    /// Explicitly captured module declaration location.
    public let sourceLocation: DefinitionSourceLocation
    /// Already constructed, immutable child declaration structure.
    public let body: Body

    /// Constructs a module while capturing the initializer's caller location.
    /// - Parameters:
    ///   - id: Stable explicit module identity. Empty, duplicate and oversized values fail compilation.
    ///   - fileID: Diagnostic file identifier, defaulting to this initializer's caller.
    ///   - line: One-based caller line; an explicit zero means unavailable.
    ///   - column: One-based caller column; an explicit zero means unavailable.
    ///   - body: Synchronous builder evaluated exactly once now. It must terminate cooperatively and
    ///     must not perform I/O, start tasks or execute bot handlers. Validation occurs on compilation.
    /// - Returns: Stored declarations with no runtime work started by the library.
    public init(id: String, fileID: String = #fileID, line: UInt = #line, column: UInt = #column,
        @BotBuilder body: () -> Body) {
        self.moduleID = id
        self.sourceLocation = DefinitionSourceLocation(fileID: fileID, line: line, column: column)
        self.body = body()
    }

    /// Constructs a module using an already captured diagnostic location.
    /// - Parameters:
    ///   - id: Stable module identity, validated as namespace-local unique during compilation.
    ///   - source: Exact diagnostic coordinate; unknown coordinates may use zero line/column.
    ///   - body: Finite synchronous builder evaluated once at initialization. It must not perform
    ///     I/O, start tasks or invoke handlers; collected declarations are validated later.
    /// - Returns: An immutable module. The source is preserved without filesystem access.
    public init(id: String, source: DefinitionSourceLocation, @BotBuilder body: () -> Body) {
        self.moduleID = id
        self.sourceLocation = source
        self.body = body()
    }
}

/// A deliberately empty definition that still participates in structural admission.
/// Counting empty nodes prevents repeated empty expansions from escaping the structural node budget.
public struct EmptyBotDefinition: BotDefinition {
    /// Explicit diagnostic coordinate associated with this empty structural node.
    public let sourceLocation: DefinitionSourceLocation

    /// Creates an empty structural node without collecting or executing anything.
    /// - Parameter source: Diagnostic source; the default marks an unknown structural coordinate.
    ///   Callers may supply an actual authoring coordinate explicitly.
    public init(source: DefinitionSourceLocation = .init(fileID: "<builder>", line: 0, column: 0)) {
        self.sourceLocation = source
    }

    /// Admits one structural node without contributing a declaration or module.
    /// - Parameter collector: Exclusive state whose node/depth bounds apply even to empty content.
    /// - Throws: A structural node or depth limit violation. No child is evaluated.
    public func collect(into collector: inout DefinitionCollector) throws {
        try collector.withStructure(source: sourceLocation) { _ in }
    }
}
