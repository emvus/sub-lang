# Using Sublang IR: frontend developer guide

Updated **October 11, 2026**. This guide covers the executable native64 backend and Wire v2, including v1 input compatibility. Dynamic values, exception unwinding, virtual dispatch and a public serialized Low IR remain development targets.

Your frontend resolves source names and types, determines evaluation order and constructs typed Sublang IR with explicit control flow. Sublang checks the module, applies compatible Optimind transformations, optionally plans memory with HyperAlloc Flow and emits LLVM IR. The sandbox launcher verifies/optimizes that LLVM and links a native program.

## Contents

1. [Input formats](#1-input-formats)
2. [Build and run](#2-build-and-run)
3. [Modules, IDs, types and source information](#3-modules-ids-types-and-source-information)
4. [Your first complete builder](#4-your-first-complete-builder)
5. [SSA and control flow](#5-ssa-and-control-flow)
6. [Numbers and failures](#6-numbers-and-failures)
7. [Records, classes and ownership](#7-records-classes-and-ownership)
8. [Calls and transfers](#8-calls-and-transfers)
9. [Strings and lists](#9-strings-and-lists)
10. [Shared graphs with Bond](#10-shared-graphs-with-bond)
11. [Optimization options](#11-optimization-options)
12. [Wire export and foreign frontends](#12-wire-export-and-foreign-frontends)
13. [Verification and diagnostics](#13-verification-and-diagnostics)
14. [Frontend integration workflow](#14-frontend-integration-workflow)
15. [Source and example reference](#15-source-and-example-reference)

## 1. Input formats

| Format | Purpose | Build input? |
| --- | --- | --- |
| `.sublang-wire` | Versioned, byte-framed High IR with tables, CFG and metadata | Yes, through the standalone executable |
| `.ems` defining `SublangProgram.build()` | Emerald code constructing neutral IR | Yes, through the builder launcher |
| `.sublang` in examples/ir | Human-readable builder dump | No parser for this notation |
| `.sublang-ir` in examples/ir/v0.4 | Illustrative architecture contracts | Not executable input |
| `.c` | Ordinary C through Clang/LLVM | Yes, without High-IR Optimind/Flow |

Wire is the existing process boundary for frontends implemented outside Emerald. Processing a Wire module does not require the Emerald compiler at invocation. Emerald frontends can use the builder and serialize later.

The builder's implementation language does not define the input language. A Sublang Class is not an Emerald AST node. Procedural frontends can use free functions and records without classes.

## 2. Build and run

Run commands from the **Sublang repository root**. The scripts run compilers and generated programs in Docker with a hard 6,000,000,000-byte RAM/RAM+swap limit, no additional swap, no network, readonly inputs and timeouts. Docker and the locally available image `emerald-selfhost-sandbox` are prerequisites; the scripts do not download it automatically.

Bootstrap once if build/sublang is missing:

```bash
bash scripts/sublang-bootstrap.sh
```

Build and run a published Wire input:

```bash
bash scripts/sublang-build.sh examples/wire/bond-component.sublang-wire \
  -o build/bond-component --flow=on --optimind=on --llvm-opt=3 --run
```

Expected output: **4242**. The Wire build does not mount Emerald. Omit --run to compile without executing the program.

| Artifact | Contents |
| --- | --- |
| build/bond-component | Native executable |
| build/bond-component.ll | Sublang LLVM output before subsequent LLVM passes |
| build/bond-component.bc | Verified bitcode optimized according to --llvm-opt |
| build/bond-component.plan | Memory placement explanations |

Inspect the report without execution:

```bash
cat build/bond-component.plan
```

The current native process wrapper calls the selected IR entry, prints its i64 result and exits successfully. The printed result is **not the process exit code**. Entry signature must be `() -> Int`. Select the entry by FunctionId; naming a function main is insufficient.

Save the complete builder in section 4 as examples/programs/first-ir.ems:

```bash
bash scripts/sublang-build.sh examples/programs/first-ir.ems \
  -o build/first-ir --flow=on --run
```

This compiles and runs the Emerald builder in the sandbox. It is not a complete frontend for arbitrary Emerald source. The input must define SublangProgram with static build(). The runner imports that one source file and Sublang packages; additional frontend files need corresponding integration changes.

Configure external dependencies when necessary:

```bash
SUBLANG_EMERALD_ROOT="/path/to/Emerald LLVM" \
  bash scripts/sublang-build.sh examples/programs/first-ir.ems -o build/first-ir --run
```

SUBLANG_SANDBOX_IMAGE selects another already available compatible image.

## 3. Modules, IDs, types and source information

A module contains types, fields, functions, spans, semantic profiles, FailureActions and effect/alias metadata. Functions contain parameters, an SSA type table and blocks. Blocks contain ordered operations followed by exactly one terminator.

### IDs are not runtime values

The builder returns host Int IDs from distinct domains: TypeId, FieldId, FunctionId, ScopeId, BlockId and ValueId. Do not interchange them.

```emerald
Int valueId = builder.ops().constInt(42, span);
```

valueId identifies an IR constant. Adding IDs in Emerald does **not** construct an IR addition: use intBinary. An Emerald while loop in a builder executes while constructing IR. A loop in the generated program needs blocks and backedges.

Positive IDs identify entities; zero means absence, no result or refused construction depending on the API. Values/blocks are function-local. Types, fields and functions belong to module tables. OperationIds are module-wide. IDs are not pointers or LLVM handles.

### Type reference

| Type | Builder | Native contract |
| --- | --- | --- |
| Void | voidType() | No result |
| Bool | boolType() | Boolean value and branch condition |
| Int | intType() | Signed i64 |
| Float | floatType() | IEEE f64 with explicit rne |
| String | module().types().stringType(), or constString | Static immutable byte-string value |
| Record | recordType(name, span) | Nominal value with primitive/String fields |
| Class | classType(name, span) | Object layout; instances accessed by references |
| Ref<T> | refType(type) | Non-null Class/List reference; separate ownership metadata |
| List<E> | listType(elementType, span) | Layout instantiated through Ref<List<E>> |
| Bond<C> | bondType(classType) | Counted shared Class handle |

Ref alone does not distinguish owning and borrowed values: passing/result metadata supplies that contract. Ref fields can internally be empty, despite non-null general SSA references. Reads/takes of empty children are checked.

The four built-in primitives are schema-defined. Obtain additional IDs from the builder; do not assume a fixed String TypeId. Field declaration order determines positional record construction order.

### Source locations

```emerald
Int source = builder.source("input.my-language");
Int span = builder.span(source, 12, 7);
Int synthetic = builder.syntheticSpan("frontend:generated-cleanup");
```

Use real positions for source operations and meaningful synthetic origins for generated operations. Source metadata is not a safety proof.

### Freeze

Call builder.freeze() or module.freeze() after construction. Native compilation and Wire writing require a frozen snapshot. Wire reading freezes its imported module.

Do not mutate afterward. Refused builder/setter requests are recorded; do not use partially constructed IDs after errors. General public fork/revision APIs for arbitrary third-party passes remain unfinished.

## 4. Your first complete builder

This adds checked i64 constants and returns **42**:

```emerald
use sublang::ir::SublangBuilder;
use sublang::ir::SublangModule;

public class SublangProgram {
    public static SublangModule build() {
        SublangBuilder builder = SublangBuilder("first-ir");
        Int span = builder.syntheticSpan("guide:first-ir");
        Int overflow = builder.failure("guide.integer-overflow");

        Int entry = builder.beginFunction("main", builder.intType(), 0, span);
        builder.module().setEntry(entry);
        builder.beginBlock();

        Int left = builder.ops().constInt(20, span);
        Int right = builder.ops().constInt(22, span);
        Int result = builder.ops().intBinary(
            "int.add", left, right, "trap", overflow, span);
        builder.ops().returnValue(result, span);

        builder.freeze();
        return builder.module();
    }
}
```

beginFunction creates/selects a function. Its third argument zero means no Class-method association. beginBlock creates/enters the first block. Subsequent ops() calls append there; returnValue terminates it.

The default profile is sublang.startup version 1: signed i64, IEEE f64/RNE, abort failures and no unwinding. Declaring an arbitrary profile name does not add backend support.

## 5. SSA and control flow

Each SSA value has one definition. That definition must dominate its uses: every execution path reaching the use must have encountered the definition. A branch-local value cannot simply be used after merging branches. Supply a block parameter and an argument on every incoming edge.

newBlock() creates without entering. enterBlock(id) changes the cursor. addBlockParam(type) adds a current-block parameter; add parameters before operations.

Terminators are branch, cond_branch, return and fail. Every block needs one, with no following operations.

### Complete loop: sum 0 through 9

Save as a separate builder input. Result: **45**.

```emerald
use sublang::ir::SublangBuilder;
use sublang::ir::SublangModule;

public class SublangProgram {
    public static SublangModule build() {
        SublangBuilder b = SublangBuilder("sum-loop");
        Int s = b.syntheticSpan("guide:sum-loop");
        Int failure = b.failure("guide.overflow");
        Int entry = b.beginFunction("main", b.intType(), 0, s);
        b.module().setEntry(entry);
        b.beginBlock();
        Int header = b.newBlock();
        Int body = b.newBlock();
        Int done = b.newBlock();
        List<Int> empty = List();

        Int zero = b.ops().constInt(0, s);
        List<Int> initial = List();
        initial.add(zero);
        initial.add(zero);
        b.ops().branchTo(header, initial, s);

        b.enterBlock(header);
        Int index = b.addBlockParam(b.intType());
        Int sum = b.addBlockParam(b.intType());
        Int limit = b.ops().constInt(10, s);
        Int condition = b.ops().compare("lt", index, limit, s);
        List<Int> finished = List();
        finished.add(sum);
        b.ops().condBranch(condition, body, empty, done, finished, s);

        b.enterBlock(body);
        Int nextSum = b.ops().intBinary("int.add", sum, index, "trap", failure, s);
        Int one = b.ops().constInt(1, s);
        Int nextIndex = b.ops().intBinary("int.add", index, one, "trap", failure, s);
        List<Int> next = List();
        next.add(nextIndex);
        next.add(nextSum);
        b.ops().branchTo(header, next, s);

        b.enterBlock(done);
        Int result = b.addBlockParam(b.intType());
        b.ops().returnValue(result, s);
        b.freeze();
        return b.module();
    }
}
```

The header receives index and sum. The backedge supplies both new values. Existing SSA values are not reassigned. Edge argument transfer is parallel, including when values exchange positions.

condBranch(condition, trueTarget, trueArgs, falseTarget, falseArgs, span) needs a Bool condition. Edge arguments must match each destination's parameter count/types. Encoded operands are condition, true arguments, false arguments; trueArgs records the split. The builder performs this encoding.

**Native limitation:** arbitrary Ref/Bond block parameters and ownership phi nodes are unsupported. Use scalar parameters for numeric state and accepted object operations for graph state.

## 6. Numbers and failures

### Integers

intBinary(opcode, left, right, overflow, failureId, span) accepts int.add/sub/mul/div/rem. intNeg supplies negation.

| Mode | Behavior |
| --- | --- |
| trap | Execute the selected FailureAction on overflow; supported native action aborts |
| wrap | Defined i64 wrapping for add/sub/mul/div/neg; not accepted for rem |
| zero | Only for rem: MIN % -1 yields zero; not a general failure fallback |

For trap, provide a valid FailureId. failure(name) creates/finds a default abort action. failureAction can describe a full record, but native codegen accepts compatible unbound/libc.abort bindings only. A throwing record does not implement exception handling.

Division and remainder explicitly handle zero divisors and MIN/-1. Wrapping division defines the overflow case. **Division and remainder by zero abort in every accepted mode**, including remainder with zero. Arithmetic modes are language semantics; never change them merely to enable optimization.

compare(predicate, left, right, span) returns Bool. Integer predicates include eq, ne, lt, le, gt, ge. Operand types must match.

### Floats

constFloatBits takes an **IEEE-754 bit pattern** in signed Int64, not a numerically converted integer. The bits for 2.0 are 4611686018427387904.

```emerald
Int two = builder.ops().constFloatBits(4611686018427387904, span);
Int four = builder.ops().floatBinary("float.mul", two, two, "rne", span);
```

Float opcodes are float.add/sub/mul/div. Startup requires rne: round to nearest, ties to even. Constants preserve negative zero/NaN payloads. Sublang does not fold floats through host arithmetic or reassociate them.

Comparisons require explicit ordered/unordered predicates: oeq, one, olt, ole, ogt, oge, ueq, une, ult, ule, ugt, uge, ord, uno. Generic lt is rejected for Float. Select the source language's NaN behavior explicitly.

failWith(failureId, span) terminates with failure. Abort is not unwinding and does not promise ordinary scope cleanup before process termination.

## 7. Records, classes and ownership

### Record values

The snippets below assume an active block, builder and span:

```emerald
Int pair = builder.recordType("Pair", span);
Int x = builder.recordField(pair, "x", builder.intType(), span);
Int y = builder.recordField(pair, "y", builder.intType(), span);
List<Int> values = List();
values.add(builder.ops().constInt(20, span));
values.add(builder.ops().constInt(22, span));
Int original = builder.ops().recordMake(pair, values, span);
Int changed = builder.ops().recordWith(
    original, x, builder.ops().constInt(40, span), span);
Int unchangedX = builder.ops().recordGet(original, x, span);
```

recordWith produces a new value; original.x remains 20. Construction operands follow field order/types. Native records allow primitive/static String fields, not arbitrary nested records or Ref fields.

### Class initialization

```emerald
Int point = builder.classType("Point", span);
Int x = builder.classField(point, "x", builder.intType(), true, span);
Int scope = builder.ops().scopeBegin(span);
Int object = builder.ops().classNew(point, scope, span);
builder.ops().fieldInit(object, x, builder.ops().constInt(41, span), span);
builder.ops().fieldWrite(object, x, builder.ops().constInt(42, span), span);
Int result = builder.ops().fieldRead(object, x, span);
builder.ops().scopeEnd(scope, span);
builder.ops().returnValue(result, span);
```

The true classField flag allows later mutation. fieldInit initializes an uninitialized field; fieldWrite performs later assignment. Required fields must be initialized on all incoming paths before read, complete-object calls or owned returns. Do not assume implicit zero/null initialization for class.new.

### Scopes and actual lifetimes

scopeBegin returns a ScopeId. New owners attach to the active innermost scope. Scope nesting must be correct along every CFG path. scopeEnd releases remaining owners. An object already transferred into a parent or returned owned has changed ownership location.

A lexical scope end is **not a universal object-death proof**. Lifetime analysis tracks moves/views; Shard lowering also tracks region backing provenance. Copied primitive fields can survive cleanup; expired references/views cannot.

### Exclusive child operations

| API | Contract |
| --- | --- |
| fieldInitOwned(parent, field, child, span) | Initialize Ref field, consume child |
| fieldWriteOwned(parent, field, child, span) | Replace mutable Ref field, destroy old child, consume replacement |
| fieldClear(parent, field, span) | Destroy old child and mark initialized-empty |
| fieldHas(parent, field, span) | Test initialized field for nonempty |
| fieldBorrow(parent, field, span) | Read-only child view; empty aborts |
| fieldTake(parent, field, scope, span) | Remove child and adopt its owner into destination scope; empty aborts |

After consuming a child, do not reuse its previous SSA owner. Borrow through its new parent when needed.

After fieldTake the parent field is logically uninitialized: refill or explicitly clear it before complete-object calls/returns. [root-tree.ems](../examples/programs/root-tree.ems) demonstrates this and returns 42.

Root destruction is iterative, avoiding recursive stack teardown. Exclusive Ref edges do not represent arbitrary shared cycles; use Bond.

## 8. Calls and transfers

beginFunction(name, returnType, methodOf, span) creates a function. addParam(name, type, passing, noEscape) adds a parameter and returns its ValueId. Add parameters before the first block.

| Mode | Contract |
| --- | --- |
| value | Primitive/String/Record value |
| borrow_read | Nonowning read access; no mutation/owned forwarding |
| borrow_write | Nonowning write access under alias/lifetime checks |
| owned | Transfer ownership; old owner becomes unusable |
| init | Designated initialization operations, not a general Ref parameter mode |

callDirect(functionId, args, modes, span) requires equal argument/mode counts matching the signature. A Void call returns builder ID zero because no SSA result exists.

Declare a read-only function before its caller:

```emerald
Int getter = builder.beginFunction("readX", builder.intType(), 0, span);
Int parameter = builder.addParam("p", builder.refType(point), "borrow_read", false);
builder.beginBlock();
builder.ops().returnValue(builder.ops().fieldRead(parameter, x, span), span);
```

Call it in the caller's active block:

```emerald
List<Int> args = List(); args.add(object);
List<String> modes = List(); modes.add("borrow_read");
Int value = builder.ops().callDirect(getter, args, modes, span);
```

noEscape=true is a declaration, not a proof. The native path checks available closed bodies and accepted operations. Unknown external calls are unsupported.

### Owned results

Factories returning Ref<Class>, Ref<List<E>> or Bond<Class> use returnOwned(value, span). It detaches the result and cleans up remaining owners/scopes. Do not end its owning scope before returning.

Callers use callDirectOwned(functionId, args, modes, destinationScope, span). The result is adopted into the active innermost destination scope. Ordinary callDirect without ownership/scope metadata does not express this contract.

Borrowed values cannot be returned owned. Duplicate owned arguments and conflicting mutable aliases are rejected. Primitive/Void returns require explicitly closing lexical scopes before returnValue; returnValue(0, span) is the Void form.

## 9. Strings and lists

### Static strings

```emerald
Int text = builder.ops().constString("Hello", span);
Int length = builder.ops().stringLength(text, span);
Int byte = builder.ops().stringByte(text, builder.ops().constInt(0, span), span);
Int same = builder.ops().stringEqual(text, text, span);
```

Strings are {pointer, i64 byteLength} values over immutable LLVM globals. Executing const.string repeatedly does not allocate another string. Indices/lengths count **bytes**, not Unicode characters. string.byte returns an unsigned byte widened to Int; negative/out-of-range indices abort. Equality compares exact bytes. Dynamic concatenation and general mutable string heaps are not provided.

### Complete Class list

This moves a Point into a list, reads through a view and returns **42**:

```emerald
use sublang::ir::SublangBuilder;
use sublang::ir::SublangModule;

public class SublangProgram {
    public static SublangModule build() {
        SublangBuilder b = SublangBuilder("point-list");
        Int s = b.syntheticSpan("guide:point-list");
        Int point = b.classType("Point", s);
        Int x = b.classField(point, "x", b.intType(), true, s);
        Int listType = b.listType(point, s);
        Int entry = b.beginFunction("main", b.intType(), 0, s);
        b.module().setEntry(entry);
        b.beginBlock();
        Int scope = b.ops().scopeBegin(s);
        Int list = b.collections().listNew(listType, scope, s);
        Int object = b.ops().classNew(point, scope, s);
        b.ops().fieldInit(object, x, b.ops().constInt(42, s), s);
        b.collections().push(list, object, s);
        Int view = b.collections().borrow(list, b.ops().constInt(0, s), s);
        Int result = b.ops().fieldRead(view, x, s);
        b.ops().scopeEnd(scope, s);
        b.ops().returnValue(result, s);
        b.freeze();
        return b.module();
    }
}
```

listType(point, ...) describes logical Point elements, not an explicit Ref<Point> element type. Push consumes the Class owner; object cannot be reused. Eligible primitive/static-String Classes can occupy the buffer without element headers. Mutable field declarations do not automatically prevent inference: only supported read-only views exist after the move and identity cannot be observed.

Classes with owning/reference children keep stable individual objects. Primitive/String/Record elements use get to obtain value copies. Class elements use read-only borrow. Mutable element views are unsupported.

Length results are i64, but internal length/capacity are bounded i32: at most 2,147,483,647 elements, also limited by checked byte sizes/RAM. Growth uses realloc. Clear destroys elements while retaining capacity; final cleanup releases the buffer.

**Views expire on** push, clear, mutable calls, list movement and cleanup. Do not carry views across mutating iterations as independent owners. Copy needed values before mutation or obtain fresh valid views afterward.

## 10. Shared graphs with Bond

Bond<C> explicitly represents shared ownership. Ordinary Ref does not become shared automatically. Roots and graph edges are counted separately.

### Complete shared cycle

```emerald
use sublang::ir::SublangBuilder;
use sublang::ir::SublangModule;

public class SublangProgram {
    public static SublangModule build() {
        SublangBuilder b = SublangBuilder("bond-cycle-guide");
        Int s = b.syntheticSpan("guide:bond-cycle");
        Int node = b.classType("Node", s);
        Int x = b.classField(node, "x", b.intType(), true, s);
        Int edge = b.classField(node, "next", b.bondType(node), true, s);
        Int entry = b.beginFunction("main", b.intType(), 0, s);
        b.module().setEntry(entry);
        b.beginBlock();
        Int outer = b.ops().scopeBegin(s);
        Int first = b.bonds().create(node, outer, s);
        b.bonds().write(first, x, b.ops().constInt(7, s), s);
        Int inner = b.ops().scopeBegin(s);
        Int second = b.bonds().create(node, inner, s);
        b.bonds().write(second, x, b.ops().constInt(35, s), s);
        b.bonds().link(first, edge, second, s);
        b.bonds().link(second, edge, first, s);
        b.ops().scopeEnd(inner, s);

        Int child = b.bonds().get(first, edge, outer, s);
        Int a = b.ops().fieldRead(b.bonds().borrow(first, s), x, s);
        Int c = b.ops().fieldRead(b.bonds().borrow(child, s), x, s);
        Int result = b.ops().intBinary("int.add", a, c, "wrap", 0, s);
        b.ops().scopeEnd(outer, s);
        b.ops().returnValue(result, s);
        b.freeze();
        return b.module();
    }
}
```

Result: **42**. Ending inner removes the second root, but first.next preserves reachability. Ending outer removes remaining roots and makes the cycle collectible.

| API under bonds() | Contract |
| --- | --- |
| create(classType, scope, span) | Zero-initialized object and one owning root |
| retain(handle, scope, span) | Independent root to the same object |
| borrow(handle, span) | Read-only Ref view, no new root |
| get(handle, field, scope, span) | New root for nonempty shared child; empty aborts |
| link(handle, field, child, span) | Shared edge without consuming child handle |
| own(handle, refField, child, span) | Consume exclusive Ref child |
| clear(handle, field, span) | Remove shared edge or destroy exclusive child |
| write(handle, field, value, span) | Write mutable primitive/static-String field |

The runtime uses candidate-local trial deletion and revision-checked SCC caching, with the implemented cache threshold of 64 members. Edge mutation invalidates cached proofs. Ordinary Ref objects are not globally mark/swept.

Mutation through a second retained alias can invalidate views from the first. Shared-view invalidation is conservative. Retain/get roots for independent reachability, and create fresh views as needed; roots do not make old views permanently valid.

Arbitrary Root-to-Bond promotion, weak refs, threads and finalizers are unsupported. Normal classNew with Bond fields is not automatically converted; use bonds().create.

## 11. Optimization options

```bash
bash scripts/sublang-build.sh examples/wire/inline-list.sublang-wire \
  -o build/points --flow=on --optimind=on --llvm-opt=3 --run
```

| Option | Effect |
| --- | --- |
| --flow=on | Enable implemented Flow planning for valid High IR |
| --flow=auto | Currently identical planning to on for native High IR; default |
| --flow=off | Disable optional placements/heap caches; preserve required ownership/cleanup |
| --optimind=on or off | Existing High-IR transformations; default on |
| --llvm-opt=0, 1, 2 or 3 | Separate LLVM level; default 2 |

Off does not discard ownership or intentionally leak cycles. Static String/container contracts also remain. Auto does not accept invalid IR. For C, auto/off leave Flow inactive; on is rejected without ownership import.

| Strategy | Executable use |
| --- | --- |
| Folded | Scalar field slots and eligible direct Inline construction |
| Local | Nonescaping addressable stack objects |
| Inline | Eligible Class elements directly in list storage |
| Shard | Closed graphs in dependent nested regions |
| Pool | Reusable temporary sites and bounded exact-layout heap caches |
| Root | Stable exclusive graphs, 16-byte prefix, iterative destruction |
| Bond | Shared graphs and cycle collection |
| Static | Immutable String globals |

Frontends express semantics, not forced physical addresses. Flow chooses compatible placements. The .plan explains decisions/fallbacks; it is text, not a stable machine-readable Explain protocol.

Optimind folds safe Integer/Bool constants, selected identities and suitable constant scalar calls through bounded closed bodies. Missing proofs block changes. Multiplication by zero does not erase a potentially failing earlier computation/call. LLVM passes follow separately. LTO/PGO are not implemented launcher switches.

## 12. Wire export and foreign frontends

### Emerald codec

The writer returns encoded text/bytes, not a file:

```emerald
use sublang::wire::SublangWire;
use sublang::wire::SublangWireResult;
use Std::Native::NativeFile;

// In your exporter, after constructing the complete module:
module.freeze();
SublangWireResult encoded = SublangWire.write(module);
if (!encoded.valid()) {
    println(encoded.error());
    return;
}
NativeFile.writeText("/tmp/program.sublang-wire", encoded.text());
```

This is an **exporter fragment**, not a replacement for SublangProgram. Run exporters in capped sandboxes and explicitly export files. The normal builder launcher exports LLVM/bitcode/plan/binary, not an extra Wire file.

SublangWire.read(text) returns valid(), error() and, on success, module(). Transport success does not establish semantic/lifetime validity.

### Wire records

Wire uses experimental netstrings: BYTE_COUNT:PAYLOAD,. These are **individual tokens**, not complete modules:

```text
3:abc,
2:42,
0:,
```

Count UTF-8 bytes, not Unicode characters. Do not add formatting whitespace between tokens.

Header order: SUBLANG-WIRE magic, transport version, IR schema, stage, revision, required-feature count/features, module name, entry FunctionId. Current output: transport 2, schema 1, High, revision 1, core.native64.v2. Wire version and IR schema are distinct.

Counted sections encode sources/spans, types/fields, profiles/failures, locations/aliases/effects, functions with SSA/block/operation records, then the end marker. Preserve operands, modes, targets, scope, result ownership, failure references and raw float bits. V2 adds constText immediately after constFloatBits. Unused attributes still follow the codec; fields are not arbitrarily optional.

| Authoritative source | Contents |
| --- | --- |
| [SublangWire.ems](../src/sublang/wire/SublangWire.ems) | Header, features, versions and section ordering |
| [SublangWireStream.ems](../src/sublang/wire/SublangWireStream.ems) | Netstrings, numeric parsing, offsets and budgets |
| [SublangWireTables.ems](../src/sublang/wire/SublangWireTables.ems) | Sources/types/fields/profiles/failures |
| [SublangWireEffects.ems](../src/sublang/wire/SublangWireEffects.ems) | Locations, aliases, effects and proof metadata |
| [SublangWireBody.ems](../src/sublang/wire/SublangWireBody.ems) | Functions, parameters, blocks and operation attributes |

A foreign writer must implement complete records, not text replacement on dumps. Keep IDs/field order consistent; remapping requires updating all references. Check representative output against the reference codec, including UTF-8, empty sequences, CFG edges and ownership metadata.

Existing [Wire examples](../examples/wire/readme.md) are concrete inputs. V1 inputs with core.native64.v1 remain readable; String/List/Bond require v2. Unknown/duplicate features, trailing bytes and unsupported stages/revisions fail. No permanent public ABI is promised yet; pin compatible compiler/frontend versions.

### Standalone process interface

```text
sublang --version
sublang emit-llvm INPUT.sublang-wire OUTPUT.ll auto|on|off on|off
```

The last arguments are positional: Flow, then Optimind. This differs from the launcher's --flow= syntax. Keep custom process integrations sandboxed; use the supplied launcher for repository work.

Success writes OUTPUT.ll and OUTPUT.ll.plan. Exit codes: 0 success, 1 invalid IR/codegen/write failure, 2 CLI/input error. The binary does not internally launch LLVM/Clang; the launcher or your buildsystem performs verification, optimization and linking.

### In-process Emerald API

SublangCompiler.compile(frozenModule, optimindBool, flowMode) returns codegenReady(), error(), llvm() and explainMemory(). Forward output only after successful readiness. LLVM generation alone is not native linking.

## 13. Verification and diagnostics

The validation layers are separate:

1. Transport: framing, counts, numeric limits, versions and ordering.
2. Generic IR: structure, types, dominance and compatible semantic records.
3. Native gate: supported features/bindings, budgets, entry, initialization, ownership, borrows and lifetime.
4. LLVM: emitted LLVM verified before/after selected LLVM passes.

Generic effects/memory statuses of not_checked are not complete proofs. Native codegen performs additional bounded checks. Structural validity does not grant every proposed platform capability.

### Effects and aliasing

Functions initially receive conservative summaries. Areas include allocation, escape, failure, exceptions, memory-read/write, synchronization, observable and control. Provenance is declared, assumed-conservative or proven; LocationIds represent logical memory.

Purity/noescape/NoAlias declarations cannot substitute for proofs. Imported proven labels do not automatically authorize call elimination or NoAlias. Existing closed-body transformations derive their own evidence. Missing aliases remain conservative; borrow_read is not a full call-effect contract.

See [IR Contracts](Sublang_IR_Contracts.md) for broader architecture requirements. Illustrative opcodes there are not automatically executable.

### Troubleshooting

| Symptom | Cause/remedy |
| --- | --- |
| SUBLANG-W001 and byte offset | Check token byte lengths, ordering and versions |
| SUBLANG-B001 | Freeze before compilation |
| SUBLANG-B002 | Generic verification failed; inspect diagnosis |
| SUBLANG-B004 | Unsupported type/operation/contract/runtime binding |
| SUBLANG-B005 and FunctionId | Initialization/ownership/lifetime violation |
| SUBLANG-B006 | Entry is not () -> Int |
| SUBLANG-B007 | Invalid Flow option |
| SUBLANG-C001 | Flow forced on for C without importer |
| Use after move | Borrow from the new owner or copy values before transfer |
| View after mutation | Read first or create a fresh valid view |
| Uninitialized field | Initialize every path; clear empty Ref fields explicitly |
| Invalid merge | Correct block parameters and incoming argument counts/types |
| Runtime abort | Possible overflow, bounds error, empty child or allocation failure |

A lifetime rejection is not necessarily an optimizer defect. Disabling Flow does not authorize unsafe references.

### Budgets

Wire: 16 MiB/file, 64 KiB/token, 262,144 counted entries. Native: 32 functions, 512 types/fields, 64 blocks and 4,096 values/function, 4,096 operations/block, 32,768 operations/module. Scope IDs are bounded. Lifetime analysis limits receiver/field pairs to 512/function and fixed-point rounds to 16,384.

These development limits require deliberate analysis/budget expansion for larger frontends. Raising constants alone does not establish scalable behavior.

## 14. Frontend integration workflow

Executable today: closed functions/direct calls, scalar signatures/block arguments, loops, i64/f64, primitive/String Records, Class fields/scopes, exclusive graphs/views, mutable borrow calls, owned parameters/results, static Strings, supported lists and Bond graphs. All eight Flow families have native paths.

Not yet generally executable: Dynamic/JIT, EH unwinding/cleanup, closures, inheritance/virtual dispatch, unknown externals, arbitrary Ref phi nodes, foreign runtime ABIs, general LLVM-to-High-IR ownership import and public serialized Low IR. C goes through Clang/LLVM without High-IR ownership proofs.

Language independence means no Emerald AST coupling; it does not mean all language semantics is implemented. Do not replace missing contracts with similar-looking operations.

Recommended sequence:

1. Parse and resolve names/types/evaluation order.
2. Declare types, fields, source locations and failure actions.
3. Create signatures and concrete direct call targets.
4. Build CFG, terminators and SSA block arguments.
5. Emit values/memory operations with correct ownership metadata.
6. Represent mutation, empty fields, moves and view invalidation.
7. Set entry, freeze and serialize complete Wire records if needed.
8. Handle diagnostics; forward only valid LLVM.
9. Verify/optimize/link and inspect unexpected memory decisions.

Start with a representative program including a branch, a call and the required memory model. A single passing example does not prove complete language compatibility or performance parity.

## 15. Source and example reference

| Source | Responsibility |
| --- | --- |
| [SublangBuilder.ems](../src/sublang/ir/SublangBuilder.ems) | Module/types/fields/functions/parameters/blocks |
| [SublangOperationBuilder.ems](../src/sublang/ir/SublangOperationBuilder.ems) | Constants/arithmetic/aggregates/fields/calls/terminators |
| [SublangCollectionBuilder.ems](../src/sublang/ir/data/SublangCollectionBuilder.ems) | List operations |
| [SublangBondBuilder.ems](../src/sublang/ir/data/SublangBondBuilder.ems) | Shared roots/edges and exclusive children |
| [SublangCompiler.ems](../src/sublang/backend/SublangCompiler.ems) | Frozen High IR to LLVM and memory plan |

| Existing input | Result | Coverage |
| --- | --- | --- |
| [root-tree.ems](../examples/programs/root-tree.ems) | 42 | Factory return, take and clear |
| [static-string.sublang-wire](../examples/wire/static-string.sublang-wire) | 200 | UTF-8 bytes, static storage/equality/length |
| [inline-list.sublang-wire](../examples/wire/inline-list.sublang-wire) | 199 | 100 Inline Points, growth and view |
| [inline-local.sublang-wire](../examples/wire/inline-local.sublang-wire) | 42 | Mutable call before Local-to-Inline transfer |
| [owned-list.sublang-wire](../examples/wire/owned-list.sublang-wire) | 199 | Stable elements with owned children |
| [value-list.sublang-wire](../examples/wire/value-list.sublang-wire) | 42 | Record values |
| [nested-regions.sublang-wire](../examples/wire/nested-regions.sublang-wire) | 28 | Dependent nested backing |
| [bond-cycle.sublang-wire](../examples/wire/bond-cycle.sublang-wire) | 55 | Cycle, owned call and exclusive child |
| [bond-component.sublang-wire](../examples/wire/bond-component.sublang-wire) | 4242 | SCC cache and graph mutation |

Construction code: [SublangFullFlowFixtures.ems](../src/sublang/harness/flow/SublangFullFlowFixtures.ems), [SublangBondComponentFixture.ems](../src/sublang/harness/flow/SublangBondComponentFixture.ems).

Further reading: [Wire](Sublang_Wire.md), [HyperAlloc contracts](HyperAlloc_IR.md), [Native Slice](Sublang_Native_Slice.md), [Flow parity](Flow_Parity.md), [C support](Sublang_C_Support.md), [IR contracts](Sublang_IR_Contracts.md), [roadmap](Roadmap.md).

New tutorial builders were checked against the APIs, not separately compiled for this documentation-only change. Existing Wire inputs/results come from the native backend's bundled sandbox checks.
