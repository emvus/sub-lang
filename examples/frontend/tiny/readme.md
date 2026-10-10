# Tiny: an independent second frontend

`tiny.py` is a small procedural-language frontend written in Python (standard
library only). It parses its own source language and writes **Wire v2**
(`.sublang-wire`). It shares no code with the Emerald builder, imports no Emerald
AST and needs no Emerald toolchain; the neutral compiler only sees the Wire file.

```bash
python3 examples/frontend/tiny/tiny.py examples/frontend/tiny/fib.tiny build/tiny/fib.sublang-wire
bash scripts/sublang-build.sh build/tiny/fib.sublang-wire -o build/tiny/fib --flow=on --run   # 6000
bash scripts/sublang-tiny-check.sh                                                           # end-to-end checks
```

## Source semantics (owned by the frontend, not by Sublang)

- Every value is a signed 64-bit `Int`. There are no other types, no strings and no
  heap values, so this frontend does not exercise ownership or Flow placement
  beyond scalar block arguments.
- `+ - * / %` and unary `-` use the `trap` overflow mode with the declared
  `test.abort` failure. Overflow of `*` and division by zero are checked by
  `scripts/sublang-tiny-check.sh`; the other trap paths rely on the backend.
- Comparisons produce a condition and are only valid as `if`/`while` conditions.
- Variables are declared with `let` and assigned with `=`; redeclaration, use before
  declaration, code after `return` and functions that can fall off the end are
  frontend errors with `line:column` positions.
- Arguments and operands are evaluated left to right. Calls are direct and may be
  forward references; recursion is allowed. `main()` with no parameters is the entry.

## Lowering

Each mutable variable in scope becomes a block parameter at loop headers, branch
arms and joins, so no SSA-construction analysis is needed. Every operation carries a
source span (`file:line:column`) that appears in `sublang dump` and diagnostics.

## What this demonstrates and what it does not

It demonstrates that a Wire writer in another language can produce accepted input
using only [the Wire specification](../../../docs/Sublang_Wire_Spec.md). It does not
cover floats, strings, collections, objects, closures or exceptions, and it does
not claim a stable frontend SDK.
