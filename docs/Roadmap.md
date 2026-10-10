# Sublang roadmap and open work

Updated **October 11, 2026**. This is the central engineering backlog. It distinguishes existing capabilities, remaining implementation work, planned platform features and optional ideas. It contains no delivery-date or percentage-complete promise.

Usage: [IR developer guide](Sublang_IR_Guide.md). Actual memory contracts: [HyperAlloc IR](HyperAlloc_IR.md). Detailed original-runtime comparison: [Flow parity](Flow_Parity.md).

## Status vocabulary

- **Implemented:** an executable path exists within the documented native subset.
- **Partial:** some data structures or paths exist, but the broader contract is incomplete.
- **Planned:** part of the intended platform; not currently a usable feature.
- **Idea:** a possible addition needing design/priority approval.
- **Archived:** preserved history outside active implementation scope.

All eight Flow families being implemented does not mean every old Flow case, language feature, target or performance characteristic is covered.

## Working baseline

| Area | Current implementation |
| --- | --- |
| Product | Standalone Emerald-built Sublang executable reads Wire and emits LLVM plus a plan |
| Input | Wire v2, v1 core input compatibility, frozen High IR, explicit feature/version rejection |
| IR | Typed functions/blocks/SSA, scalar block arguments, loops, source spans and semantic records |
| Scalars | Signed i64, checked/wrap operations, f64/RNE, Bool and static String |
| Values | Primitive/String Records, supported contiguous value lists |
| Ownership | Scope cleanup, initialization checks, moves, borrowed calls, owned parameters/results |
| Objects | Exclusive Class graphs, child take/clear/replace, iterative destruction |
| Flow | Folded, Local, Inline, Shard, Pool, Root, Bond and Static native paths |
| Sharing | Counted Bond roots/edges, cycle trial deletion and revision-checked SCC cache |
| Optimind | Safe scalar folding/identities and bounded closed-body call/getter transformations |
| Native build | LLVM verification, optimization levels 0–3, linking and optional sandboxed run |
| C | Ordinary source through Clang/LLVM; no High-IR ownership importer |
| Evidence | Bundled LLVM/native output checks and focused ASan/LSan memory checks |

The generic verifier still does not establish universal effect/lifetime proofs. Native codegen additionally checks the accepted closed subset. Public Low IR, general providers and complete pass/snapshot infrastructure are not finished.

## 1. Release hardening — next practical work

### Clear support contract

- [ ] Define the first release's exact accepted IR, runtime semantics, supported host/LLVM versions and resource budgets.
- [ ] Publish a compatibility matrix for transport, IR schema, architecture contracts and compiler versions.
- [ ] Clearly separate supported inputs from illustrative extension examples.
- [ ] Keep failure behavior and unsupported-feature diagnostics deterministic.
- [ ] Document distribution prerequisites independently from the Emerald bootstrap toolchain.

**Completion criterion:** another frontend developer can install/use a pinned compiler version, produce an accepted input and understand rejection without reading undocumented internals.

### Binary packaging and reproducibility

- [ ] Provide a reproducible release artifact build and checksums.
- [ ] Pin/record compatible LLVM/Clang and sandbox-image versions.
- [ ] Define linking/runtime-library assumptions for exported native programs.
- [ ] Add a minimal representative package smoke check and CI artifact export.
- [ ] Keep compiler bootstrap, IR compilation and generated-program execution distinct.

No complete multi-platform binary release or package manager is currently promised.

## 2. IR, pass manager and public API

### Versioned snapshots and passes — partial

- [ ] Implement controlled revision changes/forks for transforming passes.
- [ ] Define analysis cache keys using snapshot/entity identity and target/provider options.
- [ ] Declare required, preserved and invalidated analyses per pass.
- [ ] Verify structural, semantic and memory invariants after relevant transformations.
- [ ] Preserve source/origin mappings and explicit entity remapping through lowering.
- [ ] Bound analysis memory/time for larger modules instead of only increasing input limits.

**Completion criterion:** a pass can transform a module without stale lifetime/alias/effect facts being reused.

### Effect and alias analyses — partial

- [ ] Derive interprocedural effect summaries from closed bodies, including recursive SCC fixpoints.
- [ ] Connect reads/writes, escape edges, borrow provenance and invalidation to shared logical locations.
- [ ] Validate effective declared/conservative/proven facts and diagnose contradictions.
- [ ] Handle unknown targets conservatively; add external contracts only with explicit ABI/trust rules.
- [ ] Derive LLVM attributes only from sufficient effective guarantees.
- [ ] Expand alias reasoning beyond currently accepted direct/borrow patterns.

**Completion criterion:** transformations use current analysis results rather than frontend proof labels alone.

### Transport and library boundaries — partial

- [ ] Publish a self-contained record-level Wire specification with conformance examples.
- [ ] Define long-term schema/version compatibility and optional metadata rules.
- [ ] Add explicit capability discovery for features, targets, passes and providers.
- [ ] Design request/result records and structured errors without exposing Emerald layouts.
- [ ] Consider a separately versioned C ABI with opaque handles after process integration stabilizes.
- [ ] Provide foreign-language writer examples/SDKs once the encoding contract is pinned.

Wire v2 is already usable; a full Hello/Submit/Result RPC service and stable native ABI are not implemented.

### Canonical Low IR — planned

- [ ] Represent concrete layout, allocation, lifetime, drop and runtime calls explicitly.
- [ ] Tie Low IR to the consumed memory plan, revision, target and provider.
- [ ] Verify High-to-Low entity/layout mappings.
- [ ] Define serialization only after the executable Low-IR contract is coherent.

## 3. HyperAlloc Flow coverage and parity

### Object representation and escape

- [ ] Broaden Folded/value inference across richer aggregates and methods.
- [ ] Support additional provably safe identity contracts before accepting identity-observing operations.
- [ ] Extend interprocedural escape/lifetime reasoning beyond current closed cases.
- [ ] Add safe reference/block-argument merges and richer mutable-view provenance.
- [ ] Keep FFI/observable layout as explicit blockers or adapter boundaries.

Current Inline class-list inference is real, including mutable declarations under consuming/read-only usage. Arbitrary mutable inline aliases are not supported.

### Regions and reuse

- [ ] Add cross-function region escape/transfer contracts.
- [ ] Evaluate chunk reuse and region retention policies.
- [ ] Expand profitable reset/reuse cases while preserving cleanup order.
- [ ] Tune bounded Pool caches using representative workloads.
- [ ] Distinguish lifetime safety from profitability decisions in structured Explain.

Dependent nested Shard joins and bounded exact-layout caches already work. Their current profitability heuristics are conservative, not universal cost models.

### Shared graph runtime

- [ ] Design arbitrary Root/Bond transitions and mixed-graph invariants before enabling them.
- [ ] Measure SCC reverse-visitor costs against the original incoming-edge implementation.
- [ ] Broaden shared alias analysis without weakening view invalidation.
- [ ] Design weak references, observable finalizers/destructors and concurrency independently.
- [ ] Specify publication, atomic root/edge operations and thread-local/global runtime state if threads are added.

The original trial-deletion/component-cache strategy has been adapted to neutral IR. Equivalent performance and full original-runtime compatibility have not been established. Weak refs, finalizers and threads are open design work, not silently supported.

### Strings and collections

- [ ] Add dynamic strings with explicit allocation, encoding and ownership contracts.
- [ ] Add concatenation/builders and measured reuse strategies.
- [ ] Consider additional containers through real layout/effect/invalidation contracts.
- [ ] Define safe mutable element views or mutation APIs with explicit alias rules.
- [ ] Evaluate larger-length variants only when required; current list lengths/capacity are i32.

## 4. Optimind expansion

- [ ] Broader constant/range propagation across CFGs.
- [ ] Effect-safe dead computation/call removal.
- [ ] Interprocedural specialization/inlining with bounded growth.
- [ ] Proven devirtualization after OO dispatch contracts exist.
- [ ] Loop transformations where overflow, failure and FP semantics permit.
- [ ] Layout-aware allocation/representation optimizations beyond current classes/lists.
- [ ] Stable pass ordering, controls and decision reporting.

Keep optimization language-neutral. Do not hard-code benchmark names, expected outputs or source-specific shortcuts.

## 5. LLVM, targets and build optimization

- [ ] Define explicit target triples, data layouts, calling conventions and runtime-provider selection.
- [ ] Expand beyond the current native64/host-libc assumptions deliberately.
- [ ] Add LTO with consistent compile/link controls.
- [ ] Add PGO training, profile provenance, compatibility checks and reproducible use.
- [ ] Design separate/object/library output modes and multi-module linking.
- [ ] Define a runtime ABI for linked modules, caches and symbol visibility before broader composition.

LLVM optimization levels already exist. They do not imply LTO or PGO support.

## 6. Frontends and language features

### Independent frontend — planned

- [ ] Build a small second frontend with documented source semantics.
- [ ] Exercise procedural values and ownership without importing an Emerald AST.
- [ ] Produce actual Wire from another implementation language.
- [ ] Keep frontend syntax/type rules outside the neutral core.

### C semantic import — partial entry, planned analyses

- [ ] Retain the existing ordinary C → Clang/LLVM path.
- [ ] Design effect/alias/escape summaries for imported LLVM.
- [ ] Define supported allocation ownership and external-call boundaries.
- [ ] Enable High-IR/Flow transformations only after the necessary semantics are recoverable/provided.

Do not infer that arbitrary C pointers obey Flow ownership. --flow=on remains rejected until a supported import contract exists.

### Dynamic AOT — planned active requirement

- [ ] Specify a small dynamic-language profile: numeric promotion, truthiness, equality, properties and failures.
- [ ] Implement tagged values, type tests, checked box/unbox and runtime fallbacks.
- [ ] Keep a genuinely heap-backed value alive across an allocating call and release it correctly.
- [ ] Add property/index operations and closure/capture contracts.
- [ ] Show at least one explained effect/alias blocker.
- [ ] Verify through the same neutral backend and memory contracts.

A tagged-Int-only demo is insufficient. Full Python/JavaScript compatibility is not promised; JIT/deoptimization is a separate idea.

### Object-oriented expansion — planned

- [ ] Interfaces, inheritance and explicit dispatch sets.
- [ ] Object identity/reflection/layout observability contracts.
- [ ] Direct/virtual call effect summaries.
- [ ] Closures with captures whose lifetimes/ownership are explicit.

Classes and direct calls already work; these broader OO features do not.

### Exceptions and cleanup — planned

- [ ] FailureAction throw semantics and exception payload ownership.
- [ ] Invoke with explicit normal/exceptional successors and edge-defined results.
- [ ] Catch/filter/rethrow/resume and cleanup on every required exit.
- [ ] Correct language-defined finally order and secondary exceptions.
- [ ] LLVM EH/personality integration per target/runtime.

Abort-only behavior must never silently replace requested exceptions.

## 7. Debugging, Explain and developer experience

- [ ] Structured decisions/diagnostics with stable codes, entities, revisions and blockers.
- [ ] Report the call/alias/effect preventing a placement and the selected safe alternative.
- [ ] Optional before/after snapshots and bounded proof graphs.
- [ ] Preserve usable source locations/debug information through lowering.
- [ ] Add an IR inspection/dump command and eventually consider a textual input parser.
- [ ] Add documented editor/tooling integration after interfaces stabilize.

Current memory explanations are text; they are not the final protocol.

## 8. Measurement and focused validation

- [ ] Record a representative performance/RSS baseline for allocation, numeric, string and graph workloads.
- [ ] Compare equal algorithms, inputs, outputs, compiler settings and hardware.
- [ ] Separate compilation cost from program runtime.
- [ ] Measure both Flow-off and Flow-on and document all non-comparable cases.
- [ ] Establish original-runtime compatibility only through explicit mapped cases.
- [ ] Keep sanitizer checks focused on changed memory boundaries.

Existing tests establish correctness/placement evidence, not speed claims. All compiler/program execution stays sandboxed at at most 8 GB, preferably the existing 6 GB/no-swap configuration. Batch meaningful checks; do not rebuild everything after editorial changes.

## 9. Optional ideas requiring design and prioritization

- **Textual IR parser/printer:** convenient authoring after the grammar/version contract is defined.
- **SDKs/bindings:** writers and diagnostic readers for Rust, C/C++ and other frontend languages.
- **Incremental compilation:** dependency-aware module/function caching tied to revisions and target options.
- **Interactive IR explorer:** visualize CFG, ownership, region dependencies and Explain blockers.
- **Additional targets:** AArch64 or WebAssembly after layout/runtime contracts are explicit.
- **JIT/speculative specialization:** requires guards, invalidation, deoptimization and stack maps.
- **Parallel compilation/runtime:** requires thread-safe analyses and explicit Flow concurrency semantics.
- **Advanced data layout:** broader aggregate flattening, field splitting and locality transformations under identity/ABI rules.

These are candidates, not accepted first-release requirements.

## 10. Archived and outside active scope

Foreign tracing/moving-GC integration, relocation roots/barriers/safepoints and the old hyperalloc-integration mode remain in [the archive](../archive/gc-integration/readme.md). Dynamic typing remains active and does not imply reactivating those designs.

Sublang does not currently update Emerald, migrate Emerald selfhost, replace arbitrary language runtimes or generate a fused language. Any future Emerald frontend/selfhost integration is a separate project decision, not a prerequisite for the current standalone Wire path.

## Suggested sequence

1. Freeze/document the usable release subset and reproducible packaging.
2. Establish versioned passes, analysis invalidation and structured decisions.
3. Stabilize transport/capabilities and demonstrate an independent frontend.
4. Broaden Flow/Optimind with measured parity cases and required semantics.
5. Implement the Dynamic AOT slice and expand OO/EH through explicit contracts.

Parallelism between these workstreams is possible when interfaces are agreed. Completion is evaluated against executable contracts and evidence, not feature-name counts.
