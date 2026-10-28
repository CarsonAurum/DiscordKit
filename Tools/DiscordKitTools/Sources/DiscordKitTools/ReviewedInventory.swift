// File: Tools/DiscordKitTools/Sources/DiscordKitTools/ReviewedInventory.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Schema-v1 reviewed contracts, kept separate from broad, mechanically discovered definitions.
///
/// The document records a deliberately finite generation surface. IDs link provenance,
/// wire contracts, real Swift declarations and executable or fixture evidence without
/// promoting omitted upstream definitions to supported status.
struct ReviewedInventory: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let verifiedOn: String
    let maxAgeDays: Int
    let sources: [ReviewedSourcePin]
    let definitions: [ReviewedDefinition]
    let symbols: [ReviewedSymbol]
    let evidence: [ReviewedEvidence]
}

/// An exact reference to a content-addressed source in the existing discovery catalog.
struct ReviewedSourcePin: Codable, Equatable, Sendable {
    let id: String
    let revision: String
    let sha256: String
}

/// A stable reviewed entity and its independently classified implementation and provenance.
///
/// Exactly one kind-specific contract must be present. Upstream announcement and effective
/// dates may remain `unknown`; `supportSince` describes the separate local implementation.
struct ReviewedDefinition: Codable, Equatable, Sendable {
    let id: String
    let kind: String
    let name: String
    let sourceID: String
    let upstreamIDs: [String]
    let status: String
    let supportSince: String
    let announcementDate: String
    let effectiveDate: String
    let symbolIDs: [String]
    let evidenceIDs: [String]
    let notes: String
    let model: ReviewedModel?
    let field: ReviewedField?
    let enumeration: ReviewedEnumeration?
    let variant: ReviewedVariant?
    let endpoint: ReviewedEndpoint?
    let manual: ReviewedManual?
    let event: ReviewedEvent?

    /// JSON uses the wire term `enum`; Swift uses a nonkeyword property name.
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, sourceID, upstreamIDs, status, supportSince
        case announcementDate, effectiveDate, symbolIDs, evidenceIDs, notes
        case model, field, enumeration = "enum", variant, endpoint, manual, event
    }
}

/// A finite model projection with explicit supported fields and discovered omissions.
struct ReviewedModel: Codable, Equatable, Sendable {
    let fieldIDs: [String]
    let omittedUpstreamIDs: [String]
    let unknownFields: String
    let codec: String?
    let direction: String?
}

/// A reviewed wire field whose presence, null, default and unknown-value rules are explicit.
struct ReviewedField: Codable, Equatable, Sendable {
    let modelID: String
    let wireName: String
    let swiftName: String
    let valueType: String
    let optional: Bool
    let nullable: Bool
    let defaultBehavior: String
    let constraints: [String]
    let access: String
    let unknownValueBehavior: String
}

/// A closed set of recognized enum variants with a separately stated unknown-value policy.
struct ReviewedEnumeration: Codable, Equatable, Sendable {
    let variantIDs: [String]
    let unknownValueBehavior: String
}

/// One named Swift enum case and its exact integer representation on the wire.
struct ReviewedVariant: Codable, Equatable, Sendable {
    let enumID: String
    let swiftName: String
    let rawValue: Int
}

/// An endpoint contract including authentication, payload models and bounded execution policy.
///
/// `requestModelID` is `none` for an operation without a modeled request body. The two status
/// lists are explicit review metadata rather than an assertion that Discord cannot return
/// other responses; runtime error handling must retain unknown status behavior.
struct ReviewedEndpoint: Codable, Equatable, Sendable {
    let swiftName: String
    let method: String
    let path: String
    let authentication: String
    let requestModelID: String
    let responseModelID: String
    let successStatuses: [Int]
    let errorStatuses: [Int]
    let rateLimit: String
    let retry: String
    let pagination: String
}

/// An intentionally handwritten implementation mapped to reviewed discovery and test evidence.
struct ReviewedManual: Codable, Equatable, Sendable {
    let behavior: String
    let fields: [ReviewedManualField]?

    /// Records handwritten behavior and optional semantic field contracts without generating code.
    /// - Parameters:
    ///   - behavior: Nonempty implementation description, validated during the semantic audit.
    ///   - fields: Explicit field contracts, or nil for existing behavior-only records. A present
    ///     array must be nonempty and fully linked to its parent's source, symbols and upstream IDs.
    /// No source rendering or declaration inference occurs; nil is omitted by synthesized encoding.
    init(behavior: String, fields: [ReviewedManualField]? = nil) {
        self.behavior = behavior; self.fields = fields
    }
}

/// A non-generated handwritten field contract with explicit wire semantics and declaration provenance.
///
/// Unlike generated `ReviewedField` types, descriptive `valueType` metadata can name recursive,
/// request-only or semantic Swift types. It is never interpolated into generated Swift source.
/// Parent references constrain discovery and symbol membership; existing source audits still
/// require every referenced declaration to exist in a safely contained production Swift file.
struct ReviewedManualField: Codable, Equatable, Sendable {
    let wireName: String
    let swiftName: String
    let valueType: String
    let optional: Bool
    let nullable: Bool
    let defaultBehavior: String
    let constraints: [String]
    let access: String
    let unknownValueBehavior: String
    let upstreamIDs: [String]
    let symbolID: String
}

/// An exact declaration line in a real repository Swift source file, addressed by stable ID.
struct ReviewedSymbol: Codable, Equatable, Sendable {
    let id: String
    let path: String
    let declaration: String
}

/// A real test function or structured JSON fixture case that supports reviewed behavior.
struct ReviewedEvidence: Codable, Equatable, Sendable {
    let id: String
    let path: String
    let anchor: String
}

/// Stable counts returned only after structural, provenance, semantic and repository audits pass.
struct ReviewedInventoryReport: Equatable, Sendable {
    let definitions: Int
    let sources: Int
    let symbols: Int
    let evidence: Int
    let models: Int
    let fields: Int
    let enums: Int
    let variants: Int
    let endpoints: Int
    let manual: Int
    let events: Int
}

/// A deterministic reviewed-contract error containing repository metadata rather than payloads.
struct ReviewedInventoryFailure: Error, CustomStringConvertible {
    let description: String
}

/// Offline audits for reviewed schema-v1 contracts and their concrete implementation evidence.
enum ReviewedInventoryValidator {
    /// Decodes the closed reviewed schema without reading files or consulting a clock.
    ///
    /// Unknown keys are rejected at every object boundary, including kind-specific metadata;
    /// recognized optional codec/direction/manual-field keys may be omitted but may never be JSON null.
    /// This operation performs synchronous work proportional to input size, leaves input data
    /// unchanged and has no suspension points, cancellation checks or shared mutable state.
    /// - Parameter reviewedData: UTF-8 reviewed schema-v1 JSON. Empty data is invalid.
    /// - Returns: A decoded value; call `validate` before trusting semantic support claims.
    /// - Throws: `DecodingError` for missing or mistyped values; `ReviewedInventoryFailure`
    ///   for unknown keys, null values, mismatched kind metadata or a nonobject root.
    static func load(reviewedData: Data) throws -> ReviewedInventory {
        let json = try JSONSerialization.jsonObject(with: reviewedData)
        try checkShape(json)
        return try JSONDecoder().decode(ReviewedInventory.self, from: reviewedData)
    }

    /// Audits reviewed contracts against discovery membership, source pins and real evidence.
    ///
    /// Freshness uses the caller's explicit Gregorian UTC review date, making CI and tests
    /// deterministic. Neither the system clock nor the network is consulted. Repository reads
    /// are confined to regular source/test/fixture files below the symlink-resolved root.
    /// All identity/link scans are linear except small per-model uniqueness checks; memory is
    /// proportional to input size and source files. The operation does not modify files.
    /// - Parameters:
    ///   - reviewedData: Closed reviewed schema-v1 JSON with at least one definition.
    ///   - inventoryData: Existing discovery inventory JSON; its membership is checked against
    ///     the existing source catalog before reviewed references are resolved.
    ///   - sourcesData: Existing pinned discovery catalog JSON, including revision and hash.
    ///   - repository: Existing checkout root containing referenced declarations and evidence.
    ///   - asOf: Strict `YYYY-MM-DD` date. Future or overly old verification dates fail.
    ///   - generatedArtifacts: Optional deterministic rendered Swift files, keyed by safe
    ///     repository-relative path. Generation may validate declarations before writing
    ///     missing outputs; normal audits leave this empty. Evidence always uses disk files.
    /// - Returns: Counts of the successfully audited definitions and linked resources.
    /// - Throws: JSON decoding errors, file-read errors, `InventoryFailure` for invalid
    ///   discovery input, or `ReviewedInventoryFailure` for any semantic, freshness, path,
    ///   unresolved-link, duplicate, classification or missing-evidence violation. Correct
    ///   the review metadata or evidence before retrying; validation never repairs inputs.
    static func validate(
        reviewedData: Data, inventoryData: Data, sourcesData: Data,
        repository: URL, asOf: String, generatedArtifacts: [String: Data] = [:]
    ) throws -> ReviewedInventoryReport {
        _ = try InventoryValidator.validate(inventoryData: inventoryData, sourcesData: sourcesData)
        let reviewed = try load(reviewedData: reviewedData)
        let inventory = try JSONDecoder().decode(Inventory.self, from: inventoryData)
        let catalog = try JSONDecoder().decode(SourceCatalog.self, from: sourcesData)
        guard let today = day(asOf), let verified = day(reviewed.verifiedOn),
              reviewed.schemaVersion == 1, (1...366).contains(reviewed.maxAgeDays),
              (0...reviewed.maxAgeDays).contains(today - verified),
              !reviewed.definitions.isEmpty, !reviewed.sources.isEmpty else {
            throw failure("Invalid reviewed schema, freshness date, age budget, or empty definitions")
        }
        let sources = Dictionary(uniqueKeysWithValues: catalog.sources.map { ($0.id, $0) })
        let upstream = Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.id, $0) })
        let pins = try index(reviewed.sources, id: { $0.id }, label: "source pin")
        let definitions = try index(reviewed.definitions, id: { $0.id }, label: "definition")
        let symbols = try index(reviewed.symbols, id: { $0.id }, label: "symbol")
        let evidence = try index(reviewed.evidence, id: { $0.id }, label: "evidence")
        let allIDs = reviewed.definitions.map(\.id) + reviewed.symbols.map(\.id) + reviewed.evidence.map(\.id)
        try require(Set(allIDs).count == allIDs.count, "IDs collide across definitions, symbols and evidence")
        for pin in reviewed.sources {
            guard let source = sources[pin.id], source.revision == pin.revision, source.sha256 == pin.sha256,
                  let sourceDay = day(source.verifiedOn), (0...reviewed.maxAgeDays).contains(today - sourceDay) else {
                throw failure("Unresolved, changed or stale source pin: \(pin.id)")
            }
        }
        var usedSymbols: Set<String> = [], usedEvidence: Set<String> = [], usedSources: Set<String> = []
        for definition in reviewed.definitions {
            try require(["model", "field", "enum", "variant", "endpoint", "manual", "event"].contains(definition.kind),
                        "Unclassified definition: \(definition.id)")
            try require(InventoryValidator.statuses.contains(definition.status), "Unclassified status: \(definition.id)")
            try require(nonempty(definition.name) && nonempty(definition.notes), "Missing review text: \(definition.id)")
            try require(pins[definition.sourceID] != nil, "Unpinned definition source: \(definition.id)")
            try require(!definition.upstreamIDs.isEmpty, "Missing upstream references: \(definition.id)")
            try unique(definition.upstreamIDs, label: "upstream references for \(definition.id)")
            let compatibleKinds: [String: Set<String>] = [
                "model": ["section", "model"], "field": ["field"],
                "enum": ["section", "model"], "variant": ["enum_value"], "endpoint": ["endpoint"], "event": ["event"],
            ]
            for id in definition.upstreamIDs {
                try require(upstream[id]?.sourceID == definition.sourceID, "Unresolved upstream reference: \(definition.id):\(id)")
                if let kinds = compatibleKinds[definition.kind] {
                    try require(upstream[id].map { kinds.contains($0.kind) } == true,
                                "Incompatible upstream definition kind: \(definition.id):\(id)")
                }
            }
            let implemented = definition.status == "supported" || definition.status == "partial"
            try require(validDate(definition.announcementDate, unknown: true)
                        && validDate(definition.effectiveDate, unknown: true), "Invalid upstream date: \(definition.id)")
            try require(validDate(definition.supportSince, unknown: !implemented), "Invalid local support date: \(definition.id)")
            if let supportDay = day(definition.supportSince) {
                try require(supportDay <= verified, "Local support date follows verification: \(definition.id)")
            }
            try unique(definition.symbolIDs, label: "symbol references for \(definition.id)")
            try unique(definition.evidenceIDs, label: "evidence references for \(definition.id)")
            try require(!implemented || (!definition.symbolIDs.isEmpty && !definition.evidenceIDs.isEmpty),
                        "Supported definition lacks symbol or evidence: \(definition.id)")
            for id in definition.symbolIDs {
                try require(symbols[id] != nil, "Unresolved symbol: \(id)")
                usedSymbols.insert(id)
            }
            for id in definition.evidenceIDs {
                try require(evidence[id] != nil, "Unresolved evidence: \(id)")
                usedEvidence.insert(id)
            }
            usedSources.insert(definition.sourceID)
            try validateContract(definition, definitions: definitions, upstream: upstream)
        }
        try require(usedSources == Set(pins.keys), "Orphan source pins")
        try require(usedSymbols == Set(symbols.keys), "Orphan symbols")
        try require(usedEvidence == Set(evidence.keys), "Orphan evidence")
        for symbol in reviewed.symbols { try validateSymbol(symbol, repository: repository, generatedArtifacts: generatedArtifacts) }
        for item in reviewed.evidence { try validateEvidence(item, repository: repository) }
        let kinds = Dictionary(grouping: reviewed.definitions, by: \.kind)
        return ReviewedInventoryReport(
            definitions: definitions.count, sources: pins.count, symbols: symbols.count, evidence: evidence.count,
            models: kinds["model", default: []].count, fields: kinds["field", default: []].count,
            enums: kinds["enum", default: []].count, variants: kinds["variant", default: []].count,
            endpoints: kinds["endpoint", default: []].count, manual: kinds["manual", default: []].count,
            events: kinds["event", default: []].count
        )
    }

    /// Checks reciprocal ownership, field classifications and endpoint model/status references.
    /// - Parameters:
    ///   - value: One already structurally decoded definition to audit.
    ///   - definitions: Globally unique reviewed IDs available for reciprocal links.
    ///   - upstream: Valid discovery IDs and source ownership for omitted field references.
    /// - Throws: `ReviewedInventoryFailure` for invalid contracts, duplicate names/values,
    ///   orphan fields/variants, unresolved models or unclassified behavior.
    private static func validateContract(
        _ value: ReviewedDefinition, definitions: [String: ReviewedDefinition], upstream: [String: InventoryEntry]
    ) throws {
        if let model = value.model {
            try unique(model.fieldIDs, label: "fields for \(value.id)")
            try unique(model.omittedUpstreamIDs, label: "omissions for \(value.id)")
            try require(!model.fieldIDs.isEmpty, "Empty reviewed model: \(value.id)")
            try require(["preserveExact", "ignore", "discard", "reject"].contains(model.unknownFields), "Unclassified unknown-field policy: \(value.id)")
            try require(model.codec == nil || ["boundedJSON", "codable"].contains(model.codec!), "Unknown codec: \(value.id)")
            try require(model.direction == nil || ["request", "response"].contains(model.direction!), "Unknown model direction: \(value.id)")
            let codec = model.codec ?? "boundedJSON"
            try require(codec == "boundedJSON" ? model.unknownFields == "preserveExact" : ["ignore", "discard"].contains(model.unknownFields),
                        "Codec and unknown-field policy disagree: \(value.id)")
            var names: [String] = [], wireNames: [String] = [], included: Set<String> = []
            for id in model.fieldIDs {
                guard let child = definitions[id], let field = child.field, field.modelID == value.id else {
                    throw failure("Unresolved or inconsistent model field: \(id)")
                }
                try require(value.status != "supported" || child.status == "supported", "Supported model contains a partial field: \(value.id)")
                names.append(field.swiftName); wireNames.append(field.wireName)
                included.formUnion(child.upstreamIDs)
            }
            try unique(names, label: "Swift field names for \(value.id)")
            try unique(wireNames, label: "wire field names for \(value.id)")
            for id in model.omittedUpstreamIDs {
                try require(upstream[id]?.sourceID == value.sourceID && upstream[id]?.kind == "field" && !included.contains(id), "Invalid omitted field: \(id)")
            }
            let contexts = Set(included.compactMap { upstream[$0]?.context })
            try require(contexts.count == 1, "Model fields do not share an identifiable discovery group: \(value.id)")
            let discoveredFields = Set(upstream.values.filter {
                $0.sourceID == value.sourceID && $0.kind == "field" && contexts.contains($0.context)
            }.map(\.id))
            try require(discoveredFields == included.union(model.omittedUpstreamIDs),
                        "Unclassified or unrelated discovered model fields: \(value.id)")
            try require(model.omittedUpstreamIDs.isEmpty || value.status != "supported", "Supported model has omitted fields: \(value.id)")
        }
        if let field = value.field {
            try require(definitions[field.modelID]?.model?.fieldIDs.contains(value.id) == true, "Orphan field: \(value.id)")
            try require(identifier(field.swiftName) && nonempty(field.wireName), "Invalid field name: \(value.id)")
            let types: Set<String> = ["UserID", "ApplicationID", "GuildID", "String", "Bool", "Int", "UInt64", "[String]", "RawValue<PremiumType>", "JSONValue"]
            try require(types.contains(field.valueType), "Unclassified field type: \(value.id)")
            try require(nonempty(field.defaultBehavior) && nonempty(field.access) && nonempty(field.unknownValueBehavior)
                        && field.constraints.allSatisfy(nonempty), "Incomplete field contract: \(value.id)")
            try unique(field.constraints, label: "constraints for \(value.id)")
        }
        if let enumeration = value.enumeration {
            try unique(enumeration.variantIDs, label: "variants for \(value.id)")
            try require(!enumeration.variantIDs.isEmpty && nonempty(enumeration.unknownValueBehavior), "Incomplete enum contract: \(value.id)")
            var names: [String] = [], rawValues: [String] = []
            for id in enumeration.variantIDs {
                guard let variant = definitions[id]?.variant, variant.enumID == value.id else {
                    throw failure("Unresolved or inconsistent enum variant: \(id)")
                }
                try require(value.status != "supported" || definitions[id]?.status == "supported", "Supported enum contains a partial variant: \(value.id)")
                names.append(variant.swiftName); rawValues.append(String(variant.rawValue))
            }
            try unique(names, label: "enum names for \(value.id)")
            try unique(rawValues, label: "enum raw values for \(value.id)")
        }
        if let variant = value.variant {
            try require(identifier(variant.swiftName), "Invalid variant name: \(value.id)")
            try require(definitions[variant.enumID]?.enumeration?.variantIDs.contains(value.id) == true, "Orphan variant: \(value.id)")
        }
        if let endpoint = value.endpoint {
            try require(identifier(endpoint.swiftName) && ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(endpoint.method)
                        && endpoint.path.hasPrefix("/") && !endpoint.path.contains("?"), "Invalid endpoint identity: \(value.id)")
            try require(["bot", "bearer", "botOrBearer", "none"].contains(endpoint.authentication), "Unclassified authentication: \(value.id)")
            try require(endpoint.requestModelID == "none" || definitions[endpoint.requestModelID]?.model != nil,
                        "Unresolved request model: \(value.id)")
            try require(definitions[endpoint.responseModelID]?.model != nil, "Unresolved response model: \(value.id)")
            try require(value.status != "supported" || definitions[endpoint.responseModelID]?.status == "supported", "Supported endpoint has a partial response projection: \(value.id)")
            try require(!endpoint.successStatuses.isEmpty && endpoint.successStatuses.allSatisfy({ (200...299).contains($0) })
                        && !endpoint.errorStatuses.isEmpty && endpoint.errorStatuses.allSatisfy({ (400...599).contains($0) }),
                        "Invalid endpoint statuses: \(value.id)")
            try unique(endpoint.successStatuses.map(String.init), label: "success statuses for \(value.id)")
            try unique(endpoint.errorStatuses.map(String.init), label: "error statuses for \(value.id)")
            try require(nonempty(endpoint.rateLimit) && nonempty(endpoint.retry) && nonempty(endpoint.pagination), "Incomplete endpoint policy: \(value.id)")
        }
        if let manual = value.manual {
            try require(nonempty(manual.behavior), "Missing handwritten behavior: \(value.id)")
            if let fields = manual.fields {
                try require(!fields.isEmpty, "Empty handwritten field contracts: \(value.id)")
                try unique(fields.map(\.wireName), label: "handwritten wire field names for \(value.id)")
                try unique(fields.map(\.swiftName), label: "handwritten Swift field names for \(value.id)")
                for field in fields {
                    try require(identifier(field.swiftName) && safeMetadata(field.wireName)
                                && safeMetadata(field.valueType) && safeMetadata(field.defaultBehavior)
                                && safeMetadata(field.access) && safeMetadata(field.unknownValueBehavior)
                                && field.constraints.allSatisfy(safeMetadata),
                                "Incomplete or unsafe handwritten field contract: \(value.id)")
                    try unique(field.constraints, label: "handwritten constraints for \(value.id):\(field.swiftName)")
                    try require(value.symbolIDs.contains(field.symbolID),
                                "Unlinked handwritten field symbol: \(value.id):\(field.swiftName)")
                    try unique(field.upstreamIDs, label: "handwritten field upstream references for \(value.id):\(field.swiftName)")
                    try require(!field.upstreamIDs.isEmpty, "Missing handwritten field upstream reference: \(value.id):\(field.swiftName)")
                    for id in field.upstreamIDs {
                        try require(value.upstreamIDs.contains(id) && upstream[id]?.kind == "field"
                                    && upstream[id]?.sourceID == value.sourceID,
                                    "Unresolved handwritten field upstream reference: \(value.id):\(field.swiftName)")
                    }
                }
            }
        }
        if value.event != nil { try ReviewedEventValidator.validate(value, definitions: definitions, upstream: upstream) }
    }

    /// Enforces the exact recursively closed object vocabulary before synthesized decoding.
    /// - Parameter json: Parsed JSON root; scalar or array roots are rejected.
    /// - Throws: `ReviewedInventoryFailure` for unknown, missing, null or misplaced keys.
    private static func checkShape(_ json: Any) throws {
        let root = try object(json, required: ["schemaVersion", "verifiedOn", "maxAgeDays", "sources", "definitions", "symbols", "evidence"])
        for pin in try array(root["sources"]) {
            _ = try object(pin, required: ["id", "revision", "sha256"])
        }
        for symbol in try array(root["symbols"]) {
            _ = try object(symbol, required: ["id", "path", "declaration"])
        }
        for item in try array(root["evidence"]) {
            _ = try object(item, required: ["id", "path", "anchor"])
        }
        let common: Set<String> = ["id", "kind", "name", "sourceID", "upstreamIDs", "status", "supportSince", "announcementDate", "effectiveDate", "symbolIDs", "evidenceIDs", "notes"]
        let contracts: [String: Set<String>] = [
            "model": ["fieldIDs", "omittedUpstreamIDs", "unknownFields"],
            "field": ["modelID", "wireName", "swiftName", "valueType", "optional", "nullable", "defaultBehavior", "constraints", "access", "unknownValueBehavior"],
            "enum": ["variantIDs", "unknownValueBehavior"],
            "variant": ["enumID", "swiftName", "rawValue"],
            "endpoint": ["swiftName", "method", "path", "authentication", "requestModelID", "responseModelID", "successStatuses", "errorStatuses", "rateLimit", "retry", "pagination"],
            "manual": ["behavior"],
            "event": ["payloadModelID", "variantIDs", "behavior"],
        ]
        for definition in try array(root["definitions"]) {
            guard let raw = definition as? [String: Any], let kind = raw["kind"] as? String,
                  let keys = contracts[kind] else { throw failure("Unclassified definition kind") }
            let item = try object(raw, required: common.union([kind]))
            let optional: Set<String> = kind == "model" ? ["codec", "direction"] : kind == "manual" ? ["fields"] : []
            let metadata = try object(item[kind]!, required: keys, optional: optional)
            if kind == "manual", let fields = metadata["fields"] {
                for field in try array(fields) {
                    _ = try object(field, required: ["wireName", "swiftName", "valueType", "optional", "nullable",
                        "defaultBehavior", "constraints", "access", "unknownValueBehavior", "upstreamIDs", "symbolID"])
                }
            }
        }
    }

    /// Validates one dictionary's required/optional vocabulary without coercing JSON values.
    /// - Parameters:
    ///   - json: Candidate object; absent, scalar and array inputs fail.
    ///   - required: Keys that must all be present and nonnull.
    ///   - optional: Additional permitted nonnull keys; defaults to no extra keys.
    /// - Returns: The unchanged object for subsequent nested checks.
    /// - Throws: `ReviewedInventoryFailure` for a wrong container, unknown/missing key or null.
    private static func object(_ json: Any, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard let value = json as? [String: Any], required.isSubset(of: Set(value.keys)),
              Set(value.keys).isSubset(of: required.union(optional)),
              !value.values.contains(where: { $0 is NSNull }) else { throw failure("Unknown, missing or null reviewed schema key") }
        return value
    }

    /// Obtains an array without coercing a missing value or other JSON container.
    /// - Parameter json: Parsed value expected to be a JSON array.
    /// - Returns: The unmodified array, including an empty array when supplied.
    /// - Throws: `ReviewedInventoryFailure` for missing or nonarray input.
    private static func array(_ json: Any?) throws -> [Any] {
        guard let value = json as? [Any] else { throw failure("Expected reviewed schema array") }
        return value
    }

    /// Builds an index while rejecting blank, whitespace-only and duplicate IDs.
    /// - Parameters:
    ///   - values: Values to index in caller order; empty collections are permitted.
    ///   - id: Pure projection of each stable identifier.
    ///   - label: Diagnostic category, excluding credentials and response bodies.
    /// - Returns: An ID-keyed dictionary without collisions.
    /// - Throws: `ReviewedInventoryFailure` for any invalid identifier or duplicate.
    private static func index<T>(_ values: [T], id: (T) -> String, label: String) throws -> [String: T] {
        var result: [String: T] = [:]
        for value in values {
            let key = id(value)
            try require(nonempty(key) && result[key] == nil, "Invalid or duplicate \(label): \(key)")
            result[key] = value
        }
        return result
    }

    /// Rejects duplicate or blank references in a collection while preserving its order.
    /// - Parameters:
    ///   - values: Stable references or normalized strings to check; empty is permitted.
    ///   - label: Context used only in failure diagnostics.
    /// - Throws: `ReviewedInventoryFailure` for a duplicate or whitespace-only element.
    private static func unique(_ values: [String], label: String) throws {
        try require(values.allSatisfy(nonempty) && Set(values).count == values.count, "Duplicate or blank \(label)")
    }

    /// Checks a real, single-line Swift declaration in a safely contained source file.
    /// - Parameters:
    ///   - symbol: Symbol reference with an exact declaration line rather than a substring.
    ///   - repository: Checkout root; symlink escapes are rejected before reading.
    ///   - generatedArtifacts: Rendered UTF-8 source overrides for generation bootstrap.
    ///     Paths retain all containment checks even when their file is not written yet.
    /// - Throws: File errors or `ReviewedInventoryFailure` for an invalid path/declaration.
    private static func validateSymbol(_ symbol: ReviewedSymbol, repository: URL, generatedArtifacts: [String: Data]) throws {
        try require(symbol.path.hasPrefix("Sources/") && symbol.path.hasSuffix(".swift"), "Symbol is not a Swift production source: \(symbol.id)")
        let text = try contents(symbol.path, repository: repository, generatedArtifacts: generatedArtifacts)
        let declaration = symbol.declaration.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(?:(?:public|package|internal|private|fileprivate|open|static|final|nonisolated|mutating|override|convenience|required)\s+)*(?:struct|class|enum|actor|protocol|func|var|let|case|init|subscript|deinit)\b"#
        try require(!declaration.contains("\n") && declaration.range(of: pattern, options: .regularExpression) != nil
                    && text.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == declaration }),
                    "Unresolved real Swift declaration: \(symbol.id)")
    }

    /// Verifies a real test function or an explicitly identified structured JSON fixture case.
    /// - Parameters:
    ///   - item: Evidence reference; Swift anchors are bare function names and JSON anchors
    ///     are exact `id` strings in the fixture root or its top-level `cases` array.
    ///   - repository: Checkout root used to constrain resolved file ownership.
    /// - Throws: File/JSON errors or `ReviewedInventoryFailure` for unsupported paths,
    ///   missing named Swift Testing functions, missing fixture IDs or duplicate fixture
    ///   case IDs. Swift tests must have an actual `@Test` attribute, on the declaration
    ///   line or preceding lines, optionally alongside other attributes. Attribute argument
    ///   lists must fit on one line; this lexical audit is not a full Swift parser.
    private static func validateEvidence(_ item: ReviewedEvidence, repository: URL) throws {
        let isTest = item.path.hasPrefix("Tests/") || item.path.contains("/Tests/")
        let isFixture = isTest || item.path.hasPrefix("Docs/Parity/Fixtures/")
        try require(nonempty(item.anchor), "Missing evidence anchor: \(item.id)")
        let text = try contents(item.path, repository: repository)
        if isTest && item.path.hasSuffix(".swift") {
            try require(identifier(item.anchor), "Invalid test anchor: \(item.id)")
            let attribute = #"(?:@[A-Za-z_][A-Za-z_0-9]*(?:\([^\n]*\))?\s*)"#
            let pattern = #"(?m)^\s*"# + attribute + #"*@Test\b(?:\([^\n]*\))?\s*"# + attribute
                + #"*(?:(?:private|fileprivate|static|mutating|nonisolated)\s+)*func\s+"#
                + NSRegularExpression.escapedPattern(for: item.anchor) + #"\s*\("#
            try require(text.range(of: pattern, options: .regularExpression) != nil,
                        "Unresolved Swift Testing test evidence: \(item.id)")
        } else if isFixture && item.path.hasSuffix(".json") {
            guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw failure("Evidence fixture must be an object: \(item.id)")
            }
            let ids = (root["cases"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
                ?? [root["id"] as? String].compactMap { $0 }
            try unique(ids, label: "fixture case IDs for \(item.id)")
            try require(ids.contains(item.anchor), "Unresolved fixture case evidence: \(item.id)")
        } else { throw failure("Evidence is not a test or JSON fixture: \(item.id)") }
    }

    /// Reads UTF-8 text only from a regular file contained below the resolved checkout root.
    /// - Parameters:
    ///   - path: Nonempty repository-relative path without dot traversal or absolute prefix.
    ///   - repository: Existing checkout root, resolved before containment comparison.
    ///   - generatedArtifacts: Optional UTF-8 rendered sources used before disk output;
    ///     defaults to empty and never bypasses relative-path or symlink checks.
    /// - Returns: Full file contents; no caching or shared mutable state is retained.
    /// - Throws: File errors or `ReviewedInventoryFailure` for malformed/escaping paths,
    ///   symlinks leaving the root, directories or nonregular filesystem objects.
    private static func contents(_ path: String, repository: URL, generatedArtifacts: [String: Data] = [:]) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        try require(!path.hasPrefix("/") && !components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }), "Invalid repository-relative path")
        let root = repository.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        try require(file.path.hasPrefix(root.path + "/"), "Repository evidence path escapes checkout")
        if let data = generatedArtifacts[path] {
            guard let text = String(data: data, encoding: .utf8) else { throw failure("Generated declaration is not UTF-8") }
            return text
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        try require(attributes[.type] as? FileAttributeType == .typeRegular, "Repository evidence is not a regular file")
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Tests a nonempty human description without altering its meaningful whitespace.
    /// - Parameter text: Candidate metadata string; whitespace-only content is invalid.
    /// - Returns: Whether at least one nonwhitespace character exists.
    private static func nonempty(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Accepts nonempty single-line descriptive metadata without treating it as Swift source.
    /// - Parameter text: A wire name, semantic type or field policy; generics, punctuation and spaces
    ///   are permitted because these values are never emitted as executable declarations.
    /// - Returns: False for blank text, control scalars or Unicode line/paragraph separators;
    ///   true otherwise. No normalization, interpolation or file access occurs.
    private static func safeMetadata(_ text: String) -> Bool {
        nonempty(text) && !text.unicodeScalars.contains {
            [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
        }
    }

    /// Checks the deliberately narrow Swift identifier vocabulary used by generated names.
    /// - Parameter text: Candidate unescaped ASCII Swift name.
    /// - Returns: Whether it starts with an ASCII letter/underscore and contains only
    ///   letters, digits or underscores. Reserved-word escaping belongs to generation.
    private static func identifier(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z_][A-Za-z_0-9]*$"#, options: .regularExpression) != nil
    }

    /// Tests a strict date or an explicitly permitted unknown upstream/local date marker.
    /// - Parameters:
    ///   - value: `YYYY-MM-DD` text or the literal `unknown`.
    ///   - unknown: Whether the marker is permitted at this metadata location.
    /// - Returns: Whether the marker is allowed or a real Gregorian date was supplied.
    private static func validDate(_ value: String, unknown: Bool) -> Bool {
        (unknown && value == "unknown") || day(value) != nil
    }

    /// Converts a strict Gregorian calendar date to an integer UTC day for freshness checks.
    /// - Parameter value: Exactly `YYYY-MM-DD`, with a year in 0001...9999.
    /// - Returns: Days since the Foundation reference date, or `nil` for invalid dates.
    ///   Calendar round trips reject normalization such as February 30 and nonpadded input.
    private static func day(_ value: String) -> Int? {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == parts[0], roundTrip.month == parts[1], roundTrip.day == parts[2] else { return nil }
        return Int(date.timeIntervalSinceReferenceDate / 86_400)
    }

    /// Throws a deterministic reviewed-contract failure when an invariant does not hold.
    /// - Parameters:
    ///   - condition: Already evaluated pure invariant; `true` performs no work.
    ///   - message: Metadata-only explanation of the failed invariant.
    /// - Throws: `ReviewedInventoryFailure` with the supplied message when false.
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }

    /// Constructs the tool's lightweight, metadata-only validation error.
    /// - Parameter message: Human-readable failure reason without credentials or payloads.
    /// - Returns: A value suitable for immediate throwing and CLI diagnostics.
    private static func failure(_ message: String) -> ReviewedInventoryFailure {
        ReviewedInventoryFailure(description: message)
    }
}
