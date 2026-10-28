// File: Sources/DiscordActivities/ActivityClient.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordTransport
import Foundation

/// Independently adopted Activity iframe protocol v1 owner. Construction performs no tasks or I/O.
/// One reader and one ordered writer isolate host control from consumer event processing. No client secrets,
/// ordinary bot credentials, automatic reconnect or implicit browser host creation are provided. Commands are
/// never replayed after ambiguous delivery; orientation has one explicit INVALID_PAYLOAD compatibility fallback.
/// Close is terminal; create a new client/transport after host reload. All public suspension points are reentrant.
public actor ActivityClient<C: Clock> where C.Duration == Duration {
    private enum State { case idle, starting, ready, closed }
    private struct Pending {
        let command: String
        let event: String?
        let bytes: Int
        let correlation: Logger.Metadata
        let continuation: CheckedContinuation<JSONValue, any Error>
    }
    private struct Write {
        let nonce: String?
        let data: Data
        let correlation: Logger.Metadata
    }
    private struct Group {
        var tokens: Set<UUID>
        var waiters: [UUID: CheckedContinuation<Void, any Error>]
        var state: GroupState
        let event: ActivityEventName
        let arguments: [String: JSONValue]
    }
    private enum GroupState { case subscribing, active, unsubscribing }

    private let transport: any ActivityTransport
    private let clock: C
    private let applicationID: ApplicationID
    private let host: ActivityHostParameters
    private let limits: ActivityClientLimits
    private let owner = UUID()
    private var state = State.idle
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var startup: CheckedContinuation<Void, any Error>?
    private var pending: [String: Pending] = [:]
    private var pendingBytes = 0
    private var writes: [Write] = []
    private var events: [(ActivityClientEvent, Int)] = []
    private var eventBytes = 0
    private var groups: [String: Group] = [:]
    private var subscriptionTasks: [String: Task<Void, Never>] = [:]

    /// Transfers exclusive messaging ownership without opening a browser, sending a handshake or starting tasks.
    /// - Parameters:
    ///   - applicationID: Nonzero registered Activity application identifier; never a bot credential.
    ///   - host: Validated Discord-injected iframe context, independent of transport sender authentication.
    ///   - transport: Caller-selected browser/native adapter that validates exact source and origin.
    ///   - clock: Injected monotonic clock for deterministic cancellation/deadlines.
    ///   - limits: Validated finite capacities. Aggregate authorities across clients belong to the application.
    /// - Throws: `ActivityFailure.invalidConfiguration` for a zero application identifier; ownership remains caller's.
    public init(applicationID: ApplicationID, host: ActivityHostParameters, transport: any ActivityTransport,
                clock: C, limits: ActivityClientLimits = try! ActivityClientLimits()) throws {
        guard applicationID.rawValue != 0 else { throw ActivityFailure.invalidConfiguration }
        self.applicationID = applicationID; self.host = host; self.transport = transport
        self.clock = clock; self.limits = limits
    }

    /// Performs the explicit v1 JSON handshake and waits for authenticated DISPATCH/READY with version 1.
    /// - Parameter timeout: Positive monotonic startup budget, default 15 seconds. One caller owns startup.
    /// - Throws: Cancellation, deadline, invalid handshake/READY, duplicate start, host close or adapter failure.
    /// Failure closes the exclusively owned transport and rejects all waiters. READY is retained as an ordered event.
    /// No official SDK version is impersonated; sdk_version is optional in the upstream handshake.
    public func start(timeout: Duration = .seconds(15)) async throws {
        try await DiscordLog.withOperation("activities.client", event: "activities.handshake.operation") {
            try await startOwned(timeout: timeout)
        }
    }

    /// Owns handshake admission and readiness inside a correlated diagnostic scope.
    /// - Parameter timeout: Original monotonic startup budget.
    /// - Throws: The unchanged handshake failure after terminal cleanup.
    private func startOwned(timeout: Duration) async throws {
        try Task.checkCancellation()
        guard timeout > .zero else { throw ActivityFailure.invalidConfiguration }
        guard state == .idle else { throw state == .closed ? ActivityFailure.closed : ActivityFailure.notReady }
        let logger = DiscordLog.makeLogger("activities.client")
        logger.trace("Activity handshake started", metadata: ["dk.event": "activities.handshake.started"])
        state = .starting
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: timeout))
        do {
            try await context.run { try await self.awaitReady() }
            logger.info("Activity host ready", metadata: ["dk.event": "activities.handshake.completed"])
        } catch {
            await fail(error)
            throw error
        }
    }

    /// Executes a typed catalog command once with bounded pending state and strict nonce/command correlation.
    /// - Parameters:
    ///   - request: Validated command/arguments and response decoder; raw catalog extension is explicit.
    ///   - timeout: Positive monotonic admission/write/reply budget, default 15 seconds.
    /// - Returns: Decoded response data with unknown fields preserved by catalog models.
    /// - Throws: Cancellation/deadline, closure, overload, host ERROR, correlation/protocol or codec failure.
    /// Cancellation removes an unsent tuple; a sent command is never replayed or undone. Late replies are ignored.
    public func execute<Response: Sendable>(_ request: ActivityRequest<Response>, timeout: Duration = .seconds(15)) async throws -> Response {
        return try await DiscordLog.withOperation("activities.client", event: "activities.command.operation") {
            try await executeOwned(request, timeout: timeout)
        }
    }

    /// Executes one command and its explicit compatibility handling in a diagnostic scope.
    /// - Parameters:
    ///   - request: Validated catalog operation and decoder, never formatted into logs.
    ///   - timeout: Original monotonic command budget.
    /// - Returns: The unchanged decoded host response.
    /// - Throws: Original admission, host, transport or decoder failures.
    private func executeOwned<Response: Sendable>(_ request: ActivityRequest<Response>, timeout: Duration) async throws -> Response {
        guard timeout > .zero else { throw ActivityFailure.invalidConfiguration }
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: timeout))
        let logger = DiscordLog.makeLogger("activities.client")
        logger.trace("Activity command started", metadata: ["dk.event": "activities.command.started"])
        let nonce = UUID().uuidString
        let data = try await context.run {
            do {
                return try await self.exchange(command: request.command.rawValue, arguments: request.arguments,
                                               event: request.event, nonce: nonce)
            } catch let error as ActivityCommandFailure where error.code == 4000 && request.command == .setOrientationLockState && request.arguments["grid_lock_state"] != nil {
                DiscordLog.makeLogger("activities.client").notice("Activity orientation compatibility fallback", metadata: ["dk.event": "activities.command.compatibility_fallback"])
                var compatible = request.arguments; compatible.removeValue(forKey: "grid_lock_state")
                return try await self.exchange(command: request.command.rawValue, arguments: compatible,
                                               event: request.event, nonce: UUID().uuidString)
            }
        }
        try Task.checkCancellation()
        let response = try request.decode(data)
        logger.debug("Activity command completed", metadata: ["dk.event": "activities.command.completed"])
        return response
    }

    /// Acquires one reference-counted subscription. Equal event/arguments share one upstream SUBSCRIBE.
    /// - Parameters:
    ///   - event: Nonempty event name, including explicit future names; READY requires no upstream subscription.
    ///   - arguments: Event-specific object (for example channel_id); canonical JSON distinguishes subscriptions.
    ///   - timeout: Positive budget for this local caller and the first upstream acknowledgement.
    /// - Returns: Opaque ownership token; release it explicitly through unsubscribe.
    /// - Throws: Cancellation/deadline, invalid/bounded-out arguments, host ERROR or closure. Cancelling the last
    ///   caller while admission is ambiguous closes the session; one cancelled duplicate never cancels other owners.
    public func subscribe(_ event: ActivityEventName, arguments: [String: JSONValue] = [:],
                          timeout: Duration = .seconds(15)) async throws -> ActivitySubscription {
        try Task.checkCancellation()
        guard state == .ready else { throw state == .closed ? ActivityFailure.closed : ActivityFailure.notReady }
        guard timeout > .zero, event != .error, !event.rawValue.isEmpty, event.rawValue.utf8.count <= 128,
              !event.rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ActivityFailure.invalidConfiguration
        }
        guard groups.values.reduce(0, { $0 + $1.tokens.count }) < limits.maximumSubscriptions else { throw ActivityFailure.overloaded }
        let key = try subscriptionKey(event, arguments: arguments)
        let token = ActivitySubscription(owner: owner, id: UUID(), key: key)
        if var group = groups[key] {
            guard group.state != .unsubscribing else { throw ActivityFailure.subscriptionTransition }
            group.tokens.insert(token.id); groups[key] = group
            DiscordLog.makeLogger("activities.client").trace("Activity subscription shared", metadata: ["dk.event": "activities.subscription.shared",
                "dk.owners": .stringConvertible(group.tokens.count)])
        } else {
            groups[key] = Group(tokens: [token.id], waiters: [:], state: event == .ready ? .active : .subscribing,
                                event: event, arguments: arguments)
            DiscordLog.makeLogger("activities.client").trace("Activity subscription group reserved", metadata: ["dk.event": "activities.subscription.reserved",
                "dk.groups": .stringConvertible(groups.count)])
            if event != .ready {
                subscriptionTasks[key] = Task { await self.admitSubscription(key, timeout: timeout) }
            }
        }
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: timeout))
        do {
            try await context.run { try await self.waitForSubscription(token) }
            DiscordLog.makeLogger("activities.client").debug("Activity subscription acquired", metadata: ["dk.event": "activities.subscription.acquired",
                "dk.groups": .stringConvertible(groups.count)])
            return token
        } catch {
            await abandonSubscription(token)
            throw error
        }
    }

    /// Releases one token; only the final owner sends UNSUBSCRIBE and waits for its acknowledgement.
    /// - Parameters:
    ///   - subscription: Token from this client. Repeated release is a no-op; foreign-client tokens fail.
    ///   - timeout: Positive final-acknowledgement budget, default 15 seconds.
    /// - Throws: Invalid token/budget, cancellation/deadline, host ERROR or closure. An uncertain final removal
    ///   closes the session so local and remote subscription state cannot silently diverge.
    public func unsubscribe(_ subscription: ActivitySubscription, timeout: Duration = .seconds(15)) async throws {
        try Task.checkCancellation()
        guard subscription.owner == owner, timeout > .zero else { throw ActivityFailure.invalidConfiguration }
        guard var group = groups[subscription.key], group.tokens.remove(subscription.id) != nil else { return }
        if !group.tokens.isEmpty { groups[subscription.key] = group; return }
        if group.event == .ready { groups.removeValue(forKey: subscription.key); return }
        group.state = .unsubscribing; groups[subscription.key] = group
        do {
            let request = try ActivityRequest<JSONValue>(command: .unsubscribe, arguments: group.arguments, event: group.event, decode: { $0 })
            _ = try await execute(request, timeout: timeout)
            groups.removeValue(forKey: subscription.key)
            DiscordLog.makeLogger("activities.client").debug("Activity subscription released", metadata: ["dk.event": "activities.subscription.released",
                "dk.groups": .stringConvertible(groups.count)])
        } catch { await fail(error); throw error }
    }

    /// Transfers the finite ordered event buffer to the caller and releases accounted storage.
    /// - Returns: All authenticated dispatches since the previous drain, including READY and unknown names.
    /// No callbacks run on the reader. Overflow fails the session rather than silently dropping state changes.
    public func drainEvents() -> [ActivityClientEvent] {
        let result = events.map(\.0)
        DiscordLog.makeLogger("activities.client").trace("Activity events drained", metadata: ["dk.event": "activities.events.drained",
            "dk.events": .stringConvertible(events.count), "dk.event_bytes": .stringConvertible(eventBytes)])
        events.removeAll(keepingCapacity: false); eventBytes = 0; return result
    }

    /// Reports bounded ownership for deterministic diagnostics without identities or payload labels.
    /// - Returns: Counts of pending operations, retained outbound bytes, events, event bytes and subscription tokens.
    public func snapshot() -> (pending: Int, pendingBytes: Int, events: Int, eventBytes: Int, subscriptions: Int) {
        (pending.count, pendingBytes, events.count, eventBytes, groups.values.reduce(0, { $0 + $1.tokens.count }))
    }

    /// Terminates the session, rejects all waiters and awaits transport cleanup; repeated calls share cleanup.
    /// An opcode-2 normal CLOSE is attempted after the current write, with a 250 ms continuous-time cleanup budget.
    /// No close handshake is retried. Adapter disposal releases blocked I/O when the budget expires.
    public func close() async { await fail(ActivityFailure.closed, notifyHost: true) }

    /// Installs startup ownership before either I/O task can observe a synchronous host response.
    /// - Throws: Cancellation/closure or serialization failure; startup's outer deadline owns cleanup.
    private func awaitReady() async throws {
        try Task.checkCancellation()
        guard state == .starting else { throw ActivityFailure.closed }
        let handshake: JSONValue = .object(["v": .number(try JSONNumber(rawValue: "1")), "encoding": .string("json"),
                                            "client_id": .string(applicationID.description), "frame_id": .string(host.frameID)])
        let data = try tuple(0, handshake)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startup = continuation
                DiscordLog.makeLogger("activities.client").trace("Activity startup waiter installed", metadata: ["dk.event": "activities.handshake.waiter.installed"])
                reader = Task { await self.readLoop() }
                writes.append(Write(nonce: nil, data: data, correlation: Self.correlationContext())); scheduleWriter()
            }
        } onCancel: { Task { await self.fail(CancellationError()) } }
    }

    /// Registers correlation and bounded retained bytes before scheduling exactly one ordered write.
    /// - Parameters:
    ///   - command: Exact catalog wire name.
    ///   - arguments: Immutable JSON object; outer bounds include its unknown subtrees.
    ///   - event: Subscription event, or nil for ordinary commands.
    ///   - nonce: Fresh operation identity never reused in this session.
    /// - Returns: Raw response data after strict correlation.
    /// - Throws: Cancellation, invalid state/limits or the sanitized terminal operation failure.
    private func exchange(command: String, arguments: [String: JSONValue], event: ActivityEventName?, nonce: String) async throws -> JSONValue {
        try Task.checkCancellation()
        guard state == .ready else { throw state == .closed ? ActivityFailure.closed : ActivityFailure.notReady }
        var fields: [String: JSONValue] = ["cmd": .string(command), "args": .object(arguments), "nonce": .string(nonce)]
        if let event { fields["evt"] = .string(event.rawValue) }
        let data = try tuple(1, .object(fields))
        guard pending.count < limits.maximumPending, data.count <= limits.maximumPendingBytes - pendingBytes else {
            DiscordLog.makeLogger("activities.client").debug("Activity command capacity exhausted", metadata: ["dk.event": "activities.command.overloaded",
                "dk.pending": .stringConvertible(pending.count), "dk.pending_bytes": .stringConvertible(pendingBytes)])
            throw ActivityFailure.overloaded
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[nonce] = Pending(command: command, event: event?.rawValue, bytes: data.count, correlation: Self.correlationContext(), continuation: continuation)
                pendingBytes += data.count; writes.append(Write(nonce: nonce, data: data, correlation: Self.correlationContext()))
                DiscordLog.makeLogger("activities.client").trace("Activity command admitted to bounded queue", metadata: ["dk.event": "activities.command.admitted",
                    "dk.pending": .stringConvertible(pending.count), "dk.pending_bytes": .stringConvertible(pendingBytes),
                    "dk.queued": .stringConvertible(writes.count)])
                scheduleWriter()
            }
        } onCancel: { Task { await self.cancel(nonce) } }
    }

    /// Removes a cancelled caller without undoing an already delivered command or reusing its nonce.
    /// - Parameter nonce: Local operation identity; absent/late cancellation is harmless.
    private func cancel(_ nonce: String) {
        guard let operation = pending.removeValue(forKey: nonce) else { return }
        pendingBytes -= operation.bytes; writes.removeAll { $0.nonce == nonce }
        Self.withCorrelation(operation.correlation) {
            DiscordLog.makeLogger("activities.client").trace("Activity command waiter cancelled", metadata: ["dk.event": "activities.command.waiter.cancelled",
                "dk.pending": .stringConvertible(pending.count), "dk.pending_bytes": .stringConvertible(pendingBytes)])
        }
        operation.continuation.resume(throwing: CancellationError())
    }

    /// Starts at most one writer task; queue admission already reserved operation and byte capacity.
    private func scheduleWriter() {
        guard writer == nil else { return }; writer = Task { await self.writeLoop() }
    }

    /// Writes sequentially with no retries, preventing actor reentrancy from reordering browser sends.
    /// Any ambiguous adapter failure closes the session; a blocked send must be released by adapter close.
    private func writeLoop() async {
        while state != .closed, !writes.isEmpty {
            let write = writes.removeFirst()
            do {
                try await Self.withCorrelation(write.correlation) {
                    DiscordLog.makeLogger("activities.client").trace("Activity ordered write starting", metadata: ["dk.event": "activities.write.started",
                        "dk.queued": .stringConvertible(writes.count)])
                    try await transport.send(write.data)
                    DiscordLog.makeLogger("activities.client").trace("Activity ordered write completed", metadata: ["dk.event": "activities.write.completed"])
                }
            }
            catch {
                if state != .closed { await fail(ActivityFailure.closed) }
                return
            }
        }
        writer = nil
    }

    /// Owns the only transport reader. Parsing/protocol errors fail closed without echoing untrusted data.
    private func readLoop() async {
        do {
            while !Task.isCancelled, let data = try await transport.receive() {
                try accept(data)
            }
            await fail(ActivityFailure.closed)
        } catch { await fail(error is ActivityFailure ? error : ActivityFailure.invalidFrame) }
    }

    /// Validates complete bounded tuple envelopes, correlates replies and queues ordered dispatches.
    /// - Parameter bytes: Authenticated adapter frame. Source/origin validation must precede this method.
    /// - Throws: Invalid schema/version/opcode, command mismatch or event-buffer overload; caller closes the session.
    private func accept(_ bytes: Data) throws {
        guard state != .closed else { return }
        guard case .array(let tuple) = try JSONValue.parse(bytes, limits: JSONLimits(maximumBytes: limits.maximumFrameBytes)),
              tuple.count == 2, case .number(let rawOpcode) = tuple[0], let opcode = Int(rawOpcode.rawValue),
              String(opcode) == rawOpcode.rawValue, case .object(let fields) = tuple[1] else { throw ActivityFailure.invalidFrame }
        if opcode == 3 || opcode == 0 { return }
        if opcode == 2 { throw ActivityFailure.closed }
        guard opcode == 1, case .string(let command) = fields["cmd"] else { throw ActivityFailure.invalidFrame }
        if case .string(let nonce) = fields["nonce"] {
            guard let operation = pending[nonce] else {
                DiscordLog.makeLogger("activities.client").trace("Activity late reply ignored", metadata: ["dk.event": "activities.reply.late"])
                return
            }
            guard operation.command == command else { throw ActivityFailure.commandMismatch }
            let data: JSONValue
            if let value = fields["data"] { data = value }
            else if fields["evt"] == .null && ["INVITE_USER_EMBEDDED", "OPEN_SHARE_MOMENT_DIALOG"].contains(command) { data = .null }
            else { throw ActivityFailure.invalidFrame }
            if let expectedEvent = operation.event, fields["evt"] != .string("ERROR") {
                guard case .object(let acknowledgement) = data, acknowledgement["evt"] == .string(expectedEvent) else {
                    throw ActivityFailure.commandMismatch
                }
            }
            let rejection: ActivityCommandFailure?
            if fields["evt"] == .string("ERROR") {
                guard case .object(let failure) = data, case .number(let code) = failure["code"],
                      let integer = Int(code.rawValue), String(integer) == code.rawValue,
                      failure["message"] == nil || { if case .string = failure["message"] { return true }; return false }() else { throw ActivityFailure.invalidFrame }
                rejection = ActivityCommandFailure(code: integer)
            } else {
                guard fields["evt"] == .null else { throw ActivityFailure.invalidFrame }
                rejection = nil
            }
            pending.removeValue(forKey: nonce); pendingBytes -= operation.bytes
            Self.withCorrelation(operation.correlation) {
                DiscordLog.makeLogger("activities.client").trace("Activity reply correlated and waiter released", metadata: ["dk.event": "activities.reply.correlated",
                    "dk.pending": .stringConvertible(pending.count), "dk.pending_bytes": .stringConvertible(pendingBytes),
                    "dk.rejected": .stringConvertible(rejection != nil)])
            }
            if let rejection { operation.continuation.resume(throwing: rejection) }
            else { operation.continuation.resume(returning: data) }
            return
        }
        guard fields["nonce"] == nil || fields["nonce"] == .null,
              case .string(let event) = fields["evt"], let data = fields["data"],
              command == "DISPATCH" || event == "ERROR" else { throw ActivityFailure.invalidFrame }
        if state == .starting {
            guard event == "READY", fields["nonce"] == .null,
                  let ready = try? ActivityReady(value: data), ready.version.rawValue == "1" else {
                throw ActivityFailure.invalidFrame
            }
            DiscordLog.makeLogger("activities.client").trace("Activity READY envelope validated", metadata: ["dk.event": "activities.handshake.ready.validated"])
            state = .ready; startup?.resume(); startup = nil
        } else if event == "READY" { throw ActivityFailure.invalidFrame }
        guard events.count < limits.maximumEvents, bytes.count <= limits.maximumEventBytes - eventBytes else { throw ActivityFailure.overloaded }
        events.append((ActivityClientEvent(name: ActivityEventName(rawValue: event), data: data), bytes.count)); eventBytes += bytes.count
        DiscordLog.makeLogger("activities.client").trace("Activity dispatch buffered", metadata: ["dk.event": "activities.event.buffered",
            "dk.events": .stringConvertible(events.count), "dk.event_bytes": .stringConvertible(eventBytes)])
    }

    /// Produces one bounded JSON tuple, preserving numeric lexemes and rejecting excessive depth/node counts.
    /// - Parameters:
    ///   - opcode: Activity handshake/frame/close opcode 0/1/2, independent from main Gateway versions.
    ///   - payload: Complete object subtree.
    /// - Returns: UTF-8 JSON for exactly one browser postMessage tuple.
    /// - Throws: JSON validation/size/depth failure before any send.
    private func tuple(_ opcode: Int, _ payload: JSONValue) throws -> Data {
        try JSONValue.array([.number(JSONNumber(rawValue: String(opcode))), payload])
            .serialized(limits: JSONLimits(maximumBytes: limits.maximumFrameBytes))
    }

    /// Computes a deterministic canonical group key under whole-document session bounds.
    /// - Parameters:
    ///   - event: Exact dispatch name.
    ///   - arguments: Immutable event-specific parameters; object keys serialize in deterministic order.
    /// - Returns: Bounded canonical JSON string used privately and never logged.
    /// - Throws: JSON bounds violations before allocating a group.
    private func subscriptionKey(_ event: ActivityEventName, arguments: [String: JSONValue]) throws -> String {
        let data = try JSONValue.array([.string(event.rawValue), .object(arguments)]).serialized(limits: JSONLimits(maximumBytes: limits.maximumFrameBytes))
        return String(decoding: data, as: UTF8.self)
    }

    /// Sends the unique first subscription and atomically activates/resumes every remaining duplicate owner.
    /// - Parameters:
    ///   - key: Canonical local group identity; never appears in diagnostics.
    ///   - timeout: First caller's bounded upstream acknowledgement deadline.
    private func admitSubscription(_ key: String, timeout: Duration) async {
        guard let group = groups[key] else { return }
        do {
            let request = try ActivityRequest<JSONValue>(command: .subscribe, arguments: group.arguments, event: group.event, decode: { $0 })
            _ = try await execute(request, timeout: timeout)
            if var current = groups[key] {
                current.state = .active; let waiters = current.waiters; current.waiters = [:]; groups[key] = current
                for waiter in waiters.values { waiter.resume() }
            }
        } catch {
            if let current = groups.removeValue(forKey: key) { for waiter in current.waiters.values { waiter.resume(throwing: error) } }
            await fail(error)
        }
        subscriptionTasks.removeValue(forKey: key)
    }

    /// Waits independently for a shared upstream admission without sharing cancellation between owners.
    /// - Parameter token: Previously reserved local ownership token.
    /// - Throws: Closure/cancellation or the group's upstream admission error.
    private func waitForSubscription(_ token: ActivitySubscription) async throws {
        try Task.checkCancellation()
        guard let group = groups[token.key], group.tokens.contains(token.id) else { throw ActivityFailure.closed }
        if group.state == .active { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in groups[token.key]?.waiters[token.id] = continuation }
        } onCancel: { Task { await self.abandonSubscription(token) } }
    }

    /// Releases a cancelled duplicate; final ambiguous admission closes ownership rather than leaking a host listener.
    /// - Parameter token: Reserved caller ownership. Repeated removal is safe.
    private func abandonSubscription(_ token: ActivitySubscription) async {
        guard var group = groups[token.key], group.tokens.contains(token.id) else { return }
        if group.state == .active, group.tokens.count == 1 {
            group.waiters.removeValue(forKey: token.id)?.resume(throwing: CancellationError())
            do { try await unsubscribe(token) } catch { await fail(error) }
            return
        }
        group.tokens.remove(token.id)
        group.waiters.removeValue(forKey: token.id)?.resume(throwing: CancellationError())
        groups[token.key] = group
        if group.tokens.isEmpty { await fail(ActivityFailure.subscriptionTransition) }
    }

    /// Copies only finite correlation strings into already bounded request ownership.
    /// Application metadata and Discord identifiers are never retained by this helper.
    /// - Returns: At most three diagnostic identifiers, each at most 128 UTF-8 bytes.
    private nonisolated static func correlationContext() -> Logger.Metadata {
        var result: Logger.Metadata = [:]
        for key in ["dk.trace_id", "dk.span_id", "dk.parent_span_id"] {
            if case .string(let value) = DiscordLog.context[key], value.utf8.count <= 128 {
                result[key] = .string(value)
            }
        }
        return result
    }

    /// Rebinds diagnostic correlation without changing current output policy or execution ownership.
    /// - Parameters:
    ///   - correlation: Finite identifiers captured when this exact operation was admitted.
    ///   - operation: Synchronous logging work executed once without tasks or suspension.
    private nonisolated static func withCorrelation(_ correlation: Logger.Metadata, operation: () -> Void) {
        var context = DiscordLog.context
        for key in ["dk.trace_id", "dk.span_id", "dk.parent_span_id"] { context[key] = correlation[key] }
        DiscordLog.$context.withValue(context, operation: operation)
    }

    /// Preserves exact request correlation through the existing asynchronous transport send.
    /// - Parameters:
    ///   - correlation: Finite diagnostic identifiers retained by bounded request ownership.
    ///   - isolation: Original writer actor isolation, inferred without an executor hop.
    ///   - operation: Existing send invoked once; no new task, retry or cancellation handler is introduced.
    /// - Throws: The original unchanged transport or cancellation error.
    private static func withCorrelation(_ correlation: Logger.Metadata,
        isolation: isolated (any Actor)? = #isolation, operation: () async throws -> Void) async rethrows {
        var context = DiscordLog.context
        for key in ["dk.trace_id", "dk.span_id", "dk.parent_span_id"] { context[key] = correlation[key] }
        try await DiscordLog.$context.withValue(context, operation: operation)
    }

    /// Reserves terminal state before suspension, resumes every waiter exactly once and shares adapter cleanup.
    /// - Parameters:
    ///   - error: Sanitized terminal error or cancellation. No host payload is retained in failure messages.
    ///   - notifyHost: Whether explicit user close should attempt ordered opcode-2 notification before disposal.
    ///     Failures/remote close dispose immediately; all paths reserve terminal state before suspending.
    private func fail(_ error: any Error, notifyHost: Bool = false) async {
        if state != .closed {
            let logger = DiscordLog.makeLogger("activities.client")
            if notifyHost || error as? ActivityFailure == .closed {
                logger.info("Activity client closing", metadata: ["dk.event": "activities.client.closing"])
            } else if error is CancellationError {
                logger.trace("Activity client cancelled", metadata: ["dk.event": "activities.client.cancelled"])
            } else {
                logger.error("Activity client terminated", metadata: ["dk.event": "activities.client.failed",
                    "dk.pending": .stringConvertible(pending.count), "dk.failure": .string(error is ActivityFailure ? "protocol_or_state" : "transport")])
            }
            logger.trace("Activity owned waiters and queues releasing", metadata: ["dk.event": "activities.client.cleanup.releasing",
                "dk.pending": .stringConvertible(pending.count), "dk.pending_bytes": .stringConvertible(pendingBytes),
                "dk.events": .stringConvertible(events.count), "dk.groups": .stringConvertible(groups.count)])
            state = .closed
            startup?.resume(throwing: error); startup = nil
            let operations = pending.values; pending.removeAll(); pendingBytes = 0; writes.removeAll()
            for operation in operations { operation.continuation.resume(throwing: error) }
            for group in groups.values { for waiter in group.waiters.values { waiter.resume(throwing: error) } }
            groups.removeAll(); events.removeAll(); eventBytes = 0
            let previousWriter = writer
            reader?.cancel(); writer?.cancel(); reader = nil; writer = nil
            for task in subscriptionTasks.values { task.cancel() }; subscriptionTasks.removeAll()
            let transport = transport
            let notice = notifyHost ? try? tuple(2, .object(["code": .number(JSONNumber(rawValue: "1000")), "message": .string("")])) : nil
            cleanup = Task {
                if let notice {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await previousWriter?.value
                            if !Task.isCancelled { try? await transport.send(notice) }
                        }
                        group.addTask {
                            try? await Task.sleep(for: .milliseconds(250))
                            if !Task.isCancelled { await transport.close() }
                        }
                        _ = await group.next(); group.cancelAll()
                        await transport.close()
                    }
                } else { await transport.close() }
                logger.info("Activity client resources released", metadata: ["dk.event": "activities.client.closed"])
            }
        }
        await cleanup?.value
    }
}
