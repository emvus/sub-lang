# Sublang v0.4 architecture examples

These are **complete illustrative proposed modules**, not currently readable compiler inputs. Their notation, effects and validation reports express design requirements rather than executed analysis. See [extended-ir.md](../extended-ir.md).

| File | Topic |
| --- | --- |
| [01-procedural.sublang-ir](01-procedural.sublang-ir) | Checked i64, functions and effects |
| [02-objects.sublang-ir](02-objects.sublang-ir) | OO interface, open dispatch targets, declared/proven effects |
| [03-managed-high.sublang-ir](03-managed-high.sublang-ir) | Managed High IR with ownership/lifetime dependencies |
| [04-managed-low.sublang-ir](04-managed-low.sublang-ir) | Memory-plan-consuming Low IR and lowered effects |
| [06-bond-cycles.sublang-ir](06-bond-cycles.sublang-ir) | Shared cycle and provider contract |
| [07-dynamic.sublang-ir](07-dynamic.sublang-ir) | Dynamic heap values, explicit ownership and runtime calls |
| [08-closure.sublang-ir](08-closure.sublang-ir) | Value capture and effects |
| [09-explain.sublang-ir](09-explain.sublang-ir) | Unknown consuming call, escape and Explain |
| [10-exceptions.sublang-ir](10-exceptions.sublang-ir) | Invoke, cleanup, catch and resume |
| [11-ownership-transfer.sublang-ir](11-ownership-transfer.sublang-ir) | Ownership surviving lexical scope end |

[Illustrative LLVM](managed-illustrative.ll) accompanies Managed High/Low. Plans, decisions and protocol sketches share entity IDs in extended-ir.md; they are not a separate parser/validator.

The [core dumps](../readme.md) and [actual Wire inputs](../../wire/readme.md) are different example families. For working integration, read the [IR guide](../../../docs/Sublang_IR_Guide.md).

The former collector proposal 05 and collector-dependent 07/09 variants are [archived](../../../archive/gc-integration/readme.md). Foreign GC integration is outside the active roadmap.
