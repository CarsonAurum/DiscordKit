// File: Sources/DiscordNIOTransport/TLSPolicy.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import NIOCore
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOSSL
import DiscordTransport

/// Redacted adapter failures. Native errors may contain URLs, headers or paths and
/// are intentionally not retained. This layer never retries an uncertain send.
public enum NIOAdapterFailure: Error, Equatable, Sendable {
    case invalidRequest
    case capacityExceeded
    case requestTooLarge
    case responseTooLarge
    case invalidResponse
    case connectionFailed
    case upgradeRejected
    case invalidFrame
    case messageTooLarge
}

/// Full certificate-chain and hostname verification, with optional explicit roots.
/// There is deliberately no insecure verification mode or client-certificate API.
public struct TLSPolicy: Sendable {
    let context: NIOSSLContext

    /// Prepares the TLS context once, before opening sockets.
    /// - Parameter additionalTrustRootsPEM: Optional PEM trust-anchor bytes. When
    ///   supplied these replace system roots, for private PKI/local tests; `nil`
    ///   selects NIOSSL's platform default roots. Never pass an untrusted peer's
    ///   certificate here merely to suppress a verification failure.
    /// - Throws: `NIOAdapterFailure.connectionFailed` for malformed certificates or
    ///   unavailable TLS configuration. No certificate text is included in errors.
    public init(additionalTrustRootsPEM: [UInt8]? = nil) throws {
        do {
            var configuration = TLSConfiguration.makeClientConfiguration()
            configuration.certificateVerification = .fullVerification
            configuration.minimumTLSVersion = .tlsv12
            if let additionalTrustRootsPEM {
                configuration.trustRoots = .certificates(try NIOSSLCertificate.fromPEMBytes(additionalTrustRootsPEM))
            }
            context = try NIOSSLContext(configuration: configuration)
        } catch { throw NIOAdapterFailure.connectionFailed }
    }
}

/// Shared wire validation; authentication and Discord endpoint policy stay above
/// transport. Requests use origin-form targets and adapter-owned framing headers.
struct NIORequestTarget: Sendable, Hashable {
    let host: String
    let port: Int
    let secure: Bool
    let path: String
    let hostHeader: String

    /// Validates a destination without resolving DNS or exposing it in failures.
    /// - Parameters:
    ///   - request: Request with a valid method, URL and ordered wire headers.
    ///   - webSocket: Whether to require ws/wss instead of http/https schemes.
    ///   - headerLimit: Maximum UTF-8 bytes across names and values, including Host.
    /// - Throws: `invalidRequest` for credentials/fragments, invalid ports, wire
    ///   syntax, excessive headers or caller-owned framing/upgrade fields.
    init(_ request: HTTPRequest, webSocket: Bool = false, headerLimit: Int) throws {
        guard let parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty,
              host.utf8.allSatisfy({ $0 > 32 && $0 != 127 }),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              (webSocket ? ["ws", "wss"] : ["http", "https"]).contains(scheme),
              Self.isToken(request.method), !webSocket || request.method == "GET",
              !webSocket || request.body == nil else { throw NIOAdapterFailure.invalidRequest }
        let secure = scheme == "https" || scheme == "wss"
        let port = parts.port ?? (secure ? 443 : 80)
        guard (1...65535).contains(port) else { throw NIOAdapterFailure.invalidRequest }
        self.host = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host
        self.port = port
        self.secure = secure
        let literal = self.host.contains(":") ? "[\(self.host)]" : self.host
        self.hostHeader = port == (secure ? 443 : 80) ? literal : "\(literal):\(port)"
        path = (parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath)
            + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
        var size = hostHeader.utf8.count + 4
        let reserved = ["host", "content-length", "transfer-encoding", "connection", "upgrade", "expect", "trailer", "te"]
        for header in request.headers {
            guard Self.isToken(header.name),
                  header.value.utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) }),
                  !reserved.contains(header.name.lowercased()),
                  !webSocket || !header.name.lowercased().hasPrefix("sec-websocket-") else {
                throw NIOAdapterFailure.invalidRequest
            }
            guard header.name.utf8.count <= headerLimit - min(size, headerLimit) else {
                throw NIOAdapterFailure.invalidRequest
            }
            size += header.name.utf8.count
            guard header.value.utf8.count <= headerLimit - min(size, headerLimit) else {
                throw NIOAdapterFailure.invalidRequest
            }
            size += header.value.utf8.count
        }
        guard size <= headerLimit, path.utf8.count <= headerLimit else { throw NIOAdapterFailure.invalidRequest }
    }

    /// Recognizes RFC HTTP token bytes using ASCII only.
    /// - Parameter value: Nonempty method or header field name to validate.
    /// - Returns: Whether every byte is a permitted token character.
    static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || Array("!#$%&'*+-.^_`|~".utf8).contains($0)
        }
    }
}

/// A cancellation latch installed before TCP connect completes. All state is
/// synchronized; a channel arriving after cancellation is closed immediately.
final class NIOConnectionAttempt: Sendable {
    private struct State: Sendable { var channel: (any Channel)?; var cancelled = false }
    private let state = NIOLockedValueBox(State())

    /// Registers a socket before connection/handshake work can suspend.
    /// - Parameter channel: Operation-owned channel; cancellation retains no payloads.
    func install(_ channel: any Channel) {
        state.withLockedValue { state in
            state.channel = channel
            if state.cancelled { channel.eventLoop.execute { channel.close(promise: nil) } }
        }
    }

    /// Terminates pending connect/read/write without blocking the calling executor.
    /// Only the first call schedules socket closure; later calls remain safe after
    /// the owning event loop stops. Closure is queued while holding the latch,
    /// preventing cleanup from overtaking a preempted cancellation submission.
    /// A future install observes the terminal state.
    func cancel() {
        state.withLockedValue { state in
            guard !state.cancelled else { return }
            state.cancelled = true
            if let channel = state.channel {
                channel.eventLoop.execute { channel.close(promise: nil) }
            }
        }
    }
}
