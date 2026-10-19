import DiscordCore
import DiscordLogging
import DiscordTestSupport
import Testing
@testable import DiscordGateway

/// Operational event capture uses synthetic envelopes and independently scoped SwiftLog handlers.
@Suite struct GatewayLoggingTests {
    /// Subscriber overflow emits one count-only event per publication, independent of payload identity.
    /// - Throws: Unexpected queue configuration, subscription or envelope construction failures.
    @Test func overflowHasBoundedMetadataAndNoPayload() async throws {
        let recorder = LogRecorder()
        let hub = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            GatewayEventHub(configuration: try .init(maximumEventsPerSubscription: 1))
        }
        #expect(recorder.entries.isEmpty)
        let event = try makeDeliveryEvent(1, payload: .object(["token": .string("private_gateway_payload")]))
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let subscription = try await hub.subscribe()
            #expect(await hub.publish(event).delivered == 1)
            #expect(await hub.publish(event).terminated == 1)
            #expect(await hub.publish(event).terminated == 0)
            await subscription.cancel()
        }
        #expect(await hub.snapshot().bufferedBytes == 0)
        let overflows = recorder.entries.filter { $0.metadata["dk.event"] == "gateway.subscription.overflow" }
        #expect(overflows.count == 1)
        #expect(overflows.first?.metadata["dk.event"] == "gateway.subscription.overflow")
        #expect(overflows.first?.metadata["dk.terminated"]?.description == "1")
        #expect(overflows.first?.metadata.keys.sorted() == ["dk.dropped", "dk.event", "dk.subsystem", "dk.terminated"])
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.gateway" && $0.level != .info && $0.level != .notice })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_gateway_payload"))
    }
}
