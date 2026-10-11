# Runtime IR

Runtime IR lets a language compiler supply the **implementation** of its runtime as
Sublang IR, rather than just declarations calling a C implementation. Runtime bodies
and the program are bound before Optimind, HyperAlloc Flow and LLVM lowering. Their
calls, effects and ownership are analyzed together; runtime functions receive no
privileged exemption from lifetime checks.

## Implemented first slice

`runtime.bodies.v1` uses existing High IR and Wire bodies, not a second instruction set
or a new Wire record encoding. The runtime defines ordinary functions. The program
declares matching external contracts. The existing linker resolves those imports by
name, signature, semantic and type-layout rules. The runtime library must be
self-contained and have no executable entry; both snapshots must be frozen.

```sh
sublang runtime-emit runtime.sublang-wire program.sublang-wire combined.ll \
  portable x86_64-unknown-linux-gnu on on
```

The four trailing arguments are runtime target (`portable` or its exact triple),
destination triple, Flow mode (`auto|on|off`) and Optimind (`on|off`). Output is LLVM IR
plus `combined.ll.plan`. Native LLVM linking/execution is a separate step. Run compiler
commands only inside the capped development sandbox. Rebuild the core before using
this new command: previously exported binaries and bundles do not update automatically.
The distribution driver delegates core commands, but `build --runtime` is not implemented.

Each Wire input retains the 16 MiB CLI limit. Existing backend budgets, verification,
linking and verification of the combined compilation apply. `capabilities` reports the
runtime path, implemented codegen target and absent platform bindings.

For an Emerald frontend the API is `SublangRuntimeUnit(name, 1, target, frozenLibrary)`
and `SublangRuntimeCompiler.compile(unit, frozenProgram, destination, optimind, flow)`.
`src/SublangRuntimeSmoke.ems` supplies a complete executable integration example using
owned-object provider/consumer fixtures. Other frontends write Wire instead of using
Emerald's internal classes as a public ABI.

## Memory and portability

Runtime bodies retain ordinary SSA, effects, semantic profiles, source locations and
ownership. Owned calls remain transfers after linking. Flow is optional; disabling it
does not erase mandatory cleanup. Runtime implementation requires no C source, but
**the existing backend still calls its host-libc helpers**, including allocation and
failure handling. This slice does not provide libc independence or OS functions.

`portable` declares target-independent High IR bodies. It is not a native ABI promise.
Native handles, pointers, platform structures and calling conventions require explicit
target-specific bindings. Unresolved platform imports are rejected in this slice.

## Required platforms and current target identities

Linux, Windows and macOS are required families for the completed Runtime IR system.
Architecture is part of the destination identity.

| Triple | Format | Pointer bits | Native C long bits | Status |
| --- | --- | --- | --- | --- |
| `x86_64-unknown-linux-gnu` | ELF | 64 | 64 | Runtime-body native compilation |
| `aarch64-unknown-linux-gnu` | ELF | 64 | 64 | Recognized; codegen unavailable |
| `x86_64-pc-windows-msvc` | COFF | 64 | 32 | Recognized; codegen unavailable |
| `aarch64-pc-windows-msvc` | COFF | 64 | 32 | Recognized; codegen unavailable |
| `x86_64-apple-darwin` | Mach-O | 64 | 64 | Recognized; codegen unavailable |
| `arm64-apple-darwin` | Mach-O | 64 | 64 | Recognized; codegen unavailable |

Descriptors are initial ABI identities, not complete calling-convention, deployment
version, SDK or aggregate ABI implementations. Native long is separate from Int64.
Unavailable destinations fail explicitly; they never silently compile for Linux.

## Next implementation steps

1. Typed platform imports with effect/alias/ownership contracts, error behavior,
   blocking and synchronization. Arbitrary external names must not become proofs.
2. Controlled raw-memory/ABI lowering for runtime primitives. Separate allocator
   primitives from managed functions so Flow never recursively allocates through itself.
3. Real Linux file I/O, process arguments and byte-buffer results, implemented through
   IR. Then Windows/macOS implementations of the same language-facing contracts.
4. Target ABI, object linking, startup, deployment minimums and SDK discovery. Windows
   libraries and macOS system libraries/SDK can remain dependencies without C source.
5. Versioned serialized manifests, imports/exports and compatibility negotiation.
   Today envelope version 1 is an internal value selected by the CLI, with explicit
   target arguments; it is not a new stable transport schema.
6. Target-machine acceptance on Windows, macOS and ARM64. LLVM cross-compilation alone
   does not establish OS/runtime correctness. Mutually importing runtime libraries
   also remain outside the existing self-contained-provider linker contract.

## Diagnostics and verification

| Code | Meaning |
| --- | --- |
| `SUBLANG-R001` | Missing name or unsupported envelope version |
| `SUBLANG-R002` | Unknown destination or mismatched runtime target |
| `SUBLANG-R003` | Unfrozen snapshot or runtime has a program entry |
| `SUBLANG-R004` | Recognized destination lacks implemented codegen |
| `SUBLANG-R005` | Runtime contains unsupported external/platform imports |

Existing verification, K/B and CLI codes retain their meaning.

On October 11, 2026, `scripts/sublang-runtime-sandbox.sh` passed in a networkless,
read-only Docker sandbox capped at 6,000,000,000 bytes without additional swap. It checked
target/version/freeze/import rejection and generated, verified, linked and executed
runtime-body programs with Flow off/on and through the Wire CLI handler. All three
native programs printed `42`. No Windows/macOS executable was tested and no new raw
memory primitive was introduced.
