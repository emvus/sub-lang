# Sublang

Sublang is a language-independent compiler platform implemented in **Emerald (.ems)**. It provides a typed IR, verification, Optimind transformations, optional HyperAlloc Flow memory planning and LLVM code generation. This is a separate repository from the Emerald compiler.

**Development status — October 11, 2026:** a bounded native64 pipeline works with all eight Flow strategy families, owned calls/returns, static strings, lists, dependent regions and shared cyclic graphs. This is a development compiler, not complete support for every proposed language feature or permanent public ABI.

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
| [Release contract](docs/Sublang_Release_Contract.md) | Accepted input, semantics, versions and budgets of the first release |
| [Diagnostics](docs/Sublang_Diagnostics.md) | Cataloged diagnostic codes and known inconsistencies |
| [Packaging](docs/Sublang_Packaging.md) | Reproducible package, manifest and smoke check |
| [Measurement](docs/Sublang_Measurement.md) | Sandboxed timing method and its non-comparable cases |
| [Dynamic profile](docs/Sublang_Dynamic_Profile.md) | Draft dynamic-language profile (not implemented) |
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

A canonical public Low IR is still planned. Current lowering emits LLVM from the accepted High IR and compilation-local memory plan.

The standalone process interface is:

```text
sublang --version
sublang emit-llvm INPUT.sublang-wire OUTPUT.ll auto|on|off on|off
sublang dump INPUT.sublang-wire
sublang capabilities
```

Its final arguments select Flow and Optimind. The binary emits LLVM and a plan; linking is performed by the launcher. Use sandboxed integration for all executions.

The current transport is experimental Wire v2, reading v1 too. Architecture version v0.4 and IR schema 1 are different version axes. Human-readable .sublang dumps and illustrative .sublang-ir files are not parser inputs.

## Language independence and semantic responsibility

A procedural language can use free functions and value records. An OO language can use Class/Ref/Bond contracts within the accepted subset. Dynamic AOT, closures, inheritance and virtual dispatch remain planned expansions.

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

--optimind=on|off controls these transformations. --llvm-opt=0|1|2|3 separately controls downstream LLVM passes. LTO/PGO, broader range/CFG propagation and effect-driven interprocedural passes remain roadmap items.

## Verification

Existing bundled correctness evidence covers LLVM verification/execution, native output checks and ASan/LeakSanitizer at memory boundaries, including 64-node Bond cache invalidation. These are not performance measurements.

For code changes requiring native checks:

```bash
bash scripts/sublang-backend-sandbox.sh
```

Keep checks focused on changed boundaries and execute compilers only inside the capped sandbox. Documentation-only changes do not require rebuilding the complete suite.

## Development direction

The [roadmap](docs/Roadmap.md) tracks release hardening, pass/revision APIs, public transport stabilization, broader Flow parity, Dynamic AOT and EH/OO extensions. Emerald remains an external toolchain and reference implementation; this work does not update its installed compilers.
