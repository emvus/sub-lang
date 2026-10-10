# Sublang first-release support contract

Updated **October 11, 2026**. This contract defines the first Sublang release: the IR and input forms it accepts, the runtime behavior of accepted programs, the versions it is built against, the resource budgets it enforces, and what must be installed to use it. It describes the bounded native64 subset in [Native Slice](Sublang_Native_Slice.md) and the transport in [Wire and CLI](Sublang_Wire.md). It is not a permanent public ABI and promises no delivery date.

Source references point to the repository at commit `f9b9236`. Anything that cannot be checked in the repository or in a recorded artifact is marked `UNVERIFIED:`.

Related: [Roadmap section 1](Roadmap.md), [IR developer guide](Sublang_IR_Guide.md), [HyperAlloc IR](HyperAlloc_IR.md), [IR architecture contracts](Sublang_IR_Contracts.md).

## 1. Release scope

| Item | First-release contract | Source |
| --- | --- | --- |
| Compiler product | `build/sublang`, built by Emerald. `sublang emit-llvm INPUT OUTPUT.ll auto\|on\|off on\|off` writes LLVM IR text and `OUTPUT.ll.plan`. | `src/SublangMain.ems`, `src/sublang/cli/SublangCommand.ems` |
| Native executables | Produced by `scripts/sublang-build.sh`: LLVM verification and optimization, linking and optional execution, all inside Docker. | `scripts/sublang-build.sh`, `scripts/sublang-build-worker.sh` |
| Target | `native64-host-libc`, `provider=none`. Allocation, abort and output bind to the host libc. | `SublangCommand.ems` (`capabilities`), `src/sublang/backend/llvm/SublangLlvmRuntime.ems` |
| Semantic subset | Scalars, value records, scoped classes with owned references, owned and borrowed calls, lists, static strings, Flow regions and shared Bond graphs. | `docs/Sublang_Native_Slice.md`, `docs/HyperAlloc_IR.md` |
| Excluded | Dynamic AOT, closures, inheritance and virtual dispatch, exceptions and unwinding, weak references, threads, finalizers, dynamic strings, nullable references, external contracts, canonical Low IR, a versioned pass manager. | `docs/Roadmap.md` sections 2, 6 and 10; `SublangBackendGate.ems` (`contract` definitions rejected as B004); `SublangTypeChecks.ems` (nullable references, U001); `SublangSemanticChecks.ems` (U004, U005) |

## 2. Accepted IR (release subset)

### 2.1 Input forms

| Input | Route | Requirements | Source |
| --- | --- | --- | --- |
| `*.sublang-wire` (Wire v2; v1 core input accepted) | `build/sublang emit-llvm`, then sandboxed verify, optimize, link | `build/sublang` present; no Emerald mount | `scripts/sublang-build.sh`, `scripts/sublang-build-worker.sh` (wire branch) |
| `*.ems` builder defining `SublangProgram.build()` | Emerald compiler inside the sandbox, then `SublangBuild.emit` | Emerald toolchain mounted read-only | `src/sublang/backend/SublangBuild.ems`, worker builder branch |
| `*.c`, one translation unit | Clang, then LLVM verifier and optimizer, then native. No Sublang IR and no Flow or Optimind. | Clang in the image; `--flow=on` is rejected (C001) | `docs/Sublang_C_Support.md`, worker C branch |

Any other extension is rejected by the launcher. `.sublang` and `.sublang-ir` files have no parser (section 6).

### 2.2 Wire transport

Every scalar is a netstring: ASCII decimal byte length, `:`, payload, `,`. The header is:

```text
SUBLANG-WIRE, transport-version=2, IR-schema=1, stage=High, revision=1,
required-feature-count, required-features..., module-name, entry-FunctionId
```

Encoded example of the first header tokens:

```text
12:SUBLANG-WIRE,1:2,1:1,4:High,1:1,1:1,16:core.native64.v2,
```

Rules enforced by the reader (`src/sublang/wire/SublangWire.ems`, `SublangWireStream.ems`):

- Transport must be 1 or 2. Schema must be 1, stage `High`, revision 1.
- Exactly one required feature is accepted, and it must be the core token: `core.native64.v1` for transport 1, `core.native64.v2` for transport 2. Unknown or duplicate features are rejected.
- Transport 1 rejects `String`, `List` and `Bond` types and `const.string` (`SublangWireTables.ems`, `SublangWireBody.ems`).
- Trailing bytes after `end` are rejected. Malformed input reports `SUBLANG-W001` with a byte offset.

The transport is an experimental encoding, not a permanent compatibility commitment (`docs/Sublang_Wire.md`).

### 2.3 Types

| Kind | Accepted form | Source |
| --- | --- | --- |
| `Void` | Function return type only. | `SublangVocabulary.ems` (`isKnownTypeKind`) |
| `Bool`, `Int`, `Float` | Primitive values. `Int` is signed i64; `Float` is IEEE binary64. | `SublangVocabulary.ems`; `docs/Sublang_Native_Slice.md` |
| `String` | Static, immutable, `{ pointer, i64 byteLength }`. Copying does not allocate. Byte semantics only. | `docs/HyperAlloc_IR.md` (Static values); `src/sublang/checks/data/SublangStringChecks.ems` |
| `Record` | Value record. Field read and write are for primitive fields. The gate also accepts `String` fields (see section 9, item 6). | `SublangBackendGate.ems` (`types`); `SublangMemoryChecks.ems` (U001) |
| `Class` | Scoped object. Fields may be `Int`, `Bool`, `Float`, `String`, an owned `Ref` child, or a `Bond` edge. A class with `Bond` fields must be built with `bond.new`. | `SublangBackendGate.ems` (`types`); `SublangMemoryChecks.ems` (T003) |
| `Ref<Class>` | Reference. Results must carry ownership information (T004). Reference returns must be `owned`. | `SublangOperationChecks.ems` (`checkResult`) |
| `List<E>` | Layout reached through `Ref<List>`. Element kinds: primitive, `String`, `Record` (contiguous value storage), and `Class` (owned on push, borrowed view on read). | `docs/HyperAlloc_IR.md` (Collections); `SublangCollectionChecks.ems` |
| `Bond<Class>` | Explicitly shared non-null handle. Bond graph fields may be value data, owned `Ref` children, or `Bond` edges. `Record`, `Class` and `List` fields are rejected. | `docs/HyperAlloc_IR.md` (Bond); `SublangBondChecks.ems` |

### 2.4 Operations

The verifier vocabulary (`src/sublang/vocabulary/SublangVocabulary.ems`, `isKnownOpcode`) defines the accepted opcodes. The table lists the release subset and its constraints.

| Group | Opcodes | Constraints | Source |
| --- | --- | --- | --- |
| Terminators | `return`, `branch`, `cond_branch`, `fail` | `cond_branch` takes a Bool condition and `trueArgs`-split arguments. `fail` takes no operands and names a failure action. `cond_branch` is lowered by the default path of `SublangLlvmControl.emit`. | `SublangControlChecks.ems`; `SublangLlvmControl.ems` |
| Constants | `const.bool`, `const.int`, `const.float`, `const.string` | `const.float` stores raw f64 bits. `const.string` is transport 2 only. | `SublangWire.ems`; `SublangLlvmScalar.ems` |
| Integer | `int.add`, `int.sub`, `int.mul`, `int.neg`, `int.div`, `int.rem` | Overflow is never implicit. add, sub, mul, neg and div take `trap` or `wrap`. rem takes `zero` or `trap`. A failure action is required for trapping overflow and for div and rem. | `SublangVocabulary.ems` (`allowsOverflow`); `SublangArithmeticChecks.ems` (`checkOverflow`) |
| Float | `float.add`, `float.sub`, `float.mul`, `float.div` | Float operands. The fp mode must be `rne` (round-to-nearest-even). | `SublangArithmeticChecks.ems` (`checkFloatMode`) |
| Compare | `compare` | Int: eq, ne, lt, le, gt, ge. Float: ordered (oeq, one, olt, ole, ogt, oge) or unordered (ueq, une, ult, ule, ugt, uge, ord, uno). Bool and references: eq and ne only. | `SublangVocabulary.ems`; `SublangArithmeticChecks.ems` (A003) |
| Records | `record.make`, `record.get`, `record.with` | Value semantics. `record.with` returns a new value. | `SublangMemoryChecks.ems`; `examples/ir/readme.md` |
| Classes and fields | `class.new`, `field.init`, `field.write`, `field.clear`, `field.has`, `field.take`, `field.read`, `field.borrow` | `field.read` and `field.write` are primitive only (U001). `field.borrow` is a read-only view of an owned reference field and aborts on an empty field. `field.take` needs a destination scope. | `SublangMemoryChecks.ems`; `docs/Sublang_Native_Slice.md` (Root field operations) |
| Scopes | `scope.begin`, `scope.end` | Scope ids are in 1..32768 (`scope.begin` ref). A scope end closes the innermost active scope. | `SublangControlChecks.ems`; `SublangBackendBudget.ems` |
| Calls | `call.direct` | Direct calls to body functions. A reference result must be `owned` with a destination scope. | `SublangControlChecks.ems` (T004); `docs/Sublang_Native_Slice.md` |
| Lists | `list.new`, `list.push`, `list.length`, `list.get`, `list.borrow`, `list.clear` | `Ref<List>` receiver. `list.get` is for non-class elements. `list.borrow` is for class elements. `list.push` of a class takes an owned argument. | `SublangCollectionChecks.ems` |
| Strings | `const.string`, `string.length`, `string.byte`, `string.equal` | String operands in `value` mode. `string.byte` takes an Int index. | `SublangStringChecks.ems` |
| Bond | `bond.new`, `bond.retain`, `bond.borrow`, `bond.get`, `bond.link`, `bond.own`, `bond.clear`, `bond.write` | `bond.own` consumes an exclusive `Ref` child. Bond edges use `borrow_read`. Mutation needs a mutable field. | `SublangBondChecks.ems` |

### 2.5 Ownership and passing forms

- Passing modes are `value`, `owned`, `borrow_read`, `borrow_write` and `init` (`SublangVocabulary.isKnownPassing`).
- Primitive, `Record` and `String` operands must use `value` mode (`SublangOperationChecks.ems`, `checkMode`).
- Reference and Bond parameters must be `borrow_read`, `borrow_write` or `owned` (`SublangBackendGate.ems`, `functions`).
- Reference returns transfer one fully initialized owned object. The caller names the destination scope and adopts the result (`docs/Sublang_Native_Slice.md`).
- Borrowed views (`field.borrow`, `list.borrow`, `bond.borrow`) are read-only. They cannot be stored as owned children, returned owned, mutated, or carried across a loop edge as independent references (`docs/HyperAlloc_IR.md`).
- Mutable alias arguments to a call are rejected. Duplicate owned or mutable arguments are rejected before consumption.
- Frontend `noescape` labels are ignored. Native lifetime and borrow proofs are computed (`docs/Sublang_Native_Slice.md`).

### 2.6 Flow families

| Family | Accepted use | Source |
| --- | --- | --- |
| Folded | Scalar replacement of class fields for proven primitive-field uses. No object storage. | `docs/Sublang_Native_Slice.md`; plan label in `src/sublang/hyperalloc/SublangFunctionMemoryPlan.ems` |
| Local | Verified nonescaping stack objects in entry allocations. | `docs/Sublang_Native_Slice.md`; plan label `Local: entry allocation` (same file) |
| Inline | Eligible class or value elements stored directly in list buffers. | `docs/HyperAlloc_IR.md`; plan label `Inline:` (same file) |
| Shard | Closed ownership graphs in per-invocation region frames, with nested joins. | `docs/HyperAlloc_IR.md` (Shard dependencies); plan label `Shard: closed ownership graph` |
| Pool | Reusable per-site frame slots, plus bounded exact-layout heap caches. | `docs/HyperAlloc_IR.md` (Pool and Root); plan label `Pool: reusable per-site frame slot` |
| Root | Exclusive owned reference fields with a 16-byte prefix, O(1) detach and adopt, iterative destruction. | `docs/HyperAlloc_IR.md`; plan label `Root: owned reference fields` |
| Bond | Counted shared roots and edges, trial-deletion cycle collection, revision-checked SCC cache. | `docs/HyperAlloc_IR.md` (Bond shared graphs); `src/sublang/backend/llvmbond/` |
| Static | Immutable String globals (`const.string`). | `docs/HyperAlloc_IR.md` (Static values) |

Two runtime fallback labels also appear in the plan: `ScopeOwned` (ownership transfer needing stable storage) and `Heap` (Flow disabled). Source: `SublangFunctionMemoryPlan.ems`.

`--flow=off` keeps ownership cleanup and disables only optional placement and cache strategies. `auto` and `on` currently select the same planning (`docs/Sublang_Wire.md`).

### 2.7 Gate order

`SublangCompiler.compile` runs these checks in order. The first failure stops compilation, and no LLVM text is produced.

1. Flow mode must be `auto`, `on` or `off` (`SUBLANG-B007`, `src/sublang/backend/SublangCompiler.ems`).
2. The module must be frozen (`B001`, `SublangBackendGate.ems`).
3. Resource budgets (`B003`, `B008`, `SublangBackendBudget.ems`; see section 5).
4. Generic verifier must be structurally valid with semantics status `valid` (`B002`).
5. Type gate: record and class field rules (`B004`).
6. Failure bindings must be `unbound` or `libc.abort` (`B004`).
7. Function definitions must be `body`. Reference parameter modes must be supported. Lifetime analysis must pass (`B004`, `B005`).
8. Entry, if any, must be `() -> i64` (`B006`).

The generic verifier still reports effects and lifetime as `not_checked`. Native readiness applies only to this subset (`docs/Sublang_Native_Slice.md`).

### 2.8 Not accepted

These inputs are rejected with a diagnostic. None is silently ignored.

- Calling conventions other than `sublang` (U003).
- Failure behaviors other than `abort`, continuing failures (F003) and unwinding models other than `none` (U005).
- Failure bindings other than `unbound` or `libc.abort` (B004).
- Nullable references (U001).
- Floating-point modes other than `rne` (A003).
- Field read and write on non-primitive fields (U001).
- External function definitions (`contract`) (B004).
- Arbitrary bidirectional Root and Bond conversion, weak references, finalizers and threads (`docs/HyperAlloc_IR.md`).

## 3. Runtime semantics

Everything in this section is as implemented in the native backend.

**Integers.** `Int` is signed i64. In `trap` mode, add, sub, mul and neg use LLVM overflow intrinsics and call `abort` on overflow (`src/sublang/backend/llvm/SublangLlvmRuntime.ems`). In `wrap` mode they wrap. A division by zero always aborts. For `MIN / -1`, `trap` aborts and `wrap` returns `MIN`. For `MIN % -1`, `trap` aborts and `zero` returns 0. A remainder by zero aborts. These paths are tested in `scripts/sublang-backend-sandbox.sh` (overflow cases, including a discarded result that still aborts; `MIN` remainder `-1` with zero mode returns 0).

**Floats.** `Float` is IEEE binary64 with round-to-nearest-even. Operations use LLVM constrained intrinsics with `fpexcept.ignore`. Constants are raw bits. Comparisons name an ordered or unordered predicate. Optimind performs no Float reassociation or host arithmetic folding (`docs/Sublang_Wire.md`).

**Bool.** Constants and `eq`/`ne` comparisons only.

**Strings.** A static `String` is `{ pointer, i64 byteLength }`. `string.length` returns the byte length. `string.byte` is bounds-checked and aborts when out of range (`src/sublang/backend/llvmdata/SublangLlvmStrings.ems`). `string.equal` compares lengths and then bytes. The empty string never dereferences its pointer. UTF-8 bytes are preserved and indexing does not decode code points. There is no concatenation, builder or dynamic string allocation (`docs/HyperAlloc_IR.md`). A string literal is one Wire token, so it is limited to 65,536 bytes (section 5).

**Lists.** A `List` owns its buffer. Length and capacity are i32. `list.length` returns an i64. The first allocation has capacity 8, then capacity doubles. Capacity is capped at 2,147,483,647 elements. Pushing at that limit aborts. A byte-size overflow or a `realloc` failure aborts without publishing a null buffer. `list.get`, `list.borrow` and the internal index check compare the index as unsigned against the length and abort when out of range (`src/sublang/backend/llvmdata/SublangLlvmListRuntime.ems`, `SublangLlvmLists.ems`). `list.clear` destroys owned elements and sets the length to 0 (`SublangLlvmLists.ems`). Views are invalidated by push, clear, mutable calls and scope cleanup.

**Objects and ownership.** `scope.end` releases the owned roots of that scope (`docs/Sublang_Native_Slice.md`). Iterative destruction is used for deep Root and Bond structures (`docs/HyperAlloc_IR.md`). No destructor or finalizer order is defined. Ownership errors such as use after move, double initialization and missing cleanup are compile-time rejections, not runtime behavior (`docs/Sublang_Native_Slice.md`). Runtime aborts on empty access: `field.take` and `bond.get` of an empty field abort, and `field.borrow` of an empty field aborts (`SublangLlvmMemory.ems`, `docs/HyperAlloc_IR.md`).

**Failures.** Every accepted failure action has behavior `abort`, is `noreturn`, does not continue, and has unwinding model `none`. A `fail` operation lowers to a call to libc `abort()` (`src/sublang/backend/llvm/SublangLlvmControl.ems`). Both accepted bindings (`unbound` and `libc.abort`) lower to the same abort call. Allocation returning null aborts (`sublang.allocate`). A Flow size that overflows with its 16-byte prefix aborts. An abort terminates the process. No exception cleanup is claimed (`docs/Sublang_Native_Slice.md`). In the overflow cases of `scripts/sublang-backend-sandbox.sh`, stdout is empty.

**Program output.** When the module has an entry, the generated `main` calls the entry, flushes the Pool caches, prints the `i64` result with `printf("%lld\n")`, and returns 0 (`SublangLlvmEmitter.ems`, `entry`). A module without an entry emits no `main`.

**Determinism.** Wire diagnostics report a byte offset (`SUBLANG-W001 at byte N`). Backend diagnostics are text, and only the first error is reported (`docs/Sublang_Native_Slice.md`). The packaging smoke test compiles the same `.ll` twice and requires byte-identical output (`scripts/sublang-package-smoke.sh`). That test was not rerun for this document (section 9, item 10).

### 3.1 Diagnostics and exit codes

`sublang emit-llvm` exit codes (`src/sublang/cli/SublangCommand.ems`):

| Exit | Meaning | Codes |
| --- | --- | --- |
| 0 | Success. `OUTPUT.ll` and `OUTPUT.ll.plan` are written. | none |
| 1 | Invalid Wire input, backend rejection or write failure. | `SUBLANG-W001`, `SUBLANG-B0xx`, `SUBLANG-CLI003` |
| 2 | Command-line or input error. | `SUBLANG-CLI001` (Optimind), `SUBLANG-CLI002` (input file) |

Launcher exit codes come from `scripts/sublang-build.sh`: 2 for invalid arguments or unsupported extensions, and 1 for a missing exported artifact.

Code families (`SublangVocabulary.dimensionOf`: `S` and `T` are structure; the rest are semantics):

| Prefix | Meaning (examples from source) |
| --- | --- |
| `SUBLANG-W` | Wire transport: malformed input, limits, feature or version mismatch |
| `SUBLANG-CLI` | Command-line, input-size and output errors |
| `SUBLANG-B` | Backend gate: frozen input, verifier, budgets, bindings, lifetime, entry, Flow mode, duplicate operation ids |
| `SUBLANG-S` | Structure: unknown opcode or passing mode (S001), invalid span or reference (S002), scope (S003), operand and mode arity (S005) |
| `SUBLANG-T` | Types and ownership: type mismatch (T001), mode or type (T002), class, bond and list rules (T003), ownership (T004) |
| `SUBLANG-A` | Arithmetic: missing mode (A001), missing failure action (A002), unsupported mode or predicate (A003) |
| `SUBLANG-E` | Effect and alias facts: references to missing summaries or locations, or invalid evidence |
| `SUBLANG-F` | Failure actions: abort signature other than `noreturn void()` (F002), continuing action (F003) |
| `SUBLANG-P` | Semantic profiles and function profiles |
| `SUBLANG-U` | Unsupported features in v0.1: nullable references, non-primitive field access, calling conventions, failure behavior and unwinding |

The CLI prints the `SUBLANG-W`, `SUBLANG-CLI` and `SUBLANG-B` codes that its own code path produces. A verifier or check failure reaches the CLI as `SUBLANG-B002: <code> <message> (line L, column C)` for the first finding only, where `<code>` is the verifier's own `S`, `T`, `A`, `E`, `U`, `F` or `P` code (`src/sublang/backend/SublangBackendGate.ems`; verified for an unknown opcode by `scripts/sublang-tiny-check.sh`). Later findings, the entity and blockers are not printed.

## 4. Compatibility matrix

Status: **V** means verified in the repository or in a recorded artifact. **U** means `UNVERIFIED:`.

| Axis | Release value | Evidence | Status |
| --- | --- | --- | --- |
| Transport, writer | Wire 2 (`transport-version=2`) | `src/sublang/wire/SublangWire.ems`; `capabilities`: `wire.write=2` | V |
| Transport, reader | Reads 1 and 2 (`capabilities`: `wire.read=1,2`; `--version`: `reads 1/2`). Transport 1 is the v1 core compatibility input. | `src/sublang/cli/SublangCommand.ems` | V (see section 9, item 11) |
| IR schema | 1 (`ir.schema=1`; header `IR-schema=1`) | `SublangVocabulary.ems` (`schemaVersion`); `SublangCommand.ems` | V |
| IR stage and revision | High, revision 1 | `SublangWire.ems` (`transfer`); `capabilities`: `ir.stage=High` | V |
| Architecture contracts | v0.4 | Title of `docs/Sublang_IR_Contracts.md`, which states that it is required architecture, not an implementation claim | V (document) |
| Profile | `core.native64.v2` (v1 with transport 1: `core.native64.v1`) | `SublangWire.ems` (`features`); `capabilities`: `feature=core.native64.v1`, `feature=core.native64.v2` | V |
| Target and provider | `native64-host-libc`; `provider=none` | `capabilities` output | V |
| CLI | `Sublang 0.1-dev` | `--version`; `capabilities` (`compiler=Sublang 0.1-dev`); `dist/sublang-0.1-dev/MANIFEST.txt` (`sublang-version`) | V |
| Flow modes | `auto`, `on`, `off` (launcher default `auto`) | `SublangOptions.ems` (`isValid`); `capabilities` (`flow=auto,on,off`); `scripts/sublang-build.sh` | V |
| Optimind | `on`, `off` (launcher default `on`) | `capabilities` (`optimind=on,off`); `scripts/sublang-build.sh` | V |
| LLVM tools | llvm-as and opt 22.1.8 | `dist/sublang-0.1-dev/MANIFEST.txt` (`llvm-as=`, `opt=`, probed inside the sandbox) | V (for the packaged sandbox) |
| Clang | 22.1.8 | `build/c-points.plan` line 2; `dist/sublang-0.1-dev/MANIFEST.txt` (`clang=`) | V |
| Sandbox image | `emerald-selfhost-sandbox` (default; overridable with `SUBLANG_SANDBOX_IMAGE`) | `scripts/*.sh` (`IMAGE` default); manifest `sandbox-image-ref` | V (name) |
| Sandbox image ID | `sha256:3fcb7043100ee7c63153a57ad336feeb35b6a47f2f9b8286e05df4958265e354` at package time | `dist/sublang-0.1-dev/MANIFEST.txt` (`sandbox-image-id`) | V (at package time); U (current local image) |
| Sandbox architecture | x86_64 | `dist/sublang-0.1-dev/MANIFEST.txt` (`arch=x86_64`, probed in the sandbox) | V (at package time) |
| glibc | 2.44 | `dist/sublang-0.1-dev/MANIFEST.txt` (`glibc=glibc 2.44`, probed in the sandbox) | V (at package time) |
| Docker host | 29.8.1 | Reported in section 9, item 1 by a later edit to this file. This agent did not run Docker and did not re-check the version. | U (reported, not re-checked here) |
| Emerald compiler | not pinned | `scripts/sublang-bootstrap.sh` uses `emerald-stable/emerald-compiler` under `SUBLANG_EMERALD_ROOT` | U (version) |

The repository does not pin any of these versions. The Roadmap item "Pin/record compatible LLVM/Clang and sandbox-image versions" is still open (`docs/Roadmap.md` section 1, "Binary packaging and reproducibility").

## 5. Resource budgets

All limits are enforced at the point cited. A violation is an error with no LLVM output, except where marked as a runtime abort.

### 5.1 Wire reader and writer

| Limit | Value | Source |
| --- | --- | --- |
| Input file size (CLI) | 16 MiB (16,777,216 bytes) | `SublangCommand.ems` (`SUBLANG-CLI002`) |
| Input text | 16 MiB | `SublangWireStream.ems` constructor |
| Writer output | 16 MiB | `SublangWireStream.ems` (`text`) |
| Token | 65,536 bytes; at most 5 length digits | `SublangWireStream.ems` (`text`, `readToken`, `payload`) |
| Total counted entries, all tables | 262,144 | `SublangWireStream.ems` (`count`) |
| Required features | At most 32 declared; only the core feature is accepted | `SublangWire.ems` (`features`) |
| Sources | 4,096 | `SublangWireTables.ems` (`sources`) |
| Source spans | 32,768 | `SublangWireTables.ems` (`sources`) |
| Types | 508 non-primitive, plus 4 implicit primitives (512 type ids) | `SublangWireTables.ems` (`types`) |
| Fields | 512 | `SublangWireTables.ems` (`fields`) |
| Profiles and failure actions | 512 each | `SublangWireTables.ems` |
| Locations, alias facts, effect summaries | 4,096 each; effect facts per summary 512 | `SublangWireEffects.ems` |
| Functions | 32 | `SublangWireBody.ems` (`functions`) |
| Values per function | 4,096 | `SublangWireBody.ems` (`values`) |
| Parameters per function | 4,096 | `SublangWireBody.ems` (`params`) |
| Blocks per function | 64 | `SublangWireBody.ems` (`blocks`) |
| Block parameters | 4,096 | `SublangWireBody.ems` (`blocks`) |
| Operations per block | 4,096 | `SublangWireBody.ems` (`operations`) |
| Operands per operation | 4,096 | `SublangWireBody.ems` (`arguments`) |
| Targets per operation | 2 | `SublangWireBody.ems` (`arguments`) |

### 5.2 Backend gate

| Limit | Value | Source |
| --- | --- | --- |
| Functions | 32 | `SublangBackendBudget.ems`, `check` (`B003`) |
| Types (including primitives) | 512 | `SublangBackendBudget.ems`, `check` (`B003`) |
| Fields | 512 | `SublangBackendBudget.ems`, `check` (`B003`) |
| Blocks per function | 64 | `SublangBackendBudget.ems`, `checkFunction` (`B003`) |
| Values per function | 4,096 | `SublangBackendBudget.ems`, `checkFunction` (`B003`) |
| Operations per block | 4,096 | `SublangBackendBudget.ems`, `checkFunction` (`B003`) |
| Operations per module | 32,768 | `SublangBackendBudget.ems`, `operation` (`B003`) |
| Operation id | Unique, 1 to 32,768 (`B008` if duplicate) | `SublangBackendBudget.ems`, `operation` |
| Scope id | 0 to 32,768; `scope.begin` ref 1 to 32,768 | `SublangBackendBudget.ems`, `checkFunction` |
| Lifetime analysis: distinct receiver and field pairs | 512 per function | `src/sublang/hyperalloc/SublangLocalLifetime.ems` (line 38) |
| Lifetime analysis: fixed-point rounds | 16,384 | `SublangLocalLifetime.ems` (line 49) |

### 5.3 Runtime and Flow

| Limit | Value | Source |
| --- | --- | --- |
| List length and capacity | 2,147,483,647 elements (i32); minimum capacity 8 | `src/sublang/backend/llvmdata/SublangLlvmListRuntime.ems` |
| Pool heap cache | 8 blocks per layout; 1,048,576 bytes (1 MiB) total per module | `src/sublang/backend/llvmflow/SublangLlvmPoolRuntime.ems` (line 39) |
| Bond SCC cache | Cache used for components with at least 64 members | `src/sublang/backend/llvmbond/SublangLlvmBondCache.ems` (line 34) |
| Shard default chunk payload | 4,096 bytes; larger requests get an exact-size chunk | `src/sublang/backend/llvmflow/SublangLlvmShardRuntime.ems` (line 23) |
| Flow allocation prefix | 16 bytes; sizes that overflow with the prefix abort | `src/sublang/backend/llvmflow/SublangLlvmFlowRuntime.ems` |

### 5.4 Sandbox and timeouts

Every compiler and program execution runs in this container profile (`scripts/sublang-bootstrap.sh`, `sublang-build.sh`, `sublang-backend-sandbox.sh`, `check-sandbox.sh`, `sublang-package.sh`, `sublang-package-smoke.sh`):

| Setting | Value |
| --- | --- |
| RAM | `--memory=6000000000` (6,000,000,000 bytes) |
| RAM plus swap | `--memory-swap=6000000000`; no swap |
| CPUs | `--cpus=2` |
| Processes | `--pids-limit=128` |
| Network | `--network=none` |
| Root filesystem | `--read-only` |
| Capabilities | `--cap-drop=ALL`, `--security-opt=no-new-privileges` |
| Core dumps | `--ulimit core=0` |
| `/tmp` | tmpfs, `exec`, 1,073,741,824 bytes |

Timeouts, from the scripts:

| Step | Limit | Source |
| --- | --- | --- |
| Bootstrap container | 240 s (kill after 5 s) | `scripts/sublang-bootstrap.sh` |
| Build container | 300 s (kill after 5 s) | `scripts/sublang-build.sh` |
| Backend checks container | 300 s | `scripts/sublang-backend-sandbox.sh` |
| Check-sandbox container | 420 s | `scripts/check-sandbox.sh` |
| Package probe and smoke container | 120 s (probe), 300 s (smoke) | `scripts/sublang-package.sh`, `scripts/sublang-package-smoke.sh` |
| C compile (Clang) | 120 s | `scripts/sublang-build-worker.sh` |
| Wire `emit-llvm` | 120 s | `scripts/sublang-build-worker.sh` |
| Builder Emerald compile | 180 s; builder driver 30 s | `scripts/sublang-build-worker.sh` |
| Compiled program run (`--run`) | 20 s | `scripts/sublang-build-worker.sh` |
| Backend checks: compile and generator | 180 s and 20 s | `scripts/sublang-backend-sandbox.sh` |
| Backend checks: each emitted binary | 10 s | `scripts/sublang-backend-sandbox.sh` |

The roadmap sets an upper bound of 8 GB for compiler and program execution and prefers the 6 GB configuration (`docs/Roadmap.md`, section 8). Do not run worker scripts directly on the host (`scripts/sublang-build.sh`).

## 6. Supported inputs versus illustrative examples

| Path | Class | Use | Status |
| --- | --- | --- | --- |
| `examples/wire/*.sublang-wire` (11 files) | Supported input | Compiled through `sublang-build.sh`. `arithmetic.sublang-wire` is used by the backend checks (`sublang-backend-sandbox.sh`). `bond-component.sublang-wire` is used by the package smoke test. All are measured by `sublang-measure.sh`. | Supported |
| `examples/wire/readme.md` | Documentation | Explains the wire examples and expected outputs. | Documentation |
| `examples/programs/root-tree.ems` | Supported builder input | Requires the Emerald toolchain (section 7). | Supported (builder) |
| `examples/programs/c/points.c`, `point.h` | Supported C input | Clang path. `--flow=on` is rejected. | Supported (C) |
| `examples/ir/01-arithmetic.sublang` to `07-failure.sublang` (7 files) | Readable dump | Generated by `SublangExamples.ems`. No parser. | Not an input |
| `examples/ir/v0.4/*.sublang-ir` (10 files), `managed-illustrative.ll`, `Archiv.zip` | Illustrative extension proposal | Architecture examples. No parser. | Not an input |
| `examples/ir/extended-ir.md`, `examples/ir/verification.txt`, `examples/ir/readme.md`, `examples/ir/v0.4/readme.md` | Documentation | Explains the examples and their status. | Documentation |
| `sublang dump FILE` output | Rendering | Read-only rendering of a decoded Wire file. Not an input format. | Not an input |
| `archive/` | Archived | Inactive collector-integration material. | Not supported |

`docs/Sublang_Wire.md` and `examples/ir/readme.md` state that `.sublang` dumps and `.sublang-ir` files are not parser inputs. The only file input for the release is `.sublang-wire`, plus the builder and C entries above.

## 7. Distribution prerequisites

The two steps are independent. The first needs Emerald once, and the rest needs only Docker and an image with LLVM tools.

### 7.1 Build `build/sublang` (needs the Emerald toolchain)

- Docker, and the sandbox image (`SUBLANG_SANDBOX_IMAGE`, default `emerald-selfhost-sandbox`).
- An Emerald checkout at `SUBLANG_EMERALD_ROOT` (default `../Emerald LLVM` relative to the repository). It must contain `emerald-stable/emerald-compiler` and `stdlib` (`scripts/check-sandbox.sh`).
- The image must provide the LLVM library named by the bootstrap environment: `EMERALD_LLVM_LIB_DIR=/usr/lib` and `EMERALD_LLVM_LIBRARY=LLVM` (`scripts/sublang-bootstrap.sh`).
- Command: `bash scripts/sublang-bootstrap.sh`. It compiles `src/SublangMain.ems` in the sandbox, runs `--version`, and moves the result to `build/sublang`.
- The Emerald toolchain is mounted read-only only for this step.

Emerald version: `UNVERIFIED:` the repository does not record the Emerald compiler or LLVM library version.

### 7.2 Compile Wire to native (no Emerald needed)

- Host: bash, Docker, `realpath`, `mktemp`, and an executable `build/sublang` (`scripts/sublang-build.sh` checks `-x build/sublang`).
- Image: `sh`, `timeout`, coreutils (`mkdir`, `cp`, `mv`, `test`), `llvm-as`, `opt`, and `clang` with a working linker. `lli` is used only by the backend checks, not by a wire build.
- The wire branch mounts only the repository (read-only), the input (read-only) and an empty export directory. It does not mount Emerald (`scripts/sublang-build.sh`, `MOUNTS` logic).
- Tested versions recorded in the package manifest: clang, llvm-as and opt 22.1.8 (section 4).

### 7.3 Builder and C entries

- Builder `.ems` input mounts the Emerald toolchain read-only and needs the Emerald compiler at build time (`scripts/sublang-build.sh`, builder branch).
- C input mounts only its source directory. It needs Clang in the image. No Emerald mount is needed (`docs/Sublang_C_Support.md`).

### 7.4 Packaging

- `scripts/sublang-package.sh` copies an existing `build/sublang` into `dist/sublang-<version>/` with `examples/wire`, writes `MANIFEST.txt` and `SHA256SUMS`, and produces a deterministic tarball. It never bootstraps. It requires a git commit.
- The probe inside the sandbox records the binary's SHA-256, its linkage, the Clang, llvm-as and opt versions, glibc and architecture.
- `scripts/sublang-package-smoke.sh dist/sublang-<version>` checks the checksums, compiles `bond-component.sublang-wire` twice (requires byte-identical `.ll`), and runs the native program (expected output `4242`).
- The packaged binary links dynamically against the sandbox's libc (`sublang-linkage` in the manifest).
- Current state: `dist/sublang-0.1-dev/` exists. Its manifest records git commit `7d4d47a` with `git-dirty=true`. Its binary hash (`fcd07a0b...`) differs from the current `build/sublang`. The current binary was written at 00:57, after the package at 00:56, by the final steps of `scripts/sublang-backend-sandbox.sh`, which moves its staged binary to `build/sublang` and its staged wire files to `build/ir` (file timestamps; section 9, item 12). Repackage before any release claim.

## 8. Frontend developer checklist

- [ ] Install Docker and the sandbox image, and build `build/sublang` (section 7.1).
- [ ] Record `build/sublang --version` and `build/sublang capabilities` with each build. Their output is the release identity (section 4).
- [ ] Start from `examples/wire/*.sublang-wire`. Use `build/sublang dump FILE` to read them. This command is read-only.
- [ ] Write the Wire header exactly as in section 2.2: transport 2, schema 1, `High`, revision 1, one core feature, module name, entry id.
- [ ] Use only the accepted opcodes, types and passing modes in section 2. Reject anything else in your frontend.
- [ ] Name a failure action on every trapping operation (`libc.abort` or `unbound`). Use `trap` or `wrap` for integer overflow explicitly.
- [ ] Give every reference result an owner and every owned call a destination scope.
- [ ] Use an ordered or unordered predicate for every Float comparison. Use fp mode `rne`.
- [ ] Keep the module inside the budgets in section 5.
- [ ] Build and run: `bash scripts/sublang-build.sh YOUR.sublang-wire -o build/YOUR --flow=auto --optimind=on --llvm-opt=2 --run`. Expect a decimal integer on stdout.
- [ ] Read rejections from the exit code and the `SUBLANG-` code family (section 3.1). Do not rely on internals.

Completion criterion, from `docs/Roadmap.md` section 1: another frontend developer can install and use a pinned compiler version, produce an accepted input, and understand rejection without reading undocumented internals.

Status against the criterion: **not met yet**. No compiler version is pinned (section 4). Diagnostics are text, and their exact messages are only in the source (section 3.1). Items marked `UNVERIFIED:` below remain open.

## 9. UNVERIFIED items and discrepancies

1. Verified 2026-10-11: the development host reports Docker 29.8.1 (`docker --version`). The repository itself does not pin a Docker version.
2. Verified 2026-10-11: the local image `emerald-selfhost-sandbox` has ID `sha256:3fcb7043100e...` and, queried inside the capped sandbox, clang/LLVM 22.1.8, glibc 2.44, x86_64 (recorded in the generated package manifest).
3. `UNVERIFIED:` The Emerald compiler and LLVM library versions used by bootstrap are not recorded.
4. `UNVERIFIED:` `emerald-selfhost-sandbox` may or may not be built from `Emerald LLVM/docker/Dockerfile.selfhost`. That Dockerfile starts `FROM archlinux:latest`, which is not pinned.
5. `UNVERIFIED:` Float division by zero yields the IEEE result without aborting. This follows from the emitted `fpexcept.ignore` intrinsic. No sandbox case tests it.
6. `UNVERIFIED:` Records with `String` fields. The gate (`SublangBackendGate.ems`, `types`) accepts them, but `docs/Sublang_Native_Slice.md` documents primitive record fields only, and no runtime case was found.
7. `UNVERIFIED:` `list.clear` keeps capacity. `docs/HyperAlloc_IR.md` says it does, and the source sets length to 0. Capacity retention was not separately confirmed.
8. `UNVERIFIED:` The plan label for Static (`const.string`) explain records. `docs/Sublang_Native_Slice.md` says they exist, but the label text was not found in `src/`.
9. `UNVERIFIED:` Linking the output of a module with no entry (no `main` emitted). The launcher's link step was not exercised for this case.
10. Verified 2026-10-11: `scripts/sublang-backend-sandbox.sh` (all checks passed), the package smoke test (`scripts/sublang-package-smoke.sh`, output 4242, byte-identical `.ll`) and `scripts/sublang-tiny-check.sh` were rerun on this host.
11. Discrepancy: the task's "reads 1" is narrower than the code. `--version` reports `reads 1/2`, and `capabilities` reports `wire.read=1,2`. This document states the code behavior.
12. Discrepancy: `build/sublang` was rebuilt after packaging, and its hash differs from `dist/sublang-0.1-dev/sublang`. The package is not a release of the current build.
13. Not reviewed: while this document was written, the working tree also gained uncommitted edits to `docs/Roadmap.md`, `docs/Sublang_Wire.md` and `readme.md`, and untracked files `docs/Sublang_Diagnostics.md`, `docs/Sublang_Dynamic_Profile.md`, `docs/Sublang_Wire_Spec.md`, `docs/diagnostic-codes.tsv`, `examples/frontend/` and `scripts/sublang-tiny-check.sh`. None of them was used as a source for this contract. They may overlap with it and should be reconciled. Items 1, 2 and 10 above were written by a later edit to this file. This agent did not run Docker or the sandbox checks.
