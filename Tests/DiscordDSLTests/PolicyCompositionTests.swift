import DiscordDSL
import Testing

/// Records explicitly executed synthetic work without sleeps, I/O or shared cross-test state.
private actor PolicyExecutionTrace {
    private var entries: [String] = []

    /// Appends one completed observation in actor admission order.
    /// - Parameter entry: Synthetic label used only for exact deterministic assertions.
    func record(_ entry: String) { entries.append(entry) }

    /// Returns all observations completed before this actor call.
    /// - Returns: An immutable copy in exact recorded order, initially empty.
    func snapshot() -> [String] { entries }
}

/// Coordinates one suspended operation with its test without timer-based scheduling assumptions.
private actor PolicySuspensionGate {
    private var operation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var entered = false

    /// Parks the sole operation and releases observers waiting for its established suspension point.
    /// This deliberately ignores cancellation until the test explicitly opens the gate.
    func suspend() async {
        await withCheckedContinuation { continuation in
            operation = continuation
            entered = true
            for observer in observers { observer.resume() }
            observers.removeAll()
        }
    }

    /// Waits until the operation has installed its continuation; already-entered calls return immediately.
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }

    /// Resumes the parked operation once and relinquishes the stored continuation.
    /// Repeated releases are harmless; the test calls this only after `waitUntilEntered` completes.
    func release() {
        operation?.resume()
        operation = nil
    }
}

/// Distinct synthetic failures prove that wrappers preserve original typed errors.
private enum PolicyFixtureError: Error, Equatable { case predicate, terminal }

/// Verifies inert construction, bounded structure, Boolean ordering and caller-owned middleware lifetimes.
@Suite struct PolicyCompositionTests {
    /// Defaults and exact positive boundaries remain valid; invalid sizes fail without executing work.
    /// - Throws: Unexpected valid-budget construction failure fails the test.
    @Test func finiteLimitsAndInvalidConfigurations() throws {
        let defaults = try PolicyLimits()
        #expect(defaults.maximumNodes == 256)
        #expect(defaults.maximumDepth == 32)
        #expect(try PolicyLimits(maximumNodes: 1, maximumDepth: 1) == PolicyLimits(maximumNodes: 1, maximumDepth: 1))
        #expect(try PolicyLimits(maximumNodes: Int.max, maximumDepth: 128).maximumNodes == Int.max)
        for nodes in [Int.min, -1, 0] {
            #expect(throws: PolicyCompositionError.invalidLimits) { try PolicyLimits(maximumNodes: nodes) }
        }
        for depth in [Int.min, -1, 0, 129, Int.max] {
            #expect(throws: PolicyCompositionError.invalidLimits) { try PolicyLimits(maximumDepth: depth) }
        }
    }

    /// Named and operator conjunction/disjunction produce identical short-circuit truth tables and order.
    /// - Parameters:
    ///   - decisions: Left and right decisions whose complete truth table exercises short-circuit ordering.
    ///   - conjunction: Whether to require both decisions rather than either decision.
    /// - Throws: Unexpected policy execution or structural failure fails the test.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)], [false, true])
    func booleanCompositionParity(decisions: (Bool, Bool), conjunction: Bool) async throws {
        let (left, right) = decisions
        for useOperator in [false, true] {
            let trace = PolicyExecutionTrace()
            let lhs = InvocationPolicy<Int> { input in
                await trace.record("left:\(input)")
                return left
            }
            let rhs = InvocationPolicy<Int> { input in
                await trace.record("right:\(input)")
                return right
            }
            let composed: InvocationPolicy<Int>
            if conjunction { composed = useOperator ? lhs && rhs : lhs.and(rhs) }
            else { composed = useOperator ? lhs || rhs : lhs.or(rhs) }
            let limits = try PolicyLimits(maximumNodes: 3, maximumDepth: 2)
            try composed.validate(limits: limits)
            #expect(await trace.snapshot().isEmpty)
            #expect(composed.nodeCount == 3)
            #expect(composed.depth == 2)
            #expect(try await composed.evaluate(42, limits: limits) == (conjunction ? left && right : left || right))
            let reachesRight = conjunction ? left : !left
            #expect(await trace.snapshot() == (reachesRight ? ["left:42", "right:42"] : ["left:42"]))
        }
    }

    /// Prefix/named negation run once and preserve Swift's ordinary conjunction-before-disjunction grouping.
    /// - Parameter decision: Both possible child results must invert exactly once.
    /// - Throws: Unexpected policy failure fails the test.
    @Test(arguments: [false, true]) func negationAndOperatorPrecedence(decision: Bool) async throws {
        let trace = PolicyExecutionTrace()
        let policy = InvocationPolicy<Void> { _ in await trace.record("child"); return decision }
        let limits = try PolicyLimits()
        #expect(try await (!policy).evaluate((), limits: limits) == !decision)
        #expect(try await policy.negated().evaluate((), limits: limits) == !decision)
        #expect(await trace.snapshot() == ["child", "child"])
        let allow = InvocationPolicy<Void> { _ in await trace.record("allow"); return true }
        let forbidden = InvocationPolicy<Void> { _ in await trace.record("unexpected"); return false }
        let expression = allow || forbidden && !forbidden
        #expect(expression.nodeCount == 6)
        #expect(expression.depth == 4)
        #expect(try await expression.evaluate((), limits: limits))
        #expect(await trace.snapshot() == ["child", "child", "allow"])
    }

    /// Structural rejection examines skipped branches and never invokes any predicate; exact boundaries pass.
    /// - Throws: Unexpected valid-budget construction or exact-boundary evaluation failure fails the test.
    @Test func completeStructureIsAdmittedBeforeAnyPredicate() async throws {
        let trace = PolicyExecutionTrace()
        let leaf = InvocationPolicy<Void> { _ in await trace.record("leaf"); return false }
        let expression = leaf && !leaf
        #expect(expression.nodeCount == 4)
        #expect(expression.depth == 3)
        await #expect(throws: PolicyCompositionError.nodeLimit) {
            try await expression.evaluate((), limits: PolicyLimits(maximumNodes: 3, maximumDepth: 3))
        }
        await #expect(throws: PolicyCompositionError.depthLimit) {
            try await expression.evaluate((), limits: PolicyLimits(maximumNodes: 4, maximumDepth: 2))
        }
        #expect(throws: PolicyCompositionError.nodeLimit) {
            try expression.validate(limits: PolicyLimits(maximumNodes: 1, maximumDepth: 1))
        }
        #expect(await trace.snapshot().isEmpty)
        #expect(try await !expression.evaluate((), limits: PolicyLimits(maximumNodes: 4, maximumDepth: 3)))
        #expect(await trace.snapshot() == ["leaf"])
    }

    /// Cheap shared subgraphs saturate counters and retain sticky overflow even at the largest public budget.
    /// - Throws: Unexpected valid-budget construction failure fails the test.
    @Test func saturatedCountsCannotBypassAdmission() async throws {
        let trace = PolicyExecutionTrace()
        var policy = InvocationPolicy<Void> { _ in await trace.record("unexpected"); return true }
        var middleware = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("unexpected")
            return try await next(input)
        }
        for _ in 0...Int.bitWidth {
            policy = policy && policy
            middleware = middleware >>> middleware
        }
        #expect(policy.nodeCount == Int.max)
        #expect(middleware.nodeCount == Int.max)
        #expect(policy.depth == Int.bitWidth + 2)
        #expect(middleware.depth == Int.bitWidth + 2)
        let largest = try PolicyLimits(maximumNodes: Int.max, maximumDepth: 128)
        #expect(throws: PolicyCompositionError.nodeLimit) { try policy.validate(limits: largest) }
        #expect(throws: PolicyCompositionError.nodeLimit) { try policy.negated().validate(limits: largest) }
        #expect(throws: PolicyCompositionError.nodeLimit) { try middleware.validate(limits: largest) }
        #expect(await trace.snapshot().isEmpty)
    }

    /// The hard depth ceiling admits exactly 128 levels and rejects the next level before executing it.
    /// - Throws: Unexpected exact-boundary validation or execution failure fails the test.
    @Test func hardDepthBoundaryIsExact() async throws {
        let trace = PolicyExecutionTrace()
        var policy = InvocationPolicy<Void> { _ in await trace.record("policy"); return true }
        let wrapper = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("wrapper")
            return try await next(input)
        }
        var middleware = wrapper
        for _ in 1..<128 {
            policy = !policy
            middleware = middleware.then(wrapper)
        }
        let limits = try PolicyLimits(maximumNodes: 1_000, maximumDepth: 128)
        #expect(policy.depth == 128)
        #expect(middleware.depth == 128)
        #expect(try await !policy.evaluate((), limits: limits))
        #expect(try await middleware.run((), limits: limits) { _ in 123 } == 123)
        #expect(await trace.snapshot().filter { $0 == "policy" }.count == 1)
        #expect(await trace.snapshot().filter { $0 == "wrapper" }.count == 128)
        #expect(throws: PolicyCompositionError.depthLimit) { try policy.negated().validate(limits: limits) }
        #expect(throws: PolicyCompositionError.depthLimit) { try middleware.then(wrapper).validate(limits: limits) }
    }

    /// Left-side failures and negated failures retain their typed error and never invoke later decisions.
    /// - Throws: Unexpected fixture construction failure fails the test.
    @Test func predicateFailuresPropagateWithoutFallback() async throws {
        let trace = PolicyExecutionTrace()
        let failure = InvocationPolicy<Void> { _ in
            await trace.record("failure")
            throw PolicyFixtureError.predicate
        }
        let right = InvocationPolicy<Void> { _ in await trace.record("unexpected"); return true }
        let limits = try PolicyLimits()
        for policy in [failure && right, failure || right, !failure] {
            await #expect(throws: PolicyFixtureError.predicate) { try await policy.evaluate((), limits: limits) }
        }
        #expect(await trace.snapshot() == ["failure", "failure", "failure"])
    }

    /// Cancellation before evaluation and between reached leaves prevents every next predicate from starting.
    /// - Parameter before: Whether cancellation precedes the complete expression or occurs inside its left leaf.
    /// - Throws: Unexpected fixture construction failure fails the test.
    @Test(arguments: [false, true]) func policyCancellationBoundaries(before: Bool) async throws {
        let trace = PolicyExecutionTrace()
        let left = InvocationPolicy<Void> { _ in
            await trace.record("left")
            withUnsafeCurrentTask { $0?.cancel() }
            return true
        }
        let right = InvocationPolicy<Void> { _ in await trace.record("unexpected"); return true }
        let limits = try PolicyLimits()
        let task = Task {
            if before { withUnsafeCurrentTask { $0?.cancel() } }
            return try await (left && right).evaluate((), limits: limits)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await trace.snapshot() == (before ? [] : ["left"]))
    }

    /// Named/operator middleware composition enters left-to-right, unwinds right-to-left and forwards transformed data.
    /// - Parameter useOperator: Both public authoring forms must retain identical behavior.
    /// - Throws: Unexpected middleware failure fails the test.
    @Test(arguments: [false, true]) func middlewareOrderAndForwarding(useOperator: Bool) async throws {
        let trace = PolicyExecutionTrace()
        let outer = InvocationMiddleware<Int, String> { input, next in
            await trace.record("outer.enter:\(input)")
            let output = try await next(input + 1)
            await trace.record("outer.exit")
            return "outer(\(output))"
        }
        let inner = InvocationMiddleware<Int, String> { input, next in
            await trace.record("inner.enter:\(input)")
            let output = try await next(input * 2)
            await trace.record("inner.exit")
            return "inner(\(output))"
        }
        let chain = useOperator ? outer >>> inner : outer.then(inner)
        let limits = try PolicyLimits(maximumNodes: 3, maximumDepth: 2)
        try chain.validate(limits: limits)
        #expect(await trace.snapshot().isEmpty)
        #expect(chain.nodeCount == 3)
        #expect(chain.depth == 2)
        let output = try await chain.run(3, limits: limits) { input in
            await trace.record("terminal:\(input)")
            return String(input)
        }
        #expect(output == "outer(inner(8))")
        #expect(await trace.snapshot() == ["outer.enter:3", "inner.enter:4", "terminal:8", "inner.exit", "outer.exit"])
    }

    /// Short-circuit wrappers skip the inner operation, while an explicitly authored repeat reaches terminal twice.
    /// - Throws: Unexpected middleware failure fails the test.
    @Test func middlewareShortCircuitAndExplicitRepeatedContinuation() async throws {
        let trace = PolicyExecutionTrace()
        let stop = InvocationMiddleware<Int, Int> { input, _ in await trace.record("stop"); return input }
        let inner = InvocationMiddleware<Int, Int> { input, next in
            await trace.record("unexpected")
            return try await next(input)
        }
        let limits = try PolicyLimits()
        #expect(try await (stop >>> inner).run(7, limits: limits) { _ in
            await trace.record("unexpected")
            return 0
        } == 7)
        #expect(await trace.snapshot() == ["stop"])
        let repeatNext = InvocationMiddleware<Int, Int> { input, next in
            let first = try await next(input)
            return first + (try await next(input + 1))
        }
        #expect(try await repeatNext.run(2, limits: limits) { input in
            await trace.record("terminal:\(input)")
            return input
        } == 5)
        #expect(await trace.snapshot() == ["stop", "terminal:2", "terminal:3"])
    }

    /// Middleware structural rejection runs no wrapper or terminal, including chains whose first wrapper would stop.
    /// - Throws: Unexpected valid-budget construction failure fails the test.
    @Test func middlewareBoundsRejectBeforeExecution() async throws {
        let trace = PolicyExecutionTrace()
        let leaf = InvocationMiddleware<Void, Int> { _, _ in await trace.record("unexpected"); return 1 }
        let chain = leaf >>> leaf >>> leaf
        #expect(chain.nodeCount == 5)
        #expect(chain.depth == 3)
        await #expect(throws: PolicyCompositionError.nodeLimit) {
            try await chain.run((), limits: PolicyLimits(maximumNodes: 4, maximumDepth: 3)) { _ in
                await trace.record("unexpected")
                return 0
            }
        }
        await #expect(throws: PolicyCompositionError.depthLimit) {
            try await chain.run((), limits: PolicyLimits(maximumNodes: 5, maximumDepth: 2)) { _ in 0 }
        }
        #expect(await trace.snapshot().isEmpty)
        #expect(try await chain.run((), limits: PolicyLimits(maximumNodes: 5, maximumDepth: 3)) { _ in 0 } == 1)
        #expect(await trace.snapshot() == ["unexpected"])
    }

    /// Injected wrapper cleanup observes original failures and may deliberately recover without implicit retries.
    /// - Parameter recover: Whether the authored wrapper rethrows or transforms the terminal failure.
    /// - Throws: Unexpected fixture construction failure fails the test.
    @Test(arguments: [false, true]) func middlewareFailureCleanupAndRecovery(recover: Bool) async throws {
        let trace = PolicyExecutionTrace()
        let wrapper = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("acquire")
            do {
                let output = try await next(input)
                await trace.record("release")
                return output
            } catch {
                await trace.record("release")
                if recover { return 9 }
                throw error
            }
        }
        let limits = try PolicyLimits()
        let terminal: InvocationMiddleware<Void, Int>.Next = { _ in
            await trace.record("side-effect")
            throw PolicyFixtureError.terminal
        }
        if recover { #expect(try await wrapper.run((), limits: limits, next: terminal) == 9) }
        else {
            await #expect(throws: PolicyFixtureError.terminal) { try await wrapper.run((), limits: limits, next: terminal) }
        }
        #expect(await trace.snapshot() == ["acquire", "side-effect", "release"])
    }

    /// Cancellation before wrappers, between wrappers or before terminal blocks subsequent work and allows authored cleanup.
    /// - Parameter stage: Zero cancels before execution, one in outer wrapper, two in inner wrapper.
    /// - Throws: Unexpected fixture construction failure fails the test.
    @Test(arguments: [0, 1, 2]) func middlewareCancellationBoundaries(stage: Int) async throws {
        let trace = PolicyExecutionTrace()
        let outer = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("outer")
            if stage == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            do { return try await next(input) }
            catch { await trace.record("outer.cleanup"); throw error }
        }
        let inner = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("inner")
            if stage == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            do { return try await next(input) }
            catch { await trace.record("inner.cleanup"); throw error }
        }
        let limits = try PolicyLimits()
        let task = Task {
            if stage == 0 { withUnsafeCurrentTask { $0?.cancel() } }
            return try await (outer >>> inner).run((), limits: limits) { _ in
                await trace.record("unexpected")
                return 1
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let expected = stage == 0 ? [] : stage == 1 ? ["outer", "outer.cleanup"]
            : ["outer", "inner", "inner.cleanup", "outer.cleanup"]
        #expect(await trace.snapshot() == expected)
    }

    /// External cancellation while user work is suspended prevents the next leaf or terminal from starting.
    /// - Parameter useMiddleware: Both execution products must stay in the caller-owned cancellable task.
    /// - Throws: Unexpected fixture construction failure fails the test.
    @Test(arguments: [false, true]) func externalCancellationDuringSuspendedWork(useMiddleware: Bool) async throws {
        let trace = PolicyExecutionTrace(), gate = PolicySuspensionGate()
        let limits = try PolicyLimits()
        let policy = InvocationPolicy<Void> { _ in
            await trace.record("start")
            await gate.suspend()
            return true
        }
        let forbidden = InvocationPolicy<Void> { _ in await trace.record("unexpected"); return true }
        let middleware = InvocationMiddleware<Void, Int> { input, next in
            await trace.record("start")
            await gate.suspend()
            do { return try await next(input) }
            catch { await trace.record("cleanup"); throw error }
        }
        let task = Task {
            if useMiddleware {
                return try await middleware.run((), limits: limits) { _ in
                    await trace.record("unexpected")
                    return 1
                }
            }
            return try await (policy && forbidden).evaluate((), limits: limits) ? 1 : 0
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await trace.snapshot() == (useMiddleware ? ["start", "cleanup"] : ["start"]))
    }

    /// Concurrent evaluations and repeated chain execution preserve independent invocation data without cached decisions.
    /// - Throws: Unexpected concurrent operation failure fails the test.
    @Test func concurrentAndRepeatedInvocationsHaveIndependentData() async throws {
        let trace = PolicyExecutionTrace()
        let policy = InvocationPolicy<Int> { input in await trace.record("policy:\(input)"); return input.isMultiple(of: 2) }
        let middleware = InvocationMiddleware<Int, Int> { input, next in try await next(input + 1) }
        let limits = try PolicyLimits()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for input in 0..<16 {
                group.addTask { () async throws -> Void in
                    #expect(try await policy.evaluate(input, limits: limits) == input.isMultiple(of: 2))
                    #expect(try await middleware.run(input, limits: limits) { $0 * 2 } == (input + 1) * 2)
                }
            }
            try await group.waitForAll()
        }
        #expect(Set(await trace.snapshot()) == Set((0..<16).map { "policy:\($0)" }))
        #expect(await trace.snapshot().count == 16)
        #expect(try await policy.evaluate(0, limits: limits))
        #expect(await trace.snapshot().count == 17)
    }
}
