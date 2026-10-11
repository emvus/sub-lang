# Sublang Dynamic Library (dyn-v1)

Status: implemented as an IR library generator and verified by
`scripts/sublang-dynamic-sandbox.sh`. Scope and open items are in
[Sublang Dynamic Profile](Sublang_Dynamic_Profile.md), section "Implementation status".

The library adds a small set of ordinary Sublang functions to a module. It uses only existing IR
contracts (classes, owned `Ref` fields, `scope.begin`/`scope.end`, `class.new`, `call.direct` with
owned results, `text.*`, `int.*`, `float.*`, `number.equal`, `int.to_float`, `float.to_int`,
`compare`, `cond_branch`, `fail`). No opcode is added.

## 1. Representation

```text
class Dyn { tag: Int (mutable); num: Int (mutable); real: Float (mutable); text: owned Ref<List<Byte>> }
```

| tag | value | `num` | `real` | `text` |
| --- | --- | --- | --- | --- |
| 0 | nil | 0 | 0.0 | cleared |
| 1 | bool | 0 or 1 | 0.0 | cleared |
| 2 | int | the value | 0.0 | cleared |
| 3 | float | 0 | the value | cleared |
| 4 | text | 0 | 0.0 | owned byte list with the bytes |

A value is `owned Ref<Dyn>`. Every constructor allocates its object in its own scope and returns it
owned, after all four fields are initialized (`field.init`, or `field.clear` for the Ref field).
Inspection functions take `borrow_read` parameters and allocate nothing.

## 2. Functions

| Function | Signature | Behavior |
| --- | --- | --- |
| `dyn_nil` | `() -> owned Dyn` | tag 0 |
| `dyn_bool` | `(Bool) -> owned Dyn` | tag 1; `num` is 0 or 1 from a branch join, not a coercion |
| `dyn_int` | `(Int) -> owned Dyn` | tag 2 |
| `dyn_float` | `(Float) -> owned Dyn` | tag 3 |
| `dyn_text` | `(String) -> owned Dyn` | tag 4; copies the bytes with `text.from_str` |
| `dyn_truthy` | `(borrow_read Dyn) -> Bool` | nil false; bool and int `num != 0`; float `one(real, 0.0)` (not zero and not NaN); text byte length > 0 |
| `dyn_add` | `(borrow_read Dyn, borrow_read Dyn) -> owned Dyn` | Int+Int `int.add` trap (`dyn.overflow`); Int+Float promotes the Int with `int.to_float` and adds with rne; Float+Float rne; Text+Text `text.concat`; any other pair fails `dyn.type_error` |
| `dyn_equal` | `(borrow_read Dyn, borrow_read Dyn) -> Bool` | same tag: nil true, bool/int `num` equal, float `oeq`, text `text.equal`; Int vs Float (either order) `number.equal`, exact; any other pair false |
| `dyn_to_int` | `(borrow_read Dyn) -> Int` | int returns `num`; float uses `float.to_int` (exact; aborts on fraction or range); other tags fail `dyn.type_error` |

Failures use the default `libc.abort` binding, so a failing program terminates with SIGABRT
(exit status 134) and prints nothing.

No Bool-to-Int coercion exists in the library. A bool is converted to Int only by the branch in
`dyn_bool` that stores 0 or 1 as the `num` of a bool value.

## 3. Lifetime rules used

- Allocation happens only in the callee's own scope, which is the innermost scope at the
  allocation point (`class.new`, `text.from_str`, `text.concat`).
- Allocating functions return their result owned with `return`; the return closes the function's
  remaining scope. The caller adopts the result with `call.direct` (owned) into its destination scope.
- Borrowed parameters are never returned as owned, and never mutated.
- Every `Ref` field is initialized (`field.init` with an owned child, or `field.clear`) before the
  object is returned or passed as a borrow.

## 4. Decisions that differ from the draft profile

- Float truthiness: NaN is falsy (the library uses `one`, which is false for NaN). The draft in
  section 5 of the profile said NaN is truthy. The library follows the task contract that defines
  this profile version.
- Int/Float equality uses `number.equal`, which exists today. The draft's section 6 called for a
  new `float.to_int_exact` op; that dependency is not needed.
- Int+Float promotion uses `int.to_float`, which exists today. The draft's section 4 listed it as a
  new op.
- Values are objects with owned fields, not pool offsets. The draft's section 3 record and pool
  design is not used.

## 5. Source layout

`src/sublang/dynamic/` (6 files, namespace `sublang::dynamic`):

- `SublangDynamicLibrary.ems`: public generator and profile header; accessors for the function ids.
- `SublangDynamicLayout.ems`: the Dyn class, its fields, the byte-list type and the failure records.
- `SublangDynamicValues.ems`: the five constructors and the object builders they share.
- `SublangDynamicOperations.ems`: `dyn_truthy`, `dyn_equal`, `dyn_to_int`.
- `SublangDynamicArithmetic.ems`: `dyn_add`.
- `SublangDynamicBranch.ems`: tag tests and the list literals used by the dispatch chains.

## 6. Acceptance programs

`src/sublang/harness/pass/SublangDynamicFixtures.ems` and `src/SublangDynamicSmoke.ems`. Each
program is emitted with Flow off and on (optimind on in both) to `/tmp/dyn/<name>-<flow>.ll` and
`.plan`.

| Program | Checks | Expected |
| --- | --- | --- |
| `dyn-d1` | text Dyn in main survives an allocating `dyn_add`, is used after it, and is released (LeakSanitizer). `"ab"+"cd"` equals `"abcd"`; the original `"ab"` still equals `"ab"`; the sum is truthy. | 111 |
| `dyn-d2` | `greet()` builds an owned text Dyn in its own scope; main uses and releases it. | 11 |
| `dyn-d3` | exact equality: int 2^53+1 vs float 2^53 false; int 2^53 vs float 2^53 true; promotion `1 + 0.5` equals float 1.5; `to_int(1 + 0.5 + 0.5) = 2`; truthiness of bool true, bool false, nil and NaN. | 1527 |
| `dyn-d4-type`, `dyn-d4-inexact`, `dyn-d4-overflow` | int+text, `to_int(2.5)` and checked overflow abort. | exit 134, no output |
| `dyn-d5` | closure class `Closure { code: Int; captured: owned Ref<Dyn> }`: creator returns an owned closure that captured an owned Dyn; call helper dispatches on `code` over two closed bodies; result checked, then released. | 142 |
| `leakCapture` (D6) | a function returns its `borrow_read` parameter as owned. The backend gate must reject it with `borrowed reference cannot be returned as owned`. | rejected |

D6 also requires that the D1 plan with Flow on contains `may leave the region`. The smoke program
asserts both.

Constant note: the float bit pattern for 9007199254740992.0 (2^53) is 4845873199050653696. The
value 4841369599423283200 listed in the task decodes to 2^52, so the fixtures use the 2^53 pattern.

## 7. Verification

`scripts/sublang-dynamic-sandbox.sh` runs inside the capped Docker sandbox. Inside the container it
builds and runs the generator, then for each program: `llvm-as`, `opt -passes=verify`, `clang -O2`,
and a native run compared with the expected value. D1, D2 and D5 also run under AddressSanitizer
with LeakSanitizer for both variants. The aborting programs must exit with 134 and print nothing.
The last run printed `Sublang dynamic: all checks passed`.

Artifacts (`.ll` and `.plan`) are copied to `build/dyn/`.
