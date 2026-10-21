import Foundation
import Dispatch
import Logging
import Testing
@testable import DiscordLogHandlers
#if canImport(OSLog)
import OSLog
#endif

/// Exercises optional outputs without global bootstrap, external services or background work.
@Suite struct DiscordLogHandlersTests {
    /// Verifies independent output floors survive multiplex threshold changes, provider
    /// evaluation stays lazy, and copied handlers retain independent metadata and levels.
    @Test func fixedOutputFloorsAndValueSemantics() {
        let console = Box<[DiscordLogRecord]>([])
        let file = Box<[DiscordLogRecord]>([])
        let providers = Box(0)
        var floor = DiscordLevelFilterLogHandler(
            DiscordCallbackLogHandler(label: "console", logLevel: .trace) { record in
                console.update { $0.append(record) }
            }, minimumLevel: .info
        )
        #expect(console.read().isEmpty)
        #expect(floor.logLevel == .info)
        floor.metadata = ["base": "original"]
        floor[metadataKey: "temporary"] = "remove"
        floor[metadataKey: "temporary"] = nil
        #expect(floor[metadataKey: "temporary"] == nil)
        floor.metadataProvider = .init {
            providers.update { $0 += 1 }
            return ["provider": "yes"]
        }
        #expect(floor.metadataProvider != nil)
        var copy = floor
        copy[metadataKey: "base"] = "copy"
        copy.logLevel = .error
        #expect(floor.metadata["base"] == "original")
        #expect(floor.logLevel == .info)
        #expect(copy.logLevel == .error)
        var logger = Logging.Logger(label: "multiplex") { _ in
            MultiplexLogHandler([
                floor,
                DiscordCallbackLogHandler(label: "file", logLevel: .trace) { record in
                    file.update { $0.append(record) }
                },
            ])
        }
        logger.logLevel = .trace
        var rendered = false
        logger.trace("trace")
        logger.debug("debug")
        #expect(providers.read() == 0)
        logger.info("info", metadata: ["call": "value"])
        logger.notice("notice")
        logger.warning("warning")
        logger.error("error")
        logger.critical("critical")
        logger.logLevel = .critical
        logger.trace("\({ rendered = true; return "filtered" }())")
        #expect(!rendered)
        logger.logLevel = .trace
        logger.debug("file only again")
        #expect(console.read().map(\.level) == [.info, .notice, .warning, .error, .critical])
        #expect(file.read().map(\.level) == Logger.Level.allCases + [.debug])
        #expect(providers.read() == 5)
        #expect(console.read().first?.metadata["base"] == "original")
        #expect(console.read().first?.metadata["provider"] == "yes")
        #expect(console.read().first?.metadata["call"] == "value")
        #expect(copy[metadataKey: "base"] == "copy")
        let before = providers.read()
        floor.log(event: .init(level: .debug, message: "direct filtered", metadata: nil,
            source: nil, file: #fileID, function: #function, line: #line))
        #expect(providers.read() == before)
        floor.log(event: .init(level: .info, message: "direct retained", metadata: nil,
            source: nil, file: #fileID, function: #function, line: #line))
        #expect(console.read().last?.message == "direct retained")
        #expect(providers.read() == before + 1)
    }

    /// Protects captured observations for concurrent handler and diagnostic tests.
    private final class Box<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        /// Creates isolated test storage; every subsequent access is locked.
        /// - Parameter value: Initial Sendable observation.
        init(_ value: Value) { self.value = value }

        /// Returns one coherent test observation.
        /// - Returns: A value copy of the stored state.
        func read() -> Value {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        /// Mutates captured test state while holding its lock.
        /// - Parameter body: Synchronous mutation; it must not reenter this box.
        func update(_ body: (inout Value) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            body(&value)
        }
    }

    /// Records when an error's potentially sensitive description is evaluated.
    private struct SensitiveError: Error, CustomStringConvertible {
        let descriptions: Box<Int>
        /// Provides a deliberate secret marker if any backend mistakenly renders the error.
        var description: String {
            descriptions.update { $0 += 1 }
            return "DO-NOT-LOG-ERROR-CONTENT"
        }
    }

    /// Supplies custom metadata descriptions without relying on process-global state.
    private struct DescriptionValue: CustomStringConvertible, Sendable {
        /// The exact Unicode/control-containing description to encode as a JSON string.
        let description: String
    }

    /// Holds serialization at a deterministic metadata-description barrier on a dedicated Dispatch worker.
    private struct PausingDescription: CustomStringConvertible, Sendable {
        let entered: DispatchSemaphore
        let release: DispatchSemaphore

        /// Signals that serialization started, then waits for the test coordinator to release it.
        ///
        /// This synchronous application-description callback executes only on an
        /// explicit Dispatch worker, so it never blocks the main actor or a Swift
        /// cooperative executor. The coordinator releases it on success and failure.
        var description: String {
            entered.signal()
            release.wait()
            return "released description"
        }
    }

    /// Captures the ordering observations of the close-versus-serialization regression.
    private struct SerializationCloseObservation: Sendable {
        let entered: Bool
        let closedBeforeRelease: Bool
        let writerJoined: Bool
        let closeJoined: Bool
        let whilePaused: DiscordFileLogSnapshot?
        let diagnosticsWhilePaused: [DiscordFileLogError]
        let closeError: DiscordFileLogError?
    }

    /// Creates a unique existing directory owned exclusively by one test.
    /// - Returns: Directory URL; the caller removes it with `defer`.
    /// - Throws: Local temporary-directory creation errors.
    private func directory() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("DiscordLogHandlers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    /// Decodes every complete NDJSON line into a Foundation object for independent assertions.
    /// - Parameter url: Existing output file.
    /// - Returns: Ordered dictionary records; empty files yield an empty array.
    /// - Throws: File reads, invalid JSON, or unexpected nonobject record failures.
    private func objects(at url: URL) throws -> [[String: Any]] {
        let bytes = try Data(contentsOf: url)
        return try bytes.split(separator: 10).map {
            try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    /// Checks inert construction, all seven severities, caller location and privacy-preserving error omission.
    /// - Throws: Unexpected missing captured records.
    @Test func callbackLevelsAndErrorPrivacy() throws {
        let records = Box<[DiscordLogRecord]>([])
        let descriptions = Box(0)
        let now = Date(timeIntervalSince1970: 123.25)
        let logger = Logging.Logger(label: "test.callback") { label in
            DiscordCallbackLogHandler(label: label, logLevel: .trace, now: { now }) { record in
                records.update { $0.append(record) }
            }
        }
        #expect(records.read().isEmpty)
        for level in Logging.Logger.Level.allCases {
            logger.log(level: level, "accepted", error: SensitiveError(descriptions: descriptions), source: "source", file: "file", function: "function", line: 42)
        }
        let captured = records.read()
        #expect(captured.map(\.level) == Logging.Logger.Level.allCases)
        for record in captured {
            #expect(record.label == "test.callback")
            #expect(record.message == "accepted")
            #expect(record.source == "source")
            #expect(record.file == "file")
            #expect(record.function == "function")
            #expect(record.line == 42)
            #expect(record.timestamp == now)
            #expect(record.hasError)
        }
        #expect(descriptions.read() == 0)
        let defaultRecord = DiscordLogRecord(label: "", level: .info, message: "")
        #expect(defaultRecord.metadata.isEmpty)
        #expect(defaultRecord.source.isEmpty && defaultRecord.file.isEmpty && defaultRecord.function.isEmpty)
        #expect(defaultRecord.line == 0 && !defaultRecord.hasError)
    }

    /// Verifies value-semantic settings, removal, threshold filtering and base/provider/call precedence.
    /// - Throws: Unexpected missing observations.
    @Test func callbackValueSemanticsAndProviders() throws {
        let records = Box<[DiscordLogRecord]>([])
        let providers = Box(0)
        var first = Logging.Logger(label: "copy") { label in
            DiscordCallbackLogHandler(label: label, metadataProvider: .init {
                providers.update { $0 += 1 }
                return ["winner": "provider", "provider": "yes"]
            }) { record in records.update { $0.append(record) } }
        }
        first[metadataKey: "winner"] = "base"
        first[metadataKey: "base"] = "one"
        var second = first
        second.logLevel = .error
        second[metadataKey: "base"] = "two"
        second[metadataKey: "removed"] = "old"
        second[metadataKey: "removed"] = nil
        #expect(first.logLevel == .info && second.logLevel == .error)
        #expect(first[metadataKey: "base"] == "one")
        #expect(second[metadataKey: "base"] == "two")
        #expect(second[metadataKey: "removed"] == nil)
        first.debug("filtered")
        second.warning("filtered")
        #expect(providers.read() == 0 && records.read().isEmpty)
        first.info("first", metadata: ["winner": "call"])
        second.error("second")
        let captured = records.read()
        #expect(providers.read() == 2 && captured.count == 2)
        #expect(captured[0].metadata == ["winner": "call", "base": "one", "provider": "yes"])
        #expect(captured[1].metadata == ["winner": "provider", "base": "two", "provider": "yes"])
        var direct = DiscordCallbackLogHandler(label: "direct", logLevel: .error) { record in
            records.update { $0.append(record) }
        }
        direct[metadataKey: "x"] = "value"
        #expect(direct[metadataKey: "x"] == "value")
        direct.log(event: .init(level: .info, message: "filtered", metadata: nil, source: nil, file: "", function: "", line: 0))
        #expect(records.read().count == 2)
    }

    /// Confirms standard multiplexing preserves per-output filtering and dynamic context precedence.
    /// - Throws: Unexpected missing observations.
    @Test func standardMultiplexProviderPropagation() throws {
        let left = Box<[DiscordLogRecord]>([])
        let right = Box<[DiscordLogRecord]>([])
        var logger = Logging.Logger(label: "multiplex") { label in
            MultiplexLogHandler([
                DiscordCallbackLogHandler(label: label, logLevel: .trace, metadataProvider: .init { ["inner": "left", "winner": "inner"] }) { record in left.update { $0.append(record) } },
                DiscordCallbackLogHandler(label: label, logLevel: .warning, metadataProvider: .init { ["inner": "right"] }) { record in right.update { $0.append(record) } },
            ], metadataProvider: .init { ["outer": "yes", "winner": "outer"] })
        }
        logger[metadataKey: "base"] = "yes"
        logger.info("one")
        logger.warning("two", metadata: ["winner": "call"])
        #expect(left.read().count == 2 && right.read().count == 1)
        #expect(left.read()[0].metadata == ["base": "yes", "inner": "left", "outer": "yes", "winner": "outer"])
        #expect(right.read()[0].metadata == ["base": "yes", "inner": "right", "outer": "yes", "winner": "call"])
        let replacement = Logging.Logger.MetadataProvider { ["replacement": "yes"] }
        logger.handler.metadataProvider = replacement
        logger.error("replacement")
        #expect(left.read().last?.metadata["replacement"] == "yes")
        #expect(right.read().last?.metadata["replacement"] == "yes")
    }

    /// Independently parses exact UTF-8 escaping, nested metadata, custom descriptions and the stable schema.
    /// - Throws: Temporary-file, serialization, close or JSON failures.
    @Test func fileJSONEscapingAndSchema() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("events.ndjson")
        let sink = try DiscordFileLogSink(url: url)
        let text = "雪🐶\"\\\n\r\t\u{0}\u{1F}\u{2028}"
        let metadata: Logging.Logger.Metadata = [
            "z": .stringConvertible(DescriptionValue(description: text)),
            "a": .array([.string(""), .dictionary(["key\n": .string(text)])]),
        ]
        sink.write(.init(label: text, level: .critical, message: text, metadata: metadata, source: text, file: text, function: text, line: .max, timestamp: Date(timeIntervalSince1970: 123.25), hasError: true))
        try sink.close()
        let bytes = try Data(contentsOf: url)
        #expect(bytes.filter { $0 == 10 }.count == 1 && bytes.last == 10)
        let record = try #require(try objects(at: url).first)
        #expect(record["label"] as? String == text)
        #expect(record["message"] as? String == text)
        #expect(record["file"] as? String == text)
        #expect(record["function"] as? String == text)
        #expect(record["source"] as? String == text)
        #expect(record["level"] as? String == "critical")
        let line = try #require(record["line"] as? NSNumber)
        #expect(line.uint64Value == UInt64(UInt.max))
        #expect(record["timestamp"] as? Double == 123_250)
        #expect(record["hasError"] as? Bool == true)
        let object = try #require(record["metadata"] as? [String: Any])
        #expect(object["z"] as? String == text)
        let nested = try #require(object["a"] as? [Any])
        #expect(nested[0] as? String == "")
        #expect((nested[1] as? [String: String])?["key\n"] == text)
        #expect(sink.snapshot().writtenRecords == 1 && sink.snapshot().isClosed)
        #if !os(Windows)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #endif
    }

    /// Verifies deterministic key ordering and exact byte limits including JSON escaping and newline.
    /// - Throws: Unexpected serialization failures at the accepted boundary.
    @Test func serializerExactBoundsAndDeterminism() throws {
        let record = DiscordLogRecord(label: "l", level: .trace, message: "🐶\n", metadata: ["z": "last", "a": "first"], timestamp: Date(timeIntervalSince1970: 0))
        var first = DiscordLogJSONWriter(configuration: .init())
        let bytes = try first.encode(record)
        var second = DiscordLogJSONWriter(configuration: .init(maximumRecordBytes: bytes.count))
        #expect(try second.encode(record) == bytes)
        var short = DiscordLogJSONWriter(configuration: .init(maximumRecordBytes: bytes.count - 1))
        #expect(throws: DiscordFileLogError.recordTooLarge) { try short.encode(record) }
        #expect(String(decoding: bytes, as: UTF8.self).contains("\"a\":\"first\",\"z\":\"last\""))
        var invalid = DiscordLogJSONWriter(configuration: .init())
        #expect(throws: DiscordFileLogError.invalidRecord) {
            try invalid.encode(.init(label: "", level: .info, message: "", timestamp: Date(timeIntervalSince1970: .infinity)))
        }
    }

    /// Rejects excessive metadata before output and preserves the previous file during record drops.
    /// - Throws: Temporary-file or close failures.
    @Test func metadataAndOversizedRecordDrops() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("bounded.ndjson")
        let failures = Box<[DiscordFileLogError]>([])
        let sink = try DiscordFileLogSink(
            url: url, configuration: .init(maximumFileBytes: 1_024, maximumRecordBytes: 512, maximumMetadataDepth: 1, maximumMetadataValues: 3),
            onDiagnostic: { error in failures.update { $0.append(error) } }
        )
        sink.write(.init(label: "l", level: .info, message: "valid", metadata: ["a": "1", "b": "2"]))
        let accepted = sink.snapshot().activeBytes
        sink.write(.init(label: "l", level: .info, message: String(repeating: "雪", count: 1_000)))
        sink.write(.init(label: "l", level: .info, message: "nested", metadata: ["a": .array([])]))
        sink.write(.init(label: "l", level: .info, message: "count", metadata: ["a": "1", "b": "2", "c": "3"]))
        sink.write(.init(label: "l", level: .info, message: "invalid", timestamp: Date(timeIntervalSince1970: .nan)))
        #expect(sink.snapshot().activeBytes == accepted)
        #expect(sink.snapshot().writtenRecords == 1)
        #expect(sink.snapshot().droppedRecords == 4 && sink.snapshot().failures == 4)
        #expect(sink.snapshot().rotations == 0 && !sink.snapshot().isClosed)
        #expect(failures.read() == [.recordTooLarge, .metadataLimitExceeded, .metadataLimitExceeded, .invalidRecord])
        try sink.close()
        #expect(try objects(at: url).count == 1)
        var rootOnly = DiscordLogJSONWriter(configuration: .init(maximumMetadataDepth: 1, maximumMetadataValues: 1))
        #expect(try rootOnly.encode(.init(label: "", level: .info, message: "")).last == 10)
    }

    /// Exercises the exact active-file boundary, one-file retention, bounded archive count and restart append.
    /// - Parameter fileCount: Total retained file slots, including the active file.
    /// - Throws: Unexpected local file or serialization failures.
    @Test(arguments: [1, 3]) func rotationBoundsAndReopen(fileCount: Int) throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("rotation.ndjson")
        let record = DiscordLogRecord(label: "l", level: .info, message: "same", timestamp: Date(timeIntervalSince1970: 0))
        var encoder = DiscordLogJSONWriter(configuration: .init())
        let size = try encoder.encode(record).count
        let configuration = DiscordFileLogConfiguration(maximumFileBytes: size, maximumFiles: fileCount, maximumRecordBytes: size)
        let sink = try DiscordFileLogSink(url: url, configuration: configuration)
        for _ in 0..<6 { sink.write(record) }
        #expect(sink.snapshot().writtenRecords == 6 && sink.snapshot().rotations == 5)
        #expect(sink.snapshot().activeBytes == size)
        try sink.close()
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(contents.count == fileCount)
        for item in contents {
            #expect(try Data(contentsOf: item).count == size)
            #expect(try objects(at: item).count == 1)
        }
        let reopened = try DiscordFileLogSink(url: url, configuration: configuration)
        #expect(reopened.snapshot().activeBytes == size && reopened.snapshot().writtenRecords == 0)
        reopened.write(record)
        #expect(reopened.snapshot().rotations == 1)
        try reopened.close()
    }

    /// Asserts that concurrent callers produce complete unique JSON records and coherent counters.
    /// - Throws: Temporary file, close or independent JSON decoding failures.
    @Test func concurrentWrites() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("concurrent.ndjson")
        let sink = try DiscordFileLogSink(url: url)
        await withTaskGroup(of: Void.self) { group in
            for value in 0..<200 {
                group.addTask { sink.write(.init(label: "parallel", level: .debug, message: "\(value)")) }
            }
        }
        try sink.close()
        let records = try objects(at: url)
        let messages = records.compactMap { $0["message"] as? String }
        #expect(records.count == 200 && Set(messages) == Set((0..<200).map(String.init)))
        let snapshot = sink.snapshot()
        #expect(snapshot.writtenRecords == 200 && snapshot.droppedRecords == 0 && snapshot.failures == 0)
        #expect(snapshot.activeBytes == (try Data(contentsOf: url).count))
    }

    /// Covers explicit/repeated close, reentrant diagnostics, terminal admission and shared-handler state.
    /// - Throws: Temporary-file, open or close errors.
    @Test func closeAndRecursiveDiagnostics() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let holder = Box<DiscordFileLogSink?>(nil)
        let errors = Box<[DiscordFileLogError]>([])
        let sink = try DiscordFileLogSink(url: folder.appendingPathComponent("closed.ndjson"), onDiagnostic: { error in
            errors.update { $0.append(error) }
            holder.read()?.write(.init(label: "recursive", level: .error, message: "dropped"))
        })
        holder.update { $0 = sink }
        let first = DiscordFileLogHandler(label: "first", sink: sink)
        var second = first
        second.logLevel = .critical
        second[metadataKey: "copy"] = "second"
        #expect(first.logLevel == .info && second.logLevel == .critical)
        #expect(first[metadataKey: "copy"] == nil && second[metadataKey: "copy"] == "second")
        try sink.close()
        try sink.close()
        first.log(event: .init(level: .error, message: "closed", metadata: nil, source: nil, file: "", function: "", line: 0))
        #expect(errors.read() == [.closed])
        #expect(sink.snapshot().droppedRecords == 2 && sink.snapshot().failures == 2)
        #expect(sink.snapshot().isClosed && sink.snapshot().writtenRecords == 0)
        holder.update { $0 = nil }
    }

    /// Proves close joins filesystem mutations while an overlapping metadata description may outlive it.
    ///
    /// Explicit Dispatch workers run the synchronous description and close calls.
    /// Semaphores establish the ordering without sleeps; ten-second waits are
    /// failure safeguards and always release the description before joining work.
    /// - Throws: Temporary-file setup, file reads or unexpected close failures.
    @Test func closeDoesNotJoinInFlightSerialization() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("serialization-close.ndjson")
        let diagnostics = Box<[DiscordFileLogError]>([])
        let sink = try DiscordFileLogSink(url: url, onDiagnostic: { error in
            diagnostics.update { $0.append(error) }
        })
        let observation: SerializationCloseObservation = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let entered = DispatchSemaphore(value: 0)
                let release = DispatchSemaphore(value: 0)
                let writerFinished = DispatchSemaphore(value: 0)
                let closeFinished = DispatchSemaphore(value: 0)
                let closeError = Box<DiscordFileLogError?>(nil)
                DispatchQueue.global(qos: .userInitiated).async {
                    sink.write(.init(
                        label: "overlap", level: .info, message: "in flight",
                        metadata: ["description": .stringConvertible(PausingDescription(entered: entered, release: release))]
                    ))
                    writerFinished.signal()
                }
                let didEnter = entered.wait(timeout: .now() + 10) == .success
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try sink.close() }
                    catch { closeError.update { $0 = (error as? DiscordFileLogError) ?? .closeFailed } }
                    closeFinished.signal()
                }
                let closedBeforeRelease = closeFinished.wait(timeout: .now() + 10) == .success
                let whilePaused = closedBeforeRelease ? sink.snapshot() : nil
                let diagnosticsWhilePaused = diagnostics.read()
                release.signal()
                let writerJoined = writerFinished.wait(timeout: .now() + 10) == .success
                let closeJoined = closedBeforeRelease || closeFinished.wait(timeout: .now() + 10) == .success
                continuation.resume(returning: SerializationCloseObservation(
                    entered: didEnter, closedBeforeRelease: closedBeforeRelease,
                    writerJoined: writerJoined, closeJoined: closeJoined,
                    whilePaused: whilePaused, diagnosticsWhilePaused: diagnosticsWhilePaused,
                    closeError: closeError.read()
                ))
            }
        }
        #expect(observation.entered && observation.closedBeforeRelease)
        #expect(observation.writerJoined && observation.closeJoined)
        #expect(observation.closeError == nil)
        let whilePaused = try #require(observation.whilePaused)
        #expect(whilePaused.isClosed && whilePaused.writtenRecords == 0 && whilePaused.droppedRecords == 0)
        #expect(observation.diagnosticsWhilePaused.isEmpty)
        #expect(sink.snapshot().isClosed && sink.snapshot().droppedRecords == 1 && sink.snapshot().failures == 1)
        #expect(diagnostics.read() == [.closed])
        #expect(try Data(contentsOf: url).isEmpty)
        try sink.close()
    }

    /// Forces deterministic archive-rotation failure and confirms terminal, bounded error reporting.
    /// - Throws: Unexpected local setup/read/close errors.
    @Test func rotationFailureIsTerminal() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("rotation-failure.ndjson")
        let failures = Box<[DiscordFileLogError]>([])
        let record = DiscordLogRecord(label: "l", level: .info, message: "same", timestamp: Date(timeIntervalSince1970: 0))
        var encoder = DiscordLogJSONWriter(configuration: .init())
        let size = try encoder.encode(record).count
        let sink = try DiscordFileLogSink(url: url, configuration: .init(maximumFileBytes: size, maximumFiles: 2, maximumRecordBytes: size), onDiagnostic: { error in failures.update { $0.append(error) } })
        sink.write(record)
        // Remove the owned parent after opening. Its still-open active handle remains valid,
        // but rotation cannot create a replacement file in the now-missing directory.
        try FileManager.default.removeItem(at: folder)
        sink.write(record)
        sink.write(record)
        #expect(sink.snapshot().isClosed)
        #expect(sink.snapshot().writtenRecords == 1 && sink.snapshot().droppedRecords == 2)
        #expect(sink.snapshot().failures == 2 && failures.read() == [.rotationFailed, .closed])
        try sink.close()
    }

    /// Confirms file-handler filtering, clock injection and metadata-provider value precedence.
    /// - Throws: Local file, close or independent JSON decoding failures.
    @Test func fileHandlerProvidersAndFiltering() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("handler.ndjson")
        let sink = try DiscordFileLogSink(url: url)
        let calls = Box(0)
        var handler = DiscordFileLogHandler(label: "file", sink: sink, logLevel: .warning, metadataProvider: .init {
            calls.update { $0 += 1 }
            return ["winner": "provider", "provider": "yes"]
        }, now: { Date(timeIntervalSince1970: 2) })
        handler.metadata = ["winner": "base", "base": "yes"]
        handler[metadataKey: "remove"] = "old"
        handler[metadataKey: "remove"] = nil
        handler.log(event: .init(level: .debug, message: "filtered", metadata: nil, source: "s", file: "f", function: "fn", line: 3))
        #expect(calls.read() == 0 && sink.snapshot().writtenRecords == 0)
        handler.log(event: .init(level: .warning, message: "accepted", metadata: ["winner": "call"], source: "s", file: "f", function: "fn", line: 3))
        try sink.close()
        let record = try #require(try objects(at: url).first)
        #expect(record["metadata"] as? [String: String] == ["winner": "call", "base": "yes", "provider": "yes"])
        #expect(record["timestamp"] as? Double == 2_000)
        #expect(record["source"] as? String == "s" && record["file"] as? String == "f")
        #expect(record["function"] as? String == "fn" && record["line"] as? Int == 3)
        #expect(calls.read() == 1 && handler[metadataKey: "remove"] == nil)
    }

    /// Rejects invalid limits before creating files and distinguishes unsafe/missing destinations.
    /// - Throws: Unexpected temporary-directory or local file setup failures.
    @Test func invalidConfigurationAndDestinations() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("invalid.ndjson")
        let configurations: [DiscordFileLogConfiguration] = [
            .init(maximumFileBytes: 0), .init(maximumFiles: 0), .init(maximumFiles: 1_001),
            .init(maximumRecordBytes: 0), .init(maximumFileBytes: 1, maximumRecordBytes: 2),
            .init(maximumMetadataDepth: 0), .init(maximumMetadataDepth: 65),
            .init(maximumMetadataValues: 0), .init(maximumMetadataValues: 100_001),
        ]
        for configuration in configurations {
            #expect(throws: DiscordFileLogError.invalidConfiguration) { try DiscordFileLogSink(url: url, configuration: configuration) }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(throws: DiscordFileLogError.notFileURL) { try DiscordFileLogSink(url: URL(string: "https://example.invalid/log")!) }
        #expect(throws: DiscordFileLogError.notRegularFile) { try DiscordFileLogSink(url: folder) }
        #expect(throws: DiscordFileLogError.openFailed) { try DiscordFileLogSink(url: folder.appendingPathComponent("missing/log")) }
        try Data(repeating: 1, count: 300).write(to: url)
        #expect(throws: DiscordFileLogError.existingFileExceedsLimit) {
            try DiscordFileLogSink(url: url, configuration: .init(maximumFileBytes: 200, maximumRecordBytes: 100))
        }
        #expect(try Data(contentsOf: url).count == 300)
        #if !os(Windows)
        let symbolic = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: url)
        #expect(throws: DiscordFileLogError.notRegularFile) { try DiscordFileLogSink(url: symbolic) }
        #endif
        let archive = URL(fileURLWithPath: url.path + ".1")
        try Data(repeating: 1, count: 400).write(to: archive)
        #expect(throws: DiscordFileLogError.existingFileExceedsLimit) {
            try DiscordFileLogSink(url: url, configuration: .init(maximumFileBytes: 350, maximumRecordBytes: 100))
        }
        #expect(try Data(contentsOf: archive) == Data(repeating: 1, count: 400))
        #expect(try Data(contentsOf: url) == Data(repeating: 1, count: 300))
    }

    #if canImport(OSLog)
    /// Covers all Apple severity mappings and independent settings without asserting device log delivery.
    /// - Throws: No expected errors; assertions concern local mapping/provider behavior only.
    @Test func appleUnifiedLevelMappingAndValueSemantics() throws {
        #expect(DiscordOSLogHandler.unifiedLevel(for: .trace) == .debug)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .debug) == .debug)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .info) == .info)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .notice) == .default)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .warning) == .default)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .error) == .error)
        #expect(DiscordOSLogHandler.unifiedLevel(for: .critical) == .fault)
        let calls = Box(0)
        let descriptions = Box(0)
        var first = DiscordOSLogHandler(label: "test", subsystem: "DiscordKit.Tests", category: "explicit", logLevel: .info, metadataProvider: .init {
            calls.update { $0 += 1 }
            return ["context": "private"]
        })
        first[metadataKey: "value"] = "first"
        var second = first
        second.logLevel = .critical
        second[metadataKey: "value"] = "second"
        #expect(first.logLevel == .info && second.logLevel == .critical)
        #expect(first[metadataKey: "value"] == "first" && second[metadataKey: "value"] == "second")
        first.log(event: .init(level: .debug, message: "filtered", metadata: nil, source: nil, file: "", function: "", line: 0))
        #expect(calls.read() == 0)
        first.log(event: .init(level: .info, message: "private synthetic observation", error: SensitiveError(descriptions: descriptions), metadata: ["call": "private"], source: nil, file: "", function: "", line: 0))
        #expect(calls.read() == 1 && descriptions.read() == 0)
        let defaults = DiscordOSLogHandler(label: "defaults")
        #expect(defaults.logLevel == .info && defaults.metadata.isEmpty && defaults.metadataProvider == nil)
    }
    #endif
}
