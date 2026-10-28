// File: Sources/DiscordActivities/ActivityTransport.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation

/// Sanitized Activity lifecycle failures. Host error text, credentials and payloads are never diagnostic data.
public enum ActivityFailure: Error, Sendable, Equatable {
    case invalidConfiguration, invalidHostParameters, invalidFrame, notReady, closed, overloaded
    case commandMismatch, remoteError, subscriptionTransition
}

/// Numeric host command rejection. Host-supplied messages and unknown error fields are deliberately discarded.
/// This code permits the documented orientation compatibility fallback without disclosing OAuth/profile data.
public struct ActivityCommandFailure: Error, Sendable, Equatable {
    public let code: Int
}

/// One exclusively owned browser-host messaging connection. This is not a remote Gateway or desktop RPC socket.
/// Adapters MUST authenticate the exact sending Window/native host identity AND an explicitly allowed origin
/// before returning a frame. The owned JavaScript bridge implements this boundary for browser postMessage.
/// Native WebKit/browser bindings inject equivalent message delivery; a web view alone is not a Discord host.
/// Implementations serialize sends in call order, bound retained input and make close unblock every suspended call.
public protocol ActivityTransport: TransportResource {
    /// Sends one complete JSON-encoded `[opcode, payload]` tuple to the explicitly trusted host.
    /// - Parameter data: Bounded UTF-8 JSON; send once, with no retries after ambiguous delivery.
    /// - Throws: Cancellation or sanitized adapter failure; implementations must cooperate with cancellation.
    func send(_ data: Data) async throws

    /// Receives one authenticated complete tuple with exactly one active consumer.
    /// - Returns: Bounded frame bytes, or nil after host shutdown. No unauthenticated message may be returned.
    /// - Throws: Cancellation or sanitized adapter failure. Closing must unblock this suspension.
    func receive() async throws -> Data?
}

/// Discord-injected Activity identity, parsed independently from trust in the message sender.
/// Query parameters identify context, never grant OAuth scopes or create a Discord host outside Discord.
public struct ActivityHostParameters: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let frameID: String
    public let instanceID: String
    public let platform: String
    public let channelID: String?
    public let guildID: String?
    public let customID: String?
    public let referrerID: String?
    public let locationID: String?
    public let mobileAppVersion: String?

    /// Parses required host parameters and optional context with bounded storage and no I/O.
    /// - Parameter url: Activity iframe URL; at most 16 KiB. Required frame_id/instance_id are nonempty,
    ///   and platform is desktop or mobile. Duplicate recognized keys are rejected to avoid parser ambiguity.
    /// - Throws: `ActivityFailure.invalidHostParameters` for malformed/missing/oversized parameters.
    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= 16_384,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw ActivityFailure.invalidHostParameters
        }
        let recognized: Set<String> = ["frame_id", "instance_id", "platform", "channel_id", "guild_id", "custom_id", "referrer_id", "location_id", "mobile_app_version"]
        var fields: [String: String] = [:]
        for item in items where recognized.contains(item.name) {
            guard fields[item.name] == nil, let value = item.value, value.utf8.count <= 4_096,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw ActivityFailure.invalidHostParameters
            }
            fields[item.name] = value
        }
        guard let frame = fields["frame_id"], !frame.isEmpty, let instance = fields["instance_id"], !instance.isEmpty,
              let platform = fields["platform"], ["desktop", "mobile"].contains(platform) else {
            throw ActivityFailure.invalidHostParameters
        }
        frameID = frame; instanceID = instance; self.platform = platform
        channelID = fields["channel_id"]; guildID = fields["guild_id"]; customID = fields["custom_id"]
        referrerID = fields["referrer_id"]; locationID = fields["location_id"]; mobileAppVersion = fields["mobile_app_version"]
    }

    /// Conceals contextual user/channel identifiers during ordinary diagnostics.
    public var description: String { "ActivityHostParameters(redacted)" }
    /// Conceals contextual identifiers in debugger descriptions.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from expanding host context.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Explicit finite session budgets. Adapters must independently bound their own browser/native buffers.
public struct ActivityClientLimits: Sendable {
    public let maximumFrameBytes: Int
    public let maximumPending: Int
    public let maximumPendingBytes: Int
    public let maximumEvents: Int
    public let maximumEventBytes: Int
    public let maximumSubscriptions: Int

    /// Validates positive session capacities; construction never starts a timer, task or browser operation.
    /// - Parameters:
    ///   - maximumFrameBytes: Complete tuple cap, default 1 MiB, at most 16 MiB.
    ///   - maximumPending: Concurrent command/waiter cap, default 128, at most 65,536.
    ///   - maximumPendingBytes: Retained outgoing tuples, default 4 MiB.
    ///   - maximumEvents: Undrained ordered events, default 256.
    ///   - maximumEventBytes: Retained event tuple bytes, default 4 MiB.
    ///   - maximumSubscriptions: Local subscription tokens including duplicates, default 256.
    /// - Throws: `ActivityFailure.invalidConfiguration` for nonpositive or excessive capacities.
    public init(maximumFrameBytes: Int = 1_048_576, maximumPending: Int = 128,
                maximumPendingBytes: Int = 4_194_304, maximumEvents: Int = 256,
                maximumEventBytes: Int = 4_194_304, maximumSubscriptions: Int = 256) throws {
        guard (1...16_777_216).contains(maximumFrameBytes), (1...65_536).contains(maximumPending),
              (1...268_435_456).contains(maximumPendingBytes), (1...65_536).contains(maximumEvents),
              (1...268_435_456).contains(maximumEventBytes), (1...65_536).contains(maximumSubscriptions) else {
            throw ActivityFailure.invalidConfiguration
        }
        self.maximumFrameBytes = maximumFrameBytes; self.maximumPending = maximumPending
        self.maximumPendingBytes = maximumPendingBytes; self.maximumEvents = maximumEvents
        self.maximumEventBytes = maximumEventBytes; self.maximumSubscriptions = maximumSubscriptions
    }
}

/// Session-scoped local subscription ownership. Pass only to its creating client's unsubscribe method.
public struct ActivitySubscription: Sendable, Hashable {
    let owner: UUID
    let id: UUID
    let key: String
}

/// Ordered authenticated event data, including future dispatch names and unknown fields.
public struct ActivityClientEvent: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let name: ActivityEventName
    public let data: JSONValue
    /// Conceals payloads, including profile, purchase and error information.
    public var description: String { "ActivityClientEvent(redacted)" }
    /// Uses identical redaction in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing event data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
