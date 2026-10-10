# Sublang IR contracts — architecture v0.4

This is the required architecture, **not a claim that every contract below is implemented**. The executable development boundary is documented in the [IR guide](Sublang_IR_Guide.md), [Wire contract](Sublang_Wire.md) and [HyperAlloc IR](HyperAlloc_IR.md). Architecture v0.4, IR schema 1 and Wire transport v2 are independent versions.

Dynamically typed languages are an active integration requirement. They use the same Core, effect, alias, memory and verification contracts, supplemented by explicit Dynamic operations. LLVM remains the final backend; AOT does not require a JIT.

## 1. First-class effects

Functions, calls and effectful operations reference typed, versioned EffectSummary records. A borrow_read operand mode specifies access to a value; it does not replace a complete effect contract.

| Area | Required meaning |
| --- | --- |
| allocation | Allocation/deallocation effects |
| escape | Argument/result/capture escapes and globally reachable destinations |
| failure | Observable failures and concrete FailureActions |
| exceptions | MayThrow, supported exception sets/unknown and unwind behavior |
| memory | Read/write location/region sets, including globals/runtime/unknown |
| synchronization | Atomics, locks, fences, tasks/threads and memory orders |
| observable | I/O, volatile access, finalizer/runtime effects or unknown |
| control | Divergence, normal return and proved nonreturning behavior |

Every area can be unknown. Missing information never means no effect. Unknown reads/writes may alias compatible reachable memory. Allocation is not escape; synchronization is not an ordinary field write. A signature does not establish termination or call reorderability.

### Provenance and trust

- **Declared:** frontend/provider contract with origin and trust status. An unchecked hint is not a proof. An explicitly trusted external ABI contract transfers semantic responsibility to its provider.
- **AssumedConservative:** a sound upper bound, usually unknown/top. Optimistic assumptions need supported guards/fallbacks, outside the initial AOT boundary.
- **Proven:** analysis result with analysis/pass identity, entity, revision, prerequisites and dependencies.

Provenance is per fact: proved reads can coexist with unknown escape. Contradictions require diagnosis rather than selecting the more profitable fact. The effective summary safely bounds all possible targets/effects.

Interprocedural analysis joins all dispatch targets, computes recursive SCC fixpoints and keeps conservative residual effects for open targets. noescape does not imply noalias, readonly, nounwind, nosync or memory(none). LLVM attributes require sufficient effective guarantees.

## 2. Shared alias abstraction

LocationId denotes logical storage: globals, allocation sites/objects, field paths, container storage, argument regions, runtime or unknown. It is independent of later physical offsets. Lowering adds pointer provenance.

Alias queries return NoAlias, MayAlias or MustAlias with origin/revision/prerequisites. Missing facts mean MayAlias. Distinct SSA IDs and borrow_read do not establish disjointness. Field sensitivity needs matching layout/object contracts; unsafe pointers, FFI and reflection may weaken facts.

Reads/writes, escapes, borrow origins, invalidating container operations and frees share location references. Views need owner/range/invalidation dependencies, not just a scope name. Transformations preserve those dependencies or invalidate/recompute their analyses. MemorySSA/tokens are possible implementation choices, not an existing API promise.

## 3. Scopes, lifetime and ownership

scope.begin/end describes lexical boundaries or cleanup candidates. It does not by itself prove nonescape, initialization or object death.

Separate analyses track initialization, ownership state, transfers, borrows/invalidation, actual reference liveness, escapes and cleanup paths. Object, borrow, stack and region lifetimes are distinct. SSA liveness alone does not prove graph unreachability.

Only validated facts authorize stack placement, drop, reuse or region release. Reallocation can invalidate a view while its lexical scope remains active. Conversely, a correctly transferred owned object can outlive its origin scope.

## 4. Failures, exceptions and complete control flow

FailureAction describes behavior, payload, runtime binding, ABI and control flow. Abort and throw are distinct; requested throw must never silently lower to abort.

- **Abort/trap:** explicit nonreturning path. The profile determines whether observable cleanup is required before termination.
- **Throw:** owned exception payload and explicit unwind edge. Invoke has normal/exceptional successors; its normal result exists only on the normal edge.
- **Throwing checked arithmetic:** explicit failure edge or checked-invoke contract, not hidden unwinding behind ordinary arithmetic.
- **Catch:** typed filters/binding/rethrow, with a token preserving exception provenance/runtime/ownership.
- **Cleanup/finally:** exactly the required actions on every relevant exit, in language-defined order, including secondary exceptions/suppression.
- **Resume:** continue unwinding rather than return; values survive until their required cleanup.

Unwind ABI, personality and LLVM EH model belong to target/runtime contracts. Low IR chooses landingpad/resume or funclets. Exception profiles remain unsupported until actually implemented; the bounded abort-only path remains valid.

## 5. Pass contracts and validation

Each pass declares required extensions/versions, input/output stages, preconditions, analyses, semantic changes and preserved/invalidated results.

Verification dimensions:

1. **Structural:** IDs/references, SSA/dominance, terminators, normal/exceptional CFG and edge arguments.
2. **Semantic:** profile/operation compatibility, arithmetic/FP, effects, failure/EH and extension/ABI contracts.
3. **Memory/lifetime:** initialization, ownership, borrows/aliases, cleanup and provider/layout invariants.

Statuses are valid, invalid, not_checked or not_applicable with feature coverage. Skipped validation never implicitly means valid. codegenReady requires all necessary checks for the accepted features/target/provider.

Transforming passes produce new snapshots or controlled versioned mutations. Analyses bind to that exact state. After transformation the manager validates structure and relevant semantic/memory invariants, retaining prior results only through a sound preservation/incremental contract. Safety-critical lowering/codegen requires full validation for the selected subset.

Validation does not prove arbitrary program equivalence or detect every incorrect fold. Pass correctness needs implementation evidence and small focused regressions; no full test suite is required per pass invocation.

## 6. Explain and debugging

Diagnostics/decisions should be structured records containing codes, severity, entity/source span, pass/analysis, revision, requested/effective strategy, provider and proof/blocker links.

For example FLOW-LOCAL-ESCAPE-UNKNOWN should identify the blocked object and the call whose effective escape is conservatively unknown. Alias blockers name both locations and their origin. Explain reports the safe alternative; it does not imply that adding an unchecked noescape hint makes the optimization safe.

Distinguish skipped optimization from unsupported required semantics. Text/protocol views should share records. Compact normal reporting and optional bounded proof graphs/snapshots avoid turning Explain into a memory problem. An explanation is not the proof itself.

## 7. Binary product, Wire and public API

**Implemented:** the standalone executable reads bounded Wire v2, including v1 core compatibility, and emits LLVM plus a memory plan. The sandbox launcher verifies/optimizes/links without an Emerald toolchain mount after bootstrap. See [Wire](Sublang_Wire.md).

**Planned broader protocol:**

1. Hello/Capabilities: protocol/schema versions, High/Low stages, versioned extensions, passes, targets and providers.
2. Submit: request ID, immutable snapshot, target/provider, semantic profiles and options.
3. Result: accepted/effective contract, snapshot/revision IDs, verdicts, diagnostics, decisions and requested artifacts.

Reject unknown required features/incompatible versions before optimization. Skip optional nonsemantic metadata only under defined negotiation rules. Never ignore required operations or silently downgrade semantics/memory modes.

An executable process, serialized IR and native library ABI are separate interfaces. Do not expose internal Emerald layouts. A later C ABI needs separate versions, opaque handles and explicit result/error ownership.

Wire requirements include separate transport/schema versions, magic/framing, scoped stable IDs, explicit transformation remapping, raw numeric/FP constants, byte lengths, source metadata, bounded counts and deterministic export. No process pointers or native struct serialization.

The current netstring encoding is experimental, not a permanent compatibility commitment or a complete RPC service. Human-readable .sublang files remain dumps; actual serialized input uses .sublang-wire.

## 8. Dynamic AOT integration

A statically typed IR can model DynamicValue with tags and representation contracts whose payload is determined at runtime. Initial integration is AOT/LLVM; JIT/deoptimization is separate.

The Dynamic extension needs tags/tests, checked box/unbox, dynamic calls, properties/indices, captures/closures and runtime fallbacks. Promotion, overflow, equality, truthiness, strings/properties and failure semantics come from a versioned language profile. There is no universal Python/JavaScript contract.

Immediate/heap representation and ownership must be explicit. The initial dynamic runtime uses nonmoving storage and defined releases. Dynamic values are not automatically pointer-free/NoAlias. Property access may execute user code; absent proof, effects remain unknown. Shape specialization needs guards/invalidation and a correct slow path.

### First actual slice

Specify a small language subset supporting i64/f64, a genuinely heap-backed string value, type tests, dynamic addition with defined promotion/failure/fallback, a property/index operation and a closure call.

Preserve a heap value across an allocating call and release it correctly. Tagged-integer-only demonstrations do not establish heap/lifetime safety. Expose at least one effect/alias blocker in Explain. No complete Python/JS compatibility is claimed.

Foreign GC integration and the earlier hyperalloc-integration mode are [archived](../archive/gc-integration/readme.md). Dynamic typing stays active. Sharing, weak refs, finalizers and threads require actual runtime coverage before admission.

## 9. Implementation stages

- **A.1:** effect provenance, locations/aliases, conservative defaults, distinct verification dimensions and diagnostic references.
- **A.2:** versioned snapshots/pass manager, fixed transport specification, capabilities and bounded roundtrips.
- **B:** bounded static LLVM path with a correct Flow-off baseline.
- **B.1:** real Dynamic AOT integration as described above.
- **EH/providers:** exception CFG/cleanup, LLVM EH and runtime coverage before admitting exception-dependent languages.

The [roadmap](Roadmap.md) tracks the current remaining work. Compiler/program execution stays sandboxed at at most 8 GB, preferably the existing 6 GB/no-swap setup. Keep checks meaningful and bundled.

## Existing safety boundaries

Freeze seals types/functions/blocks/operations/summaries. Collection inputs are copied; getters return defensive copies; hot paths use Count/At access. Abort actions require noreturn void().

SublangProofReference is immutable metadata with analysis identity, module revision and location dependencies. Location IDs cannot be transferred between modules. Fact reference validation does not prove the claimed effect/alias property. Imported NoAlias/MustAlias facts do not authorize optimization without an actual analysis checker; identical valid locations intrinsically MustAlias. General entity dependencies/revision invalidation remain open.

## Executable native extension

All eight Flow families have native paths including cycles, Inline lists, Static strings and nested dependent regions. The compilation-local memory plan controls placement. Native lifetime checking proves the documented closed subset through CFG fixpoints and body-checked borrows; generic universal effect/lifetime validation remains incomplete.

Owned return encodes return with an owned operand. Owned calls encode resultOwnership and destination scope. The native gate checks liveness/initialization, rejects moving borrowed references, invalidates consumed arguments and diagnoses aliases. Returning an owner transfers it and cleans up remaining owners. Owned parameters are released on normal return unless transferred onward.

Exclusive Ref fields consume children on init/write; replacement drops the prior subtree. Clear stores initialized-empty, has checks occupancy, take moves ownership and leaves the parent field logically uninitialized. Clear/refill is required before complete-parent calls/returns. Empty take aborts; ordinary field.read does not create reference aliases. See [HyperAlloc IR](HyperAlloc_IR.md) and [Native Slice](Sublang_Native_Slice.md).

C remains a separate Clang/LLVM entry retaining C ABI/memory semantics; no High-IR ownership import is implemented. See [C support](Sublang_C_Support.md).
