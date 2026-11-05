// File: Sources/DiscordModels/ComponentContentScan.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Discord's API v10 content-scan results for component media, retaining unknown fields.
/// Results are response-only and can first appear in a later Message Update. When reposting
/// user media, inspect the sent message and subsequent updates and act on flagged media.
/// A missing result does not establish whether scanning has finished.
/// See https://docs.discord.com/developers/components/reference#unfurled-media-item-content-scan-metadata-structure.
public struct UnfurledMediaContentScanMetadata: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Required nonnull scan bitfield; wrap with `UnfurledMediaContentScanFlags` for named checks.
    public let flags: UInt64
    /// Original bounded object, preserving future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses and validates one bounded content-scan object synchronously without I/O.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object containing a nonnull unsigned integer `flags`.
    ///   - limits: Whole-document parser bounds; defaults to 1 MiB, depth 64 and 100,000 nodes.
    /// - Throws: JSON syntax or bound errors, or sanitized invalid-response errors for
    ///   missing flags, nulls, incompatible types, nonintegral spellings or unsigned overflow.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded metadata subtree without reparsing its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown fields and flag bits remain intact.
    ///   - limits: The containing document's bounds, used for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or missing, null or malformed flags.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        flags = try object.required("flags", UInt64.self)
        rawFields = object.resource.fields
    }

    /// Conceals all scan metadata, including unknown fields, in ordinary diagnostics.
    public var description: String { "UnfurledMediaContentScanMetadata(redacted)" }
    /// Returns the same redacted value as ordinary diagnostics without traversing raw payloads.
    public var debugDescription: String { description }
    /// Exposes only a redaction marker, keeping future payload content out of reflective diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Documented response-only content-scan flags for unfurled component media.
/// These bits differ from attachment and embed flags. Unknown bits remain inspectable;
/// an empty bitfield describes the available result and does not predict later scan updates.
public struct UnfurledMediaContentScanFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned scan bitfield, including future bits.
    public let rawValue: UInt64

    /// Retains an unsigned scan bitfield synchronously without I/O, normalization or side effects.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown bits.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Discord's content scanning flagged this media as explicit.
    public static let isExplicitContent = Self(rawValue: 1 << 0)
    /// Discord's content scanning flagged this media as gore.
    public static let isGoreContent = Self(rawValue: 1 << 1)
    /// Discord's content scanning flagged this media as self-harm.
    public static let isSelfHarmContent = Self(rawValue: 1 << 2)
}
