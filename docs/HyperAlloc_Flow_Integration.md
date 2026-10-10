# HyperAlloc Flow integration

All eight Flow strategy families now have executable native paths. Full original
runtime/semantic parity remains a separate compatibility target; the exact implemented
contracts and remaining limits are in [HyperAlloc IR](HyperAlloc_IR.md).
The implementation is Emerald source under `src/sublang/hyperalloc` and LLVM lowering
under `src/sublang/backend/llvm` and `llvmflow`. No foreign GC integration is in scope.

## Executable now

| Capability | Implemented behavior |
| --- | --- |
| Analysis | CFG fixed-point scopes, definite allocation liveness, field initialization joins |
| Nested lifetimes | Nested scopes, loops, conditional allocation and early scope ends |
| Interprocedural borrows | Verified read/write permissions, transitive forwarding, noescape derived from bodies |
| Call safety | Live and fully initialized arguments; mutable/owned argument aliases rejected |
| Ownership transfer | Consuming owned parameters, owned returns, caller scope adoption, use-after-move rejection |
| Memory plan | Immutable, revision-associated allocation decisions and explanations |
| Folded | Primitive class fields become scalar slots when the object address is unobserved, including proved one-field getter calls |
| Shard | Closed graphs use aligned chunks and nested dependent regions; adoption joins toward the longer lifetime |
| Local | Acyclic-entry stack placement, no object header |
| Pool | Invocation-local slots plus bounded exact-layout runtime caches; destruction precedes reuse |
| Inline | Contiguous value lists and inferred immutable-class elements; checked realloc growth and element-view invalidation |
| Static | String literal bytes in immutable globals, with byte indexing/equality and value copying |
| Bond | Shared roots/edges, owned calls/returns, cycle collection and exclusive Root children of shared parents |
| Root | Exclusive child fields, adoption/replacement/take/clear, iterative tree destruction, read-only views with transitive ancestor invalidation |
| ScopeOwned | Nonmoving dynamic ownership chains, 16-byte prefixes, O(1) detach/adopt and automatic scope cleanup |
| Flow option | on/auto choose proven Folded, Local, Pool, Shard, Root or ScopeOwned; off uses heap and required cleanup |
| LLVM | Typed layouts, compiled runtime helpers, overflow/failure behavior preserved |

The new scope runtime is a foundation for Flow, not a substitute name for all of
Emerald's existing runtime. Unsupported constructs are rejected with no LLVM output.
The generic verifier still does not advertise general lifetime/effect readiness;
the native backend proves its documented subset separately.

## Remaining integration work

1. Extend the implemented direct-reference transfers to reference block arguments/merges,
   richer provenance and ownership-dependent analyses; add stable serialized contracts.
2. Extend implemented read-only graph/list views to mutable views and richer alias
   sets; shared mutations currently invalidate shared-derived views conservatively.
3. Bond: weak references and arbitrary bidirectional Root/Bond conversion; counted
   shared graphs, local trial deletion and revision-checked SCC caches exist.
4. Broader cross-function region escape proofs and measured Pool/chunk cache policies.
5. Language/runtime coverage beyond static String and value/class lists: dynamic
   strings/object identity, dispatch, threading and exception cleanup contracts.
6. Emerald adapter and migration: translate the bound program into Sublang IR, map existing
   Flow behavior explicitly, verify representative programs and only then migrate selfhost.

Existing Emerald analysis/runtime sources remain the reference for established behavior.
They are coupled to Emerald AST/catalog/layout and are not copied wholesale into the neutral
core. Their strategies need executable IR contracts before being enabled in Sublang.

## Verification

`bash scripts/sublang-backend-sandbox.sh` builds and runs only inside the networkless,
read-only Docker sandbox with a hard 6,000,000,000-byte RAM/RAM+swap limit and timeouts.
The bundled cases cover nested loop allocation, initialization joins, mixed placement,
borrow forwarding, owned transfer chains and negative lifetime/permission/move cases.
Root tree cases include replacement/take/clear, four invalid ownership cases and a
10,000-node chain. LeakSanitizer checks the nested heap scenario, both transfer variants
and both Root graph/deep-chain variants. The build entry point also exports a runnable
Root example with result 42. See [native slice](Sublang_Native_Slice.md) for the precise executable boundary.

No full-runtime compatibility, performance improvement or selfhost migration is claimed
from these small correctness cases.

The original Emerald optimization parity target, exact ported subsets and remaining work
are tracked in [Flow parity](Flow_Parity.md). Emerald itself is not modified by this migration.
