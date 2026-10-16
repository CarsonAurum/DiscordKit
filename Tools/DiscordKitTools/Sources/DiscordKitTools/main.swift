import Foundation

// Only inventory validation exists in Part 0. Future roadmap commands must fail explicitly.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 4,
      Array(arguments.prefix(3)) == ["inventory", "validate", "--repository"] else {
    FileHandle.standardError.write(Data("Usage: DiscordKitTools inventory validate --repository <directory>\n".utf8))
    exit(64)
}
do {
    let root = URL(fileURLWithPath: arguments[3], isDirectory: true)
    let parity = root.appending(path: "Docs/Parity", directoryHint: .isDirectory)
    let report = try InventoryValidator.validate(
        inventoryData: Data(contentsOf: parity.appending(path: "inventory-v1.json")),
        sourcesData: Data(contentsOf: parity.appending(path: "sources-2026-10-15.json"))
    )
    print("Valid inventory: \(report.entries) entries, \(report.sources) sources, 0 unclassified discovery IDs")
    print("Implemented support: \(report.supported); pending semantic review: \(report.pendingReview)")
    print("Structural validation does not certify platform qualification or full API parity.")
} catch {
    FileHandle.standardError.write(Data("Inventory validation failed: \(error)\n".utf8))
    exit(1)
}
