/// An ordered, type-erased structural group of public definition extension points.
/// Groups preserve their nesting until compilation so empty groups and nested expansion remain
/// subject to structural count/depth admission. Group construction does not flatten recursively,
/// execute handlers or collect children; its storage is proportional to supplied immediate children.
public struct BotDefinitionGroup: BotDefinition {
    /// Immediate children in declaration order; no dictionary or type-name ordering is introduced.
    public let definitions: [any BotDefinition]
    /// Source for structural failures, or an explicit unknown builder coordinate.
    public let sourceLocation: DefinitionSourceLocation

    /// Stores a finite group without expanding its children.
    /// - Parameters:
    ///   - definitions: Immediate, immutable definitions in deterministic source/iteration order.
    ///     The author owns finite construction; compilation admits nodes before traversing children.
    ///   - source: Diagnostic coordinate; the default marks a compiler-created structural group
    ///     rather than falsely assigning the builder implementation's file to the author.
    public init(_ definitions: [any BotDefinition],
        source: DefinitionSourceLocation = .init(fileID: "<builder>", line: 0, column: 0)) {
        self.definitions = definitions
        self.sourceLocation = source
    }

    /// Admits the group, then collects each child synchronously in stored order.
    /// - Parameter collector: Exclusive compiler state. The collector owns cleanup of structural
    ///   depth on every exit, and each child uses the same count, text and capability authorities.
    /// - Throws: The first structural admission or child validation error. Remaining children are
    ///   not evaluated after failure; successful earlier children are private compilation state.
    public func collect(into collector: inout DefinitionCollector) throws {
        try collector.withStructure(source: sourceLocation) { collector in
            for definition in definitions {
                try definition.collect(into: &collector)
            }
        }
    }
}

/// Pure structural syntax for finite reusable modules and third-party contribution values.
/// Statements, chosen branches, array elements and loop iterations retain their source order.
/// Builder functions store syntax; structural/declaration/text bounds are enforced incrementally
/// during collection before the next child is expanded. Swift evaluates ordinary expressions and
/// finite loop bodies while constructing syntax, so author code must terminate cooperatively and
/// avoid I/O, task creation and handler execution. No builder can preempt arbitrary Swift code.
@resultBuilder public enum BotBuilder {
    /// Stores a complete block, including an empty block, as one admitted structural group.
    /// - Parameter components: Definition statements in source order; no child collection occurs here.
    /// - Returns: An immutable immediate-child group. Compilation enforces node/depth/text bounds.
    public static func buildBlock(_ components: any BotDefinition...) -> BotDefinitionGroup {
        BotDefinitionGroup(components)
    }

    /// Adopts a typed leaf, composite or external conformer without evaluating its collection method.
    /// - Parameter expression: An already constructed definition whose own invariants are unchanged.
    /// - Returns: The exact value, preserving its static type until its enclosing structural group.
    public static func buildExpression<Definition: BotDefinition>(_ expression: Definition) -> Definition {
        expression
    }

    /// Adopts a finite homogeneous definition array without flattening nested child structure.
    /// - Parameter expression: Definitions in caller-chosen order; an empty array is a structural node.
    /// - Returns: One ordered group. Collection halts at the first exceeded configured bound.
    public static func buildExpression<Definition: BotDefinition>(_ expression: [Definition]) -> BotDefinitionGroup {
        BotDefinitionGroup(expression)
    }

    /// Adopts a finite heterogeneous array of public definition conformers.
    /// - Parameter expression: Already constructed definitions, including external extension types,
    ///   in explicit order. No sorting, handler invocation or source discovery is performed.
    /// - Returns: One structural group that retains empty and nested children for bounded collection.
    public static func buildExpression(_ expression: [any BotDefinition]) -> BotDefinitionGroup {
        BotDefinitionGroup(expression)
    }

    /// Preserves a chosen optional branch or represents an omitted branch by an empty group.
    /// - Parameter component: The branch constructed by Swift, or nil when its condition was false.
    /// - Returns: The branch unchanged when present; otherwise one empty structural group. The
    ///   omitted branch is never constructed by this method and contributes no declarations.
    public static func buildOptional(_ component: BotDefinitionGroup?) -> BotDefinitionGroup {
        component ?? BotDefinitionGroup([])
    }

    /// Preserves the first selected branch of an if/else or switch without additional wrapping.
    /// - Parameter component: The already constructed first branch in its own declaration order.
    /// - Returns: The selected group unchanged. Swift does not construct the unselected branch.
    public static func buildEither(first component: BotDefinitionGroup) -> BotDefinitionGroup {
        component
    }

    /// Preserves the second selected branch of an if/else or switch without additional wrapping.
    /// - Parameter component: The already constructed second branch in its own declaration order.
    /// - Returns: The selected group unchanged. No work in an unselected branch is invoked here.
    public static func buildEither(second component: BotDefinitionGroup) -> BotDefinitionGroup {
        component
    }

    /// Stores finite loop iterations in iteration order without repeatedly copying an accumulated list.
    /// - Parameter components: Immediate iteration groups already constructed synchronously by Swift.
    ///   Authors must use finite, cooperatively terminating iteration; empty iterations remain counted.
    /// - Returns: One group of iteration groups. Compilation admits it before traversing iterations
    ///   and stops immediately at the first structural or declaration validation failure.
    public static func buildArray(_ components: [BotDefinitionGroup]) -> BotDefinitionGroup {
        BotDefinitionGroup(components)
    }

    /// Erases an availability-selected block's concrete contents through the common structural group.
    /// - Parameter component: Only the block selected by Swift's availability check; its source order
    ///   and structural nesting are preserved without evaluating unavailable code.
    /// - Returns: The same already erased group, with no runtime resources or tasks created.
    public static func buildLimitedAvailability(_ component: BotDefinitionGroup) -> BotDefinitionGroup {
        component
    }
}
