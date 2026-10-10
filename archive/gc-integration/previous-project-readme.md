# Sublang — archived platform overview

**Historical design, archived October 10, 2026.** This English edition preserves the earlier proposal's scope. It is not the current support matrix. Foreign collector integration was subsequently removed from active development. See the [current README](../../readme.md) and [roadmap](../../docs/Roadmap.md).

Sublang was proposed as a reusable, language-independent compiler/optimization platform implemented in Emerald. Optimind names the general analysis/pass engine; HyperAlloc Flow names the optional memory subsystem. LLVM remains the final backend. No fused language or new source extension was part of this proposal.

## Repository and historical status

The independent core, examples and contracts belong in Sublang, separate from Emerald's frontend/compiler/stdlib/runtime. Emerald is an external bootstrap toolchain, configured by SUBLANG_EMERALD_ROOT; the sandbox image by SUBLANG_SANDBOX_IMAGE.

At this historical stage, the typed builder/dump/structural verifier existed. Lifetime/effect proof, LLVM lowering, public process interface and complete Flow integration were still proposed. Structural validity was not codegen readiness. Later executable support must not be projected backward onto these archived claims.

All compiler/selfhost checks were required to run in a capped sandbox, at most 8 GB and preferably 6 GB/no swap, networkless and readonly. The examples harness did not constitute a full selfhost bootstrap.

## Intended adoption paths

- **Optimization library:** a compiler emits typed IR, runs selected passes and consumes the result. Its LLVM integration can remain external; an existing C backend can coexist.
- **Compiler framework:** a frontend also delegates memory planning, runtime integration, LLVM emission and build orchestration.

Frontends retain syntax and source semantics. They must resolve names/types/call targets and evaluation order. A configuration file alone cannot describe arbitrary language behavior. Emerald was the initial reference, not a mandatory input language/runtime.

## Proposed pipeline

```text
Language frontend -> typed High IR + semantic profiles
                  -> verification and analyses
                  -> optimization and memory planning
                  -> Low IR -> LLVM -> native code
```

High IR preserves values, identity, methods, ownership and lifetime. Low IR makes representation, memory operations, calls and cleanup concrete. Optimizing before erasing those relations into raw pointers enables stronger proofs.

## Core and extensions

| Area | Proposed capability |
| --- | --- |
| Core | Primitive/value types, functions, SSA, CFG, direct calls and arithmetic semantics |
| Object | Classes, identity, fields/methods, later interfaces/inheritance/dynamic dispatch |
| Memory | Ownership, borrows, reference relations, lifetime and transfers |
| GC/runtime | Roots, barriers, safepoints, pinning, weak references and finalizers |

High/Low describes lowering stage; Core/extensions describe capabilities. A procedural language can omit Object; an OO language with GC could combine Object and GC/runtime.

Extensions affecting correctness cannot be ignored. A pass must understand/preserve them or decline transformation. Unknown required capabilities fail before codegen. Closures/captures need explicit contracts, not implicit Class encoding.

## Historical Flow modes

Flow was intended to analyze neutral IR rather than Emerald AST. Object graphs, mutation, escapes and runtime properties would feed a common analysis base with different providers.

### Managed mode

The language explicitly delegates compatible memory management to Flow. Strategies include inline values, stack objects, regions/pools, deterministic exclusive ownership and shared/cyclic runtime management.

Auto means selecting strategies within an explicitly selected memory mode, not permission to replace a language's collector. Runtime support remains necessary for cases that cannot be resolved statically.

Bond cycle collection is a building block rather than a replacement for every tracing collector. Weak references, finalizers, resurrection, moving objects, reflection and threads require precise contracts and potentially more runtime work. Managed does not inherently mean collector-free.

### Integration mode — now archived

The language retains its existing collector/memory system. Flow performs compatible optimizations through a provider describing roots, barriers, safepoints, moving references, pinning and native calls.

This requires preserving/generating operations at correct sites, not merely linking a GC library. Stack/layout transformations must satisfy both source semantics and collector contracts.

## Proposed configuration

These are historical architecture options, not current CLI instructions.

| Option | Proposed meaning |
| --- | --- |
| --sublang-flow=off | Disable optional passes, retain required safety/management |
| --sublang-flow=on | Require Flow and diagnose missing capabilities |
| --sublang-flow=auto | Choose compatible behavior and report effective mode |
| --sublang-memory=language | Keep the language-selected provider; default |
| --sublang-memory=hyperalloc-managed | Explicitly select Flow management |
| --sublang-memory=hyperalloc-integration | Explicitly integrate the existing collector |

Explicit Flow memory modes require the Flow package. Combining them with off is contradictory in this proposal. Under auto an explicitly selected provider remains required; no silent replacement is allowed.

## Semantics and representation

Contracts must preserve integer widths/overflow, FP/NaN/rounding, value copies/reference identity, mutation, call effects/escape/ownership and exceptions/finalizers/threads/reflection/FFI.

Unknown is not a guarantee. Missing optional optimization proof selects a safe baseline; missing required semantics prevents codegen. Flow off cannot disable ownership, overflow checks or required release. Heap fallback alone does not repair invalid lifetimes.

Layout optimizations may remove per-element headers or flatten eligible objects. Identity, FFI, reflection, serialization and finalizers can block changes. Target data layout and provider metadata determine representation; Emerald's 16-byte header is not a universal public ABI.

## Intended optimizations

Escape/lifetime analysis, scalar replacement, value inference, stack/pool/region allocation, exclusive/shared strategies, constant strings, collection representation, proved direct calls, effect-safe High-IR transformations and LLVM/LTO/PGO integration.

Not every pass belongs to Flow or fits every language. Library transformations require semantic contracts; a name such as List is insufficient. LLVM/LTO/PGO remain separate controls.

## Frontend integration and development stages

Frontends resolve source semantics, emit typed Core/extensions with source spans, provide effective effect/runtime contracts, verify/optimize/plan and lower through LLVM.

The original sequence was IR/contracts, a bounded static LLVM path, a second non-OO frontend, provider/Flow migration and possible Emerald selfhost integration after verification. This historical sequence is not today's release scope.

Dynamic typing was an explicit AOT target: tags, tests, runtime fallback, heap values, properties and captures. JIT/deoptimization, complete Python/JS semantics and universal GC compatibility were not promised.

## Evidence and architecture examples

The historical Technical Overview reported Emerald measurements and incomplete regex-redux/k-nucleotide runs. They were not independently remeasured for this document and are not standalone Sublang benchmarks or guaranteed frontend performance.

The seven core examples were real builder dumps with separate structural verification. Extended .sublang-ir modules, plans, protocol reports and GC contracts were illustrative requirements. Positive analysis reports were expected results, not executed proofs.

The v0.4 design required effect provenance, common alias/locations, separate structural/semantic/memory checks, explicit exception CFG and structured Explain identifying blockers. Public process/Wire/library ABI versions were to remain distinct from internal layouts. Lexical scope.end alone never proved object death.
