# Archived GC integration design

Archived on 2026-10-10 at the user's request. These files preserve earlier proposals,
not the active roadmap, supported features, or implementation instructions.

Foreign collector integration, moving-GC roots/barriers/safepoints, and the
`hyperalloc-integration` mode are out of the active scope. HyperAlloc Flow remains
optional as its own ownership/lifetime/allocation system. Language independence,
Optimind, static and dynamic IR, and LLVM lowering remain active goals.

`previous-project-readme.md`, `docs/`, and `examples/` are historical snapshots;
their original links and claims describe the earlier design. Dynamic and Explain
examples in the active tree now use explicit ownership instead of collector hooks.
