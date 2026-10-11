# Language-frontend handoff

Written October 11, 2026 for the developer of a language frontend that targets Sublang. It
describes the interface that exists and was executed. Anything not listed under "Implemented
and verified" must not be designed around. Source of truth is the repository; the checks named
here are scripts in `scripts/` that run only inside the capped sandbox.

## 1. Exact compiler identity

| Item | Value |
| --- | --- |
| Product string | `Sublang 0.1-dev; wire=2 (reads 1/2); core.native64.v2` |
| Baseline commit | `0eba7ba` plus an **uncommitted** working tree (no commit was requested) |
| Source identity | SHA-256 of sorted `src/**/*.ems` checksum lines: `c5e0112109b32c782f7fbb3bcbc79b9b3262e9a88c6b4e6b1c17c7c889b9fbcb` |
| Binary | `build/sublang`, SHA-256 `887786060a730b31c59efa24b8927b6bceca6363ab92868014724bb08c15ea19` (built with `scripts/sublang-bootstrap.sh`) |
| IR schema / stage | 1 / High |
| Wire | reads transport 1 and 2, writes 2 |
| Required-feature tokens | `core.native64.v1`, `core.native64.v2`, `ext.bytes.v1`, `ext.numeric.v1`, `ext.eh.v1`, `ext.oo.v1` |
| Target | `native64-host-libc` (x86_64 Linux, 64-bit pointers, host libc) - the only one |
| Toolchain in the sandbox image | clang/LLVM 22.1.8, glibc 2.44, libstdc++ (needed for exceptions) |
| Optional full distribution | LLVM 23.1.3, private loader/libraries and C sysroot; see [Bundled LLVM](Sublang_Bundled_LLVM.md) for the separate driver, compatibility check and target restrictions |

`sublang capabilities` prints this as stable `key=value` lines (`capabilities-format=2`).

Source fingerprint command, from the repository root:
`find src -type f -name '*.ems' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum`.

The latest hardening run rebuilt the binary and passed `sublang-pass-sandbox.sh`, then compiled
and ran `bond-component.sublang-wire` with Flow on (4242) and `inline-local.sublang-wire` with
Flow off (42), Optimind on in both cases. Both plans report verified Low IR and successful
structure/semantics/native-memory validation. Historical full runtime/sanitizer checks below
were not repeated for this compiler-only hardening change.

## 2. Build and export commands

The installed full distribution adds `sublang build` and `sublang toolchain info` through its
packaged driver. The commands below continue to describe development launchers and the core
binary. Add `--toolchain=bundled` to the development build launcher to select the full package
inside the prescribed sandbox; the core binary alone still emits LLVM and does not spawn tools.

Prerequisites: Docker, the local image `emerald-selfhost-sandbox` (`SUBLANG_SANDBOX_IMAGE`
overrides it), and for building the compiler itself the Emerald toolchain at `../Emerald LLVM`
(`SUBLANG_EMERALD_ROOT`). A frontend that only emits Wire needs neither Emerald nor Python in
the sandbox. Every compiler or program run happens in a container with 6,000,000,000 bytes of
RAM and the same swap limit, no network, read-only inputs and time limits.

```bash
bash scripts/sublang-bootstrap.sh                       # build build/sublang once
bash scripts/sublang-build.sh program.sublang-wire -o build/program --flow=on --optimind=on --llvm-opt=2 --run
bash scripts/sublang-build.sh a.sublang-wire -o build/a --emit=obj          # or bc, ll, exe (default)
bash scripts/sublang-build.sh p.sublang-wire -o build/p --lto=full          # or thin
bash scripts/sublang-build.sh p.sublang-wire -o build/p --pgo=train         # exports program.profdata + .profmeta
bash scripts/sublang-build.sh p.sublang-wire -o build/p --pgo=use --profile=DIR
```

Inside a container (or any host that has the binary) the process interface is:

```text
sublang emit-llvm IN.sublang-wire OUT.ll auto|on|off on|off     # writes OUT.ll and OUT.ll.plan
sublang link OUT.sublang-wire PROVIDER.sublang-wire CONSUMER.sublang-wire [MORE...]
sublang dump IN.sublang-wire            # human dump (not an input format)
sublang dump-low IN.sublang-wire auto|on|off on|off
sublang text-dump IN.sublang-wire       # canonical lossless text IR
sublang text-build IN.sublang-text OUT.sublang-wire
sublang capabilities | --version
```

Exit codes: 0 success, 1 invalid IR / link / codegen failure, 2 command-line or input error.
Executables must be linked with `-lstdc++` when the IR uses exceptions (the launcher does this
automatically when the emitted LLVM references `__gxx_personality_v0`).

## 3. Implemented and verified

Each line names the check that executed it.

| Area | Contract | Check |
| --- | --- | --- |
| Scalars | signed Int64 (per operation `trap`, `wrap` or `zero` overflow mode), Float64 IEEE round-to-nearest-even, Bool, static byte String | `sublang-backend-sandbox.sh` |
| Control | typed functions, blocks with block parameters (SSA), branches, loops, direct calls, abort-only `fail` | backend suite, `sublang-tiny-check.sh` |
| Ownership | explicit scopes; owned/borrowed passing modes `value`, `owned`, `borrow_read`, `borrow_write`, `init`; owned returns; definite-initialization and use-after-move rejection | backend suite (ASan/LSan) |
| Objects | Class with Record values; Folded, Local, Inline, Shard, Pool, Root, Bond, Static placements chosen by the plan | backend suite |
| Collections | `List` of primitives, Records, inline classes, owned classes; `list.set`, `list.replace` | backend suite |
| Byte text | `Byte`, dynamic strings as `List<Byte>`: `text.from_str/append/concat/slice/equal`, bounds-checked, realloc-safe, released under churn | backend suite (150 MB limit, ASan) |
| Numerics | `int.to_float`, exact `float.to_int`/`float.is_int`, exact mixed `number.equal` | backend suite |
| Exceptions | `invoke` (normal + unwind edge, result on the normal edge only), `throw`, `resume`; exception value is an Int code; cleanup is explicit in your CFG | backend suite (exactly-once cleanup under LSan) |
| Objects/OO | class hierarchies by `target` (field prefix rule), closed-world dispatch groups, `class.upcast`, checked `class.downcast`, `call.virtual`; destruction through a base type | backend suite |
| Modules | `sublang link`: imports resolved by name and exact signature, types unified by name and structure | backend suite |
| Build modes | `--emit`, `--lto`, `--pgo` | `sublang-modes-check.sh` |
| Text IR | lossless round trip with Wire | `sublang-text-sandbox.sh` |
| Dynamic values | library of IR functions over `class Dyn` (nil, bool, int, float, text) | `sublang-dynamic-sandbox.sh` |
| Independent frontend | Python `tiny.py` writing Wire v2 | `sublang-tiny-check.sh` |
| Pass isolation | independent snapshot forks, stale-parent rejection, context/store-specific caches, pre-commit native lifetime verification, at most 64 entries per analysis table | `sublang-pass-sandbox.sh` |

### Semantic profile

`sublang.startup` v1: `i64-signed` integers, `f64-ieee-rne` floats, failure model `abort`
(SIGABRT, nothing printed), unwinding `none`. Source-language rules (evaluation order,
identity, mutation, error meaning) belong to your frontend; Sublang does not infer them.

Failures: checked arithmetic overflow, division by zero, bounds errors on strings, lists and
text, `field.borrow` of an empty field, failed `class.downcast`, inexact `float.to_int`, an
unregistered dispatch tag and an uncaught exception all abort the process.

### Closures, errors and objects

- **No closure opcode.** The tested pattern is a class that holds the captured environment
  (owned `Ref`) plus an `Int` code, created by a function that returns it owned, applied through
  a closed set of targets (branch chain or `call.virtual`). `scripts/sublang-dynamic-sandbox.sh`
  fixture D5 does this; a borrowed parameter returned as owned is rejected (D6).
- **Errors:** user exceptions are `Int` codes. There is no payload object, no typed catch, no
  filter or `finally` construct; the frontend lowers them to code comparison and explicit
  cleanup blocks. The verifier rejects `throw`/`resume` while a scope is active and a plain call
  to a function that may throw while cleanup is pending (`SUBLANG-B005`).
- **Objects:** single inheritance only; the root class has an `Int` tag field you store
  yourself; every concrete class is registered with a tag and every group must list an
  implementation per registered class. Interfaces are dispatch groups; there is no reflection,
  no multiple inheritance and no dynamic loading.

## 4. Accepted IR examples

All are produced and consumed by the checks above; start from them rather than from the spec.

- Wire inputs: `examples/wire/*.sublang-wire` (core subset, Flow families).
- Independent frontend: `examples/frontend/tiny/` (`tiny.py`, `fib.tiny`, `factorial.tiny`).
  Functions, loops, branches, calls, checked arithmetic, source spans.
- Feature fixtures (Emerald builders): `src/sublang/harness/pass/SublangTextFixtures.ems`
  (text, `list.set`, numbers), `SublangExceptionFixtures.ems` (invoke/throw/resume),
  `SublangObjectFixtures.ems` (hierarchy, dispatch), `SublangLinkFixtures.ems` (link),
  `SublangDynamicFixtures.ems` (Dyn library).
- Text form (canonical, lossless; grammar in `docs/Sublang_Text_IR.md`):

```text
sublang-text 1 schema=1 stage=High revision=1
module "arithmetic" entry=1
span id=1 source=0 line=0 column=0 origin="backend:arithmetic"
profile id=1 name="sublang.startup" version=1 integer-rules="i64-signed" float-rules="f64-ieee-rne" failure-model="abort" unwinding-model="none"
failure id=1 name="test.abort" behavior="abort" binding="unbound" signature="noreturn void()" continues=false unwinding="none" span=0
effect id=1 name="conservative" span=0
  fact area="allocation" value="unknown" provenance="assumed-conservative" ...   (nine areas)
func id=1 name="main" returnType=3 methodOf=0 span=1 profile=1 effect=1 linkage="internal" convention="sublang" definition="body"
  value id=1 type=3
  block id=1 params=[]
    op id=1 opcode="const.int" ... int=2000000000 ...
    op id=3 opcode="int.add" ... ref=1 overflow="trap" operands=[1,2] modes=["value","value"] ...
    op id=4 opcode="return" ... operands=[3] modes=["value"] ...
end
```

Rules a writer must follow that the transport does not check: operation ids are unique across
the whole module (`SUBLANG-B008`); every function body ends each block in exactly one
terminator; scopes are begun once and ended innermost-first on every exit; the entry is
`() -> Int`.

## 5. Runtime and link ABI

- Generated functions are internal `@fn<id>` symbols; there is no exported or imported C ABI.
  A call to an external contract is rejected (`SUBLANG-B004`). Interaction with C is only
  through the separate `scripts/sublang-build.sh file.c` path, which is plain clang.
- The entry function prints its `Int` result with `printf("%lld\n")` and returns 0.
- Provider symbols (flow, shard, bond, list, text, pool runtime and per-type drop/trace
  visitors) are emitted into every module; calls to them are verified against
  `src/sublang/low/target/SublangLowProvider.ems`.
- Link: dynamic libc; add `-lstdc++` for exceptions. Output modes `exe`, `obj`, `bc`, `ll`.
- Memory-plan and effect decisions are written to `OUT.plan` (Flow families, blockers with the
  blocking callee and derived summary, `optimind:` and `effects:` lines, the `lowering:` route).

## 6. Diagnostics and rejected features

Catalog: `docs/Sublang_Diagnostics.md`. Backend gate failures print
`SUBLANG-B002: <verifier code> <message> (line L, column C)`. Rejected on purpose:
nullable references, arbitrary pointers, FFI/external calls, tracing GC integration, Float
comparisons without an explicit ordered/unordered predicate (`SUBLANG-A003`), borrowed string
slices (`text.slice` copies), exceptions with payload objects, threads, finalizers.

## 7. Unavailable and not implemented

| Capability | State |
| --- | --- |
| Weak handles, finalizers/destructor hooks | not implemented (design only in `Implementation_Plan.md` section 11) |
| Threads, shared concurrent Bond | not implemented; no thread-safety claim of any kind |
| C ownership import from LLVM (`--flow=on` for C) | not implemented; C stays plain clang, `--flow=on` is rejected |
| Additional targets, cross compilation | not implemented; only `native64-host-libc` |
| Cross-module LTO with C code | not available: there is no C import contract |
| Dynamic: objects/properties, indexes, ordering and `- * / %` on `Dyn`, general closures | not implemented (library covers nil/bool/int/float/text, add, equal, truthy, to_int) |
| Borrowed byte-string views | not implemented |
| Speed or RSS claims | none; the measurement tooling exists but the bundled inputs are correctness-sized |

## 8. Toolchain observations

Found while implementing; they concern the external Emerald toolchain, which this work does not
modify:

- A fixture built through helper methods crashed the Emerald compiler once and a missing
  `return` in a fixture crashed the generator; the root cause was not isolated.
- A `String` produced by `StringBuilder.toString()` from a builder local to the returning
  function was observed to be corrupted; concatenation with `+` avoids it.
- Emerald Flow v1 requires single-binding object locals (`List<...>` included) and rejects
  views of list elements that outlive a mutation; the compiler prints `error:L:C` without a
  file name.
- Emerald string literals have no escape for NUL; build NUL bytes at run time or read them from
  a file.

## 9. Minimal independent frontend

`examples/frontend/tiny/tiny.py` is a complete, standard-library-only frontend that writes real
Wire and is exercised end to end:

```bash
python3 examples/frontend/tiny/tiny.py examples/frontend/tiny/fib.tiny build/tiny/fib.sublang-wire
bash scripts/sublang-build.sh build/tiny/fib.sublang-wire -o build/tiny/fib --flow=on --run   # 6000
bash scripts/sublang-tiny-check.sh                                                          # values, aborts, diagnostics
```

Next step for the language project: write the second language prompt against sections 3 to 7,
using Tiny as the template for a Wire writer or the text IR (`text-build`) while the language
is young, and extend the profile only with capabilities listed as implemented.
