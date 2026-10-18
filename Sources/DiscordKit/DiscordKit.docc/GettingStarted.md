# Get started with DiscordKit

Choose a product, add it to your Swift package, and run a local example before connecting to Discord.

## Overview

### Requirements

Use Swift 6.4 or newer. The declared Apple deployment minima are macOS 13, iOS and tvOS 16, watchOS 9 and visionOS 1. Availability of a portable value type does not imply that a network or audio adapter is qualified on every host. Review the [platform support matrix](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/PlatformSupport.md) when selecting a concrete backend.

Clone the repository and run its deterministic suites:

```sh
git clone https://github.com/CarsonAurum/DiscordKit.git
cd DiscordKit
swift build
swift test
```

Root tests use local fixtures and some loopback peers; they do not require Discord credentials. Consumer packages under Examples resolve independently from the repository root package.

### Select a dependency

Use a reviewed tag or immutable revision when integrating the package. The development candidate is unpublished, so do not assume that a version in a document is an available release. This local manifest shows a REST consumer against a neighboring checkout:

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MyDiscordApp",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../DiscordKit")],
    targets: [.executableTarget(name: "MyDiscordApp", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordFoundationTransport", package: "DiscordKit"),
    ])]
)
```

Use DiscordClient for a bot with supervised Gateway sessions, DiscordInteractions and DiscordCommands for a signed HTTP application, or the separate RPC, Activities, Social and voice products for their respective hosts. <doc:TableOfContents> maps every product to its guides and reference.

### Run an offline introduction

```sh
swift build --package-path Examples/CommandsApp
swift test --package-path Examples/CommandsApp
swift run --package-path Examples/CommandsApp
```

The program validates a `/greet` definition and a message containing a refresh button. It reads no credentials, registers nothing and opens no transport. The expected output is:

```text
Offline command /greet: validated greeting and refresh button.
```

Continue with <doc:DefineACommand> to explore its definition and wire payload.

### Prepare a real application

Create an application in the [Discord Developer Portal](https://discord.com/developers/applications). Select install contexts, OAuth redirect URIs, permissions and intents for the surface you will use. A bot token, an OAuth user token, an interaction signing public key and a local desktop host session confer different authority; use the credential type required by the operation.

The [official API reference](https://docs.discord.com/developers/reference) lists REST/Gateway v10 and explains version selection, authentication, identifiers and optional fields. DiscordKit explicitly selects protocol versions in its integrations. Check the [Discord change log](https://docs.discord.com/developers/change-log) when maintaining an application.

Keep secrets in a backend or injected secure store, redact them from diagnostics, and assign one owner for each transport and shared authority. <doc:ConcurrencyAndOwnership> explains startup and cleanup; <doc:RESTOnly> and <doc:GatewayBots> show the next application choices.
