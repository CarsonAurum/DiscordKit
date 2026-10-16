import Foundation

// The executable dispatches only implemented offline operations. Usage failures remain
// distinct from failed validation, and generated writes require explicit --write intent.
do {
    let command = try ToolCommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    print(try command.execute(), terminator: "")
} catch let error as ToolUsageFailure {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("DiscordKitTools failed: \(error)\n".utf8))
    exit(1)
}
