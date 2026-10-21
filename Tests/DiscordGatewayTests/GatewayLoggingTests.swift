import DiscordTransport
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
        #expect(overflows.first?.level == .warning)
        #expect(overflows.first?.metadata["dk.event"] == "gateway.subscription.overflow")
        #expect(overflows.first?.metadata["dk.terminated"]?.description == "1")
        #expect(overflows.first?.metadata.keys.sorted() == ["dk.dropped", "dk.event", "dk.module", "dk.subsystem", "dk.terminated"])
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.gateway.events" })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_gateway_payload"))
    }

    /// Synthetic Identify, READY, duplicate dispatch and shutdown expose protocol phases without identity data.
    /// - Throws: Unexpected fixture, runtime, cancellation or ownership failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func sessionProtocolAndCleanupTrace() async throws {
        let recorder = LogRecorder()
        let identified = TestBarrier(), received = TestBarrier()
        let idle = TestBarrier(onWaitScheduled: { received.open() })
        let socket = GatewayTestSocket(steps: [
            { .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#) },
            { try await identified.wait(); return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"private_session","resume_gateway_url":"wss://resume.discord.gg/private_resume_path"}}"#) },
            { .text(#"{"op":0,"s":1,"t":"PRIVATE_EVENT_NAME","d":{"token":"private_dispatch_payload"}}"#) },
            { try await idle.wait(); return nil }
        ], onSend: { envelope in if envelope.opcode == 2 { identified.open() } })
        let fixture = try makeRuntime(sockets: [socket], jitter: 1)
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let task = Task { try await fixture.shard.run() }
            try await received.wait()
            await fixture.shard.stop()
            try await task.value
        }
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        for event in ["gateway.lease.acquire", "gateway.lease.acquired", "gateway.connection.connected",
            "gateway.hello.received", "gateway.hello.accepted", "gateway.identify.admission",
            "gateway.frame.encoded", "gateway.frame.sent", "gateway.identify.submitted",
            "gateway.frame.received", "gateway.frame.decoded", "gateway.session.ready",
            "gateway.events.queued", "gateway.dispatch.duplicate", "gateway.cleanup.started",
            "gateway.cleanup.completed", "gateway.operation.completed"] {
            #expect(events.contains(event))
        }
        #expect(recorder.entries.contains { $0.level == .notice && $0.metadata["dk.event"] == "gateway.session.ready" })
        #expect(recorder.entries.contains { $0.level == .info && $0.metadata["dk.event"] == "gateway.shard.started" })
        #expect(recorder.entries.contains { $0.label == "discordkit.gateway.protocol" && $0.level == .trace && $0.metadata["dk.opcode"]?.description == "0" })
        #expect(Set(recorder.entries.compactMap { $0.metadata["dk.trace_id"]?.description }).count == 1)
        let terminal = try #require(recorder.entries.last { $0.metadata["dk.event"] == "gateway.operation.completed" })
        #expect(terminal.metadata["dk.duration_ns"] != nil)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("private_session") && !rendered.contains("private_resume_path"))
        #expect(!rendered.contains("private_dispatch_payload") && !rendered.contains("PRIVATE_EVENT_NAME"))
    }

}
