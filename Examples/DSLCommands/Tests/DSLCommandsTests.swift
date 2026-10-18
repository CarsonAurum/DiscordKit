import DiscordCommandDSL
import DiscordDSL
import Testing
@testable import DSLCommands

/// The independent application compiles genuine macros and executes exact signed HTTP response assertions.
@Suite struct DSLCommandsTests {
    /// One macro-authored ping is compiled once and served twice using independent signature/response owners.
    /// Construction/compilation and serving have no registration client or network adapter to invoke.
    /// - Throws: Any schema, macro registration, crypto, ingress, routing or callback mismatch fails the test.
    @Test func signedOfflinePing() async throws {
        let ping = try Ping().contribution(id: "example.ping", source: .init(fileID: "test", line: 1))
        let commands = try CommandCompilation.compile(Module(id: "test") { ping })
        #expect(commands.definitions.map(\.request.name) == ["ping"])
        for _ in 0..<2 { try await DSLCommands.offline(commands) }
    }
}
