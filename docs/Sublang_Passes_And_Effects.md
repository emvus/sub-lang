# Sublang Snapshots, Pass Manager and Derived Effects (M1/M2)

Status: reference for the uncommitted working tree. Each statement was checked against the
source named in its section. The snapshot/pass/cache acceptance harness was executed on
October 11, 2026; other historical source-only observations are marked where applicable.

Primary sources:

| Area | Files |
|---|---|
| Snapshots | `src/sublang/snapshot/SublangSnapshotStore.ems`, `SublangSnapshotKey.ems`, `SublangEntityMap.ems`, `SublangModuleCopy.ems`, `SublangFunctionCopy.ems`, `SublangModuleLinker.ems`, `SublangFunctionLink.ems`; `src/sublang/ir/SublangModule.ems` (`derived`, `freeze`) |
| Pass manager | `src/sublang/pass/SublangPassManager.ems`, `SublangPassDescriptor.ems`, `SublangPassResult.ems`, `SublangAnalysisCache.ems`, `SublangPassReport.ems` |
| Optimind passes | `src/sublang/pass/SublangFoldPass.ems`, `SublangDeadComputationPass.ems`; `src/sublang/optimind/*.ems` |
| Effects | `src/sublang/effects/*.ems` |
| Blockers | `src/sublang/hyperalloc/SublangObjectUses.ems` |
| Backend gate | `src/sublang/backend/SublangBackendGate.ems` |
| Routing | `src/sublang/backend/SublangCompiler.ems` |

## 1. Snapshot identity

A snapshot is one revision of a module. `SublangModule.derived(source, revision)` creates a new
module that carries the source's stage, entry function id, operation counter and parent revision
(`parentRevisionValue`). The module tables are then filled by the copier. `freeze()` seals the
module, its tables and every function, block and operation; a frozen revision refuses mutation,
and analyses must refer to a frozen revision.

`SublangSnapshotStore` assigns lineage identity:

| Item | Rule (source) |
|---|---|
| Lineage instance | assigned by `admit(module)` when the module object is not yet in `snapshots` (`SublangSnapshotStore.admit`); the instance is the 1-based position of the lineage in `headRevisions` |
| Identity test | `snapshots.indexOf(module)`. The store comment states that instances are assigned by object identity |
| Module name | not identity. The store and key comments say two modules with equal names are different instances |
| Key | `SublangSnapshotKey(instance, revision)`; `text()` renders `m<instance>@r<revision>` |
| Valid key | `instance >= 1 && revision >= 1`; `admit` of an unfrozen module returns the key `(0, 0)` |
| Head | `headRevision(instance)`: the newest revision committed to the lineage. `isHead(key)` is true only for that revision |
| Next revision | `nextRevision(instance) = headRevision + 1` |
| Commit | Requires a frozen, previously unregistered derived module, a parent that is the current head, `derived.parentRevision() == parent.revision()` and `derived.revision() == headRevision + 1`; only then advances the head |

A superseded snapshot stays valid data. `run` rejects it with `SUBLANG-P011`. To work from it,
call `manager.fork(module)`: this deep-copies it into a new lineage, demotes old proof references,
validates the copy and returns a `SublangPassResult` with its origin map. Fork revision numbers
start at source revision + 1; later passes advance only the new lineage. The source head does
not change. The store independently rejects stale-parent commits.

Store scope: `SublangPassManager` is created with a new `SublangSnapshotStore` and a new
`SublangAnalysisCache` for each call of `SublangCompiler.compile` (`SublangCompiler.compile`).
A key from one store is unrelated to a key from another store.

## 2. Revisions and the entity map

`SublangEntityMap(from, to)` records how entities of the previous snapshot map to the new one.
Its keys are snapshot texts (`m<i>@r<r>`).

| Kind string | Recorded by | Meaning |
|---|---|---|
| `value` | `SublangFunctionCopy.copy` | a value id whose new id differs from the old one (0 = erased with a removed operation) |
| `op` | `SublangFunctionCopy.copyBlock` | an operation removed from the copy (new id 0) |
| `op-replaced` | `SublangFoldPass.function` | an operation replaced in place by a constant (old id = new id) |

The kinds `function`, `type` and `field` are named in the comment of `SublangEntityMap` but no
caller records them (grep of `.record("` in `src/sublang`).

`lookup(kind, functionId, oldId)` returns the recorded new id, `0` for an erased entity, or the
old id when nothing was recorded. `countFor(functionId)` counts the `op` and `op-replaced`
entries of one function; the optimind plan line uses it (section 6). `erasedCount(kind)` and
`replacedCount(kind)` count entries with new id 0 and nonzero new id.

## 3. Deep copy, value renumbering and stale-proof demotion

`SublangModuleCopy.copy(source, revision, removedFunctions, removedOps, map)` builds the successor
module by a full rebuild. The comment states that nothing is shared with the source: every table
entry and operation is a new object.

Order of the copy:

1. `SublangModule.derived` (revision set to the new revision).
2. Sources and spans.
3. Types: the type table starts with 4 builtin entries created by its constructor (Void, Bool, Int, Float; `SublangTypeTable`). The copy re-adds ids from 5 upward, then the fields, then `restoreFieldLists` removes fields that the source had removed from a type's field list.
4. Semantic profiles, failure actions and effect summaries. Effect-summary facts are copied with demotion (below).
5. Aliases: locations, then alias facts with demotion.
6. Dispatch: classes, groups and entries (tags and function ids are copied unchanged).
7. Each function, through `SublangFunctionCopy.copy`.

### 3.1 Renumbering inside a function

`SublangFunctionCopy.valueRemap` numbers surviving values densely from 1. A value defined by a
removed operation gets 0. Operand, result, parameter and block-argument references are passed
through the remap (`operation`, `copyBlock`). Operation ids, block ids, type, field, function and
scope ids are preserved.

For every value whose new id differs from the old one (including 0), a `value` entry is recorded.
For every removed operation, an `op` entry with new id 0 is recorded.

### 3.2 Stale-proof demotion

A proven fact keeps neither its proof reference nor its provenance in a new revision. In
`SublangModuleCopy.facts` (effect summaries) and `SublangModuleCopy.aliases` (alias facts):

| Field | Old value | New value |
|---|---|---|
| provenance / origin | `proven` | `declared` |
| label | the old proof text | `stale-proof:<analysis>@r<revision>` (analysis and revision of the old proof reference) |
| evidence | the old proof reference | `SublangProofReference.missing()` |

Facts that are not `proven` are copied with their label and evidence. The stale-proof label is
the only text that records the old proof.

## 4. Pass descriptors and the pass manager

`SublangPassDescriptor(name, version, stage, requires, preserves)`. Everything not named in
`preserves` is invalidated. The comment states that a preservation claim is honored only when the
manager re-establishes the named invariant on the new snapshot.

| Descriptor | Name | Version | Stage | Requires | Preserves |
|---|---|---|---|---|---|
| `fold()` | `optimind.fold` | 1 | `High` | none | `callgraph` |
| `deadComputation()` | `optimind.dce` | 1 | `High` | `effects` | `callgraph` |

`SublangPassManager.run(passName, module)` checks, in this order:

| Code | Condition | Result |
|---|---|---|
| `SUBLANG-P010` | the input key is not valid (module not frozen) | rejected |
| `SUBLANG-P011` | the input is not the lineage head (`isHead` false); text: `input snapshot <key> is superseded; fork it or use the head revision` | rejected |
| `SUBLANG-P012` | Resource budget, structural, semantic or target-specific lifetime validation fails | rejected, including the underlying cause |
| (no code) | `optimind.fold` | `derive(fold, ...)` with no removed functions or operations |
| (no code) | `optimind.dce` | `eliminate` (effects of the input, then `SublangDeadComputationPass.select`) |
| `SUBLANG-P013` | any other pass name | rejected |

`derive(descriptor, module, previous, functions, operations, removals)`:

1. The new revision is `nextRevision(previous.instance)`. The map is `SublangEntityMap(previous key, m<instance>@r<revision>)`.
2. If the pass is `optimind.dce` and `removals == 0`, the input is returned unchanged; no revision is created.
3. `SublangModuleCopy.copy` builds the draft. For `optimind.fold`, `SublangFoldPass.apply` rewrites it.
4. If there are no rewrites and no removals, the input is returned unchanged.
5. The draft is frozen and validated for resource budget, structure, semantics and the context's lifetime rules. A failure is rejected with `SUBLANG-P014: <pass> produced an invalid snapshot: <cause>`, before committing or preserving analyses.
6. `store.commit(draft, module)` is called. A refusal is rejected with `SUBLANG-P015: snapshot lineage rejected the new revision`.
7. The result is marked changed with the rewrite and removal counts, and `preserve` runs.

A rejected or unchanged run returns the input module, so `module()` is always usable (`SublangPassResult`).

`preserve(descriptor, before, after, ...)`: when the descriptor names `callgraph`, the old call graph
(of `before`) and a fresh call graph (of `after`) are compared with `sameEdges`. The comparison
requires equal edge counts and equal `edgeFromAt`/`edgeToAt` at every index. If the edges match,
the fresh graph is stored under the new snapshot key and the result records `callgraph` as
preserved. Otherwise nothing is stored, and the next request recomputes the graph.

## 5. Analysis cache

`SublangAnalysisCache.key(snapshot, analysis, version, options)` renders
`<snapshot text>|<analysis>/<version>|<options>`. Manager options include a cache-local store
namespace and a length-prefixed context fingerprint.

| Analysis | Key options | Where |
|---|---|---|
| effects | Store identity, target, provider, ABI, profile selector, options, module stage | `SublangPassManager.effects` |
| callgraph | The same compilation context, plus `direct` | `SublangPassManager.callGraph`, `preserve` |

Revision and lineage are part of the key, so a successor revision never reuses another revision's
results. Preservation re-keys an entry explicitly (`putGraph` with the new key). The cache counts
hits and misses only for effects lookups (`hasEffects`).

Use `SublangPassManager.forContext(store, cache, context)` with an immutable
`SublangPassContext(target, provider, abi, profile, options)`. The ordinary compiler supplies its
effective Flow and Optimind options. Frozen module profile tables are covered by snapshot
identity. An unfrozen module's analysis is recomputed without entering the cache.

Each analysis table retains at most 64 entries; reaching capacity clears that table before the
next insertion. Replacing an existing key updates it without growing the table. This is an
entry bound, not a byte bound for analyses or the snapshot store. Stores retain snapshots and
must be scoped to a compilation/session; persistent caches are not implemented.

`SublangPassResult.structureStatus()`, `semanticsStatus()` and `memoryStatus()` distinguish
`valid`, `invalid` and `not_checked`. A rejected transformation reports its candidate's validation
status and returns the original module. Memory verification currently covers the accepted
`native64-host-libc` / `host-libc-runtime` / `low.native64.v1` scoped-ownership rules only.
Unsupported target/provider/ABI contexts reject with `SUBLANG-P017`; this is not a universal
proof for arbitrary language/runtime semantics. Resource limits are shared with codegen through
`limits/SublangResourceBudget`. Generic `SublangVerification.memoryStatus()` remains
`not_checked`; the manager does not relabel that generic verifier.

## 6. Optimind passes

`SublangCompiler.compile` with Optimind on runs `optimind.fold`, then `optimind.dce` on the fold
result. The optimized snapshot is used only if both passes are accepted and the result passes
`SublangBackendGate.check`; otherwise the original snapshot is compiled and the report says so
(section 6.3).

### 6.1 `optimind.fold` (`SublangFoldPass`)

Facts come from `SublangOptimind.analyzeModule(draft, function, true)` for each body function.
A fold replaces an operation in place (same operation id and result value) with `const.int` or
`const.bool`. It applies only when all of these hold:

- the operation has a result whose fact is known;
- its opcode is not already a constant, and is `int.*` (any suffix), `compare` or `call.direct`;
- the result type kind is `Int` (replaced by `const.int`) or `Bool` (replaced by `const.bool`).

Operand computations are not removed by fold; they stay in the snapshot, and dead ones are left to
the DCE pass.

Sources of facts (`SublangOptimind`, `SublangConstantFold`, `SublangIntegerBounds`, `SublangValueFacts`):

| Operation | Fact derived when | Not derived |
|---|---|---|
| `const.int`, `const.bool` | always (constant) | |
| `int.add`, `int.sub`, `int.mul` | both operands known and `SublangIntegerBounds.safe` holds (no overflow) | any overflowing case |
| `int.div`, `int.rem` | divisor known and nonzero; the case `minimum / -1` gives `minimum` only for `int.div` with overflow `wrap`, and `0` for `int.rem` with overflow `zero` | divisor 0; `minimum / -1` in other modes |
| `int.neg` | operand known and not the minimum value | minimum value |
| `compare` | both operands known; predicates `eq`, `ne`, `lt`, `le`, `gt`, `ge` | |
| identities | `int.sub x x` gives 0; `int.mul` with 0 gives 0; `int.rem` with 1 gives 0 | |
| identities (alias only) | `int.add`/`int.sub` with 0, `int.mul`/`int.div` with 1 make the result an alias of the other operand | not applied by fold; used only by lowering (`facts.alias`) |
| `call.direct` | the callee passes the closed-body proof of section 6.1.1 | any other call |

Because a fold only exists when no trap is possible, a fold never removes a runtime check. This is
the reason for the comment "Fold only arithmetic proved not to overflow" in `SublangConstantFold`.

#### 6.1.1 Closed-body proof for calls (`SublangCallAnalysis.fold`)

The proof gives a constant result for a `call.direct` only when:

- the call has an Int or Bool result and every argument is a known constant;
- the callee has exactly one block of at most 64 operations;
- the callee is not already on the active call stack (recursion is refused) and the nesting depth is below 16;
- the total evaluation budget (4096 steps) is not exhausted;
- every operation in the body is a `const.*`, an `int.*`, a `compare` or a nested `call.direct`, and each non-call operation folds to a known constant (so any trapping or unknown operation makes the proof fail).

The comment says the proof is independent of declared effect and noescape annotations.

### 6.2 `optimind.dce` (`SublangDeadComputationPass`)

Selection runs per body function and repeats until no operation is found (a removal releases its
operands). A use count is kept for every value; the count is decremented for each removed
operation's operands.

An operation is removed only when all of these hold: it is not a terminator; it has no result or
its result has no uses; and its kind is in the removable set below.

| Removable | Condition |
|---|---|
| `const.*` (including `const.string`), `compare`, `float.*` (except `float.to_int`), `number.equal`, `string.length`, `string.equal` | always |
| `record.make`, `record.get`, `record.with` | result type kind is `Record`, `Int`, `Bool`, `Float` or `String` |
| `int.*` | overflow mode is `wrap` and the opcode is not `int.div` or `int.rem` |
| `call.direct` | callee `removableWhenUnused()` (section 7) is true; result type kind (if any) is `Int`, `Bool` or `Float`; every argument mode is `value` or `borrow_read` |

Never removed (by the rules above, or by the default `false`): terminators; `float.to_int`
(aborts when the value is not an exact integer); `int.div` and `int.rem` in every mode (a zero
divisor traps in every mode); `int.add`, `int.sub`, `int.mul`, `int.neg` and `int.to_float` unless
the overflow mode is `wrap`; every operation whose result has a use; every other opcode, including
field, list, text, byte, bond, class, scope and invoke/throw operations (the default case of
`dead`).

### 6.3 Plan lines and rejection

With Optimind on, `SublangPassReport.render` writes:

```
optimind: enabled; decisions are safe constant folds and removal of unused effect-free computations
optimind: snapshots <input key> -> <output key>; fold rewrote <n>; dce removed <m>
optimind: fn<id> <name>: <k> decisions
```

`<k>` is the number of `op` and `op-replaced` entries of that function in the fold and DCE maps.
With Optimind off, the line is `optimind: disabled; no transformation decisions`.

When either pass is rejected, or the optimized snapshot fails the backend gate, the line is:

```
optimind: transformation rejected; compiled the original snapshot (fold: <message>) (dce: <message>)
```

The parenthesized parts appear only for the rejected pass; when neither pass was rejected the text is
`(the optimized snapshot failed the backend gate)`.

## 7. Derived interprocedural effects (`src/sublang/effects`)

`SublangEffectAnalysis.derive(module)` computes one summary per function. A summary is a set of
areas with a value each, plus per-parameter flags and a few function flags. The analysis derives
facts from the body; declared annotations are only checked against it (section 7.9).

### 7.1 Areas and values

Area names, in index order (`SublangVocabulary`, the list returned by `effectAreas()`):

| Index | Area | Values |
|---|---|---|
| 0 | `allocation` | `none`, `may`, `unknown` |
| 1 | `escape` | `none`, `may`, `unknown` |
| 2 | `failure` | `none`, `may`, `unknown` |
| 3 | `exceptions` | `none`, `may`, `unknown` |
| 4 | `memory-read` | `none`, `may`, `unknown` |
| 5 | `memory-write` | `none`, `may`, `unknown` |
| 6 | `synchronization` | `none`, `may`, `unknown` |
| 7 | `observable` | `none`, `may`, `unknown` |
| 8 | `control` | `returns`, `may-diverge`, `unknown` |

Internally the values are the integers 0, 1 and 2 (`SublangFunctionEffects`, `areaText()`).
For `control`, 0 is `returns`, 1 is `may-diverge`, 2 is `unknown`. For the other areas, 0 is
`none`, 1 is `may`, 2 is `unknown`.

Provenance strings accepted by the vocabulary: `declared`, `assumed-conservative`, `proven`.

### 7.2 Lattice and join

The order is 0 < 1 < 2. `raise(area, value)` keeps the maximum. `absorb(other)` joins a whole
summary: each area takes the maximum, the boolean flags (per-parameter and function flags) are
OR-ed, and the call returns true if anything grew. `widenToUnknown()` sets all nine areas to 2,
sets every per-parameter flag to true, and sets `readsOther`, `writesOther`, `returnsFresh` and
`returnsUnknown`. It does not set `external`.

Per-parameter flags: `readsParams`, `writesParams`, `escapesParams`, `returnsParams`.
Function flags: `readsOther`, `writesOther`, `returnsFresh`, `returnsUnknown`, `external`.

### 7.3 Call graph and strongly connected components (`SublangCallGraph`)

- Edges come from `call.direct` and `invoke` operations whose target id exists in the module.
  `call.virtual` adds one edge for each dispatch entry whose function exists.
- Every function id is a node, including external functions (definition other than `body`), which have no outgoing edges.
- A reference to an id that does not exist adds no edge.
- Components are computed with Tarjan's algorithm (the comment in `SublangCallGraph` says so). The
  implementation is recursive (`visit` and `follow` call each other).
- Components are emitted in Tarjan completion order, so callees come before callers.
  `SublangEffectAnalysis` solves components in index order (bottom-up).
- `isRecursive(f)` is true when `f` calls itself or its component has more than one member.

The header comment of `SublangCallGraph` mentions a `components()` method that does not exist;
the accessors are `componentCount`, `memberCount` and `memberAt`.

### 7.4 Fixpoint and widening

Per component (`SublangEffectAnalysis.solve`):

- The round bound is `members * 24 + 8`. Each round refreshes every member. A member that is
  external is skipped. A recursive member gets `control` raised to 1 (`may-diverge`).
- If the bound is reached while a change is still pending, `widen` runs: it marks the result
  widened, calls `widenToUnknown()` on every member, and appends one note per member:
  `SUBLANG-E009: effect analysis budget exhausted for function <name>; widened to unknown`.

Inside one function (`SublangEffectTransfer`), the sweep over the body is capped at 64 passes.
When the cap is reached with a change still pending, the transfer calls `widenToUnknown()` and
returns. This path emits no note and does not set the widened marker, so it is not reported
through `SUBLANG-E009`.

### 7.5 Transfer function, regions and escape

Each body is run through `SublangEffectTransfer` with a region-flow graph (`SublangRegionFlow`).
Tokens:

- one token per parameter whose type kind is `Ref`, `Bond`, `List` or `Class`;
- one token per allocation site (`class.new`, `list.new`, `bond.new`) and per call whose callee has `returnsFresh`;
- one unknown token.

Token numbers: sites follow the parameters; the unknown token is last. Two relations only grow:
`origin(value, token)` (which token a value may carry) and `contents(from, to)` (which token may be
stored in another). `closure()` is reachability over `contents`.

The escape definition, quoted from `SublangEffectTransfer`:

> "A parameter escapes when it is reachable from a returned region, from the unknown region, or from the memory of another parameter, which outlives the call."

Implementation: roots are the unknown token and the tokens of returned values (`publishEscapes`),
then parameters reachable from other parameters are marked (`escapeThroughParams`). A callee
escape flag links the argument to the unknown token. An unclassified call links all of its
operands to the unknown token.

### 7.6 Removability and memory-free predicates (`SublangFunctionEffects`)

`removableWhenUnused()` is true when these areas are all 0: `allocation`, `failure`, `exceptions`,
`memory-write`, `synchronization`, `observable`, `control`, and `writesOther` is false.

It does **not** test the `escape` area, the `memory-read` area, or `readsOther`.

`memoryFree()` is `removableWhenUnused()` plus `memory-read` == 0 and `readsOther` false.

Consumer of `removableWhenUnused()`: the DCE pass for `call.direct` (section 6.2).

Because `escape` is not tested, a function whose only nonzero area is `escape` passes `memoryFree()`.
This follows from the code as read; the harness fixtures do not cover that case (see section 11).

### 7.7 LLVM attributes

`SublangEffectReport.attributes(module, result, id)` returns the only attribute string in the source:

```
nounwind willreturn memory(none)
```

It is returned only when all of these hold: the function has a body; it is not the module entry
function; and `memoryFree()` holds. Every attribute therefore comes from a memory-free summary.
The attribute string is used by the legacy emitter (`SublangLlvmEmitter.emit`) and passed to
`SublangLowering` (`setAttributes`), which Low emission prints in the function header.

### 7.8 Plan lines

`SublangEffectReport.render` writes one line per function, in id order:

```
effects: fn<id> <name>: allocation=<v> escape=<v> failure=<v> exceptions=<v> memory-read=<v> memory-write=<v> synchronization=<v> observable=<v> control=<v>[ arg<i>=<flags>]...[ llvm=<attributes>]
```

- `<v>` is the area text from 7.1.
- `arg<i>=<flags>` is written for each parameter with at least one flag. The flag letters are `r` (reads), `w` (writes), `e` (escapes) and `R` (returns), in that order.
- `llvm=...` is written only when the attribute string is non-empty.

The optimind plan lines are in section 6.3. The effects lines are placed after the optimind line
and before the route line (`SublangCompiler.finish`). Notes from the effect analysis are not written by `render`.

### 7.9 Contradiction check (`SUBLANG-E008`)

`SublangEffectChecks.contradictions` checks only functions with a body. For each declared effect
fact, the claim is converted to a level (`claimed`):

| Declared value | Level |
|---|---|
| provenance `assumed-conservative` | no claim (-1) |
| value `none` or `returns` | 0 |
| value `may` or `may-diverge` | 1 |
| anything else | no claim (-1) |

A contradiction exists when the claimed level is at least 0 and below the derived level for that area.
Message: `SUBLANG-E008: function <name> declares <area>=<value> but its body derives <derived text>`.

Parameter checks produce two more `SUBLANG-E008` messages:

- `SUBLANG-E008: parameter <name> of <fn> is declared noescape but its body lets it escape`
- `SUBLANG-E008: borrow_read parameter <name> of <fn> is written by its body`

The harness and `SublangPassManager.effectDiagnostics` expose contradictions. The compiler also
appends `SublangEffectReport.diagnostics` to the memory plan, including `SUBLANG-E008` findings.
They are diagnostics rather than trusted frontend proofs or automatic compile-time errors.

### 7.10 Result notes

`SublangEffectResult` stores notes, including `SUBLANG-E009`. The compiler's
`SublangEffectReport.diagnostics` appends these notes to the memory plan. The backend gate still
uses derived summaries for lifetime checking without separately printing their notes.

## 8. Blockers and how Explain names the callee (`src/sublang/hyperalloc/SublangObjectUses.ems`)

`SublangObjectUses` decides whether a region (shard) can hold an allocation. Each reason is
recorded once: `blockShard(reason)` stores a blocker only while the region is still safe, so the
first reason wins. `shardBlocker()` returns the stored blocker, or one of two defaults:

- `small acyclic graph does not justify a chunk`, when the graph is acyclic and has fewer than 8 allocation sites;
- `none`, otherwise.

The initial region state starts with the blocker `owned result may leave the region` when the
function's return type is a `Ref`.

Blocker reasons, in the order the source can produce them:

| Trigger | Reason text |
|---|---|
| reference parameter (constructor) | `reference parameter <name> can connect to an external graph` |
| opcode `list.*` or `text.*` | `collection elements require independent ownership storage` |
| opcode `bond.*` | `shared graph lifetime is managed by Bond` |
| `class.upcast` with owned mode | `owned upcast of a reference moves it across ownership scopes` |
| `call.direct` or `call.virtual` with a `Ref` result | `reference call result of <callee> requires an imported ownership region` + derived suffix |
| owned argument of `call.direct`, `invoke` or `call.virtual` | `owned argument <i> of call to <callee> may leave the region` + derived suffix |
| owned return | `owned return may leave the region` |
| in a CFG cycle: `field.take` of an unmoved value | `taken subtree released in a loop would retain dead region storage` |
| in a CFG cycle: `class.new` of an unmoved value whose type has a `Ref` field | `Pool graph reset in a loop would retain discarded region storage` |
| in a CFG cycle: `field.write` or `field.clear` on a `Ref` field | `early subtree release in a loop would retain dead region storage` |
| in a CFG cycle: `borrow_write` operand of a call | `loop-capable mutable call can discard region subtrees` |

Callee name (`calleeName`):

- `call.virtual`: `dispatch group <group name>`;
- a target id that does not exist: `unknown target`;
- otherwise the callee's function name.

Derived suffixes, appended to the call-related reasons:

| Condition | Suffix |
|---|---|
| `call.virtual` | ` (derived: every registered implementation is considered)` |
| external callee | ` (derived: external target is unknown)` |
| argument escapes in the callee summary | ` (derived: the callee lets this argument escape)` |
| argument does not escape | ` (derived: the callee does not retain this argument, but region transfer is not modeled)` |
| result is `returnsFresh` (argument -1 only) | ` (derived: the callee returns a fresh allocation)` |

Where the callee-bearing blocker is printed. In `SublangFunctionMemoryPlan`, an enabled `class.new`
whose type has owned `Ref` fields gets the choice text:

```
Root: owned reference fields require iterative ownership cleanup; Shard blocked: <shardBlocker()>
```

Later conditions overwrite this choice for Local, Pool, Folded and Shard placements. The plan line
is written as:

```
revision=<R> function=<F> operation=<O> value=<V> scope=<S> type=<T> <choice>
```

So the callee name appears in the plan only when a `Root` placement is chosen for an allocation with
owned `Ref` fields and the blocker came from a call. `shardBlocker()` is also read inside
`SublangObjectUses` (line 164) to decide a shard-eligibility condition; that use does not print text.

## 9. Backend gate (`src/sublang/backend/SublangBackendGate.ems`)

`SublangBackendGate.check(module)` returns the first error text, or `""`. It is called by
`SublangCompiler.compile` before the passes, and again on the optimized snapshot. The gate itself
never returns a `SUBLANG-E` code.

| Code | Condition |
|---|---|
| `SUBLANG-B001` | the input snapshot is not frozen |
| `SUBLANG-B002` | the verifier is not structurally valid or its semantics status is not `valid`; text is the first diagnostic code and message, with a span when available |
| `SUBLANG-B003` | budget exceeded: module (more than 32 functions, 512 types or 512 fields); function (more than 64 blocks or 4096 values); block (more than 4096 operations); scope id outside 1..32768; operation count or id outside 1..32768 |
| `SUBLANG-B004` | records with non-primitive fields (class fields may also be Ref or Bond owned by a class); failure binding other than `unbound` or `libc.abort`; external contract without a body; reference parameter without a `borrow_read`, `borrow_write` or `owned` contract |
| `SUBLANG-B005` | `SublangLocalLifetime` check fails for a function; prefixed `fn<id>: `; examples: `lifetime field-pair budget exceeded (512)`, `lifetime fixed-point budget exceeded`, `call to <name> may throw while cleanup is pending; use invoke` |
| `SUBLANG-B006` | the entry function is not `() -> i64` |
| `SUBLANG-B008` | duplicate operation id (in the budget checks) |

Budget and lifetime error texts are produced by `SublangBackendBudget` and `SublangLocalLifetime`;
the gate passes them through unchanged, except that B005 adds the function prefix.

Codes produced outside the gate: `SUBLANG-B007` (invalid Flow mode, `SublangCompiler.compile`) and
`SUBLANG-B009` (extension operations that the legacy emitter cannot produce, `SublangCompiler.finish`).

## 10. Harness coverage

`src/sublang/harness/pass/SublangPassChecks.ems` contains checks for the effect summaries
(pure helper memory-free, memory writer not removable, reader summary, allocating helper area 0,
recursion classified as `may-diverge`, declared-pure writer not trusted) and for the
contradiction diagnostics. `scripts/sublang-pass-sandbox.sh` executed these checks successfully
on October 11, 2026, together with independent forks, stale-parent rejection, escaping-borrow
rejection, target/provider/ABI/profile/options cache isolation, cross-store isolation, draft-cache
bypass and bounded analysis retention.

## 11. Limitations

1. Optimind folds and removals are local. Fold rewrites scalar `int.*`, `compare` and `call.direct`
   results only. The closed-body proof accepts single-block callees with at most 64 operations.
2. `removableWhenUnused()` does not test the `escape` or `memory-read` areas or `readsOther`
   (section 7.6). `memoryFree()` tests `memory-read` and `readsOther`, but not `escape`. Attributes
   therefore follow `memoryFree()` (section 7.7).
3. The transfer-level cap (64 passes) widens to unknown without a separate note (section 7.4).
4. Effect contradictions reach the plan as text, not a structured request/result protocol.
5. Snapshot stores retain their admitted revisions; entry-bounded analysis caches do not bound
   the byte size of the snapshot history.
6. Stale-proof demotion applies to effect-summary facts and alias facts. The EntityMap kinds
   `function`, `type` and `field` are documented but never recorded (section 2).
7. Blocker texts are the only explanation of region decisions. The callee name is printed only in
   the `Root ... Shard blocked` placement text (section 8).
8. The effect fixpoint bound is `members * 24 + 8` per component; this is an inline expression, not a named constant (section 7.4).
9. Native lifetime validation is target-specific. This does not establish arbitrary external
   runtime contracts or a general-purpose memory proof system.

`UNVERIFIED:` the claims in sections 7.3 and 7.5 about the exact Tarjan implementation and the
region-flow closure rely on a read of the recursive `visit` and `follow` functions by a subagent
digest, which was spot-checked only for the items listed in section 7.4 and 7.6.
`UNVERIFIED:` whether any harness fixture covers an escape-only summary (not checked).
