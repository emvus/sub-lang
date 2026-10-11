# Sublang Low IR (M3)

Status: canonical reference for the Low IR in the uncommitted working tree. Every statement
was checked against the source named in each section. Nothing here was produced by running the
compiler; statements about runtime behaviour that could not be confirmed by reading are marked
`UNVERIFIED:`.

Primary sources:

| Area | Files |
|---|---|
| Low model | `src/sublang/low/SublangLowOp.ems`, `SublangLowBlock.ems`, `SublangLowFunction.ems`, `SublangLowModule.ems` |
| Verifier and dump | `src/sublang/low/SublangLowVerifier.ems`, `SublangLowDump.ems` |
| Target, layout, provider | `src/sublang/low/target/SublangLowTarget.ems`, `SublangLowLayout.ems`, `SublangLowProvider.ems` |
| High to Low lowering | `src/sublang/lowering/SublangLowering.ems`, `SublangLowerContext.ems`, `SublangLowerScalar.ems`, `SublangLowerControl.ems`, `SublangLowerData.ems`, `SublangLowerMemory.ems`, `SublangLowerBond.ems`, `SublangLowerOwnership.ems` |
| Low to LLVM text | `src/sublang/backend/lowllvm/SublangLowLlvm.ems`, `src/sublang/backend/llvm/SublangLlvmEmitter.ems` (`emitLow`) |
| Routing | `src/sublang/backend/SublangCompiler.ems`, `SublangCompilation.ems`, `src/sublang/cli/SublangCommand.ems` |
| Plan binding | `src/sublang/hyperalloc/SublangMemoryPlan.ems` |

## 1. Purpose and what Low IR is not

Low IR is the typed, SSA-form intermediate representation between a frozen High snapshot and
textual LLVM. The lowering consumes three inputs: the High snapshot, the memory plan made for
that exact snapshot, and an explicit target. Every placement decision (stack, pool, shard, heap,
scalar fold), every ownership transfer and every checked failure is already an operation when
the Low module exists. The LLVM emitter only spells those operations.

Low IR is:

- a verified module: `SublangLowVerifier` runs before any Low text is used;
- target-explicit: concrete sizes, alignments and offsets come from `SublangLowLayout` for one `SublangLowTarget`;
- deterministic: `SublangLowDump` renders equal modules to equal text.

Low IR is not:

- LLVM text. `SublangLowLlvm` is a separate, mechanical printer, and the LLVM text written to disk is produced by `SublangLlvmEmitter.emitLow`, which wraps Low functions in provider text.
- a serialization format. The dump is a diagnostic rendering and is not read back (no parser for it was found in `src/sublang/low`).
- a general target abstraction. Only `native64-host-libc` is supported (section 6).
- complete. Some parts of the output are still LLVM text produced by the legacy host-libc provider (section 10).

## 2. Routing through Low

`SublangCompiler.compile` runs the backend gate, then (if Optimind is on) the `optimind.fold` and
`optimind.dce` snapshot passes, and then `finish`:

```
compile(module, optimind, flow)
  SublangOptions(flow).isValid()            else SUBLANG-B007
  SublangBackendGate.check(module)          else its error
  [optimind on] fold -> dce; if either is rejected or the result fails the gate,
                compile the original snapshot and report it in the optimind line
finish(target, manager, flow, optimind, optimindReport)
  effects   = manager.effects(target)
  plan      = SublangMemoryPlan(target, flow != "off", effects)
  lowering  = SublangLowering(target, plan, optimind, effects, SublangLowTarget.host())
  findings  = verify(lowering.low()) when lowering.ready(), else []
  if ready && no findings:  text = SublangLlvmEmitter.emitLow(...); route = "lowering: Low IR (native64-host-libc, N functions)"
  if ready && findings:     route = "lowering: legacy emitter; " + findings[0]        (text stays empty)
  if not ready:             route = "lowering: legacy emitter; " + problem[0]
  if text empty and module uses bytes, numeric, exception or object operations:
                            SUBLANG-B009 (no legacy fallback for those operations)
  if text empty:            text = SublangLlvmEmitter.emit(...)   // legacy text
  explain = plan.explain() + optimindReport + SublangEffectReport.render(...) + SublangEffectReport.diagnostics(...) + route + "\n" + notes
  if ready && no findings:  the Low dump is attached
```

Points that follow directly from this code:

- The plan line for a Low-routed module is `lowering: Low IR (native64-host-libc, <n> functions)`. The explanation text is written to `<output>.plan` by `emit-llvm` and is returned by `compilation.explainMemory()`.
- Each lowering note is printed as its own line starting with `lowering: ` (`notes`). These come from `context.note(...)`; the only producer found is the devirtualization note of `call.virtual` with a single implementation (`SublangLowerControl.virtual`).
- `withLowDump` is attached only when lowering is ready and its verifier reports no findings. A rejected Low module is never exposed as a verified dump.
- `SUBLANG-L014` appears only in the CLI. `dump-low` exits 1 with it when no verified Low dump is attached, including legacy fallback after a Low verifier finding.

## 3. CLI

```
sublang dump-low <input.sublang-wire> <auto|on|off> <on|off>
```

Argument 2 is the Flow mode (`SublangOptions.isValid`: `auto`, `on`, `off`); argument 3 is the
Optimind mode (`on` or `off`). The command runs the same pipeline as `emit-llvm`, writes nothing
to disk and prints the dump with `println`. Its errors are `SUBLANG-CLI001` (invalid Optimind
mode), `SUBLANG-CLI002` (input not a regular file or larger than 16 MiB) and `SUBLANG-L014`.

## 4. Structure

| Class | Fields and meaning |
|---|---|
| `SublangLowModule` | `name`; `target`; source `SublangModule` (identity); `sourceRevision`; `planRevision`; ordered `functions` (id = index + 1) |
| `SublangLowFunction` | `id`; `name`; `returnType` (Low type name); `origin` (High function id; the emitter names the LLVM symbol `@fn<origin>`); `attributes` (text from `SublangEffectReport.attributes`); value table (type and hint per value id); `paramValues`; blocks |
| `SublangLowBlock` | `id` (1-based); `paramValues` (block parameters, the SSA phis); ordered operations; a block must end in exactly one terminator |
| `SublangLowOp` | `opcode`; `result` (value id, 0 for none); `resultType`; `operands`; `immediate` (integer); `text` (symbol, predicate, global name or hint); `typeText` (Low type or aggregate name); `index` (field index or callee id); `targets` (block ids); `trueArguments` (count, `cond_br` only); `origin` (High operation id, 0 if none) |

Value ids run from 1 to `valueCount`. Function parameters are the first values. Every value has
exactly one definition (a parameter, a block parameter or an operation result).

Block mapping: Low block 1 is a dedicated entry block that holds stack slots and parameter
adoption. High block `b` becomes Low block `b + 1` (`SublangLowerContext.blockOf`). Extra blocks
are created by lowering for checks, branch forwarding and landing pads.

`SublangLowOp.isTerminator()` is true for `ret`, `br`, `cond_br`, `abort`, `invoke` and `throw`.

## 5. Types and concrete layouts

### 5.1 Low type names

| Low type | Produced for (`SublangLowLayout.lowOf`) | Size | Align | LLVM spelling (`SublangLowLlvm.type`) |
|---|---|---|---|---|
| `void` | High `Void` | 0 | 1 | `void` |
| `i1` | High `Bool` | 1 | 1 | `i1` |
| `i8` | High `Byte` | 1 | 1 | `i8` |
| `i32` | not produced by `lowOf`; used for string comparison results and list lengths | 4 | 4 | `i32` |
| `i64` | High `Int` | 8 | 8 | `i64` |
| `f64` | High `Float` | 8 | 8 | `double` |
| `ptr` | High `Ref`, `Bond`; also every runtime handle | `pointerBytes` (8) | 8 | `ptr` |
| `str` | High `String` | `2 * pointerBytes` (16) | 8 | `{ ptr, i64 }` |
| `list` | list header (runtime) | 16 | 8 | `%sublang.list` = `{ ptr, i32, i32 }` |
| `shard` | shard region frame | 40 | 8 | `%sublang.shard` = `{ ptr, i64, i64, i64, ptr }` |
| `bondroot` | Bond root | 24 | 8 | `%sublang.bond.root` = `{ ptr, ptr, ptr }` |
| `%t<id>` | any other High kind (`Record`, `Class`, `List` and others) | aggregate rule | max field align | `%t<id> = type { ... }` in the provider text |
| `hdr%t<id>` | pool header: two link words then the payload | `alignUp(16 + size(%t<id>), 16)` | 16 | `{ ptr, ptr, %t<id> }` |

The sizes and alignments of `shard` and `bondroot` were checked against the LLVM declarations
in `llvmflow/SublangLlvmShardRuntime.ems` and `llvmflow/SublangLlvmBondRuntime.ems`.

### 5.2 Aggregate rule

`SublangLowLayout` places fields in declaration order. Each field starts at the next multiple of
its alignment, and the aggregate size is rounded up to the largest field alignment (the natural
rule of a non-packed LLVM struct). `fieldOffset(aggregate, index)` implements this rule, but no
caller in `src` uses it; the emitter addresses fields with `getelementptr` and lets LLVM compute
the offset.

Fixed field tables used by lowering:

| Aggregate | Field 0 | Field 1 | Field 2 |
|---|---|---|---|
| `list` | `ptr` (data) | `i32` (length) | `i32` (capacity) |
| `hdr%t<id>` | `ptr` | `ptr` | `%t<id>` (payload) |
| `%t<id>` | field types from the High type table | | |

### 5.3 Known discrepancies between the layout and the LLVM text

| Case | Low layout | LLVM text | Status |
|---|---|---|---|
| `%t<id>` for a High `List` kind | `sizeOf` = 0, since a List type has no fields | `%t<id> = type { ptr, i32, i32 }` (16 bytes) | The High checker forbids a List field by value (`SublangTypeChecks.checkFieldType`), and List values are handled as `ptr` in Low. Reachability through a lowering path was not established. `UNVERIFIED:` whether a `lowOf` result of `%t<id>` for a List id can reach `sizeOf`. |
| `hdr%t<id>` size and alignment | alignment 16, size rounded to 16 | struct `{ ptr, ptr, %t<id> }` sized to its natural alignment (8, or the payload alignment) | The verifier does not compare these. Lowering uses the header type in `stack.alloc` with alignment 16 and in `field.addr` for the payload (`addPool`). `sizeOf` of a header is only used by `known()`, not for an allocation size. |

### 5.4 Mapping from High kinds

`lowOf(typeId)`: `Int` to `i64`, `Bool` to `i1`, `Float` to `f64`, `Byte` to `i8`, `Void` to `void`,
`Ref` and `Bond` to `ptr`, `String` to `str`, any other kind to `%t<typeId>`.

## 6. Target descriptor

`SublangLowTarget` carries `name`, `triple`, `pointerWidth` (bits), `libc`, `unwinding` and
`callingConvention`. `SublangLowTarget.host()` is the only constructor used by the compiler.

| Field | Value (`host()`) |
|---|---|
| name | `native64-host-libc` |
| triple | `x86_64-unknown-linux-gnu` |
| pointer | 64 bits (`pointerBytes` = 8) |
| libc | `host-libc` |
| unwinding | `abort-only` |
| convention | `c` |

`supported()` is true only when the name is `native64-host-libc` and the pointer width is 64.
`SUBLANG-L010` is reported otherwise. The harness (`harness/pass/SublangLowChecks.ems`) builds
a `wasm32` target to exercise that rejection; no path in `src/sublang/backend` produces another
target.

The triple is descriptive only. The LLVM text begins with a comment line and the runtime text,
and no `target triple` or `target datalayout` line is written (`SublangLlvmEmitter.provider`).
`UNVERIFIED:` whether the LLVM toolchain applies the x86_64 layout to the output in every
environment; this doc relies on the host default.

`describe()` renders the target as
`target=<name> triple=<triple> pointer=<bits> libc=<libc> unwinding=<unwinding> convention=<convention>`.

## 7. Opcodes

Notation: operands are listed in order; "args" means a variable-length argument list; types in
brackets are the required `typeText` attribute. Verifier codes are the findings that the
verifier reports for that opcode (section 9).

### 7.1 Constants and symbols

| Opcode | Operands | Result | Attributes | Notes |
|---|---|---|---|---|
| `const.i64` | none | `i64` | `immediate` = value | |
| `const.i1` | none | `i1` | `immediate` 0 or 1 | other values: L002 |
| `const.i32` | none | `i32` | `immediate` | |
| `const.f64` | none | `f64` | `immediate` = IEEE-754 bit pattern | printed as hex by `SublangDumpText.hex64` |
| `const.null` | none | `ptr` | none | emitted as `null` |
| `const.ptr` | none | `ptr` | `immediate` = address bits | emitted as `inttoptr (i64 N to ptr)` |
| `const.zero` | none | `[typeText]` | `typeText` = type; must be sized and not `void` | emitted as `zeroinitializer` (L002 otherwise) |
| `const.size` | none | `i64` | `typeText`; `immediate` = `layout.sizeOf(typeText)` | L002 for an unknown type |
| `const.str` | none | `str` | `text` = global name; `immediate` = byte length | emitted as `{ ptr @<name>, i64 N }`; the global is defined by the provider text |
| `sym.addr` | none | `ptr` | `text` = symbol name | emitted as `@<name>`; the verifier does not check the name |

### 7.2 Memory

| Opcode | Operands | Result | Attributes | Notes |
|---|---|---|---|---|
| `stack.alloc` | none | `ptr` | `typeText` (sized, not `void`); `immediate` = alignment | must be in block 1 (L001); `alloca`, with `, align N` when the alignment is positive |
| `load` | `ptr` | `[typeText]` | `typeText` | sized type required (L002) |
| `store` | `ptr`, value | `void` | `typeText` = stored type | the value must have that type |
| `field.addr` | `ptr` | `ptr` | `typeText` = `%t<id>`, `hdr%t<id>` or `list`; `index` = field index | `getelementptr <agg>, ptr p, i32 0, i32 index`; index range checked (L002) |
| `elem.addr` | `ptr`, `i64` | `ptr` | `typeText` = element type | `getelementptr <elem>, ptr p, i64 i` |
| `byte.addr` | `ptr`, `i64` | `ptr` | none | `getelementptr i8, ptr p, i64 i` |

### 7.3 Arithmetic and comparison

| Opcode | Operands | Result | Attributes | Notes |
|---|---|---|---|---|
| `i64.add`, `i64.sub`, `i64.mul` | `i64`, `i64` | `i64` | none | wrapping; emitted as `add`/`sub`/`mul i64`. Trapping arithmetic is not an `i64.*` op (see `rt.call` below) |
| `i64.neg` | `i64` | `i64` | none | emitted as `sub i64 0, x` |
| `f64.add`, `f64.sub`, `f64.mul`, `f64.div` | `f64`, `f64` | `f64` | none | `llvm.experimental.constrained.f<op>.f64` with `round.tonearest` and `fpexcept.ignore` |
| `cmp` | `a`, `b` (both of `typeText`) | `i1` | `typeText` in `i64`, `f64`, `i1`, `ptr`, `i32`; `text` = predicate | see the predicate table below |

Predicate table (`SublangLowVerifier.checkCompare`, `SublangLowLlvm.compare`):

| Operand type | Accepted predicates | Emitted as |
|---|---|---|
| `i64` | `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `ult`, `ule`, `ugt`, `uge` | `icmp`; signed forms get an `s` prefix except `eq`/`ne` and the `u` forms |
| `f64` | any predicate starting with `o` or `u` | `fcmp <pred>` |
| `i1`, `ptr`, `i32` | `eq`, `ne` | `icmp` |

### 7.4 Conversions

| Opcode | Operand | Result | Attributes | Notes |
|---|---|---|---|---|
| `sitofp` | `i64` | `f64` | none | |
| `fptosi` | `f64` | `i64` | none | poison for out-of-range input; lowering guards the call (`SublangLowerContext` comment) |
| `trunc` | `i64` | `[typeText]` (`i8` or `i32`) | `typeText` = target type | |
| `zext` | `[typeText]` (`i8` or `i32`) | `i64` | `typeText` = source type | |
| `str.len` | `str` | `i64` | none | `extractvalue ..., 1` |
| `str.ptr` | `str` | `ptr` | none | `extractvalue ..., 0` |

### 7.5 Aggregates

| Opcode | Operands | Result | Attributes | Notes |
|---|---|---|---|---|
| `agg.extract` | aggregate | field type | `typeText` = aggregate; `index` | field type must match `layout.fieldType` (L002) |
| `agg.insert` | aggregate, field value | aggregate | `typeText` = aggregate; `index` | both operand types checked (L002) |

### 7.6 Calls, exceptions and control flow

| Opcode | Operands | Result | Attributes | Notes |
|---|---|---|---|---|
| `call` | args | callee return type (`void` gives no result) | `index` = callee function id (1..functionCount) | args must match the callee parameter types; emitted as `call <ret> @fn<id>(...)` (L004) |
| `rt.call` | args | provider return type | `text` = provider symbol | signature from `SublangLowProvider` (section 8); emitted as `call <ret> @<symbol>(...)` (L004) |
| `invoke` | args | callee return type | `index` = callee id; two targets: normal, unwind | terminator; `invoke <ret> @fn<id>(...) to label %bN unwind label %bM`; the unwind block must start with `eh.catch` (L005) |
| `eh.catch` | none | `i64` | none | must be the first operation of a block (L005); emitted as a `landingpad { ptr, i32 }` with `catch ptr @_ZTIl`, then `__cxa_begin_catch` and `__cxa_end_catch` |
| `throw` | `i64` | none | none | terminator; allocates 8 bytes with `__cxa_allocate_exception`, stores the code, calls `__cxa_throw` with `@_ZTIl` and emits `unreachable` |
| `br` | args (one per target block parameter) | none | `target[0]` | terminator |
| `cond_br` | `i1` condition, true args (`trueArguments`), false args | none | targets [true, false]; `trueArguments` | terminator; the false arguments follow the true arguments |
| `ret` | zero or one value | none | none | terminator; the value must have the function return type (L002) |
| `abort` | none | none | none | terminator; `call void @abort()` then `unreachable` |

Lowering helpers that emit these opcodes are in `SublangLowerContext`: `runtime`, `runtimeNamed`,
`runtimeVoid`, `call`, `invoke`, `caught`, `raise`, `branch`, `conditional`, `ret`, `abort`, `guard`.
`guard(c)` emits `cond_br c` to a block with `abort` and a continuation block.

## 8. Runtime provider

`SublangLowProvider.signature(symbol)` returns `ret(p1,...,pn)` for each symbol that `rt.call` may
name, and the empty string for every other symbol. The verifier rejects an unlisted symbol with
L004, and rejects arity or type mismatches with L004 as well.

| Symbol | Signature |
|---|---|
| `abort` | `void()` |
| `sublang.add`, `sublang.sub`, `sublang.mul` | `i64(i64,i64)` |
| `sublang.div.trap`, `sublang.div.wrap` | `i64(i64,i64)` |
| `sublang.rem.trap`, `sublang.rem.zero` | `i64(i64,i64)` |
| `sublang.flow.allocate` | `ptr(ptr,i64)` |
| `sublang.flow.allocate.t<N>` (family prefix) | `ptr(ptr,i64)` |
| `sublang.flow.adopt` | `void(ptr,ptr)` |
| `sublang.flow.detach` | `void(ptr)` |
| `sublang.flow.drop` | `void(ptr,ptr)` |
| `sublang.flow.end` | `void(ptr,ptr)` |
| `sublang.shard.begin` | `void(ptr,ptr)` |
| `sublang.shard.end` | `void(ptr)` |
| `sublang.shard.leave` | `void(ptr)` |
| `sublang.shard.join` | `void(ptr,ptr)` |
| `sublang.shard.root` | `ptr(ptr)` |
| `sublang.shard.allocate` | `ptr(ptr,ptr,i64)` |
| `sublang.bond.allocate` | `ptr(i64,ptr)` |
| `sublang.bond.retain` | `void(ptr)` |
| `sublang.bond.root.add` | `void(ptr,ptr,ptr)` |
| `sublang.bond.root.take` | `ptr(ptr)` |
| `sublang.bond.scope.end` | `void(ptr)` |
| `sublang.bond.edge.set` | `void(ptr,ptr)` |
| `sublang.list.at` | `ptr(ptr,i64,i64)` |
| `sublang.list.push.slot` | `ptr(ptr,i64)` |
| `sublang.list.clear.t<N>` (family prefix) | `void(ptr)` |
| `sublang.text.append` | `void(ptr,ptr,i64)` |
| `sublang.text.equal` | `i1(ptr,ptr)` |
| `memcmp` | `i32(ptr,ptr,i64)` |

Notes on the table:

- Checked integer arithmetic goes through `sublang.add`, `sublang.sub`, `sublang.mul` and the
  division and remainder helpers. The overflow mode of the High operation selects the symbol
  (`SublangLowerScalar.integer`). The vocabulary (`SublangVocabulary.allowsOverflow`) allows
  `trap` or `wrap` for add, sub, mul and div, and `zero` or `trap` for rem. Therefore the
  symbols that can be produced are exactly the eight listed above, and `sublang.div.zero` is
  never produced.
- The per-type family symbols (`sublang.flow.allocate.t<N>`, `sublang.list.clear.t<N>`) match by prefix.
- Symbols that are not in the table and are not `rt.call` targets: `sublang.drop.t<N>` (drop
  visitors) and `sublang.bond.trace.t<N>` (Bond trace routines). Lowering references them
  through `sym.addr`, which the verifier does not check. Their bodies are generated LLVM text
  (`llvmdata/SublangLlvmLists.ems`, `llvmflow/SublangLlvmBonds.ems`).
- `sublang.str.<id>` globals referenced by `const.str` are not in the table either. They are
  defined by `SublangLlvmStrings`, using the High operation id as `<id>`.
- Exceptions: `SublangLowProvider.exceptionPersonality()` names `__gxx_personality_v0`. The
  LLVM emitter adds `personality ptr @__gxx_personality_v0` to any function that contains an
  `invoke`, and adds `exceptionDeclarations()` (`@_ZTIl`, the personality, `__cxa_*`) when
  `SublangWireFeatures.usesExceptions(module)` is true. That predicate is computed from the
  High opcodes (`SublangVocabulary.isExceptionOpcode`), not from the Low module.
- The `memcmp` symbol is a libc function, not a body in the provider text.

## 9. Verifier

`SublangLowVerifier.verify()` checks each function in id order and collects at most 16 findings.
The message format is:

```
SUBLANG-<code>: function <name> block <b> op <i>: <message>
```

Order of checks for one function:

1. entry block exists (L001); return type known (L002);
2. definitions: each value defined once and only if it exists (L001);
3. shape of every block: ends in a terminator, no terminator earlier, `stack.alloc` only in block 1 (L001);
4. if any finding so far, stop for this function;
5. dominance: unreachable blocks (L003); operand definitions must dominate uses; a use before its definition in the same block (L003); invoke results are usable only in the normal successor (L003);
6. per-operation checks: result type (L002), opcode-specific operand and attribute rules (L002, L004, L005).

Codes:

| Code | Category | Rules (all messages are produced by the verifier) |
|---|---|---|
| `SUBLANG-L001` | structure | no entry block; defines an unknown value; a value defined twice; a block without a terminator; a terminator before the end of a block; `stack.alloc` outside block 1; a use of an undefined value; a branch to a missing block; an unknown opcode |
| `SUBLANG-L002` | types and shapes | result type differs from the value table; wrong operand count; wrong operand type for arithmetic, comparison, memory, conversion, aggregate, branch and return operations; unknown or unsized `load`, `stack.alloc`, `const.zero` or `const.size` type; `const.i1` not 0 or 1; `cmp` predicate or type not allowed; `field.addr` index out of range; branch argument count or type differs from the destination parameters; unknown return type |
| `SUBLANG-L003` | dominance and reachability | block unreachable from block 1; use not dominated by its definition; use before definition in the same block; invoke result used where only the unwind edge reaches |
| `SUBLANG-L004` | calls and provider | `rt.call` symbol not in the provider; `call` or `invoke` naming no function; wrong argument count; argument type mismatch; result type mismatch |
| `SUBLANG-L005` | exceptions | `invoke` without two distinct targets; invoke successors with block parameters; unwind block not starting with `eh.catch`; `eh.catch` not the first operation of its block |

Verifier gaps, derived from reading the verifier:

- The `i64.` and `f64.` prefixes are accepted for any suffix; only the operand count and types are checked. The LLVM printer then uses the suffix as the instruction name (`i64.` ops) or inside `llvm.experimental.constrained.f<suffix>` (`f64.` ops). Lowering produces only `i64.add`, `i64.sub`, `i64.mul`, `i64.neg`, `f64.add`, `f64.sub`, `f64.mul` and `f64.div`.
- `sym.addr` names are not checked against any table.
- `stack.alloc` alignment is not checked.
- `const.str` globals, the sizes implied by layouts, and LLVM name uniqueness are not checked. Value hints are emitted as LLVM names, and the verifier does not check that hints are unique.

## 10. Plan, snapshot and target binding (L010 to L014)

The binding is checked at construction, in `SublangLowering`:

| Code | Condition | Effect |
|---|---|---|
| `SUBLANG-L010` | `!target.supported()` | the target name is not `native64-host-libc` or the pointer width is not 64; the module is not ready |
| `SUBLANG-L011` | `!plan.matches(module)` | the memory plan is for another snapshot object or another revision; the module is not ready |
| `SUBLANG-L012` | a function with `definition() != "body"` | an external function has no Low body; the module is not ready |
| `SUBLANG-L013` | a problem recorded by a `SublangLowerContext` | a lowering problem, for example an unsupported High opcode family, an unbound High value, or a `class.downcast` without a dispatch group; the module is not ready |
| `SUBLANG-L014` | CLI `dump-low` only | no Low dump is attached to the compilation |

`SublangMemoryPlan.matches(module)` is object identity plus the revision recorded when the plan
was made. The Low module records the source object, the source revision and the plan revision.
`SublangLowModule.loweredFrom(module)` is object identity plus revision. The dump header prints
`from revision=<n> plan-revision=<m>`.

`SublangLowering` lowers functions in id order only while there are no problems, so after the
first problem the remaining functions are not lowered. Context problems (L013) are collected per
function and copied into the module's problem list.

`SUBLANG-L013` lists the High families the dispatcher handles. Any other opcode is reported as
`opcode <name> is not lowered`. The handled families are: `const.string`, `string.*`, `list.*`,
`text.*`, `byte.*` (data); `bond.*`; `int.*`, `float.*`, `const.*`, `compare`, `number.equal`
(scalar); `branch`, `cond_branch`, `return`, `fail`, `call.direct`, `invoke`, `throw`, `resume`,
`call.virtual` (control); `record.*`, `field.*`, `scope.*`, `class.new`, `class.upcast`,
`class.downcast` (memory).

A single problem in any function makes the whole module use the legacy emitter, because the
Low route is all or nothing (`SublangCompiler.finish`).

## 11. Deterministic dump (`sublang dump-low`)

`SublangLowDump.render` produces the following layout:

```
low-module <name> target=<...> triple=<...> pointer=64 libc=host-libc unwinding=abort-only convention=c
from revision=<n> plan-revision=<m>
func @<name>(v<id>:<type>, ...) -> <retType> origin=<highFunctionId>[ attrs=<text>]
  b<k>(v<id>:<type>, ...)
    [v<id>:<type> = ]<opcode>[ <typeText>][ @<text>][ v<operand>]...[ #<immediate>,<index>][ ->b<target>]...[ true-args=<n>][ ; op<originId>]
```

Rules, from `SublangLowDump`:

- Functions and blocks are printed in id order; operations in block order. There are no addresses.
- `#<immediate>,<index>` is printed only for opcodes that start with `const.`, and for `stack.alloc`, `field.addr`, `agg.*` and `call`. It is not printed for `invoke`, `rt.call`, `elem.addr`, `byte.addr` or the others.
- `true-args=` is printed for `cond_br` only.
- `; op<n>` is printed when the operation has a High origin.
- Value hints are not printed. The callee index of `invoke` is not printed, so two modules that differ only in that index render equally. The dump is a diagnostic rendering, not a round-trip format.

An example line shape is the template above; this doc does not show captured output.

## 12. What is not Low yet

The following parts of the emitted LLVM text are not produced from Low operations.

| Part | Where it comes from | Note |
|---|---|---|
| runtime bodies (`sublang.add` and friends, flow, shard, bond, pool, list, text, string runtime) | `SublangLlvmEmitter.provider`, which calls the `definitions()` of the legacy LLVM runtime classes | provider text is appended verbatim by `emitLow` |
| `%t<id>` type definitions, list type, shard and bond root types | `SublangLlvmTypes.definitions`, `SublangLlvmListRuntime`, `SublangLlvmShardRuntime`, `SublangLlvmBondRuntime` | the Low layout is computed separately (section 5) |
| drop visitors `sublang.drop.t<N>` | `SublangLlvmDropEmitter.definitions` and `SublangLlvmLists.visitor` | referenced from Low through `sym.addr` |
| Bond trace routines `sublang.bond.trace.t<N>` | `SublangLlvmBonds` | referenced from Low through `sym.addr` |
| Bond trial and cache runtime | `SublangLlvmBondTrial`, `SublangLlvmBondCache` | provider text |
| string globals `@sublang.str.<High op id>` | `SublangLlvmStrings.definitions` (`llvmdata/SublangLlvmStrings.ems`) | referenced by `const.str` through `text` = `sublang.str.<id>` |
| module entry function | `SublangLlvmEmitter.entry` | appended after the Low functions by `emitLow` |

So the Low route covers the function bodies. The provider text and the generated visitors are
still produced by the legacy host-libc provider. The provider header comment (`; Sublang initial
native LLVM slice`) is the only comment in that text.

## 13. Limitations

1. Only `native64-host-libc` (section 6) exists. The triple and the layout rules are fixed for that target.
2. Any unsupported function, or any verifier finding, sends the whole module to the legacy emitter, except for the extension-operation case that fails with `SUBLANG-B009`.
3. The verifier gaps listed in section 9 apply. A missing check does not mean the operation is wrong; the lowering is the authority for those choices.
4. The layout discrepancies in section 5.3 are not covered by the verifier.
5. The dump omits value hints and the callee index of `invoke`; it is not a serialization format.
6. The `call.virtual` dispatch chain aborts for an unknown tag. When a group has no entries, the join block of the chain has no predecessor, so the verifier reports it as unreachable (L003), and the module falls back to the legacy emitter. `UNVERIFIED:` this path was derived by reading `SublangLowerControl.chain`; it was not executed.
7. Legacy fallback remains possible for the core subset; inspect the plan's lowering route rather than assuming every accepted input used Low IR.
8. The Low verifier and binding harness (`harness/pass/SublangLowChecks.ems`) passed in the October 11 hardening run. Native Bond/inline examples also used verified Low IR. Other source-only observations in this document are not additional runtime evidence.
