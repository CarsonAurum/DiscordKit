// File: Tools/DiscordKitTools/Tests/DiscordKitToolsTests/GeneratorTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordKitTools

/// Verifies pure rendering, nonwriting checks, bounded writes and actual Codable template execution.
@Suite("Reviewed code generation") struct GeneratorTests {
    /// Independent input-array order never changes bytes; field reference order remains intentional.
    /// - Throws: Reviewed fixture decoding or generation errors if the committed seed is inconsistent.
    @Test func deterministicRenderingAndCaseIndex() throws {
        let reviewed = try seed()
        let first = try Generator.render(reviewed)
        let reordered = ReviewedInventory(schemaVersion: reviewed.schemaVersion, verifiedOn: reviewed.verifiedOn,
            maxAgeDays: reviewed.maxAgeDays, sources: reviewed.sources.reversed(), definitions: reviewed.definitions.reversed(),
            symbols: reviewed.symbols.reversed(), evidence: reviewed.evidence.reversed())
        #expect(first == (try Generator.render(reordered)))
        #expect(Set(first.map(\.path)) == Generator.outputPaths)
        #expect(first.map(\.path) == first.map(\.path).sorted())
        for artifact in first {
            #expect(artifact.data.last == 10)
            #expect(!artifact.data.suffix(2).elementsEqual([10, 10]))
        }
        let index = try #require(first.first { $0.path.hasSuffix("reviewed-cases.json") })
        let object = try #require(JSONSerialization.jsonObject(with: index.data) as? [String: Any])
        let cases = try #require(object["cases"] as? [[String: Any]])
        #expect(cases.count == 128)
        #expect(Set(cases.compactMap { $0["id"] as? String }).count == cases.count)
        let endpoint = try #require(first.first { $0.path.hasSuffix("DiscordEndpoints.generated.swift") })
        #expect(String(decoding: endpoint.data, as: UTF8.self).contains("successStatuses: [200]"))
    }

    /// A stale/missing check leaves all bytes and mtimes unchanged and creates no missing directories.
    /// - Throws: Local temporary-file or generation failures when expected success setup cannot be established.
    @Test func checkNeverWritesAndWriteIsIdempotent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = try Generator.render(seed())
        do {
            _ = try Generator.apply(artifacts, repository: directory, check: true)
            Issue.record("A missing output set unexpectedly passed")
        } catch let error as GenerationFailure {
            #expect(error.changedPaths == artifacts.map(\.path))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let written = try Generator.apply(artifacts, repository: directory, check: false)
        #expect(written.changedPaths == artifacts.map(\.path))
        let target = directory.appendingPathComponent(artifacts[0].path)
        let sentinel = Data("stale\n".utf8)
        try sentinel.write(to: target)
        let date = Date(timeIntervalSince1970: 1_234_567_890)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        #expect(throws: GenerationFailure.self) { try Generator.apply(artifacts, repository: directory, check: true) }
        #expect(try Data(contentsOf: target) == sentinel)
        #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date == date)
        #expect(try Generator.apply(artifacts, repository: directory, check: false).changedPaths == [artifacts[0].path])
        let unchanged = try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date
        #expect(try Generator.apply(artifacts, repository: directory, check: false).changedPaths.isEmpty)
        #expect(try Generator.apply(artifacts, repository: directory, check: true).changedPaths.isEmpty)
        #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date == unchanged)
        #expect(try Generator.run(repository: directory, reviewed: seed(), check: true).artifacts == 5)
    }

    /// Extra outputs, duplicate paths and symlinked parents/targets fail before any owned file changes.
    /// - Parameter kind: The output-set or path violation applied to an otherwise valid generation.
    /// - Throws: Temporary setup or rendering errors; the audited generation must fail safely.
    @Test(arguments: ["extra", "duplicate", "parentLink", "targetLink", "brokenLink", "directory", "missingRoot"])
    func rejectsUnsafeDestinations(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var artifacts = try Generator.render(seed())
        var repository = directory
        switch kind {
        case "extra": artifacts.append(GeneratedArtifact(path: "unowned.swift", data: Data()))
        case "duplicate": artifacts[0] = artifacts[1]
        case "missingRoot": repository = directory.appendingPathComponent("missing")
        default:
            let chosen = artifacts.first { $0.path.hasPrefix("Sources/DiscordModels/") }!
            let destination = directory.appendingPathComponent(chosen.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch kind {
            case "parentLink":
                let parent = destination.deletingLastPathComponent()
                try FileManager.default.removeItem(at: parent)
                try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: directory)
            case "directory": try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            case "brokenLink": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: directory.appendingPathComponent("absent"))
            default: try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: directory)
            }
        }
        #expect(throws: GenerationFailure.self) { try Generator.apply(artifacts, repository: repository, check: false) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Docs/Generated/ReviewedAPI.md").path))
    }

    /// Invalid generation contracts fail explicitly instead of emitting invalid or misleading Swift.
    /// - Parameter mutation: One lexical, graph, policy or support violation.
    /// - Throws: Fixture mutation/decoding failures; rendering must throw a safe generation error.
    @Test(arguments: ["status", "keyword", "invalidName", "fieldType", "collision", "codec", "unknownPolicy", "fieldLink", "variantLink", "duplicateID", "objectConstraint", "mutation", "request", "pagination", "path", "enumPolicy", "boundedRequest", "missingEnum", "shadowCoreType", "shadowFoundationType", "default", "constraint", "boundedLocal", "codableLocal", "helperType", "namespaceType"])
    func rejectsUnsupportedTemplates(mutation: String) throws {
        var object = try seedObject()
        var definitions = object["definitions"] as! [[String: Any]]
        let model = definitions.firstIndex { $0["id"] as? String == "model.User" }!
        let field = definitions.firstIndex { $0["id"] as? String == "field.User.username" }!
        let endpoint = definitions.firstIndex { $0["kind"] as? String == "endpoint" }!
        let enumeration = definitions.firstIndex { $0["kind"] as? String == "enum" }!
        switch mutation {
        case "status": definitions[field]["status"] = "unsupported"
        case "keyword": var value = definitions[field]["field"] as! [String: Any]; value["swiftName"] = "class"; definitions[field]["field"] = value
        case "invalidName": definitions[model]["name"] = "User {}"
        case "collision": definitions[model]["name"] = "Application"
        case "helperType": definitions[model]["name"] = "ResourceObject"
        case "namespaceType": definitions[model]["name"] = "DiscordEndpoints"
        case "boundedLocal": var value = definitions[field]["field"] as! [String: Any]; value["swiftName"] = "object"; definitions[field]["field"] = value
        case "codableLocal": var value = definitions[field]["field"] as! [String: Any]; value["swiftName"] = "values"; definitions[field]["field"] = value
        case "shadowCoreType": definitions[model]["name"] = "Nullable"
        case "shadowFoundationType": definitions[model]["name"] = "Mirror"
        case "default": var value = definitions[field]["field"] as! [String: Any]; value["defaultBehavior"] = "inventedDefault"; definitions[field]["field"] = value
        case "constraint": var value = definitions[field]["field"] as! [String: Any]; value["constraints"] = ["inventedValidation"]; definitions[field]["field"] = value
        case "fieldType": var value = definitions[field]["field"] as! [String: Any]; value["valueType"] = "String; unsafe()"; definitions[field]["field"] = value
        case "codec": var value = definitions[model]["model"] as! [String: Any]; value["codec"] = "unknown"; definitions[model]["model"] = value
        case "unknownPolicy": var value = definitions[model]["model"] as! [String: Any]; value["unknownFields"] = "ignore"; definitions[model]["model"] = value
        case "boundedRequest": var value = definitions[model]["model"] as! [String: Any]; value["direction"] = "request"; definitions[model]["model"] = value
        case "missingEnum": definitions.remove(at: enumeration)
        case "fieldLink": var value = definitions[model]["model"] as! [String: Any]; value["fieldIDs"] = ["missing"]; definitions[model]["model"] = value
        case "variantLink": var value = definitions[enumeration]["enum"] as! [String: Any]; value["variantIDs"] = ["missing"]; definitions[enumeration]["enum"] = value
        case "enumPolicy": var value = definitions[enumeration]["enum"] as! [String: Any]; value["unknownValueBehavior"] = "discard"; definitions[enumeration]["enum"] = value
        case "duplicateID": definitions.append(definitions[0])
        case "objectConstraint": var value = definitions[field]["field"] as! [String: Any]; value["constraints"] = ["objectOnly"]; definitions[field]["field"] = value
        default:
            var value = definitions[endpoint]["endpoint"] as! [String: Any]
            if mutation == "mutation" { value["method"] = "POST" }
            if mutation == "request" { value["requestModelID"] = "model.User" }
            if mutation == "pagination" { value["pagination"] = "cursor" }
            if mutation == "path" { value["path"] = "/users/../@me" }
            definitions[endpoint]["endpoint"] = value
        }
        object["definitions"] = definitions
        let reviewed = try ReviewedInventoryValidator.load(reviewedData: JSONSerialization.data(withJSONObject: object))
        #expect(throws: GenerationFailure.self) { try Generator.render(reviewed) }
    }

    /// Multiline reviewed prose stays entirely inside comments, including code-looking lines.
    /// - Throws: Seed decoding or rendering errors; output must contain safely prefixed prose.
    @Test func documentationCannotInjectDeclarations() throws {
        var object = try seedObject()
        var definitions = object["definitions"] as! [[String: Any]]
        let index = definitions.firstIndex { $0["kind"] as? String == "endpoint" }!
        var endpoint = definitions[index]["endpoint"] as! [String: Any]
        endpoint["rateLimit"] = "first\npublic func injected() {}"
        definitions[index]["notes"] = "Reviewed\npublic func injectedAgain() {}"
        definitions[index]["endpoint"] = endpoint
        object["definitions"] = definitions
        let artifacts = try Generator.render(ReviewedInventoryValidator.load(reviewedData: JSONSerialization.data(withJSONObject: object)))
        let text = String(decoding: artifacts.first { $0.path.hasSuffix("DiscordEndpoints.generated.swift") }!.data, as: UTF8.self)
        #expect(text.contains("    /// public func injected() {}"))
        #expect(text.contains("    /// public func injectedAgain() {}"))
        #expect(!text.contains("\npublic func injected"))
    }

    /// Handwritten event metadata contributes documentation without generating runtime delivery APIs.
    /// - Throws: Synthetic event decoding or rendering errors.
    @Test func eventDocumentationRemainsHandwritten() throws {
        var object = try seedObject()
        var definitions = object["definitions"] as! [[String: Any]]
        var event = common(id: "event.Fixture", kind: "event", name: "FixtureEvent")
        event["status"] = "unsupported"
        event["event"] = ["payloadModelID": "model.User", "variantIDs": ["variant.PremiumType.none"], "behavior": "No handler is generated."]
        definitions.append(event)
        object["definitions"] = definitions
        let artifacts = try Generator.render(ReviewedInventoryValidator.load(reviewedData: JSONSerialization.data(withJSONObject: object)))
        let documentation = String(decoding: artifacts.first { $0.path.hasSuffix("ReviewedAPI.md") }!.data, as: UTF8.self)
        #expect(documentation.contains("Payload model: model.User"))
        #expect(documentation.contains("Handwritten event behavior: No handler is generated."))
        for artifact in artifacts where artifact.path.hasSuffix(".swift") {
            #expect(!String(decoding: artifact.data, as: UTF8.self).contains("FixtureEvent"))
        }
    }

    /// Compiles and executes generated request and response Codable strategies with actual Core wrappers.
    ///
    /// The smoke program checks missing required nullable keys, explicit null, omitted fields,
    /// unknown-key discard, wrong types, forbidden optional nulls, encode-time validation and
    /// memberwise defaults. It uses only local compiler processes and a unique temporary directory.
    /// - Throws: Setup, compiler, runtime or generation failures; no network/package resolution occurs.
    @Test func ordinaryCodableTemplatesCompileAndRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let object = codableObject()
        let reviewed = try ReviewedInventoryValidator.load(reviewedData: JSONSerialization.data(withJSONObject: object))
        let artifact = try #require(Generator.render(reviewed).first { $0.path.hasSuffix("HTTPResources.generated.swift") })
        let generated = directory.appendingPathComponent("Generated.swift")
        try artifact.data.write(to: generated)
        let core = repository().appendingPathComponent("Sources/DiscordCore/Field.swift")
        _ = try run(["swiftc", "-swift-version", "6", "-emit-library", "-emit-module", "-module-name", "DiscordCore", core.path,
                     "-o", directory.appendingPathComponent("libDiscordCore.dylib").path,
                     "-emit-module-path", directory.appendingPathComponent("DiscordCore.swiftmodule").path], directory: directory)
        let main = directory.appendingPathComponent("main.swift")
        try Data(codableSmoke.utf8).write(to: main)
        let executable = directory.appendingPathComponent("smoke")
        _ = try run(["swiftc", "-swift-version", "6", "-I", directory.path, "-L", directory.path, "-lDiscordCore",
                     "-Xlinker", "-rpath", "-Xlinker", directory.path, generated.path, main.path, "-o", executable.path], directory: directory)
        #expect(try run([executable.path], directory: directory).contains("codable smoke passed"))
    }

    /// Finds the checkout independently of process working directory.
    /// - Returns: Repository root derived from this test's source location.
    private func repository() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Reads the frozen generation seed as an editable dictionary for independent mutations.
    /// The fixture retains positive model/endpoint generation coverage for runtime models with handwritten codecs.
    /// - Returns: The root reviewed JSON object.
    /// - Throws: File, JSON or setup-container failures.
    private func seedObject() throws -> [String: Any] {
        let data = try Data(contentsOf: repository().appendingPathComponent("Tools/DiscordKitTools/Tests/DiscordKitToolsTests/Fixtures/generation-seed.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Loads the frozen generation seed without semantic filesystem validation.
    /// Keeping this input independent of the runtime inventory preserves positive template coverage as models evolve.
    /// - Returns: Closed-schema reviewed data for pure generation tests.
    /// - Throws: File-read, JSON or schema errors.
    private func seed() throws -> ReviewedInventory {
        try ReviewedInventoryValidator.load(reviewedData: Data(contentsOf: repository().appendingPathComponent("Tools/DiscordKitTools/Tests/DiscordKitToolsTests/Fixtures/generation-seed.json")))
    }

    /// Allocates an isolated, empty temporary root for one filesystem/compiler test.
    /// - Returns: A newly created unique directory owned by the caller.
    /// - Throws: Filesystem creation errors; callers remove the directory with `defer`.
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DiscordKitGenerator-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs a local executable through env and captures bounded compiler/runtime diagnostics.
    /// - Parameters:
    ///   - arguments: Executable name/path and literal arguments; no shell expansion occurs.
    ///   - directory: Unique working directory; inherited compiler caches are unchanged.
    /// - Returns: Complete UTF-8 stdout/stderr for these finite fixture processes.
    /// - Throws: Launch failures or `GenerationFailure` for a nonzero child status.
    private func run(_ arguments: [String], directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GenerationFailure(description: "Generated fixture process failed: " + output) }
        return output
    }

    /// Constructs independent request/response records exercising all four field-presence combinations.
    /// - Returns: Synthetic reviewed-shaped definitions used only by rendering, without upstream support claims.
    private func codableObject() -> [String: Any] {
        var definitions: [[String: Any]] = []
        for direction in ["Request", "Response"] {
            let modelID = "model.Fixture" + direction
            let fields: [(String, String, Bool, Bool)] = [("title", "String", false, false), ("label", "String", false, true), ("enabled", "Bool", true, false), ("displayName", "String", true, true)]
            var model = common(id: modelID, kind: "model", name: "Fixture" + direction)
            model["model"] = ["fieldIDs": fields.map { modelID + "." + $0.0 }, "omittedUpstreamIDs": [], "unknownFields": "ignore", "codec": "codable", "direction": direction.lowercased()]
            definitions.append(model)
            for (name, type, optional, nullable) in fields {
                var value = common(id: modelID + "." + name, kind: "field", name: name)
                value["field"] = ["modelID": modelID, "wireName": name == "displayName" ? "display_name" : name, "swiftName": name, "valueType": type, "optional": optional, "nullable": nullable, "defaultBehavior": optional ? "absent" : "rejectMissing", "constraints": [], "access": "fixture", "unknownValueBehavior": "rejectTypeMismatch"]
                definitions.append(value)
            }
        }
        return ["schemaVersion": 1, "verifiedOn": "2026-10-16", "maxAgeDays": 30, "sources": [], "symbols": [], "evidence": [], "definitions": definitions]
    }

    /// Supplies required common metadata without asserting synthetic fixture support upstream.
    /// - Parameters:
    ///   - id: Stable fixture-only ID.
    ///   - kind: Model or field metadata discriminator.
    ///   - name: Valid Swift declaration/member name.
    /// - Returns: Required reviewed-shaped common fields for renderer-only tests.
    private func common(id: String, kind: String, name: String) -> [String: Any] {
        ["id": id, "kind": kind, "name": name, "sourceID": "fixture", "upstreamIDs": [], "status": "partial", "supportSince": "2026-10-16", "announcementDate": "unknown", "effectiveDate": "unknown", "symbolIDs": [], "evidenceIDs": [], "notes": "Synthetic presence-aware fixture.\nNo upstream support claim."]
    }

    /// Standalone executable assertions independent of the renderer's implementation.
    private var codableSmoke: String {
        #"""
        import DiscordCore
        import Foundation

        /// Fails the finite smoke executable when an independently asserted codec invariant is false.
        /// - Parameter value: Evaluated fixture invariant; false terminates this test process.
        func verify(_ value: Bool) { precondition(value) }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = Data(#"{"title":"t","label":null,"display_name":null,"future":42}"#.utf8)
        let request = try decoder.decode(FixtureRequest.self, from: data)
        verify(request.title == "t" && request.label == .null && request.enabled == .absent && request.displayName == .null)
        let response = try decoder.decode(FixtureResponse.self, from: data)
        verify(response.title == "t" && response.label == .null && response.enabled == .absent && response.displayName == .null)
        let encoded = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        verify(object["enabled"] == nil && object["display_name"] is NSNull && object["label"] is NSNull && object["future"] == nil)
        verify(try decoder.decode(FixtureRequest.self, from: encoded) == request)
        let defaulted = FixtureRequest(title: "x", label: .value("label"))
        verify(defaulted.enabled == .absent && defaulted.displayName == .absent)
        let populated = FixtureResponse(title: "x", label: .value("label"), enabled: .value(false), displayName: .value("Display"))
        verify(try decoder.decode(FixtureResponse.self, from: encoder.encode(populated)) == populated)
        for invalid in [#"{"title":"t"}"#, #"{"title":null,"label":null}"#, #"{"title":"t","label":null,"enabled":null}"#, #"{"title":"t","label":null,"enabled":1}"#, #"{"title":"t","label":null,"display_name":1}"#] {
            do { _ = try decoder.decode(FixtureRequest.self, from: Data(invalid.utf8)); preconditionFailure("invalid request accepted") }
            catch is DecodingError {}
            do { _ = try decoder.decode(FixtureResponse.self, from: Data(invalid.utf8)); preconditionFailure("invalid response accepted") }
            catch is DecodingError {}
        }
        do { _ = try encoder.encode(FixtureRequest(title: "x", label: .null, enabled: .null)); preconditionFailure("forbidden null encoded") }
        catch is EncodingError {}
        verify(String(reflecting: request) == "FixtureRequest(redacted)")
        verify(Mirror(reflecting: response).children.count == 1)
        print("codable smoke passed")
        """#
    }
}
