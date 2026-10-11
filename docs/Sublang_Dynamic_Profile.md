# Sublang Dynamic Profile (dyn-v1 draft)

Status: design specification, 2026-10-11. Nothing in this document is implemented
unless the "Verified today" table says so. The profile is a small, closed subset for
Dynamic AOT (roadmap section 6). It is not Python or JavaScript compatibility.

Labels used throughout:

- **Specified:** a profile rule. It can be lowered today with operations listed in the
  "Verified today" table.
- **Needs new IR ops:** requires an operation that is absent from
  `src/sublang/vocabulary/SublangVocabulary.ems` (`isKnownOpcode` and `producesValue`).
- **Needs new analysis:** requires a checker or proof that does not exist yet.
- **Out of scope:** not part of dyn-v1.
- **UNVERIFIED:** a claim this document could not confirm from source or docs.

Related: [IR contracts](Sublang_IR_Contracts.md) section 8, [HyperAlloc IR](HyperAlloc_IR.md),
[Native slice](Sublang_Native_Slice.md), [IR guide](Sublang_IR_Guide.md), and the
illustrative [dynamic example](../examples/ir/v0.4/07-dynamic.sublang-ir), which is
not accepted input.

## 1. Verified today

Each row was checked in source or in the cited documentation during this pass.

| Capability | Status | Where |
| --- | --- | --- |
| Type kinds: Void, Bool, Int, Float, Record, Class, Ref, String, List, Bond | Exists. No Dynamic, tag or box kind. | `vocabulary/SublangVocabulary.ems` `isKnownTypeKind` |
| Opcodes: const.bool/int/float, int.add/sub/mul/div/rem/neg (trap or wrap modes), float.add/sub/mul/div (rne), compare, record.make/get/with | Exists | `isKnownOpcode`, `isIntOpcode`, `isFloatOpcode` |
| Compare predicates: int eq/ne/lt/le/gt/ge; float ordered and unordered predicates | Exists. `compare` accepts only Int, Bool or Ref operands, and both operands must have the same type. | `SublangArithmeticChecks.ems` lines 141-181 |
| Float compare requires an explicit predicate; generic `lt` is rejected for Float | Exists | `SublangArithmeticChecks.ems` line 165; guide section 6 |
| String ops: const.string, string.length, string.byte, string.equal (static only, byte based) | Exists. No concatenation, no heap String. | `SublangOperationBuilder.ems`; `HyperAlloc_IR.md` |
| List ops: list.new, push, length, get, borrow, clear. List element kinds: primitive, String, Record, Class. | Exists. **No element set or replace op.** | `isKnownOpcode`; `SublangTypeChecks.ems` line 53 |
| Field types: primitive and String for any owner; Ref and Bond only for Class owners | Exists | `SublangTypeChecks.ems` lines 158-166 |
| Value records with primitive fields: construction, read, functional update; by-value params and returns | Exists (native slice doc) | `Sublang_Native_Slice.md` |
| Direct calls only (`call.direct`). No indirect call or closure opcode. | Exists | `isKnownOpcode`; `SublangOperationBuilder.ems` `callDirect` |
| Branches, conditional branches, block parameters | Exists. Reference block arguments are documented as unsupported. | `Sublang_Native_Slice.md` |
| `fail` terminator and `failWith`; the native lowering calls `abort` then `unreachable` | Exists | `backend/llvm/SublangLlvmControl.ems` line 9 |
| Failure bindings accepted by the native gate: `unbound` or `libc.abort`; other bindings are rejected | Exists | `backend/SublangBackendGate.ems` line 32 |
| Integer trap: the native code aborts for overflow and for division by zero or MIN/-1 alike | Exists | `backend/llvm/SublangLlvmRuntime.ems` (`sublang.div.trap`) |
| Semantic profile: startup profile only (i64 signed, f64 IEEE rne, abort, unwinding none) | Exists | `semantics/SublangSemanticProfile.ems`; `SublangVocabulary.ems` |
| Exceptions, unwinding, catch and cleanup-on-throw | Not implemented. `A throwing record does not implement exception handling.` | `Sublang_IR_Guide.md` section 6 |
| Explain: per-object choice strings (Folded, Local, Pool, Shard, Root, ScopeOwned, Heap) and blocker strings | Exists | `hyperalloc/SublangFunctionMemoryPlan.ems`; `hyperalloc/SublangObjectUses.ems` |
| Blocker strings used today, including "reference parameter can connect to an external graph" (line 34), "collection elements require independent ownership storage" (line 75), "owned call or return may leave the region" (line 91) | Exists | `SublangObjectUses.ems` |
| Diagnostic records carry a code, dimension, span, entity and blocker list | Exists | `diagnostics/SublangDiagnostic.ems` |
| Numeric conversion ops (int to float, float to int, bit casts), float negate, dynamic string or concat | **Absent.** `grep` for sitofp, fptosi, convert and promot in `src/sublang` finds nothing. | source search |
| Tag, box, unbox, type-test, property-by-name, closure or indirect-call ops | **Absent** | `isKnownOpcode` |
| Backend sandbox | Runs through Docker (`scripts/sublang-backend-sandbox.sh` line 9, `scripts/check-sandbox.sh`). It has 30 spec entries. This pass did not run it. | scripts |

Consequence: the profile can be lowered on the existing set of operations for most rules.
A few rules need new operations (section 15).

## 2. Value universe

| Type | Values | Notes |
| --- | --- | --- |
| Nil | one value | Tag only. |
| Bool | false, true | |
| Int | signed i64 | Every arithmetic result is checked. Overflow aborts. No promotion to Float. |
| Float | IEEE binary64 | Round to nearest, ties to even. NaN and signed zero are observable through the rules below. |
| String | byte sequence | Indices and lengths count bytes. No code point semantics. |
| Object | fixed-shape property record | Shape is closed and known at compile time. No property addition after creation. |
| List | growable sequence of dyn values | Homogeneous only in the sense that every element is a DynValue. |
| Closure | (body id, captured environment) | Closed set of bodies only (section 11). |

Out of scope: classes and inheritance, prototypes, getters and setters, property
addition or deletion, bigints, code points, maps and sets, generators, async, eval,
reflection, threads, exceptions, weak references, finalizers, JIT and deoptimization.

## 3. Tagged representation

### 3.1 Value record

```text
record DynValue { tag: Int; a: Int; b: Int; f: Float }
```

Tags are constants of type Int:

| Tag | Name | Payload |
| --- | --- | --- |
| 0 | Nil | a=0, b=0, f=0.0 |
| 1 | Bool | a is 0 or 1 |
| 2 | Int | a is the value |
| 3 | Float | f is the value. Floats are stored in their own field, so no bit cast is needed. |
| 4 | String | a = byte offset in `bytes` pool, b = byte length. |
| 5 | Object | a = base index in `slots` pool, b = shape id. |
| 6 | List | a = index in `headers` pool. |
| 7 | Closure | a = body id (closed set), b = environment base in `slots` pool, or -1 if empty. |

Status: **Specified.** Record construction and reads use `record.make`, `record.get`
and `record.with`, which exist today. All four fields are primitive, so the record passes
the field-type rule (`SublangTypeChecks.ems` lines 158-166).

Immediate payloads are the record itself. Pointer tagging or NaN boxing would need bit
casts between Int and Float, which do not exist (**Needs new IR ops**, out of scope for dyn-v1).

### 3.2 Pools

A dynamic runtime instance owns three pools. Each is created by `list.new` in one runtime
scope that is opened at function entry and closed on every return.

| Pool | Element type | Holds |
| --- | --- | --- |
| `bytes` | Int (one byte per element, 0..255) | String contents, appended by push |
| `slots` | Record DynValue | Object slots, closure environments and list elements |
| `headers` | Record ListHeader `{ offset: Int; length: Int; capacity: Int }` | List headers |

Status: **Specified** using existing `list.new`, `list.push`, `list.get`, `list.length`
and `list.clear` on primitive and Record elements. Each pool is a bump region. Objects and
lists never move inside a pool except when a list grows (section 7.3).

Element type checks: Record elements are accepted (`SublangTypeChecks.ems` line 53).

Caveats:

- **UNVERIFIED:** a DynValue record as a block parameter across branches or loops. If it is
  not supported, pass the three primitive components as separate block parameters.
- **Needs new IR ops:** `list.set` (checked index, value). Object property writes and list
  element writes depend on it.
- One byte per Int element is wasteful but correct. A byte-buffer op is optional
  (**Needs new IR ops**, not required by dyn-v1).

### 3.3 Why handles are offsets

Handles are integer offsets, not pointers. Pool growth inside `list.push` may reallocate
the backing buffer. Offsets stay valid after reallocation. Element views and borrows of a
list are invalidated by push (`Sublang_Native_Slice.md`, `HyperAlloc_IR.md`), so the
lowering never holds a view across a push. It reads with `list.get`, which copies.

## 4. Numeric promotion

| Left | Right | Result | Rule | Status |
| --- | --- | --- | --- | --- |
| Int | Int | Int | +, -, * are checked (`int.add`, `int.sub`, `int.mul`, trap mode). Overflow aborts with dyn.overflow. | Specified |
| Int | Int | Int | `/` truncates toward zero (`int.div`, trap mode). Zero divisor aborts with dyn.div_zero. MIN / -1 aborts with dyn.overflow. | Specified |
| Int | Int | Int | `%` is the truncated remainder with the sign of the dividend (`int.rem`, trap mode). Zero divisor aborts. | Specified |
| Float | Float | Float | +, -, *, / are IEEE binary64 with round to nearest, ties to even (`float.*` with rne). Division by 0.0 yields IEEE infinity or NaN and does not abort. | Specified. UNVERIFIED: backend result for float division by zero (constrained `fdiv` is expected). |
| Int | Float or Float | Int | Float | Int is converted to f64 with rne, then the Float rule applies. | Needs new IR ops: `numeric.int_to_float`. |
| Any other pair | | | abort dyn.type_error | Specified |

Decisions in this table that differ from Python or JavaScript, recorded so they are not
mistaken for compatibility:

- Integer `/` truncates. It is not floor division, and it is not a float result.
- Overflow never promotes to Float or to a big integer. It aborts.
- Float division by zero follows IEEE and does not raise an exception.
- Bool is not an Int in arithmetic. There is no implicit coercion.
- No implicit Float to Int conversion exists in dyn-v1.

Unary operators: `-x` on Int uses `int.neg` (trap, so MIN aborts). `-x` on Float is lowered
as `float.mul(x, -1.0)`. This is exact for every input (including signed zero), and the NaN
sign is not observable in dyn-v1. Status: **Specified**.

String concatenation `+` on String and String is **Specified** as a lowering that copies
bytes into `bytes` with `list.push`. The result is a heap String (section 10).

Ordering operators on Int and Float use the existing predicates. Float uses ordered
predicates (`olt`, `ole`, `ogt`, `oge`), so NaN compares false. Ordering on String is the
unsigned byte-lexicographic order, lowered as a loop. Ordering on mixed Int and Float needs
`numeric.int_to_float`. Other ordering pairs abort dyn.type_error.

## 5. Truthiness

Used by `if`, `while`, `!` and short-circuit operators.

| Value | Truthy when | Lowering (existing ops) |
| --- | --- | --- |
| Nil | never | constant false |
| Bool | a != 0 | compare eq on a with 0 |
| Int | a != 0 | compare ne on a with 0 |
| Float | f is not zero. Both +0.0 and -0.0 are falsy. NaN is truthy. | `compare une(f, 0.0)`. `une` is true for NaN and for non-zero values, and false for both zeros. |
| String | b != 0 | compare ne on b with 0 |
| List | header length != 0 | load header, then compare ne |
| Object | always | constant true |
| Closure | always | constant true |

Status: **Specified**. The tag dispatch uses `compare` and `cond_branch`. Floats need only
`une`, which exists.

## 6. Equality

`==` and `!=` are total. They never abort. They return Bool.

| Pair | Rule | Status |
| --- | --- | --- |
| Nil, Nil | true | Specified |
| Bool, Bool | equal values | Specified |
| Int, Int | exact equality | Specified (`compare eq`) |
| Float, Float | IEEE: `oeq`. NaN is not equal to NaN. -0.0 equals +0.0. | Specified |
| String, String | equal byte length and equal bytes. Static and heap Strings compare by content. | Specified. Lowered as a loop over `bytes`. |
| Object, Object | same runtime, same base and same shape id (identity of the slot region) | Specified |
| List, List | same header index | Specified |
| Closure, Closure | same body id and same environment base | Specified |
| Int, Float | exact mathematical equality: a Float equals an Int only when it is integral, in i64 range, and equal after exact conversion | **Needs new IR ops**: an exact float-to-int conversion (`float.to_int_exact`). Until it exists, the frontend must not emit this comparison. |
| Any other mixed-tag pair | false | Specified |

Identity rule: distinct live objects never share a base, because pools are bump regions
and nothing is reused before the owning scope closes. This property is **Specified**
by the allocation rule in section 7.3, not by a proof.

## 7. Properties and indexes

### 7.1 Shapes

A shape is a compile-time table: an id, an ordered list of property names, and one slot
index for each name. Names are unique within a shape. Shapes form a closed set for the
module.

Object creation with shape S reserves `count(S)` slots at the end of `slots` and
initializes them to Nil. Reads of an uninitialized slot are impossible because every
slot starts as Nil.

### 7.2 Property access

| Form | Behaviour | Status |
| --- | --- | --- |
| `o.name`, static name | If the tag is not Object, abort dyn.type_error. For each shape S that contains `name`, branch on `b == S.id` and read `list.get(slots, a + slot)`. If no shape contains the name, abort dyn.key_error. | Specified (`compare`, `cond_branch`, `list.get`) |
| `o.name = v`, static name | Same dispatch, then `list.set(slots, a + slot, v)`. Writing a name that is not in the shape aborts dyn.key_error. Properties are never added. | Needs new IR ops: `list.set` |
| `o[k]`, String key k | Compare k byte-wise with each closed name, then dispatch as above. No match aborts dyn.key_error. | Specified (lowering) |
| Other receiver | abort dyn.type_error | Specified |

### 7.3 Lists and index access

A List value's `a` is an index into `headers`. The header gives `offset`, `length` and
`capacity`. Elements live at `slots[offset .. offset + length)`.

| Form | Behaviour | Status |
| --- | --- | --- |
| `len(x)` on String | b of the String value | Specified |
| `len(x)` on List | header length | Specified |
| `l[i]`, read | i must be Int. If i < 0 or i >= length, abort dyn.index_error. Otherwise `list.get(slots, offset + i)`. | Specified |
| `l[i] = v`, write | Same bounds check, then `list.set`. | Needs new IR ops: `list.set` |
| `l.push(v)` | If length equals capacity, allocate a new region of twice the capacity at the end of `slots`, copy with `list.get` and `list.push`, then replace the header with `list.set(headers, ...)`. Append v. | Needs new IR ops: `list.set` on `headers` |
| `s[i]`, String | i must be Int. If i is outside [0, length), abort dyn.index_error. The result is an Int in 0..255. Indices count bytes. | Specified (lowering over `bytes`) |
| `o[i]` on Object with Int i | abort dyn.type_error | Specified |

Negative indices do not wrap. Index errors always abort.

## 8. Failure semantics

### 8.1 Model

- Every dyn-v1 failure is a FailureAction with behaviour `abort`, binding `libc.abort`
  (or `unbound`), signature `noreturn void()`, `continues=false` and unwinding `none`.
  The native gate accepts only these bindings (`SublangBackendGate.ems` line 32).
- Named failures:

| Name | Raised by |
| --- | --- |
| dyn.type_error | operand or receiver tag does not match the operation, or unboxing a wrong tag |
| dyn.overflow | Int overflow in `+ - * neg`, or MIN / -1 |
| dyn.div_zero | Int `/` or `%` with a zero divisor |
| dyn.key_error | property name not in any relevant shape |
| dyn.index_error | index out of range, including negative |
| dyn.internal | closure body id outside the closed set (should be unreachable) |

- Names are verifier and explain metadata. The native backend does not distinguish them:
  `sublang.div.trap` aborts for both zero division and MIN / -1, and each failure site
  is a plain abort. The observable result of every failure is SIGABRT with no result.
  Status: **Specified**.

### 8.2 Abort versus requested exceptions

Roadmap section 6 requires that abort never silently replace requested exceptions.
Therefore:

- dyn-v1 has no `throw`, `try`, `catch`, `finally` or exception-like failure. Its unwind
  model is `none`, consistent with `startupUnwindingModel()`.
- Source constructs that request catchable exceptions (for example a TypeError handler)
  are rejected by the frontend or by verification with an unsupported-feature diagnostic.
  They are never lowered to dyn.type_error.
- dyn.type_error is an abort because dyn-v1 defines it as one. It is not a stand-in for a
  catchable exception. A language that needs catchable errors is out of scope until the
  exception model in `Sublang_IR_Contracts.md` section 4 is implemented.
- Abort gives no cleanup guarantee (`Sublang_IR_Guide.md` section 6). Programs must not
  depend on observable output produced by cleanup after a failure.

### 8.3 Explain visibility

Each failure site should be reported with its failure name and the operation it guards.
**UNVERIFIED:** the current diagnostic path does not emit failure-site records. A new
diagnostic record would carry the failure name, the guarded operation and the blocker
list. `SublangDiagnostic.ems` supports that shape.

## 9. Box, unbox and type-test contracts

Box, unbox and test are contracts over the DynValue record. Each one is also expressible
as a lowering with existing ops.

| Operation | Contract | Lowering today |
| --- | --- | --- |
| `box.nil()` | DynValue with tag 0, a=0, b=0, f=0.0 | `record.make` |
| `box.bool(x: Bool)` | tag 1, a = 1 if x else 0 | `cond_branch` into two `record.make` blocks, or into one block with a block parameter. Both are **Specified**. |
| `box.int(x: Int)` | tag 2, a = x | `record.make` |
| `box.float(x: Float)` | tag 3, f = x | `record.make` |
| `box.string` | Only for heap String: see section 10 | lowering over `bytes` |
| `test(v, t) -> Bool` | v.tag == t | `record.get`, `compare eq` |
| `unbox.int(v) -> Int` | If tag != 2, fail dyn.type_error. Else return a. | `record.get`, `compare`, `cond_branch` to `fail` |
| `unbox.float(v) -> Float` | If tag != 3, fail dyn.type_error. Else return f. | same |
| `unbox.bool(v) -> Bool` | If tag != 1, fail. Else return a != 0. | same |

`unbox` never reinterprets bits. A wrong tag always fails.

Optional fused opcodes (`dyn.box.*`, `dyn.unbox.*`, `dyn.test`) would improve Explain
identity and reduce IR size. They are **Needs new IR ops**. Each would need entries in
`isKnownOpcode`, `producesValue` and `refMeaning`, plus checks and backend emission
(`SublangVocabulary.ems`, `checks/operation`, `backend/llvm`). They are not required for
correctness.

## 10. Heap-backed values and ownership across allocating calls

### 10.1 What is heap-backed

A heap value's content lives in a pool, not in the record:

- Heap String: bytes at `bytes[a .. a+b)`.
- Object: slots at `slots[a .. a+count(shape))`.
- List: elements in `slots`, with the header in `headers`.
- Closure environment: slots in `slots`.

The pools are the only allocation sites. Every allocation is a bump at the pool end, or a
list growth. Each pool is freed as a whole when its runtime scope closes (`scope.end`).

### 10.2 Lifetime contract

1. A heap-tagged DynValue (tags 4 to 7 with a non-empty payload) is valid only while the
   runtime scope that owns its pools is open.
2. Handles are offsets. Pool growth from push does not invalidate them.
3. An allocating callee takes the pools as `borrow_write` parameters. It returns a
   DynValue that refers to those pools. It must not return a heap-tagged value whose pool
   the caller does not own.
4. At scope end, all pools are released. A heap DynValue held after that point is dangling.
   Status of rule 4: **Needs new analysis**. The native lifetime checker does not know that
   a DynValue's handle refers to a pool, so the rule is a property of the lowering, checked
   by the sandbox (ASan and LSan) and by tests, not by the verifier.

Status of the pattern: **Specified**. The existing sandbox has borrowed-call and
owned-transfer cases (`Sublang_Native_Slice.md`). A List passed as `borrow_write` to a
direct call is **UNVERIFIED**. `SublangBackendGate.ems` line 63 requires a borrow or owned
passing mode for Ref parameters, which is consistent with it, but no fixture was found for
List parameters.

### 10.3 Heap String example

`s = "ab" + "cd"`: copy 2 bytes and 2 bytes into `bytes`, then return
`box.string(a=start, b=4)`. This value is alive until scope end. A later allocating call
such as `grow(bytes)`, which pushes many bytes and reallocates, leaves `s` readable,
because `s` is only an offset. Reading `s` after the call copies bytes with `list.get`.

## 11. Closures and captures

### 11.1 Scope

Closures are closed-world only. The module declares a finite set of body functions
B0 to Bk. A closure literal lowers to `DynValue { tag=7, a=bodyId, b=envBase }`. Calls
use a dispatch over bodyId.

Open-world closures, where the callee is a runtime table entry or code from an external
provider, are **Out of scope**. There is no indirect-call opcode (`isKnownOpcode`).

### 11.2 Capture contract

- Capture is by value at closure creation. Each captured DynValue is copied into the
  environment region in `slots`. The number of captures for each body is known at compile
  time.
- A primitive capture (Nil, Bool, Int, Float) is an independent copy. This matches the
  `extended-ir.md` section 7 example, which yields 42.
- A heap capture copies the handle, not the content. An Object or List capture still
  refers to the same slots, so it is shared, not independent. String captures are
  immutable, so sharing is not observable. The difference from a value copy is intended.
- Mutable captured variables are out of scope. They would need a cell in `slots` and
  `list.set`.

### 11.3 Call lowering

`closure.call(f, args)` lowers to a chain: for each body id k, `cond_branch(f.a == k)` to
`call.direct Bk(env, args..)`. The fall-through path is `fail dyn.internal`.
Status: **Specified** (`compare`, `cond_branch`, `call.direct`, `fail`).

Each body takes the environment as a DynValue value parameter. It also takes the pools as
`borrow_write` parameters, as in section 10.2.

### 11.4 Escape

A closure whose environment refers to pools that a caller will release must not escape the
scope that owns those pools. A closure with primitive-only captures has no pool reference
and may be returned.

Status: **Needs new analysis**. The explain blocker in section 12 names the escape. The
native planner blocks Shard for owned calls and returns (`SublangObjectUses.ems` line 91),
but no existing analysis models closure environments.

## 12. Effects and alias blocker for Explain

Requirement: at least one effect or alias blocker is shown by Explain.

Demonstration program (D6 in section 14):

1. A pool (`slots`) is passed as `borrow_write` to a declared external function. The
   external function's effects are unknown (`declareExternal`), and the frontend
   noescape flag is ignored by the native gate.
2. The planner's existing blocker for that case is:
   `reference parameter can connect to an external graph`
   (`SublangObjectUses.ems` line 34). It blocks Shard for the pool. The planner falls
   back to Root or ScopeOwned.
3. The same pool is used with list operations. The existing blocker
   `collection elements require independent ownership storage` (line 75) applies.

The required explain output is therefore the blocker string above, the object identity
(pool or slot region), and the safe fallback that the planner chose.

**UNVERIFIED:** whether the exact blocker text reaches `explainMemory()` for pools of
DynValue records. `SublangFunctionMemoryPlan.ems` lines 80-117 assemble the choice
strings, but this pass did not trace a case where a list pool is the subject.

A separate alias blocker is proposed but **not implemented**. `bytes`, `slots` and
`headers` may be one LocationId, or each other's alias, if they share a region. Writes
through `list.set` on `slots` may then alias an Object's slot region. Explain should report
MayAlias with both locations and the fact origin. Source search found no alias-blocker
text in the memory plan. `SublangAliasFact.ems` exists, so this could be built on it.
**Needs new analysis.**

## 13. Effects per operation

Areas follow `SublangVocabulary.effectAreas()`. Values follow `isEffectValue`.

| Operation | allocation | escape | failure | memory-read | memory-write | control |
| --- | --- | --- | --- | --- | --- | --- |
| Int/Float arithmetic | none | none | may (trap sites) | none | none | returns |
| compare, truthiness, equality | none | none | none | none | none | returns |
| Concatenation, push, growth | may | none | may | may | may | returns |
| Property or index read | none | none | may | may | none | returns |
| Property or index write (`list.set`) | none | none | may | may | may | returns |
| Call to a closed body | none | none | may | may | may | returns |
| Call to a declared external | may | unknown | may | unknown | unknown | unknown |
| Scope end (pool release) | may (free) | none | none | none | may | returns |

Status: **Specified** as the declared profile summary. Its provenance is `declared` for
runtime helpers and `proven` only after a checker establishes it. The verifier does not
yet derive these facts for dyn code.

## 14. Incremental implementation plan and acceptance tests

Each acceptance test is one entry in the spec list of
`scripts/sublang-backend-sandbox.sh` (30 entries today) with a builder in
`src/SublangBackendSmoke.ems`. It returns an Int checksum, as the existing entries do.
Each case runs in both Flow-off and Flow-on variants, and LLVM and native results must
match. Failure cases expect SIGABRT with no result.

**Caveat:** the sandbox script runs under Docker. This document does not run it. The tests
below are the acceptance criteria for a future run.

### D1: tags, checked Int, truthiness (no new ops)

| Test | Program | Expected |
| --- | --- | --- |
| dyn-int-arith | box(2), box(3), unbox(add) | 5 |
| dyn-int-trunc-div | unbox(box(-7) / box(2)) | -3 (truncation, not -4) |
| dyn-int-rem | unbox(box(-7) % box(2)) | -1 |
| dyn-truthy-table | count truthy among [Nil, false, true, 0, 1, -1] | 3 |
| dyn-unbox-type-error | unbox.int(box.bool(true)) | SIGABRT, no result |
| dyn-int-overflow | box(MAX) + box(1) | SIGABRT, no result |
| dyn-int-div-zero | box(7) / box(0) | SIGABRT, no result |

### D2: promotion and Float rules (needs `numeric.int_to_float`)

| Test | Program | Expected |
| --- | --- | --- |
| dyn-promote-add | Int 1 + Float 2.5, compared oeq with the bits of 3.5 (0x400C000000000000) | 1 |
| dyn-float-div-zero | 1.0 / 0.0 compared oeq with +inf (0x7FF0000000000000) | 1 (UNVERIFIED backend result, see section 4) |
| dyn-negzero-eq | 0.0 == -0.0 under oeq | 1 |
| dyn-nan-eq | NaN == NaN under oeq | 0 |
| dyn-truthy-float | count truthy among [0.0, -0.0, 0.5, NaN] | 2 |

### D3: heap String (no new ops)

| Test | Program | Expected |
| --- | --- | --- |
| dyn-str-concat-index | "ab" + "cd", then s[2] | 99 |
| dyn-str-realloc-survives | s = "hello"; a helper pushes 100000 bytes (forcing growth); then sum the bytes of s | 532 |
| dyn-str-eq | "abc" == ("a" + "bc") and "abc" == "abd" | 10 (1 for the first, 0 for the second, combined as 10 * first + second) |
| dyn-str-index-range | s[4] for a 4-byte String | SIGABRT, no result |

The sum for the realloc test is 104 + 101 + 108 + 108 + 111 = 532. The `bytes` pool
reallocates during the helper call. The sandbox's ASan and LSan configuration for these
memory boundaries should show no leak (**UNVERIFIED** for this new case, because it
depends on the script's sanitizer setup).

### D4: objects and lists (needs `list.set`)

| Test | Program | Expected |
| --- | --- | --- |
| dyn-object-prop | o = {x: 40}; o.x = o.x + 2; return o.x | 42 |
| dyn-missing-key | o.z where z is not in the shape | SIGABRT, no result |
| dyn-list-sum | l = [1, 2, 3]; sum of l[0..2] | 6 |
| dyn-list-bounds | l[3], and l[-1] | SIGABRT, no result (each case separately) |
| dyn-list-growth-objects | push 1000 objects with x = 0..999, then sum o.x | 499500 |

### D5: closures (no new ops)

| Test | Program | Expected |
| --- | --- | --- |
| dyn-closure-capture | base = box(40) captured by value; body(a) = base + a; call with 2 | 42 |
| dyn-closure-dispatch | two closed bodies; call id 1 with 21, where body 1 doubles its argument | 42 |
| dyn-closure-escape-rejected | a closure with a heap capture is returned from its owning scope | rejected by verification (negative test). **Needs new analysis.** |

### D6: Explain and negative tests

| Test | Expected |
| --- | --- |
| dyn-explain-external | `explainMemory()` contains `reference parameter can connect to an external graph` for the pool passed to a declared external. The sandbox does not currently assert explain text, so this is **UNVERIFIED** until a check is added. |
| dyn-reject-indirect | A module using an unknown opcode such as `call.indirect` is rejected. The vocabulary rejects unknown tags. |
| dyn-reject-catch | A frontend request for catchable exceptions produces an unsupported-feature diagnostic, not an abort. |

Stage order: D1 first, then D3 after D2 (D3 uses only existing ops), then D4 after
`list.set` exists, then D5, then D6. D2 depends on `numeric.int_to_float`. The mixed
equality in section 6 depends on `float.to_int_exact`. Neither dependency blocks D1,
D3 or D5.

## 15. Status summary

### Specified (lowers to existing ops)

- Value record `DynValue` with four primitive fields, and the tags in section 3.1.
- Pools as `list.new`/`push`/`get`/`length` over Int, Record and bump offsets.
- Int checked arithmetic, truncating division, truncated remainder, abort names.
- Float IEEE rules with explicit ordered predicates.
- Truthiness table, equality table except mixed Int/Float.
- Box, unbox and test as lowerings (section 9).
- Heap String concatenation and byte indexing, copied into `bytes`.
- Closed-world closures with by-value captures and a dispatch chain.
- Abort-only failure model with the named failures.

### Needs new IR ops

| Op | Used by | Reason |
| --- | --- | --- |
| `list.set(list, index, value)` | object and list writes, growth | No element write exists (`isKnownOpcode`). |
| `numeric.int_to_float` | Int/Float promotion, mixed ordering | No int to float conversion exists. |
| `float.to_int_exact` | mixed Int/Float equality | No float to int conversion exists. |
| `dyn.box.*`, `dyn.unbox.*`, `dyn.test` (optional) | Explain identity, IR size | Lowerings suffice for correctness. |
| byte-buffer ops (optional) | heap String storage | `List<Int>` works with one Int per byte. |

Each new op needs entries in `SublangVocabulary.ems` (`isKnownOpcode`, `producesValue`,
`refMeaning`), checks under `src/sublang/checks/operation`, backend emission under
`src/sublang/backend/llvm`, and the Wire v2 representation.
**UNVERIFIED:** whether Wire v2 needs per-opcode table changes or handles new opcodes
generically.

### Needs new analysis

- Handle provenance: a checker that knows a heap DynValue refers to a pool and that the
  pool outlives its uses (section 10.2, rule 4).
- Closure escape of heap environments (section 11.4).
- Alias facts for shared pools (section 12).

### Out of scope

Python or JavaScript compatibility; bigints; code points; getters and setters; prototypes;
property addition and deletion; open-world closures; `call.indirect`; exceptions, `try`,
`catch` and `finally`; generators and async; threads; GC, cycle collection, weak references
and finalizers. Pools are reclaimed only at scope end, so memory use is bounded by the scope
but not by live data. JIT and deoptimization are separate work.

## 16. Open items

- UNVERIFIED: record-typed block parameters (section 3.2).
- UNVERIFIED: List passed as `borrow_write` to a direct call (section 10.2).
- UNVERIFIED: IEEE result of float division by zero in the native backend (section 4).
- UNVERIFIED: planner choice and explain text for DynValue pools (section 12).
- UNVERIFIED: the "Ref block arguments unsupported" claim is taken from
  `Sublang_Native_Slice.md`. The rejection path was not located in source during this pass.
- UNVERIFIED: String-typed record fields are accepted by the type checker
  (`SublangTypeChecks.ems` line 159), but backend lowering was not checked. dyn-v1 avoids
  them.
- Decision (profile choice, not a claim): truncating integer division, no overflow
  promotion, IEEE float division by zero, NaN truthy, Object and closure always truthy.

## Implementation status

This section records what the implemented dyn-v1 library does and what remains open. The
sections above are the design draft. Where the implementation differs from the draft, the
difference is listed here. The acceptance programs D1 to D6 named below are the ones in
`src/sublang/harness/pass/SublangDynamicFixtures.ems`, not the draft's section 14 table.
Library reference: [Sublang Dynamic Library](Sublang_Dynamic_Library.md).

Implemented and verified by `scripts/sublang-dynamic-sandbox.sh`:

- Tags 0 nil, 1 bool, 2 int, 3 float, 4 text. The value is a class `Dyn { tag, num, real, text }`
  with `text: owned Ref<List<Byte>>`, not the pool record of section 3. Values are owned heap
  objects, so Flow scope, ownership and drop rules apply.
- Constructors `dyn_nil`, `dyn_bool`, `dyn_int`, `dyn_float`, `dyn_text` (copies the bytes).
- `dyn_truthy`. Float truthiness is "not zero and not NaN", so NaN is falsy. This differs from
  section 5, which made NaN truthy.
- `dyn_add` for Int+Int (checked trap), Int+Float and Float+Int (exact promotion with
  `int.to_float`, IEEE rne), Float+Float (rne), and Text+Text (concatenation). Other pairs abort.
- `dyn_equal` for same-tag values and exact Int/Float equality with `number.equal`. Equality
  between mixed tags other than Int and Float is false. No new op is needed, which differs from
  the draft's section 6.
- `dyn_to_int`: int returns `num`; float uses the exact `float.to_int`. Other tags abort.
- Failures `dyn.type_error`, `dyn.overflow` and `dyn.internal` abort (SIGABRT, no output).
- No Bool-to-Int coercion. A bool becomes a tag-1 value with `num` 0 or 1 through a branch.

Not implemented or unspecified:

- Objects and properties (sections 2, 7.1, 7.2): no object tag, no shapes, no property access.
- Lists as dyn values (section 7.3): no list tag, no index access, no bounds errors.
- Ordering operators, and the `-`, `*`, `/`, `%` operators on dyn values (section 4). Only `+`
  is implemented, and ordering on Strings is absent.
- String slicing views and indexing: text values are copies, with no slices and no `s[i]`.
- General closures (section 11): the library has no closure construct. The D5 program shows a
  closed two-body dispatch with an owned capture in fixture code only. Open-world callees, mutable
  captures and sharing of heap captures are unspecified.
- Shared or cyclic values (Bond graphs): not modeled. Text values are not shared.
- Explain for pools and the external blocker in section 12: not asserted. The smoke program
  asserts only the blocker text `may leave the region` for the D1 plan with Flow on.
- Catchable exceptions and the draft's `dyn-reject-catch` case: not specified.
- Equality on Objects, Lists and Closures (section 6): not present.

Toolchain note: during development, fixture code that built IR through helper methods made the
Emerald-built generator crash, and the cause was not isolated. The fixtures therefore build their
IR inline. A fixture with a missing `return` also crashed the generator, which is a separate bug
in that fixture.
