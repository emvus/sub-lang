# Archived Sublang IR contracts — v0.4 collector proposal

**Archived October 10, 2026.** This English rendering records the earlier GC-integration design. It is not the active roadmap or implemented public schema/ABI. Current contracts are [outside this archive](../../../docs/Sublang_IR_Contracts.md).

## 1. Effects and provenance

Functions/calls/effectful operations reference versioned EffectSummary records. Borrow mode alone does not describe all effects.

| Area | Historical requirement |
| --- | --- |
| allocation | Allocation and potential GC safepoints |
| escape | Argument/result/capture/global escape |
| failure | Concrete observable FailureActions |
| exceptions | Throw sets/unknown and unwind contracts |
| memory | Read/write locations including globals/runtime/unknown |
| synchronization | Atomics/locks/fences/tasks/threads and memory orders |
| observable | I/O/volatile/finalizer/runtime effects |
| control | Divergence, normal return and proved noreturn |

Missing information is unknown, never false. Unknown memory effects may alias compatible reachable locations. Allocation, escape and synchronization remain distinct.

Declared contracts carry origin/trust; conservative facts are sound upper bounds; proven facts carry analysis/entity/revision/dependency identity. Contradictions require diagnostics rather than selecting more profitable claims.

Interprocedural summaries join dispatch targets and recursive SCC fixpoints. Open targets keep conservative residual effects. noescape does not imply noalias/readonly/nounwind/nosync. LLVM attributes require sufficient guarantees.

## 2. Shared alias abstraction

Logical locations include globals, objects/allocation sites, field paths, containers, argument regions, runtime and unknown. They are independent of physical offsets. Queries return NoAlias/MayAlias/MustAlias with provenance/revision; missing facts mean MayAlias.

Reads/writes, escapes, borrow origins, container invalidation and GC movement share location references. Relocation invalidates raw address assumptions. Mutable passes preserve or recompute these relationships. Distinct SSA IDs do not prove disjointness.

## 3. Scope, ownership and lifetime

Lexical scope markers do not prove object death, nonescape or initialization. Separate checks establish ownership/transfers, borrows/invalidation, reference liveness, escapes and cleanup.

Memory plans derive stack/drop/reuse/region/provider decisions only after validation. Container growth may invalidate views before lexical scope end. Escaped objects can survive through a valid transfer/provider contract.

## 4. Failures and exception control flow

FailureAction describes behavior, payload, binding, ABI and control flow. Abort cannot silently substitute for throw.

Invoke has explicit normal/exceptional successors and edge-defined results. Checked arithmetic that throws needs explicit failure edges. Catch/filter/rethrow, cleanup/finally and resume carry language-defined ordering and exception ownership.

Runtime personality and LLVM EH model are target/provider contracts. Required exceptions remain unsupported until implemented. Observable cleanup before abort must be explicit.

## 5. Pass validation

Passes declare versions/extensions, stages, prerequisites, analyses and preservation/invalidation. Separate dimensions check structure, semantics and memory/lifetime, including roots/barriers/safepoints and provider/layout validity.

Statuses are valid/invalid/not_checked/not_applicable. Codegen requires applicable checks to pass. Transformations produce versioned snapshots/remappings; stale analyses cannot be reused without a valid preservation contract.

Verification proves invariants, not arbitrary semantic equivalence. Focused correctness evidence remains necessary.

## 6. Explain and debug

Structured decisions identify entity/source, revision/pass/provider, requested/effective strategy and proof/blocker references. An unknown-escape call or alias blocker must be named.

Explain distinguishes skipped optimization from unsupported semantics and reports a safe alternative. Text/protocol views share records. Detailed proof graphs/snapshots are optional and bounded.

## 7. Public binary/protocol boundary

The historical proposal separated executable process, serialized IR and native library ABI. Internal Emerald layouts must not become a public ABI.

Proposed process messages were Hello/Capabilities, Submit and Result: versions/features/stages/targets/providers, immutable module/options and verdicts/diagnostics/decisions/artifacts.

Unknown required features fail before optimization. Wire needs explicit magic/sections/lengths, scoped stable IDs/revisions, raw numeric bits, source data, bounded decoding and deterministic export. Native pointers/struct serialization are prohibited.

These were proposed interfaces, not an implemented stable format at this historical stage.

## 8. Dynamic values and collector providers

DynamicValue is a typed IR carrier with runtime tags/representation. Extensions need type tests, checked box/unbox, dynamic dispatch, properties/indices, closures/captures and runtime fallback. Numeric promotion/truthiness/equality/strings/failures belong to a language profile, not universal Python/JS rules.

Dynamic values may contain heap references. Moving-GC integration requires explicit roots, barriers, safepoints and relocation-safe handles. Raw addresses must be reloaded after safepoints. Native calls/pinning/escape require provider contracts.

The first proposed AOT slice included i64/f64, heap strings, type tests, dynamic addition, property/index access and closure calls. A real heap value had to survive an allocating call; tagged integers alone did not prove integration. A nonmoving provider did not establish moving-GC support.

An existing collector could remain through Integration mode. Managed mode was permitted only when its provider covered required sharing/cycle/finalizer/weak/thread semantics. Dynamic typing neither required a universal collector nor allowed omitting required behavior.

## 9. Historical implementation stages

A.1 covered effect provenance/location/alias records, conservative defaults and separate verification. A.2 required pass snapshots, fixed Wire/capabilities and bounded roundtrips. B required a bounded static LLVM path, followed by a real Dynamic AOT slice and EH/provider expansion.

Checks were to remain small/bundled. Every compiler/selfhost execution required a sandbox at most 8 GB, preferably 6 GB/no swap. This archived contract did not execute compilers or claim new features.

## Archive boundary

Foreign collector integration, moving-GC root relocation and hyperalloc-integration were subsequently removed from active scope. These preserved requirements do not instruct current implementation work.
