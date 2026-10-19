// swift-tools-version: 6.4
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .defaultIsolation(nil),
]
let consumers = [
    "PositiveExternal", "InvalidCommandMetadata", "DynamicMetadata", "ComputedOption",
    "MissingOption", "InferredType", "InitializedLet", "MultipleBindings", "DynamicDefault",
    "WrongDefaultType", "UnsupportedArgumentType", "NonSendableHandler", "DuplicateOptions",
    "UnsupportedOptionMetadata", "MissingArgumentsAlias",
    "ImmediateResponderAccess", "DeferredResponderAccess", "WrongResponseFamily", "MultipleResponseFamilies",
    "InvalidUserCommandMetadata", "MultipleUserResponseFamilies", "WrongContextMenuResponse", "WrongModalResponse", "DeferredModalSlashResponse", "WrongAutocompleteResponse", "WrongComponentResponse",
]
let runtime: [Target.Dependency] = [
    .product(name: "DiscordCommandDSL", package: "DiscordKit"),
    .product(name: "DiscordCore", package: "DiscordKit"),
    .product(name: "DiscordModels", package: "DiscordKit"),
    .product(name: "DiscordDSL", package: "DiscordKit"),
    .product(name: "DiscordInteractions", package: "DiscordKit"),
]
let package = Package(
    name: "DSLCompileFixtures",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    dependencies: [
        .package(name: "DiscordKit", path: "../../.."),
        .package(name: "DiscordDSLMacros", path: "../../../Packages/DiscordDSLMacros"),
    ],
    targets: [
        .target(name: "ExternalCodec", dependencies: runtime, swiftSettings: concurrencySettings),
    ] + consumers.map { name in
        .target(name: name, dependencies: runtime + [
            "ExternalCodec", .product(name: "DiscordDSLMacros", package: "DiscordDSLMacros"),
        ], swiftSettings: concurrencySettings)
    }
)
