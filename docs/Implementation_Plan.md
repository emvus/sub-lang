# Remaining Sublang implementation: handoff brief

**Additional user requirement:** bundle the LLVM toolchain and provide an install-relative native build driver; each ordinary release targets the newest stable LLVM at toolchain freeze. Read [Toolchain distribution](Sublang_Toolchain_Distribution.md) alongside M8 and packaging. This is newly planned work, not an existing capability.

Prepared October 11, 2026. Baseline inspected: **0eba7ba**, following f4c0bbd and f9b9236. This is an implementation brief, not a claim that the missing capabilities already work.

Read [Roadmap](Roadmap.md), [IR contracts](Sublang_IR_Contracts.md), [HyperAlloc IR](HyperAlloc_IR.md), [Wire specification](Sublang_Wire_Spec.md), [release contract](Sublang_Release_Contract.md) and [Dynamic profile](Sublang_Dynamic_Profile.md). Current source wins over historical implementation-status notes.

## 1. Scope, decisions and working rules

The goal is a usable standalone Sublang with Optimind and full supported HyperAlloc behavior. Implement the remaining areas through real executable contracts. Do not replace implementation with another illustrative specification.

The choices below are recommended engineering defaults for this assignment, not universal language semantics. A source language requiring different behavior needs an explicit supported profile.

- Core, analyses and generated-runtime implementation remain Emerald .ems. No Python-generated core source. Existing Tiny is an external Python frontend demonstration, not a core implementation precedent.
- Do not modify Emerald, its installed compilers or its runtime. Reuse its established algorithms only through neutral Sublang contracts.
- Preserve the current High-IR pipeline, old accepted inputs and Flow-off correctness.
- Disabling optional optimization never disables required ownership, failure, cleanup or bounds checks.
- Foreign tracing/moving-GC integration remains archived.
- Follow Pureline 1.3, English source/comments/docs, explicit guards, no namespace cycles and at most eight production files per namespace directory.
- Compiler and generated-program execution only inside the existing networkless readonly sandbox: RAM=6000000000 and memory-swap=6000000000, no additional swap, timeouts. User ceiling: 8 GB total; do not run capped compiler jobs concurrently.
- Implement coherent groups, then run focused bundled checks. No full rebuild after every file or editorial change. New unsafe memory boundaries need meaningful sanitizer evidence.
- Keep local chatgpt.md/claude.md unpublished, without public ignore entries or AI attribution. No commit/push/history rewrite is requested; the latest push instruction was withdrawn.
- Do not automatically contact another chat or create background automations.

Already present: all eight native Flow families, lifetime checking, Wire v2/v1 compatibility, Bond trial deletion/SCC cache, capabilities/dump, Optimind counts, packaging/smoke/measurement tooling, diagnostics catalog, record-level Wire spec and Tiny. Preserve these; do not recreate them.

## 2. Dependency order and source anchors

| Milestone | Delivery | Dependencies |
| --- | --- | --- |
| M1 | Versioned immutable snapshots and pass invalidation | Existing freeze/verifier |
| M2 | Derived interprocedural effects/escape and shared locations | M1 |
| M3 | Canonical typed Low IR and plan-consuming LLVM lowering | M1/M2, explicit host target |
| M4 | Owned byte buffers, dynamic strings and collection mutation | M3 |
| M5 | Managed Dynamic AOT, properties and closures | M2–M4 |
| M6 | Exceptions/cleanup and native EH adapter | M2/M3 |
| M7 | OO interfaces/dispatch/inheritance and identity | M2/M3 |
| M8 | Objects/libraries, multi-module, targets and LTO/PGO | M3, defined runtime ABI |
| M9 | Weak handles, finalization, then threads | M2/M3, separate acceptance gates |
| M10 | Text IR parser and bounded C ownership import | Stable contracts; C needs M2/M3/M8 |

This is a dependency graph, not a giant rewrite. Keep the old route until a replacement preserves its supported behavior.

Relevant sources: backend/SublangCompiler.ems and SublangBackendGate.ems; ir/SublangModule.ems and tables; body/*; semantics/* and proof/*; optimind/*; hyperalloc/*; backend/llvm, llvmdata, llvmflow and llvmbond; wire/*; cli/SublangCommand.ems. Paths are relative to src/sublang. The build boundary is scripts/sublang-build.sh and sublang-build-worker.sh.

## 3. M1 — snapshots and pass manager

Use frozen snapshots. Transformations construct a new snapshot; never unfreeze an old shared module. A deep rebuild is acceptable initially; structural sharing requires actual immutability.

Conceptual contracts, not existing API names:

```text
SnapshotKey = ModuleInstanceId + Revision
EntityKey   = SnapshotKey + EntityKind + FunctionId? + LocalId
AnalysisKey = SnapshotKey + AnalysisId/Version + OptionsFingerprint
PassResult  = NewFrozenSnapshot + EntityMap + PreservedAnalyses + Diagnostics
```

A module name is not identity. Two equal-named modules must not share proofs. Persistent cross-process caches additionally need content/compiler/schema identity. Options include target, provider, runtime ABI, language profile and semantic flags.

Implement:
1. Controlled builder/rebuilder with explicit origin mapping and type/field/function/SSA remapping. No mutable backing-list aliases.
2. Pass descriptors for versions/features, stages, prerequisites, analyses and preservation/invalidation.
3. Actual analysis caches. Transformations invalidate by default; preservation must name an implemented narrow invariant.
4. Imported proven labels are metadata, not usable proofs until matched to current internally derived evidence.
5. Separate structural/semantic/memory verdicts, with applicable checks before unsafe lowering.
6. Route one real safe scalar transformation through the manager. Preserve potentially failing operand computations unless removal is independently proved safe.

Acceptance bundle: no-op retains snapshot; real change creates a new revision; old dump remains unchanged; stale proof/plan reuse recomputes or rejects; equal-named modules stay isolated; discarded overflow still aborts.

## 4. M2 — effects, aliases and escape summaries

Keep declared, conservative and derived/proven facts separate. Effective summaries are sound upper bounds. Distinguish empty locations, finite sets and unknown/top.

Allocation/deallocation, escape, failure/throw, memory reads/writes, synchronization, observable effects and divergence are independent. Allocation may fail. borrow_read does not mean no global effects.

Implement per-op transfer contracts and logical locations for arguments, allocations, fields, containers, globals and runtime. Build the actual call graph and solve recursive SCCs with a bounded monotone fixpoint. Budget exhaustion must widen conservatively or diagnose, never return optimistic facts.

Map callee locations to caller arguments/results. Track returned ownership, captures/publication and possible retention. Unknown/unbound targets remain conservative and unsupported where no executable binding exists.

Effect convergence is not a termination proof. Recursion/loops stay may-diverge without another analysis. Check declarations against bodies; diagnose contradictions. Derive LLVM attributes only from sufficient effective guarantees.

Acceptance: pure, mutating, recursive and allocating helpers plus an unknown target; convergence stays bounded, false purity cannot erase work, Explain names the blocking call/location.

## 5. M3 — canonical Low IR

Low IR is typed compiler data, not LLVM text in a wrapper. Reuse common entities where useful, with stage-specific type/op rules. High IR does not gain arbitrary pointer operations just because lowering needs them.

Inputs: frozen High snapshot + current validated MemoryPlan + explicit target/runtime contract. Output: new Low snapshot and origin/remapping. LLVM emission consumes Low IR instead of independently redeciding High placements.

Minimum families:
- Concrete layouts: sizes, alignments, offsets, strides, representation/ownership.
- Typed storage/address calculation and checked load/store contracts.
- Stack/heap/region/pool allocation, checked size arithmetic and failure behavior.
- Attach/detach/adopt/drop, region dependency/join/release, buffers and Bond runtime calls.
- Calls with ABI/effects/bindings; normal and later exceptional edges.
- CFG and edge-defined results.

Managed owners and borrowed addresses remain distinct. Address operations require provenance, extent/alignment and valid lifetimes.

Start with the current host target descriptor. Route arithmetic, Root transfer, Inline list, nested Shard and Bond cycle through Low. Reject a plan for another snapshot/target; preserve existing output and sanitizer cleanup.

Add a deterministic Low dump. Serialize only after the contract works. Do not alter Wire v2 record layouts under its old feature token; retain v1/v2 input compatibility and explicitly version new representation/features.

## 6. M4 — strings and collections

Keep current static String ABI unchanged. Introduce an explicit managed byte-buffer/heap-string owner and borrowed views. Static literals can feed construction without allocating themselves.

Use bytes, not an i64 per byte. Check size/offset/terminator arithmetic; embedded zero is valid. Length/index remain byte-based unless an operation explicitly decodes Unicode.

Independent slices must retain an owner or copy; borrowed slices depend on the owner's lifetime. Sharing needs an explicit supported mechanism.

Implement creation, length, bounds-checked bytes, equality and concat; then a builder for repeated appends. Realloc failure must preserve the old buffer and never publish null as success.

Add list.set/replace first for primitive/Record values. Define ownership-bearing replacement separately: consume new, drop old exactly once, invalidate dependent views. Preserve i32 list limits initially; larger-length layouts require explicit variants.

Additional maps/sets need actual hash/equality/effect/iteration contracts, not recognition by type name.

Acceptance: loop concat, empty/UTF-8/embedded-zero strings, slice lifetime, replacement/growth, checked size failure and stale views. Sanitizers must demonstrate release and no accumulation of dead buffers after repeated temporary work.

## 7. M5 — managed Dynamic AOT

Adopt dyn-v1's source rules as the initial profile: checked signed i64, explicit mixed Int/Float promotion, no Bool-as-Int coercion, byte strings, IEEE Float division, fixed shapes, closed closure targets and abort-only dynamic errors initially. No Python/JS compatibility claim.

### Correct the draft representation before implementation

Integer offsets into bytes/slots/header pools are valid only with an explicit live runtime owner. They are not independently owned values. Do not hide heap ownership in primitive Records so it escapes Flow or accumulates until process exit.

For the managed path use a dedicated Dynamic type/operation contract with immediate or managed heap payload, explicit retention/transfer/drop and type-directed ownership visible to Flow. Low IR chooses tag/payload layout; NaN boxing is unnecessary.

A pool-offset experiment may remain labeled frontend-local with checked region dependency. It is not complete managed Dynamic integration. Update the draft and its acceptance rules accordingly.

### Numbers

Add explicit int-to-f64 conversion with rounding semantics. Mixed equality must not simply round every Int to Float: above 2^53 that is wrong.

Provide exact checked Float-to-Int conversion with a success indicator and value, or equivalent correct guarded lowering. Reject NaN/infinity/fractional/out-of-i64-range values before fptosi to avoid poison. Preserve signed zero and NaN truthiness/equality rules.

Fix the draft's malformed promotion table and contradictory source-capability descriptions before turning them into code.

### Heap values, objects and closures

Dynamic properties/list elements own or share their payloads explicitly. Replacement releases old values; mutation invalidates views. Fixed shapes preserve identity and define missing-property failure.

Closures are code/signature identity plus managed environments. Captures distinguish value/owned/shared/borrow. Closed-target branch dispatch is a valid first implementation; arbitrary indirect calls need signature/effect verification.

Owned escaping environments are legal when transferred. Borrowed expired captures reject. Rejecting every escaping closure is not the final feature.

Shared Dynamic cycles need Bond-compatible graphs and typed tracing of payload edges. A Root-only first slice remains explicitly restricted.

Acceptance: revised D1–D6 with a real heap value surviving an allocating call, returning to a longer-lived caller, being used and released. Include exact equality around 2^53, type/bounds failures, one legal owned escaping closure, one rejected dangling capture and an explained unknown effect. Run both Flow modes and focused sanitizer cleanup.

## 8. M6 — Exceptions and EH

Initial semantics: synchronous typed exceptions, first-match catch/filter, rethrow, finally/cleanup and owned exception payloads. Initial cleanup order is reverse acquisition; other language orders require explicit profiles. Compiler-generated drops are nonthrowing.

Implement invoke with normal/exceptional edges and results only on their defining edges. Add throw/catch/resume and exception ownership/provenance. Generate cleanup for every required fallthrough, return, break/continue, throw and rethrow. Extend lifetime/initialization to exceptional CFG; do not redrop transferred owners.

Throwing arithmetic requires an explicit failure-edge/operation contract. Abort-only profiles stay abort-only.

Native EH needs a real host-target personality/unwind runtime and exception ABI. LLVM does not invent a language personality. Do not emit unresolved pretend runtime symbols. If the offline sandbox lacks required libraries, report the exact missing capability and keep it rejected.

An explicit status-result error ABI can be a separate implementation, but is not native unwinding and cannot silently replace required EH. Initially forbid throwing cleanup or define abort for contract violation; do not claim every language's secondary-exception policy.

Acceptance: an allocating callee throws through an owned caller frame into catch; exactly-once cleanup/finally on both paths; rethrow; defined uncaught behavior; normal invoke result rejected on unwind; sanitizer evidence for owned payload/owner transfers.

## 9. M7 — OO extension

Keep free functions and Records first-class. Add interfaces, implementation tables, single inheritance first, fields, override signatures and dispatch contracts.

Source identity is not necessarily physical address. Identity-observing operations can block Folded/Inline or require stable identity tokens.

Begin with closed-world dispatch sets and validated receiver/signature. Devirtualize only from current target proofs; join all possible effects. Unknown targets need supported conservative bindings.

Base layout/destruction must follow explicit target/concrete-type metadata. Destruction through base references must free derived owned fields.

Reflection, multiple inheritance and arbitrary dynamic loading remain separate capabilities, not implicit interface support.

Acceptance: two implementations dispatch, override mismatch rejects, monomorphic call explains direct lowering, open targets remain conservative and base destruction releases derived resources.

## 10. M8 — modules, targets, LTO and PGO

### Define ABI before composition

Add LLVM/bitcode/object/executable output modes. Specify imports/exports, symbol collisions, profile/type compatibility, ownership signatures and source mapping. Rebase local IDs when merging; equal numeric IDs across files do not establish type identity.

Use one coherent program runtime for interacting modules. Independent per-module Bond graphs/caches cannot simply exchange owners. Define symbol visibility, initialization/shutdown and final flush after live owners are gone.

Cross-module optimization consumes verified bodies or versioned summaries bound to ABI/content identity. Reject incompatible providers/layouts and unresolved imports.

### Targets

Describe triple/data layout, pointer/alignment, convention, runtime/libc and EH capabilities explicitly. Make host output reproducible first. Additional targets need actual code generation/link/runtime coverage; distinguish unexecuted cross output. Changing a triple string is insufficient.

### LTO

Start with full LTO. Participating code/runtime must reach the linker in compatible bitcode with one consistent pipeline. Record effective configuration. Repeating opt is not LTO. ThinLTO is optional later.

### PGO

Separate instrument/train/use. Bind profiles to compiler/runtime/target/options and source/IR identity; reject incompatible/stale profiles or report explicit fallback. Training stays capped/sandboxed, with evaluation inputs separate from training. No benchmark-name shortcuts.

Acceptance: two modules transfer/drop an owner under one runtime; incompatible imports fail; LTO preserves results; compatible PGO applies and stale profiles reject. Missing offline tools produce explicit limitations, not automatic downloads or claimed success.

## 11. M9 — weak handles, finalizers and threads

Separate capabilities with separate verification. Atomic counters alone do not make trial deletion thread-safe.

### Weak handles

Begin with Bond weak handles. Retain a control block, not strong payload reachability. Mark dead before freeing payload; keep tombstones until weak handles vanish. Prevent ABA through control-block lifetime or checked generations.

Upgrade must check-and-retain atomically with respect to reclamation and return a strong owner or explicit absence. Add an Optional/result contract rather than silently changing non-null Ref ABI. Weak handles must not keep cycles alive.

### Finalization

First implement explicitly opted-in nonthrowing exactly-once drop hooks and documented exclusive ordering. Treat hooks as observable effects in optimization.

For dead cycles, preserve the permitted payload graph through hooks, then detach/drop/free. Existing edge deletion before hooks is invalid if hooks may inspect edges. Specify no resurrection, permitted access and unspecified cycle inter-object order for the initial profile; enforce those restrictions.

General resurrection and foreign language finalizer ordering remain unsupported unless implemented.

### Threads

Independent thread-confined runtime instances with explicit checked transfer are a first step, not shared concurrent Bond support.

Shared mode must synchronize roots, edges, weak upgrade, collection and caches. A coarse graph mutex is acceptable initially but does not protect a borrowed payload after unlocking. Require strong pin/read guards or proved exclusive access; release guards on every normal/exceptional exit.

Define publication, lock ordering, cache ownership, shutdown and reclamation. User hooks cannot run reentrantly under a global runtime lock; provide a safe queued lifecycle. Counts alone do not make graph scans concurrent.

Acceptance: weak upgrade before/after death, no weak-kept cycle, exactly-once exclusive/cycle hooks, and controlled retain/release/upgrade/guard interleavings. Use thread sanitizer only if supported; record absent evidence instead of calling the shared runtime verified.

## 12. M10 — textual IR and C ownership import

### Text IR

Define canonical grammar/version/features for actual executable contracts. Parser/printer share typed IR; no arbitrary LLVM/Emerald escape hatches. Preserve IDs/modes, spans, raw float bits, exact bytes, ownership and CFG arguments.

Start with accepted High IR, not automatic acceptance of illustrative v0.4 syntax. Bounded decoding and precise line/column/byte diagnostics apply. Canonical printing is deterministic; text/model/Wire roundtrips preserve meaning. Unknown required operations reject.

### C importer

Keep current C → Clang/LLVM functional. Analyze a documented LLVM subset with explicit allocator-family/ABI contracts. Pointer types or function names alone do not prove ownership.

Track alloc/free/realloc, size/null/failure/alignment, calloc initialization, observable errno and matching families. Preserve aliases, interior pointers, identity/layout, captures, globals and unknown calls.

Unsupported pointer-int casts, inline assembly, volatile/atomics and type punning must block transformations unless their full semantics are handled. Do not turn C signed-overflow UB into another language's checked semantics. LLVM poison/provenance rules still apply.

Start with a proven local allocation, a nonescaping helper and an unknown-call blocker. Unsupported imports may stay unchanged in an explicitly reported mixed pipeline; explicitly required unsatisfied Flow must diagnose.

Acceptance: eligible transformations preserve behavior; escaping/interior/external cases remain unchanged or reject under the declared mode; realloc/null failure behavior is preserved; modules do not mismatch runtime ownership.

## 13. Reporting and completion

Each new operation needs model/builder, vocabulary, typing/semantics, effects, lifetime, transport/dump, lowering/runtime and focused positive/negative evidence. A parsed name or capability string is not implementation.

For every milestone report exact contract, changed files, an end-to-end artifact, checks actually run and remaining limitations. Update release/capability/Wire/diagnostic/roadmap claims only with actual support. Generic effect/memory readiness cannot be inferred from one native subset.

If unattended execution is unavailable, complete safe design/implementation work and label it implemented but unverified, with exact next command/dependency. Do not silently skip requested areas or fabricate verification. No speed/RAM claim without equal-input measurement; use existing compile/link/run-separated tooling.

## 14. Immediate assignment and language-frontend handoff

Start with **M1/M2**, then route a real fixture through **M3**. Do not first rewrite every emitter or add all future opcode names.

Routine engineering choices within this contract do not need repeated confirmation. Incompatible source semantics or unavailable external prerequisites need specific reporting. No commit/push is requested.

When the Sublang stage is finished, provide a handoff for the separate language-frontend developer:
- Exact compiler commit/version, supported schema/Wire versions and capabilities.
- Actual working build/export commands and sandbox prerequisites.
- The implemented source-semantic profiles, object/collection/closure/error contracts.
- Accepted IR examples for functions, CFG, values, ownership, Dynamic and EH where implemented.
- Runtime/link ABI, import/export/target rules and required libraries.
- Diagnostics and known rejected features; distinguish implemented, verified and unavailable.
- A minimal independently generated frontend module that compiles/runs through the binary.

Only then write the second language-development prompt against those real interfaces. The language frontend must not be designed around unimplemented roadmap features.
