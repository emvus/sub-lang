# HyperAlloc / Optimind parity with the original Emerald optimizer

Target: reproduce the established Emerald optimization capabilities in Sublang,
through neutral IR contracts and Emerald implementation source. The Emerald compiler,
runtime and installed normal/stable binaries are not updated by this work.

The reference is the original Emerald Flow family (Folded, Local, Inline, Shard, Pool,
Root, Bond, Static), its borrow/container checks and compatible general optimizations.
Existing source and the retained October 7 reference snapshot supply implementation
evidence; no new full compatibility run of that snapshot is claimed here.

## Implemented parity boundaries — 2026-10-11

| Original capability | Executable Sublang behavior | Still required for parity |
| --- | --- | --- |
| Folded | Primitive class fields split into scalar slots, including closed-body one-field getter calls; LLVM can promote slots | General method/body inlining and broader aggregate analysis |
| Local | Entry allocation on stack, verified borrow calls | Richer escape summaries and aliases |
| Pool | Reusable per-site frame slots plus exact-layout heap caches, bounded to eight blocks/layout and one MiB/module | Broader escaping/reset policies and measured cache tuning |
| Shard | Closed owned graphs, nested regions, dependency joins toward the longer lifetime and inherited field-take provenance | Cross-function region escape contracts and chunk reuse policies |
| Root | Exclusive reference fields, adoption/replacement/take/clear, owned calls/returns, iterative destruction and read-only graph views with ancestor invalidation | Richer mutable-view provenance and merges |
| Bond | Counted roots/edges, owned calls/returns, local trial deletion, revision-checked SCC external-count cache, shared parents with exclusive Root children | Performance validation, weak refs, arbitrary bidirectional Root/Bond conversion |
| Inline | Value lists and inferred inline immutable-class elements; folded temporaries construct elements directly in the buffer | Richer identity contracts and mutable inline objects |
| Static | Exact immutable UTF-8 bytes in LLVM globals; String value operations/fields/calls | Dynamic strings and general static object graph inference |
| Container views | Checked List element views, invalidation on growth/mutation/move, transitive owner provenance | Mutable views and reference block-argument merges |
| Numeric optimization | Safe add/sub/mul/neg/div/rem folding, integer/Bool comparisons, identities and bounded constant-call evaluation | Broader range propagation, CFG constants, generic effect-driven transformations |
| Build optimization | LLVM optimization levels and verification | Explicit LTO/PGO interfaces, training/profile provenance and compatibility |

This table is a migration checklist, not a statement that all original strategies are
fully ported. No percentage or performance parity follows from strategy names alone.

## Folded proof and lowering

After the native lifetime gate, use classification proves that a primitive-field
allocation is used only as the receiver of field initialization, writes and reads.
There are no reference aliases/block arguments in this executable subset. Reference
fields or any unrecognized call/ownership use prevent this lowering. A closed-body
read-only getter of one primitive field is lowered directly to the field slot.
Primitive mutation is supported;
the object address and identity must be unobserved. No frontend hint grants this proof.

The backend omits the object allocation and Ref value slot, emitting one appropriately
typed scalar slot per field. Loop sites reuse invocation-local slots. Field operations
access those slots directly, and LLVM mem2reg can reconstruct SSA values. Constructor
effects are separate IR operations and remain present. Flow off retains the heap path.

Eligible immutable classes consumed by List push now construct directly in contiguous
element storage. Their source temporary can stay Folded without a per-object header.
Classes with owning/shared fields retain stable separate objects. Field mutability
alone does not prevent value inference under the consuming/read-only container
contract. See [executable contracts](HyperAlloc_IR.md).

## Shard proof, backing and cost guard

Initial eligibility requires no reference
parameters or reference return, no owned call arguments, and no reference call results.
The preexisting lifetime proof establishes legal field transfers and nonescaping borrows.
These restrictions prevent a region node from reaching an external owner. Nested
frames join toward the older active region on adoption, preserving dependent backing.
Field takes inherit the owning root's storage provenance. Loop churn and graph-Pool
reset costs keep the stable fallback when region retention would accumulate dead storage.

Chunks start at 4096 bytes and grow to fit an oversized request. Each request, including
its 16-byte ownership header, is aligned to 16 bytes; size arithmetic is checked.
Frames are per invocation, not global. On scope end, visitors destroy ownership trees
first, then every backing chunk is freed and the frame reset. Region backing is marked
in the low bit of the next-header word; exposed payload pointers remain untagged.
Detach/adopt and iterative pending lists preserve the mark. Heap children from verified
mutable borrow helpers can coexist and are freed individually. This internal representation
targets the current native64 integral-pointer ABI, not an unrestricted public C ABI.

Profitability is separate from lifetime safety. A bounded CFG cycle analysis selects
loop allocation sites (or at least eight static sites). Reference replacement/clear or
mutable borrow calls in a CFG cycle disable Shard conservatively: otherwise dead subtrees
could accumulate until region end. Small acyclic graphs keep Root instead of allocating
a chunk. Explain records the blocking reason. This is a conservative cost guard, not
a measured universal performance model; it can miss optimizable cases.

## General optimization safety

Pool graph parents whose own reference never transfers can reuse frame slots even
when fields own dynamic children. Their 16-byte prefix marks nonheap storage. Reuse
detaches the old scope entry, iteratively destroys previous children and reattaches
to the current scope. Scope exit drops children without freeing frame storage.
Visitors clear child fields and cleanup clears backlinks, allowing reuse both
within one outer scope and after an iteration scope ends. Replacement allocation
invalidates dependent views. Transferred parents retain stable runtime storage;
primitive-only Pool slots remain headerless. These are per-invocation slots, not
a global cache or inline storage for arbitrary retained lists of objects.

Integer folding checks bounds before computing in checked Emerald. Multiplication
handles all sign combinations and MIN/-1. Division/remainder preserve their selected
trap/wrap/zero semantics and never evaluate division by zero during compilation.
Float operations are not reassociated or folded through host arithmetic.

Identities also cover commuted add/mul, multiplication by zero, division by one,
remainder by one and subtraction of the identical SSA value. Operand-defining operations
are retained, so an overflowing multiplication or division by zero still aborts when a
later multiplication discards its result. These are Sublang Optimind transformations;
LLVM's subsequent passes are separate.

## Binary integration target

The product is a standalone Sublang compiler binary accepting language-independent IR
files. Frontends generate IR, Sublang verifies/optimizes it, selects compatible optional
HyperAlloc runtime support, then emits native code through LLVM. Runtime lowering must
not require an Emerald AST or frontend-local data structure.

The compiled `SublangMain` executable now reads versioned `.sublang-wire` files and
emits LLVM plus the memory plan. The capped launcher verifies, optimizes and links
that LLVM without an Emerald toolchain mount. See [wire/process interface](Sublang_Wire.md).
The transport is experimental, not a permanently stable public ABI. The C entry
currently goes directly through Clang/LLVM; its semantic summary importer is still
missing. All eight strategy families now have executable native paths. The accepted
IR subset, explicit shared-graph contracts and differences from the original Bond
collector are documented in [HyperAlloc IR](HyperAlloc_IR.md); strategy coverage does
not establish full original-runtime or performance parity.

## Verification evidence

One bundled runner was used per changed memory boundary, all compilation/execution in
a networkless read-only Docker sandbox capped at 6,000,000,000 bytes RAM/RAM+swap, no swap.
The final bundle covers all previous native cases plus primitive Folded fields (42),
retained Shard graphs mixed with heap children (5085 across two invocations), Root churn
fallback (5085), Pool borrows (100), and integer folding (47). Fifteen signed product
boundary cases use independent exact expected integers. Overflow and division failures
abort in both variants even when their result is discarded. ASan/LSan checks mixed
region/heap cleanup; the previous deep Root and transfer leak checks remain in the bundle.

These are correctness and placement checks. No speed/RSS benchmark or complete old-Flow
compatibility result is claimed.

2026-10-11: the expanded bundle also passes Static UTF-8 strings (200), Inline and
owned-object lists (199), Record value lists (42), dependent nested regions (28),
and shared cyclic graphs with owned Root children and an owned function roundtrip
(55), in both variants through LLVM and native execution. A 64-node SCC exercises
component caching, repeated temporary handles, edge-change invalidation and partial
graph reclamation while preserving the surviving root (4242). ASan/LSan checks both
list layouts, joined regions and cycle/Root cleanup. Negative tests reject an
element view after clear, a shared view after scope end, and a child view invalidated
through a second shared handle. String negative-index access aborts in both variants.
