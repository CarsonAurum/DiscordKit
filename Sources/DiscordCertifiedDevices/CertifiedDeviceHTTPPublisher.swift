import DiscordCore
import DiscordTransport
import Foundation

/// Explicit loopback-only HTTP state publication with one in-flight full replacement.
///
/// Construction performs no I/O. The caller selects and pins a port; this publisher
/// never scans desktop services, retries an ambiguous mutation, observes hardware,
/// follows a remote endpoint, or owns the injected transport's shared connection pool.
public actor CertifiedDeviceHTTPPublisher: TransportResource {
    /// Certified Devices documents eleven ports; generic RPC documents ten.
    /// The difference remains unresolved rather than silently changing this range.
    public static let documentedPorts = 6463...6473
    private let url: URL
    private let transport: any HTTPTransport
    private let maximumDevices: Int
    private let maximumRequestBytes: Int
    private let maximumResponseBytes: Int
    private var operation: Task<Void, any Error>?
    private var closed = false

    /// Configures a fixed v1 HTTP endpoint without connecting or discovering peers.
    /// - Parameters:
    ///   - clientID: Nonzero decimal application ID within UInt64, at most 20 bytes.
    ///   - port: Explicit port in `6463...6473`; no arbitrary host can be supplied.
    ///   - transport: Caller-owned injectable transport. It must honor cancellation,
    ///     avoid redirects, and not replay requests or forward loopback traffic through proxies.
    ///   - maximumDevices: Local complete-array bound in `1...1_024`, default 128.
    ///   - maximumRequestBytes: Local serialized request limit in `1...1_048_576`, default 262,144.
    ///   - maximumResponseBytes: Local collected response limit in `1...1_048_576`, default 65,536.
    /// - Throws: `CertifiedDeviceFailure.invalidClientID`, `.invalidPort` or
    ///   `.invalidLimits`. Limits are local policy, not documented Discord quotas.
    public init(clientID: String, port: Int, transport: any HTTPTransport,
                maximumDevices: Int = 128, maximumRequestBytes: Int = 262_144,
                maximumResponseBytes: Int = 65_536) throws {
        guard !clientID.isEmpty, clientID.utf8.count <= 20,
              clientID.utf8.allSatisfy({ (48...57).contains($0) }),
              let numericID = UInt64(clientID), numericID > 0 else {
            throw CertifiedDeviceFailure.invalidClientID
        }
        guard Self.documentedPorts.contains(port) else { throw CertifiedDeviceFailure.invalidPort }
        guard (1...1_024).contains(maximumDevices), (1...1_048_576).contains(maximumRequestBytes),
              (1...1_048_576).contains(maximumResponseBytes) else { throw CertifiedDeviceFailure.invalidLimits }
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = "127.0.0.1"
        parts.port = port
        parts.path = "/rpc"
        parts.queryItems = [URLQueryItem(name: "v", value: "1"),
                            URLQueryItem(name: "client_id", value: clientID)]
        guard let url = parts.url else { throw CertifiedDeviceFailure.invalidClientID }
        self.url = url
        self.transport = transport
        self.maximumDevices = maximumDevices
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumResponseBytes = maximumResponseBytes
    }

    /// Publishes a complete device array once, preserving highest-priority-first order.
    ///
    /// An empty array clears the published list. Removed devices are not merged back
    /// into later calls. Call on every relevant host-observed device/processing change.
    /// Overlapping calls fail immediately, so no unbounded waiter queue or stale state
    /// accumulates. An error after transmission is indeterminate; obtain fresh host
    /// state before explicitly publishing again rather than automatically replaying.
    /// - Parameters:
    ///   - devices: Entire current list; `(type,id)` pairs must be unique. Different
    ///     types may share a native ID. Ordering controls Discord's device preference.
    ///   - nonce: Fresh nonblank control-free reply correlation string of at most
    ///     128 UTF-8 bytes. Defaults to a new UUID; caller-provided values must be unique.
    ///   - context: Injected clock, cooperative cancellation and optional deadline
    ///     covering execution and response consumption.
    /// - Throws: Validation/capacity errors before I/O; `.closed` or `.operationInProgress`;
    ///   `.httpStatus`, `.remoteError` or `.invalidResponse`; bounded JSON errors;
    ///   sanitized `.transportFailure`, cancellation or expiration. All owned bodies close
    ///   before completion. Remote error text is discarded, and authentication/approval
    ///   errors are returned to the caller without broadening access or attempting OAuth.
    public func publish<C: Clock>(_ devices: [CertifiedDevice], nonce: String = UUID().uuidString,
                                  context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw CertifiedDeviceFailure.closed }
        guard operation == nil else { throw CertifiedDeviceFailure.operationInProgress }
        let arguments = try certifiedDeviceArguments(devices, maximumDevices: maximumDevices)
        guard !nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              nonce.utf8.count <= 128,
              !nonce.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CertifiedDeviceFailure.invalidNonce
        }
        let bytes = try JSONValue.object([
            "cmd": .string("SET_CERTIFIED_DEVICES"), "nonce": .string(nonce), "args": .object(arguments),
        ]).serialized(limits: JSONLimits(maximumBytes: maximumRequestBytes))
        let transport = self.transport
        let url = self.url
        let maximumResponseBytes = self.maximumResponseBytes
        let task = Task {
            try await executeCertifiedDevicePublication(bytes: bytes, url: url, nonce: nonce,
                transport: transport, maximumResponseBytes: maximumResponseBytes, context: context)
        }
        operation = task
        defer { operation = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Prevents new publication, cancels pending work and awaits owned body cleanup.
    /// Repeated concurrent calls await the same operation; the shared transport stays
    /// caller-owned. Closing does not publish an empty array or mutate desktop state.
    public func close() async {
        closed = true
        let pending = operation
        pending?.cancel()
        _ = await pending?.result
    }
}

/// Validates complete-array size and identity uniqueness for either publication transport.
/// - Parameters:
///   - devices: Highest-priority-first complete current device list, including empty.
///   - maximumDevices: Inclusive host resource bound; caller validates positivity.
/// - Returns: The command argument object containing exactly one ordered `devices` array.
/// - Throws: `CertifiedDeviceFailure.tooManyDevices` or `.duplicateDevice` before I/O.
func certifiedDeviceArguments(_ devices: [CertifiedDevice], maximumDevices: Int) throws -> [String: JSONValue] {
    guard devices.count <= maximumDevices else { throw CertifiedDeviceFailure.tooManyDevices }
    var identifiers: [CertifiedDeviceType: Set<String>] = [:]
    for device in devices {
        guard identifiers[device.type, default: []].insert(device.id).inserted else {
            throw CertifiedDeviceFailure.duplicateDevice
        }
    }
    return ["devices": .array(devices.map(\.jsonValue))]
}

/// Executes a single POST and validates its bounded correlated acknowledgement.
/// - Parameters:
///   - bytes: Validated complete command bytes, including native device identifiers.
///   - url: Fixed loopback v1 endpoint constructed by the publisher.
///   - nonce: Expected response nonce; never logged or stored in failures.
///   - transport: Borrowed transport; operation owns its request and response bodies.
///   - maximumResponseBytes: Positive aggregate body limit.
///   - context: Clock/cancellation/deadline shared by execution and body consumption.
/// - Throws: Transport, deadline, cancellation, HTTP, JSON, response-size or envelope
///   failures. No failure is replayed and all transferred bodies are closed.
private func executeCertifiedDevicePublication<C: Clock>(bytes: Data, url: URL, nonce: String,
    transport: any HTTPTransport, maximumResponseBytes: Int, context: TransportContext<C>) async throws
    where C.Duration == Duration {
    let source = CertifiedDeviceRequestBody(bytes)
    let requestBody = try BodyStream(maximumChunkBytes: max(1, bytes.count),
        next: { await source.take() }, close: { await source.discard() })
    do {
        try await context.run {
            let response = try await transport.execute(HTTPRequest(method: "POST", url: url,
                headers: [HTTPHeader(name: "Content-Type", value: "application/json")], body: requestBody),
                context: context)
            do {
                guard response.status == 200 else { throw CertifiedDeviceFailure.httpStatus(response.status) }
                guard let body = response.body else { throw CertifiedDeviceFailure.invalidResponse }
                var bytes = Data()
                for try await chunk in body {
                    try context.check()
                    guard chunk.count <= maximumResponseBytes - bytes.count else {
                        throw CertifiedDeviceFailure.responseTooLarge
                    }
                    bytes.append(chunk)
                }
                try context.check()
                let value = try JSONValue.parse(bytes, limits: JSONLimits(maximumBytes: maximumResponseBytes))
                guard case .object(let object) = value,
                      object["cmd"] == .string("SET_CERTIFIED_DEVICES"), object["nonce"] == .string(nonce) else {
                    throw CertifiedDeviceFailure.invalidResponse
                }
                if object["evt"] == .string("ERROR") {
                    var code: Int?
                    if case .object(let data) = object["data"], case .number(let number) = data["code"] {
                        code = Int(number.rawValue)
                    }
                    throw CertifiedDeviceFailure.remoteError(code: code)
                }
                guard object["evt"] == .null, object["data"] == .null else {
                    throw CertifiedDeviceFailure.invalidResponse
                }
                await response.body?.close()
            } catch {
                await response.body?.close()
                throw error
            }
        }
        await requestBody.close()
    } catch {
        await requestBody.close()
        if error is CancellationError { throw CancellationError() }
        if let failure = error as? CertifiedDeviceFailure { throw failure }
        if let failure = error as? TransportFailure { throw failure }
        if let failure = error as? JSONValueError { throw failure }
        throw CertifiedDeviceFailure.transportFailure
    }
}

/// A single retained immutable request chunk, released on first pull or explicit close.
private actor CertifiedDeviceRequestBody {
    private var bytes: Data?

    /// Retains one bounded serialized request without starting I/O.
    /// - Parameter bytes: Complete request bytes owned by this source until consumed.
    init(_ bytes: Data) { self.bytes = bytes }

    /// Transfers the sole chunk and then returns EOF on every later call.
    /// - Returns: Retained bytes once, or nil after consumption/closure.
    func take() -> Data? { defer { bytes = nil }; return bytes }

    /// Discards unconsumed bytes; repeated calls are harmless.
    func discard() { bytes = nil }
}
