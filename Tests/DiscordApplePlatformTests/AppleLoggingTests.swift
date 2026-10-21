import Testing
import DiscordApplePlatform
import DiscordLogging
import DiscordTestSupport
import DiscordTransport

/// Confirms host lifecycle logs follow explicit execution and preserve cleanup ownership.
struct AppleLoggingTests {
    /// Inert construction emits nothing; suspension drains an owned resource exactly once.
    @Test func explicitLifecycleDiagnostics() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let lifecycle = try AppleLifecycle(host: .macOS, qualifiedCapabilities: [.http])
            #expect(recorder.entries.isEmpty)
            let resource = LogTestResource()
            _ = try await lifecycle.retain(resource, requiring: .http)
            await lifecycle.transition(to: .suspended)
            #expect(await resource.closeCount == 1)
            #expect(await lifecycle.retainedResourceCount() == 0)
        }
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"] } == ["apple.lifecycle.transition", "apple.lifecycle.drain", "apple.lifecycle.drain.completed"])
        #expect(recorder.entries.first?.metadata["state"] == "suspended")
        #expect(recorder.entries.first?.level == .info)
        #expect(recorder.entries.last?.metadata["dk.resources"]?.description == "1")
    }
}

/// Actor-confined counter for lifecycle cleanup assertions.
private actor LogTestResource: TransportResource {
    var closeCount = 0

    /// Records explicit close calls without performing I/O.
    func close() async { closeCount += 1 }
}
