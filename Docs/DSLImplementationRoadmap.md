# Modular bot authoring implementation

Phase 15 is delivered as independently usable milestones. **15A** implements the
shared structural foundation in `DiscordDSL`; this status does not imply that the
complete bot authoring experience is available. See [shared declarations](DSL.md)
for the implemented API and [architecture](Architecture.md) for product boundaries.

| Milestone | Status | Scope |
| --- | --- | --- |
| 15A | Implemented | Protocol/module composition, result builders, stable explicit identities, source diagnostics and bounded deterministic descriptions. |
| 15B | Planned | Typed argument schemas/decoding and lowering to existing command definitions/routes. |
| 15C | Planned | Separate authoring macro package, diagnostics and compiled expansion parity. |
| 15D | Planned | Immediate/deferred/manual response ownership and independently adopted HTTP command application. |
| 15E | Planned | Validated message/component builders and safe typed interpolation. |
| 15F | Planned | Remaining command families, explicit registration and reconciliation. |
| 15G | Planned | Bounded policies, middleware and named/operator composition. |
| 15H | Planned | Typed Gateway handlers over existing bounded subscriptions/dispatch. |
| 15I | Planned | Bot application and supervised client/interaction lifetime. |
| 15J | Planned | Independent external extensions, typed dependency validation and consumer adoption. |
| 15K | Planned | Compile-time and direct-versus-DSL runtime measurements, finite budgets and DSL-specific soak evidence. |
| 15L | Planned | Complete DSL adoption/migration guides and full Phase 15 release certification. |

15A's immutable descriptions can be inspected and compared offline. The description
contains only metadata; the plan also retains typed contributions without executing
them or owning a runtime. Future command and bot products will reuse the existing
command, interaction and client implementations; they may depend on the
shared foundation, while existing products keep their independent adoption graphs.
The macro package remains a separate consumer of runtime products, with no compiler
plugin or SwiftSyntax dependency in the shared product.

Structural admission limits describe finite compilation resources. They do not
establish network throughput, bot population, live Discord interoperability or
production capacity. Later milestones require their own implementation, tests,
independent consumers and evidence before those behaviors are claimed.
