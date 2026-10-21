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
        #expect(recorder.entries.filter { $0.level == .info }.count == 2)
        #expect(recorder.entries.allSatisfy { $0.metadata["dk.event"] != nil })
        #expect(!String(describing: recorder.entries).contains("SECRET"))
    }

    /// A native loopback exchange traces slot ownership, bounded upload, response transfer and body cleanup.
    /// - Throws: Unexpected local peer, request, body collection or native adapter failure.
    @Test func httpBodyTraceShowsOwnershipWithoutContent() async throws {
        let recorder = LogRecorder()
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\nPRIVATE".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try .init())
        do {
            try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
                let response = try await adapter.execute(HTTPRequest(method: "GET", url: url,
                    headers: [.init(name: "X-Private", value: "PRIVATE_HEADER")]), context: .init(clock: ContinuousClock()))
                var bytes = Data()
                for try await chunk in try #require(response.body) { bytes.append(chunk) }
                #expect(bytes == Data("PRIVATE".utf8))
                await adapter.close()
            }
        } catch { await adapter.close(); await peer.close(); throw error }
        await peer.close()
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        for event in ["foundation.admission.reserved", "foundation.http.upload.completed", "foundation.http.submitted",
            "foundation.http.body.transferred", "foundation.http.response", "foundation.http.body.cleanup",
            "foundation.admission.released", "foundation.http.closed"] {
            #expect(events.contains(event))
        }
        let cleanup = try #require(recorder.entries.first { $0.metadata["dk.event"] == "foundation.http.body.cleanup" })
        #expect(cleanup.level == .trace && cleanup.metadata["dk.bytes"]?.description == "7")
        #expect(recorder.entries.last?.level == .info)
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("PRIVATE") && !rendered.contains("127.0.0.1"))
    }

}
#endif
