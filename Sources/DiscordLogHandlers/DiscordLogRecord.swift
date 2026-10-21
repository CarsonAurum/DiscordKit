import Foundation
import Logging

/// A synchronous logging observation suitable for forwarding to an application-owned output.
///
/// Metadata retains SwiftLog's structured strings, arrays and dictionaries. Custom
/// `stringConvertible` values remain application-owned Sendable values; outputs must
/// render their descriptions synchronously when an exact textual snapshot is needed.
public struct DiscordLogRecord: Sendable {
    /// The logger's stable subsystem label.
    public let label: String
    /// The original semantic SwiftLog severity, preserved across output adapters.
    public let level: Logger.Level
    /// The fully interpolated message supplied by SwiftLog.
    public let message: String
    /// Merged metadata, with call values overriding provider values and base values.
    public let metadata: Logger.Metadata
    /// The module or explicitly supplied logging source.
    public let source: String
    /// The caller's source-file identifier.
    public let file: String
    /// The caller's function identifier.
    public let function: String
    /// The caller's one-based source line.
    public let line: UInt
    /// Wall-clock observation time; file output encodes milliseconds since the Unix epoch.
    public let timestamp: Date
    /// Whether SwiftLog attached an error; error objects and descriptions are intentionally omitted.
    public let hasError: Bool

    /// Creates an immutable observation without starting work or selecting any global backend.
    /// - Parameters:
    ///   - label: Stable subsystem label; outputs do not infer privacy from its spelling.
    ///   - level: Original SwiftLog severity.
    ///   - message: Already-rendered message; callers remain responsible for redaction.
    ///   - metadata: Structured, already-merged context; defaults to an empty dictionary.
    ///   - source: Module or caller-supplied source; defaults to an empty string.
    ///   - file: Source-file identifier; defaults to an empty string.
    ///   - function: Source function; defaults to an empty string.
    ///   - line: Source line; zero denotes an unspecified line.
    ///   - timestamp: Wall-clock observation time; defaults to the current time.
    ///   - hasError: Whether an error accompanied the event; the payload is never rendered automatically.
    public init(
        label: String, level: Logger.Level, message: String, metadata: Logger.Metadata = [:],
        source: String = "", file: String = "", function: String = "", line: UInt = 0,
        timestamp: Date = Date(), hasError: Bool = false
    ) {
        self.label = label
        self.level = level
        self.message = message
        self.metadata = metadata
        self.source = source
        self.file = file
        self.function = function
        self.line = line
        self.timestamp = timestamp
        self.hasError = hasError
    }

    /// Captures one accepted SwiftLog call and evaluates its provider exactly once.
    /// - Parameters:
    ///   - label: Stable handler label.
    ///   - event: Accepted SwiftLog event; error payloads are omitted to avoid leaking descriptions.
    ///   - base: Handler-local metadata with value semantics.
    ///   - provider: Optional dynamic context evaluated on the calling thread.
    ///   - timestamp: Wall-clock time observed by the handler.
    /// - Returns: One merged record; no output or global configuration is performed.
    static func capture(
        label: String, event: LogEvent, base: Logger.Metadata,
        provider: Logger.MetadataProvider?, timestamp: Date
    ) -> Self {
        var merged = base
        if let provider { merged.merge(provider.get()) { _, value in value } }
        if let metadata = event.metadata { merged.merge(metadata) { _, value in value } }
        return Self(
            label: label, level: event.level, message: event.message.description, metadata: merged,
            source: event.source, file: event.file, function: event.function, line: event.line,
            timestamp: timestamp, hasError: event.error != nil
        )
    }
}

/// A SwiftLog backend for application-owned console, telemetry, test or other outputs.
///
/// The callback runs synchronously on the logging caller and may run concurrently.
/// It owns any forwarding, buffering, privacy policy and errors. This handler starts
/// no tasks and never bootstraps `LoggingSystem`. Use SwiftLog's `StreamLogHandler`
/// for standard output/error and `MultiplexLogHandler` to combine independent outputs.
public struct DiscordCallbackLogHandler: LogHandler {
    /// Handler-local metadata; copies remain independent.
    public var metadata: Logger.Metadata = [:]
    /// Dynamic metadata evaluated only for accepted calls.
    public var metadataProvider: Logger.MetadataProvider?
    /// Minimum accepted severity; defaults to informational output.
    public var logLevel: Logger.Level
    private let label: String
    private let output: @Sendable (DiscordLogRecord) -> Void
    private let now: @Sendable () -> Date

    /// Configures a callback without invoking it or starting background work.
    /// - Parameters:
    ///   - label: Stable logger/subsystem identifier.
    ///   - logLevel: Minimum severity; defaults to `.info`.
    ///   - metadataProvider: Optional synchronous dynamic context.
    ///   - now: Injected wall clock; defaults to the current time.
    ///   - output: Concurrent-safe synchronous consumer. Avoid recursive logging through itself.
    public init(
        label: String, logLevel: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        output: @escaping @Sendable (DiscordLogRecord) -> Void
    ) {
        self.label = label
        self.logLevel = logLevel
        self.metadataProvider = metadataProvider
        self.now = now
        self.output = output
    }

    /// Reads or changes only this handler copy's stored metadata.
    /// - Parameter metadataKey: Exact metadata key; assigning `nil` removes it.
    /// - Returns: The stored value, excluding provider and call metadata.
    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        /// Returns this copy's stored metadata without consulting dynamic providers.
        get { metadata[metadataKey] }
        /// Changes this copy only; assigning nil removes the stored key.
        set { metadata[metadataKey] = newValue }
    }

    /// Delivers one accepted record synchronously; filtered calls do not evaluate providers.
    /// - Parameter event: Accepted SwiftLog event; call metadata wins duplicate keys.
    ///   Error presence is retained; error payloads and descriptions are omitted.
    public func log(event: LogEvent) {
        guard event.level >= logLevel else { return }
        output(.capture(
            label: label, event: event, base: metadata, provider: metadataProvider, timestamp: now()
        ))
    }
}
