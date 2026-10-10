# Sublang

Naming migration: terminology has been updated to Sublang, Optimind and HyperAlloc Flow. This is an editorially migrated copy; the original user-supplied file and its original hash remain historical provenance, not the checksum of this revision. Technical scope and reported benchmark evidence are unchanged.

> **High-level compiler optimization, semantic-aware object lowering, and optional memory intelligence — without forcing a language to adopt Emerald's runtime or memory model.**

## What Sublang is

**Sublang is a reusable, language-independent compiler optimization and lowering framework.** A language frontend supplies a typed intermediate representation (IR) and explicit semantic contracts. Sublang uses those contracts to verify the input, analyze program behavior, perform applicable high-level optimizations, plan representations and storage, and lower the result toward LLVM IR.

Sublang is **not** a programming language, a replacement for a language's parser or type checker, or merely a collection of LLVM optimization flags. It operates at the layer where information such as object identity, methods, aliasing, value semantics, ownership, and effects can still be represented explicitly. This allows optimizations to be reasoned about before conventional low-level lowering erases those distinctions.

**The frontend owns language semantics. Sublang owns the reusable analysis, transformations, and lowering machinery for the semantic features that frontend declares.**

## Why this matters

A compiler for an object-oriented or dynamic language has to bridge a large semantic gap between classes, methods, objects, calls, and physical instructions. Straightforward lowering can materialize objects too early, preserve unnecessary heap allocations, or lose information useful for specialization.

Sublang separates **what an operation means** from **how it is represented in machine code**. Its high-level IR preserves semantic relationships; its lowering process chooses concrete representations and produces LLVM-compatible low-level code. LLVM remains responsible for target-specific optimization and machine-code generation.

The result is a framework for building language-specific frontends on top of shared compiler infrastructure rather than reimplementing each analysis and optimization for every language.

## Architecture

```text
Language A frontend     Language B frontend     Language C frontend
         \                      |                      /
          +---------------------+---------------------+
                                |
                 Typed Sublang High IR + semantic contracts
                                |
                      Verification and analyses
                                |
                 Optional high-level optimization passes
                                |
                   Representation and storage planning
                                |
                            Sublang Low IR
                                |
                             LLVM IR
                                |
                        Native machine code
```

### High IR: semantic information before lowering

Sublang High IR represents typed values and control flow with explicit semantic information. Its capability model distinguishes the following concerns:

| Capability | Semantic information |
| --- | --- |
| **Core** | Primitive types, value aggregates, functions, SSA values, control flow, direct calls, arithmetic rules |
| **Object** | Reference classes, object identity, fields, methods, inheritance, interfaces, dynamic dispatch |
| **Memory** | Ownership, borrowing, reference relationships, lifetimes, transfers, storage constraints |
| **GC / Runtime** | GC roots, barriers, safepoints, pinning, weak references, finalizers, collector contracts |

A language uses the capabilities that match its semantics. A procedural language does not need to manufacture classes; an object-oriented language is not forced into Emerald's class representation. Extensions that affect correctness must be understood and preserved by the passes that encounter them.

### Low IR: concrete implementation choices

Sublang Low IR expresses the representation decisions made from high-level semantics: layouts, memory operations, calls, transfers, and cleanup. The LLVM lowering then targets the appropriate platform data layout and ABI. Runtime object headers and collector-specific metadata are defined by the corresponding runtime integration rather than by a universal Emerald object layout.

### Semantic contracts, not guesses

A frontend describes the rules under which optimizations are valid: integer overflow behavior, floating-point semantics, evaluation order, mutability, object identity, method resolution, call effects, exceptions, foreign calls, reflection, concurrency, and relevant runtime operations.

An unknown property is **not** proof of safety. Sublang may conservatively skip an optimization if it cannot establish the necessary facts. This is how shared optimizations remain useful without redefining the semantics of their source languages.

## Flagship capability: HyperAlloc Flow

**HyperAlloc Flow is Sublang's optional, semantics-driven object and memory optimization system.** It analyzes object usage, effects, aliases, escape paths, ownership, and lifetime relationships to determine whether an allocation or representation can be simplified and which management strategy is valid.

Its optimization vocabulary includes:

| Strategy | Technical purpose |
| --- | --- |
| **Folded** | Scalar replacement: remove suitable object allocations and keep the observable state in independent values |
| **Inline** | Represent suitable objects as value aggregates rather than separately allocated identities |
| **Local** | Place eligible non-escaping objects in stack storage |
| **Pool** | Reuse storage for suitable allocation sites under verified lifetime constraints |
| **Shard** | Use region-style allocation where object lifetimes allow coordinated reclamation |
| **Root** | Apply unique ownership and deterministic release where the program's semantics permit it |
| **Bond** | Manage shared ownership with compatible reference tracking and cycle handling |
| **Static** | Use static storage for eligible immutable data, such as constant strings |

These are **candidate transformations, not unconditional promises**: a strategy is chosen only when its proof obligations and runtime contracts are satisfied. Crucially, some strategies remove allocations or change representation without requiring Sublang to own the language's memory management at all.

### Flow does **not** require replacing a tracing GC

Sublang separates three independent decisions:

1. **Use Sublang as an optimization framework?** A language may use Sublang analyses and lowering without enabling HyperAlloc Flow.
2. **Enable Flow?** A language may use Flow's compatible analysis and optimization passes while retaining its existing allocator or tracing garbage collector.
3. **Delegate memory management to Flow?** A language may explicitly select a Flow-managed runtime if its semantics and required runtime capabilities are covered.

These are separate configuration and integration choices. **Using Sublang does not imply using Flow; using Flow does not imply replacing a GC; and choosing LLVM lowering does not inherently require replacing a language's runtime.**

#### Flow Integration Mode: keep the language runtime

The language retains its own GC, allocator, object runtime, and externally observable semantics. A runtime provider supplies relevant capabilities such as roots, write barriers, safepoints, moving-reference handling, pinning, finalizers, and native-call conventions. Flow performs only transformations compatible with those contracts.

This mode can permit object elimination, scalar replacement, selected stack allocation, and other valid improvements **without adopting Root/Bond or Emerald's object layout**. Exactly which optimizations are legal depends on the source language and collector behavior.

#### Flow Managed Mode: delegate memory strategy

A language may intentionally choose Flow as its memory-management layer. In this mode, Flow can coordinate allocation placement, ownership, regions, reuse, deterministic release, and shared-graph handling using appropriate runtime mechanisms.

This is **an opt-in runtime architecture**, not a mandatory upgrade or an automatic way to delete any GC. Dynamic graphs, weak references, resurrection, finalization, concurrency, reflection, and moving-object semantics still require explicit, correct support. A particular reference-counting and cycle-collection mechanism is not a drop-in semantic replacement for every tracing collector.

## Object-oriented lowering is a first-class concern

Sublang is designed to preserve object-level concepts long enough to make informed lowering decisions. Object identity, fields, methods, and dispatch are part of the semantic model rather than something every frontend must immediately flatten into opaque pointers and arbitrary helper calls.

Depending on proof and declared semantics, Sublang can choose to preserve an object, replace it with component values, represent it as an aggregate, eliminate an unnecessary allocation, or lower dispatch through a known target. A method call with an unknown target is treated conservatively unless the frontend provides enough sound information for specialization.

**LLVM is the output technology, not the language model.** Sublang's purpose is to carry richer language semantics to the point where low-level LLVM representation choices can be made correctly.

## Static, dynamic, procedural, and object-oriented languages

Sublang does not require Emerald's syntax or type system. It requires a frontend to express the relevant semantics in Sublang IR.

For a dynamically typed language, that can mean explicit representation of tagged values, runtime type checks, dispatch semantics, dynamic calls, and applicable effect information. Dynamic typing does not make high-level optimization impossible; it changes what must be represented, what can be proven, and where conservative fallback is required.

Sublang does **not** magically infer a complete frontend from source code or know the effects of an unknown call. A language integration provides the IR, runtime ABI and semantic contracts necessary for sound transformations. This is real engineering work, not a config-file toggle.

## Adoption without rewriting the entire compiler

Sublang is conceived for two integration styles:

**Optimization-library integration.** An existing compiler feeds typed IR and semantic contracts into Sublang, runs selected analyses and passes, and consumes the resulting representation or lowered code through an adapter. The surrounding compiler and its own runtime remain in control. If it wants to retain a C generation path, that path can coexist with an Sublang/LLVM path; Sublang does not automatically optimize arbitrary emitted C without a suitable IR integration.

**Compiler-framework integration.** A frontend delegates a wider part of the backend pipeline to Sublang, including high-level optimization, storage planning, low-level IR, LLVM emission, and optional runtime integration.

This distinction matters: **Sublang's LLVM-oriented lowering is not a demand that every existing backend be deleted.** An optional LLVM path can be added while a portable C backend remains available. Conversely, a compiler that wants Sublang's complete low-level pipeline can use it directly.

## Empirical validation: Emerald as the reference implementation

Sublang builds on compiler optimization and lowering techniques exercised in **Emerald**, its reference language. These are real, reported benchmark executions rather than hypothetical speedup estimates. The following measurements are taken from the supplied benchmark report screenshots (October 2026). They establish evidence for specific Emerald compiler/runtime paths; they must **not** be read as independent benchmarks of every Sublang integration, an Sublang-versus-LLVM comparison, or proof that every pass is production-stable.

### Executed workloads

| Workload | Emerald result | Comparison from the same report | What was exercised |
| --- | ---: | --- | --- |
| Prime counting below 200,000 | **20 ms / 10.9 MB peak RSS** | Rust 11 ms; Crystal 14 ms; Novus 30 ms | Integer-heavy code generation, runtime footprint |
| Two million object instances | **50 ms / 34.4 MB peak RSS** | Rust 9 ms / 33.6 MB; Crystal 105 ms / 95.9 MB; Novus 175 ms / 139.9 MB | Value-class inference and compact object handling |
| Word frequency + recursive quicksort | **131 ms / 10.9 MB peak RSS** | Rust 85 ms; Crystal 99 ms; Java 149 ms; Novus 278 ms | Maps, strings, recursion, arrays, allocation behavior |
| Reconstructed 24-field / 24-method dispatch microbenchmark | **7 ms / 10.8 MB peak RSS** | Rust 14 ms; Crystal 10 ms; Novus 1.41 s | Direct method/field lowering and dispatch overhead |
| Spectral norm, N=5,500 | **1.279 s / 10.8 MB peak RSS** | C 0.81 s; Rust 1.35 s; Crystal 1.38 s | Floating-point numeric lowering |
| N-body, 50 million steps | **15.128 s / 10.8 MB peak RSS** | C 2.16 s; Rust 5.60 s; Crystal 3.50 s | Numeric execution; demonstrates remaining performance headroom |

**Reproducibility qualifications:** These are results *as reported in the provided screenshots*, not benchmarks rerun or independently audited for this document. They use different benchmark constructions and language implementations, so they are directional evidence, not a universal ranking. In particular, the dispatch entry uses a reconstructed, same-shape workload rather than byte-identical source; the report explicitly distinguishes it from the original Emerald port. RSS comparisons may include runtime and process overhead, not just objects allocated by the test.

### Validation also means recording failures

The report includes older successful Emerald runs and newer runs that **did not finish**:

- `regex-redux`: Emerald's **previous build** finished in **7.218 s / 381.1 MB**, while the newer build did not complete within the report's 120-second limit.
- `k-nucleotide`: Emerald's **previous build** finished in **2.487 s / 844.0 MB**, while the newer build did not finish within the report's 150-second limit.
- The benchmark report additionally identifies Novus timeouts / out-of-memory outcomes on some larger workloads; these are properties of the tested implementations, not evidence that Sublang has already fixed them.

These results are useful for engineering because they show both the achievable optimization quality **and** where regression testing is still necessary. The demonstrated Emerald workloads give Sublang a tested technical foundation, but **they do not establish that the independent Sublang IR, adapters, Flow modes, or entire platform have all been validated and declared stable**.

### What this demonstrates for compiler developers

The meaningful technical claim is not that Sublang automatically makes every language faster than Rust or C. It is that its underlying approach is supported by **concrete compiled-language experiments**: eliminating or compacting eligible object representations, reducing dispatch overhead where call targets are known, and producing native code with low resident-memory overhead in selected workloads. For any new frontend, those results define testable optimization hypotheses, not guaranteed cross-language speedups.

## What Sublang is — and what it is not

| Sublang is | Sublang is not |
| --- | --- |
| A reusable, semantics-aware compiler optimization and lowering framework | Emerald syntax or Emerald's compiler frontend in disguise |
| A way to preserve and optimize object-level information before LLVM lowering | Merely an LLVM optimization preset |
| A host for optional HyperAlloc Flow analyses and memory strategies | A mandatory replacement for the language's GC |
| A capability- and contract-based integration model | A promise that every optimization fits every language |
| A path toward shared object lowering and LLVM code generation | An obligation to abandon existing C or other backend paths |

## The Sublang proposition

**Keep your language. Keep your semantics. Keep your runtime if you want it.**

Use Sublang to centralize the difficult compiler work between high-level language constructs and LLVM: semantic verification, cross-function analysis, object-aware optimization, storage and representation planning, and lowering. Turn on HyperAlloc Flow when its optimizations are useful; integrate with your existing collector or opt into a Flow-managed memory model when that is the right architectural choice.

> **Sublang turns rich language semantics into optimization opportunities before they disappear into low-level IR. HyperAlloc Flow makes object representation and memory behavior part of that optimization space — without making its memory runtime compulsory.**

---

*This document describes the Sublang architecture and integration model, alongside reported benchmark evidence from its Emerald reference implementation. Benchmarks from Emerald do not certify the maturity, availability, or stability of every Sublang component or language integration.*
