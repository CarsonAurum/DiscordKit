// File: Tests/DiscordCertifiedDevicesTests/CertifiedDeviceTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCertifiedDevices
import DiscordCore
import Foundation
import Testing

/// Validated native metadata, optional input processing and redacted diagnostics.
@Suite("Certified device models")
struct CertifiedDeviceTests {
    /// Preserves device identifiers, metadata, related order and every optional flag.
    /// Unknown input processing remains absent while explicit false is encoded.
    @Test func wireProjection() throws {
        let product = try certifiedProduct()
        let processing = CertifiedDeviceAudioProcessing(echoCancellation: true, noiseSuppression: false,
            automaticGainControl: true, hardwareMute: false)
        let device = try CertifiedDevice(type: .audioInput, id: "Native Input", vendor: product,
            model: product, related: ["Native Input", "Speaker"], audioProcessing: processing)
        #expect(device.type == .audioInput)
        #expect(device.id == "Native Input")
        #expect(device.vendor == product && device.model == product)
        #expect(device.related == ["Native Input", "Speaker"])
        #expect(device.audioProcessing == processing)
        #expect(processing.echoCancellation == true && processing.noiseSuppression == false)
        #expect(processing.automaticGainControl == true && processing.hardwareMute == false)
        guard case .object(let object) = device.jsonValue else { Issue.record("Expected device object"); return }
        #expect(object["type"] == .string("audioinput"))
        #expect(object["id"] == .string("Native Input"))
        #expect(object["related"] == .array([.string("Native Input"), .string("Speaker")]))
        #expect(object["vendor"] == .object(["name": .string("Vendor"), "url": .string("https://example.invalid/device")]))
        #expect(object["model"] == object["vendor"])
        #expect(object["echo_cancellation"] == .bool(true))
        #expect(object["noise_suppression"] == .bool(false))
        #expect(object["automatic_gain_control"] == .bool(true))
        #expect(object["hardware_mute"] == .bool(false))
        let empty = CertifiedDeviceAudioProcessing()
        #expect(empty.echoCancellation == nil && empty.noiseSuppression == nil)
        #expect(empty.automaticGainControl == nil && empty.hardwareMute == nil)
        let unreported = try CertifiedDevice(type: .audioInput, id: "Unreported", vendor: product,
            model: product, audioProcessing: empty)
        guard case .object(let fields) = unreported.jsonValue else { Issue.record("Expected object"); return }
        #expect(fields.count == 5)
        #expect(fields["echo_cancellation"] == nil && fields["hardware_mute"] == nil)
        for type in CertifiedDeviceType.allCases {
            let noFlags = try CertifiedDevice(type: type, id: "ID", vendor: product, model: product)
            guard case .object(let fields) = noFlags.jsonValue else { Issue.record("Expected object"); continue }
            #expect(fields["type"] == .string(type.rawValue))
            #expect(fields["related"] == .array([]))
            #expect(noFlags.audioProcessing == nil)
        }
    }

    /// Rejects blank, control-bearing and overlong text without leaking input in failures.
    /// - Parameter text: An invalid identifier/name spelling across boundary classes.
    @Test(arguments: ["", " ", "\n", "has\u{0}control", String(repeating: "a", count: 1_025)])
    func invalidIdentifier(_ text: String) throws {
        let product = try certifiedProduct()
        #expect(throws: CertifiedDeviceFailure.invalidText) {
            try CertifiedDevice(type: .audioInput, id: text, vendor: product, model: product)
        }
        #expect(throws: CertifiedDeviceFailure.invalidText) {
            try CertifiedDevice(type: .audioInput, id: "valid", vendor: product, model: product, related: [text])
        }
    }

    /// Accepts inclusive UTF-8 bounds while rejecting overlong model names and URLs.
    @Test func modelTextBoundaries() throws {
        let url = try #require(URL(string: "http://example.invalid/product"))
        let product = try CertifiedDeviceProduct(name: String(repeating: "a", count: 256), url: url)
        #expect(product.name.utf8.count == 256 && product.url == url)
        #expect(throws: CertifiedDeviceFailure.invalidText) {
            try CertifiedDeviceProduct(name: String(repeating: "a", count: 257), url: url)
        }
        for name in ["", " ", "bad\nname"] {
            #expect(throws: CertifiedDeviceFailure.invalidText) { try CertifiedDeviceProduct(name: name, url: url) }
        }
        let maximum = try CertifiedDevice(type: .videoInput, id: String(repeating: "é", count: 512),
            vendor: product, model: product, related: (0..<64).map { String($0) })
        #expect(maximum.id.utf8.count == 1_024 && maximum.related.count == 64)
        #expect(throws: CertifiedDeviceFailure.tooManyRelatedDevices) {
            try CertifiedDevice(type: .audioInput, id: "ID", vendor: product, model: product,
                related: (0..<65).map { String($0) })
        }
        #expect(throws: CertifiedDeviceFailure.duplicateRelatedDevice) {
            try CertifiedDevice(type: .audioInput, id: "ID", vendor: product, model: product, related: ["x", "x"])
        }
    }

    /// Disallows active schemes, user information, fragments and oversized descriptive URLs.
    /// - Parameter spelling: Invalid URL supplied by a host application.
    @Test(arguments: ["file:///tmp/device", "relative/device", "https://user:secret@example.invalid/device",
                      "https://example.invalid/#fragment", "https://example.invalid/" + String(repeating: "a", count: 2_048)])
    func invalidProductURL(_ spelling: String) throws {
        let url = try #require(URL(string: spelling))
        #expect(throws: CertifiedDeviceFailure.invalidURL) { try CertifiedDeviceProduct(name: "Vendor", url: url) }
    }

    /// Restricts native processing metadata to audio inputs even when every flag is absent.
    /// - Parameter type: A documented device type with no input-processing contract.
    @Test(arguments: [CertifiedDeviceType.audioOutput, .videoInput])
    func audioOnlyFields(_ type: CertifiedDeviceType) throws {
        let product = try certifiedProduct()
        #expect(throws: CertifiedDeviceFailure.audioProcessingRequiresAudioInput) {
            try CertifiedDevice(type: type, id: "ID", vendor: product, model: product,
                audioProcessing: CertifiedDeviceAudioProcessing())
        }
    }

    /// Keeps native identifiers, names and URLs out of every standard diagnostic path.
    @Test func diagnosticRedaction() throws {
        let secret = "sentinel-native-device"
        let product = try CertifiedDeviceProduct(name: secret,
            url: #require(URL(string: "https://example.invalid/\(secret)")))
        let device = try CertifiedDevice(type: .audioInput, id: secret, vendor: product, model: product,
            related: [secret])
        for value in [product as any Sendable, device as any Sendable] {
            #expect(!String(describing: value).contains(secret))
            #expect(!String(reflecting: value).contains(secret))
            #expect(!String(describing: Array(Mirror(reflecting: value).children)).contains(secret))
        }
        #expect(Set([device, device]).count == 1)
        #expect(Set([product, product]).count == 1)
    }
}

/// Creates ordinary valid metadata for deterministic tests without resolving its hostname.
/// - Returns: Immutable vendor/model metadata with a non-routable example URL.
/// - Throws: Test requirement or production validation failures.
func certifiedProduct() throws -> CertifiedDeviceProduct {
    try CertifiedDeviceProduct(name: "Vendor", url: #require(URL(string: "https://example.invalid/device")))
}

/// Creates a host-identified device without touching native hardware or desktop services.
/// - Parameters:
///   - id: Native identifier test fixture, default `Input`.
///   - type: Documented device kind, default audio input.
/// - Returns: A valid device with no optional audio metadata.
/// - Throws: Metadata validation or fixture requirement failures.
func certifiedDevice(_ id: String = "Input", type: CertifiedDeviceType = .audioInput) throws -> CertifiedDevice {
    let product = try certifiedProduct()
    return try CertifiedDevice(type: type, id: id, vendor: product, model: product)
}
