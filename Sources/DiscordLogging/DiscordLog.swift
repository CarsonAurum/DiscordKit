@_exported import Logging

/// Native SwiftLog entry points shared by independently adopted DiscordKit products.
///
/// The application owns `LoggingSystem.bootstrap`, handlers, thresholds and retention.
/// This module starts no tasks, opens no outputs and never bootstraps the process.
/// Library events use `trace`/`debug` and exceptional `warning`/`error`/`critical`;
/// `info` and `notice` remain available for application semantic events.
public enum DiscordLog {
    /// Application-supplied factory inherited by structured child tasks.
    ///
    /// The default honors SwiftLog's process configuration. Override this task-local
    /// value around an explicit operation or supervised `run` to select a logger
    /// without mutating process state. Detached tasks do not inherit task-local values.
    /// Factories must be concurrency-safe, cheap, and must not log recursively.
    /// No logger is cached during inert subsystem construction.
    @TaskLocal public static var loggerFactory: @Sendable (String) -> Logger = { Logger(label: $0) }

    /// Creates a native logger for an operation using the current application factory.
    ///
    /// Metadata and threshold retain SwiftLog value semantics. This method adds only
    /// the stable subsystem field and does not change the application's threshold.
    /// - Parameter subsystem: Stable subsystem name, such as `http` or `voice`.
    ///   Library call sites use fixed names rather than user data or credentials.
    /// - Returns: A logger labeled `discordkit.<subsystem>`, with `dk.subsystem` metadata.
    public static func makeLogger(_ subsystem: String) -> Logger {
        var logger = loggerFactory("discordkit.\(subsystem)")
        logger[metadataKey: "dk.subsystem"] = .string(subsystem)
        return logger
    }
}
