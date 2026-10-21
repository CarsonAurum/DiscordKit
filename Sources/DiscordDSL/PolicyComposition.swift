import DiscordLogging

/// A sanitized structural admission failure that contains no invocation data or user error text.
/// Predicate, middleware and terminal errors propagate unchanged and are not represented here.
public enum PolicyCompositionError: Error, Sendable, Equatable {
    /// A node bound is nonpositive, or a depth bound falls outside `1...128`.
    case invalidLimits
    /// The complete composition contains more nodes than the explicitly selected budget.
    case nodeLimit
    /// The complete composition exceeds the explicitly selected nesting budget.
    case depthLimit
}

/// Explicit finite structural budgets for policy and middleware execution.
/// A leaf has one node and depth one; each composition adds one node and one level above its
/// children. These bounds admit authoring structure, not network throughput or task capacity.
public struct PolicyLimits: Sendable, Equatable {
    /// Maximum number of leaves and composition nodes, inclusive; default 256.
    public let maximumNodes: Int
    /// Maximum composition depth, inclusive and restricted to `1...128`; default 32.
    public let maximumDepth: Int

    /// Validates and records finite budgets without invoking any user work.
    /// - Parameters:
    ///   - maximumNodes: Positive total node budget, default 256. Every positive `Int` is finite.
    ///   - maximumDepth: Nesting budget in `1...128`, default 32. The hard ceiling bounds the
    ///     library's recursive closure traversal; arbitrary injected work must terminate cooperatively.
    /// - Throws: `PolicyCompositionError.invalidLimits` for a nonpositive node budget or depth
    ///   outside the supported range. No predicate, middleware or terminal closure is invoked.
    public init(maximumNodes: Int = 256, maximumDepth: Int = 32) throws {
        guard maximumNodes > 0, (1...128).contains(maximumDepth) else {
            throw PolicyCompositionError.invalidLimits
        }
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
    }
}

/// An immutable asynchronous invocation predicate with bounded, deterministic Boolean composition.
/// Construction, composition and validation do not execute predicates or start tasks or I/O.
/// Explicit evaluation executes on the caller's task; injected predicates own their side effects,
/// suspension points, cleanup and error behavior. Concurrent evaluations share no library state.
public struct InvocationPolicy<Input: Sendable>: Sendable {
    /// Total leaves and composition nodes, saturating at `Int.max` rather than overflowing.
    public let nodeCount: Int
    /// Maximum leaf-to-root nesting depth, saturating at `Int.max` rather than overflowing.
    public let depth: Int
    /// Sticky overflow prevents saturated counts from admitting a larger-than-representable graph.
    private let nodeCountOverflowed: Bool
    /// Stored execution closure; structural admission occurs once at the public entry point.
    private let operation: @Sendable (Input) async throws -> Bool

    /// Stores a leaf predicate without executing it or acquiring resources.
    /// - Parameter predicate: Sendable per-invocation decision. `true` allows the invocation;
    ///   `false` denies it. Called only after structural admission and cancellation checking.
    ///   Errors propagate unchanged. The predicate owns any I/O, resource cleanup and partial
    ///   side effects it explicitly performs, and must cooperate with cancellation while suspended.
    public init(_ predicate: @escaping @Sendable (Input) async throws -> Bool) {
        self.nodeCount = 1
        self.depth = 1
        self.nodeCountOverflowed = false
        self.operation = { input in
            try Task.checkCancellation()
            DiscordLog.makeLogger("dsl.policy").trace("Invocation predicate leaf entered", metadata: ["dk.event": "dsl.policy.leaf_entered"])
            defer { DiscordLog.makeLogger("dsl.policy").trace("Invocation predicate leaf exited", metadata: ["dk.event": "dsl.policy.leaf_exited"]) }
            let allowed = try await predicate(input)
            DiscordLog.makeLogger("dsl.policy").trace("Invocation predicate leaf decided", metadata: ["dk.event": "dsl.policy.leaf_decided", "dk.allowed": .stringConvertible(allowed)])
            return allowed
        }
    }

    /// Records a composed operation whose descendants already check cancellation before leaves.
    /// - Parameters:
    ///   - nodeCount: Positive saturating count of the complete immutable expression.
    ///   - depth: Positive saturating depth of the complete immutable expression.
    ///   - nodeCountOverflowed: Sticky evidence that the actual count exceeds `Int.max`.
    ///   - operation: Inert closure retaining child operations without running them now.
    private init(nodeCount: Int, depth: Int, nodeCountOverflowed: Bool,
                 operation: @escaping @Sendable (Input) async throws -> Bool) {
        self.nodeCount = nodeCount
        self.depth = depth
        self.nodeCountOverflowed = nodeCountOverflowed
        self.operation = operation
    }

    /// Combines decisions in left-to-right order, skipping the right predicate when this one denies.
    /// - Parameter other: Right child, evaluated only after this policy returns `true`.
    /// - Returns: An inert conjunction with the same behavior as `self && other`. A thrown left
    ///   error or cancellation prevents right execution; no rollback or implicit retry occurs.
    public func and(_ other: Self) -> Self {
        let count = policyCompositionCount(nodeCount, other.nodeCount)
        return Self(nodeCount: count.value, depth: policySaturatingAdd(max(depth, other.depth), 1),
                    nodeCountOverflowed: nodeCountOverflowed || other.nodeCountOverflowed || count.overflowed) { input in
            guard try await operation(input) else {
                DiscordLog.makeLogger("dsl.policy").trace("Conjunction skipped its right predicate after denial", metadata: ["dk.event": "dsl.policy.short_circuited", "dk.operator": "and"])
                return false
            }
            DiscordLog.makeLogger("dsl.policy").trace("Conjunction proceeding to its right predicate", metadata: ["dk.event": "dsl.policy.right_entered", "dk.operator": "and"])
            return try await other.operation(input)
        }
    }

    /// Combines decisions in left-to-right order, skipping the right predicate when this one allows.
    /// - Parameter other: Right child, evaluated only after this policy returns `false`.
    /// - Returns: An inert disjunction with the same behavior as `self || other`. A thrown left
    ///   error or cancellation prevents right execution; skipped predicates have no side effects.
    public func or(_ other: Self) -> Self {
        let count = policyCompositionCount(nodeCount, other.nodeCount)
        return Self(nodeCount: count.value, depth: policySaturatingAdd(max(depth, other.depth), 1),
                    nodeCountOverflowed: nodeCountOverflowed || other.nodeCountOverflowed || count.overflowed) { input in
            guard try await !operation(input) else {
                DiscordLog.makeLogger("dsl.policy").trace("Disjunction skipped its right predicate after allowance", metadata: ["dk.event": "dsl.policy.short_circuited", "dk.operator": "or"])
                return true
            }
            DiscordLog.makeLogger("dsl.policy").trace("Disjunction proceeding to its right predicate", metadata: ["dk.event": "dsl.policy.right_entered", "dk.operator": "or"])
            return try await other.operation(input)
        }
    }

    /// Reverses a successfully evaluated Boolean decision without converting errors into decisions.
    /// - Returns: An inert negation with the same behavior as `!self`. Evaluation invokes the
    ///   child once; thrown errors and cancellation propagate unchanged.
    public func negated() -> Self {
        let count = policyCompositionCount(nodeCount, 0)
        return Self(nodeCount: count.value, depth: policySaturatingAdd(depth, 1),
                    nodeCountOverflowed: nodeCountOverflowed || count.overflowed) { input in
            try await !operation(input)
        }
    }

    /// Admits the entire expression without invoking any predicate, including skipped branches.
    /// - Parameter limits: Explicit finite node/depth budgets chosen by the adopting application.
    /// - Throws: `PolicyCompositionError.nodeLimit` first when the total count exceeds its budget;
    ///   otherwise `PolicyCompositionError.depthLimit` for excess depth. No work executes on failure.
    public func validate(limits: PolicyLimits) throws {
        try validatePolicyComposition(nodeCount: nodeCount, depth: depth,
                                      nodeCountOverflowed: nodeCountOverflowed, limits: limits)
    }

    /// Validates the full expression and evaluates admitted leaves on the caller's task.
    /// - Parameters:
    ///   - input: Sendable invocation data passed unchanged to every evaluated predicate.
    ///   - limits: Explicit structural admission budgets, checked before any user code.
    /// - Returns: The composed Boolean decision with left-to-right short-circuit ordering.
    /// - Throws: A structural `PolicyCompositionError`, `CancellationError` before an evaluated
    ///   leaf starts, or an unchanged predicate error. Cancellation during a predicate remains
    ///   cooperative. Earlier side effects are retained; this method owns no tasks or cleanup.
    public func evaluate(_ input: Input, limits: PolicyLimits) async throws -> Bool {
        try validate(limits: limits)
        try Task.checkCancellation()
        DiscordLog.makeLogger("dsl.policy").trace("Invocation policy evaluation started", metadata: ["dk.event": "dsl.policy.evaluating", "dk.nodes": .stringConvertible(nodeCount), "dk.depth": .stringConvertible(depth)])
        do {
            let allowed = try await operation(input)
            DiscordLog.makeLogger("dsl.policy").trace("Invocation policy evaluation completed", metadata: ["dk.event": "dsl.policy.evaluated", "dk.allowed": .stringConvertible(allowed)])
            return allowed
        } catch {
            DiscordLog.makeLogger("dsl.policy").debug("Invocation policy evaluation failed", metadata: ["dk.event": "dsl.policy.failed", "dk.cancelled": .stringConvertible(error is CancellationError)])
            throw error
        }
    }
}

/// Creates an inert short-circuit conjunction in ordinary Swift Boolean precedence.
/// - Parameters:
///   - lhs: First decision; denial or failure skips the right predicate.
///   - rhs: Decision evaluated only after the left predicate allows.
/// - Returns: The same bounded immutable expression as `lhs.and(rhs)`; no closure executes now.
public func && <Input>(lhs: InvocationPolicy<Input>, rhs: InvocationPolicy<Input>) -> InvocationPolicy<Input> {
    lhs.and(rhs)
}

/// Creates an inert short-circuit disjunction in ordinary Swift Boolean precedence.
/// - Parameters:
///   - lhs: First decision; allowance or failure skips the right predicate.
///   - rhs: Decision evaluated only after the left predicate denies.
/// - Returns: The same bounded immutable expression as `lhs.or(rhs)`; no closure executes now.
public func || <Input>(lhs: InvocationPolicy<Input>, rhs: InvocationPolicy<Input>) -> InvocationPolicy<Input> {
    lhs.or(rhs)
}

/// Creates an inert Boolean negation while retaining error and cancellation propagation.
/// - Parameter policy: Decision whose successful Boolean result is inverted exactly once.
/// - Returns: The same bounded immutable expression as `policy.negated()`.
public prefix func ! <Input>(policy: InvocationPolicy<Input>) -> InvocationPolicy<Input> {
    policy.negated()
}

/// An immutable invocation wrapper whose caller explicitly supplies the terminal operation.
/// Construction, composition and validation start no tasks or I/O. The left wrapper is outermost
/// during composition; successful unwinding occurs in reverse order. Injected middleware owns
/// resource acquisition, `defer` cleanup, errors and any retained partial side effects. It may
/// short-circuit or call `next` repeatedly; application response/admission owners remain authoritative.
public struct InvocationMiddleware<Input: Sendable, Output: Sendable>: Sendable {
    /// A caller-owned terminal or inner operation, executed on the current task when explicitly called.
    public typealias Next = @Sendable (Input) async throws -> Output

    /// Total leaves and composition nodes, saturating at `Int.max` rather than overflowing.
    public let nodeCount: Int
    /// Maximum leaf-to-root nesting depth, saturating at `Int.max` rather than overflowing.
    public let depth: Int
    /// Sticky overflow prevents saturated counts from admitting a larger-than-representable graph.
    private let nodeCountOverflowed: Bool
    /// Stored wrapper operation; the public entry point admits the complete composition once.
    private let operation: @Sendable (Input, @escaping Next) async throws -> Output

    /// Stores one middleware wrapper without invoking it or the continuation.
    /// - Parameter body: Sendable wrapper receiving invocation data and an escaping inner operation.
    ///   It may forward unchanged or replacement data, omit the inner call, transform output, or
    ///   explicitly retry. It owns cleanup and must cooperate with cancellation during suspensions.
    ///   Retaining `next` beyond this invocation transfers its lifetime responsibility to the author.
    public init(_ body: @escaping @Sendable (Input, @escaping Next) async throws -> Output) {
        self.nodeCount = 1
        self.depth = 1
        self.nodeCountOverflowed = false
        self.operation = { input, next in
            try Task.checkCancellation()
            DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware wrapper entered", metadata: ["dk.event": "dsl.middleware.wrapper_entered"])
            defer { DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware wrapper exited", metadata: ["dk.event": "dsl.middleware.wrapper_exited"]) }
            return try await body(input, next)
        }
    }

    /// Stores a composed wrapper whose leaf operations already check cancellation before execution.
    /// - Parameters:
    ///   - nodeCount: Positive saturating count of the complete immutable expression.
    ///   - depth: Positive saturating depth of the complete immutable expression.
    ///   - nodeCountOverflowed: Sticky evidence that the actual count exceeds `Int.max`.
    ///   - operation: Inert closure retaining wrappers without invoking them now.
    private init(nodeCount: Int, depth: Int, nodeCountOverflowed: Bool,
                 operation: @escaping @Sendable (Input, @escaping Next) async throws -> Output) {
        self.nodeCount = nodeCount
        self.depth = depth
        self.nodeCountOverflowed = nodeCountOverflowed
        self.operation = operation
    }

    /// Wraps another middleware so this wrapper executes first and unwinds last.
    /// - Parameter other: Inner wrapper reached only when this wrapper calls its continuation.
    /// - Returns: An inert composition equivalent to `self >>> other`. Both wrappers may transform
    ///   data/output or short-circuit; errors propagate through their ordinary `do`/`catch` scopes.
    public func then(_ other: Self) -> Self {
        let count = policyCompositionCount(nodeCount, other.nodeCount)
        return Self(nodeCount: count.value, depth: policySaturatingAdd(max(depth, other.depth), 1),
                    nodeCountOverflowed: nodeCountOverflowed || other.nodeCountOverflowed || count.overflowed) { input, next in
            try await operation(input) { forwarded in
                try await other.operation(forwarded, next)
            }
        }
    }

    /// Admits every wrapper and composition node without invoking middleware or the terminal.
    /// - Parameter limits: Explicit finite node/depth budgets selected by the adopting application.
    /// - Throws: `PolicyCompositionError.nodeLimit` before `PolicyCompositionError.depthLimit`
    ///   when both bounds are exceeded. No user closure executes on structural rejection.
    public func validate(limits: PolicyLimits) throws {
        try validatePolicyComposition(nodeCount: nodeCount, depth: depth,
                                      nodeCountOverflowed: nodeCountOverflowed, limits: limits)
    }

    /// Admits the complete chain and explicitly runs it with a caller-owned terminal operation.
    /// - Parameters:
    ///   - input: Initial sendable invocation data; wrappers may explicitly replace forwarded data.
    ///   - limits: Finite structural budgets, validated before any wrapper or terminal execution.
    ///   - next: Terminal operation. Called only when all reached wrappers choose to forward;
    ///     cancellation is checked before each terminal call, including repeated calls.
    /// - Returns: The outermost wrapper's output, including any explicit output transformation.
    /// - Throws: A structural `PolicyCompositionError`, `CancellationError` before a reached
    ///   wrapper or terminal starts, or an unchanged user error unless a wrapper handles it.
    ///   Already completed side effects remain; caller middleware owns cleanup and retry policy.
    public func run(_ input: Input, limits: PolicyLimits, next: @escaping Next) async throws -> Output {
        try validate(limits: limits)
        try Task.checkCancellation()
        DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware started", metadata: ["dk.event": "dsl.middleware.started", "dk.nodes": .stringConvertible(nodeCount), "dk.depth": .stringConvertible(depth)])
        do {
            let result = try await operation(input) { forwarded in
                try Task.checkCancellation()
                DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware terminal entered", metadata: ["dk.event": "dsl.middleware.terminal_entered"])
                defer { DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware terminal exited", metadata: ["dk.event": "dsl.middleware.terminal_exited"]) }
                return try await next(forwarded)
            }
            DiscordLog.makeLogger("dsl.middleware").trace("Invocation middleware completed", metadata: ["dk.event": "dsl.middleware.completed"])
            return result
        } catch {
            DiscordLog.makeLogger("dsl.middleware").debug("Invocation middleware failed", metadata: ["dk.event": "dsl.middleware.failed", "dk.cancelled": .stringConvertible(error is CancellationError)])
            throw error
        }
    }
}

/// Left-associative wrapper composition, binding more tightly than Boolean conjunction.
precedencegroup InvocationMiddlewarePrecedence {
    associativity: left
    higherThan: LogicalConjunctionPrecedence
}

infix operator >>>: InvocationMiddlewarePrecedence

/// Composes middleware with the left side outermost and the right side innermost.
/// - Parameters:
///   - lhs: Wrapper entered first and unwound last when the inner operation succeeds.
///   - rhs: Inner wrapper reached only if the left wrapper calls its continuation.
/// - Returns: The same inert bounded chain as `lhs.then(rhs)`; no user work executes now.
public func >>> <Input, Output>(lhs: InvocationMiddleware<Input, Output>,
                               rhs: InvocationMiddleware<Input, Output>) -> InvocationMiddleware<Input, Output> {
    lhs.then(rhs)
}

/// Adds nonnegative structural sizes without allowing integer overflow to bypass admission.
/// - Parameters:
///   - lhs: Nonnegative size maintained by immutable composition.
///   - rhs: Nonnegative size maintained by immutable composition.
/// - Returns: Their exact sum when representable, otherwise `Int.max` for later rejection by depth.
private func policySaturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? Int.max : result.partialValue
}

/// Checks structural metadata before any invocation closure executes.
/// - Parameters:
///   - nodeCount: Positive saturating total of all leaves and composition nodes.
///   - depth: Positive saturating maximum leaf-to-root depth.
///   - nodeCountOverflowed: Whether the actual count exceeded the integer representation.
///   - limits: Previously validated finite positive budgets.
/// - Throws: `PolicyCompositionError.nodeLimit` for excess count, otherwise
///   `PolicyCompositionError.depthLimit` for excess depth; diagnostics retain no input text.
private func validatePolicyComposition(nodeCount: Int, depth: Int, nodeCountOverflowed: Bool,
                                       limits: PolicyLimits) throws {
    guard !nodeCountOverflowed, nodeCount <= limits.maximumNodes else { throw PolicyCompositionError.nodeLimit }
    guard depth <= limits.maximumDepth else { throw PolicyCompositionError.depthLimit }
}

/// Counts two child expressions and their new parent without losing overflow evidence.
/// - Parameters:
///   - lhs: Nonnegative saturating node count of the first child.
///   - rhs: Nonnegative saturating count of the second child, or zero for unary composition.
/// - Returns: The saturated total and whether either addition exceeded `Int.max`. Child sticky
///   overflow evidence is combined separately by the immutable expression constructor.
private func policyCompositionCount(_ lhs: Int, _ rhs: Int) -> (value: Int, overflowed: Bool) {
    let children = lhs.addingReportingOverflow(rhs)
    guard !children.overflow else { return (Int.max, true) }
    let parent = children.partialValue.addingReportingOverflow(1)
    return (parent.overflow ? Int.max : parent.partialValue, parent.overflow)
}
