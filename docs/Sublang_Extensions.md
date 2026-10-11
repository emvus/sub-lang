# Sublang Wire Extension Features

Status: experimental. Describes the four required-feature tokens of the Sublang Wire
transport as implemented in the working tree. Every statement is taken from the Emerald
sources named in it; claims that could not be confirmed by reading code or fixtures are
marked `UNVERIFIED:`. The sandbox script was read but not executed, so no PASS result
below is a run result.

Related: `docs/Sublang_Wire_Spec.md` (record level), `docs/Sublang_Diagnostics.md` (codes).

## 1. Feature model

The header carries a required-feature list. The first token is the core token; every later
token is an extension token (`src/sublang/wire/SublangWire.ems`, `features`).

| Token | Declared exactly when the module uses | Opcodes / types |
|---|---|---|
| `core.native64.v1` / `core.native64.v2` | always (exactly one core token, must match transport) | core IR |
| `ext.bytes.v1` | a `Byte` type exists, or any opcode in the byte-text set | see section 2 |
| `ext.numeric.v1` | any opcode in the numeric set | see section 3 |
| `ext.eh.v1` | any `invoke`, `throw` or `resume` | see section 4 |
| `ext.oo.v1` | a non-empty dispatch table, a class with a base (`target != 0`), or any object opcode | see section 5 |

Sources: `SublangWireFeatures.ems` (`needed`, `usesBytes`, `usesNumeric`, `usesExceptions`,
`usesObjects`), `SublangVocabulary.ems` (`isTextOpcode`, `isNumericOpcode`,
`isExceptionOpcode`, `isObjectOpcode`).

Rules that apply to all four:

- **Canonical order.** The writer emits extension tokens in the order `bytes, numeric, eh, objects`
  (`needed`). A reader accepts any order of known tokens.
- **Transport.** Extension tokens are accepted only with transport 2 (`extension()` rejects
  them when `version != 2`). Transport 1 also rejects the `Byte`, `String`, `List` and `Bond`
  type kinds (`SublangWireTables.types`).
- **Count.** The token count is `1 + needed.length()` on write and is bounded to 32 on read.
- **Writer.** `SublangWire.write` requires a frozen module and writes exactly the tokens that
  `needed(module)` returns, so a written module always declares what it uses.
- **Reader.** Unknown tokens and duplicate tokens are rejected (`unknown or duplicate required
  feature`). A module that uses a feature without declaring it is rejected with
  `module uses ext.X without declaring the feature` (`SublangWire.transfer`).
- **Declared but unused.** The reader does not reject an extension token that the module does
  not use. `UNVERIFIED:` this is only what the code shows; no test covers it.
- **Capabilities.** `sublang capabilities` prints only the two core tokens
  (`src/sublang/cli/SublangCommand.ems`). Extension tokens are not listed there.
- **Dispatch section.** The dispatch tables (`SublangWireTables.dispatch`) are read and written
  only when `ext.oo.v1` is declared.

Compiler guard: `SublangCompiler.ems` returns `SUBLANG-B009` when a module that uses
`ext.bytes.v1`, `ext.numeric.v1` or `ext.eh.v1` cannot be lowered to Low IR. These extension
operations are emitted only from Low IR. `ext.oo.v1` is not in that guard (see section 5).

---

## 2. ext.bytes.v1 (byte text and list replacement)

### Type and opcodes

Type kind `Byte`: primitive, width 8, unsigned (`SublangTypeChecks.ems`). It is not a
`Bool`/`Int` comparison operand (`compare` accepts only `Int`, `Bool` and `Ref`;
`SublangArithmeticChecks.ems`). There is no `const.byte`; a `Byte` value comes only from
`byte.from_int`.

Notation: `L` = `Ref<List<Byte>>` (a byte list). `E` = list element type. `C` = class element type.

| Opcode | Operands (mode) | Result | Ref / scope |
|---|---|---|---|
| `byte.from_int` | `Int` (value) | `Byte` | no ownership, scope 0 |
| `byte.to_int` | `Byte` (value) | `Int` | no ownership, scope 0 |
| `list.set` | `Ref<List<E>>` (borrow_write), `Int` index (value), `E` (value) | none | no result |
| `list.replace` | `Ref<List<C>>` (borrow_write), `Int` index (value), `Ref<C>` (owned) | none | no result |
| `text.from_str` | `String` (value) | `L` | owned, scope > 0, `ref` = List<Byte> |
| `text.append` | `L` (borrow_write), `String` (value) | none | no result |
| `text.concat` | `L` (borrow_read), `L` (borrow_read) | `L` | owned, scope > 0 |
| `text.slice` | `L` (borrow_read), `Int` start (value), `Int` length (value) | `L` | owned, scope > 0 |
| `text.equal` | `L` (borrow_read), `L` (borrow_read) | `Bool` | no ownership, scope 0 |

Sources: `src/sublang/ir/data/SublangCollectionBuilder.ems` (builders), `SublangTextChecks.ems`
(contracts).

### Verifier

- `SublangTextChecks.check` reports every violation as `SUBLANG-T003` (the message names the
  opcode). Examples: wrong operand count; `byte.from_int` operand not `Int`; receiver not
  `Ref<List<Byte>>`; wrong access mode; `text.append` operand not `String`; `text.slice`
  start/length not `Int` values; a `text.*` result that is not owned with a destination scope.
- `list.set` rejects class elements (`use list.replace`). `list.replace` requires owned class
  elements (inline classes rejected) and an owned `Ref<C>` argument.
- Lifetime (`SublangLocalLifetime.ems`, surfaced by the backend gate as `SUBLANG-B005`): a text
  allocation (`text.from_str`, `text.concat`, `text.slice`) requires its destination scope to be
  the innermost active scope; operands of `text.concat`, `text.slice` (source) and `text.equal`
  must be alive; mutating operations on a read-only borrow are rejected; mutations
  (`list.set`, `list.replace`, `text.append`, `list.push`, `list.clear`) invalidate borrowed views.

### Semantics and lowering

- `byte.from_int`: `value >u 255` (unsigned compare, so negatives fail too) aborts; otherwise
  `trunc` to `i8` (`SublangLowerData.narrowByte`). `byte.to_int`: `zext` `i8` to `i64`.
- `list.set` / `list.replace`: index checked by `sublang.list.at` (aborts if index >= length).
  `replace` detaches the child, stores it, then drops the old element exactly once.
- Byte lists are runtime headers `{ptr data, i32 length, i32 capacity}`
  (`SublangLlvmListRuntime.ems`). `sublang.text.append` grows geometrically with overflow-checked
  arithmetic; a capacity above 2^31-1 aborts; a failed `realloc` aborts before the old buffer is
  replaced.
- `text.from_str` / `text.concat` / `text.slice` allocate in the destination scope and copy.
  `text.slice` aborts unless `start <=u length` and `count <=u length - start`.
- `text.equal`: equal lengths, then `memcmp` (`sublang.text.equal`).
- Lowering routing: `SublangLowering.ems` sends `list.*`, `text.*`, `byte.*` to `SublangLowerData`.

### Evidence

- Fixtures: `src/sublang/harness/pass/SublangTextFixtures.ems`: `loop`, `utf8`, `listSet`,
  `replace(false|true)`, `churn`, `abort(0|1|2)`. `SublangBackendSmoke.ems` emits them as
  `text-loop`, `text-utf8`, `list-set`, `list-replace`, `text-churn`, `set-bounds`,
  `slice-bounds`, `byte-range`.
- Sandbox (`scripts/sublang-backend-sandbox.sh`): expected results `text-loop:2021`,
  `text-utf8:195164`, `list-set:139`, `list-replace:5`, `text-churn:400000000`; ASan/LSan runs
  for these; `text-churn` under a 150 MB address-space limit; `set-bounds`, `slice-bounds`,
  `byte-range` must exit with status 134 (SIGABRT).
- Wire: `SublangPassChecks.wireFeature` (run from `SublangPassSmoke.ems`) checks that a
  `list.set` module writes `12:ext.bytes.v1`, reads back, rejects the token when removed
  (`without declaring`), and rejects an unknown token (`ext.bytes.v9`). A core-only module
  must not contain `ext.`.

### Restrictions (not supported)

- No `Byte` constant, no `Byte` arithmetic, no `Byte` comparison.
- `text.append` accepts only a static `String`; joining two dynamic byte lists uses
  `text.concat`.
- No borrowed slice: `text.slice` always copies, and a dynamic text result is always an owner.
- `string.byte` (core) reads static strings only; it is not part of this feature.
- `list.set` is not valid for class elements; `list.replace` is not valid for inline or
  non-class elements.
- Element and text sizes are bounded by the runtime `i32` header (2^31-1).
- Out-of-range `byte.from_int`, `text.slice` and list indexes abort. They are not catchable
  (no `ext.eh.v1` involvement).
- `list.set` on any list also requires `ext.bytes.v1` in the header, because `list.set` and
  `list.replace` are in the byte-text opcode set (`isTextOpcode`), even for non-byte lists.

---

## 3. ext.numeric.v1 (exact numeric conversions)

### Opcodes

| Opcode | Operands (mode) | Result | Notes |
|---|---|---|---|
| `int.to_float` | `Int` (value) | `Float` | rounds to nearest-even (source comment) |
| `float.to_int` | `Float` (value) | `Int` | aborts unless finite, integral and in [-2^63, 2^63) |
| `float.is_int` | `Float` (value) | `Bool` | false outside the range; never aborts |
| `number.equal` | `Int` (value), `Float` (value) | `Bool` | exact mixed equality |

All four results carry no ownership and scope 0 (`SublangConversionChecks.ems`).

### Verifier

Violations are `SUBLANG-T001` (`SublangConversionChecks.check`): operand count, operand type or
mode, result type, ownership or scope.

### Lowering

Routed by `SublangLowering.ems` to `SublangLowerScalar.ems`:

- `int.to_float`: `sitofp i64 to double`.
- `float.is_int`: a branch-based range test (`>= -2^63` ordered, `< 2^63` ordered; NaN and
  infinities go to `false`), then `fptosi`, `sitofp` back, and an ordered-equal compare. `-0.0`
  is accepted as zero.
- `float.to_int`: the same range guard; on a non-integral or out-of-range value the block
  calls `abort`.
- `number.equal`: the Float must pass the range and integrality tests and then be compared to
  the `Int` as an `i64` equality. The `Int` is never converted to `Float`, so values above 2^53
  are not rounded in the comparison.

Effects: `float.to_int` raises the `failure` effect (`SublangEffectTransfer.ems`).

### Evidence

- Fixture `SublangTextFixtures.numbers()` (emitted as `numbers`, expected `7034`): covers
  `2^53+1` vs its rounded float (false), `2^53` (true), `2.5`, `1e30`, NaN, `2^63`, `-0.0`
  (true), and `Int64 max` vs `2^63`.
- Fixture `SublangTextFixtures.inexact(0|1)` (emitted as `toint-fraction` = 2.5 and
  `toint-range` = 1e30): the sandbox requires status 134 (SIGABRT) for both.

### Restrictions (not supported)

- No implicit `Int`/`Float` conversion and no `Float` to `Int` truncation or rounding mode.
  `float.to_int` does not round; it aborts.
- `float.to_int` is not catchable (it aborts, it does not raise an `ext.eh.v1` exception).
- No overflow or rounding operand on these opcodes.
- No `Byte` involvement (use `byte.to_int` in `ext.bytes.v1`).
- `UNVERIFIED:` that `int.to_float` uses round-to-nearest-even on the built binary. The claim
  rests on the source comment and the default LLVM floating-point environment.

---

## 4. ext.eh.v1 (exceptions)

### Model

An exception is an `Int` code. There is no exception object, no typed catch in High IR, and no
payload beyond the code. Cleanup is explicit in the control-flow graph.

| Opcode | Shape | Semantics |
|---|---|---|
| `invoke` | `ref` = body function; one argument per callee parameter (mode must match); two successors: normal, unwind; no result on the op | Normal edge: the call result is the only parameter of the normal block (no parameter for `Void`). Unwind edge: the exception `Int` is the only parameter of the unwind block. |
| `throw` | one `Int` value (value mode); no successors; no result | Raises the code. |
| `resume` | one `Int` value (value mode); no successors; no result | Rethrows the code it is given; lowered the same way as `throw` (`SublangLowerControl.raise`). It does not refer to the original exception. |

### Verifier

- `SublangExceptionChecks.check` reports shape and contract errors as `SUBLANG-X001`:
  - an exception op that defines a value;
  - `invoke` of an unknown function or of an external function (`needs a provider contract`);
  - argument count, type or passing-mode mismatch;
  - callee return type not `Void`, `Int`, `Bool` or `Float`;
  - not exactly two targets, or non-existent target blocks, or equal targets;
  - normal block parameter count/type wrong; unwind block not exactly one `Int` parameter;
  - `throw`/`resume` with successors, or an operand that is not one `Int` value.
- Lifetime rules are not in `SublangExceptionChecks`. They are in `SublangLocalLifetime`,
  reported by `SublangBackendGate` as `SUBLANG-B005`:
  - `throw` or `resume` while any owner scope is still active (`owner scope still active at
    throw; end it before leaving the function`);
  - a `call.direct` or `call.virtual` to a function that may throw while cleanup is pending.
    Cleanup is pending when a scope is open or the function has an owned reference parameter.
    The message is `call to F may throw while cleanup is pending; use invoke`. "May throw" means
    the callee's `exceptions` effect area is non-zero (for a group: any registered
    implementation).
  - An `invoke` is never rejected by this rule.

### Lowering (Low IR and Itanium C++ ABI)

- `SublangLowControl.invoke`: transfers owned arguments, then emits a Low `invoke` with a normal
  block and a landing block. The landing block starts the High unwind block with the caught
  code.
- `SublangLowLlvm.ems`:
  - `invoke` becomes an LLVM `invoke ... to label ... unwind label ...`;
  - the landing block emits `landingpad { ptr, i32 } catch ptr @_ZTIl`, `__cxa_begin_catch`,
    loads the `i64` code, then `__cxa_end_catch`;
  - `throw` becomes `__cxa_allocate_exception(8)`, a store of the `i64` code,
    `__cxa_throw(ptr, @_ZTIl, null)`, `unreachable`;
  - a function containing `invoke` gets `personality ptr @__gxx_personality_v0`;
  - modules that use `ext.eh.v1` get the declarations (`@_ZTIl`, `__gxx_personality_v0`,
    `__cxa_allocate_exception`, `__cxa_throw`, `__cxa_begin_catch`, `__cxa_end_catch`)
    (`SublangLlvmEmitter.ems` line 45).
- Leaving by exception (`raise`) first ends the function-level owners, as a return does.
- Linking: the sandbox adds `-lstdc++` whenever the `.ll` contains `__gxx_personality_v0`, which
  every `ext.eh.v1` module does because of the declarations above. `UNVERIFIED:` whether the
  product build adds `-lstdc++` outside the sandbox.

### Evidence

- Fixtures `src/sublang/harness/pass/SublangExceptionFixtures.ems`:
  - `build(0)` (emitted as `exceptions`, expected `311`): a `thrower` allocates in its own scope,
    throws on nonzero code; `middle` invokes it, ends its scope exactly once on the unwind edge,
    and rethrows with `resume`; `main` catches the second call.
  - `uncaught()` (emitted as `uncaught`): a plain call from a frame with no cleanup; the sandbox
    requires status 134 (SIGABRT).
  - `build(2)` (throw inside an active scope) and `build(3)` (plain call to a throwing function
    with a scope active) are documented as rejected in the fixture comment. Smoke emits only
    `build(0)` and `uncaught()`. `UNVERIFIED:` no test asserts the `B005` rejections.
- Sandbox: `exceptions` runs under ASan and LeakSanitizer and must print `311` (base and opt);
  the line `PASS exceptional cleanup runs exactly once on throw, rethrow and catch` is printed on
  success. `uncaught` must exit 134.

### Restrictions (not supported)

- Exceptions carry only an `Int` code; no object, no message, no typed exception.
- No `catch` in High IR (`eh.catch` exists only in Low IR).
- `invoke` only on body functions; not on external functions and not on `call.virtual`.
- `invoke` results only `Void`, `Int`, `Bool` or `Float`; no `Ref` or `Bond` results across an
  invoke.
- The landing pad catches only the `long` typeinfo (`_ZTIl`); other C++ exception types are not
  produced by Sublang code.
- No `finally`-style cleanup construct; cleanup is written in the CFG.
- An uncaught exception terminates the process with SIGABRT (from the C++ runtime's terminate
  path). The sandbox asserts status 134; the mechanism is not otherwise verified here.
- `throw` and `resume` are rejected (`B005`) while any owner scope is active, so a raise always
  happens after the frame's scopes have been ended explicitly.

---

## 5. ext.oo.v1 (classes, hierarchies, closed-world dispatch)

### Model

- A class hierarchy is expressed through a `Class` type descriptor's `target` (the base class).
  The field prefix rule requires that a derived class begins with the base's fields, same name,
  type and mutability (`SublangDispatchChecks.hierarchy`).
- A dispatch table (`src/sublang/ir/SublangDispatchTable.ems`) is closed-world: it holds
  - registered classes `(type, tag)`;
  - groups `(name, root, tagField, prototype)` with entries `(tag, function)`.
- The root class has an `Int` tag field; each concrete class stores its registered tag there.

### Opcodes

| Opcode | Operands (mode) | Result | Rules |
|---|---|---|---|
| `class.upcast` | `Ref<D>` (`borrow_read` or `owned`) | `Ref<B>` | `B` must be an ancestor of `D`. Borrowed: result `borrow_read`, scope 0 (a read-only view). Owned: result `owned`, scope > 0 (ownership moves). |
| `class.downcast` | `Ref<B>` (`borrow_read`) | `Ref<D>` `borrow_read`, scope 0 | `D` must be a proper descendant of `B` and have a registered tag. Checked at run time. |
| `call.virtual` | `group` (`ref`); arguments match the prototype exactly (types and modes) | the prototype's return type | `Void` group: no result. `Ref`/`Bond` result: owned with scope >= 1. |

### Verifier

- Module-level (`SublangDispatchChecks.ems`):
  - `SUBLANG-O001`: base is not a class; cycle; derived class does not begin with the base's fields.
  - `SUBLANG-O002`: registered type not a class; class registered twice; two classes of one
    hierarchy share a tag; group root not a root class; group tag field not an `Int` field of the
    root; a registered class under the root has no entry in the group (closed-world coverage).
  - `SUBLANG-O003`: group has no prototype; entry names an unknown function; implementation
    signature (parameter types, passing modes, return type) differs from the prototype; a tag
    listed twice in one group.
- Operation-level (`SublangObjectChecks.ems`, `SUBLANG-O004`): upcast and downcast shape and
  ownership rules as in the table; `call.virtual` names no group, group has no implementation,
  wrong argument count or modes, wrong result type or presence, missing owned/scope for a
  reference result.

### Lowering

- `SublangLowerMemory.ems`:
  - `class.upcast` owned: detaches the source and adopts the object into the destination scope;
    borrowed: a plain binding (same pointer).
  - `class.downcast`: loads the tag field through the hierarchy root's group tag field, and calls
    `guard(tag != registered tag)`, which aborts on mismatch. The abort is not catchable.
- `SublangLowerControl.virtual`:
  - a group with one entry is lowered to a direct call with no tag test and records the note
    `call.virtual <group> in <fn>: one implementation, lowered to a direct call of <target>`
    (this note appears in the `.plan` output);
  - otherwise the receiver's tag is compared with each registered entry tag in order, and the
    matching function is called; an unknown tag reaches `abort`.
- Destruction: `SublangLlvmDropEmitter.ems`. For a class with registered descendants, the visitor
  switches on the tag and calls the descendant's visitor, which releases the derived-only owned
  fields. The emitted type-tag switch is named `switch i64 %tag`.
- Effects: `SublangEffectTransfer.ems` unites the effects of every entry of a group for
  `call.virtual`; `SublangCallGraph.ems` adds the group edges. This is the basis for
  devirtualization.

### Evidence

- Fixtures `src/sublang/harness/pass/SublangObjectFixtures.ems`:
  - `build(0)` (emitted as `objects`, expected `19`): `Shape` with `Rect` and `Holder`
    subclasses, one group `area` with three `call.virtual` calls, an owned upcast into a field,
    and nested scopes;
  - `build(2)` (`objects-solo`, expected `2`): one registered implementation, so the call
    becomes a direct call;
  - `build(3)` (`bad-downcast`): downcast of a plain `Shape` to `Rect`; the sandbox requires
    status 134.
- Sandbox: `objects` and `objects-solo` run under ASan and LeakSanitizer (base and opt); the
  script greps `switch i64 %tag` in `objects-opt.ll` and the one-implementation note in
  `objects-solo-opt.plan`. Success line: `PASS closed-world dispatch, base-type destruction and
  devirtualization (ASan/LeakSanitizer)`.

### Restrictions (not supported)

- Closed world only: no dynamic class registration; a group must cover every registered class
  of its hierarchy.
- Single inheritance only (one `target` per class).
- `class.downcast` takes only `borrow_read` references and produces only a view; no owned
  downcast.
- `class.upcast` to a non-ancestor is rejected; `class.downcast` to a non-registered class is
  rejected.
- `call.virtual` on a group with no entries is rejected.
- `UNVERIFIED:` the verifier does not check that the first parameter of a group prototype is a
  `Ref` to the group's root class, but `SublangLowerControl.chain` reads the tag through the
  first argument. Whether a mismatched prototype can reach lowering is not verified.
- `UNVERIFIED:` `ext.oo.v1` is not covered by the `SUBLANG-B009` guard, so an object-only module
  that fails Low lowering may fall back to the legacy emitter. The legacy emitter's handling of
  `class.upcast`, `class.downcast` and `call.virtual` was not checked.
- No `SUBLANG-O` diagnostic has a test assertion (search of `src/`, `scripts/` and the harness
  found only emitters and documentation).

---

## 6. Summary

| Feature | Declared when the module uses | Core operations | Transport | Verifier codes | Lowering | Evidence (fixture / sandbox) | Main restrictions |
|---|---|---|---|---|---|---|---|
| `ext.bytes.v1` | a `Byte` type, or `byte.*`, `list.set`, `list.replace`, `text.*` | `byte.from_int`, `byte.to_int`, `list.set`, `list.replace`, `text.from_str`, `text.append`, `text.concat`, `text.slice`, `text.equal` | 2 | T003 (text checks); B005 (lifetime); B009 (guard) | Low IR, `SublangLowerData` and `SublangLlvmListRuntime` | `text-loop`, `text-utf8`, `list-set`, `list-replace`, `text-churn`, `set-bounds`, `slice-bounds`, `byte-range`; `wireFeature` | no Byte constants or arithmetic; `text.append` takes only `String`; no borrowed slices |
| `ext.numeric.v1` | `int.to_float`, `float.to_int`, `float.is_int`, `number.equal` | the four opcodes | 2 | T001 | Low IR, `SublangLowerScalar` | `numbers` (7034); `toint-fraction`, `toint-range` (134) | exact only; `float.to_int` aborts, not catchable; no rounding modes |
| `ext.eh.v1` | `invoke`, `throw`, `resume` | `invoke`, `throw`, `resume` (`Int` codes) | 2 | X001 (shape); B005 (scope and cleanup rules) | Low IR; Itanium ABI (`__gxx_personality_v0`, `__cxa_throw`, `_ZTIl`) | `exceptions` (311); `uncaught` (134) | `Int` codes only; no typed catch; body callees only; needs libstdc++ |
| `ext.oo.v1` | hierarchy, dispatch table, `class.upcast`, `class.downcast`, `call.virtual` | the three opcodes; dispatch section in the wire | 2 | O001 to O004 | Low IR `SublangLowerMemory` and `SublangLowerControl`; drop visitors | `objects` (19); `objects-solo` (2); `bad-downcast` (134) | closed world; single inheritance; downcast is a borrowed view only |

## 7. Unverified items

Consolidated from the sections above:

1. The sandbox script was read, not run (Docker was not permitted); every PASS line is unexecuted.
2. No test asserts the `X001`, `O001` to `O004`, `B005` or `B009` rejections; their behaviour is from source only.
3. `ext.oo.v1` is inside the `B009` guard: a module that uses objects is never emitted by the legacy emitter.
4. The verifier checks that a group prototype's first parameter is a `Ref` to the root class (`SUBLANG-O003`).
5. Declared-but-unused extension tokens are accepted by the reader; no test covers this.
6. Round-to-nearest-even for `int.to_float` and `-lstdc++` at product link time are not verified on a built binary.
