// File: Sources/DiscordCertifiedDevices/CertifiedDevice.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Validation and publication failures that never retain native device identifiers or response text.
public enum CertifiedDeviceFailure: Error, Sendable, Equatable {
    case invalidText
    case invalidURL
    case audioProcessingRequiresAudioInput
    case tooManyRelatedDevices
    case duplicateRelatedDevice
    case invalidClientID
    case invalidPort
    case invalidLimits
    case tooManyDevices
    case duplicateDevice
    case invalidNonce
    case operationInProgress
    case closed
    case responseTooLarge
    case invalidResponse
    case transportFailure
    case httpStatus(Int)
    case remoteError(code: Int?)
}

/// The three device types documented by the Certified Devices v1 protocol.
public enum CertifiedDeviceType: String, Sendable, Hashable, CaseIterable {
    case audioInput = "audioinput"
    case audioOutput = "audiooutput"
    case videoInput = "videoinput"
}

/// A hardware vendor or model name and public product URL; diagnostics redact both.
public struct CertifiedDeviceProduct: Sendable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public let name: String
    public let url: URL

    /// Validates immutable vendor/model metadata without contacting its URL.
    /// - Parameters:
    ///   - name: Nonblank, control-free name of at most 256 UTF-8 bytes.
    ///   - url: Absolute HTTP(S) URL, at most 2,048 UTF-8 bytes, with a host and no
    ///     user information or fragment. These are local safety bounds, not Discord limits.
    /// - Throws: `CertifiedDeviceFailure.invalidText` or `.invalidURL`. URLs are
    ///   descriptive metadata only and are never fetched by this product.
    public init(name: String, url: URL) throws {
        try validateCertifiedText(name, maximumBytes: 256)
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, url.absoluteString.utf8.count <= 2_048 else {
            throw CertifiedDeviceFailure.invalidURL
        }
        self.name = name
        self.url = url
    }

    /// Returns a fixed diagnostic that excludes vendor names and URLs.
    public var description: String { "CertifiedDeviceProduct(redacted)" }

    /// Returns the same redacted diagnostic for debug formatting.
    public var debugDescription: String { description }

    /// Prevents reflection from exposing vendor metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Creates descriptive wire metadata without performing network I/O.
    /// - Returns: The documented `name` and `url` object; callers must redact it.
    var jsonValue: JSONValue { .object(["name": .string(name), "url": .string(url.absoluteString)]) }
}

/// Optional current native processing states for an audio input device.
///
/// A missing flag is omitted on the wire; false explicitly reports disabled. These
/// fields report hardware state and do not request a Discord voice-settings mutation.
public struct CertifiedDeviceAudioProcessing: Sendable, Hashable {
    public let echoCancellation: Bool?
    public let noiseSuppression: Bool?
    public let automaticGainControl: Bool?
    public let hardwareMute: Bool?

    /// Stores optional native audio-input state without starting observation.
    /// - Parameters:
    ///   - echoCancellation: Whether native echo cancellation is enabled, or nil when unreported.
    ///   - noiseSuppression: Whether native noise suppression is enabled, or nil when unreported.
    ///   - automaticGainControl: Whether native gain control is enabled, or nil when unreported.
    ///   - hardwareMute: Whether the hardware mute is engaged, or nil when unreported.
    public init(echoCancellation: Bool? = nil, noiseSuppression: Bool? = nil,
                automaticGainControl: Bool? = nil, hardwareMute: Bool? = nil) {
        self.echoCancellation = echoCancellation
        self.noiseSuppression = noiseSuppression
        self.automaticGainControl = automaticGainControl
        self.hardwareMute = hardwareMute
    }
}

/// One identified device in a complete priority-ordered Certified Devices replacement.
///
/// The host supplies the native Windows device UUID or macOS device name. This
/// product does not enumerate hardware, synthesize identifiers, or claim certification.
/// See https://docs.discord.com/developers/topics/certified-devices, verified 2026-10-17.
public struct CertifiedDevice: Sendable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public let type: CertifiedDeviceType
    public let id: String
    public let vendor: CertifiedDeviceProduct
    public let model: CertifiedDeviceProduct
    public let related: [String]
    public let audioProcessing: CertifiedDeviceAudioProcessing?

    /// Validates one immutable device while preserving related-device order.
    /// - Parameters:
    ///   - type: Documented audio-input, audio-output or video-input wire type.
    ///   - id: Native Windows UUID/macOS name, nonblank and control-free, at most
    ///     1,024 UTF-8 bytes. Platform syntax is deliberately not guessed.
    ///   - vendor: Validated hardware vendor metadata.
    ///   - model: Validated hardware model metadata.
    ///   - related: At most 64 unique native identifiers with the same text bounds
    ///     as `id`; defaults to empty. Self-reference is permitted by Discord's example.
    ///   - audioProcessing: Optional native input processing state; requires audio input.
    /// - Throws: `CertifiedDeviceFailure` for invalid identifiers, repeated related
    ///   IDs, excessive related count, or audio-only metadata on another device type.
    ///   Count/text bounds are local resource policy rather than published Discord limits.
    public init(type: CertifiedDeviceType, id: String, vendor: CertifiedDeviceProduct,
                model: CertifiedDeviceProduct, related: [String] = [],
                audioProcessing: CertifiedDeviceAudioProcessing? = nil) throws {
        try validateCertifiedText(id, maximumBytes: 1_024)
        guard related.count <= 64 else { throw CertifiedDeviceFailure.tooManyRelatedDevices }
        for value in related { try validateCertifiedText(value, maximumBytes: 1_024) }
        guard Set(related).count == related.count else { throw CertifiedDeviceFailure.duplicateRelatedDevice }
        guard type == .audioInput || audioProcessing == nil else {
            throw CertifiedDeviceFailure.audioProcessingRequiresAudioInput
        }
        self.type = type
        self.id = id
        self.vendor = vendor
        self.model = model
        self.related = related
        self.audioProcessing = audioProcessing
    }

    /// Returns a fixed diagnostic without native IDs, names, relationships or URLs.
    public var description: String { "CertifiedDevice(redacted)" }

    /// Uses redacted formatting in debug output.
    public var debugDescription: String { description }

    /// Prevents reflection-based diagnostics from traversing native device metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Projects a validated device into the documented wire object.
    /// - Returns: All required fields plus reported audio-input flags. Unknown
    ///   hardware capabilities remain absent; the returned JSON contains native IDs.
    public var jsonValue: JSONValue {
        var fields: [String: JSONValue] = [
            "type": .string(type.rawValue), "id": .string(id),
            "vendor": vendor.jsonValue, "model": model.jsonValue,
            "related": .array(related.map { .string($0) }),
        ]
        if let value = audioProcessing?.echoCancellation { fields["echo_cancellation"] = .bool(value) }
        if let value = audioProcessing?.noiseSuppression { fields["noise_suppression"] = .bool(value) }
        if let value = audioProcessing?.automaticGainControl { fields["automatic_gain_control"] = .bool(value) }
        if let value = audioProcessing?.hardwareMute { fields["hardware_mute"] = .bool(value) }
        return .object(fields)
    }
}

/// Rejects oversized, blank or control-bearing native metadata before serialization.
/// - Parameters:
///   - text: Identifier or descriptive name supplied by the host.
///   - maximumBytes: Inclusive UTF-8 byte bound selected by the surrounding model.
/// - Throws: `CertifiedDeviceFailure.invalidText`; failure never stores input text.
private func validateCertifiedText(_ text: String, maximumBytes: Int) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.utf8.count <= maximumBytes,
          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw CertifiedDeviceFailure.invalidText
    }
}
