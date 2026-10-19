import DiscordCommandDSL
import DiscordCore
import DiscordModels
import Foundation
import Testing

/// Pure current-modal admission and typed codec coverage with no response owner, network or hydration.
@Suite struct ModalValueTests {
    /// Built-in codecs preserve Unicode/empty/false/optional semantics and distinguish missing/null/wrong kinds.
    /// - Throws: Unexpected codec construction failures fail the test.
    @Test func scalarCodecs() throws {
        #expect(try String.decodeModalInput(.text("")) == "")
        #expect(try String.decodeModalInput(.text("e\u{301}🦊")) == "e\u{301}🦊")
        #expect(try String.decodeModalInput(.radio("picked")) == "picked")
        #expect(try Bool.decodeModalInput(.checked(false)) == false)
        #expect(try Bool.decodeModalInput(.checked(true)))
        #expect(try Optional<String>.decodeModalInput(nil) == nil)
        #expect(try Optional<String>.decodeModalInput(.radio(nil)) == nil)
        #expect(try Optional<String>.decodeModalInput(.text("")) == "")
        #expect(try Optional<Bool>.decodeModalInput(.checked(false)) == false)
        #expect(throws: ArgumentValueError.missing) { try String.decodeModalInput(nil) }
        #expect(throws: ArgumentValueError.nullValue) { try String.decodeModalInput(.radio(nil)) }
        #expect(throws: ArgumentValueError.wrongKind) { try String.decodeModalInput(.checked(true)) }
        #expect(throws: ArgumentValueError.missing) { try Bool.decodeModalInput(nil) }
        #expect(throws: ArgumentValueError.wrongKind) { try Bool.decodeModalInput(.text("true")) }
        #expect(throws: ArgumentValueError.wrongKind) { try Optional<Bool>.decodeModalInput(.text("false")) }
        #expect(try ModalSelections.decodeModalInput(.selection([])) == ModalSelections([]))
        #expect(try ModalSelections.decodeModalInput(.selection(["b", "a"])).values == ["b", "a"])
        #expect(throws: ArgumentValueError.missing) { try ModalSelections.decodeModalInput(nil) }
        #expect(throws: ArgumentValueError.wrongKind) { try ModalSelections.decodeModalInput(.checked(false)) }
        #expect(String.modalComponentTypes == [.textInput, .radioGroup])
        #expect(Bool.modalComponentTypes == [.checkbox])
        #expect(Optional<String>.modalComponentTypes == String.modalComponentTypes)
        #expect(Optional<String>.acceptsMissingModalInput)
        #expect(!String.acceptsMissingModalInput)
    }

    /// Descriptor and schema construction bounds exact IDs, unique fields, kinds, and count before any user work.
    /// - Throws: Unexpected valid schema construction failures fail the test.
    @Test func descriptorAndSchemaValidation() throws {
        #expect(throws: DiscordError.self) { try ModalField<String>(customID: "") }
        #expect(throws: DiscordError.self) { try ModalField<String>(customID: String(repeating: "🦊", count: 101)) }
        #expect(try ModalField<String>(customID: String(repeating: "🦊", count: 100)).customID.unicodeScalars.count == 100)
        #expect(throws: DiscordError.self) { try ModalField<String>(customID: "x", componentType: .checkbox) }
        #expect(throws: DiscordError.self) { try ModalField<EmptyModalCodec>(customID: "x") }
        #expect(throws: DiscordError.self) { try ModalField<ContainerModalCodec>(customID: "x") }
        let field = try ModalField<String>(customID: "x")
        #expect(throws: DiscordError.self) { try ModalSchema<String>(fields: [field.erased, field.erased]) { _ in "" } }
        let many = try (0..<6).map { try ModalField<String>(customID: String($0)).erased }
        #expect(throws: DiscordError.self) { try ModalSchema<String>(fields: many) { _ in "" } }
        let noFields = try ModalSchema<String>(fields: []) { _ in "empty" }
        #expect(try noFields.decode(Self.data(#"[{"type":10,"content":"display only"}]"#)) == "empty")
    }

    /// Current string/entity selects, files and checkbox groups decode via typed selection fields with exact order.
    /// - Parameter kind: Every currently supported modal selection/upload leaf kind.
    /// - Throws: Unexpected descriptor/projection/decoding failures fail the test.
    @Test(arguments: [ComponentType.stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect, .fileUpload, .checkboxGroup])
    func currentSelectionFamilies(kind: ComponentType) throws {
        let field = try ModalField<ModalSelections>(customID: "choice", componentType: kind)
        let schema = try ModalSchema<ModalSelections>(fields: [field.erased]) { try $0.value(for: field) }
        let values = [ComponentType.stringSelect, .checkboxGroup].contains(kind) ? ["second", "first"] : ["18446744073709551615", "2"]
        let child: JSONValue = .object(["type": .number(try JSONNumber(rawValue: String(kind.rawValue))),
            "custom_id": .string("choice"), "values": .array(values.map(JSONValue.string))])
        let data = try InteractionModalData(data: JSONValue.object(["custom_id": .string("form"),
            "components": .array([.object(["type": .number(JSONNumber(rawValue: "18")), "component": child])])]).serialized())
        #expect(try schema.decode(data).values == values)
        let empty = try Self.data(#"[{"type":18,"component":{"type":\#(kind.rawValue),"custom_id":"choice","values":[]}}]"#)
        #expect(try schema.decode(empty).values.isEmpty)
    }

    /// Legacy rows, current labels, optional omission and unselected radio values produce fresh typed aggregates.
    /// - Throws: Unexpected valid schema or input errors fail the test.
    @Test func legacyLabelsAndOptionalPresence() throws {
        let text = try ModalField<String>(customID: "text"), checked = try ModalField<Bool>(customID: "checked")
        let radio = try ModalField<String?>(customID: "radio", componentType: .radioGroup)
        let schema = try ModalSchema<ModalFixtureAggregate>(fields: [text.erased, checked.erased, radio.erased]) {
            try ModalFixtureAggregate(text: $0.value(for: text), checked: $0.value(for: checked), radio: $0.value(for: radio))
        }
        let first = try schema.decode(Self.data(#"[{"type":1,"components":[{"type":4,"custom_id":"text","value":""}]},{"type":18,"component":{"type":23,"custom_id":"checked","value":false}},{"type":18,"component":{"type":21,"custom_id":"radio","value":null}}]"#))
        #expect(first.text == "")
        #expect(!first.checked)
        #expect(first.radio == nil)
        let second = try schema.decode(Self.data(#"[{"type":18,"component":{"type":4,"custom_id":"text","value":"second"}},{"type":18,"component":{"type":23,"custom_id":"checked","value":true}}]"#))
        #expect(second.text == "second")
        #expect(second.checked)
        #expect(second.radio == nil)
        #expect(first.text.isEmpty)
        let selected = try schema.decode(Self.data(#"[{"type":18,"component":{"type":4,"custom_id":"text","value":"x"}},{"type":18,"component":{"type":23,"custom_id":"checked","value":true}},{"type":18,"component":{"type":21,"custom_id":"radio","value":"picked"}}]"#))
        #expect(selected.radio == "picked")
    }

    /// Invalid tree shapes, repeated IDs, undeclared fields and incomplete values fail before aggregate construction.
    /// - Parameter roots: Controlled parser-valid but schema-invalid modal component roots.
    /// - Throws: Unexpected fixture errors fail; exact no-construction behavior is asserted.
    @Test(arguments: [
        "[]",
        #"[{"type":4,"custom_id":"text","value":"x"}]"#,
        #"[{"type":999}]"#,
        #"[{"type":18}]"#,
        #"[{"type":1,"components":[]}]"#,
        #"[{"type":1,"components":[{"type":23,"custom_id":"text","value":false}]}]"#,
        #"[{"type":1,"components":[{"type":4,"custom_id":"text","value":"a"},{"type":4,"custom_id":"text","value":"b"}]}]"#,
        #"[{"type":18,"component":{"type":1,"components":[{"type":4,"custom_id":"text","value":"x"}]}}]"#,
        #"[{"type":18,"components":[],"component":{"type":4,"custom_id":"text","value":"x"}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"text","value":"x","components":[]}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"","value":"x"}}]"#,
        #"[{"type":18,"component":{"type":4,"value":"x"}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"text"}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"text","value":"x","values":[]}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"undeclared","value":"x"}}]"#,
        #"[{"type":18,"component":{"type":23,"custom_id":"text","value":false}}]"#,
        #"[{"type":18,"component":{"type":4,"custom_id":"text","value":"a"}},{"type":18,"component":{"type":4,"custom_id":"text","value":"b"}}]"#,
        #"[{"type":18,"id":1,"component":{"type":4,"id":1,"custom_id":"text","value":"x"}}]"#,
        #"[{"type":10,"content":"display","custom_id":"text"}]"#,
        #"[{"type":18,"component":{"type":21,"custom_id":"text","value":null}}]"#
    ]) func malformedBeforeConstruction(roots: String) throws {
        let field = try ModalField<String>(customID: "text")
        let schema = try ModalSchema<String>(fields: [field.erased]) { _ in
            Issue.record("Malformed modal reached aggregate construction")
            return "forbidden"
        }
        let data = try Self.data(roots)
        #expect(throws: (any Error).self) { try schema.decode(data) }
    }

    /// Numeric zero IDs are generation sentinels while count/text/selection bounds reject excessive retained input.
    /// - Throws: Unexpected fixture or valid boundary errors fail the test.
    @Test func boundsAndNumericIdentity() throws {
        let field = try ModalField<String>(customID: "text")
        let schema = try ModalSchema<String>(fields: [field.erased]) { try $0.value(for: field) }
        #expect(try schema.decode(Self.data(#"[{"type":18,"id":0,"component":{"type":4,"id":0,"custom_id":"text","value":"x"}}]"#)) == "x")
        let textBoundary = String(repeating: "🦊", count: 4_000)
        let boundary = try Self.single(kind: .textInput, id: "text", value: .string(textBoundary))
        #expect(try schema.decode(boundary) == textBoundary)
        let tooLong = try Self.single(kind: .textInput, id: "text", value: .string(textBoundary + "x"))
        #expect(throws: DiscordError.self) { try schema.decode(tooLong) }
        let tooLongID = try Self.single(kind: .textInput, id: String(repeating: "x", count: 101), value: .string("x"))
        #expect(throws: DiscordError.self) { try schema.decode(tooLongID) }
        let tooManyRoots = try Self.data("[" + Array(repeating: #"{"type":10,"content":"display"}"#, count: 6).joined(separator: ",") + "]")
        #expect(throws: DiscordError.self) { try schema.decode(tooManyRoots) }
        for kind in [ComponentType.stringSelect, .fileUpload, .checkboxGroup] {
            let selection = try ModalField<ModalSelections>(customID: "choice", componentType: kind)
            let selectionSchema = try ModalSchema<ModalSelections>(fields: [selection.erased]) { try $0.value(for: selection) }
            let count = kind == .stringSelect ? 26 : 11
            let excessive = try Self.single(kind: kind, id: "choice", value: .array((0..<count).map { .string(String($0 + 1)) }), selections: true)
            #expect(throws: DiscordError.self) { try selectionSchema.decode(excessive) }
            let duplicate = try Self.single(kind: kind, id: "choice", value: .array([.string("1"), .string("1")]), selections: true)
            #expect(throws: DiscordError.self) { try selectionSchema.decode(duplicate) }
        }
        let resource = try ModalField<ModalSelections>(customID: "choice", componentType: .userSelect)
        let resourceSchema = try ModalSchema<ModalSelections>(fields: [resource.erased]) { try $0.value(for: resource) }
        let malformed = try Self.single(kind: .userSelect, id: "choice", value: .array([.string("not-snowflake")]), selections: true)
        #expect(throws: DiscordError.self) { try resourceSchema.decode(malformed) }
    }

    /// Descriptor lookups reject unrelated identities/kinds/generic types; custom conversion errors propagate exactly.
    /// - Throws: Unexpected fixture/schema errors fail the test.
    @Test func decodedLookupAndCustomFailure() throws {
        let field = try ModalField<String>(customID: "text")
        let other = try ModalField<String>(customID: "other")
        let wrongKind = try ModalField<String>(customID: "text", componentType: .radioGroup)
        let wrongType = try ModalField<String?>(customID: "text")
        let schema = try ModalSchema<String>(fields: [field.erased]) { values in
            #expect(throws: ArgumentValueError.wrongKind) { try values.value(for: other) }
            #expect(throws: ArgumentValueError.wrongKind) { try values.value(for: wrongKind) }
            #expect(throws: ArgumentValueError.wrongKind) { try values.value(for: wrongType) }
            return try values.value(for: field)
        }
        #expect(try schema.decode(Self.single(kind: .textInput, id: "text", value: .string("x"))) == "x")
        let rejected = try ModalField<FailingModalCodec>(customID: "text")
        let rejectingSchema = try ModalSchema<FailingModalCodec>(fields: [rejected.erased]) { try $0.value(for: rejected) }
        #expect(throws: ModalFixtureFailure.codec) {
            try rejectingSchema.decode(Self.single(kind: .textInput, id: "text", value: .string("x")))
        }
    }

    /// Parses controlled roots into a bounded existing-model modal submission without applying outgoing UI requirements.
    /// - Parameter roots: Complete controlled JSON root-component array.
    /// - Returns: Immutable modal data with an exact finite custom ID.
    /// - Throws: Controlled JSON/projection errors.
    private static func data(_ roots: String) throws -> InteractionModalData {
        try InteractionModalData(data: Data(("{\"custom_id\":\"form\",\"components\":" + roots + "}").utf8))
    }

    /// Wraps one controlled scalar/selection leaf in a current modal label.
    /// - Parameters:
    ///   - kind: Current known modal leaf kind.
    ///   - id: Controlled custom ID, including deliberately malformed boundaries.
    ///   - value: Exact scalar or selection-array JSON.
    ///   - selections: Whether the leaf uses plural values rather than scalar value; default false.
    /// - Returns: Parser-bounded input for schema admission tests.
    /// - Throws: Controlled JSON/model errors.
    private static func single(kind: ComponentType, id: String, value: JSONValue, selections: Bool = false) throws -> InteractionModalData {
        try InteractionModalData(data: JSONValue.object(["custom_id": .string("form"), "components": .array([
            .object(["type": .number(JSONNumber(rawValue: "18")), "component": .object([
                "type": .number(try JSONNumber(rawValue: String(kind.rawValue))), "custom_id": .string(id),
                selections ? "values" : "value": value])])])]).serialized())
    }
}

private struct ModalFixtureAggregate: Sendable {
    let text: String
    let checked: Bool
    let radio: String?
}

private enum ModalFixtureFailure: Error { case codec }

/// Invalid custom codec with no supported kind; descriptors must reject it before decoding.
private struct EmptyModalCodec: ModalValue {
    /// Reports an invalid empty supported-kind list without work.
    static var modalComponentTypes: [ComponentType] { [] }
    /// Marks forbidden execution through a thrown controlled error.
    /// - Parameter input: Ignored admitted input; invalid descriptor construction prevents this method.
    /// - Returns: Never returns a value.
    /// - Throws: A controlled fixture error if accidentally invoked.
    static func decodeModalInput(_ input: ModalInput?) throws -> Self { throw ModalFixtureFailure.codec }
}

/// Invalid codec attempting to use a container instead of a modal leaf.
private struct ContainerModalCodec: ModalValue {
    /// Reports an invalid container kind for descriptor admission testing.
    static var modalComponentTypes: [ComponentType] { [.label] }
    /// Throws if invalid construction ever permits this codec to execute.
    /// - Parameter input: Ignored controlled value.
    /// - Returns: Never returns a value.
    /// - Throws: A controlled fixture error.
    static func decodeModalInput(_ input: ModalInput?) throws -> Self { throw ModalFixtureFailure.codec }
}

/// Well-formed custom codec proving schema conversion preserves application errors without fallback construction.
private struct FailingModalCodec: ModalValue {
    /// Adopts the valid text-input family without work.
    static var modalComponentTypes: [ComponentType] { [.textInput] }
    /// Rejects a completely admitted local value with an exact controlled application error.
    /// - Parameter input: Parser/schema-admitted text value.
    /// - Returns: Never returns a value.
    /// - Throws: The exact controlled codec error.
    static func decodeModalInput(_ input: ModalInput?) throws -> Self { throw ModalFixtureFailure.codec }
}
