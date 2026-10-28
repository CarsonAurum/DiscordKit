// File: Sources/DiscordInteractions/InteractionHTTPApplication.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTransport
import Foundation

/// HTTP-only interaction composition with structured handler ownership and early inline acknowledgement.
/// Construction starts no listener, timer or network work; callers inject and own the ingress adapter.
public struct InteractionHTTPApplication: Sendable {
    private let applicationID: ApplicationID
    private let ingress: DiscordSignedIngress
    private let admission: InteractionAcknowledgementAdmission
    private let autoDefer: InteractionAutoDeferPolicy?
    private let limits: JSONLimits

    /// Binds independently bounded authentication and acknowledgement authorities.
    /// - Parameters:
    ///   - applicationID: Expected application; authenticated cross-application payloads are rejected before dispatch.
    ///   - ingress: Shared bounded signed-ingress adapter. Use a separate verifier/policy for webhook events.
    ///   - admission: Shared initial-only count/byte authority, independent from ordinary REST work.
    ///   - autoDefer: Optional early defer, disabled by default. Autocomplete, PING and unknown types never auto-defer.
    ///     Update mode applies only to component/modal input carrying an original message.
    ///   - limits: Complete JSON bounds applied only after signature verification.
    public init(applicationID: ApplicationID, ingress: DiscordSignedIngress,
                admission: InteractionAcknowledgementAdmission, autoDefer: InteractionAutoDeferPolicy? = nil,
                limits: JSONLimits = .default) {
        self.applicationID = applicationID; self.ingress = ingress; self.admission = admission
        self.autoDefer = autoDefer; self.limits = limits
    }

    /// Authenticates one exchange, normalizes its typed context and owns its handler until completion.
    ///
    /// The initial sink sends HTTP 200 immediately when reply/defer wins; a slow handler remains
    /// structured and may edit through the injected continuation sink after the HTTP response is sent.
    /// PING receives PONG without invoking the handler. Authentication/parsing/application failures return
    /// 401/400/403. A handler that exits or throws before responding receives 500; once an initial response
    /// is reserved no second HTTP response is attempted. Handler errors are rethrown after cleanup.
    ///
    /// Configure this application's delivery mode as HTTP in Discord. Gateway applications build the
    /// same InteractionContext with `.gateway` and an HTTP REST sink instead. No Gateway import is needed.
    /// - Parameters:
    ///   - exchange: Accepted request and single response slot; ownership transfers on all paths.
    ///   - context: Receipt clock and handler deadline. This may exceed three seconds for deferred work;
    ///     the initial responder independently enforces the receipt-relative three-second deadline.
    ///   - continuations: Factory for optional REST continuation mechanics; its initial closure is replaced
    ///     by inline HTTP. Nil supports immediate replies only and starts no REST work.
    ///   - handler: Cooperative handler with the same context used by command/Gateway routing.
    /// - Throws: Handler, cancellation, deadline or response transport failures. Closing the response
    ///   slot does not undo an acknowledgement already sent; no mutation is automatically replayed.
    public func handle<C: Clock>(_ exchange: HTTPExchange, context: TransportContext<C>,
        continuations: (@Sendable (Interaction) -> InteractionResponseSink)? = nil,
        handler: @escaping @Sendable (InteractionContext) async throws -> Void) async throws
        where C.Duration == Duration {
        DiscordLog.makeLogger("interactions.http").debug("Interaction HTTP application exchange started", metadata: ["dk.event": "interactions.http.started"])
        let clock = InteractionClock(context.clock)
        let slot = InlineInteractionResponseSlot(responder: exchange.responder)
        let failure = InteractionHandlerFailure()
        do {
            let result = try await ingress.process(request: exchange.request, context: context) { verified in
                let interaction: Interaction
                do { interaction = try Interaction(data: verified.rawBody, limits: limits) }
                catch {
                    DiscordLog.makeLogger("interactions.http").debug("Authenticated interaction envelope is malformed", metadata: ["dk.event": "interactions.http.decode_rejected", "dk.status": "400"])
                    return HTTPResponse(status: 400)
                }
                DiscordLog.makeLogger("interactions.http").trace("Authenticated interaction envelope decoded", metadata: ["dk.event": "interactions.http.decoded"])
                guard interaction.applicationID == applicationID else {
                    DiscordLog.makeLogger("interactions.http").debug("Authenticated interaction has another application owner", metadata: ["dk.event": "interactions.http.application_rejected", "dk.status": "403"])
                    return HTTPResponse(status: 403)
                }
                let rest = continuations?(interaction)
                let sink = InteractionResponseSink(initial: { response, remaining in
                    let bytes = try response.jsonValue(interactionType: interaction.type.knownValue).serialized()
                    let deadline = context.clock.now.advanced(by: remaining)
                    let bounded = TransportContext(clock: context.clock, deadline: context.deadline.map { min($0, deadline) } ?? deadline)
                    try await slot.send(try Self.response(bytes), context: bounded)
                }, editOriginal: rest?.edit, followup: rest?.followup, deleteOriginal: rest?.delete)
                let responder = InteractionResponder(interaction: interaction, deliveryMode: .http,
                    clock: clock, sink: sink, admission: admission, receivedAt: .zero)
                let normalized = try InteractionContext(interaction: interaction, deliveryMode: .http, responder: responder)
                DiscordLog.makeLogger("interactions.http").trace("HTTP interaction response owner and context normalized", metadata: ["dk.event": "interactions.http.normalized"])
                if interaction.type.knownValue == .ping {
                    DiscordLog.makeLogger("interactions.http").trace("Handling authenticated protocol ping", metadata: ["dk.event": "interactions.http.ping"])
                    do { try await responder.respond(.pong) }
                    catch { await failure.store(error) }
                } else {
                    do {
                        DiscordLog.makeLogger("interactions.http").trace("Entering normalized interaction handler", metadata: ["dk.event": "interactions.http.handler_entered"])
                        defer { DiscordLog.makeLogger("interactions.http").trace("Normalized interaction handler exited", metadata: ["dk.event": "interactions.http.handler_exited"]) }
                        if let autoDefer, Self.canDefer(interaction, policy: autoDefer) {
                            try await responder.runWithAutoDefer(policy: autoDefer) { try await handler(normalized) }
                        } else { try await handler(normalized) }
                    } catch { await failure.store(error) }
                }
                return HTTPResponse(status: 500)
            }
            if !(await slot.wasReserved()) { try await slot.send(result, context: context) }
            else { await result.body?.close() }
            if let error = await failure.read() { throw error }
            DiscordLog.makeLogger("interactions.http").debug("Interaction HTTP application exchange completed", metadata: ["dk.event": "interactions.http.completed"])
        } catch {
            await exchange.request.body?.close()
            await exchange.responder.close()
            DiscordLog.makeLogger("interactions.http").trace("Failed interaction HTTP exchange closed", metadata: ["dk.event": "interactions.http.cleanup_completed"])
            throw error
        }
    }

    /// Restricts automatic acknowledgement to legal message/update triggers before starting a timer.
    /// - Parameters:
    ///   - interaction: Authenticated typed input, including possible future kinds.
    ///   - policy: Explicit defer visibility/mechanics.
    /// - Returns: True for known compatible triggers; false for PING, autocomplete and unknown input.
    private static func canDefer(_ interaction: Interaction, policy: InteractionAutoDeferPolicy) -> Bool {
        switch interaction.type.knownValue {
        case .applicationCommand: return policy.mode != .update
        case .messageComponent, .modalSubmit:
            if policy.mode == .update { if case .value = interaction.message { return true }; return false }
            return true
        default: return false
        }
    }

    /// Materializes one finite JSON response as a single-use transport body.
    /// - Parameter bytes: Validated callback JSON within the model's limits.
    /// - Returns: HTTP 200 with application/json and a body owned by the response slot.
    /// - Throws: Body stream construction errors if its byte bound cannot be represented.
    private static func response(_ bytes: Data) throws -> HTTPResponse {
        let source = InlineInteractionBody(bytes)
        return HTTPResponse(status: 200, headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: try BodyStream(maximumChunkBytes: max(1, bytes.count), next: { await source.next() }, close: { await source.close() }))
    }
}

/// Reserves the inline response before I/O so transport errors never trigger a second HTTP attempt.
private actor InlineInteractionResponseSlot {
    private let responder: any HTTPResponder
    private var reserved = false

    /// Retains the caller-transferred response slot without starting transmission.
    /// - Parameter responder: Exactly-once adapter response owner.
    init(responder: any HTTPResponder) { self.responder = responder }
    /// Reports whether an inline response attempt already consumed the slot.
    /// - Returns: True even when the attempted transmission failed ambiguously.
    func wasReserved() -> Bool { reserved }
    /// Reserves and sends once, closing bodies passed by duplicate callers.
    /// - Parameters:
    ///   - response: Owned response body and metadata.
    ///   - context: Initial-response or fallback transmission deadline.
    /// - Throws: Duplicate, cancellation, deadline or adapter error; reservation remains consumed.
    func send<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws where C.Duration == Duration {
        guard !reserved else { await response.body?.close(); throw InteractionLifecycleError.alreadyAcknowledged }
        reserved = true
        DiscordLog.makeLogger("interactions.http").trace("Inline HTTP response slot reserved", metadata: ["dk.event": "interactions.http.response_reserved", "dk.status": .stringConvertible(response.status)])
        try await responder.respond(response, context: context)
        DiscordLog.makeLogger("interactions.http").trace("Inline HTTP response transmission completed", metadata: ["dk.event": "interactions.http.response_sent"])
    }
}

/// Retains a handler's original failure across the ingress adapter's sanitized HTTP mapping.
private actor InteractionHandlerFailure {
    private var error: (any Error)?
    /// Stores the handler error without logging or including it in HTTP response text.
    /// - Parameter error: Original failure, possibly cancellation.
    func store(_ error: any Error) { self.error = error }
    /// Retrieves the original handler failure after the response path has relinquished resources.
    /// - Returns: The failure, or nil when the handler succeeded.
    func read() -> (any Error)? { error }
}

/// Single-chunk source with explicit body cleanup and no queue.
private actor InlineInteractionBody {
    private var bytes: Data?
    /// Takes ownership of finite validated callback bytes.
    /// - Parameter bytes: Original response data, including an empty body if explicitly supplied.
    init(_ bytes: Data) { self.bytes = bytes }
    /// Transfers the chunk once and then yields EOF.
    /// - Returns: Original data on the first pull, otherwise nil.
    func next() -> Data? { defer { bytes = nil }; return bytes }
    /// Discards an unread chunk; repeated closure is harmless.
    func close() { bytes = nil }
}
