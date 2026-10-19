import DiscordCore
import DiscordInteractions
import Testing
@testable import DiscordCommands

/// Package-scoped provenance distinguishes preparation, execution and nested response failures.
@Suite(.timeLimit(.minutes(1))) struct CommandOperationFailureTests {
    /// Unscoped calls retain exact injected errors; scoped calls identify the original command boundary.
    /// - Parameter preparation: True fails synchronous preparation; false fails admitted asynchronous execution.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func scopeAndIdentity(preparation: Bool) async throws {
        let sentinel = CommandOperationSentinel()
        let route = CommandRoute(key: try .command(name: "ping"), prepare: { _ in
            if preparation { throw sentinel }
            return { throw sentinel }
        })
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        do {
            _ = try await router.route(context)
            Issue.record("Expected original error")
        } catch { #expect((error as? CommandOperationSentinel) === sentinel) }
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            do {
                _ = try await router.route(context)
                Issue.record("Expected operation provenance")
            } catch {
                let failure = try #require(error as? InteractionOperationFailure)
                #expect(failure.stage == (preparation ? .preparation : .handler))
                #expect((failure.underlying as? CommandOperationSentinel) === sentinel)
            }
        }
        #expect(await router.activeHandlerCount == 0)
    }

    /// A responder's acknowledgement provenance survives the enclosing command execution boundary.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func nestedResponderBoundary() async throws {
        let route = CommandRoute(key: try .command(name: "ping")) { context in
            try await context.responder.respond(.pong)
        }
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            do {
                _ = try await router.route(context)
                Issue.record("Expected incompatible initial callback failure")
            } catch {
                let failure = try #require(error as? InteractionOperationFailure)
                #expect(failure.stage == .acknowledgement)
                #expect(failure.underlying as? DiscordError == .validation(.invalidValue))
            }
        }
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Application typed catches see original responder errors; replacements discard response provenance.
    /// - Parameter replace: True throws an unrelated handler error; false rethrows the original typed failure.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func typedCatchAndReplacement(replace: Bool) async throws {
        let sentinel = CommandOperationSentinel()
        let route = CommandRoute(key: try .command(name: "ping")) { context in
            do { try await context.responder.respond(.pong) }
            catch let error as DiscordError {
                #expect(error == .validation(.invalidValue))
                if replace { throw sentinel }
                throw error
            }
        }
        let router = try CommandRouter(routes: [route], maximumConcurrentHandlers: 1)
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            do {
                _ = try await router.route(context)
                Issue.record("Expected escaping handler failure")
            } catch {
                let failure = try #require(error as? InteractionOperationFailure)
                #expect(failure.stage == (replace ? .handler : .acknowledgement))
                if replace { #expect((failure.underlying as? CommandOperationSentinel) === sentinel) }
                else { #expect(failure.underlying as? DiscordError == .validation(.invalidValue)) }
            }
        }
        #expect(await router.activeHandlerCount == 0)
    }

    /// A successful explicit response clears an earlier handled observation before later handler failure.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func successClearsHandledObservation() async throws {
        let route = CommandRoute(key: try .command(name: "ping")) { context in
            do { try await context.responder.respond(.pong) }
            catch let error as DiscordError { #expect(error == .validation(.invalidValue)) }
            try await context.responder.deferResponse()
            throw DiscordError.validation(.invalidValue)
        }
        let router = try CommandRouter(routes: [route])
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            do {
                _ = try await router.route(context)
                Issue.record("Expected final handler failure")
            } catch {
                let failure = try #require(error as? InteractionOperationFailure)
                #expect(failure.stage == .handler)
                #expect(failure.underlying as? DiscordError == .validation(.invalidValue))
            }
        }
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
    }

    /// Nested public router calls retain original errors for application catches and share outer safe observations.
    /// - Parameter replace: False rethrows the nested responder error; true replaces it at the outer handler.
    /// - Throws: Unexpected fixture construction or provenance failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func nestedRoutingPreservesApplicationCatch(replace: Bool) async throws {
        let inner = try CommandRouter(routes: [CommandRoute(key: try .command(name: "ping")) { context in
            try await context.responder.respond(.pong)
        }])
        let outer = try CommandRouter(routes: [CommandRoute(key: try .command(name: "ping")) { context in
            do { _ = try await inner.route(context) }
            catch let error as DiscordError {
                #expect(error == .validation(.invalidValue))
                if replace { throw DiscordError.transport(.invalidResponse) }
                throw error
            }
        }])
        let context = try CommandsTestFixtures.context(type: 2, data: CommandsTestFixtures.commandData())
        try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
            do {
                _ = try await outer.route(context)
                Issue.record("Expected escaping outer router failure")
            } catch {
                let failure = try #require(error as? InteractionOperationFailure)
                #expect(failure.stage == (replace ? .handler : .acknowledgement))
                #expect(failure.underlying as? DiscordError ==
                    (replace ? .transport(.invalidResponse) : .validation(.invalidValue)))
            }
        }
        #expect(await inner.activeHandlerCount == 0)
        #expect(await outer.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }
}

/// Immutable identity witness for unchanged ordinary command errors.
private final class CommandOperationSentinel: Error, Sendable {}
