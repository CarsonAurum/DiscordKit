import DiscordCommands
import DiscordCore
import DiscordModels

/// Offline command/component composition. Nothing reads credentials, registers commands or opens I/O.
@main struct CommandsApp {
    /// Builds a bounded `/greet` definition with one required string and optional private-reply flag.
    /// The returned value is inert; a caller must explicitly reconcile or register it using API v10.
    /// - Returns: A validated slash-command request in declaration order, with no default permission override.
    /// - Throws: Command/option validation errors if this authored example becomes inconsistent.
    static func greetingCommand() throws -> CommandDefinition {
        try CommandDefinition.slash(name: "greet", description: "Show a greeting with a refresh button") {
            try ApplicationCommandOptionCreate(type: .string, name: "name", description: "Name to greet", required: true)
            try ApplicationCommandOptionCreate(type: .boolean, name: "private", description: "Reply only to you")
        }
    }

    /// Composes one legacy action row, preserving the exact refresh custom ID for explicit routing.
    /// This example uses a fixed greeting to avoid treating user input or a custom ID as authorization.
    /// - Parameter ephemeral: True selects interaction-only visibility; defaults to true.
    /// - Returns: A validated JSON-only initial/follow-up body containing text and one primary button.
    /// - Throws: Component/message validation errors; no network request or acknowledgement occurs.
    static func greetingMessage(ephemeral: Bool = true) throws -> InteractionMessageCreate {
        let row = try MessageComponent(jsonValue: .object([
            "type": .number(try JSONNumber(rawValue: "1")),
            "components": .array([.object([
                "type": .number(try JSONNumber(rawValue: "2")),
                "style": .number(try JSONNumber(rawValue: "1")),
                "label": .string("Refresh"), "custom_id": .string("greeting:refresh"),
            ])]),
        ]))
        return try InteractionMessageCreate(content: .value("Hello from DiscordKit!"),
            components: .value([row]), flags: .value(ephemeral ? .ephemeral : []))
    }

    /// Exercises both public compositions and their wire validators without transmitting the payloads.
    /// - Throws: Definition, component or JSON validation errors; the process owns no resources to close.
    @MainActor static func main() throws {
        let definition = try greetingCommand()
        let body = try greetingMessage().jsonValue()
        _ = try body.serialized()
        print("Offline command /\(definition.request.name): validated greeting and refresh button.")
    }
}
