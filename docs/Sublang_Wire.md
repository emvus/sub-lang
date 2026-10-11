# Standalone compiler and IR transport

Implementation: Emerald only. `src/SublangMain.ems` builds a native `sublang`
executable. Invocation of that executable does not invoke an Emerald compiler,
import a frontend AST or execute source embedded in an IR file.

```sh
bash scripts/sublang-bootstrap.sh
bash scripts/sublang-build.sh program.sublang-wire -o build/program --flow=on --run
```

Bootstrap uses the readonly Emerald toolchain once. The file-build sandbox does
not mount Emerald. It runs the compiled Sublang executable, verifies and optimizes
its LLVM output, and links the native program. Both paths have a 6,000,000,000-byte
RAM/RAM+swap limit, no swap, no network, readonly inputs and time limits.

The executable process interface is:

```text
sublang --version
sublang emit-llvm INPUT OUTPUT.ll auto|on|off on|off
sublang dump INPUT
sublang dump-low INPUT auto|on|off on|off
sublang text-dump INPUT
sublang text-build INPUT.sublang-text OUTPUT.sublang-wire
sublang link OUTPUT PROVIDER CONSUMER [MORE...]
sublang capabilities
```

`dump` decodes a Wire file and prints the deterministic text dump to standard
output (exit 1 for malformed input, 2 for a missing or oversized file); it does not
verify or compile. `capabilities` prints stable `key=value` lines (`wire.read`,
`wire.write`, `ir.schema`, `feature`, `target`, `provider`, `flow`, `optimind`,
`input.max-bytes`, `output`). The record-level encoding is specified in
[Wire specification](Sublang_Wire_Spec.md). `capabilities` lists only the two core features; extension tokens are not listed.

`dump-low` runs the same pipeline as `emit-llvm`, writes nothing to disk and prints the Low IR dump ([Low IR](Sublang_Low_IR.md)). `text-dump` prints the canonical text of a Wire file without verifying it. `text-build` parses, verifies and freezes canonical text, then writes Wire ([Text IR](Sublang_Text_IR.md)). `link` merges each consumer into the provider, left to right, and verifies the merged module before writing it (Wire specification, section 13.5). Exit codes and input limits are in the [Release contract](Sublang_Release_Contract.md), sections 3.1 and 5.

The last argument selects Optimind. Successful compilation writes LLVM and
`OUTPUT.ll.plan`. Exit codes: 0 success, 1 invalid IR/codegen/write failure,
2 command-line/input error. The sandbox build launcher additionally handles LLVM
optimization, native linking, the output kinds, LTO, PGO, optional execution and artifact export (see Build launcher below). The binary
itself currently emits LLVM; it does not internally launch Clang or LLVM tools.

## Wire version 2, experimental (v1 input retained)

`.sublang-wire` is a byte-framed transport, separate from human-readable `.sublang`
builder dumps and illustrative `.sublang-ir` extension proposals. This development
version is not a promised permanent public ABI or a packed machine-word format.
Every scalar is a netstring: ASCII decimal byte length, `:`, the payload, `,`.
Names and messages retain UTF-8, punctuation and newlines without escaping.
Integer payloads are signed decimal Int64; booleans are `0` or `1`.

The authoritative symmetric codec is `src/sublang/wire/`. Header tokens are:

```text
SUBLANG-WIRE, transport-version=2, IR-schema=1, stage=High, revision=1,
required-feature-count, required-features..., module-name, entry-FunctionId
```

The writer declares `core.native64.v2` and each extension token the module uses
(see Extension features below). The reader also accepts transport 1 with
`core.native64.v1` for existing core modules; transport 1 takes no extension token. String/List/Bond types require v2.
Unknown/duplicate required features,
unsupported versions/stages/revisions and trailing bytes are rejected, rather
than ignored. Section tags and their counted records follow in this order:

1. `sources`: names; `spans`: source, line, column, synthetic origin.
2. `types`: descriptors after the four schema-defined primitives; `fields`:
   owner, name, type, mutability, span. Dense stable IDs are table ordinals.
3. `profiles`: complete integer/float/failure/unwinding contracts; `failures`:
   behavior, binding, ABI signature, continuation, unwinding and source span.
4. `locations`, `aliases`, `effects`: full metadata, provenance, proof labels,
   proof analysis/revision/dependencies and referenced locations.
5. `functions`: signature/profile/effect/linkage/convention/definition, dense
   SSA type table, original parameter IDs, blocks, block parameters and operations.
   Operations preserve every current attribute, operands, passing modes, targets,
   ownership, scope, failure action and raw f64 bits. V2 appends the byte-preserving
   `constText` scalar immediately after raw f64 bits; v1 has no such scalar.
6. `end`, followed by end of file. When `ext.oo.v1` is declared, a `dispatch` section comes after `functions` and before `end` (`SublangWire.transfer`; layout in the Wire specification, section 13.3).

Serialization preserves IDs, including non-contiguous signature parameter IDs;
it does not remap CFG references or rederive metadata from names. Implicit primitive
descriptors and nominal field order must match the schema on export. Opcode and
semantic acceptance remain the verifier/backend's responsibility after reading.
Transport success grants no ownership or effect proof. Imported `proven` metadata
does not authorize NoAlias or call elimination: those require actual analyses.

Budgets: 16 MiB per file, 64 KiB per token, 262,144 total counted entries; tighter
native function/type/field/block/value/operation limits also apply. Counts and
Int64 values are checked before multiplication, allocation or negation can overflow.
Malformed transport diagnostics include the byte offset (`SUBLANG-W001`).

The native v2 contracts for Static, Inline collections, dependent Shards, bounded
runtime Pool reuse and Bond cycles are specified in [HyperAlloc IR](HyperAlloc_IR.md).

## Closed-body optimizations and graph borrows

Optimind can evaluate constant scalar calls through bounded, nonrecursive,
single-block bodies. Any unknown operation, side effect, unsupported Float
evaluation or unproven arithmetic safety blocks evaluation. Calls whose arithmetic
would trap remain present even if a later operation discards their result.

A verified one-field read-only getter no longer forces a primitive-field class
temporary to have an address: Flow can keep its fields scalar and lower that
getter directly to the field slot. This is derived from the callee body, not a
frontend `pure`/`noescape` assertion.

`field.borrow` returns a read-only, nonowning Ref view of an owned reference field.
It checks for an empty field at runtime and aborts. The view cannot be initialized,
mutated, transferred, returned owned or used after an ancestor expires. Parent
mutation, ownership transfer and mutable calls invalidate dependent views;
CFG joins retain only definitely live views. Mutation/ownership call arguments
that share a borrow origin are rejected. This implements graph-field views;
collection element views and shared cyclic graphs remain separate work.

Pool additionally handles nonescaping fixed-layout parents with owned child graphs.
Their invocation-local slots retain a 16-byte nonheap ownership prefix. Reuse drops
the previous children before reattachment, and normal scope cleanup drops remaining
children without freeing frame storage. Both an outer scope covering the entire
loop and a separate scope per iteration are supported.

## Build launcher

```text
bash scripts/sublang-build.sh INPUT -o OUTPUT [--flow=auto|on|off] [--optimind=on|off]
    [--llvm-opt=0|1|2|3] [--c-standard=c89|c99|c11|c17] [--emit=exe|obj|bc|ll]
    [--lto=off|full|thin] [--pgo=off|train|use --profile=DIR] [--run]
```

INPUT is a `.sublang-wire` file, a `.c` file or a `.ems` builder. The launcher rejects any other extension.

- `--emit` (default `exe`). The launcher always exports `OUTPUT.ll`, `OUTPUT.bc`, `OUTPUT.plan` and `OUTPUT.config`. `exe` also exports the executable `OUTPUT`, and `obj` exports `OUTPUT.o` instead of an executable. `bc` and `ll` add no further file.
- `--lto` (default `off`). `full` passes `-flto` and `thin` passes `-flto=thin` to Clang for the program's module. This is single-module LTO. The chosen mode is recorded in `OUTPUT.config`.
- `--pgo=train` runs an instrumented build of the program once, then exports `OUTPUT.profdata` and `OUTPUT.profmeta`. `--pgo=use --profile=DIR` reads `DIR/program.profdata` and `DIR/program.profmeta`, so copy the training outputs to those names first, as `scripts/sublang-modes-check.sh` does. A profile whose metadata (IR hash, Clang version, target, `-O` level) does not match is rejected with `SUBLANG-PGO001` and a non-zero exit. A missing `program.profdata` is `SUBLANG-PGO002` (exit 2).
- `OUTPUT.config` records the emit, LTO, PGO and `-O` settings, the IR SHA-256, the Clang identity, the target and the EH runtime (`scripts/sublang-build-worker.sh`).

Launcher exit codes are 2 for invalid arguments and unsupported inputs. A non-zero status from the worker is returned unchanged (Release contract, section 3.1).

## Extension features

Four required-feature tokens extend the transport 2 record set: `ext.bytes.v1` (byte text and list replacement), `ext.numeric.v1` (exact numeric conversions), `ext.eh.v1` (`Int`-coded exceptions) and `ext.oo.v1` (single inheritance and closed-world dispatch). A token is declared exactly when the module uses it. Opcodes, verifier codes, lowering and evidence are in [Wire extensions](Sublang_Extensions.md). Record layouts are in the [Wire specification](Sublang_Wire_Spec.md), section 13.

## Canonical text

`text-dump` and `text-build` convert between Wire and the canonical text of [Text IR](Sublang_Text_IR.md). For transport 2 inputs the round trip is byte-identical. Transport 1 inputs come back as transport 2 with the same text. These properties are checked by `scripts/sublang-text-sandbox.sh`. `UNVERIFIED:` the result of that run was reported by the author and was not re-run for this document.
