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
sublang capabilities
```

`dump` decodes a Wire file and prints the deterministic text dump to standard
output (exit 1 for malformed input, 2 for a missing or oversized file); it does not
verify or compile. `capabilities` prints stable `key=value` lines (`wire.read`,
`wire.write`, `ir.schema`, `feature`, `target`, `provider`, `flow`, `optimind`,
`input.max-bytes`, `output`). The record-level encoding is specified in
[Wire specification](Sublang_Wire_Spec.md).

The last argument selects Optimind. Successful compilation writes LLVM and
`OUTPUT.ll.plan`. Exit codes: 0 success, 1 invalid IR/codegen/write failure,
2 command-line/input error. The sandbox build launcher additionally handles LLVM
optimization, native linking, optional execution and artifact export. The binary
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

The writer uses `core.native64.v2`. The reader also accepts transport 1 with
`core.native64.v1` for existing core modules. String/List/Bond types require v2.
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
6. `end`, followed by end of file.

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
