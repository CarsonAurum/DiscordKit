import Foundation

/// One deterministic, UTF-8 output owned exclusively by the reviewed generator.
struct GeneratedArtifact: Equatable, Sendable {
    let path: String
    let data: Data
}

/// The result of comparing or updating the fixed output set; paths are lexically sorted.
struct GeneratorReport: Equatable, Sendable {
    let artifacts: Int
    let changedPaths: [String]
}

/// A safe generation diagnostic containing repository-relative names rather than payloads.
struct GenerationFailure: Error, CustomStringConvertible {
    let description: String
    var changedPaths: [String] = []
}

/// Offline templates for the deliberately small, semantically reviewed API slice.
///
/// Discovery input is never accepted directly. Callers validate reviewed provenance and
/// support evidence before rendering. No template fetches upstream data, edits policies,
/// or executes as part of a consumer package build.
enum Generator {
    static let outputPaths: Set<String> = [
        "Sources/DiscordModels/Generated/HTTPResources.generated.swift",
        "Sources/DiscordHTTP/Generated/DiscordEndpoints.generated.swift",
        "Docs/Generated/ReviewedAPI.md",
        "Docs/Parity/generated-reviewed.md",
        "Tests/DiscordModelsTests/Fixtures/reviewed-cases.json",
    ]

    /// Renders every owned artifact without consulting the filesystem, clock, or network.
    /// - Parameter reviewed: Previously validated reviewed definitions; explicit field order is retained.
    /// - Returns: The complete fixed output set in lexical path order, terminated by one newline.
    /// - Throws: `GenerationFailure` for duplicate IDs, dangling references or unsupported template strategies.
    static func render(_ reviewed: ReviewedInventory) throws -> [GeneratedArtifact] {
        try auditTemplates(reviewed)
        let grouped = Dictionary(grouping: reviewed.definitions, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw GenerationFailure(description: "Duplicate reviewed definition IDs")
        }
        let definitions = grouped.mapValues { $0[0] }
        let models = reviewed.definitions.filter { $0.kind == "model" }.sorted { $0.name < $1.name }
        let enums = reviewed.definitions.filter { $0.kind == "enum" }.sorted { $0.name < $1.name }
        let endpoints = reviewed.definitions.filter { $0.kind == "endpoint" }.sorted { $0.name < $1.name }
        var modelText = header + "import DiscordCore\nimport Foundation\n\n"
        for definition in enums { modelText += try renderEnum(definition, definitions: definitions) + "\n" }
        for definition in models { modelText += try renderModel(definition, definitions: definitions) + "\n" }
        var endpointText = header + "import DiscordModels\nimport Foundation\n\nextension DiscordEndpoints {\n"
        for definition in endpoints { endpointText += try renderEndpoint(definition, definitions: definitions) + "\n" }
        endpointText += "}\n"
        let artifacts: [String: Data] = [
            "Sources/DiscordModels/Generated/HTTPResources.generated.swift": Data(modelText.utf8),
            "Sources/DiscordHTTP/Generated/DiscordEndpoints.generated.swift": Data(endpointText.utf8),
            "Docs/Generated/ReviewedAPI.md": Data(renderDocumentation(reviewed).utf8),
            "Docs/Parity/generated-reviewed.md": Data(renderParity(reviewed).utf8),
            "Tests/DiscordModelsTests/Fixtures/reviewed-cases.json": try renderCases(reviewed),
        ]
        return artifacts.keys.sorted().map { path in
            let text = String(decoding: artifacts[path]!, as: UTF8.self).trimmingCharacters(in: .newlines) + "\n"
            return GeneratedArtifact(path: path, data: Data(text.utf8))
        }
    }

    /// Rejects reviewed contracts that the finite templates cannot implement faithfully.
    ///
    /// This lexical/strategy preflight also runs before virtual symbol validation during a
    /// clean regeneration. Metadata cannot introduce Swift declarations through identifiers,
    /// unsupported types, raw comment text, or a support classification the generator ignores.
    /// - Parameter reviewed: Decoded reviewed graph; full provenance auditing remains separate.
    /// - Throws: `GenerationFailure` for unsafe names, collisions or unsupported contracts.
    private static func auditTemplates(_ reviewed: ReviewedInventory) throws {
        let supported: Set<String> = ["supported", "partial"]
        let types: Set<String> = ["UserID", "ApplicationID", "GuildID", "String", "Bool", "Int", "UInt64", "[String]", "RawValue<PremiumType>", "JSONValue"]
        var typeNames: Set<String> = ["String", "Bool", "Int", "UInt64", "JSONValue", "JSONLimits", "Nullable", "Field", "RawValue", "Data", "Mirror", "Decoder", "Encoder", "CodingKey", "DecodingError", "EncodingError", "UserID", "ApplicationID", "GuildID", "Endpoint", "ReadPolicy", "DiscordError", "Sendable", "Equatable", "Codable", "CustomStringConvertible", "CustomDebugStringConvertible", "CustomReflectable"], endpointNames: Set<String> = []
        for definition in reviewed.definitions where definition.kind != "manual" && definition.kind != "event" {
            guard supported.contains(definition.status) else {
                throw GenerationFailure(description: "Unsupported generation status: \(definition.id)")
            }
            if let model = definition.model {
                guard validIdentifier(definition.name), !types.contains(definition.name), !["Nullable", "Field", "RawValue", "Foundation", "DiscordCore", "DiscordModels"].contains(definition.name), typeNames.insert(definition.name).inserted,
                      ["boundedJSON", "codable"].contains(model.codec ?? "boundedJSON"),
                      model.direction == nil || ["request", "response"].contains(model.direction!),
                      model.codec == "codable" ? ["ignore", "discard"].contains(model.unknownFields) : (model.unknownFields == "preserveExact" && (model.direction ?? "response") == "response") else {
                    throw GenerationFailure(description: "Unsupported model name or codec contract: \(definition.id)")
                }
                guard Set(model.fieldIDs).count == model.fieldIDs.count else {
                    throw GenerationFailure(description: "Duplicate model field references: \(definition.id)")
                }
            }
            if let field = definition.field {
                guard validIdentifier(field.swiftName), types.contains(field.valueType),
                      field.defaultBehavior == (field.optional ? "absent" : "rejectMissing"),
                      Set(field.constraints).isSubset(of: ["objectOnly", "decimalStringUInt64", "integerLexemeNativeRange"]),
                      !["rawFields", "description", "debugDescription", "customMirror", "CodingKeys", "data", "limits", "object", "decoder", "encoder", "values"].contains(field.swiftName),
                      field.valueType != "JSONValue" || field.constraints.contains("objectOnly"),
                      field.valueType != "RawValue<PremiumType>" || reviewed.definitions.contains(where: { $0.name == "PremiumType" && $0.enumeration != nil }) else {
                    throw GenerationFailure(description: "Unsupported Swift field contract: \(definition.id)")
                }
            }
            if let enumeration = definition.enumeration {
                guard validIdentifier(definition.name), !types.contains(definition.name), !["Nullable", "Field", "RawValue", "Foundation", "DiscordCore", "DiscordModels"].contains(definition.name), typeNames.insert(definition.name).inserted,
                      enumeration.unknownValueBehavior == "preserveRaw" else {
                    throw GenerationFailure(description: "Unsupported enum contract: \(definition.id)")
                }
            }
            if let variant = definition.variant, !validIdentifier(variant.swiftName) {
                throw GenerationFailure(description: "Invalid Swift variant name: \(definition.id)")
            }
            if let endpoint = definition.endpoint {
                let segments = endpoint.path.split(separator: "/", omittingEmptySubsequences: false)
                guard validIdentifier(endpoint.swiftName), endpointNames.insert(endpoint.swiftName).inserted,
                      segments.first == "", segments.count > 1,
                      segments.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("{") && !$0.contains("}") && !$0.contains("?") && !$0.contains("#") && !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) }),
                      !endpoint.successStatuses.isEmpty, Set(endpoint.successStatuses).count == endpoint.successStatuses.count,
                      endpoint.successStatuses.allSatisfy({ (200...299).contains($0) }) else {
                    throw GenerationFailure(description: "Unsupported Swift endpoint identity: \(definition.id)")
                }
            }
        }
    }

    /// Checks the ASCII Swift identifier vocabulary while rejecting reserved or generated names.
    /// - Parameter value: Unescaped reviewed type/member name; Unicode and keyword names need a future strategy.
    /// - Returns: Whether the name can be emitted verbatim as a single Swift identifier.
    private static func validIdentifier(_ value: String) -> Bool {
        let reserved: Set<String> = ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while", "as", "Any", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try", "_", "Type", "Protocol", "DiscordEndpoints", "ResourceObject"]
        return value.range(of: #"^[A-Za-z_][A-Za-z_0-9]*$"#, options: .regularExpression) != nil && !reserved.contains(value)
    }

    /// Compares or explicitly regenerates the reviewed output set after rendering succeeds.
    /// - Parameters:
    ///   - repository: Existing repository directory; its resolved location bounds all outputs.
    ///   - reviewed: Reviewed input whose provenance and links were validated by the CLI.
    ///   - check: `true` compares bytes and never writes; `false` writes changed allowlisted outputs.
    /// - Returns: Artifact count and sorted changed paths; successful checks have no changes.
    /// - Throws: Rendering/filesystem failures, unsafe paths, or `GenerationFailure` listing missing/stale outputs.
    static func run(repository: URL, reviewed: ReviewedInventory, check: Bool) throws -> GeneratorReport {
        try apply(render(reviewed), repository: repository, check: check)
    }

    /// Applies the fixed output set only after every destination passes the path audit.
    ///
    /// Checks never create directories, repair artifacts or touch modification times. Writes
    /// replace changed files atomically; a filesystem failure can leave earlier outputs updated,
    /// so callers rerun check after resolving the failure. Repository edits must not race this operation.
    /// - Parameters:
    ///   - artifacts: Exactly one artifact for each hardcoded owned path; arbitrary destinations fail.
    ///   - repository: Existing repository root, resolved once before destination traversal.
    ///   - check: Whether differing bytes produce a failure instead of writes.
    /// - Returns: A deterministic comparison/update report.
    /// - Throws: `GenerationFailure` for an unsafe output set, symlink, directory target or stale check; I/O errors otherwise.
    static func apply(_ artifacts: [GeneratedArtifact], repository: URL, check: Bool) throws -> GeneratorReport {
        guard artifacts.count == outputPaths.count, Set(artifacts.map(\.path)) == outputPaths else {
            throw GenerationFailure(description: "Generation must use exactly the fixed output allowlist")
        }
        let root = repository.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GenerationFailure(description: "Generation repository is not an existing directory")
        }
        let ordered = artifacts.sorted { $0.path < $1.path }
        for artifact in ordered { try auditDestination(artifact.path, repository: root) }
        var changed: [GeneratedArtifact] = []
        for artifact in ordered {
            let url = root.appendingPathComponent(artifact.path)
            if try !FileManager.default.fileExists(atPath: url.path) || Data(contentsOf: url) != artifact.data {
                changed.append(artifact)
            }
        }
        let paths = changed.map(\.path)
        if check, !paths.isEmpty {
            throw GenerationFailure(description: "Generated output differs: " + paths.joined(separator: ", "), changedPaths: paths)
        }
        if !check {
            for artifact in changed {
                let url = root.appendingPathComponent(artifact.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try artifact.data.write(to: url, options: .atomic)
            }
        }
        return GeneratorReport(artifacts: artifacts.count, changedPaths: paths)
    }

    /// Rejects links at the destination and every existing parent before any write begins.
    /// - Parameters:
    ///   - path: One hardcoded relative output name.
    ///   - repository: Canonical existing root; output components cannot escape it.
    /// - Throws: `GenerationFailure` for links, nondirectory parents or directory outputs; I/O errors otherwise.
    private static func auditDestination(_ path: String, repository: URL) throws {
        var current = repository
        let components = path.split(separator: "/")
        for (index, component) in components.enumerated() {
            current.appendPathComponent(String(component))
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                let type = attributes[.type] as? FileAttributeType
                guard type != .typeSymbolicLink else {
                    throw GenerationFailure(description: "Generated output traverses a symlink: \(path)")
                }
                let last = index == components.count - 1
                guard last ? type == .typeRegular : type == .typeDirectory else {
                    throw GenerationFailure(description: "Generated output has an invalid file kind: \(path)")
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return
            }
        }
    }

    private static let header = "// Generated by DiscordKitTools from Docs/Parity/reviewed-v1.json. Do not edit.\n// Regenerate explicitly with: swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --write --repository .\n\n"

    /// Emits a line-safe Swift documentation block from reviewed prose.
    /// - Parameters:
    ///   - text: Plain reviewed prose; embedded newlines begin separate comment lines.
    ///   - indentation: Leading spaces for a member declaration, defaulting to top level.
    /// - Returns: A documentation block that cannot terminate its own comments.
    private static func documentation(_ text: String, indentation: String = "") -> String {
        text.components(separatedBy: .newlines).map { indentation + "///" + ($0.isEmpty ? "" : " " + $0) }.joined(separator: "\n") + "\n"
    }

    /// Looks up typed field members in their explicit reviewed declaration order.
    /// - Parameters:
    ///   - definition: A model definition with field-ID references.
    ///   - definitions: Unique reviewed definitions by stable ID.
    /// - Returns: Field definitions in model order; empty records are supported by Codable templates.
    /// - Throws: `GenerationFailure` for missing model metadata, field links or mismatched ownership.
    private static func fields(_ definition: ReviewedDefinition, definitions: [String: ReviewedDefinition]) throws -> [ReviewedDefinition] {
        guard let model = definition.model else { throw GenerationFailure(description: "Model metadata missing: \(definition.id)") }
        return try model.fieldIDs.map { id in
            guard let field = definitions[id], field.field?.modelID == definition.id else {
                throw GenerationFailure(description: "Model field link missing: \(id)")
            }
            return field
        }
    }

    /// Maps optionality and nullability independently into the runtime's reviewed field wrappers.
    /// - Parameter field: Reviewed field metadata with a supported payload type.
    /// - Returns: `Field<T>` for omittable keys, `Nullable<T>` for required nullable keys, otherwise `T`.
    private static func swiftType(_ field: ReviewedField) -> String {
        field.optional ? "Field<\(field.valueType)>" : (field.nullable ? "Nullable<\(field.valueType)>" : field.valueType)
    }

    /// Renders either an exact bounded response projection or an ordinary presence-aware Codable record.
    /// - Parameters:
    ///   - definition: Reviewed model, whose strategy defaults to bounded JSON responses.
    ///   - definitions: Complete unique reviewed definition lookup.
    /// - Returns: A public struct with documented parsing/encoding behavior and redacted diagnostics.
    /// - Throws: `GenerationFailure` for unsupported strategies or missing linked fields.
    private static func renderModel(_ definition: ReviewedDefinition, definitions: [String: ReviewedDefinition]) throws -> String {
        let members = try fields(definition, definitions: definitions)
        guard let model = definition.model, ["boundedJSON", "codable"].contains(model.codec ?? "boundedJSON") else {
            throw GenerationFailure(description: "Unsupported model codec: \(definition.id)")
        }
        let codable = model.codec == "codable"
        var result = documentation(definition.notes)
        result += "public struct \(definition.name): Sendable, Equatable, " + (codable ? "Codable, " : "") + "CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {\n"
        for member in members {
            let field = member.field!
            result += documentation(member.notes + " Missing key behavior: " + field.defaultBehavior + ". Access: " + field.access + ". Constraints: " + (field.constraints.isEmpty ? "wire type only" : field.constraints.joined(separator: ", ")) + ". Unknown values: " + field.unknownValueBehavior + ".", indentation: "    ")
            result += "    public let \(field.swiftName): \(swiftType(field))\n"
        }
        if codable {
            result += try renderCodable(members)
        } else {
            result += "    /// Complete original object, including unmodeled fields and exact numeric lexemes.\n    public let rawFields: [String: JSONValue]\n\n"
            result += "    /// Parses an API v10 snapshot synchronously under explicit byte, depth and node bounds.\n    /// - Parameters:\n    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present.\n    ///   - limits: Parsing and per-field bounds; defaults to 1 MiB, depth 64 and 100,000 nodes.\n    /// - Throws: Safe JSON errors or `DiscordError.transport(.invalidResponse)` for missing, null-forbidden,\n    ///   malformed or out-of-range modeled fields. Unknown fields retain their exact JSON values.\n    ///\n    /// No I/O, suspension, credential access or lifecycle changes occur. Nested unmodeled\n    /// payloads remain partial; response strings are not authorization or destination validation.\n    public init(data: Data, limits: JSONLimits = .default) throws {\n        let object = try ResourceObject(data: data, limits: limits)\n"
            for member in members {
                let field = member.field!
                if field.constraints.contains("objectOnly") {
                    guard field.valueType == "JSONValue", !field.optional, field.nullable else {
                        throw GenerationFailure(description: "Unsupported object constraint: \(member.id)")
                    }
                    result += "        \(field.swiftName) = try object.nullableObject(\(literal(field.wireName)))\n"
                } else if field.optional {
                    result += "        \(field.swiftName) = try object.field(\(literal(field.wireName)), as: \(field.valueType).self" + (field.nullable ? ", nullable: true" : "") + ")\n"
                } else {
                    result += "        \(field.swiftName) = try object.required(\(literal(field.wireName)), as: \(swiftType(field)).self)\n"
                }
            }
            result += "        rawFields = object.fields\n    }\n"
        }
        result += "\n    /// Redacts modeled fields and raw payloads from ordinary diagnostics.\n    public var description: String { \(literal(definition.name + "(redacted)")) }\n    /// Uses the same redacted marker during debug formatting.\n    public var debugDescription: String { description }\n    /// Prevents reflection-based diagnostics from expanding sensitive payloads.\n    public var customMirror: Mirror { Mirror(self, children: [\"redacted\": true]) }\n}\n"
        return result
    }

    /// Emits ordinary keyed Codable methods preserving omission and enforcing reviewed nullability.
    ///
    /// This strategy intentionally discards unknown keys; exact JSON response projections use
    /// `boundedJSON` instead. It introduces no payload limits or endpoint validation on its own.
    /// - Parameter members: Reviewed fields in their declaration order.
    /// - Returns: Documented memberwise initialization, keys and Codable methods.
    /// - Throws: `GenerationFailure` when exact JSON/object constraints require the bounded strategy.
    private static func renderCodable(_ members: [ReviewedDefinition]) throws -> String {
        guard members.allSatisfy({ $0.field!.valueType != "JSONValue" && !$0.field!.constraints.contains("objectOnly") }) else {
            throw GenerationFailure(description: "Exact JSON fields require the boundedJSON codec")
        }
        var text = "\n    /// Creates a typed record without I/O; endpoint-specific validation remains separate.\n"
        if !members.isEmpty { text += "    /// - Parameters:\n" }
        for member in members { text += documentation("  - \(member.field!.swiftName): \(member.notes)", indentation: "    ") }
        text += "    public init(" + members.map { "\($0.field!.swiftName): \(swiftType($0.field!))" + ($0.field!.optional ? " = .absent" : "") }.joined(separator: ", ") + ") {\n"
        for member in members { text += "        self.\(member.field!.swiftName) = \(member.field!.swiftName)\n" }
        text += "    }\n\n    /// Exact API member spellings; unknown keys are intentionally not retained by this codec.\n    private enum CodingKeys: String, CodingKey {\n"
        for member in members { text += "        case \(member.field!.swiftName) = \(literal(member.field!.wireName))\n" }
        text += "    }\n\n    /// Decodes required keys and distinct optional absence/null states synchronously.\n    /// - Parameter decoder: Decoder positioned at the record object; unknown keys are ignored.\n    /// - Throws: `DecodingError` for missing, malformed or illegally null reviewed fields.\n    public init(from decoder: any Decoder) throws {\n        let values = try decoder.container(keyedBy: CodingKeys.self)\n"
        for member in members {
            let field = member.field!
            text += "        \(field.swiftName) = try values." + (field.optional ? "decodeField(\(field.valueType).self" : "decode(\(swiftType(field)).self") + ", forKey: .\(field.swiftName))\n"
            if field.optional, !field.nullable {
                text += "        if case .null = \(field.swiftName) {\n            throw DecodingError.valueNotFound(\(field.valueType).self, .init(codingPath: values.codingPath + [CodingKeys.\(field.swiftName)], debugDescription: \"Null is not permitted\"))\n        }\n"
            }
        }
        text += "    }\n\n    /// Encodes required keys and preserves omission without collapsing explicit null.\n    /// - Parameter encoder: Destination encoder; this codec supplies no transport or byte limits.\n    /// - Throws: Encoder failures or `EncodingError` for null in a nonnullable optional field.\n    public func encode(to encoder: any Encoder) throws {\n        var values = encoder.container(keyedBy: CodingKeys.self)\n"
        for member in members {
            let field = member.field!
            if field.optional, !field.nullable {
                text += "        if case .null = \(field.swiftName) {\n            throw EncodingError.invalidValue(\(field.swiftName), .init(codingPath: values.codingPath + [CodingKeys.\(field.swiftName)], debugDescription: \"Null is not permitted\"))\n        }\n"
            }
            text += "        try values." + (field.optional ? "encodeField" : "encode") + "(\(field.swiftName), forKey: .\(field.swiftName))\n"
        }
        return text + "    }\n"
    }

    /// Emits an extensible integer enum whose consumers preserve future values with `RawValue`.
    /// - Parameters:
    ///   - definition: Reviewed integer enum metadata.
    ///   - definitions: Unique reviewed definitions by ID.
    /// - Returns: Documented variants sorted numerically and then by Swift name.
    /// - Throws: `GenerationFailure` for dangling or nonreciprocal variant references.
    private static func renderEnum(_ definition: ReviewedDefinition, definitions: [String: ReviewedDefinition]) throws -> String {
        guard let metadata = definition.enumeration else { throw GenerationFailure(description: "Enum metadata missing: \(definition.id)") }
        let variants = try metadata.variantIDs.map { id -> ReviewedDefinition in
            guard let variant = definitions[id], variant.variant?.enumID == definition.id else {
                throw GenerationFailure(description: "Enum variant link missing: \(id)")
            }
            return variant
        }.sorted { ($0.variant!.rawValue, $0.variant!.swiftName) < ($1.variant!.rawValue, $1.variant!.swiftName) }
        var text = documentation(definition.notes) + "public enum \(definition.name): Int, Sendable {\n"
        for variant in variants {
            text += documentation(variant.notes, indentation: "    ")
            text += "    case \(variant.variant!.swiftName) = \(variant.variant!.rawValue)\n"
        }
        return text + "}\n"
    }

    /// Emits only the safe, bodyless GET descriptor strategy reviewed for this phase.
    /// - Parameters:
    ///   - definition: Reviewed endpoint including authentication and success statuses.
    ///   - definitions: Unique definition lookup for the bounded response model.
    /// - Returns: A documented descriptor method; runtime rate/retry/lifecycle policy stays handwritten.
    /// - Throws: `GenerationFailure` for unsupported mutations, requests, retry policy or response codecs.
    private static func renderEndpoint(_ definition: ReviewedDefinition, definitions: [String: ReviewedDefinition]) throws -> String {
        guard let endpoint = definition.endpoint, endpoint.method == "GET", endpoint.requestModelID == "none",
              endpoint.retry == "safe", endpoint.pagination == "none",
              ["bot", "botOrBearer", "bearer", "none"].contains(endpoint.authentication),
              let response = definitions[endpoint.responseModelID], response.model != nil,
              response.model?.codec != "codable" else {
            throw GenerationFailure(description: "Unsupported endpoint template: \(definition.id)")
        }
        let path = endpoint.path.split(separator: "/").map { literal(String($0)) }.joined(separator: ", ")
        let statuses = endpoint.successStatuses.sorted().map(String.init).joined(separator: ", ")
        let prose = definition.notes + "\n- Parameter readPolicy: Eligible-read reuse; defaults to in-flight coalescing without a completed-result cache.\n  A caller-selected positive TTL may serve stale authorization-scoped data until expiry.\n- Returns: An immutable API v10 descriptor; no request starts during construction.\n- Throws: Descriptor validation errors, including nonpositive freshness TTLs.\n\nRate limits: " + endpoint.rateLimit + "\nRetry safety: " + endpoint.retry + ". Pagination: " + endpoint.pagination + "."
        return documentation(prose, indentation: "    ") + "    public static func \(endpoint.swiftName)(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<\(response.name)> {\n        try Endpoint(method: \(literal(endpoint.method)), path: [\(path)], authentication: .\(endpoint.authentication),\n                     successStatuses: [\(statuses)], retrySafety: .safe, readPolicy: readPolicy, decode: { try \(response.name)(data: $0) })\n    }\n"
    }

    /// Quotes reviewed wire strings as valid Swift source without enabling interpolation.
    /// - Parameter value: Reviewed literal text; all control scalars and backslashes are escaped.
    /// - Returns: A Swift string literal safe for generated paths, names and markers.
    private static func literal(_ value: String) -> String {
        var text = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: text += "\\\""
            case 92: text += "\\\\"
            case 0...31, 127: text += "\\u{\(String(scalar.value, radix: 16))}"
            default: text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }

    /// Renders a reviewed API reference starting structure directly from per-definition metadata.
    /// - Parameter reviewed: Previously validated seed with source and evidence links.
    /// - Returns: Deterministic Markdown documenting the slice, omissions and behavior boundaries.
    private static func renderDocumentation(_ reviewed: ReviewedInventory) -> String {
        var text = "<!-- Generated by DiscordKitTools; edit reviewed-v1.json and regenerate. -->\n# Reviewed API slice\n\nVerified \(reviewed.verifiedOn), Discord API v10. This starting reference describes a reviewed partial slice, not full API parity. Runtime response projections use bounded exact JSON parsing; they do not promise a generic Codable round trip.\n\n"
        for definition in reviewed.definitions.filter({ ["model", "enum", "endpoint", "manual", "event"].contains($0.kind) }).sorted(by: { $0.id < $1.id }) {
            text += "## \(definition.name)\n\n\(definition.notes)\n\nStatus: \(definition.status). Support since: \(definition.supportSince). Source: \(definition.sourceID). Upstream announcement: \(definition.announcementDate); effective: \(definition.effectiveDate).\n\n"
            if let model = definition.model {
                text += "Codec: \(model.codec ?? "boundedJSON"); direction: \(model.direction ?? "response"); unknown fields: \(model.unknownFields). Omitted typed definitions: \(model.omittedUpstreamIDs.count).\n\n| Wire key | Swift member | Payload | Optional | Nullable | Access |\n| --- | --- | --- | --- | --- | --- |\n"
                let byID = Dictionary(uniqueKeysWithValues: reviewed.definitions.map { ($0.id, $0) })
                for id in model.fieldIDs {
                    if let field = byID[id]?.field { text += "| \(field.wireName) | \(field.swiftName) | \(field.valueType) | \(field.optional) | \(field.nullable) | \(field.access) |\n" }
                }
                text += "\n"
            }
            if let endpoint = definition.endpoint {
                text += "`\(endpoint.method) /\(endpoint.path.dropFirst())`; authentication: \(endpoint.authentication); success: \(endpoint.successStatuses.sorted()); documented errors: \(endpoint.errorStatuses.sorted()). Retry: \(endpoint.retry); pagination: \(endpoint.pagination).\n\n\(endpoint.rateLimit)\n\n"
            }
            if let event = definition.event {
                text += "Payload model: \(event.payloadModelID). Related variants: " + event.variantIDs.sorted().joined(separator: ", ") + ".\n\nHandwritten event behavior: " + event.behavior + "\n\n"
            }
            text += "Evidence: " + definition.evidenceIDs.sorted().joined(separator: ", ") + ".\n\n"
        }
        return text
    }

    /// Summarizes the reviewed subset separately from the unreviewed discovery denominator.
    /// - Parameter reviewed: Validated reviewed inventory; definitions are sorted by stable ID.
    /// - Returns: Markdown with explicit status, upstream and symbol/evidence mappings.
    private static func renderParity(_ reviewed: ReviewedInventory) -> String {
        var text = "<!-- Generated by DiscordKitTools; edit reviewed-v1.json and regenerate. -->\n# Generated reviewed coverage\n\nVerified \(reviewed.verifiedOn). These \(reviewed.definitions.count) reviewed records are a selected subset of discovery. Counts are not full API parity, and no transport capacity claim follows from them. Discovery and reviewed counts are reported separately by `parity check`.\n\n| Definition | Kind | Status | Upstream records | Symbols | Evidence |\n| --- | --- | --- | ---: | ---: | ---: |\n"
        for definition in reviewed.definitions.sorted(by: { $0.id < $1.id }) {
            text += "| \(definition.id) | \(definition.kind) | \(definition.status) | \(definition.upstreamIDs.count) | \(definition.symbolIDs.count) | \(definition.evidenceIDs.count) |\n"
        }
        text += "\nGenerated model and endpoint declarations are committed. Authentication, rate coordination, cancellation, retry budgets, Gateway lifecycle and exact JSON parsing remain handwritten and independently tested.\n"
        return text
    }

    /// Builds the case index linking each field's required/presence contract to real test evidence.
    /// - Parameter reviewed: Validated definitions and evidence IDs; no untrusted payloads are emitted.
    /// - Returns: Canonically sorted, pretty-printed UTF-8 JSON with a trailing newline.
    /// - Throws: Foundation serialization errors if a template accidentally emits invalid JSON values.
    private static func renderCases(_ reviewed: ReviewedInventory) throws -> Data {
        var cases: [[String: Any]] = []
        for definition in reviewed.definitions.sorted(by: { $0.id < $1.id }) {
            guard let field = definition.field else { continue }
            let scenarios = ["value", field.optional ? "absent" : "missingRejected", field.nullable ? "null" : "nullRejected", "wrongTypeRejected"]
            for scenario in scenarios {
                cases.append(["id": definition.id + "." + scenario, "definitionID": definition.id,
                              "scenario": scenario, "wireName": field.wireName, "valueType": field.valueType,
                              "modelName": reviewed.definitions.first(where: { $0.id == field.modelID })!.name,
                              "optional": field.optional, "nullable": field.nullable,
                              "evidenceIDs": definition.evidenceIDs.sorted()])
            }
        }
        let root: [String: Any] = ["schemaVersion": 1, "verifiedOn": reviewed.verifiedOn, "cases": cases]
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(10)
        return data
    }
}
