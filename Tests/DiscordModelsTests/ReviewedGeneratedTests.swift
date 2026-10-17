import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Executes the preserved generated seed contracts against the expanded handwritten projections.
///
/// The Phase 5G migration freezes these scalar regression cases; current nested fields have separate tests.
/// Every case supplies independent complete JSON bytes. Fixtures and metadata are local,
/// deterministic and credential-free; each generated field contract receives meaningful
/// value, omission, null and wrong-type assertions through the public bounded initializer.
@Suite struct ReviewedGeneratedTests {
    /// Exercises every original generated scalar scenario using a fixed nonduplicate regression index.
    ///
    /// The index drives actual decoding rather than acting as a declaration-only support claim.
    /// Existing projection tests additionally assert concrete typed values, redaction and unknown enums.
    /// - Throws: Fixture read/decode errors or safe parser errors when test setup is malformed.
    @Test func reviewedFieldContracts() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/projection-regressions.json")
        let index = try JSONDecoder().decode(ReviewedCaseIndex.self, from: Data(contentsOf: fixture))
        #expect(index.schemaVersion == 1)
        #expect(index.verifiedOn == "2026-10-16")
        #expect(index.cases.count == 128)
        #expect(Set(index.cases.map(\.id)).count == index.cases.count)
        #expect(Set(index.cases.map(\.definitionID)).count == 32)
        for item in index.cases {
            var fields = try minimalFields(model: item.modelName)
            let accepts: Bool
            switch item.scenario {
            case "value": fields[item.wireName] = item.wireName == "flags_new" ? .string("184467440737095516160") : try validValue(item.valueType); accepts = true
            case "absent": fields.removeValue(forKey: item.wireName); accepts = true; #expect(item.optional)
            case "missingRejected": fields.removeValue(forKey: item.wireName); accepts = false; #expect(!item.optional)
            case "null": fields[item.wireName] = .null; accepts = true; #expect(item.nullable)
            case "nullRejected": fields[item.wireName] = .null; accepts = false; #expect(!item.nullable)
            case "wrongTypeRejected": fields[item.wireName] = item.valueType == "[String]" ? .bool(true) : .array([]); accepts = false
            default: Issue.record("Unknown generated scenario: \(item.id)"); continue
            }
            let data = try JSONValue.object(fields).serialized()
            if accepts {
                let actual = try decodedFields(data, model: item.modelName)
                #expect(actual[item.wireName] == fields[item.wireName], "Case \(item.id)")
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse), "Case \(item.id)") {
                    try decodedFields(data, model: item.modelName)
                }
            }
            #expect(item.evidenceIDs.contains("evidence.reviewed-field-contracts"))
        }
    }

    /// Checks each generated known Nitro variant and an unknown code through the real User projection.
    /// - Parameter raw: Official subscription codes 0...3 and a future unrecognized integer.
    /// - Throws: Fixture or model errors if a valid integral code cannot be preserved.
    @Test(arguments: [0, 1, 2, 3, 99])
    func generatedEnumVariants(raw: Int) throws {
        var fields = try minimalFields(model: "User")
        fields["premium_type"] = .number(try JSONNumber(rawValue: String(raw)))
        let user = try User(data: JSONValue.object(fields).serialized())
        guard case .value(let premium) = user.premiumType else {
            Issue.record("A supplied premium code was absent")
            return
        }
        #expect(premium.rawValue == raw)
        #expect(premium.knownValue == [PremiumType.none, .nitroClassic, .nitro, .nitroBasic].first { $0.rawValue == raw })
    }

    /// Preserves arbitrary-width and exponent numeric lexemes inside the nullable raw and typed team.
    ///
    /// This regression protects the handwritten subtree helper used by the expanded Application
    /// initializer from accidentally crossing the intentionally restricted JSONValue Codable bridge.
    /// - Throws: Safe JSON/model errors if a valid bounded nested object cannot be projected.
    @Test func nestedTeamRetainsExactNumbers() throws {
        var fields = try minimalFields(model: "Application")
        let team = try JSONValue.parse(#"{"id":"18446744073709551615","name":"team","icon":null,"owner_user_id":"2","members":[],"future":123456789012345678901234567890,"exponent":1e1000,"fraction":1.2300}"#)
        fields["team"] = team
        let application = try Application(data: JSONValue.object(fields).serialized())
        #expect(application.team == .value(team))
        #expect(application.rawFields["team"] == team)
        if case .value(let value) = application.team {
            let serialized = String(decoding: try value.serialized(), as: UTF8.self)
            #expect(serialized.contains("123456789012345678901234567890"))
            #expect(serialized.contains("1e1000"))
            #expect(serialized.contains("1.2300"))
        } else { Issue.record("A supplied team object became null") }
        #expect(!String(reflecting: application).contains("1234567890"))
    }

    /// Supplies complete minimal response objects independently of the generator's declaration logic.
    /// - Parameter model: The reviewed User or Application response name.
    /// - Returns: Required keys, including required-nullable members, with no optional fields.
    /// - Throws: Safe JSON errors or a setup validation error for an unknown model name.
    private func minimalFields(model: String) throws -> [String: JSONValue] {
        let text: String
        switch model {
        case "User": text = #"{"id":"1","username":"user","discriminator":"0","global_name":null,"avatar":null}"#
        case "Application": text = #"{"id":"1","name":"app","icon":null,"description":"example","bot_public":true,"bot_require_code_grant":false,"verify_key":"key","team":null}"#
        default: throw DiscordError.validation(.invalidValue)
        }
        guard case .object(let fields) = try JSONValue.parse(text) else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Projects one independent fixture through the public handwritten response initializer.
    /// - Parameters:
    ///   - data: Complete untrusted response bytes for exactly one model.
    ///   - model: User or Application; all other names are setup errors.
    /// - Returns: The complete raw object after typed fields have been validated successfully.
    /// - Throws: Safe parser/projection errors or a setup error for an unknown model name.
    private func decodedFields(_ data: Data, model: String) throws -> [String: JSONValue] {
        switch model {
        case "User": return try User(data: data).rawFields
        case "Application": return try Application(data: data).rawFields
        default: throw DiscordError.validation(.invalidValue)
        }
    }

    /// Chooses boundary-oriented valid payloads for the finite reviewed field-type vocabulary.
    /// - Parameter type: Reviewed payload type, excluding Field/Nullable wrappers.
    /// - Returns: An independent JSON value including maximum snowflakes and unknown enum values.
    /// - Throws: Safe number errors or a setup validation error for a new unhandled reviewed type.
    private func validValue(_ type: String) throws -> JSONValue {
        switch type {
        case "UserID", "ApplicationID", "GuildID": return .string("18446744073709551615")
        case "String": return .string("test")
        case "Bool": return .bool(true)
        case "Int": return .number(try JSONNumber(rawValue: String(Int.max)))
        case "UInt64": return .number(try JSONNumber(rawValue: String(UInt64.max)))
        case "RawValue<PremiumType>": return .number(try JSONNumber(rawValue: "99"))
        case "[String]": return .array([.string("first"), .string("second")])
        case "JSONValue": return try JSONValue.parse(#"{"id":"1","name":"team","icon":null,"owner_user_id":"2","members":[],"future":1e1000}"#)
        default: throw DiscordError.validation(.invalidValue)
        }
    }
}

/// The generated index shape; decoding rejects incompatible fixture changes before scenario execution.
private struct ReviewedCaseIndex: Decodable {
    let schemaVersion: Int
    let verifiedOn: String
    let cases: [ReviewedCase]
}

/// One generated scenario with sufficient metadata to exercise the real response decoder.
private struct ReviewedCase: Decodable {
    let id: String
    let definitionID: String
    let modelName: String
    let wireName: String
    let valueType: String
    let scenario: String
    let optional: Bool
    let nullable: Bool
    let evidenceIDs: [String]
}
