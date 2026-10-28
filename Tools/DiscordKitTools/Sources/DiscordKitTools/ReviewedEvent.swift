// File: Tools/DiscordKitTools/Sources/DiscordKitTools/ReviewedEvent.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// A reviewed event-to-payload relationship whose delivery lifecycle remains handwritten.
///
/// `payloadModelID` is `none` when no typed payload projection has been reviewed. Such
/// an event may remain unsupported or partial, but cannot claim supported typed coverage.
/// `variantIDs` identifies already reviewed enum variants relevant to the event payload;
/// an empty list explicitly records that no variant relationship is currently classified.
/// The record describes schema/evidence links and creates no Gateway event handler.
struct ReviewedEvent: Codable, Equatable, Sendable {
    let payloadModelID: String
    let variantIDs: [String]
    let behavior: String
}

/// Pure semantic checks for event payload links in the closed reviewed inventory schema.
enum ReviewedEventValidator {
    /// Resolves one event's source, payload model and related enum variants without I/O.
    ///
    /// The enclosing inventory validator checks global IDs, source ownership, dates and
    /// implementation evidence before this operation. Event records must refer to actual
    /// discovered events; opcode, endpoint and section records cannot stand in for them.
    /// Supported events require a supported typed payload and supported related variants.
    /// Partial events may explicitly leave their payload unmodeled. These classifications
    /// do not prove event ordering, delivery, resumption or runtime protocol qualification;
    /// handwritten behavior text and linked tests document those separate limitations.
    ///
    /// - Parameters:
    ///   - value: Definition whose kind is `event` and whose event metadata is present.
    ///   - definitions: Globally unique reviewed definitions available for payload/model
    ///     and enum-variant references. Missing or wrong-kind targets are invalid.
    ///   - upstream: Globally unique, structurally validated discovery definitions. Every
    ///     upstream ID in `value` must identify a discovered event.
    /// - Throws: `ReviewedInventoryFailure` for absent event metadata, empty behavior,
    ///   missing or wrong-kind links, duplicate/blank variant references, or a supported
    ///   classification whose payload or variants remain partial or unsupported. This
    ///   synchronous helper performs no writes, network access or suspension.
    static func validate(
        _ value: ReviewedDefinition, definitions: [String: ReviewedDefinition], upstream: [String: InventoryEntry]
    ) throws {
        guard value.kind == "event", let event = value.event,
              !value.upstreamIDs.isEmpty,
              value.upstreamIDs.allSatisfy({ upstream[$0]?.kind == "event" }),
              !event.behavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewedInventoryFailure(description: "Missing event behavior or discovered event reference: \(value.id)")
        }
        if event.payloadModelID == "none" {
            guard value.status != "supported" else {
                throw ReviewedInventoryFailure(description: "Supported event requires a typed payload model: \(value.id)")
            }
        } else {
            guard let payload = definitions[event.payloadModelID], payload.model != nil,
                  value.status != "supported" || payload.status == "supported" else {
                throw ReviewedInventoryFailure(description: "Unresolved or partially supported event payload model: \(value.id)")
            }
        }
        guard Set(event.variantIDs).count == event.variantIDs.count,
              event.variantIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ReviewedInventoryFailure(description: "Duplicate or blank event variant reference: \(value.id)")
        }
        for id in event.variantIDs {
            guard let variant = definitions[id], variant.variant != nil,
                  value.status != "supported" || variant.status == "supported" else {
                throw ReviewedInventoryFailure(description: "Unresolved or partially supported event variant: \(value.id):\(id)")
            }
        }
    }
}
