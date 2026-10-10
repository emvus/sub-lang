# Sublang / Optimind / HyperAlloc Flow naming migration

## Repository boundary and current status

Sublang is a separate checkout/repository at https://github.com/emvus/sub-lang. Its original remote commit 01f25358a9951fb20988eb8793f437fcfbb93499 contained LICENSE only; the license was preserved.

Implementation is Emerald .ems. No fused language or new source extension is introduced. Optimind names the general optimization engine; HyperAlloc Flow remains optional. Renaming did not redefine arithmetic, FP or ownership contracts.

This document records migration history. Earlier checks below describe their historical stages; current executable support is documented in [the IR guide](Sublang_IR_Guide.md) and [Flow parity](Flow_Parity.md).

## Canonical mapping

| Former name | Canonical name |
| --- | --- |
| EOS / Emerald Optimization System | Sublang |
| eos::* / Eos* | sublang::* / Sublang* |
| EOS-* diagnostics | SUBLANG-* |
| examples/eos and EOS documents | examples/ir and docs/Sublang_* |
| .eos dump / .eosir proposal | .sublang dump / .sublang-ir proposal |
| Emerald Flow | HyperAlloc Flow |
| emerald::compiler::flow | emerald::compiler::hyperallocflow |
| Flow* / NativeFlow* | HyperAllocFlow* / NativeHyperAllocFlow* |
| emerald_flow_* | hyperalloc_flow_* |
| EMERALD_FLOW_* | HYPERALLOC_FLOW_* |
| --explain-flow / --flow-strict | --explain-hyperalloc-flow / --hyperalloc-flow-strict |
| emerald.sh flow | emerald.sh hyperalloc-flow |
| General optimization engine | Optimind |

The Emerald-specific rows record the earlier naming migration, not a new Emerald update by the Sublang backend work. Historical binary/log/backup/stage0 data is not rewritten as active source.

.sublang and .sublang-ir name dumps/proposals, not a new source language. Current accepted serialized input is .sublang-wire. Proposed --sublang-flow/--sublang-memory platform flags are not the implemented CLI; the build launcher uses --flow and --optimind. The old hyperalloc-integration mode was archived on October 10, 2026.

## Separation from Emerald

The neutral core exists in Sublang/src/sublang. Emerald retains its frontend/compiler/stdlib and original runtime integration. Builder/bootstrap sandboxes mount repositories separately readonly. SUBLANG_EMERALD_ROOT selects the external toolchain; SUBLANG_SANDBOX_IMAGE selects the image. Wire builds do not need the Emerald mount after bootstrap.

The original Emerald C runtime was not copied in as Sublang's core implementation. The current neutral HyperAlloc runtime is emitted from Emerald sources within the documented native backend.

## Historical ABI compatibility work

Installed compilers could retain old runtime symbol names. The earlier Emerald migration therefore added portable legacy ABI forwarders to the same canonical allocator state, not a second runtime, plus an explicitly opt-in legacy header.

New environment variables took precedence, including explicit zero values; absent new settings permitted legacy fallback. Old CLI aliases remained narrowly supported while help used canonical names. Historical overview/source hashes retained provenance.

## Historical verification

The naming-stage Sublang check passed its five harness cases and seven structural/type/dominance examples in a capped 6 GB/no-swap/networkless run. At that stage lifetime was not_checked and codegenReady false. These are historical results, not the present native backend limitation.

A subsequent capped Emerald/runtime check reported:

- Canonical and legacy runtime symbols shared allocator state, with zero live/invalid-release counts after the cross-ABI case.
- The renamed Emerald compiler built from Main.ems using the stable toolchain.
- Its temporary build compiled an i64 example with --explain-hyperalloc-flow and output 4000000000.
- The retained --explain-flow alias produced the same output.

No multistage selfhost determinism or new performance result was established. Installed compilers were not replaced.

## Backup provenance

The earlier rename snapshot was saved at /tmp/sublang-before-naming-migration.tar. The older full project backup remains outside the working project. This record does not imply that temporary backup paths remain available indefinitely.
