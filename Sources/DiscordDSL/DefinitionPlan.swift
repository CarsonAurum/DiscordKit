import DiscordCore

/// A source coordinate retained with a declaration, without reading the source file.
/// Zero line/column values indicate a synthetic or unavailable location. File identifiers
/// are caller supplied; they are neither resolved nor treated as trusted filesystem paths.
public struct DefinitionSourceLocation: Sendable, Hashable {
    /// Compiler file identifier or a synthetic label.
    public let fileID: String
    /// One-based source line, or zero when unavailable.
    public let line: UInt
    /// One-based source column, or zero when unavailable.
    public let column: UInt

    /// Captures a coordinate synchronously without reading files or environment variables.
    /// - Parameters:
    ///   - fileID: Compiler file identifier by default; any explicit label is retained.
    ///   - line: Compiler source line by default; zero means unknown.
    ///   - column: Compiler source column by default; zero means unknown.
    public init(fileID: String = #fileID, line: UInt = #line, column: UInt = #column) {
        self.fileID = fileID
        self.line = line
        self.column = column
    }
}

/// Admission limits for synchronous structural expansion, separate from deployment capacity.
/// Invalid configurations are retained until compilation, which rejects them before visiting
/// user definitions. Zero count/byte limits are valid for intentionally empty admission.
public struct DefinitionLimits: Sendable, Equatable {
    /// Maximum globally distinct module instances; default 256.
    public let maxModules: Int
    /// Maximum simultaneously open module/group/contribution scopes, in `1...128`; default 32.
    public let maxDepth: Int
    /// Maximum contributed declarations; default 4,096.
    public let maxDeclarations: Int
    /// Aggregate UTF-8 metadata and compact JSON payload bytes; default 1 MiB.
    public let maxTextBytes: Int
    /// Maximum visited module/group/contribution scopes, including empty groups; default 16,384.
    public let maxStructuralNodes: Int

    /// Configures finite compilation admission without expanding any definitions.
    /// - Parameters:
    ///   - maxModules: Nonnegative module count, default 256.
    ///   - maxDepth: Structural depth in `1...128`, default 32; a hard ceiling protects the stack.
    ///   - maxDeclarations: Nonnegative leaf count, default 4,096.
    ///   - maxTextBytes: Nonnegative aggregate byte budget, default 1,048,576.
    ///   - maxStructuralNodes: Nonnegative visited scope count, default 16,384.
    public init(maxModules: Int = 256, maxDepth: Int = 32, maxDeclarations: Int = 4_096,
                maxTextBytes: Int = 1_048_576, maxStructuralNodes: Int = 16_384) {
        self.maxModules = maxModules
        self.maxDepth = maxDepth
        self.maxDeclarations = maxDeclarations
        self.maxTextBytes = maxTextBytes
        self.maxStructuralNodes = maxStructuralNodes
    }
}

/// One bounded structural failure. Compilation fails on the first error rather than
/// collecting unbounded diagnostics. No payload or declaration text appears in this error.
public struct DefinitionDiagnostic: Error, Sendable, Equatable {
    /// Stable failure categories; applications should display their own localized explanations.
    public enum Code: Sendable, Equatable {
        /// A negative limit or depth outside `1...128` was supplied.
        case invalidLimits
        /// An ID, kind or capability is empty, exceeds 128 UTF-8 bytes, or contains ASCII controls.
        case invalidIdentity
        /// A module ID has already been installed anywhere in the plan.
        case duplicateModuleID
        /// A declaration ID has already been contributed anywhere in the plan.
        case duplicateDeclarationID
        /// The compiler's explicitly supported kinds do not contain the declaration kind.
        case unsupportedKind
        /// An explicitly required capability is absent from the supplied host capabilities.
        case unsupportedCapability
        /// Module count admission was exhausted before expanding the next body.
        case moduleLimit
        /// Structural nesting admission was exhausted before visiting the next scope.
        case depthLimit
        /// Declaration count admission was exhausted before retaining the next contribution.
        case declarationLimit
        /// Aggregate metadata or serialized payload bytes exceed admission.
        case textLimit
        /// Visited scope admission was exhausted, including for empty groups.
        case structureLimit
        /// A payload exceeds the shared JSON depth/node limits or cannot be serialized.
        case invalidPayload
    }

    /// Machine-readable failure category.
    public let code: Code
    /// Failure coordinate; the file identifier is truncated to at most 256 UTF-8 bytes.
    public let source: DefinitionSourceLocation
    /// Already admitted ancestor module IDs, bounded by depth and the 128-byte identity limit.
    public let modulePath: [String]

    /// Creates a diagnostic while bounding caller-supplied display context.
    /// - Parameters:
    ///   - code: Structural failure category.
    ///   - source: Coordinate; only a bounded file-label prefix is retained.
    ///   - modulePath: At most 128 ancestors, each reduced to at most 128 UTF-8 bytes.
    public init(code: Code, source: DefinitionSourceLocation, modulePath: [String]) {
        self.code = code
        self.source = DefinitionSourceLocation(
            fileID: Self.boundedLabel(source.fileID, maximumBytes: 256),
            line: source.line, column: source.column)
        self.modulePath = modulePath.prefix(128).map {
            Self.boundedLabel($0, maximumBytes: 128)
        }
    }

    /// Copies only complete Unicode scalars into a bounded diagnostic label.
    /// - Parameters:
    ///   - value: Untrusted source or identity label; no normalization is performed.
    ///   - maximumBytes: Nonnegative UTF-8 output bound, fixed by the diagnostic initializer.
    /// - Returns: The longest scalar-aligned prefix within the bound, without replacement growth.
    private static func boundedLabel(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var count = 0
        for scalar in value.unicodeScalars {
            let part = String(scalar)
            guard part.utf8.count <= maximumBytes - count else { break }
            result.append(part)
            count += part.utf8.count
        }
        return result
    }
}

/// Public escape hatch for finite metadata consumed by an explicitly selected downstream compiler.
/// It is useful without a command runtime: applications can validate and inspect a catalog of
/// their own kinds. This value grants no protocol support, permissions, execution or I/O.
public struct RawDefinitionContribution: DefinitionContribution, Sendable, Equatable {
    /// Globally unique, explicit stable declaration instance ID, validated during compilation.
    public let id: String
    /// Application-defined kind, accepted only when explicitly listed in `supportedKinds`.
    public let kind: String
    /// All host capabilities required to adopt this declaration; no capabilities are inferred.
    public let requiredCapabilities: Set<String>
    /// Human/schema text counted verbatim as UTF-8 bytes without interpretation.
    public let text: String
    /// Lossless metadata; compact deterministic serialization contributes to the byte budget.
    public let payload: JSONValue
    /// Original declaration coordinate.
    public let source: DefinitionSourceLocation
    /// The raw declaration itself; typed third-party contributions expose the same snapshot contract.
    public var declaration: RawDefinitionContribution { self }

    /// Records metadata without validating, registering or executing it.
    /// - Parameters:
    ///   - id: Nonempty stable identity, at most 128 UTF-8 bytes without ASCII controls.
    ///   - kind: Nonempty compiler-supported kind with the same identity restrictions.
    ///   - requiredCapabilities: Explicit capability identities; default empty.
    ///   - text: Metadata text, default empty; no escaping or wire interpretation occurs.
    ///   - payload: Lossless JSON, default null. Compilation enforces 64-container/100,000-node
    ///     JSON limits in addition to the remaining aggregate byte budget.
    ///   - source: Source coordinate, captured by the supplied value; no source file is opened.
    public init(id: String, kind: String, requiredCapabilities: Set<String> = [], text: String = "",
                payload: JSONValue = .null, source: DefinitionSourceLocation) {
        self.id = id
        self.kind = kind
        self.requiredCapabilities = requiredCapabilities
        self.text = text
        self.payload = payload
        self.source = source
    }

    /// Records raw metadata while capturing the author's call site without opening source files.
    /// - Parameters:
    ///   - id: Globally unique stable ID, validated at compilation; nonempty and at most 128 UTF-8 bytes.
    ///   - kind: Explicit downstream kind; compilation fails unless the host supports it.
    ///   - requiredCapabilities: Explicit host requirements, default empty; no capability is inferred.
    ///   - text: Verbatim metadata text, default empty, counted against aggregate UTF-8 admission.
    ///   - payload: Lossless JSON metadata, default null; compilation enforces byte/depth/node admission.
    ///   - fileID: Caller compiler file identifier by default; no filesystem lookup occurs.
    ///   - line: Caller one-based line by default; explicit zero means unavailable.
    ///   - column: Caller one-based column by default; explicit zero means unavailable.
    ///
    /// This overload starts no work and performs no validation. Use the explicit-source overload
    /// when forwarding a location already captured by another authoring abstraction.
    public init(id: String, kind: String, requiredCapabilities: Set<String> = [], text: String = "",
                payload: JSONValue = .null, fileID: String = #fileID, line: UInt = #line,
                column: UInt = #column) {
        self.init(id: id, kind: kind, requiredCapabilities: requiredCapabilities, text: text,
                  payload: payload, source: .init(fileID: fileID, line: line, column: column))
    }
}

/// An installed module in pre-order expansion order.
public struct PlannedModule: Sendable, Equatable {
    /// Explicit instance identity, unique throughout the compiled plan.
    public let id: String
    /// Ancestor IDs followed by this module's ID.
    public let path: [String]
    /// Original module coordinate.
    public let source: DefinitionSourceLocation
}

/// A declaration snapshot in deterministic, depth-first source order.
public struct PlannedDeclaration: Sendable, Equatable {
    /// Validated finite metadata, independent of any retained executable behavior.
    public let declaration: RawDefinitionContribution
    /// Ancestor module identities; empty for top-level contributions.
    public let modulePath: [String]
}

/// Comparable description of one compilation. Equality compares exact metadata, locations,
/// order and accounting; it does not claim equivalence of arbitrary user handler behavior.
public struct DefinitionDescription: Sendable, Equatable {
    /// Module installations in deterministic pre-order.
    public let modules: [PlannedModule]
    /// Contributions in deterministic depth-first source order.
    public let declarations: [PlannedDeclaration]
    /// Admitted metadata/payload bytes. Repeated source labels count once per declaration/module.
    public let textBytes: Int
    /// Visited structural scopes, including modules, builder groups and contributions.
    public let structureCount: Int
}

/// An immutable admitted definition plan. Construction and compilation own no tasks, sockets,
/// registrations, subscriptions or persistence. Typed contributions are retained for later
/// independently adopted lowering; their execution methods are never invoked by this library.
public struct DefinitionPlan: Sendable {
    /// Reproducible metadata snapshot; compare this value rather than object identity.
    public let description: DefinitionDescription
    /// Typed extension values aligned exactly with `description.declarations`.
    /// A custom contribution must expose deterministic metadata and keep its own behavior inert.
    public let contributions: [any DefinitionContribution]

    /// Expands and validates a finite definition synchronously, in declaration order.
    /// - Parameters:
    ///   - definition: Root structural definition; custom expansion/body/getter code must terminate,
    ///     propagate failures, and avoid side effects. Arbitrary Swift is not sandboxed.
    ///   - supportedKinds: Explicitly admitted contribution kinds, default empty (fail closed).
    ///   - capabilities: Available host capabilities, default empty; requirements are never enabled implicitly.
    ///   - limits: Structural and aggregate text admission, with finite standard defaults.
    /// - Returns: Immutable description and typed contributions; no partial plan escapes on failure.
    /// - Throws: `DefinitionDiagnostic` for admission/identity/capability errors, or a custom expansion
    ///   error. A swallowed collector error remains terminal and is rethrown at completion.
    ///
    /// No suspension or I/O occurs in owned code. Runtime is proportional to visited structure,
    /// admitted text and deterministic JSON key sorting. Bounds govern compilation, not memory
    /// already allocated by user constructors/builders. Concurrent compilations share no state.
    public static func compile<D: BotDefinition>(_ definition: D, supportedKinds: Set<String> = [],
        capabilities: Set<String> = [], limits: DefinitionLimits = .init()) throws -> Self {
        var collector = DefinitionCollector(supportedKinds: supportedKinds, capabilities: capabilities, limits: limits)
        try collector.validateLimits()
        do { try definition.collect(into: &collector) }
        catch { throw collector.failure ?? error }
        if let failure = collector.failure { throw failure }
        return Self(description: DefinitionDescription(modules: collector.modules,
            declarations: collector.declarations, textBytes: collector.textBytes,
            structureCount: collector.structureCount), contributions: collector.contributions)
    }
}

/// Compiler-owned mutable admission context exposed only for synchronous extension expansion.
/// Obtain one through `BotDefinition.collect(into:)`; there is no public initializer or plan
/// extraction. Composite extensions must use `withStructure` and contribute through `append`
/// or `withModule`, propagate errors, and avoid retaining/copying the collector for later work.
public struct DefinitionCollector: Sendable {
    private let supportedKinds: Set<String>
    private let capabilities: Set<String>
    private let limits: DefinitionLimits
    fileprivate var modules: [PlannedModule] = []
    fileprivate var declarations: [PlannedDeclaration] = []
    fileprivate var contributions: [any DefinitionContribution] = []
    fileprivate var textBytes = 0
    fileprivate var structureCount = 0
    fileprivate var failure: (any Error)?
    private var moduleIDs: Set<String> = []
    private var declarationIDs: Set<String> = []
    private var modulePath: [String] = []
    private var depth = 0

    /// Creates isolated admission state without inspecting definitions.
    /// - Parameters:
    ///   - supportedKinds: Explicit downstream kind allowlist.
    ///   - capabilities: Host capability allowlist.
    ///   - limits: Configuration validated before expansion.
    fileprivate init(supportedKinds: Set<String>, capabilities: Set<String>, limits: DefinitionLimits) {
        self.supportedKinds = supportedKinds
        self.capabilities = capabilities
        self.limits = limits
    }

    /// Rejects invalid limits before any custom definition code is visited.
    /// - Throws: `DefinitionDiagnostic` with `invalidLimits` for negative budgets or unsafe depth.
    fileprivate mutating func validateLimits() throws {
        guard limits.maxModules >= 0, (1...128).contains(limits.maxDepth),
              limits.maxDeclarations >= 0, limits.maxTextBytes >= 0, limits.maxStructuralNodes >= 0 else {
            throw reject(.invalidLimits, source: .init(fileID: "<configuration>", line: 0, column: 0))
        }
    }

    /// Opens one bounded composite scope and restores nesting on every exit.
    /// - Parameters:
    ///   - source: Diagnostic coordinate, synthetic by default; it does not itself consume text admission.
    ///   - body: Synchronous ordered expansion, called only after scope/depth admission succeeds.
    /// - Throws: The first terminal collector error or the body's error. Errors poison the collector
    ///   even if custom enclosing code catches them; no successful partial plan can escape.
    public mutating func withStructure(source: DefinitionSourceLocation = .init(fileID: "<structure>", line: 0, column: 0),
                                      _ body: (inout DefinitionCollector) throws -> Void) throws {
        if let failure { throw failure }
        guard depth < limits.maxDepth else { throw reject(.depthLimit, source: source) }
        guard structureCount < limits.maxStructuralNodes else { throw reject(.structureLimit, source: source) }
        depth += 1
        structureCount += 1
        defer { depth -= 1 }
        do { try body(&self) }
        catch {
            if failure == nil { failure = error }
            throw failure ?? error
        }
    }

    /// Admits an explicit module instance before expanding its body.
    /// - Parameters:
    ///   - id: Globally unique stable ID with the identity restrictions documented by the raw leaf.
    ///   - source: Module source coordinate, counted in the aggregate text budget.
    ///   - body: Synchronous expansion; not called if module, depth, identity or byte admission fails.
    /// - Throws: Structural/duplicate/identity errors or the body's error; ancestor scope is always restored.
    public mutating func withModule(id: String, source: DefinitionSourceLocation,
                                   _ body: (inout DefinitionCollector) throws -> Void) throws {
        try withStructure(source: source) { collector in
            try collector.validateIdentity(id, source: source)
            guard !collector.moduleIDs.contains(id) else { throw collector.reject(.duplicateModuleID, source: source) }
            guard collector.modules.count < collector.limits.maxModules else { throw collector.reject(.moduleLimit, source: source) }
            try collector.charge(id, source: source)
            try collector.charge(source.fileID, source: source)
            collector.moduleIDs.insert(id)
            collector.modulePath.append(id)
            collector.modules.append(PlannedModule(id: id, path: collector.modulePath, source: source))
            defer { collector.modulePath.removeLast() }
            try body(&collector)
        }
    }

    /// Admits and retains one typed leaf without invoking any execution behavior.
    /// - Parameter contribution: Third-party or raw leaf; its declaration getter is called exactly once,
    ///   after structural/count admission. The returned immutable snapshot drives all validation.
    /// - Throws: Count/depth/identity/kind/capability/text/JSON admission errors. Failed appends
    ///   poison compilation and never produce an executable or partial plan.
    public mutating func append(_ contribution: any DefinitionContribution) throws {
        try withStructure { collector in
            guard collector.declarations.count < collector.limits.maxDeclarations else {
                throw collector.reject(.declarationLimit, source: .init(fileID: "<contribution>", line: 0, column: 0))
            }
            let raw = contribution.declaration
            try collector.validateIdentity(raw.id, source: raw.source)
            try collector.validateIdentity(raw.kind, source: raw.source)
            guard !collector.declarationIDs.contains(raw.id) else { throw collector.reject(.duplicateDeclarationID, source: raw.source) }
            guard collector.supportedKinds.contains(raw.kind) else { throw collector.reject(.unsupportedKind, source: raw.source) }
            try collector.charge(raw.id, source: raw.source)
            try collector.charge(raw.kind, source: raw.source)
            try collector.charge(raw.text, source: raw.source)
            try collector.charge(raw.source.fileID, source: raw.source)
            // Every identity consumes at least one byte, so even a huge capability set
            // is rejected before sorting or copying it into retained metadata.
            guard raw.requiredCapabilities.count <= collector.limits.maxTextBytes - collector.textBytes else {
                throw collector.reject(.textLimit, source: raw.source)
            }
            for capability in raw.requiredCapabilities {
                try collector.validateIdentity(capability, source: raw.source)
            }
            for capability in raw.requiredCapabilities.sorted() {
                try collector.charge(capability, source: raw.source)
                guard collector.capabilities.contains(capability) else {
                    throw collector.reject(.unsupportedCapability, source: raw.source)
                }
            }
            let remaining = collector.limits.maxTextBytes - collector.textBytes
            guard remaining > 0 else { throw collector.reject(.textLimit, source: raw.source) }
            var lowerBoundRemaining = remaining
            var payloadNodes = 0
            try collector.validatePayloadShape(raw.payload, nodes: &payloadNodes, depth: 0, source: raw.source)
            try collector.preflightPayload(raw.payload, remaining: &lowerBoundRemaining, source: raw.source)
            do {
                let bytes = try raw.payload.serialized(limits: JSONLimits(maximumBytes: remaining))
                collector.textBytes += bytes.count
            } catch JSONValueError.maximumBytesExceeded {
                throw collector.reject(.textLimit, source: raw.source)
            } catch {
                throw collector.reject(.invalidPayload, source: raw.source)
            }
            collector.declarationIDs.insert(raw.id)
            collector.declarations.append(PlannedDeclaration(declaration: raw, modulePath: collector.modulePath))
            collector.contributions.append(contribution)
        }
    }

    /// Validates JSON shape before byte admission so unordered object traversal cannot change error priority.
    /// - Parameters:
    ///   - value: Current subtree, visited without copying or sorting dictionary keys.
    ///   - nodes: Admitted values, bounded to 100,000 before incrementing.
    ///   - depth: Already open containers; a new container is admitted only below 64.
    ///   - source: Declaration coordinate on failure.
    /// - Throws: `invalidPayload` for depth or node admission, independent of JSON object key order.
    private mutating func validatePayloadShape(_ value: JSONValue, nodes: inout Int,
        depth: Int, source: DefinitionSourceLocation) throws {
        guard nodes < 100_000 else { throw reject(.invalidPayload, source: source) }
        nodes += 1
        switch value {
        case .array(let values):
            guard depth < 64, values.count <= 100_000 - nodes else { throw reject(.invalidPayload, source: source) }
            for child in values { try validatePayloadShape(child, nodes: &nodes, depth: depth + 1, source: source) }
        case .object(let values):
            guard depth < 64, values.count <= 100_000 - nodes else { throw reject(.invalidPayload, source: source) }
            for child in values.values { try validatePayloadShape(child, nodes: &nodes, depth: depth + 1, source: source) }
        default: break
        }
    }

    /// Bounds input metadata before the shared serializer sorts object keys or escapes strings.
    /// - Parameters:
    ///   - value: Current lossless JSON subtree, visited without allocating a key array.
    ///   - remaining: Remaining lower-bound output bytes, decremented for raw text and delimiters.
    ///   - source: Original declaration coordinate for all failures.
    /// - Throws: `textLimit` for an impossible byte fit; shape admission has already succeeded.
    ///
    /// Raw UTF-8 text is a lower bound because JSON escaping can expand it. The subsequent bounded
    /// serializer enforces the exact byte count. This pass ensures even rejected preconstructed
    /// dictionaries and strings cannot require sorting or scanning beyond admitted input bounds.
    private mutating func preflightPayload(_ value: JSONValue, remaining: inout Int,
        source: DefinitionSourceLocation) throws {
        switch value {
        case .null:
            try consumePayloadBytes(4, remaining: &remaining, source: source)
        case .bool(let flag):
            try consumePayloadBytes(flag ? 4 : 5, remaining: &remaining, source: source)
        case .number(let number):
            try consumePayloadText(number.rawValue, remaining: &remaining, source: source)
        case .string(let string):
            try consumePayloadBytes(2, remaining: &remaining, source: source)
            try consumePayloadText(string, remaining: &remaining, source: source)
        case .array(let values):
            try consumePayloadBytes(2, remaining: &remaining, source: source)
            try consumePayloadBytes(max(0, values.count - 1), remaining: &remaining, source: source)
            for child in values {
                try preflightPayload(child, remaining: &remaining, source: source)
            }
        case .object(let values):
            try consumePayloadBytes(2, remaining: &remaining, source: source)
            try consumePayloadBytes(max(0, values.count - 1), remaining: &remaining, source: source)
            for (key, child) in values {
                try consumePayloadBytes(3, remaining: &remaining, source: source)
                try consumePayloadText(key, remaining: &remaining, source: source)
                try preflightPayload(child, remaining: &remaining, source: source)
            }
        }
    }

    /// Accounts for JSON syntax or scalar bytes without overflowing the remaining budget.
    /// - Parameters:
    ///   - count: Nonnegative byte count derived from bounded delimiters or container counts.
    ///   - remaining: Nonnegative remaining lower-bound output capacity.
    ///   - source: Declaration coordinate on failure.
    /// - Throws: `textLimit` before subtracting more bytes than remain.
    private mutating func consumePayloadBytes(_ count: Int, remaining: inout Int,
                                             source: DefinitionSourceLocation) throws {
        guard count <= remaining else { throw reject(.textLimit, source: source) }
        remaining -= count
    }

    /// Measures only a bounded prefix of a JSON string/number/key before any escaping or sorting.
    /// - Parameters:
    ///   - value: Exact raw Unicode text or validated numeric lexeme.
    ///   - remaining: Lower-bound capacity consumed by the measured UTF-8 bytes.
    ///   - source: Declaration coordinate on failure.
    /// - Throws: `textLimit` for raw text already too large to fit its JSON representation.
    private mutating func consumePayloadText(_ value: String, remaining: inout Int,
                                            source: DefinitionSourceLocation) throws {
        let count = value.utf8.prefix(remaining == Int.max ? remaining : remaining + 1).count
        try consumePayloadBytes(count, remaining: &remaining, source: source)
    }

    /// Checks bounded explicit identities without trimming, normalizing or inventing names.
    /// - Parameters:
    ///   - value: Module/declaration/kind/capability identity to inspect.
    ///   - source: Coordinate used for failure attribution.
    /// - Throws: `invalidIdentity` for empty/oversized strings or ASCII controls, including DEL.
    private mutating func validateIdentity(_ value: String, source: DefinitionSourceLocation) throws {
        guard !value.isEmpty, value.utf8.prefix(129).count <= 128,
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw reject(.invalidIdentity, source: source)
        }
    }

    /// Charges a UTF-8 string before retaining it, without integer overflow or full oversized scans.
    /// - Parameters:
    ///   - value: Exact metadata spelling, including repeated source labels.
    ///   - source: Failure coordinate; text content is never included in the diagnostic.
    /// - Throws: `textLimit` before cumulative admission exceeds the configured budget.
    private mutating func charge(_ value: String, source: DefinitionSourceLocation) throws {
        let remaining = limits.maxTextBytes - textBytes
        let count = value.utf8.prefix(remaining == Int.max ? remaining : remaining + 1).count
        guard count <= remaining else { throw reject(.textLimit, source: source) }
        textBytes += count
    }

    /// Stores the first bounded admission diagnostic, preserving terminal failure across catches.
    /// - Parameters:
    ///   - code: Failure category.
    ///   - source: Original source coordinate, truncated by the diagnostic initializer.
    /// - Returns: The bounded diagnostic for immediate throwing; no payload/text is copied.
    private mutating func reject(_ code: DefinitionDiagnostic.Code, source: DefinitionSourceLocation) -> DefinitionDiagnostic {
        let diagnostic = DefinitionDiagnostic(code: code, source: source, modulePath: modulePath)
        if failure == nil { failure = diagnostic }
        return diagnostic
    }
}
