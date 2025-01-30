// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiscordKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "DiscordKit",
            targets: ["DiscordKit"]),
    ],
    dependencies: [
        // NETWORK
        .package(url: "https://github.com/swift-server/async-http-client.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-nio.git", branch: "main"),
        .package(url: "https://github.com/vapor/websocket-kit.git", branch: "main"),
        // UTILS
        .package(url: "https://github.com/apple/swift-atomics.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-crypto.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", branch: "main"),
        .package(url: "https://github.com/Flight-School/AnyCodable", branch: "master"),
    ],
    targets: [
        .target(
            name: "DiscordKit",
            dependencies: [
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "DiscordKitTests",
            dependencies: ["DiscordKit"]
        ),
    ]
)
