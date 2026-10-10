# Native C entry point

Ordinary C source can now be built without a handwritten Sublang IR file:

```bash
bash scripts/sublang-build.sh examples/programs/c/points.c -o build/c-points --run
```

The implemented pipeline is:

```text
.c + local headers -> Clang -> LLVM IR -> LLVM verifier/optimizer -> native executable
```

Clang supplies parsing, preprocessing, C typing, ABI/layout and source-language
semantics. The build entry point orchestrates tools; it does not pretend to implement
a new C parser in Emerald. C compilation does not require the Emerald toolchain mount.
All compiler and optional native execution steps run inside the existing networkless,
read-only Docker sandbox with a hard 6,000,000,000-byte RAM/RAM+swap limit, no swap,
bounded CPU/pids and timeouts. The preinstalled image must contain compatible Clang,
llvm-as and opt versions. No tools are downloaded during a build.

## Current interface

- One `.c` translation unit, system headers/libc and relative headers inside its source
  directory. The directory is mounted read-only. Parent directories and custom external
  include paths are not mounted. Multiple source files and custom link libraries need
  a later build interface; they are not accepted silently.
- `--c-standard=c89|c99|c11|c17`, default c17.
- `--llvm-opt=0|1|2|3`, default 2, used by Clang and the explicit LLVM pipeline.
- `-o path` exports the native binary, Clang-produced `.ll`, final verified/optimized
  `.bc`, and `.plan` with frontend/tool version and effective capabilities.
- `--run` runs only inside the capped container, before exporting artifacts.

LLVM optimization follows C semantics. Sublang does not change C integer widths,
turn signed-overflow undefined behavior into checked arithmetic, or replace malloc/free.
The native target currently comes from the installed Linux toolchain, not a cross-target API.

## Optimind and HyperAlloc boundary

The High-IR Optimind passes currently require Sublang builder IR. They do not run on
C-imported LLVM. `--optimind=on` is recorded as requested but unavailable for this
frontend; the CLI and `.plan` state this explicitly. LLVM's own passes are controlled
independently by `--llvm-opt`, including when Optimind is off.

`--flow=off` retains C memory management. `--flow=auto` also retains it because there is
no established C ownership proof. `--flow=on` rejects with `SUBLANG-C001` before invoking
a compiler. Unknown pointer behavior is not a noescape guarantee. This is direct native
C support, not completed C-to-HyperAlloc migration or cross-language optimization.

## Integration layer still to implement

The proposed two-input design remains appropriate: High IR from semantic frontends and
LLVM/bitcode from Clang feed a common integration boundary, then compatible Optimind
and optional HyperAlloc transformations. The C branch above implements source ingestion
and native generation first. A substantive integration layer must still:

1. Import LLVM bodies, ABI, attributes, source locations and stable entity identities
   without inventing object/ownership semantics lost during lowering.
2. Derive alias, escape and effect summaries, distinguishing declarations, conservative
   assumptions and verified facts. Unknown external calls remain conservative.
3. Share verified summaries with Optimind and define safe mixed-module linking.
4. Enable individual Flow transformations only with proven lifetimes, allocation-family
   compatibility, pointer identity/layout and observable C behavior preserved.

These are implementation requirements, not existing analyses hidden behind the wrapper.
No foreign-GC adapter is introduced. Full arbitrary C memory management cannot be inferred
from types alone.

## Verification evidence — 2026-10-10

The example with a local struct header, 64-bit fields, malloc/free and libc output
produced 10000 with LLVM O2/Flow auto and LLVM O0/Flow off. Assembly and explicit LLVM
verification succeeded in both sandbox builds. The shared builder entry is checked with
the Root example (42). These checks establish basic source/native compatibility, not
C language-suite conformance or performance gains.
