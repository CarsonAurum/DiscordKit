# Part 15L authoring candidate

The unpublished 0.15.0 candidate completes the locally verifiable Phase 15
documentation and release milestone on 2026-10-18. Upstream announcement/effective
dates are unknown: this milestone changes no Discord wire contracts or support
classifications. Existing reviewed sources and the weekly maintenance record
continue to govern those contracts; no fresh upstream semantic review is claimed.

The [design](../../DSLDesign.md), [adoption](../../DSLAdoption.md) and
[migration](../../Migration.md) guides connect the independently selected shared,
command, bot, macro and extension products. DocC tutorials display source listings
from independently compiled examples. Source auditing includes all macro package
subtrees; separate tests inspect actual emitted callable syntax and its comments.
Neither check proves semantic documentation completeness.

The macOS arm64 API comparison against the preserved 0.14.0 baseline has 1,010
additions, no changed/removed symbols and no removed relationships. Additions
include three command preparation/interception observations in DiscordCommands;
the remainder belongs to the three new DSL modules. The conservative pre-1.0 minor
version policy accepts 0.15.0. Separately named root, macro and extension 0.15.0
baselines now detect drift in current CI. Existing direct consumers need no
migration; adoption and command registration remain explicit.

The [new report](../../Release/phase15l-report.json) selects current local checks,
preserving the 15K and earlier hash-bound reports. The 15K workload/soak artifacts
remain historical measurements of unchanged runtime/benchmark source. They are
not new timing runs or production/fleet capacity evidence. Unrun platforms,
devices, live Discord, independent crypto review, complete-client interoperability,
binary ABI and other-platform APIs remain excluded. No publication or tag occurs.
