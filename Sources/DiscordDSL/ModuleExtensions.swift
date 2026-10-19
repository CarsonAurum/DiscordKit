/// A collision-safe declaration or module identity in an explicit namespace.
/// Components retain their exact spelling and boundaries. This value never joins IDs using a
/// delimiter, rewrites wire names, discovers services or grants runtime capabilities. Identity
/// comparison uses ordinary Swift `String` equality, including canonical Unicode equivalence. A public
/// initializer permits comparisons with expected identities; compilation validates installed values.
public struct DefinitionIdentity: Sendable, Hashable {
    /// Ordered explicit namespace components, empty for ordinary unnamespaced definitions.
    public let namespacePath: [String]
    /// Original module or declaration ID, independent of wire command/event names.
    public let id: String

    /// Records an exact identity without interpreting, validating or normalizing its components.
    /// - Parameters:
    ///   - namespacePath: Explicit namespace components in outermost-first order; default empty.
    ///   - id: Original stable module or declaration ID. Installed IDs are validated by compilation.
    public init(namespacePath: [String] = [], id: String) {
        self.namespacePath = namespacePath
        self.id = id
    }
}

/// An admitted explicit namespace in deterministic pre-order, including empty installations.
/// Namespace identity is the exact component path; module ancestry remains independent metadata.
public struct PlannedNamespace: Sendable, Equatable {
    /// Original stable component supplied by the author.
    public let id: String
    /// Outermost-first namespace components followed by this namespace's ID.
    public let path: [String]
    /// Original module ancestry at the namespace's installation site.
    public let modulePath: [String]
    /// Original source coordinate, without filesystem resolution or source rewriting.
    public let source: DefinitionSourceLocation
}

/// A bounded identity scope for installing reusable modules or contributions more than once.
/// Namespaces change only authoring identity. They never rename commands, selectors, routes or
/// custom metadata, and therefore cannot resolve duplicate wire routes in downstream compilers.
/// Every full namespace path may be installed once; nested path components are unambiguous.
public struct ModuleNamespace<Body: BotDefinition>: BotDefinition {
    /// Stable namespace component, validated during compilation.
    public let namespaceID: String
    /// Original namespace authoring coordinate.
    public let sourceLocation: DefinitionSourceLocation
    /// Finite stored definitions whose original metadata remains unchanged.
    public let body: Body

    /// Stores a namespace while capturing the initializer's caller coordinate.
    /// - Parameters:
    ///   - id: Nonempty stable component, at most 128 UTF-8 bytes without ASCII controls.
    ///   - fileID: Caller compiler file identifier by default; no filesystem lookup occurs.
    ///   - line: Caller one-based line by default; zero means unavailable.
    ///   - column: Caller one-based column by default; zero means unavailable.
    ///   - body: Finite synchronous builder evaluated once now; it must not perform I/O, start
    ///     tasks or invoke handlers. Namespace admission occurs later during compilation.
    public init(id: String, fileID: String = #fileID, line: UInt = #line, column: UInt = #column,
                @BotBuilder body: () -> Body) {
        self.namespaceID = id
        self.sourceLocation = DefinitionSourceLocation(fileID: fileID, line: line, column: column)
        self.body = body()
    }

    /// Stores a namespace with a previously captured coordinate.
    /// - Parameters:
    ///   - id: Stable explicit namespace component; duplicate full paths fail compilation.
    ///   - source: Exact authoring coordinate; zero line/column may indicate unknown source.
    ///   - body: Finite synchronous builder evaluated once now, without I/O, tasks or execution.
    ///     Metadata and capability requirements remain subject to the common compilation admission.
    public init(id: String, source: DefinitionSourceLocation, @BotBuilder body: () -> Body) {
        self.namespaceID = id
        self.sourceLocation = source
        self.body = body()
    }

    /// Admits this namespace before collecting its stored children in declaration order.
    /// - Parameter collector: Exclusive synchronous state sharing all count, depth and text budgets.
    /// - Throws: Invalid/duplicate namespace identity, namespace/structural/depth/text admission,
    ///   or a child's error. No partial plan escapes; namespace ancestry is restored on all exits.
    public func collect(into collector: inout DefinitionCollector) throws {
        try collector.withNamespace(id: namespaceID, source: sourceLocation) { nested in
            try body.collect(into: &nested)
        }
    }
}

/// Explicit typed dependencies validated before a reusable module evaluates its child factory.
/// Implementations inspect finite local configuration only. Dependencies may contain injected
/// actor or service references, but validation must not invoke asynchronous work, perform I/O,
/// inspect ambient credentials or consult a global service registry. Owned compilation is inert;
/// arbitrary application validation code must cooperate and is not sandboxed.
public protocol ModuleDependencies: Sendable {
    /// Validates local configuration synchronously without starting dependent work.
    /// - Throws: An application-defined error for invalid or missing configuration. Compilation
    ///   translates every failure into bounded `DefinitionDiagnostic.Code.invalidDependencies`
    ///   at the module coordinate and omits the original error and dependency contents.
    func validate() throws
}

/// A reusable module with explicit typed dependency injection and lazy, validated body creation.
/// Initialization stores dependencies and a factory without invoking either. Collection first
/// admits the module, then validates dependencies, then constructs and collects one finite body.
/// No service lookup, handler execution, tasks, registration or I/O is owned by this value.
public struct DependentModule<Dependencies: ModuleDependencies, Body: BotDefinition>: BotDefinition {
    /// Stable explicit module instance ID, unique within the installed namespace.
    public let moduleID: String
    /// Original module coordinate used for admission and dependency diagnostics.
    public let sourceLocation: DefinitionSourceLocation
    /// Explicitly supplied immutable dependency value; no ambient resolution is attempted.
    public let dependencies: Dependencies
    private let makeBody: @Sendable (Dependencies) -> Body

    /// Stores a lazy module factory while capturing the initializer's caller coordinate.
    /// - Parameters:
    ///   - id: Stable explicit module ID; invalid or duplicate IDs fail before dependency validation.
    ///   - dependencies: Typed injected configuration and references, retained without validation now.
    ///   - fileID: Caller compiler file identifier by default; no filesystem lookup occurs.
    ///   - line: Caller one-based line by default; zero means unavailable.
    ///   - column: Caller one-based column by default; zero means unavailable.
    ///   - body: Retained synchronous builder invoked once per admitted compilation, after successful
    ///     validation. It must terminate without tasks, I/O or handlers. It receives the same injected value.
    public init(id: String, dependencies: Dependencies, fileID: String = #fileID,
                line: UInt = #line, column: UInt = #column,
                @BotBuilder body: @escaping @Sendable (Dependencies) -> Body) {
        self.moduleID = id
        self.sourceLocation = DefinitionSourceLocation(fileID: fileID, line: line, column: column)
        self.dependencies = dependencies
        self.makeBody = body
    }

    /// Stores a lazy module factory using a previously captured module coordinate.
    /// - Parameters:
    ///   - id: Explicit stable module ID, unique within its explicit namespace during compilation.
    ///   - dependencies: Injected local configuration and references, never looked up or validated now.
    ///   - source: Exact authoring coordinate for bounded admission/dependency diagnostics.
    ///   - body: Finite retained synchronous builder. Each admitted compilation invokes it once after
    ///     dependency validation, passing the original value; it must not start I/O, tasks or handlers.
    public init(id: String, dependencies: Dependencies, source: DefinitionSourceLocation,
                @BotBuilder body: @escaping @Sendable (Dependencies) -> Body) {
        self.moduleID = id
        self.sourceLocation = source
        self.dependencies = dependencies
        self.makeBody = body
    }

    /// Admits the module, validates its injected dependencies, then constructs and collects children.
    /// - Parameter collector: Exclusive synchronous admission context; all nested declarations retain
    ///   common budgets, capability/kind checks and original source metadata.
    /// - Throws: Module admission or child errors, or bounded `invalidDependencies` for any validation
    ///   failure. Rejected modules skip validation; invalid dependencies skip body evaluation entirely.
    public func collect(into collector: inout DefinitionCollector) throws {
        try collector.withModule(id: moduleID, source: sourceLocation) { nested in
            try nested.validateDependencies(dependencies, source: sourceLocation)
            try makeBody(dependencies).collect(into: &nested)
        }
    }
}
