# Sublang

Sublang is a language-independent compiler platform implemented in **Emerald (.ems)**. It provides a typed IR, verification, Optimind transformations, optional HyperAlloc Flow memory planning and LLVM code generation. This is a separate repository from the Emerald compiler.

**Development status — October 11, 2026:** a bounded native64 pipeline works with all eight Flow strategy families, owned calls/returns, static strings, lists, dependent regions and shared cyclic graphs. Four opt-in Wire extensions add byte text, exact numeric conversions, `Int`-coded exceptions and closed-world objects with single inheritance. Function bodies are lowered through a verified Low IR. This is a development compiler, not complete support for every proposed language feature or permanent public ABI.

- **Optimind** is the general analysis/optimization engine. Existing transformations are implemented; a general versioned pass pipeline remains work in progress.
- **HyperAlloc Flow** is optional memory optimization and management. It includes ownership/lifetime analysis, allocation strategies and Bond cycle collection.
- **LLVM** remains the final backend.
- Implementation stays in Emerald. The neutral core does not require an Emerald AST.
- Foreign GC integration is archived and outside the active roadmap.

Repository: https://github.com/emvus/sub-lang

## Documentation

Start with the **[IR developer guide](docs/Sublang_IR_Guide.md)** for formats, complete builders, SSA/control flow, ownership, collections, Bond and frontend integration.

| Document | Purpose |
| --- | --- |
| [Roadmap](docs/Roadmap.md) | Remaining work, planned capabilities and optional ideas |
| [Wire and CLI](docs/Sublang_Wire.md) | Actual process boundary, encoding and limits |
| [Wire specification](docs/Sublang_Wire_Spec.md) | Record-level encoding for writers in other languages, with conformance cases |
| [Wire extensions](docs/Sublang_Extensions.md) | Opt-in Wire features: byte text, exact numerics, exceptions and closed-world objects |
| [Text IR](docs/Sublang_Text_IR.md) | Canonical text form, read and written by `text-dump` and `text-build` |
| [Low IR](docs/Sublang_Low_IR.md) | Verified intermediate for function bodies; not yet a public format |
| [Runtime IR](docs/Sublang_Runtime_IR.md) | Language-generated runtime bodies, joint Flow/Optimind compilation and platform boundaries |
| [Passes and effects](docs/Sublang_Passes_And_Effects.md) | Snapshots, the pass manager, derived effects and blockers |
| [Implementation plan](docs/Implementation_Plan.md) | Brief for the remaining work; a plan, not a completion claim |
| [Release contract](docs/Sublang_Release_Contract.md) | Accepted input, semantics, versions and budgets of the first release |
| [Diagnostics](docs/Sublang_Diagnostics.md) | Cataloged diagnostic codes and known inconsistencies |
| [Packaging](docs/Sublang_Packaging.md) | Reproducible package, manifest and smoke check |
| [Measurement](docs/Sublang_Measurement.md) | Sandboxed timing method and its non-comparable cases |
| [Dynamic profile](docs/Sublang_Dynamic_Profile.md) | Draft dynamic-language profile; a Dyn IR library is in progress |
| [HyperAlloc IR](docs/HyperAlloc_IR.md) | Exact executable memory contracts |
| [Flow parity](docs/Flow_Parity.md) | Original Flow comparison and remaining gaps |
| [Native Slice](docs/Sublang_Native_Slice.md) | Accepted native subset and evidence |
| [IR architecture contracts](docs/Sublang_IR_Contracts.md) | Broader effect/alias/pass/EH/Dynamic requirements |
| [Technical overview](docs/Sublang_Technical_Overview.md) | Platform design and intended value |
| [C support](docs/Sublang_C_Support.md) | Clang input path and missing ownership importer |

## Quick start

Run from the repository root. Docker and the locally available compatible image
emerald-selfhost-sandbox are prerequisites.

```bash
bash scripts/sublang-bootstrap.sh
bash scripts/sublang-build.sh examples/wire/bond-component.sublang-wire \
  -o build/bond-component --flow=on --optimind=on --llvm-opt=3 --run
```

Expected output: 4242. Bootstrap builds the standalone Sublang compiler once. Subsequent Wire builds do not mount or invoke the Emerald compiler.

The other commands use the same binary, `build/sublang`. `text-dump`, `text-build`, `link`, `dump` and `dump-low` only read and write files; they do not run generated programs:

```bash
build/sublang text-dump examples/wire/arithmetic.sublang-wire > arithmetic.txt
build/sublang text-build arithmetic.txt arithmetic.sublang-wire
build/sublang link linked.sublang-wire provider.sublang-wire consumer.sublang-wire
```

Output kinds, LTO and PGO are launcher options. This example uses the Tiny frontend (Python), and its first output line is 6000:

```bash
mkdir -p build
python3 -I examples/frontend/tiny/tiny.py examples/frontend/tiny/fib.tiny build/fib.sublang-wire
bash scripts/sublang-build.sh build/fib.sublang-wire -o build/fib --lto=thin --llvm-opt=2 --run
bash scripts/sublang-build.sh build/fib.sublang-wire -o build/fib-obj --emit=obj
bash scripts/sublang-build.sh build/fib.sublang-wire -o build/fib-train --pgo=train
```

`--emit=obj` exports `build/fib-obj.o` and no executable. `--pgo=train` exports `build/fib-train.profdata` and `.profmeta`; copy them to a directory as `program.profdata` and `program.profmeta` before `--pgo=use --profile=DIR`. Options are described in [Wire and CLI](docs/Sublang_Wire.md).

The commands of this section were not re-run while this readme was edited. The checks that exercise them are listed under Verification.

All compiler/generated-program runs use the supplied Docker sandbox: 6,000,000,000-byte RAM and RAM+swap limits, no additional swap, no network, readonly inputs and timeouts. Do not run the worker script directly on the host.

The launcher exports the native executable, frontend LLVM .ll, verified/optimized .bc and a .plan report beside the selected output path. Omit --run to build without executing.

An Emerald builder can also supply IR:

```bash
bash scripts/sublang-build.sh examples/programs/root-tree.ems \
  -o build/root-tree --flow=auto --run
```

Expected output: 42. This input defines SublangProgram.build(); it is not arbitrary Emerald source translated by a complete frontend.

Ordinary C uses a separate Clang/LLVM path:

```bash
bash scripts/sublang-build.sh examples/programs/c/points.c -o build/c-points --run
```

C currently retains C ABI and malloc/free semantics. High-IR Optimind/Flow are unavailable for this path; --flow=on is rejected rather than silently ignored.

Configure the external toolchain with SUBLANG_EMERALD_ROOT when it is not located at ../Emerald LLVM. SUBLANG_SANDBOX_IMAGE selects an existing compatible image.

## Repository layout

```text
src/SublangMain.ems         standalone Wire-to-LLVM CLI
src/sublang/               neutral IR, checks, Optimind, Flow and LLVM lowering
src/SublangHarness.ems     core IR harness
src/SublangBackendSmoke.ems native pipeline fixture generator
examples/programs/        actual builder and C inputs
examples/wire/            actual versioned IR inputs
examples/frontend/tiny/   independent second frontend (Python) that writes Wire
examples/ir/              readable dumps and labeled architecture proposals
scripts/                  capped build/check launchers
docs/                     usage, contracts, evidence and roadmap
archive/gc-integration/   inactive historical collector-integration proposals
```

## Frontend and binary integration

A frontend parses its own language, resolves names/types, specifies evaluation order and emits typed High IR plus explicit semantics. It can use the current Emerald builder or generate .sublang-wire in another implementation language.

```text
Language frontend -> typed High IR + semantic contracts
                  -> verification and closed-body analyses
                  -> Optimind + optional HyperAlloc memory plan
                  -> LLVM IR -> LLVM optimization/linking -> native program
```

Function bodies are lowered to a verified Low IR ([Low IR](docs/Sublang_Low_IR.md)). The runtime provider text is still legacy, and a public Low IR format is still planned.

The standalone process interface is:

```text
sublang --version
sublang emit-llvm INPUT.sublang-wire OUTPUT.ll auto|on|off on|off
sublang dump INPUT.sublang-wire
sublang dump-low INPUT.sublang-wire auto|on|off on|off
sublang text-dump INPUT.sublang-wire
sublang text-build INPUT.sublang-text OUTPUT.sublang-wire
sublang link OUTPUT.sublang-wire PROVIDER.sublang-wire CONSUMER.sublang-wire [MORE...]
sublang capabilities
```

Its final arguments select Flow and Optimind. The binary emits LLVM and a plan. The launcher performs LLVM optimization, native linking, LTO and PGO. Use sandboxed integration for all executions.

The current transport is experimental Wire v2, reading v1 too. Wire v2 declares the core token and the extension tokens `ext.bytes.v1`, `ext.numeric.v1`, `ext.eh.v1` and `ext.oo.v1`, each exactly when the module uses it ([Wire extensions](docs/Sublang_Extensions.md)). Canonical text (`.sublang-text`) is read by `text-build` only. Architecture version v0.4 and IR schema 1 are different version axes. Human-readable .sublang dumps and illustrative .sublang-ir files are not parser inputs.

## Language independence and semantic responsibility

A procedural language can use free functions and value records. An OO language can use Class/Ref/Bond contracts within the accepted subset, including single inheritance with closed-world virtual dispatch (`ext.oo.v1`). Dynamic AOT (in progress, see the dynamic profile), closures and interfaces remain planned expansions.

Source languages retain their arithmetic, identity, mutation and error rules. A configuration file alone cannot define every language. Frontends must implement real translation rules and reject unsupported semantics.

Effect summaries distinguish declared, conservative and proven facts. An imported purity/noescape/NoAlias assertion is not automatically an optimization proof. Unknown calls/effects require conservative handling or rejection at the current native boundary.

Externally visible layout, FFI, reflection, finalizers and object identity can prevent representation changes. The native backend currently targets its documented native64/host-libc contract; general runtime/target providers are not yet implemented.

## HyperAlloc Flow

All eight families have executable native paths:

| Family | Current use |
| --- | --- |
| Folded | Scalar replacement of suitable class fields |
| Local | Verified nonescaping stack objects |
| Inline | Eligible class/value elements directly in list buffers |
| Shard | Closed graphs in dependent nested regions |
| Pool | Reusable temporary slots and bounded exact-layout heap caches |
| Root | Stable exclusive graphs with iterative destruction |
| Bond | Shared roots/edges, local trial deletion and revision-checked SCC cache |
| Static | Immutable String globals |

HyperAlloc Flow does not require every allocation to use a collector. Ordinary ownership paths use scoped cleanup; Bond handles shared cyclic graphs. Shared objects pay additional metadata costs. Exact contracts and restrictions are in HyperAlloc IR.

The native --flow=off path preserves ownership/cleanup while disabling optional placement/cache optimizations. On and auto currently enable the same native High-IR planning. No foreign-GC integration mode is active.

Strategy coverage is not complete original-runtime or performance parity. Arbitrary bidirectional Root/Bond conversion, weak refs, threads and finalizers remain unsupported. No speed/RSS comparison is claimed from correctness tests.

## Optimind and build optimization

Existing Sublang transformations include safe Integer/Bool constant folding, selected arithmetic identities, bounded scalar constant-call evaluation and a closed-body getter path. Potential failures and side effects are preserved; Float reassociation/host arithmetic folding is not performed.

--optimind=on|off controls these transformations. --llvm-opt=0|1|2|3 separately controls downstream LLVM passes. `--lto` (single-module) and `--pgo` (train and use, with stale-profile rejection) are launcher options. Broader range/CFG propagation and effect-driven interprocedural passes remain roadmap items.

## Verification

Existing bundled correctness evidence covers LLVM verification/execution, native output checks and ASan/LeakSanitizer at memory boundaries, including 64-node Bond cache invalidation. These are not performance measurements.

For code changes requiring native checks:

```bash
bash scripts/sublang-backend-sandbox.sh
```

Other checks: `scripts/sublang-text-sandbox.sh` (text round trip), `scripts/sublang-modes-check.sh` (output kinds, LTO, PGO), `scripts/sublang-pass-sandbox.sh` (snapshots, passes, effects) and `scripts/sublang-tiny-check.sh` (Tiny frontend). `UNVERIFIED:` their results were reported by the author on 2026-10-11 and were not re-run for this readme.

Keep checks focused on changed boundaries and execute compilers only inside the capped sandbox. Documentation-only changes do not require rebuilding the complete suite.

## Not implemented

- Weak handles, finalizers and destructor hooks.
- Threads and shared concurrent Bond graphs (milestone M9).
- Bounded C ownership import from LLVM. C still goes through Clang unchanged, and `--flow=on` is rejected.
- Borrowed string slices. `text.slice` copies.
- Dynamic AOT beyond the numeric core. A Dyn IR library is in progress; see [Dynamic profile](docs/Sublang_Dynamic_Profile.md).
- Targets other than `native64-host-libc`.
- Cross-module LTO, and any speedup from LTO or PGO. The LTO check covers a single module.
- Any speed or RSS claim. The bundled inputs are correctness tests.

## Development direction

The [roadmap](docs/Roadmap.md) tracks release hardening, pass/revision APIs, public transport stabilization, broader Flow parity, Dynamic AOT and EH/OO extensions. Emerald remains an external toolchain and reference implementation; this work does not update its installed compilers.
