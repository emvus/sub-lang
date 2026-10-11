# Sublang roadmap and open work

Updated **October 11, 2026**. This is the central engineering backlog. It distinguishes existing capabilities, remaining implementation work, planned platform features and optional ideas. It contains no delivery-date or percentage-complete promise.

Implementation sequence and engineering defaults: [remaining implementation brief](Implementation_Plan.md). This link is a plan, not a completion claim.

**Runtime IR requirement:** language compilers supply runtime implementations as IR,
with Linux, Windows and macOS as required platform families. The first
[Runtime IR slice](Sublang_Runtime_IR.md) binds self-contained High/Wire runtime bodies
before Optimind/Flow and emits native Linux x86-64 LLVM. Other platform identities are
recognized but fail codegen explicitly. OS imports, raw-memory/ABI boundaries, platform
providers, target SDKs and a versioned runtime manifest remain open; no complete portable
OS runtime or libc-independent backend is claimed.

Usage: [IR developer guide](Sublang_IR_Guide.md). Actual memory contracts: [HyperAlloc IR](HyperAlloc_IR.md). Detailed original-runtime comparison: [Flow parity](Flow_Parity.md). Newer contracts: [Wire extensions](Sublang_Extensions.md), [Text IR](Sublang_Text_IR.md), [Low IR](Sublang_Low_IR.md), [Passes and effects](Sublang_Passes_And_Effects.md).

## Status vocabulary

- **Implemented:** an executable path exists within the documented native subset.
- **Partial:** some data structures or paths exist, but the broader contract is incomplete.
- **Planned:** part of the intended platform; not currently a usable feature.
- **Idea:** a possible addition needing design/priority approval.
- **Archived:** preserved history outside active implementation scope.

Bullet annotations: a checked box names the check that covers it. `*Partial:*` and `*Not implemented:*` give the precise gap. `*In progress:*` marks work that is outside the checks listed here.

All eight Flow families being implemented does not mean every old Flow case, language feature, target or performance characteristic is covered.

## Working baseline

| Area | Current implementation |
| --- | --- |
| Product | Standalone Emerald-built Sublang executable: `emit-llvm` (LLVM plus plan), `link`, `dump`, `dump-low`, `text-dump`, `text-build`, `capabilities` |
| Input | Wire transport 2 with the core token and declared extension tokens (`ext.bytes.v1`, `ext.numeric.v1`, `ext.eh.v1`, `ext.oo.v1`); transport 1 core input; frozen High IR; canonical text through `text-build`; explicit feature/version rejection |
| IR | Typed functions/blocks/SSA, scalar block arguments, loops, source spans and semantic records |
| Scalars | Signed i64, checked/wrap operations, f64/RNE, Bool and static String; exact Int/Float conversions (`ext.numeric.v1`) |
| Values | Primitive/String Records, supported contiguous value lists, byte lists (`ext.bytes.v1`) |
| Ownership | Scope cleanup, initialization checks, moves, borrowed calls, owned parameters/results |
| Objects | Exclusive Class graphs, child take/clear/replace, iterative destruction; single-inheritance classes with closed-world virtual dispatch (`ext.oo.v1`) |
| Exceptions | `Int`-coded `invoke`/`throw`/`resume` on the Itanium C++ ABI (`ext.eh.v1`), exactly-once cleanup on throw and catch |
| Flow | Folded, Local, Inline, Shard, Pool, Root, Bond and Static native paths |
| Sharing | Counted Bond roots/edges, cycle trial deletion and revision-checked SCC cache |
| Passes | Snapshot passes `optimind.fold` and `optimind.dce` with rejection fallback; derived interprocedural effects |
| Optimind | Safe scalar folding/identities, bounded closed-body call/getter transformations, per-function decision count |
| Low IR | Function bodies lowered to verified Low IR for `native64-host-libc`; provider runtime text is still legacy |
| Native build | LLVM verification, optimization levels 0–3, output kinds exe, obj, bc and ll (`--emit`), LTO off, full or thin (`--lto`), PGO off, train or use (`--pgo`), linking and optional sandboxed run |
| C | Ordinary source through Clang/LLVM; no High-IR ownership importer |
| Evidence | Bundled LLVM/native output checks, ASan/LSan memory checks, text round trip, Tiny frontend, output-mode checks, pass/effect checks |

The generic verifier still does not establish universal effect/lifetime proofs. Native codegen additionally checks the accepted closed subset. Low IR is verified but incomplete (drop visitors, Bond trace routines and runtime bodies are still legacy text); no general provider exists; the pass infrastructure is limited to the two Optimind passes.

## 1. Release hardening — next practical work

### Clear support contract

- [x] Define the first release's exact accepted IR, runtime semantics, supported host/LLVM versions and resource budgets. See [Release contract](Sublang_Release_Contract.md); unverified items are listed there.
- [x] Publish a compatibility matrix for transport, IR schema, architecture contracts and compiler versions (Release contract, section 4).
- [x] Clearly separate supported inputs from illustrative extension examples (Release contract; `examples/wire` and `examples/frontend` are inputs, `examples/ir` is not).
- [ ] Keep failure behavior and unsupported-feature diagnostics deterministic. *Partial:* codes are cataloged in [Diagnostics](Sublang_Diagnostics.md), which also lists inconsistencies still to fix. The `SUBLANG-TX` text codes are not in that catalog (see [Text IR](Sublang_Text_IR.md)). Diagnostics are text, not structured.
- [x] Document distribution prerequisites independently from the Emerald bootstrap toolchain (Release contract and [Packaging](Sublang_Packaging.md)).

**Completion criterion:** another frontend developer can install/use a pinned compiler version, produce an accepted input and understand rejection without reading undocumented internals.

### Binary packaging and reproducibility

- [x] Provide a reproducible release artifact build and checksums (`scripts/sublang-package.sh`; deterministic tar.gz with SHA256SUMS).
- [x] Pin and validate LLVM/Clang and the sysroot-image identity for the Linux full bundle. The release lock selects LLVM 23.1.3; every required executable is validated before builds. The legacy thin package remains separate.
- [ ] Define linking/runtime-library assumptions for exported native programs. *Partial:* the package manifest and [Packaging](Sublang_Packaging.md) cover the sandbox libc; they do not yet state that `ext.eh.v1` programs need `libstdc++`. `scripts/sublang-build-worker.sh` adds `-lstdc++` when the IR contains `__gxx_personality_v0`.
- [ ] Add a minimal representative package smoke check and CI artifact export. *Partial:* `scripts/sublang-package-smoke.sh` exists and passes; there is no CI export.
- [ ] Keep compiler bootstrap, IR compilation and generated-program execution distinct. *Partial:* they are separate scripts (`sublang-bootstrap.sh`, `sublang-build.sh`, `sublang-build-worker.sh`); no check enforces the separation.

No complete multi-platform binary release or package manager is currently promised.

The Linux full bundle (`sublang-package.sh --with-llvm`) includes tools, private loader/libraries,
Clang resources and a C sysroot. See [Bundled LLVM](Sublang_Bundled_LLVM.md). The installed
driver currently uses Bash for process orchestration; a native Emerald driver, signed releases,
corresponding-source publication and CI exports remain open.

## 2. IR, pass manager and public API

### Versioned snapshots and passes — partial

- [x] Implement controlled revision changes/forks for transforming passes. `manager.fork` validates a deep copy in an independent lineage; stale-parent commits are independently rejected by the store.
- [x] Define analysis cache keys using snapshot identity and target/provider options. Keys include cache-local store identity, lineage, revision, analysis/version, target, provider, ABI, profile selector and options. Mutable drafts bypass caching.
- [ ] Declare required, preserved and invalidated analyses per pass. *Partial:* the two Optimind passes declare `requires`/`preserves`; only the call graph is preserved, and everything else is invalidated implicitly.
- [x] Verify structural, semantic and memory invariants after relevant transformations for the accepted native subset. Each candidate receives separate verdicts before commit; the target-specific lifetime check is mandatory. Additional runtime proof contexts remain unsupported.
- [ ] Preserve source/origin mappings and explicit entity remapping through lowering. *Partial:* the origin-map check passes; Low operations keep the High operation id, and entity remapping is not a documented contract.
- [ ] Bound analysis memory/time for larger modules instead of only increasing input limits. *Partial:* resource limits precede verification; effect fixpoints are bounded; each analysis cache table retains at most 64 entries. Byte budgets and snapshot-history reclamation remain open.

**Completion criterion:** a pass can transform a module without stale lifetime/alias/effect facts being reused.

### Effect and alias analyses — partial

- [x] Derive interprocedural effect summaries from closed bodies, including recursive SCC fixpoints. Covered by the `effects` checks of `scripts/sublang-pass-sandbox.sh` (pure, read, write, allocate and recursive summaries).
- [ ] Connect reads/writes, escape edges, borrow provenance and invalidation to shared logical locations. *Partial:* effect areas and locations are derived; borrow invalidation is checked by the ownership rules, not by the same location model.
- [ ] Validate effective declared/conservative/proven facts and diagnose contradictions. *Partial:* derived facts drive decisions and contradictions (`SUBLANG-E008`) appear in the memory plan; a complete structured proof protocol remains open.
- [ ] Handle unknown targets conservatively; add external contracts only with explicit ABI/trust rules. *Partial:* unknown targets widen to unknown and the native subset rejects external contracts; no external contract form exists.
- [ ] Derive LLVM attributes only from sufficient effective guarantees. *Partial:* attributes follow the `memoryFree()` predicate; sufficiency against every proof label is not established.
- [ ] Expand alias reasoning beyond currently accepted direct/borrow patterns. *Not implemented:* alias facts remain within the accepted patterns.

**Completion criterion:** transformations use current analysis results rather than frontend proof labels alone.

### Transport and library boundaries — partial

- [x] Publish a self-contained record-level Wire specification with conformance examples ([Wire specification](Sublang_Wire_Spec.md); negative cases verified against the binary). Extension tokens are described in [Wire extensions](Sublang_Extensions.md).
- [ ] Define long-term schema/version compatibility and optional metadata rules. *Partial:* extension tokens are declared exactly when used and unknown tokens are rejected; no long-term compatibility policy exists.
- [x] Add explicit capability discovery for implemented features, targets, passes and providers. `sublang capabilities` lists core/extension tokens, the target/provider, Low IR, passes and unsupported features.
- [ ] Design request/result records and structured errors without exposing Emerald layouts. *Not implemented:* no request/result record format exists.
- [ ] Consider a separately versioned C ABI with opaque handles after process integration stabilizes. *Not implemented:* no C ABI exists.
- [ ] Provide foreign-language writer examples/SDKs once the encoding contract is pinned. *Partial:* the Python Tiny frontend writes Wire (`scripts/sublang-tiny-check.sh`); no SDK exists, and the encoding is not pinned.

Wire v2 is already usable; a full Hello/Submit/Result RPC service and stable native ABI are not implemented.

### Canonical Low IR — partial

- [ ] Represent concrete layout, allocation, lifetime, drop and runtime calls explicitly. *Partial:* function bodies are Low operations; the `%t` type definitions, runtime bodies, drop visitors and Bond trace routines are still legacy provider text ([Low IR](Sublang_Low_IR.md), section 12).
- [ ] Tie Low IR to the consumed memory plan, revision, target and provider. *Partial:* lowering takes the snapshot, the plan and the explicit target, and binding problems are reported as L010 to L014. The provider is not yet part of the Low module.
- [ ] Verify High-to-Low entity/layout mappings. *Partial:* `SublangLowVerifier` runs before any Low text is used; its gaps are listed in [Low IR](Sublang_Low_IR.md), sections 5.3 and 9.
- [ ] Define serialization only after the executable Low-IR contract is coherent. *Not implemented:* the `dump-low` rendering is not a serialization format and has no parser.

## 3. HyperAlloc Flow coverage and parity

### Object representation and escape

- [ ] Broaden Folded/value inference across richer aggregates and methods. *Partial:* primitive class fields and one-field read-only getters are folded (`folded-fields` and `folded-getter` checks); richer aggregates and methods are not.
- [ ] Support additional provably safe identity contracts before accepting identity-observing operations. *Not implemented:* identity-observing operations are not accepted.
- [ ] Extend interprocedural escape/lifetime reasoning beyond current closed cases. *Not implemented:* the closed cases of the native subset are the only ones.
- [ ] Add safe reference/block-argument merges and richer mutable-view provenance. *Partial:* graph-field `field.borrow` views survive CFG joins only when definitely live; there are no general mutable views.
- [ ] Keep FFI/observable layout as explicit blockers or adapter boundaries. *Partial:* external contracts are rejected (B004); no adapter boundary exists.

Current Inline class-list inference is real, including mutable declarations under consuming/read-only usage. Arbitrary mutable inline aliases are not supported.

### Regions and reuse

- [ ] Add cross-function region escape/transfer contracts. *Not implemented:* Shard and Pool regions are per function invocation only.
- [ ] Evaluate chunk reuse and region retention policies. *Not implemented:* no evaluation exists.
- [ ] Expand profitable reset/reuse cases while preserving cleanup order. *Partial:* Pool reuses frame slots and graph slots (`pool-borrow`, `pool-graph-*` checks); no broader cases exist.
- [ ] Tune bounded Pool caches using representative workloads. *Not implemented:* the caches are bounded (8 blocks per layout, 1 MiB per module) but not tuned; no representative workload exists (section 8).
- [ ] Distinguish lifetime safety from profitability decisions in structured Explain. *Not implemented:* Explain is text only (section 7).

Dependent nested Shard joins and bounded exact-layout caches already work. Their current profitability heuristics are conservative, not universal cost models.

### Shared graph runtime

- [ ] Design arbitrary Root/Bond transitions and mixed-graph invariants before enabling them. *Not implemented:* only the transitions of the native subset are enabled.
- [ ] Measure SCC reverse-visitor costs against the original incoming-edge implementation. *Not implemented:* no measurement exists.
- [ ] Broaden shared alias analysis without weakening view invalidation. *Not implemented:* alias facts stay within the accepted patterns.
- [ ] Design weak references, observable finalizers/destructors and concurrency independently. *Not implemented:* weak references, finalizers and threads are outside the accepted subset (Release contract, section 2.8).
- [ ] Specify publication, atomic root/edge operations and thread-local/global runtime state if threads are added. *Not implemented:* no threads exist.

The original trial-deletion/component-cache strategy has been adapted to neutral IR. Equivalent performance and full original-runtime compatibility have not been established. Weak refs, finalizers and threads are open design work, not silently supported.

### Strings and collections

- [ ] Add dynamic strings with explicit allocation, encoding and ownership contracts. *Partial:* dynamic byte text exists as `List<Byte>` under `ext.bytes.v1` (`text.from_str`, `text.concat`, `text.slice`, `text.equal`, with explicit destination scopes). There is no dynamic `String` type, and the encoding is bytes only.
- [ ] Add concatenation/builders and measured reuse strategies. *Partial:* `text.concat` and `text.append` exist for byte text; there is no builder API and no measured reuse.
- [ ] Consider additional containers through real layout/effect/invalidation contracts. *Not implemented:* only the List family exists.
- [ ] Define safe mutable element views or mutation APIs with explicit alias rules. *Partial:* `list.set` and `list.replace` are bounds-checked mutation APIs that invalidate views; mutable element views are not implemented.
- [ ] Evaluate larger-length variants only when required; current list lengths/capacity are i32. *Not implemented:* no larger variant exists.

## 4. Optimind expansion

- [ ] Broader constant/range propagation across CFGs. *Not implemented:* `optimind.fold` rewrites local scalar operations only; there is no range propagation.
- [ ] Effect-safe dead computation/call removal. *Partial:* `optimind.dce` removes locally dead computation using the derived effects; call removal is limited to what the local analysis proves ([Passes and effects](Sublang_Passes_And_Effects.md), section 11).
- [ ] Interprocedural specialization/inlining with bounded growth. *Not implemented:* there is no inlining; closed-body evaluation covers bounded single-block callees only.
- [ ] Proven devirtualization after OO dispatch contracts exist. *Partial:* a `call.virtual` group with one registered implementation lowers to a direct call (`objects-solo` check); there is no proof-based devirtualization across groups.
- [ ] Loop transformations where overflow, failure and FP semantics permit. *Not implemented:* no loop transformation exists; LLVM passes run downstream only.
- [ ] Layout-aware allocation/representation optimizations beyond current classes/lists. *Not implemented:* only the Folded and Pool/Inline representations exist.
- [ ] Stable pass ordering, controls and decision reporting. *Partial:* the plan carries a per-function Optimind decision count (checked by `scripts/sublang-backend-sandbox.sh`); the pass order is fixed in `SublangCompiler`, and there is no per-decision report or pass control beyond on/off.

Keep optimization language-neutral. Do not hard-code benchmark names, expected outputs or source-specific shortcuts.

## 5. LLVM, targets and build optimization

- [ ] Define explicit target triples, data layouts, calling conventions and runtime-provider selection. *Partial:* the Low target names `native64-host-libc` and triple `x86_64-unknown-linux-gnu` (`dump-low` check in the backend sandbox); the calling convention is `sublang` only, and provider selection is not implemented.
- [ ] Expand beyond the current native64/host-libc assumptions deliberately. *Not implemented:* only `native64-host-libc` exists.
- [x] Add LTO with consistent compile/link controls. `sublang-build.sh --lto=off|full|thin` records the mode in `.config`, and the output-mode checks in `scripts/sublang-modes-check.sh` verify that each mode preserves the result. *Scope:* single-module LTO only; there is no cross-module LTO check and no speedup claim.
- [ ] Add PGO training, profile provenance, compatibility checks and reproducible use. *Partial:* `--pgo=train` and `--pgo=use --profile=DIR` are checked, including rejection of a stale profile (`SUBLANG-PGO001`). Reproducibility of the profile data is not checked, and provenance is limited to the `.profmeta` fields.
- [ ] Design separate/object/library output modes and multi-module linking. *Partial:* `--emit=obj` and `--emit=bc` exist (`sublang-modes-check.sh`); `sublang link` merges Wire modules (backend sandbox). There is no library output, and linking is at the Wire level, not object-file level.
- [ ] Define a runtime ABI for linked modules, caches and symbol visibility before broader composition. *Not implemented:* no runtime ABI is defined; the link check runs one merged program.

LLVM optimization levels (`--llvm-opt`) are separate from `--lto` and `--pgo`. The latter two exist as launcher options with the limits stated above.

## 6. Frontends and language features

### Independent frontend — partial

- [x] Build a small second frontend with documented source semantics ([Tiny](../examples/frontend/tiny/readme.md)).
- [ ] Exercise procedural values and ownership without importing an Emerald AST. *Partial:* Tiny exercises procedural Int values, loops and calls; it has no heap values, so ownership is not exercised.
- [x] Produce actual Wire from another implementation language (Python; checked end to end by `scripts/sublang-tiny-check.sh`).
- [ ] Keep frontend syntax/type rules outside the neutral core. *Not implemented:* no automated check enforces this boundary.

### C semantic import — partial entry, planned analyses

- [ ] Retain the existing ordinary C → Clang/LLVM path. *Partial:* the path exists in `scripts/sublang-build.sh` and `examples/programs/c/points.c`; no check script covers it.
- [ ] Design effect/alias/escape summaries for imported LLVM. *Not implemented:* no LLVM import exists.
- [ ] Define supported allocation ownership and external-call boundaries. *Not implemented:* no import contract exists.
- [ ] Enable High-IR/Flow transformations only after the necessary semantics are recoverable/provided. *Not implemented:* `--flow=on` is rejected with `SUBLANG-C001`.

Do not infer that arbitrary C pointers obey Flow ownership. --flow=on remains rejected until a supported import contract exists.

### Dynamic AOT — planned active requirement (in progress)

*In progress:* a Dyn IR library is being added separately. See [Dynamic profile](Sublang_Dynamic_Profile.md). The profile is a draft, and none of the bullets below is covered by a check in the sandbox scripts.

- [x] Specify a small dynamic-language profile: numeric promotion, truthiness, equality, properties and failures ([Dynamic profile](Sublang_Dynamic_Profile.md), a draft with acceptance tests D1–D6; its "Verified today" table lists what is implemented).
- [ ] Implement tagged values, type tests, checked box/unbox and runtime fallbacks. *Not implemented:* not in the release subset or its checks; in progress separately.
- [ ] Keep a genuinely heap-backed value alive across an allocating call and release it correctly. *Not implemented:* not in the release subset.
- [ ] Add property/index operations and closure/capture contracts. *Not implemented.*
- [ ] Show at least one explained effect/alias blocker. *Not implemented* for dynamic code; the native subset's Explain blockers are text (Passes and effects, section 8).
- [ ] Verify through the same neutral backend and memory contracts. *Not implemented* for dynamic code.

A tagged-Int-only demo is insufficient. Full Python/JavaScript compatibility is not promised; JIT/deoptimization is a separate idea.

### Object-oriented expansion — partial

- [ ] Interfaces, inheritance and explicit dispatch sets. *Partial:* single inheritance and closed-world dispatch groups exist under `ext.oo.v1` (`objects` and `objects-solo` checks). Interfaces are not implemented.
- [ ] Object identity/reflection/layout observability contracts. *Not implemented.*
- [ ] Direct/virtual call effect summaries. *Partial:* `call.virtual` unites the effects of every group entry (`SublangEffectTransfer`); no check covers this directly.
- [ ] Closures with captures whose lifetimes/ownership are explicit. *Not implemented.*

Classes, direct calls, single-inheritance classes and closed-world virtual dispatch work (`ext.oo.v1`). Interfaces, identity/reflection observability and closures do not.

### Exceptions and cleanup — partial

- [ ] FailureAction throw semantics and exception payload ownership. *Partial:* exceptions carry an `Int` code only (`ext.eh.v1`). There is no payload object, and failure actions remain `abort`.
- [x] Invoke with explicit normal/exceptional successors and edge-defined results. Scope: body callees; results `Void`, `Int`, `Bool` or `Float`. Covered by the `exceptions` check of `scripts/sublang-backend-sandbox.sh`.
- [ ] Catch/filter/rethrow/resume and cleanup on every required exit. *Partial:* the landing pad catches `long` codes and `resume` rethrows (`exceptions` check); there is no filter and no catch in High IR. Throw or resume while a scope is active is rejected by a source rule (B005) that no test asserts.
- [ ] Correct language-defined finally order and secondary exceptions. *Not implemented:* there is no finally construct and no secondary-exception handling.
- [ ] LLVM EH/personality integration per target/runtime. *Partial:* the Itanium personality `__gxx_personality_v0` is used for `native64-host-libc` only; `scripts/sublang-build-worker.sh` adds `-lstdc++`. No other target or runtime is covered.

Abort-only behavior must never silently replace requested exceptions.

## 7. Debugging, Explain and developer experience

- [ ] Structured decisions/diagnostics with stable codes, entities, revisions and blockers. *Partial:* codes are cataloged and a code-range proposal exists in [Diagnostics](Sublang_Diagnostics.md); the output is still text.
- [ ] Report the call/alias/effect preventing a placement and the selected safe alternative. *Partial:* blocker text names the callee only in the Root/Shard placement message ([Passes and effects](Sublang_Passes_And_Effects.md), sections 8 and 11); the safe alternative is not reported.
- [ ] Optional before/after snapshots and bounded proof graphs. *Not implemented:* snapshots are internal; there is no user-facing before/after output or proof graph.
- [ ] Preserve usable source locations/debug information through lowering. *Partial:* verifier findings keep their line and column (`sublang-tiny-check.sh`); Low operations keep the High operation id, not source spans; no debug information is emitted.
- [ ] Add an IR inspection/dump command and eventually consider a textual input parser. *Partial:* `sublang dump`, `dump-low` and `text-dump` exist. `text-build` parses the canonical text form in [Text IR](Sublang_Text_IR.md), checked by `scripts/sublang-text-sandbox.sh`. There is no general textual language.
- [ ] Add documented editor/tooling integration after interfaces stabilize. *Not implemented.*

Current memory explanations are text; they are not the final protocol.

## 8. Measurement and focused validation

- [ ] Record a representative performance/RSS baseline for allocation, numeric, string and graph workloads. *Partial:* `scripts/sublang-measure.sh` runs the bundled inputs, which are correctness-sized; no baseline is claimed.
- [ ] Compare equal algorithms, inputs, outputs, compiler settings and hardware. *Not implemented:* no comparison exists.
- [x] Separate compilation cost from program runtime (`scripts/sublang-measure.sh` reports compile, LLVM optimization, link and run times separately; see [Measurement](Sublang_Measurement.md)).
- [ ] Measure both Flow-off and Flow-on and document all non-comparable cases. *Not implemented:* no recorded Flow-off/Flow-on comparison exists.
- [ ] Establish original-runtime compatibility only through explicit mapped cases. *Not implemented:* see [Flow parity](Flow_Parity.md).
- [ ] Keep sanitizer checks focused on changed memory boundaries. *Partial:* the backend sandbox runs ASan/LSan on the Flow, text, object and exception fixture groups. That is broad coverage, not a selection by changed boundary.

Existing tests establish correctness/placement evidence, not speed claims. All compiler/program execution stays sandboxed at at most 8 GB, preferably the existing 6 GB/no-swap configuration. Batch meaningful checks; do not rebuild everything after editorial changes.

UNVERIFIED: the pass results of the sandbox scripts named in this document were reported by the author on 2026-10-11. They were not re-run while this document was edited.

## 9. Optional ideas requiring design and prioritization

- **Textual IR authoring:** a canonical text parser and printer now exists (section 7). A friendlier authoring syntax is still an idea.
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

Status is given per step. No step is complete.

1. Freeze/document the usable release subset and reproducible packaging. *Partly done:* the [Release contract](Sublang_Release_Contract.md) and the Wire extensions are documented. The packaged `dist/` binary predates the current build (Release contract, section 7.4), and versions are not pinned.
2. Establish versioned passes, analysis invalidation and structured decisions. *Partly done:* independent forks, context/store-isolated bounded analysis entries, derived effects and pre-commit native lifetime verification exist. Broader preservation, byte/history budgets and structured decisions remain open.
3. Stabilize transport/capabilities and demonstrate an independent frontend. *Partly done:* the Tiny frontend is checked end to end, the text round trip exists and capabilities list extension tokens and passes. Long-term transport stability remains open.
4. Broaden Flow/Optimind with measured parity cases and required semantics. *Not done:* Flow families exist, but no measured parity case exists.
5. Implement the Dynamic AOT slice and expand OO/EH through explicit contracts. *Partly done:* the closed-world OO slice (`ext.oo.v1`) and the `Int`-coded EH slice (`ext.eh.v1`) exist. The Dynamic AOT slice is in progress (see [Dynamic profile](Sublang_Dynamic_Profile.md)).

Parallelism between these workstreams is possible when interfaces are agreed. Completion is evaluated against executable contracts and evidence, not feature-name counts.
