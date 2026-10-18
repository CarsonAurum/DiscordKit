# Shared module declarations

Part 15A adds the independently adopted `DiscordDSL` product. Ordinary Swift
protocols and a result builder compose declarations into a reproducible, immutable
metadata description. The only direct dependencies are `DiscordCore` and
`DiscordModels`; existing products have no upward dependency on the DSL.

The shared product implements structural authoring and validation. Part 15B adds
[typed arguments and command lowering](CommandDSL.md) through the separately
selected `DiscordCommandDSL` product. Macros, response builders, policies, HTTP
hosts and Gateway execution remain later
[implementation milestones](DSLImplementationRoadmap.md).
An application can use the raw contribution API now to validate its own finite
metadata catalog, without pretending that a custom kind implements a Discord API.

## Declare and compile a finite catalog

Select the `DiscordDSL` library product explicitly in the consuming package, then
construct an identified module and allowlist the metadata kinds its compiler
supports:

```swift
import DiscordDSL

let source = DefinitionSourceLocation(fileID: "Guide/Modules.swift", line: 1, column: 1)
let includeRules = true
let module = Module(id: "community", source: source) {
    RawDefinitionContribution(
        id: "community.help", kind: "guide.note",
        requiredCapabilities: ["local.describe"], text: "Help catalog", source: source)
    if includeRules {
        RawDefinitionContribution(
            id: "community.rules", kind: "guide.note", text: "Rules catalog", source: source)
    }
    for suffix in ["first", "second"] {
        RawDefinitionContribution(
            id: "community.\(suffix)", kind: "guide.note", source: source)
    }
}

let plan = try DefinitionPlan.compile(
    module,
    supportedKinds: ["guide.note"],
    capabilities: ["local.describe"])
assert(plan.description.declarations.map(\.declaration.id) == [
    "community.help", "community.rules", "community.first", "community.second"
])
```

Kinds and capabilities are application-defined exact identifiers. Both compiler
allowlists default to empty: unsupported kinds or required capabilities fail
closed. The example's names describe local metadata and grant no permissions,
intents or network access. Raw metadata supports `JSONValue` payloads through
`DiscordCore`; payloads retain exact numbers and use deterministic compact JSON
serialization for byte accounting.

`BotModule` provides a reusable associated `Body`, an explicit `moduleID` and a
source coordinate. Its default collection admits the module before evaluating
the body. `Module` is the convenient primitive: its initializer evaluates its
builder once and stores the resulting body. `BotBuilder` supports nested modules,
empty blocks, conditionals, `switch`, availability branches, homogeneous or
heterogeneous definition arrays and finite loops in source/iteration order.
Every builder group, even an empty one, participates in structural admission.

## Extension and ownership contract

Custom leaves conform to `DefinitionContribution` and expose one deterministic
`RawDefinitionContribution` snapshot. Its default collection calls the shared
collector admission path. `DefinitionPlan.contributions` retains the typed leaf
values aligned with the immutable declaration description, allowing an
explicit downstream compiler such as `CommandCompilation` to recover typed authoring
information. Collection never invokes an execution method on those values.

Custom composites conform to `BotDefinition` and implement synchronous
`collect(into:)`. Use `DefinitionCollector.withStructure(source:_:)` before
expanding children, `withModule(id:source:_:)` for identified modules and `append`
for leaves. Propagate failures. A failed collector remains terminal even if custom
code catches the error, so compilation cannot return a successful partial plan.
Do not copy or retain the collector for later/concurrent use. Each compilation
has isolated state; it starts no task and has no suspension point.

Owned construction and compilation perform no I/O, environment reads,
subscriptions, command registration, handler execution or persistence. Arbitrary
user builder expressions, module bodies and contribution getters remain ordinary
Swift: they must terminate cooperatively and avoid side effects. Validation bounds
the compiler's admitted state. It cannot preempt arbitrary Swift code or reclaim
memory already allocated while a caller constructs an array or loop body.

## Admission and diagnostics

`DefinitionLimits` has the following configurable defaults:

| Limit | Default | Meaning |
| --- | --- | --- |
| `maxModules` | 256 | Globally unique installed module instances. |
| `maxDepth` | 32 | Simultaneously open module, builder-group and contribution scopes; valid range `1...128`. |
| `maxDeclarations` | 4,096 | Admitted leaf contributions. |
| `maxTextBytes` | 1,048,576 | Aggregate UTF-8 metadata and compact JSON payload bytes. |
| `maxStructuralNodes` | 16,384 | All visited structural scopes, including empty groups. |

Count/byte budgets accept zero and reject negatives. The depth hard ceiling limits
recursive collector expansion. IDs, kinds and capability names must be nonempty,
at most 128 UTF-8 bytes and contain no ASCII controls, including DEL. Module IDs
are globally unique across the plan; declaration IDs are independently globally
unique. Installing the same reusable module twice requires distinct explicit IDs,
even beneath different parent modules. Names are never inferred from type names,
reflection or dictionary enumeration.

Text accounting includes module IDs/source labels; declaration IDs, kinds, text,
source labels and required capability names; and each payload's serialized bytes.
A label repeated by multiple declarations is charged for each declaration. JSON
also enforces 64-container-depth and 100,000-node limits, and the remaining text
budget is enforced during serialization. A bounded preflight checks JSON shape and
raw text before sorting object keys or escaping strings; shape failures take
precedence over payload byte failures independent of dictionary iteration order.
Source coordinates are metadata and do
not cause source files to be read. Use explicit coordinates for reproducible
cross-file examples; unavailable/synthetic line and column values are zero.

Compilation throws the first `DefinitionDiagnostic` for invalid limits/identities,
duplicates, unsupported kinds/capabilities, count/depth/text/structure exhaustion
or malformed/oversized payloads. The diagnostic retains a bounded source label
and ancestor module path, without declaration text or payload contents. Custom
expansion errors propagate. No partial plan is returned; correct the declaration,
allowlist or explicit budget before compiling again.

`DefinitionDescription` equality compares exact module/declaration order, metadata,
coordinates and accounting. Modules use preorder and declarations use depth-first
source order. Equality does not compare executable behavior retained by custom
leaf values. Structural limits and local tests provide no network throughput,
platform, live Discord, macro, command/event execution or fleet-capacity evidence.
See [the authoring-only history](Parity/changes/phase15-dsl.md).
