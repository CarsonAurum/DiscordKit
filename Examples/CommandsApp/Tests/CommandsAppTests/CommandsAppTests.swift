import DiscordCore
import Testing
@testable import CommandsApp

/// Verifies the example's observable wire payloads using Swift Testing and no network or credentials.
@Suite struct CommandsAppTests {
    /// The required string precedes the optional boolean and each has the documented name/type.
    /// Repeated composition returns identical registration fields and never registers remotely.
    /// - Throws: Unexpected construction errors fail the test.
    @Test func commandDefinition() throws {
        let first = try CommandsApp.greetingCommand().request.jsonValue()
        let repeated = try CommandsApp.greetingCommand().request.jsonValue()
        #expect(first == repeated)
        guard case .object(let fields) = first, case .array(let options) = fields["options"] else {
            Issue.record("Missing command options"); return
        }
        #expect(fields["name"] == .string("greet"))
        #expect(options.count == 2)
        guard case .object(let required) = options[0], case .object(let optional) = options[1] else {
            Issue.record("Options must be objects"); return
        }
        #expect(required["name"] == .string("name"))
        #expect(required["type"] == .number(try JSONNumber(rawValue: "3")))
        #expect(required["required"] == .bool(true))
        #expect(optional["name"] == .string("private"))
        #expect(optional["type"] == .number(try JSONNumber(rawValue: "5")))
        #expect(optional["required"] != .bool(true))
    }

    /// Both visibility modes retain the fixed text and exactly one routable refresh button.
    /// Complete serialization also exercises the final payload validator; no sink is constructed.
    /// - Parameter ephemeral: Both supported visibility selections, including the public alternative.
    /// - Throws: Unexpected component/message/serialization errors fail the test.
    @Test(arguments: [true, false]) func message(ephemeral: Bool) throws {
        let value = try CommandsApp.greetingMessage(ephemeral: ephemeral).jsonValue()
        #expect(try JSONValue.parse(value.serialized()) == value)
        guard case .object(let fields) = value, case .array(let rows) = fields["components"],
              case .object(let row) = rows.first, case .array(let buttons) = row["components"],
              case .object(let button) = buttons.first else {
            Issue.record("Missing action row/button"); return
        }
        #expect(fields["content"] == .string("Hello from DiscordKit!"))
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: ephemeral ? "64" : "0")))
        #expect(rows.count == 1)
        #expect(buttons.count == 1)
        #expect(button["custom_id"] == .string("greeting:refresh"))
        #expect(button["style"] == .number(try JSONNumber(rawValue: "1")))
        #expect(button["label"] == .string("Refresh"))
        #expect(try CommandsApp.greetingMessage().jsonValue() == CommandsApp.greetingMessage(ephemeral: true).jsonValue())
    }

    /// The executable entry point completes after local validation and requires no external setup.
    /// - Throws: Any unexpected local validation failure from the same path used by `swift run`.
    @Test @MainActor func offlineEntryPoint() throws {
        try CommandsApp.main()
        #expect(try CommandsApp.greetingCommand().request.name == "greet")
    }
}
