/// One accepted request and its exactly-once response reservation.
public struct HTTPExchange: Sendable {
    public let request: HTTPRequest
    public let responder: any HTTPResponder

    /// Transfers accepted request ownership without starting handler work.
    /// - Parameters:
    ///   - request: Incoming request; handler consumes or closes its bounded body.
    ///   - responder: Response owner; reserve before suspension and reject second responses.
    public init(request: HTTPRequest, responder: any HTTPResponder) {
        self.request = request; self.responder = responder
    }
}

/// A response slot for one inbound exchange; closing abandons the exchange.
public protocol HTTPResponder: TransportResource {
    /// Reserves and sends exactly one response, even under reentrant concurrent calls.
    /// - Parameters:
    ///   - response: Outgoing metadata/body; ownership transfers to the responder.
    ///   - context: Clock and deadline for transmitting the response.
    /// - Throws: Duplicate/closed response, cancellation, deadline, validation or I/O error.
    ///   Failure closes the supplied body; it does not reopen the response slot.
    func respond<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws
        where C.Duration == Duration
}

/// An injected HTTP listener with pull acceptance and an adapter-configured bounded backlog.
public protocol HTTPIngress: TransportResource {
    /// Accepts one request without running application handlers on the accept loop.
    /// - Parameter context: Clock/deadline for the single active acceptance operation.
    /// - Returns: Exchange owned by the caller, or `nil` after orderly listener shutdown.
    /// - Throws: Concurrent accept, cancellation, expiration, overflow or listener errors.
    ///   Closing the listener unblocks acceptance and rejects new requests; accepted
    ///   exchanges remain caller-owned and must be responded to or closed separately.
    func accept<C: Clock>(context: TransportContext<C>) async throws -> HTTPExchange?
        where C.Duration == Duration
}
