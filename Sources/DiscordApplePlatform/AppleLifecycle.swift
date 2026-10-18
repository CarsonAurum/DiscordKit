import DiscordCore
import DiscordTransport
import Foundation

/// Apple host policy selected independently from runtime transport qualification.
public enum AppleHost: String, CaseIterable, Sendable {
    case macOS, iOS, tvOS, watchOS, visionOS, other

    /// Identifies the compile target without claiming device/runtime qualification.
    /// - Returns: The current Apple OS, or `other` on portable test/server hosts.
    public static var current: AppleHost {
        #if os(macOS)
        .macOS
        #elseif os(iOS)
        .iOS
        #elseif os(tvOS)
        .tvOS
        #elseif os(watchOS)
        .watchOS
        #elseif os(visionOS)
        .visionOS
        #else
        .other
        #endif
    }
}

/// Host-reported application state; the embedding app forwards its actual lifecycle.
///
/// This adapter neither acquires background execution time nor observes UI frameworks.
/// The app must forward suspension/path replacement before retaining new resources.
public enum AppleLifecycleState: String, CaseIterable, Sendable {
    case active, inactive, background, suspended, stopped
}

/// Capacity failure when the lifecycle owner already tracks its configured maximum.
public enum AppleLifecycleFailure: Error, Equatable, Sendable {
    case invalidLimit
    case resourceLimit
}

/// A bounded lifecycle owner that drains transports when host policy revokes their use.
///
/// UI/browser/authentication/audio frameworks stay outside the transport graph. A
/// lifecycle state is provided by the embedding application; no simulator result or
/// compiled SDK implies physical-device qualification. Availability combines this
/// policy with a caller-supplied list of independently qualified capabilities.
///
/// Resources have a single lifecycle owner. Registration does not open sockets;
/// transitions stop admission before closing affected resources. Cleanup tasks are
/// owned and awaited even if callers are cancelled. Consumers must recheck after
/// suspension; an already-in-flight network write cannot be recalled.
public actor AppleLifecycle: TransportResource {
    private let host: AppleHost
    private let qualifiedCapabilities: Set<PlatformCapability>
    private let maximumResources: Int
    private var state: AppleLifecycleState
    private var resources: [UUID: (PlatformCapability, any TransportResource)] = [:]
    private var cleanupTask: (UUID, Task<Void, Never>)?

    /// Creates an empty lifecycle owner without installing UI notification observers.
    /// - Parameters:
    ///   - host: Policy host; defaults to the compile target, injectable for tests.
    ///   - initialState: App-reported state; defaults to active for explicit foreground adoption.
    ///   - qualifiedCapabilities: Capabilities proven by the consumer's actual adapter/host
    ///     conformance tests; defaults to empty, returning `notQualified`.
    ///   - maximumResources: Positive maximum retained registrations, defaulting to 64.
    /// - Throws: `AppleLifecycleFailure.invalidLimit` for a nonpositive resource bound.
    public init(host: AppleHost = .current, initialState: AppleLifecycleState = .active,
                qualifiedCapabilities: Set<PlatformCapability> = [], maximumResources: Int = 64) throws {
        guard maximumResources > 0 else { throw AppleLifecycleFailure.invalidLimit }
        self.host = host
        state = initialState
        self.qualifiedCapabilities = qualifiedCapabilities
        self.maximumResources = maximumResources
    }

    /// Checks host/lifecycle policy and supplied qualification without performing I/O.
    ///
    /// watchOS raw sockets, WebSocket and listeners remain restricted; this adapter
    /// does not infer an authorized exception. Mobile background/suspension cannot
    /// promise ordinary long-lived transport execution. Browser and media adapters
    /// are unimplemented and never become available through caller qualification.
    /// - Parameter capability: Portable capability to inspect.
    /// - Returns: Structured availability or a closed unavailable reason; no OS grants
    ///   or permissions are requested and no resource is retained.
    public func availability(of capability: PlatformCapability) -> CapabilityAvailability {
        if cleanupTask != nil { return .unavailable(.restrictedByHost) }
        return policyAvailability(of: capability, in: state)
    }

    /// Transfers lifecycle ownership of an already-created transport resource.
    /// - Parameters:
    ///   - resource: Closeable resource; caller must close it if registration fails.
    ///   - capability: Capability required to retain this resource in the current state.
    /// - Returns: Opaque registration for explicit removal; resources are otherwise
    ///   closed on an invalidating transition or `close()`.
    /// - Throws: Cancellation, `DiscordError.capabilityUnavailable`, or
    ///   `AppleLifecycleFailure.resourceLimit`. Failure does not transfer ownership.
    public func retain(_ resource: any TransportResource, requiring capability: PlatformCapability) throws -> UUID {
        try Task.checkCancellation()
        try availability(of: capability).requireAvailable()
        guard resources.count < maximumResources else { throw AppleLifecycleFailure.resourceLimit }
        let registration = UUID()
        resources[registration] = (capability, resource)
        return registration
    }

    /// Removes and closes one registration; stale/repeated removals do nothing.
    /// - Parameter registration: Opaque identifier previously returned by `retain`.
    /// - Important: Close remains usable from cancelled tasks and awaits resource cleanup.
    ///   A transition may have taken ownership first; its own caller awaits that cleanup.
    public func release(_ registration: UUID) async {
        guard let entry = resources.removeValue(forKey: registration) else { return }
        await entry.1.close()
    }

    /// Updates the app-reported state and drains resources whose policy was revoked.
    ///
    /// Admission is closed while cleanup runs. Competing transitions await current
    /// cleanup before evaluating their requested state; caller scheduling determines
    /// their order. Active/inactive transitions preserve eligible foreground resources.
    /// Calling active after stopped explicitly begins a fresh adoption lifecycle.
    /// - Parameter newState: State supplied by the app's actual lifecycle integration.
    /// Completes after all resources invalidated by this transition finish closing.
    public func transition(to newState: AppleLifecycleState) async {
        while let pending = cleanupTask {
            await pending.1.value
            if cleanupTask?.0 == pending.0 { cleanupTask = nil }
        }
        state = newState
        let invalid = resources.filter { policyAvailability(of: $0.value.0, in: newState) != .available }
        for key in invalid.keys { resources.removeValue(forKey: key) }
        guard !invalid.isEmpty else { return }
        let closing = invalid.values.map { $0.1 }
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for resource in closing { group.addTask { await resource.close() } }
            }
        }
        let cleanupID = UUID()
        cleanupTask = (cleanupID, task)
        await task.value
        if cleanupTask?.0 == cleanupID { cleanupTask = nil }
    }

    /// Stops admission and closes all lifecycle-owned resources, safe to repeat.
    /// Returning means transition-owned cleanup has completed; callers may explicitly
    /// restart with `transition(to: .active)` after this call completes.
    public func close() async { await transition(to: .stopped) }

    /// Reports retained registrations for deterministic ownership and capacity checks.
    /// - Returns: A count in `0...maximumResources`, excluding resources being drained.
    public func retainedResourceCount() -> Int { resources.count }

    /// Applies a conservative host policy independently of in-progress cleanup.
    /// - Parameters:
    ///   - capability: Requested portable capability.
    ///   - lifecycleState: State being evaluated, possibly a proposed transition.
    /// - Returns: Policy plus explicit qualification; never requests host permission.
    private func policyAvailability(of capability: PlatformCapability,
                                    in lifecycleState: AppleLifecycleState) -> CapabilityAvailability {
        guard host != .other else { return .unavailable(.unsupportedPlatform) }
        switch capability {
        case .browserAuthorization, .audioCapture, .audioPlayback:
            return .unavailable(.notImplemented)
        case .backgroundExecution:
            return .unavailable(.restrictedByHost)
        default: break
        }
        if lifecycleState == .stopped || lifecycleState == .suspended {
            return .unavailable(.restrictedByHost)
        }
        if host != .macOS && lifecycleState == .background { return .unavailable(.restrictedByHost) }
        if host == .watchOS && capability != .http { return .unavailable(.restrictedByHost) }
        if host != .macOS && (capability == .localIPC || capability == .httpIngress) {
            return .unavailable(.restrictedByHost)
        }
        return qualifiedCapabilities.contains(capability) ? .available : .unavailable(.notQualified)
    }
}
