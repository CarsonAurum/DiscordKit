/// An `@main`-compatible application with explicitly constructed host dependencies.
/// Modules, credentials, adapters, services and shared authorities belong to the application
/// factory. Merely conforming to this protocol performs no environment access or runtime work.
public protocol BotApplication: Sendable {
    /// Builds one inert runtime over explicitly compiled command/event protocol modules.
    /// - Returns: Single-use owner whose construction starts no registration, tasks or I/O.
    /// - Throws: Application configuration/credential validation or catalog/host admission errors.
    ///   The application owns environment reading and concrete adapter selection, if desired.
    static func makeRuntime() async throws -> BotRuntime
}

extension BotApplication {
    /// Creates the host once and awaits its complete supervised lifetime and cleanup.
    /// - Throws: Factory, cancellation, setup, handler, client or cleanup failures unchanged.
    ///   Construction and ordinary execution never synchronize command registrations.
    public static func main() async throws {
        let runtime = try await makeRuntime()
        try await runtime.run()
    }
}
