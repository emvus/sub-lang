# Executable native slice — 2026-10-11

Sublang now has a small executable path written in Emerald:

```text
frozen builder module OR versioned IR file -> standalone Sublang binary
  -> resource/identifier gate
  -> structural and semantic checks
  -> CFG fixed-point lifetime/initialization and closed borrow proofs
  -> optional Optimind overlay
  -> immutable HyperAlloc memory plan with placement explanations
  -> textual LLVM IR
  -> LLVM verification / optimization
  -> native executable
```

This is an initial backend with a sandbox build entry point, not the complete Sublang platform. The first
target is native 64-bit Linux with libc abort/malloc/free/printf. A target-independent
runtime ABI, serialized Low IR and permanently stable public compiler ABI remain
future boundaries. The experimental IR transport and compiled process interface
are implemented; see [Sublang Wire](Sublang_Wire.md). No foreign GC integration is required or planned.

## Library API

```java
use sublang::backend::SublangCompiler;
use sublang::backend::SublangCompilation;

builder.freeze();
SublangCompilation result = SublangCompiler.compile(builder.module(), true, "auto");
if (!result.codegenReady()) {
    println(result.error());
    return;
}
String llvm = result.llvm();
String memoryDecisions = result.explainMemory();
```

The Bool selects Optimind; Flow accepts `off`, `on`, `auto`. The frozen input is never
modified. Optimind results are ephemeral function-local overlays, not mutating IR
passes or cached analysis results. No new revision is fabricated. In this closed
slice `auto` first selects Folded for scalar-only object uses, then Local for suitable
acyclic-entry allocations, Pool for reusable fixed-layout sites, Shard for proven closed
regions, and stable runtime storage for other ownership transfers or Root trees.

After the gate succeeds, a compilation-local `SublangMemoryPlan` records each
allocation in every block by function/value/operation/scope/type and frozen revision. Its immutable
function plans drive LLVM allocation and release decisions directly. `explainMemory()`
returns the same decisions as text: `Folded` for scalar fields, `Local` for proven entry stack placement,
`Pool` for proven reusable slots, `Shard` for closed chunk regions, `Root` for owned reference fields,
`ScopeOwned` for ownership transfers requiring runtime storage, or `Heap` when Flow is off.
Static literals, Inline list layouts and Bond shared allocations also have explain records.
Plans are internal lowering artifacts, not reusable frontend proof certificates or
a stable serialized plan API. Constructing a plan independently does not validate IR;
only `SublangCompiler.compile` runs the required gates.

`SublangCompilation.codegenReady()` applies only to this backend's verified subset.
The general verifier still reports effects/lifetime as `not_checked` and its generic
readiness remains false. This does not bypass a failed generic check: the backend
rejects invalid input, then establishes the narrower required memory properties itself.
Untrusted frontend effect/proof strings are not used to grant transformations.

## Supported semantics

- i64, Bool and IEEE binary64; raw float bits and ordered/unordered comparisons.
- Checked add/sub/mul/neg through LLVM overflow intrinsics; explicit wrapping modes.
- Division by zero aborts. MIN/-1 follows the selected trap/wrap rule; remainder
  supports trap or zero explicitly, without executing undefined LLVM division.
- f64 arithmetic uses constrained LLVM intrinsics with round-to-nearest-even.
- Direct calls to module bodies, primitive/value-record parameters and returns.
- Reference parameters with derived nonescaping `borrow_read`/`borrow_write` behavior.
  Calls require a live, fully initialized object; mutable alias arguments are rejected.
  Read-only borrows cannot mutate or be forwarded to mutable parameters. All participating
  bodies are verified, including recursive call graphs; frontend noescape flags are ignored.
- Owned reference parameters consume the caller's reference. Owned reference returns transfer
  one fully initialized object; callers explicitly name the destination owner scope.
- Branches, loops and SSA block parameters. Edge copies load every incoming value
  before storing destinations, preserving parallel assignments and swaps.
- Value records with primitive fields, construction, reads and functional updates.
- Scoped classes with primitive and exclusively owned class-reference fields. References
  can be borrowed or moved into verified module functions, returned as owned, adopted
  into fields, replaced, taken or cleared. Reference block-argument aliases, sharing
  and read-only graph-field views use `field.borrow` with ancestor invalidation.

Scopes are not automatically lifetime proofs. `SublangLocalLifetime` now runs a forward
fixed-point analysis over the CFG; its historical class name does not restrict analysis
to Local placement. Incoming scope stacks must agree at joins. Definite reference liveness
is intersected; field initialization is tracked as uninitialized/initialized/mixed.
Reads/writes require initialization on every incoming path; initialization requires the
field to be uninitialized on all paths. New allocations reset their own field state.

Nested scopes, branch initialization, early scope ends, scopes within loops and allocations
in arbitrary blocks are supported. A scope end must close the innermost active scope and
invalidates its references. Primitive/Void returns require lexical owner scopes closed; owned returns clean remaining owners automatically. Calls borrow
only while the caller's scope remains active; borrowed callee parameters cannot be initialized,
released, moved or returned as owned. Owned parameters receive an implicit function owner
and are released on normal return unless transferred onward. Every reachable body is checked before
any LLVM is returned. This is a closed interprocedural proof, not a general effect analysis.
Library callers outside this compiler must honor borrow lifetime, full initialization,
mutable exclusivity and owned-reference runtime-prefix preconditions. The function symbols
are an internal compiler ABI; a public foreign-call ABI is not implemented.

Flow on/auto first eliminates object storage through Folded for proven scalar-field-only
uses. Other suitable acyclic-entry allocations use stack storage. Repeated
fixed-layout primitive-only allocations with no owned escape use Pool: one reusable
entry-frame slot per static allocation site, separate for every function invocation.
This is bounded slot reuse, not a general slab allocator. Other allocations are
linked to their dynamic owner scope by a generated LLVM runtime with a 16-byte prefix.
The prefix holds the next header and a pointer to the link slot referencing this header,
allowing O(1) detach/adopt during ownership moves without moving the payload. Allocations
used by owned calls/returns always use stable runtime storage, even in entry blocks.
The memory planner collects these transfer uses in one linear scan.
`scope.end` releases exactly that scope's owned roots, including conditionally executed
and repeated allocations; nested scopes have separate, type-specific chains. Both prefix-size overflow and
allocation failure abort. Payloads remain nonmoving. Flow off disables stack placement and
uses the same scope cleanup mechanism to preserve memory safety. This runtime is emitted by
Emerald source, with libc malloc/free as backing storage; it is not a copied C implementation.

Root trees now support exclusively owned reference fields and iterative destruction.
Visitors use the existing 16-byte headers as a pending-work list after ownership ends,
so deep trees do not require recursive drop calls or extra cleanup allocations.
Adoption consumes a child; replacement drops the previous subtree. Self-adoption,
use after adoption and repeated takes without reinitialization are rejected.
Closed nested Shard regions are implemented; their dependency joins, mixed backing and
loop-retention cost guard are described in [Flow parity](Flow_Parity.md).
Bond shared/cyclic graphs, owned shared calls/returns, exclusive children of shared parents,
Inline value/class lists and Static strings are also implemented. See [HyperAlloc IR](HyperAlloc_IR.md)
for builder APIs, runtime layouts, cache bounds and conservative alias rules.
Mutable graph borrow views, reference block arguments, destructors, exceptions/unwinding,
concurrency and weak references remain unsupported.
An abort terminates the process, so there is no exception-cleanup claim. Stack objects need
no header; heap field offsets use LLVM layouts after the prefix. Allocator/abort bind to
the stated libc target; other failure bindings are rejected rather than silently replaced.

## Owned transfer API

```java
// Reference-returning functions explicitly transfer one owned reference.
builder.ops().returnOwned(objectValue, span);

// The caller immediately adopts the returned reference into its active innermost scope.
Int result = builder.ops().callDirectOwned(callee, args, modes, scope, span);

// Existing callDirect consumes arguments whose matching parameter mode is "owned".
// Returning a primitive or Void releases any remaining owned parameters automatically.
```

Reference return types currently imply owned return semantics. The generic verifier checks
explicit return/call ownership encoding; the native lifetime analysis proves that the
returned reference is live, owned and fully initialized. Ordinary `returnValue` is not a
reference-transfer operation. A moved reference becomes invalid on that path, including
at CFG joins if any predecessor consumed it. A borrowed reference cannot become owned.
Duplicate call arguments with any owned or mutable mode are rejected before consumption.

An owned-return terminator detaches its result and cleans up the remaining function-owned
and lexical scope chains. Scope slots start empty, so branch-local, already closed and
never opened scopes are safe to visit during this cleanup. No destructor ordering is
defined by this initial class subset. Primitive/Void returns still require lexical scopes
to be closed explicitly, then release the implicit owner of owned parameters. The caller
adopts the returned object before subsequent instructions; there is no detached-object
value exposed as a general IR operation. Exceptions remain unsupported.

Optimind folds safe integer add/sub/mul/neg/div/rem constants and integer/Bool comparisons,
and applies safe identities including commuted add/mul, multiply by zero, divide/remainder
by one and subtracting the identical SSA value. Overflowing or unknown arithmetic retains
runtime checks. Operand-defining
computations remain in place, preserving calls and failures. LLVM's later mem2reg,
instcombine and simplifycfg are separate from these Sublang-level transformations.

## Root field operations

`fieldInitOwned(parent, field, child, span)` initializes an owned reference field;
`fieldWriteOwned(...)` replaces it, dropping its old subtree. Both consume the child.
`fieldClear(parent, field, span)` stores an explicitly initialized empty field and
drops any old subtree. `fieldHas(...)` returns whether that initialized field is nonempty.
`fieldTake(parent, field, destinationScope, span)` removes the child and adopts it into
the active innermost destination scope; taking an empty field aborts. The parent field
becomes logically uninitialized and must be cleared or refilled before passing/returning
the parent as fully initialized. Mutation requires mutable fields and permissions.
Ordinary field reads return primitive values only; they do not create graph aliases.

## Sandbox source build entry point

```bash
bash scripts/sublang-build.sh examples/programs/root-tree.ems -o build/root-tree --flow=auto --run
bash scripts/sublang-build.sh examples/programs/c/points.c -o build/c-points --run
```

The Emerald file is a builder defining `SublangProgram.build()`, not arbitrary Emerald
source translated by a complete Emerald frontend. The C entry accepts ordinary source
directly through Clang; no Sublang IR file is required. Both export the binary, frontend
LLVM `.ll`, verified/optimized `.bc`, and `.plan` beside the output path. `--run` executes
only in the same 6 GB sandbox. `--llvm-opt=0|1|2|3` controls LLVM optimization separately
from `--optimind=on|off`. The C boundary and missing import analyses are documented in
[Native C](Sublang_C_Support.md).

## Resource and feature gate

Initial budgets: 32 functions, 512 types/fields, 64 blocks and 4096 values per function,
4096 operations per block, 32768 operations per module. Operation ids must be unique,
positive and within that budget. Scope IDs are also bounded by 32768 before lowering
key arithmetic. Limits are checked before dominance tables are built.
The lifetime analysis additionally limits distinct receiver/field pairs to 512 per function
and fixed-point rounds to 16384. Unsupported features yield `SUBLANG-B*` errors and no LLVM output. The first error is
currently textual; full backend diagnostic/protocol records remain an API follow-up.

## Bundled verification

```bash
bash scripts/sublang-backend-sandbox.sh
```

The runner builds one Emerald generator and emits baseline (`Optimind=false`, Flow off)
and optimized (`Optimind=true`, Flow on) variants. For each non-aborting case it checks
LLVM assembly, runs the IR, builds native code, and compares both outputs with fixed
independent expected values. All build/run commands execute inside a read-only,
networkless Docker sandbox: hard 6,000,000,000-byte RAM and RAM+swap limit, no swap,
CPU/pid limits and timeouts. Generated binaries/IR remain in container tmpfs.

| Scenario | Expected output |
| --- | --- |
| i64 addition | 4000000000 |
| loop with direct call and parallel block-parameter swap | 5072 |
| original record plus updated copy | 41 |
| 2.0+3.0 and NaN unordered comparison | 1 |
| initialized local object | 43 |
| local object shared by branch/loop, both terminal paths exercised | 89 |
| nested loop scopes, branch initialization, mixed stack/runtime placement | 36 |
| mutable borrow plus forwarded read-only borrow (noescape flag false) | 82 |
| factory owned return, move through transformer, consuming call and cleanup | 82 |
| owned Root graph replacement, take and clear | 43 |
| 10,000-node Root chain with iterative destruction | 10000 |
| Folded Int/Bool/f64 fields and mutation | 42 |
| Shard tree plus heap children, two invocations | 5085 |
| Root fallback for repeated early subtree release | 5085 |
| Pool with verified borrow calls | 100 |
| additional safe numeric folds | 47 |
| MIN remainder -1 with zero mode | 0 |
| overflowing i64 addition | SIGABRT, no result |

Both variants passed on 2026-10-10, including nested loop scopes and borrowed calls.
The gate rejected uninitialized fields, use after lifetime end, mutable input snapshots
and duplicate operation ids. CFG cases reject missing cleanup, branch use-after-end,
double initialization, initialization absent on one incoming path and incorrect nested
scope release order. Borrow cases reject mutation through a read-only parameter,
uninitialized call arguments, read-to-write forwarding and mutable alias arguments. Transfer cases additionally reject use after move, duplicate
owned arguments, uninitialized owned returns, borrowed-to-owned returns and missing
call-result ownership/destination metadata (the latter at the generic boundary).
Flow auto/on LLVM equality, mixed placement explanations and dynamic cleanup sites are
checked. LeakSanitizer reported no leaks for the nested-scope heap baseline and for
both baseline/optimized ownership-transfer chains, including non-head unlinking.

The runner verifies emitted LLVM, executes the unoptimized IR, compiles native variants
and checks independent outputs. These are correctness checks, not speed/RSS measurements.
The runtime, borrow and transfer additions were checked as successive bundled sandbox runs
when implementation changed. The 28-case core harness passed after the additive Root
operation vocabulary and class-reference field rules. Root negatives and LeakSanitizer
passed for both tree variants, including the deep chain. Pool placement and explanation
were checked in the loop case. These are bounded correctness checks, not benchmarks.

## Following milestones

Preserve this baseline while adding versioned pass/snapshot APIs and broader structured
memory decisions, then expand the neutral HyperAlloc runtime and Optimind. Interprocedural object
lifetimes, a canonical Low IR and target/provider configuration need explicit proofs
and contracts. Dynamic AOT remains the next language-capability slice; EH/cleanup and
full Emerald selfhost migration are later coverage work. The current slice is not a
claim of full Emerald compatibility or a stable public release.

Folded/Shard and numeric parity additions passed the bundled runner. Mixed region/heap
cleanup passed ASan with leak detection, and discarded numeric failure results still abort.
No generic verifier schema was changed by these lowering/analysis additions.
