import Testing
@testable import DiscordNIOTransport
import NIOCore
import NIOEmbedded

/// Deterministic cancellation-latch tests without sockets, clocks or host threads.
@Suite private struct ConnectionAttemptTests {
    /// Cancellation schedules exactly one close whether it precedes or follows
    /// channel installation. A held-close spy keeps the channel pipeline observable
    /// so repeated cancellation cannot hide behind native closed-channel behavior.
    /// - Parameter installFirst: Whether a channel exists before cancellation.
    /// Fixture cleanup forwards the held close; unexpected cleanup errors fail the test.
    @Test(arguments: [false, true])
    func cancellationSchedulesOneClose(_ installFirst: Bool) {
        let observer = HeldCloseObserver()
        let channel = EmbeddedChannel(handler: observer)
        defer {
            observer.forwardClose = true
            do { _ = try channel.finish() } catch { Issue.record(error) }
        }
        let attempt = NIOConnectionAttempt()
        if installFirst { attempt.install(channel) }
        attempt.cancel()
        attempt.cancel()
        if !installFirst {
            #expect(observer.closes == 0)
            attempt.install(channel)
        }
        channel.embeddedEventLoop.run()
        #expect(observer.closes == 1)
        for _ in 0..<16 { attempt.cancel() }
        channel.embeddedEventLoop.run()
        #expect(observer.closes == 1)
    }
}

/// Counts native-close requests without removing itself from the embedded pipeline.
private final class HeldCloseObserver: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    var closes = 0
    var forwardClose = false

    /// Holds operation closes for observation, then forwards final fixture cleanup.
    /// - Parameters:
    ///   - context: Synchronous embedded event-loop context; no concurrent use occurs.
    ///   - mode: Requested native closure mode, preserved during final cleanup.
    ///   - promise: Optional completion; held closes complete without closing the core.
    func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        closes += 1
        if forwardClose { context.close(mode: mode, promise: promise) }
        else { promise?.succeed(()) }
    }
}
