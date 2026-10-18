# Message/component builders and safe text

Part 15E adds pure message authoring to the unpublished **0.15.0 candidate**.
`DiscordDSL.MessageContent` retains text and typed mention intent using only Core
and Models. `DiscordCommandDSL` supplies `MessageBuilder`, `ComponentBuilder` and
thin immediate/deferred response initializers. Existing products retain their
independent adoption graphs; no compiler plugin is required for these APIs.

Constructing or rendering a template and lowering a builder perform no I/O, task
startup, registration or handler execution. Existing Models remain authoritative
for message limits, legal component placement, field presence and payload flags.
The existing interaction responder retains acknowledgement and transmission
ownership; see [response modes](CommandResponses.md).

## Author a validated response

```swift
import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordModels

let name = "A visitor with @everyone in their name"
let user = UserID(rawValue: 42)
let response = try MessageResponse(visibility: .ephemeral) {
    Text("Hello, \(name)! Welcome \(user: user).")
    Components {
        Component.actionRow {
            Component.button("Continue", customID: "welcome.continue")
            Component.linkButton("Guide", url: "https://example.com/guide")
        }
    }
}
let payload = try response.message.jsonValue()
```

The content contains escaped dynamic `name` text and a typed `<@42>` user
mention. The complete message supplies `allowed_mentions` with `parse: []`,
`users: ["42"]` and `replied_user: false`. Other users, roles, `@here` and
`@everyone` receive no broad parsing permission. This selects allowed recipients;
Discord permissions, mentionability, notification suppression and recipient
settings still determine actual delivery.

`Text` declarations join in declaration order with a newline. `Embed` adopts an
existing validated `MessageEmbed`; it does not reinterpret the embed or fetch its
URLs. `Components` accepts a component builder. Builders support empty blocks,
optional/conditional branches, arrays and finite loops with deterministic source
and iteration order. Empty construction is valid authoring syntax, while a final
immediate message still must satisfy its payload's nonempty-content rules. An empty
deferred builder is a permitted no-op edit. Arbitrary Swift inside a closure must
terminate cooperatively and avoid unwanted side effects.

## Keep text and mention intent separate

`MessageContent` conforms to `ExpressibleByStringLiteral` and
`ExpressibleByStringInterpolation`. Its custom interpolation retains each segment
until explicit `render()` rather than flattening all expressions through `String`.

```swift
let untrusted = "**text** <@42> @everyone"
let role = RoleID(rawValue: 84)
let channel = ChannelID(rawValue: 126)
let content: MessageContent = "**Greeting** \(untrusted) \(user: user) \(role: role, notify: false) \(channel: channel)"
let rendered = try content.render()
```

Trusted source literals preserve developer-authored Markdown. Ordinary dynamic
`String` interpolation escapes Markdown metacharacters and inserts U+200B after
`<` and `@`, so untrusted mention-looking input remains inert even when another
typed segment allows the same identifier. It also inserts a separator before
ordinary text following an open mention introducer in trusted segments, preventing
split tokens from bypassing this protection. `MessageContent(dynamicString)` uses
the same escaped-text behavior. Interpolating another `MessageContent` preserves
its retained segment intent.

`user:` and `role:` interpolation format typed Core identifiers and default to
`notify: true`, adding that identifier to the corresponding allowlist. Explicit
`notify: false` formats the reference without adding permission. `channel:` formats
a channel reference and contributes no notification selector. Identifiers are
deduplicated in first-use order, with at most 100 distinct notifying users and
100 roles. Broad parsing and reply-author notification remain disabled.

`raw:` interpolation is the explicit trusted formatting escape hatch. It does not
add allowlisted IDs. Discord applies a message's allowlists globally: a literal or
raw mention of an ID allowed by a typed segment can still notify that ID, and a
`notify: false` occurrence cannot revoke another occurrence's opt-in. Keep untrusted
input in ordinary interpolation. Explicit payload-level mention-policy overrides
are deliberate application responsibility, and direct Models remain available.

`MessageContent.joined(_:separator:)` preserves segments in input order. The
default separator is a newline; a supplied separator is trusted literal text.
Repeated rendering is deterministic and consumes no state.

## Preserve component grammar

`Component.actionRow` admits one through five buttons or exactly one select;
mixed buttons/selects, nested rows and duplicate custom IDs fail complete message
validation. Button factories cover standard interactive, URL and premium SKU
buttons. `stringSelect` adopts existing typed `ComponentOption` values; `select`
covers user, role, mentionable and channel selects without resolving entities.

Components V2 uses `textDisplay`, `section(accessory:)`, `container` and `separator`
for supported text/layout authoring. A `textDisplay` uses the same safe content
renderer and contributes its typed mentions to the message-level policy. Sections
require one through three text displays and a valid button/thumbnail accessory.
Nested containers and invalid children fail the existing Models validator. Other
supported layouts and advanced fields remain available through exact raw
`MessageComponent` adoption, including its omission/null/value semantics.

The default component mode is `.automatic`: a top-level declaration other than
an action row selects V2, and deferred edits honor observed V2 `previousFlags`.
Explicit `.legacy` and `.v2` modes let the caller choose the grammar; an explicit
legacy edit of an existing V2 message fails because V2 cannot be removed.
V2 requires `IS_COMPONENTS_V2`, admits at most 40 total components and
rejects legacy content/embeds, poll and stickers. The complete payload validator
checks flag compatibility and all nested counts; the DSL does not silently repair
an illegal layout or establish support for a new component family.

## Validate before transmission

Literal/interpolation constructors cannot throw. Capture therefore records the
first admission failure and reports it from `render()` or response construction;
no partial payload is transmitted. Content capture admits at most 4,096 nonempty
segments and 1 MiB of source UTF-8, with a separate 1 MiB rendered UTF-8 bound.
These authoring limits do not replace Discord message limits. Existing Models count
Unicode scalars for text limits, including 2,000 message content scalars, ten embeds
and 6,000 aggregate embed text scalars. A Swift `Character` may contain multiple
scalars, and escaping may increase output size. Validation never truncates text to
make an oversized message fit.

Builders retain at most 64 message contributions; typed component declarations
share a 40-node admission bound and depth bound of eight. Complete lowered JSON
is additionally limited to 64 KiB, 24 JSON containers and 4,096 values. These are
local finite authoring budgets, not upstream server capacity claims.

Undeclared text, embeds and components remain absent. `Text("")` explicitly writes
an empty string; `Components {}` supplies an empty array, including component
clearing on edit. Explicit nulls, clearing embeds and advanced fields use the
existing raw-model initializer; raw embed/component adoption preserves existing
field presence. Lowering then invokes existing complete payload validation. The
immediate response supplies an existing `InteractionMessageCreate`; the deferred
response supplies an `InteractionMessageEdit`
for edit-original completion. `DeferredMessageResponse(previousFlags:)` accepts
explicitly observed prior flags to retain immutable bits and existing V2 state; it
performs no hidden fetch. Migrating an existing legacy message to V2 may require
explicitly clearing incompatible fields through the raw-model edit initializer.
JSON-only response constructors reject new multipart upload placeholders, and
deferred visibility stays fixed by the initial
acknowledgement. Raw-model response initializers remain available for incremental
adoption and richer existing fields.

Local tests compare builder output to directly constructed model JSON and exercise
escaping, typed opt-in, Unicode limits, empty/invalid layouts and response ownership.
The independent [DSLCommands consumer](../Examples/DSLCommands/README.md) uses an
actual compiled macro command and a builder-authored response in its synthetic
signed HTTP exchange. This evidence does not establish live Discord rendering,
notification delivery, platform qualification, production capacity or the remaining
[Phase 15 milestones](DSLImplementationRoadmap.md).

The affected [message](https://docs.discord.com/developers/resources/message),
[component](https://docs.discord.com/developers/components/reference) and
[interaction](https://docs.discord.com/developers/interactions/receiving-and-responding)
contracts and Swift's [interpolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0228-fix-expressiblebystringinterpolation.md)
and [result-builder](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md)
contracts were reviewed on **2026-10-18**. The
[source record](Release/sources/2026-10-18-phase15e.json) identifies exact inputs;
[parity history](Parity/changes/phase15e-message-builders.md) records the additive
local authoring change without promoting wire coverage.
