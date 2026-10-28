// File: Tools/DiscordKitTools/Sources/DiscordKitTools/Inventory.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// A versioned discovery inventory. Entries describe upstream definitions, not SDK support.
struct Inventory: Decodable, Sendable {
    let schemaVersion: Int
    let verifiedOn: String
    let protocolVersions: [String: String]
    let entries: [InventoryEntry]
}

/// An individually addressable definition whose provenance is inherited from its source.
struct InventoryEntry: Decodable, Sendable {
    let id: String
    let kind: String
    let name: String
    let sourceID: String
    let locator: String
    let context: String
    let status: String
    let condition: String
    let review: String
    let evidence: [String]
    let protocolVersion: String?

    /// Recognized schema keys; absent protocol overrides inherit the source classification.
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, sourceID, locator, context, status, condition, review, evidence
        case protocolVersion
    }

    /// Decodes required metadata and an optional, nonnullable protocol override.
    ///
    /// An omitted `protocolVersion` inherits the source's classification. An explicit
    /// null or nonstring value is malformed rather than an inheritance request, matching
    /// the interchange schema. The enclosing validator rejects unknown metadata keys;
    /// source-specific `definition` objects remain opaque until semantic review.
    /// This synchronous operation performs no I/O, suspension or shared-state mutation.
    ///
    /// - Parameter decoder: Decoder positioned at one inventory-entry object. Required
    ///   strings and string arrays must be present; classification values are checked by
    ///   `InventoryValidator.validate(inventoryData:sourcesData:)` after decoding.
    /// - Throws: `DecodingError` for a nonobject entry, missing required key, null value,
    ///   or incompatible JSON type, including an explicitly null protocol override.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(String.self, forKey: .kind)
        name = try values.decode(String.self, forKey: .name)
        sourceID = try values.decode(String.self, forKey: .sourceID)
        locator = try values.decode(String.self, forKey: .locator)
        context = try values.decode(String.self, forKey: .context)
        status = try values.decode(String.self, forKey: .status)
        condition = try values.decode(String.self, forKey: .condition)
        review = try values.decode(String.self, forKey: .review)
        evidence = try values.decode([String].self, forKey: .evidence)
        protocolVersion = values.contains(.protocolVersion)
            ? try values.decode(String.self, forKey: .protocolVersion) : nil
    }
}

/// Pinned sources and their complete discovery membership, used to detect lost definitions.
struct SourceCatalog: Decodable, Sendable {
    let schemaVersion: Int
    let verifiedOn: String
    let sources: [InventorySource]
}

/// A content-addressed upstream source; unknown dates are explicit rather than inferred.
struct InventorySource: Decodable, Sendable {
    let id: String
    let url: String
    let revision: String
    let sha256: String
    let verifiedOn: String
    let announcementDate: String
    let effectiveDate: String
    let protocolVersion: String
    let authority: String
    let accessPrerequisites: String
    let platformAvailability: String
    let entryIDs: [String]
}

/// A successful structural audit. Semantic review and runtime qualification remain separate gates.
struct InventoryReport: Equatable, Sendable {
    let entries: Int
    let sources: Int
    let supported: Int
    let pendingReview: Int
}

/// A deterministic audit failure; diagnostics contain definition IDs, never upstream payloads.
struct InventoryFailure: Error, CustomStringConvertible {
    let description: String
}

/// Checks the committed discovery inventory without accessing the network or changing files.
enum InventoryValidator {
    static let protocolVersions: Set<String> = ["10", "8", "unversioned", "not_applicable"]
    static let statuses: Set<String> = ["supported", "partial", "unsupported", "deprecated", "removed"]
    static let conditions: Set<String> = [
        "public_protocol", "approval_required", "portal_only", "unavailable_upstream",
        "undocumented_protocol", "unavailable_host", "not_applicable",
    ]
    static let kinds: Set<String> = [
        "page", "section", "endpoint", "model", "field", "enum_value", "permission",
        "intent", "opcode", "close_code", "event", "sdk_method", "protocol_state", "table_row",
    ]

    /// Decodes and audits both JSON documents, including source membership and support evidence.
    ///
    /// This synchronous, nonisolated operation has no side effects or cancellation points. It
    /// performs linear scans with sets proportional to the inventory size. Discovery membership
    /// catches accidentally omitted definitions; it does not prove that an extractor understood
    /// every upstream contract. A passing result must never be labeled full API parity.
    /// Source versions and any entry overrides use the schema-v1 vocabulary. An absent
    /// override inherits its source version; an explicit null or nonstring is rejected.
    ///
    /// - Parameters:
    ///   - inventoryData: UTF-8 JSON matching inventory schema version 1. Empty or malformed
    ///     data fails decoding; an empty entries array fails validation.
    ///   - sourcesData: UTF-8 JSON containing pinned sources and the IDs discovered in each.
    /// - Returns: Counts of entries, pinned sources, supported entries, and pending reviews.
    /// - Throws: `DecodingError` for missing or incorrectly typed fields, or
    ///   `InventoryFailure` for invalid classifications, provenance, dates, IDs, membership,
    ///   protocol versions, or unsupported claims of verified implementation.
    static func validate(inventoryData: Data, sourcesData: Data) throws -> InventoryReport {
        let inventory = try JSONDecoder().decode(Inventory.self, from: inventoryData)
        let catalog = try JSONDecoder().decode(SourceCatalog.self, from: sourcesData)
        try validateKeys(
            inventoryData,
            rootKeys: ["schemaVersion", "verifiedOn", "protocolVersions", "entries"],
            collectionKey: "entries",
            itemKeys: [
                "id", "kind", "name", "sourceID", "locator", "context", "status", "condition", "review",
                "evidence", "protocolVersion", "definition",
            ]
        )
        try validateKeys(
            sourcesData, rootKeys: ["schemaVersion", "verifiedOn", "sources"], collectionKey: "sources",
            itemKeys: [
                "id", "url", "revision", "sha256", "verifiedOn", "announcementDate", "effectiveDate",
                "protocolVersion", "authority", "accessPrerequisites", "platformAvailability", "entryIDs",
            ]
        )
        guard inventory.schemaVersion == 1, catalog.schemaVersion == 1,
              isDate(inventory.verifiedOn), inventory.verifiedOn == catalog.verifiedOn,
              inventory.protocolVersions == ["rest": "10", "gateway": "10", "voice": "8"],
              !inventory.entries.isEmpty, !catalog.sources.isEmpty else {
            throw InventoryFailure(description: "Invalid schema version, baseline date, protocols, or empty inventory")
        }
        var sourcesByID: [String: InventorySource] = [:]
        var discovered: Set<String> = []
        var discoveryOwners: [String: String] = [:]
        for source in catalog.sources {
            guard !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sourcesByID[source.id] == nil,
                  let url = URL(string: source.url), url.scheme == "https", url.host != nil,
                  source.sha256.count == 64,
                  source.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  !source.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, isDate(source.verifiedOn),
                  source.verifiedOn == catalog.verifiedOn,
                  isDate(source.announcementDate, allowUnknown: true),
                  isDate(source.effectiveDate, allowUnknown: true),
                  protocolVersions.contains(source.protocolVersion),
                  ["written_docs", "preview_spec", "sdk_reference", "discovery_index"].contains(source.authority),
                  !source.accessPrerequisites.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !source.platformAvailability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !source.entryIDs.isEmpty else {
                throw InventoryFailure(description: "Invalid or duplicate source: \(source.id)")
            }
            sourcesByID[source.id] = source
            for id in source.entryIDs {
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, discovered.insert(id).inserted else {
                    throw InventoryFailure(description: "Duplicate or empty discovery ID: \(id)")
                }
                discoveryOwners[id] = source.id
            }
        }
        var seen: Set<String> = []
        var supported = 0
        var pendingReview = 0
        for entry in inventory.entries {
            guard !entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(entry.id).inserted,
                  kinds.contains(entry.kind), statuses.contains(entry.status),
                  entry.protocolVersion.map({ protocolVersions.contains($0) }) ?? true,
                  conditions.contains(entry.condition), ["discovered", "reviewed"].contains(entry.review),
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  sourcesByID[entry.sourceID] != nil, discoveryOwners[entry.id] == entry.sourceID else {
                throw InventoryFailure(description: "Invalid, unclassified, duplicate, or unlinked entry: \(entry.id)")
            }
            if entry.status == "supported" || entry.status == "partial" {
                guard entry.review == "reviewed", !entry.evidence.isEmpty,
                      entry.evidence.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw InventoryFailure(description: "Support requires review and test evidence: \(entry.id)")
                }
            }
            if entry.status == "supported" { supported += 1 }
            if entry.review == "discovered" { pendingReview += 1 }
        }
        guard seen == discovered else {
            throw InventoryFailure(description: "Inventory membership differs from pinned source discovery IDs")
        }
        return InventoryReport(
            entries: seen.count, sources: sourcesByID.count, supported: supported,
            pendingReview: pendingReview
        )
    }

    /// Rejects metadata keys absent from schema v1 while retaining opaque source definitions.
    ///
    /// Typed decoding runs first, so this pass only examines objects and arrays whose
    /// required shapes already passed the decoder. The additional JSON traversal is
    /// linear in the input size, performs no I/O and does not modify caller data.
    /// `definition` is intentionally source-specific: its contents are unrestricted,
    /// but a present value must be a JSON object, matching the committed schema.
    ///
    /// - Parameters:
    ///   - data: JSON already decoded into its inventory or source-catalog type.
    ///   - rootKeys: Complete permitted keys for the containing schema-v1 document.
    ///   - collectionKey: Required array of entry or source objects within the document.
    ///   - itemKeys: Complete permitted metadata keys for each collection object.
    /// - Throws: `InventoryFailure` for unknown document or metadata keys, or a nonobject
    ///   source definition; JSON serialization errors propagate if input is malformed.
    private static func validateKeys(
        _ data: Data, rootKeys: Set<String>, collectionKey: String, itemKeys: Set<String>
    ) throws {
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InventoryFailure(description: "Inventory document must be a JSON object")
        }
        let rootExtras = Set(document.keys).subtracting(rootKeys).sorted()
        guard rootExtras.isEmpty else {
            throw InventoryFailure(description: "Unknown inventory metadata keys: \(rootExtras.joined(separator: ", "))")
        }
        for item in document[collectionKey] as? [[String: Any]] ?? [] {
            let extras = Set(item.keys).subtracting(itemKeys).sorted()
            guard extras.isEmpty else {
                throw InventoryFailure(description: "Unknown \(collectionKey) metadata keys: \(extras.joined(separator: ", "))")
            }
            if let definition = item["definition"], !(definition is [String: Any]) {
                throw InventoryFailure(description: "Source-specific definition must be a JSON object")
            }
        }
    }

    /// Validates a Gregorian calendar date using exactly `YYYY-MM-DD`, without normalization.
    ///
    /// - Parameters:
    ///   - value: A four-digit year in 0001...9999, month and day, or the literal `unknown`.
    ///   - allowUnknown: Whether `unknown` is accepted; defaults to `false` for verification dates.
    /// - Returns: Whether the input is a real date or an explicitly permitted unknown. Leap days
    ///   use Gregorian rules. This pure helper neither reads the current clock nor a time zone.
    private static func isDate(_ value: String, allowUnknown: Bool = false) -> Bool {
        if allowUnknown, value == "unknown" { return true }
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), year > 0,
              let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(value.suffix(2)) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }
}
