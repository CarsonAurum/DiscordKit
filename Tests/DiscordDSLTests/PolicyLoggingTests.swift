import DiscordDSL
import DiscordLogging
import DiscordTestSupport
import Testing

/// Confirms native diagnostics preserve pure authoring and never inspect generic invocation values.
@Suite struct PolicyLoggingTests {
    /// Construction, validation and empty compilation emit nothing; explicit execution emits fixed events.
    /// - Throws: Unexpected structural admission or predicate execution failure.
    @Test func pureAuthoringAndRedactedEvaluation() async throws {
        let recorder = LogRecorder()
        let policy = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let policy = InvocationPolicy<String> { !$0.isEmpty }
            try policy.validate(limits: .init())
            _ = try DefinitionPlan.compile(EmptyBotDefinition())
            return policy
        }
        #expect(recorder.entries.isEmpty)
        let allowed = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await policy.evaluate("private_invocation_value", limits: .init())
        }
        #expect(allowed)
        #expect(recorder.entries.map { $0.metadata["dk.event"]?.description } == ["dsl.policy.evaluating", "dsl.policy.evaluated"])
        #expect(recorder.entries.allSatisfy { $0.level == .trace && $0.label == "discordkit.dsl" })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_invocation_value"))
    }
}
