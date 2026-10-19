# Part 15L execution

Scope: finish the locally verifiable 0.15.0 authoring candidate after the committed
15K measurement checkpoint. Preserve the existing staged roadmap and historical
reports/baselines. No package publication or tag.

1. Review 15K evidence and 15L acceptance criteria against current source.
2. Add adoption/design/migration guidance and compiler-derived DocC navigation.
   Synchronize tutorial listings with independent HTTP, Gateway and extension
   packages. Audit macro source and generated callable documentation.
3. Emit root/macro/extension public graphs, review the 0.14.0 comparison, then
   capture separately named 0.15.0 baselines. Wire current CI comparisons to them.
4. Run root/tooling tests, external compiler fixtures, independent consumers and
   offline modes, graph/inventory/generation/parity/docs/API/maintenance checks.
   Preserve the 15K measurements as historical workload evidence; no runtime or
   benchmark workload implementation changes are planned here.
5. Append local authoring release history and a new hash-bound report with current
   validation. Exclude unavailable platform/live/hardware/crypto/interop, semantic
   completeness and production/fleet qualification.
6. Review diff and staged scope, commit only Part 15L changes, report exact commit
   and validation limits.
