# Executable HyperAlloc IR contracts

All eight Flow strategy families have executable paths in the native64 backend.
This document describes those paths, not the unimplemented Dynamic/EH extension
proposals. The source implementation and runtime emission are Emerald `.ems`.

## Static values

`const.string(text) -> String` embeds exact byte data in a private immutable LLVM
global. `String` is a `{ pointer, i64 byteLength }` value. Copying it, storing it in
a record or passing/returning it does not allocate. `string.length`, `string.byte`
and `string.equal` operate on byte lengths, bounds-checked unsigned bytes and exact
byte equality. UTF-8 is preserved; indexing does not decode code points. Empty
strings never dereference their data pointer. These are static strings; dynamically
allocated concatenation is not part of this value contract.

## Collections and Inline

`List<E>` is a layout type, used through `Ref<List<E>>`. The list owns its buffer
and has an i32 length and capacity. Public length results are widened to i64.
Growth doubles capacity, checks the 2,147,483,647 element limit and byte-size
overflow, and uses `realloc`. Failure aborts without publishing a null buffer.

The operations and Emerald builder entry points are:

| IR operation | Builder | Contract |
| --- | --- | --- |
| `list.new` | `collections().listNew(type, scope, span)` | Owned, initially empty list in active innermost scope |
| `list.push` | `collections().push(list, element, span)` | Mutable borrow of list; value argument or consumed owned class |
| `list.length` | `collections().length(list, span)` | Read borrow, i64 result |
| `list.get` | `collections().get(list, index, span)` | Checked value read for primitive, String or Record elements |
| `list.borrow` | `collections().borrow(list, index, span)` | Checked read-only class-element view |
| `list.clear` | `collections().clear(list, span)` | Destroys owned elements; retains reusable buffer capacity |

Primitive, String and Record elements occupy contiguous value storage. Classes
with primitive/static-String fields also occupy contiguous storage without
per-element headers when consuming the owner and exposing only read-only views
makes their identity and mutable aliases unobservable. Fields may be declared
mutable and changed before the move. This is derived from the complete accepted
layout and use contracts; it is not a trusted frontend annotation. The executable
IR has no pointer-identity primitive or foreign pointer escape. Such operations
must acquire explicit identity-preservation rules before being admitted.

An eligible class temporary consumed only by an inline push can stay Folded:
its field slots are copied straight into the list buffer. Constructor-field
computation remains present. Classes with owned/shared fields retain
stable separately owned objects. Their list visitor enqueues children into the
iterative ownership destructor, including deeply nested owned graphs.

If a temporary needed an address for a verified call before the push, Local or
Pool storage can still be copied into the buffer. Headerless sources bypass heap
detach/drop; the move invalidates their borrows exactly as for a folded source.

Every element view depends on the list's lifetime. Push, clear, mutable calls,
list movement and scope cleanup invalidate views, including before a possible
`realloc`. A view cannot be stored as an owned child, returned owned, mutated or
carried across a loop edge as an independently live reference. Copy value elements
when an independent lifetime is required.

## Shard dependencies

Eligible closed ownership graphs use per-invocation region frames and aligned
chunks. Nested scopes have separate frames. Adopting a child joins its storage
dependency with the parent's region, always toward the shallower active lifetime.
Forwarding links preserve previous joins. A field take inherits storage provenance
from its owning root; its lexical destination alone is not its allocation region.

Graph cleanup precedes bulk backing release. Joined inner frames no longer own the
promoted chunks. Subsequent allocations resolve the representative region.
External reference parameters/results and ownership transfers through calls keep
stable Root storage. Profitability guards also keep Root for early-drop loop churn,
unretained takes and Pool graph resets that would retain dead region storage.

## Pool and Root

Nonescaping temporaries use Folded, headerless Local or reusable per-site Pool
slots. Pool graph slots destroy previous children before reuse. Other exclusive
graphs use Root with a 16-byte prefix, O(1) detach/adopt and iterative destruction.

Flow-enabled heap allocations additionally use exact-layout runtime caches: at
most eight dead blocks per layout and one MiB total per module. Destruction always
runs before storage enters the cache. Overflow blocks are freed immediately. The
generated executable flushes caches before returning from `main`. No power-of-two
padding or extra object-header word is introduced. Flow off disables this cache
and the optional temporary-placement strategies; required ownership cleanup stays.

## Bond shared graphs

`Bond<C>` is an explicitly shared, non-null class handle. Each owned handle is a
counted scoped root; typed Bond fields are graph edges with separate incoming-edge
counts. Shared objects alone pay for a sidecar in addition to their 16-byte prefix.

| Builder entry point | Behavior |
| --- | --- |
| `bonds().create(class, scope, span)` | Zero-initialized shared object and one owned root |
| `bonds().retain(handle, scope, span)` | Independent scoped handle to the same object |
| `bonds().borrow(handle, span)` | Read-only `Ref<C>` view tied to that handle |
| `bonds().link(owner, field, child, span)` | Set a shared edge without consuming child handle; cycles allowed |
| `bonds().get(owner, field, scope, span)` | Retained scoped handle to nonempty shared edge; empty edge aborts |
| `bonds().own(owner, field, child, span)` | Consume an exclusive Ref child into a shared parent |
| `bonds().clear(owner, field, span)` | Remove shared edge or destroy exclusive child |
| `bonds().write(owner, field, value, span)` | Write a mutable value field |

Owned Bond parameters/returns transfer a counted root without a transient loss of
reachability. Scope cleanup releases roots in a batch. Removing a root/edge makes
collection eligible; releases that keep all roots positive avoid a graph scan.
Cycle collection follows the original Flow candidate-local trial-deletion model:
gather a candidate's forward closure, initialize trial counts from roots plus incoming
edges, subtract internal edges, then propagate reachability from remaining external
references. Unreachable nodes lose every outgoing edge and exclusive child before
any shared node is freed. Intrusive scan/work links replace temporary scan arrays.

Stable strongly connected components of at least 64 members share a revision-checked
external-reference count. Their membership is the reverse closure of the candidate
within its forward closure. Root retain/release adjusts the shared count; a positive
count skips repeated scans. Edge changes invalidate cached proofs through the graph
revision. Components release their sidecar when their last member leaves. The neutral
backend derives reverse connectivity through typed field visitors rather than the
original Emerald incoming-edge catalog.

Shared aliases require stronger invalidation than direct SSA aliases: shared graph
mutation invalidates all current shared-root-derived views conservatively. Mutable
or owned Bond calls mixed with Ref arguments require a disjointness proof and are
currently rejected. This prevents a second handle from silently invalidating a
borrowed exclusive child. Owned Root children do not themselves carry Bond fields;
arbitrary bidirectional Root/Bond graph conversion is not implemented.

The original trial-deletion and component-cache strategy is implemented; data layouts
and reverse traversal are adapted to neutral IR. Functional cycle handling and cache
invalidation are tested; equivalent performance is not claimed. Concurrency, weak references,
user destructors/finalizers and exception unwinding are not accepted contracts.

## Files and verification

Wire v2 preserves literal bytes and the new operations/types. The reader also
accepts existing v1 core modules. Serialized metadata never substitutes for the
native lifetime proof. See [wire protocol](Sublang_Wire.md).

`scripts/sublang-backend-sandbox.sh` checks both Flow off and Flow on through LLVM
and native execution, plus ASan/LSan at the new memory boundaries. The sandbox has
a hard 6,000,000,000-byte RAM/RAM+swap limit, no swap or network, readonly inputs
and timeouts. This does not constitute an Emerald selfhost migration or a complete
old-runtime compatibility/performance result.
