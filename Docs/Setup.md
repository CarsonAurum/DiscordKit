# Application setup and deployment

Verified **2026-10-18** against Discord's [getting-started guide](https://docs.discord.com/developers/quick-start/getting-started),
[permissions reference](https://docs.discord.com/developers/topics/permissions),
[Gateway reference](https://docs.discord.com/developers/events/gateway) and
[Activities overview](https://docs.discord.com/developers/activities/overview).
This is application configuration guidance; deployment and access approval are
separate from the package's local test results.

## Choose an independent consumer

Use Swift 6.4 or newer. Add the needed products to your target rather than importing
the umbrella for every application. Examples are separate packages with explicit
product selections; `swift build --package-path Examples/<Name>` compiles without
executing them. Offline CI builds the independent consumers and audits their selected
dependency/import graphs.

| Application | Example | Configuration required before live use |
| --- | --- | --- |
| REST bot backend | [RESTOnly](../Examples/RESTOnly/README.md) | Bot credential and application install permissions |
| Supervised Gateway bot | [GatewayBot](../Examples/GatewayBot/README.md) | Matching bot ID/token, explicit intents and shared authorities |
| Protocol-module Gateway host | [DSLBot](../Examples/DSLBot/README.md) | Offline synthetic host; inject real client dependencies and explicit intents for deployment |
| Typed Gateway event modules | [DSLEvents](../Examples/DSLEvents/README.md) | Offline synthetic event delivery with explicit finite subscription ownership |
| Signed HTTP application | [HTTPApp](../Examples/HTTPApp/README.md) | Public application ID/key, HTTPS forwarding and registered commands |
| Commands/components | [CommandsApp](../Examples/CommandsApp/README.md) | Offline composition; explicit registration and trusted receipt in deployment |
| OAuth application | [OAuthApp](../Examples/OAuthApp/README.md) | Registered redirect, user scopes, injected browser and secure storage |
| Voice components | [VoiceBot](../Examples/VoiceBot/README.md) | Offline synthetic demonstration; use supervised sessions for explicit network ownership |
| Desktop RPC/devices | [RPCApp](../Examples/RPCApp/README.md) | Available desktop Discord, approved local user scopes and injected IPC |
| Embedded Activity | [ActivityHost](../Examples/ActivityHost/README.md) | Enabled Activity, URL mapping, actual Discord host and separate HTTPS backend |
| Public Social providers | [SocialApp](../Examples/SocialApp/README.md) | Explicit consent and provider-specific host/authority requirements |

Select `DiscordCommandDSL` and `DiscordDSL` explicitly for [typed command
authoring](CommandDSL.md). Compilation produces existing validated registration
definitions and exact routes. It does not register commands, verify ingress, bind
a listener or choose a Gateway client. Part 15D's `CommandApplication` explicitly
composes signed ingress and the bounded router. Inject the shared admission authority
and an HTTP listener; `run` owns and closes that listener. Call `synchronize` separately
for registration. Use [DSLCommands](../Examples/DSLCommands/README.md) in its default
offline mode to exercise a signed exchange; `--listen` explicitly opts into listener
ownership. Its response uses Part 15E's [message builder](MessageBuilders.md), with
explicit mention suppression by default. See [response/application contracts](CommandResponses.md).
For optional `@CommandArguments`/`@SlashCommand` authoring, select the separate
[DiscordDSLMacros package](MacroDSL.md); the root package does not select its plugin.

Select `DiscordBotDSL` for [supervised bot applications](BotApplications.md). Its
`BotApplication` factory constructs explicit host dependencies and returns a
single-use `BotRuntime`. The runtime subscribes before client startup, owns the
existing client and event/interaction pipelines, and joins their cleanup on terminal
exit. Share credential, startup, lease, event, handler, REST and resource authorities;
ordinary startup performs no command synchronization. Gateway interaction provenance
comes from the client's package-internal ingestion boundary, and callbacks retain
existing HTTP response ownership. Ordinary synthetic event publication cannot
authenticate an interaction.

Only CommandsApp, DSLCommands in default/`--offline` mode, DSLEvents, DSLBot, VoiceBot, RPCApp,
ActivityHost, OAuthApp and SocialApp are safe
offline demonstrations by design. RESTOnly/GatewayBot can use credentials when
run; HTTPApp can bind a listener when configured. Routine CI builds these examples
and runs only explicitly offline consumers.

## Portal and authority

Create an application in the [Developer Portal](https://discord.com/developers/applications).
Record its public application ID and verification public key. Configure supported
installation contexts and an install link with the scopes and bot permissions your
application actually needs. Keep bot tokens and client secrets in backend secret
storage. Application IDs and verification public keys are not substitutes for user
consent, bot permissions or signed-request verification.

Choose receipt mode explicitly. HTTP applications configure a public HTTPS
Interactions Endpoint URL, preserve original body/signature bytes and answer
authenticated PING. Gateway consumers request explicit intents. Enable required
privileged intents in the portal and obtain Discord approval where required;
the package cannot grant that access. Register commands deliberately and review
reconciliation before applying changes. Neither a constructor nor an example build
performs registration.

For OAuth, register the exact redirect, bind state/issuer/PKCE to the application
session, and inject browser and transactional token storage. Public clients keep
secrets on the backend and use an explicitly enabled public-client flow. Activity
URL mappings and real host embedding are distinct from standalone browser hosting.
SDK-only Social and unpublished Commerce operations remain named gaps in the
[Social catalog](Parity/phase13-social-catalog.json).

## Lifecycle, freshness and overload

Constructors are inert. Start work through the explicit run/connect/join methods
and await stop/close/leave cleanup on success, errors and cancellation. Share
credential rate coordinators, startup budgets, shard leases, resource limits and
application authorities across related clients. Inject externally coordinated
implementations for multiple workers; process-local actors do not coordinate a fleet.

Subscribe before starting a Gateway client, use bounded handler/subscriber queues,
and observe overflow or resync signals. A dropped event or invalidated session
requires an explicit bounded refresh before treating state as current. Choose
cache freshness and hydration policies per scope, retain missing/null distinctions,
and never infer resource existence or authorization from an incomplete cache.
See [Client](Client.md), [HTTP](HTTP.md) and [Scalability](Scalability.md).

Keep heartbeat/control work independent of handlers and cache I/O. HTTP initial
responses have a separate three-second acknowledgement budget; defer slow work
while eligible and use explicitly bounded continuations. A saturated ordinary
REST queue must not consume that acknowledgement authority. Do not replay a
mutation after an ambiguous send merely because the caller timed out.

Apple mobile background execution and watchOS networking require the actual host's
policy; simulator compilation grants neither. Device permissions, audio routing,
Windows IPC, Android integration, native Social access and authorized Discord
smoke remain separately qualified in [PlatformSupport](PlatformSupport.md).

## Build the guides

`swift package dump-symbol-graph --minimum-access-level public` emits the public
graphs. Then `python3 Tools/ci/build_docc.py` converts each owned library module and
the committed guide catalog with the installed toolchain's `docc`, treats warnings
as errors, enables diagnostic analysis and coverage, and writes ignored archives
under `.build`. Use `--symbolgraphs <directory>` for another graph location. No
documentation plugin is added to the production graph. Public-symbol DocC coverage
does not replace the owned SwiftSyntax audit at every access level or semantic
review for accuracy.

The [CI guide](CI.md) describes enabled jobs, infrastructure gates, and the optional
manually invoked live read-only smoke. The [migration guide](Migration.md) separates
local API changes from upstream protocol transitions.
