import DiscordCore
import DiscordClient
import DiscordGateway
import DiscordTransport
import DiscordCommands
import DiscordInteractions

/// Macro-free typed command definition; independent consumers import `DiscordCommands`.
public typealias CommandDefinition = DiscordCommands.CommandDefinition
/// Explicit bounded command/autocomplete/component/modal routing for either delivery mode.
public typealias CommandRouter = DiscordCommands.CommandRouter
/// Explicit command synchronization that preserves unmanaged registrations.
public typealias CommandReconciler = DiscordCommands.CommandReconciler
/// Typed HTTP/Gateway input paired with one actor-protected response owner.
public typealias InteractionContext = DiscordInteractions.InteractionContext
/// HTTP-only signed interaction application; no Gateway product is required for independent adoption.
public typealias InteractionHTTPApplication = DiscordInteractions.InteractionHTTPApplication

/// Supervised consumer bot client; import `DiscordClient` for the independent runtime product.
public typealias BotClient<C: Clock, Leases: ShardLeaseStore> = DiscordClient<C, Leases>
    where C.Duration == Duration, Leases.LeaseClock == C
/// Explicit intent/topology and ingestion configuration for the consumer bot runtime.
public typealias BotConfiguration = ClientConfiguration
/// Independent bounded broadcast event hub used by the consumer runtime.
public typealias EventHub = GatewayEventHub

/// A typed Discord identifier, available from the umbrella product.
/// Import `DiscordCore` directly when only portable values are needed.
public typealias Snowflake<Tag> = DiscordCore.Snowflake<Tag>
/// A Discord user identifier preserving all 64 bits.
public typealias UserID = DiscordCore.UserID
/// A Discord channel identifier preserving all 64 bits.
public typealias ChannelID = DiscordCore.ChannelID
/// A Discord guild identifier preserving all 64 bits.
public typealias GuildID = DiscordCore.GuildID
/// A Discord message identifier preserving all 64 bits.
public typealias MessageID = DiscordCore.MessageID
/// A Discord application identifier preserving all 64 bits.
public typealias ApplicationID = DiscordCore.ApplicationID
/// A bounded, lossless JSON tree; use its explicit parser for numeric lexeme fidelity.
public typealias JSONValue = DiscordCore.JSONValue
/// Resource bounds for untrusted JSON input/output.
public typealias JSONLimits = DiscordCore.JSONLimits
/// An exact JSON number spelling, including unknown future numeric formats within JSON grammar.
public typealias JSONNumber = DiscordCore.JSONNumber
/// A request/update field whose omitted, null and value states remain distinct.
public typealias Field<Value> = DiscordCore.Field<Value>
/// A required response field that accepts explicit null.
public typealias Nullable<Value> = DiscordCore.Nullable<Value>
/// An ISO-8601 timestamp retaining its validated original precision and spelling.
public typealias DiscordTimestamp = DiscordCore.DiscordTimestamp
/// Typed credential selection with redacted ordinary diagnostics.
public typealias Credential = DiscordCore.Credential
/// A bot token requiring explicit access to reveal its contents.
public typealias BotToken = DiscordCore.BotToken
/// Typed failures distinguishing cancellation and unknown mutation outcomes.
public typealias DiscordError = DiscordCore.DiscordError
