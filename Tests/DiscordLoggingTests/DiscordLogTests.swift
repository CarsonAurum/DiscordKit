import Testing
import DiscordLogging
import DiscordTestSupport

/// Exercises scoped native SwiftLog injection without mutating process-global state.
struct DiscordLogTests {
    /// Verifies labels, metadata, reserved application levels and threshold ownership.
    @Test func nativeLevelsAndValueSemantics() {
        let recorder = LogRecorder()
        DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let logger = DiscordLog.makeLogger("test")
            var copy = logger
            copy.logLevel = .error
            copy[metadataKey: "copy"] = "yes"
            for level in Logger.Level.allCases {
                logger.log(level: level, "event", metadata: ["dk.event": "test.event"])
            }
            copy.debug("filtered")
            copy.error("copy")
            #expect(logger.logLevel == .trace)
            #expect(logger[metadataKey: "copy"] == nil)
        }
        #expect(recorder.entries.count == 8)
        #expect(recorder.entries.prefix(7).map(\.level) == Logger.Level.allCases)
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.test" && $0.metadata["dk.subsystem"] == "test" })
    }

    /// Ensures structured children inherit factories while nested overrides restore them.
    @Test func scopedFactoriesAndConcurrency() async {
        let outer = LogRecorder()
        let inner = LogRecorder()
        await DiscordLog.$loggerFactory.withValue({ outer.makeLogger($0) }) {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask { DiscordLog.makeLogger("child").trace("child") }
                }
            }
            DiscordLog.$loggerFactory.withValue({ inner.makeLogger($0) }) {
                DiscordLog.makeLogger("inner").debug("inner")
            }
            DiscordLog.makeLogger("outer").debug("restored")
        }
        #expect(outer.entries.count == 17)
        #expect(inner.entries.map(\.label) == ["discordkit.inner"])
    }

    /// Checks finite recording and SwiftLog's lazy metadata/message evaluation.
    @Test func boundedCaptureAndLazyFiltering() {
        let recorder = LogRecorder(maximumEntries: 1)
        var logger = recorder.makeLogger("test")
        logger.logLevel = .error
        var evaluated = false
        logger.trace("\({ evaluated = true; return "secret" }())")
        #expect(!evaluated)
        logger.error("one")
        logger.critical("two")
        #expect(recorder.entries.map(\.message) == ["one"])
    }
}
