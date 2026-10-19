#if canImport(Darwin)
import Foundation
import Testing
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import DiscordFoundationTransport

/// Exercises diagnostics without opening a socket or exposing URL/header credentials.
struct FoundationLoggingTests {
    /// Constructors emit nothing; invalid exchanges and explicit closure remain observable.
    @Test func invalidRequestRedaction() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let adapter = FoundationHTTPTransport(configuration: try .init())
            let websocket = FoundationWebSocketTransport(configuration: try .init())
            #expect(recorder.entries.isEmpty)
            let request = HTTPRequest(method: "GET", url: URL(string: "https://user:SECRET@example.invalid/SECRET?token=SECRET")!,
                                      headers: [.init(name: "Authorization", value: "SECRET")])
            await #expect(throws: FoundationTransportFailure.invalidRequest) {
                try await adapter.execute(request, context: .init(clock: ContinuousClock()))
            }
            await #expect(throws: FoundationTransportFailure.invalidRequest) {
                try await websocket.connectWebSocket(request, context: .init(clock: ContinuousClock()))
            }
            await adapter.close()
            await websocket.close()
        }
        #expect(recorder.entries.count == 6)
        #expect(recorder.entries.allSatisfy { $0.metadata["dk.event"] != nil && $0.level <= .debug })
        #expect(!String(describing: recorder.entries).contains("SECRET"))
    }
}
#endif
