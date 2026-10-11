# Sublang diagnostics catalog

Status: analysis of the source as it stood at the time of the scan. Read-only; no source file was edited.
Machine-readable companion: `docs/diagnostic-codes.tsv`.

Roadmap references: section 7 ("Structured decisions/diagnostics with stable codes, entities, revisions and blockers") and section 1 ("Keep failure behavior and unsupported-feature diagnostics deterministic"), both in `docs/Roadmap.md`.

## Scope and method

- Searched: every `.ems` file under `src/` (220 lines carry a `SUBLANG-` code with a 3-digit suffix; 3 more carry other `SUBLANG-` tokens: the `SUBLANG-WIRE` magic on two lines and the `S`/`T` prefix test in `SublangVocabulary.ems:192`), `scripts/*.sh`, `docs/*.md`, root the maintainers' internal planning notes and the maintainers' internal planning notes, and `examples/`.
- Each emission was classified as a diagnostic emitter (`report`, `reportBlocked`, a returned or printed string, or a shell `echo`) or as an assertion (harness, smoke test, `startsWith` check, wire-check). Assertions are listed separately.
- Totals: 189 emission sites (188 in `src/`, 1 in `scripts/sublang-build.sh`) and 32 assertion sites, covering 47 distinct codes. Every code that is asserted is also emitted; 21 emitted codes are never asserted.
- Snapshot: `src/` was copied and scanned as a frozen snapshot. Files in the live repository changed during the run (`src/sublang/cli/SublangCommand.ems` at 00:53 and `src/sublang/backend/SublangCompiler.ems` at 00:57), so line numbers in this document describe the snapshot. A final `diff -r` against the live tree was run before writing; see the verification note at the end.
- Every row of `docs/diagnostic-codes.tsv` was checked by a script that re-reads the cited source line and asserts that the code token is on it.

## Naming scheme (as used)

Format: `SUBLANG-<FAMILY><NNN>`, where `NNN` is three digits. The family is one letter, except for `CLI`.

| Family | Codes in use | Meaning in practice | Dimension (`SublangVocabulary.dimensionOf`, `src/sublang/vocabulary/SublangVocabulary.ems:191-196`) |
| --- | --- | --- | --- |
| `S` | S001-S008 (all used) | IR well-formedness: unknown enum values, dangling ids, CFG shape, dominance | structure |
| `T` | T001-T006 (all used) | Type rules, operand/argument shape, ownership rules, Void and bare class | structure |
| `A` | A001-A003 | Attribute modes: overflow, floating-point mode, compare predicate | semantics |
| `E` | E001-E004, E006, E007 (E005 unused) | Effect summaries, alias facts, evidence | semantics |
| `F` | F001-F003 | Failure actions | semantics |
| `P` | P001-P003 | Semantic profiles | semantics |
| `U` | U001, U003-U006 (U002 unused) | Features outside Sublang v0.1 | semantics |
| `B` | B001-B008 | Backend gate: budget, host-libc target limits, lifetime, entry, flow option | not classified (never becomes a `SublangDiagnostic`) |
| `W` | W001 | Wire transport (decode and write) | not classified |
| `CLI` | CLI001-CLI003 | Command-line arguments, input and output | not classified |
| `C` | C001 | C frontend option conflict; exists only in the launcher script | not classified |

Same prefix, different meaning (not diagnostics):

- `SUBLANG-WIRE` is the wire magic header (`src/sublang/wire/SublangWire.ems:28`, examples under `examples/wire/`).
- `SUBLANG-R01` to `SUBLANG-R14` are requirement IDs in the maintainers' internal planning notes (not part of this repository). They use two digits, so the three-digit pattern does not match them, but they share the prefix.
- `EOS-*` is the retired prefix; `docs/Sublang_Naming_Migration.md:17` maps it to `SUBLANG-*`. No `EOS-` token remains in `src/`.

Dimension rule: `S` and `T` are "structure"; everything else, including any unrecognised prefix, is "semantics". The rule is string-prefix based and is the only place that maps families to dimensions.

## Where codes come from (phase order)

Exit codes of `sublang emit-llvm` / `sublang dump` (`src/sublang/cli/SublangCommand.ems`, consistent with `docs/Sublang_Wire.md:25-27`): 0 success; 1 invalid IR, compile failure or write failure; 2 usage or input error.

Order of checks on the `emit-llvm` path:

1. `CLI001`, `CLI002` (arguments, input size) - exit 2.
2. `W001` (wire decode via `SublangWire.read`, which also freezes the module) - exit 1.
3. `SublangCompiler.compile`: `B007` (Flow option), then `SublangBackendGate.check`:
   1. `B001` (not frozen)
   2. `B003`, `B008` (budget, `SublangBackendBudget`)
   3. verifier: all `S`, `T`, `A`, `E`, `F`, `P`, `U` findings. Only the first one reaches the caller, re-emitted as `B002` with that diagnostic's own code, message and position (`SublangBackendGate.ems:25`, `verifierFinding` at line 43).
   4. `B004` (record field types, failure bindings, external contracts, reference parameter modes)
   5. `B005` (lifetime, `SublangLocalLifetime`)
   6. `B006` (entry signature)
4. `CLI003` (after the output is written and checked) - exit 1.

The `dump` command runs no verifier (its own comment says so at `SublangCommand.ems:37`); it can only print `W001` and `CLI002`.

## Catalog

One row per code. "Emitted by" lists the first three sites (repo-relative, from the snapshot); the TSV lists all sites. "Asserted by" lists harness or smoke checks that expect the code. Example triggers were derived from the message and, where a harness case exists, that case name is given. The triggers were not executed.

| Code | Meaning | Emitted by (file:line) | Phase, dimension, exit | Example trigger | Asserted by |
| --- | --- | --- | --- | --- | --- |
| `SUBLANG-A001` | Arithmetic op with no overflow mode (int) or floating-point mode (float) | `src/sublang/checks/operation/SublangArithmeticChecks.ems:75`<br>`src/sublang/checks/operation/SublangArithmeticChecks.ems:101` | verifier, semantics; CLI shows B002, exit 1 | int.add without an overflow mode (harness missing-overflow) | yes: `src/sublang/harness/SublangHarnessRejected.ems:72` |
| `SUBLANG-A002` | Trapping overflow or division by zero without a failure action | `src/sublang/checks/operation/SublangArithmeticChecks.ems:82` | verifier, semantics; CLI shows B002, exit 1 | int.add with overflow=trap and no fail action (harness missing-overflow) | yes: `src/sublang/harness/SublangHarnessRejected.ems:73` |
| `SUBLANG-A003` | Attribute not allowed: overflow mode for op, fp mode other than rne, float compare without ordered/unordered predicate, unknown predicate, ordering predicate on Bool/Ref | `src/sublang/checks/operation/SublangArithmeticChecks.ems:78`<br>`src/sublang/checks/operation/SublangArithmeticChecks.ems:105`<br>`src/sublang/checks/operation/SublangArithmeticChecks.ems:165`<br>+2 more (see TSV) | verifier, semantics; CLI shows B002, exit 1 | float compare with a generic predicate (harness float-generic-predicate) | yes: `src/sublang/harness/SublangHarnessRejected.ems:92` |
| `SUBLANG-B001` | Backend input snapshot is not frozen | `src/sublang/backend/SublangBackendGate.ems:15` | backend gate, first step; exit 1 | Module passed to SublangCompiler.compile without freeze() (CLI cannot reach it: SublangWire.read freezes) | no |
| `SUBLANG-B002` | Verifier rejected the module. Carries the first verifier diagnostic's own code and message, and its position as ` (line L, column C)` when the span is known | `src/sublang/backend/SublangBackendGate.ems:25` (call), `:43` (`verifierFinding`) | backend gate after B003/B008 budget; exit 1 | Any verifier error through emit-llvm, e.g. a dominance violation (harness dominance expects S007 at API level, prints as `SUBLANG-B002: SUBLANG-S007 ... (line L, column C)` on CLI) | yes: `src/SublangBackendSmoke.ems:460`, `scripts/sublang-tiny-check.sh:57` |
| `SUBLANG-B003` | Backend budget exceeded: >32 functions, >512 types or fields, >64 blocks, >4096 values or block ops, >32768 operation ids or scope ids | `src/sublang/backend/SublangBackendBudget.ems:25`<br>`src/sublang/backend/SublangBackendBudget.ems:38`<br>`src/sublang/backend/SublangBackendBudget.ems:43`<br>+3 more (see TSV) | budget, before verifier; exit 1 | module with 33 functions | no |
| `SUBLANG-B004` | Construct unsupported by the host-libc target: failure binding, non-primitive record field, external contract, reference parameter passing mode | `src/sublang/backend/SublangBackendGate.ems:33`<br>`src/sublang/backend/SublangBackendGate.ems:47`<br>`src/sublang/backend/SublangBackendGate.ems:59`<br>+1 more (see TSV) | backend gate, after verifier and type gate; exit 1 | failure action bound to a binding other than libc.abort or unbound | no |
| `SUBLANG-B005` | Ownership, initialization or lifetime violation; prefixed with 'fn<N>:' and followed by a lifetime message | `src/sublang/backend/SublangBackendGate.ems:73` | lifetime analysis, backend gate, after B004 checks; exit 1 | Use after move: a Ref is consumed and then read (docs/Sublang_IR_Guide.md troubleshooting table) | yes: `src/SublangBackendSmoke.ems:221`, `src/SublangBackendSmoke.ems:305`, `src/SublangBackendSmoke.ems:373` (+2) |
| `SUBLANG-B006` | Executable entry function is not () -> i64 | `src/sublang/backend/SublangBackendGate.ems:86` | backend gate, after function checks; exit 1 | entry function that takes one parameter | no |
| `SUBLANG-B007` | Invalid Flow option passed to the compiler | `src/sublang/backend/SublangCompiler.ems:16` | SublangCompiler.compile before the gate; exit 1 on emit-llvm (the launcher rejects first with exit 2 and no code) | sublang emit-llvm in.sublang-wire out.ll auto maybe (flow=bogus is wrong, the 4th argument is the Flow mode) | no |
| `SUBLANG-B008` | Duplicate operation id (ids become LLVM SSA names) | `src/sublang/backend/SublangBackendBudget.ems:65` | budget, before verifier; exit 1 | two operations with the same id in one module | yes: `src/SublangBackendSmoke.ems:536` |
| `SUBLANG-C001` | --flow=on for a C source; C ownership import is not implemented | `scripts/sublang-build.sh:39` | launcher script, before any compile; exit 2 | scripts/sublang-build.sh src.c --flow=on | no |
| `SUBLANG-CLI001` | Optimind argument is not on or off | `src/sublang/cli/SublangCommand.ems:52` | CLI argument check; exit 2 | sublang emit-llvm in.sublang-wire out.ll auto maybe | no |
| `SUBLANG-CLI002` | Input is not a regular file or exceeds 16 MiB (emitted by dump and emit-llvm) | `src/sublang/cli/SublangCommand.ems:40`<br>`src/sublang/cli/SublangCommand.ems:54` | CLI input check; exit 2 | sublang dump missing.sublang-wire | no |
| `SUBLANG-CLI003` | Output could not be written, or its size differs after writing | `src/sublang/cli/SublangCommand.ems:63` | CLI, after compile succeeds; exit 1 | output path in a directory that does not exist or is not writable | no |
| `SUBLANG-E001` | Reference to a nonexistent effect summary (from a function or an operation) | `src/sublang/checks/SublangSemanticChecks.ems:171`<br>`src/sublang/checks/operation/SublangOperationChecks.ems:45` | verifier, semantics; CLI shows B002, exit 1 | call operation naming an effect summary id that does not exist (harness dangling-references-rejected) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:117` |
| `SUBLANG-E002` | Effect summary or alias fact has unknown provenance, area or origin, or gives a value for an area | `src/sublang/checks/SublangSemanticChecks.ems:99`<br>`src/sublang/checks/SublangSemanticChecks.ems:106`<br>`src/sublang/checks/SublangSemanticChecks.ems:110`<br>+1 more (see TSV) | verifier, semantics; CLI shows B002, exit 1 | effect summary with an unknown area name | no |
| `SUBLANG-E003` | Effect or alias evidence lacks current revision or valid dependencies | `src/sublang/checks/SublangEvidenceChecks.ems:22`<br>`src/sublang/checks/SublangEvidenceChecks.ems:36`<br>`src/sublang/checks/SublangSemanticChecks.ems:146` | verifier, semantics; CLI shows B002, exit 1 | evidence left stale after a revision change (harness evidence-boundaries) | yes: `src/sublang/harness/SublangHarnessBoundaries.ems:137` |
| `SUBLANG-E004` | Effect summary omits a required area (a missing area is not 'none') | `src/sublang/checks/SublangSemanticChecks.ems:79` | verifier, semantics; CLI shows B002, exit 1 | summary without one of the required areas (harness effects-incomplete) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:55` |
| `SUBLANG-E006` | Effect or alias fact refers to an unknown logical location, or has an unknown answer | `src/sublang/checks/SublangEvidenceChecks.ems:33`<br>`src/sublang/checks/SublangSemanticChecks.ems:152`<br>`src/sublang/checks/SublangSemanticChecks.ems:155` | verifier, semantics; CLI shows B002, exit 1 | alias fact naming a location id that does not exist (harness dangling-references-rejected) | yes: `src/sublang/harness/SublangHarnessBoundaries.ems:138`, `src/sublang/harness/SublangHarnessSemantics.ems:118` |
| `SUBLANG-E007` | Alias fact claims a precise answer from an assumed-conservative origin; emitted as a blocked finding (blocker alias:a,b) | `src/sublang/checks/SublangSemanticChecks.ems:164` | verifier, semantics (reportBlocked); CLI shows B002, exit 1 | NoAlias claim with conservative provenance (harness alias-noalias-unproven) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:81` |
| `SUBLANG-F001` | Failure action incomplete: binding or signature missing | `src/sublang/checks/SublangSemanticChecks.ems:52` | verifier, semantics; CLI shows B002, exit 1 | failure action with no binding (harness failure-incomplete) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:65` |
| `SUBLANG-F002` | abort signature is not noreturn void() | `src/sublang/checks/SublangSemanticChecks.ems:49` | verifier, semantics; CLI shows B002, exit 1 | abort declared with a non-void signature (harness failure-signature) | yes: `src/sublang/harness/SublangHarnessBoundaries.ems:77` |
| `SUBLANG-F003` | Failure action continues; abort never returns | `src/sublang/checks/SublangSemanticChecks.ems:43` | verifier, semantics; CLI shows B002, exit 1 | abort with continue behavior (harness failure-records-rejected) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:98` |
| `SUBLANG-P001` | Function refers to a semantic profile that does not exist | `src/sublang/checks/SublangSemanticChecks.ems:177` | verifier, semantics; CLI shows B002, exit 1 | profile id that is not defined (harness profile-invalid-id) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:25` |
| `SUBLANG-P002` | Profile uses rules outside the v0.1 startup set (not supported) | `src/sublang/checks/SublangSemanticChecks.ems:182` | verifier, semantics; CLI shows B002, exit 1 | profile with an unsupported rule (harness profile-unsupported-rule) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:43` |
| `SUBLANG-P003` | Op names a rounding mode that the function's profile does not provide | `src/sublang/checks/operation/SublangArithmeticChecks.ems:116` | verifier, semantics; CLI shows B002, exit 1 | fp op with a rounding mode the profile lacks (harness fp-mode-profile-mismatch) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:136` |
| `SUBLANG-S001` | Unknown value of an enumerated field (linkage, definition kind, passing mode, type kind, location kind, opcode) | `src/sublang/checks/SublangFunctionChecks.ems:35`<br>`src/sublang/checks/SublangFunctionChecks.ems:41`<br>`src/sublang/checks/SublangFunctionChecks.ems:56`<br>+5 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | call operand with an unknown passing mode (harness a0-unknown-mode) | yes: `src/sublang/harness/SublangHarnessRejected.ems:162` |
| `SUBLANG-S002` | Undefined or dangling reference (type, field, value, function, block, scope, failure action). Also missing source span (span 0) and foreign or duplicate field lists | `src/sublang/analysis/SublangVerifier.ems:77`<br>`src/sublang/checks/SublangFlowChecks.ems:104`<br>`src/sublang/checks/SublangFlowChecks.ems:193`<br>+21 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | record.make with an unknown field id (harness a0-unknown-field); block parameter of undefined type (harness a0-block-param-type) | yes: `src/sublang/harness/SublangHarnessRejected.ems:133`, `src/sublang/harness/SublangHarnessRejected.ems:185` |
| `SUBLANG-S003` | Value defined more than once or never; scope begun more than once | `src/sublang/checks/SublangFlowChecks.ems:118`<br>`src/sublang/checks/SublangFlowChecks.ems:121`<br>`src/sublang/checks/operation/SublangControlChecks.ems:122` | verifier, structure; CLI shows B002, exit 1 | two operations defining the same value id | no |
| `SUBLANG-S004` | Block or function shape: no blocks, no terminator, terminator not last, external contract with a body | `src/sublang/checks/SublangFlowChecks.ems:31`<br>`src/sublang/checks/SublangFlowChecks.ems:131`<br>`src/sublang/checks/SublangFlowChecks.ems:163`<br>+2 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | block whose last operation is not a terminator | no |
| `SUBLANG-S005` | Arity or shape of control flow and operand lists: branch targets, cond_branch splits, block argument counts, operand count vs passing-mode count | `src/sublang/checks/SublangFlowChecks.ems:35`<br>`src/sublang/checks/operation/SublangControlChecks.ems:157`<br>`src/sublang/checks/operation/SublangControlChecks.ems:171`<br>+4 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | branch to a block with 2 parameters that passes 1 argument | no |
| `SUBLANG-S006` | Value used before its definition in the same block | `src/sublang/checks/SublangFlowChecks.ems:216` | verifier, structure; CLI shows B002, exit 1 | operation reads v5 before the operation that defines v5 | no |
| `SUBLANG-S007` | Use not dominated by its definition, or definition in an unreachable block | `src/sublang/checks/SublangFlowChecks.ems:211`<br>`src/sublang/checks/SublangFlowChecks.ems:221` | verifier, structure; CLI shows B002, exit 1 | use in a block the definition does not dominate (harness dominance) | yes: `src/sublang/harness/SublangHarnessRejected.ems:50` |
| `SUBLANG-S008` | Block unreachable from the entry block | `src/sublang/checks/SublangFlowChecks.ems:144` | verifier, structure; CLI shows B002, exit 1 | extra block with no incoming branch | no |
| `SUBLANG-T001` | Type mismatch, or wrong operand/result count for typed operations (arithmetic, compare, record, scope, fail, return, branch argument) | `src/sublang/checks/SublangTypeChecks.ems:161`<br>`src/sublang/checks/data/SublangStringChecks.ems:17`<br>`src/sublang/checks/data/SublangStringChecks.ems:31`<br>+31 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | int.add on a non-Int operand (harness type-error) | yes: `src/sublang/harness/SublangHarnessRejected.ems:24` |
| `SUBLANG-T002` | Argument, parameter, receiver or passing-mode mismatch; wrong call arity; void call result misuse | `src/sublang/checks/SublangFunctionChecks.ems:69`<br>`src/sublang/checks/SublangFunctionChecks.ems:72`<br>`src/sublang/checks/SublangFunctionChecks.ems:86`<br>+16 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | call with the wrong number of arguments | no |
| `SUBLANG-T003` | Wrong kind of type for an operation or descriptor (Ref target, List/Bond layout, record vs class, field owner) | `src/sublang/checks/SublangFunctionChecks.ems:82`<br>`src/sublang/checks/SublangTypeChecks.ems:50`<br>`src/sublang/checks/SublangTypeChecks.ems:53`<br>+12 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | Ref whose target is not a class type | no |
| `SUBLANG-T004` | Reference ownership or destination-scope rule violated | `src/sublang/checks/operation/SublangControlChecks.ems:108`<br>`src/sublang/checks/operation/SublangControlChecks.ems:151`<br>`src/sublang/checks/operation/SublangMemoryChecks.ems:190`<br>+5 more (see TSV) | verifier, structure; CLI shows B002, exit 1 | class.new that produces a borrowed rather than owned reference | no |
| `SUBLANG-T005` | Void or bare class used as a value, parameter or return type | `src/sublang/checks/SublangFunctionChecks.ems:29`<br>`src/sublang/checks/SublangFunctionChecks.ems:122`<br>`src/sublang/checks/SublangFunctionChecks.ems:126` | verifier, structure; CLI shows B002, exit 1 | parameter of bare class type (harness a0-bare-class-param) | yes: `src/sublang/harness/SublangHarnessRejected.ems:215` |
| `SUBLANG-T006` | Primitive descriptor with an unsupported width or sign | `src/sublang/checks/SublangTypeChecks.ems:112` | verifier, structure; CLI shows B002, exit 1 | primitive with an unsupported width (harness a0-unsupported-width) | yes: `src/sublang/harness/SublangHarnessRejected.ems:199` |
| `SUBLANG-U001` | Outside v0.1: nullable references, non-primitive fields, field.read/field.write on non-primitive fields | `src/sublang/checks/SublangTypeChecks.ems:67`<br>`src/sublang/checks/SublangTypeChecks.ems:166`<br>`src/sublang/checks/operation/SublangMemoryChecks.ems:276`<br>+1 more (see TSV) | verifier, semantics; CLI shows B002, exit 1 | Ref type declared nullable | no |
| `SUBLANG-U003` | Calling convention other than sublang | `src/sublang/checks/SublangFunctionChecks.ems:38` | verifier, semantics; CLI shows B002, exit 1 | function with a C calling convention | no |
| `SUBLANG-U004` | Failure behavior other than abort | `src/sublang/checks/SublangSemanticChecks.ems:40` | verifier, semantics; CLI shows B002, exit 1 | failure action with behavior other than abort (harness failure-records-rejected) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:99` |
| `SUBLANG-U005` | Failure action declares unwinding | `src/sublang/checks/SublangSemanticChecks.ems:46` | verifier, semantics; CLI shows B002, exit 1 | failure action with unwinding declared (harness failure-records-rejected) | yes: `src/sublang/harness/SublangHarnessSemantics.ems:100` |
| `SUBLANG-U006` | Call to an external function needs a trusted provider contract; emitted as a blocked finding (blocker call:<name>) | `src/sublang/checks/operation/SublangControlChecks.ems:62` | verifier, semantics (reportBlocked); CLI shows B002, exit 1 | call to host_clock (harness external-call, blocker call:host_clock) | yes: `src/sublang/harness/SublangHarnessRejected.ems:112` |
| `SUBLANG-W001` | Malformed or unsupported wire input: bad token or length, unknown or duplicate feature, unsupported transport version or schema, trailing data, input over 16 MiB; also a writer given an unfrozen module. Message is prefixed with the byte offset | `src/sublang/wire/SublangWireStream.ems:36` | wire decode (dump, emit-llvm) and wire write; exit 1 | sublang dump on an empty file (SublangWireChecks reads "") | no |

## Findings

Inconsistencies found, ordered by impact. File references are to the snapshot.

1. **Fixed: the CLI used to hide the verifier codes and positions.** Before, `SublangBackendGate.ems` replaced the verifier result with `SUBLANG-B002: <message>` and dropped the `S`, `T`, `A`, `E`, `F`, `P` and `U` code and the source span. The gate now keeps the verifier's own code and position: `SUBLANG-B002: <code> <message> (line L, column C)` (`verifierFinding`, `SublangBackendGate.ems:43`; checked by `scripts/sublang-tiny-check.sh:57`). The position is printed only when the span id is greater than 0 and within the module, so a span-less finding prints without `(line, column)`. Still open: only the first finding is reported, and the entity and blocker are not part of the output.

2. **Codes are stringly typed with no registry.** The 189 emission sites repeat literal strings. Nothing defines the set of valid codes, checks that a code is documented, or prevents a typo. The only code-aware logic is the prefix test in `dimensionOf` (`SublangVocabulary.ems:191-196`), which silently sends any unknown family to "semantics". `B`, `CLI`, `W` and `C` never reach `SublangDiagnostic`, so they have no dimension, entity, revision or blocker fields (roadmap section 7 asks for all of these).

3. **The same condition has a different code or no code in the script.** Invalid Flow mode: `scripts/sublang-build.sh:26` prints `Invalid Flow mode` with no code and exits 2; the compiler path emits `SUBLANG-B007` (`SublangCompiler.ems:16`) and exits 1. Invalid Optimind mode: `scripts/sublang-build.sh:27` is uncoded (exit 2), while `CLI001` (`SublangCommand.ems:52`) is coded (exit 2). For Flow the exit codes differ (2 in the script, 1 in the compiler). The script omits the code for both.

4. **Unsupported-in-v0.1 features are spread over six places.** `U001`, `U003`-`U006` are the "unsupported" family, but the same kind of message also appears as `A003` ("floating-point mode ... is not supported in Sublang v0.1", `SublangArithmeticChecks.ems:105`), `P002` ("... not supported in v0.1", `SublangSemanticChecks.ems:182`), `T006` ("unsupported width", `SublangTypeChecks.ems:112`), and `B004` (host-libc target limits, `SublangBackendGate.ems:33,47,59,66`). Roadmap section 1 asks for deterministic unsupported-feature diagnostics; a reader cannot tell "unsupported" from the family.

5. **`U002` is documented and never emitted; `E005` is neither.** the maintainers' internal planning notes lists `SUBLANG-U001–U002`. No source or script emits `U002`, and nothing reserves it. `E005` is absent from both source and documentation without a note.

6. **A documented rule contradicts the source.** the maintainers' internal planning notes says a float compare is rejected with `SUBLANG-U001`. The source emits `A003` only when the predicate is missing or unknown (`SublangArithmeticChecks.ems:163-166`) and accepts a valid ordered or unordered predicate. `U001` is never emitted for compares.

7. **`C001` exists only in the launcher.** It is printed by `scripts/sublang-build.sh:39` and documented in `docs/Sublang_C_Support.md:47` and `docs/Sublang_IR_Guide.md:623`, but no `.ems` file emits it. The launcher is the only owner of a code that describes a frontend option.

8. **Argument-count errors use three codes.** Operand count: `T001` (for example `SublangArithmeticChecks.ems:48`, `SublangControlChecks.ems:115`). Call argument count: `T002` (`SublangControlChecks.ems:75`). Block argument count and operand/passing-mode count: `S005` (`SublangControlChecks.ems:202`, `SublangOperationChecks.ems:48`).

9. **Void is coded three ways.** A Void field is `T001` (`SublangTypeChecks.ems:161`). A Void value is `T005` (`SublangFunctionChecks.ems:122`). A call result on a void function is `T002` (`SublangControlChecks.ems:100`).

10. **Duplicates use two codes.** A value defined twice and a scope begun twice are `S003` (`SublangFlowChecks.ems:121`, `SublangControlChecks.ems:122`). A field listed twice is `S002` (`SublangTypeChecks.ems:91`).

11. **`S002` covers at least four different things.** It is used for undefined references (most of its 24 sites), for a missing source span with span 0 (`SublangTypeChecks.ems:43`, `SublangOperationChecks.ems:42`, `SublangVerifier.ems:77`), for field lists that name a foreign or duplicate field (`SublangTypeChecks.ems:88,91`), and for a scope that is missing or never begun (`SublangControlChecks.ems:118,131`, `SublangMemoryChecks.ems:187,239`).

12. **Some messages have no code of their own.**
    - Lifetime analysis (`src/sublang/hyperalloc/SublangLocalLifetime.ems`) returns about 60 uncoded message literals. All of them are folded into `B005` with the function id.
    - The Bond, List and String data checks return plain text (`SublangBondChecks.ems:11`, `SublangCollectionChecks.ems:11`, `SublangStringChecks.ems:17,23,31`); the caller picks one code for each family, which hides the cause.
    - The CLI usage line (`SublangCommand.ems:48`, exit 2) has no code.
    - The shell scripts print about 15 uncoded messages (`scripts/sublang-build.sh:22-30,36,49,71`, `scripts/sublang-build-worker.sh:34`, `scripts/check-sandbox.sh:7-10`).

13. **Wire errors share one code and a meaningless offset for writes.** All 27 `reject()` call sites across five wire files produce `W001`, so bad tokens, unknown features and trailing data are indistinguishable. The writer precondition (`SublangWire.ems:22`) also goes through `reject()` and reports "at byte N" for an output stream.

14. **`B003` covers five limits.** The six sites in `SublangBackendBudget.ems` (lines 25, 38, 43, 48, 49, 62) cover module, function, block, scope-id and operation limits; the two scope-id sites share the code with the others. The code alone cannot tell which limit was hit.

15. **Twenty-one emitted codes are never asserted.** The harness and smoke tests do not check: B001, B003, B004, B006, B007, C001, CLI001, CLI002, CLI003, E002, S003, S004, S005, S006, S008, T002, T003, T004, U001, U003, W001. The wire check (`src/sublang/harness/flow/SublangWireChecks.ems:14`) asserts `valid() == false` only, not the code text.

16. **Requirement IDs share the diagnostic prefix.** `SUBLANG-R01` to `SUBLANG-R14` (the maintainers' internal planning notes) use the same prefix as diagnostics. Searching the repository for `SUBLANG-` returns both; a future `R` family would collide.

17. **Entities and revisions exist only on the verifier path.** `SublangReport.ems:69` records the revision and the function, block and operation of each finding. The backend path carries none of that; `B005` only has the function id as text (`SublangBackendGate.ems:73`). Roadmap section 7 needs the same fields on every diagnostic.

Checked and not an inconsistency: `E007` and `U006` are the only `reportBlocked` sites, so blockers are used exactly where a feature is not proven. The `S001` (enum value) and `S002` (id reference) split for "unknown" is consistent and could be documented as a rule.

## Proposed code-range allocation (PROPOSAL, not implemented)

Rules: codes are never renumbered or reused. A retired code keeps its row with a "retired" note. New codes take the next free number in their family. Emitters go through one table (see the TSV) so that the set of codes is checked.

| Family | Scope | Existing codes | Proposed range | Notes |
| --- | --- | --- | --- | --- |
| `S` | IR well-formedness | S001-S008 | S001-S099 | Keep the current split; document the rule for `S001` (enum) vs `S002` (reference). Give span-less findings their own code instead of `S002`. |
| `T` | Types, shapes, ownership | T001-T006 | T001-T099 | Put arity errors under one code (proposed `T007` for operand count, `T008` for call arity) and retire the `S005` arity use. |
| `A` | Attribute modes | A001-A003 | A001-A099 | `A003` keeps invalid-mode meanings only; "not supported" moves to `U`. |
| `E` | Effects, alias, evidence | E001-E007 (E005 reserved) | E001-E099 | Keep E005 reserved, not reusable. |
| `F` | Failure actions | F001-F003 | F001-F099 | No change. |
| `P` | Semantic profiles | P001-P003 | P001-P099 | `P002` moves to `U` if it is a feature gate. |
| `U` | Unsupported in v0.1 or later | U001, U003-U006 (U002 reserved) | U001-U099 | Single home for "not supported". Move `A003` (fp mode), `P002` and `T006` (width) here, each with a new number. |
| `B` | Backend gate | B001-B008 | B001-B099 | Keep `B002` but carry the original code: `B002` should print the first verifier code too. Split `B003` by limit (B010-B019). |
| `W` | Wire transport | W001 | W001-W099 read, W100-W199 write | Split `reject()` by reason so that bad tokens, unknown features and trailing data are distinguishable. |
| `CLI` | Command line | CLI001-CLI003 | CLI001-CLI099 usage/input (exit 2), CLI100-CLI199 output/IO (exit 1) | The usage line gets `CLI004`. |
| `C` | C frontend | C001 (script only) | C001-C099 | Emit from a single place once the C frontend owns the check; until then the launcher keeps it, documented as launcher-owned. |
| `D` | Shell launcher and worker | none | D001-D099 | Give the uncoded shell messages stable codes and keep their exit codes (2 for usage, 1 for artifact export). |
| `X` | Experimental | none | X001-X099 | Not part of the stable contract. |
| `R` | Requirement IDs | (internal notes) | retire the `SUBLANG-R` form | Rename requirement IDs to `REQ-R01` etc. so diagnostic searches are clean. |

Also proposed: a single `docs/diagnostic-codes.tsv`-style table in source (one row per code: family, number, dimension, phase, exit, message template), checked by a test that fails when an emitter uses an unlisted code or a listed code has no emitter.

## Verification note

- Emitter and assertion lines were extracted from the frozen snapshot and each TSV row was checked against its source line by script (189 rows, all verified).
- Live repository state was compared with the snapshot with `diff -r` at the end of the run (about 01:00 CEST). `src/` and `scripts/` were identical, and all 189 TSV rows matched the live source.
- No commands that change the repository were run (no edits, commits, stashes or checkouts). Docker was not used.

## Codes added after the first catalog

Scope: the families below were added after the catalog above was made. Each was found by grepping `src/` and `scripts/`, and each emitting line was read. Line numbers refer to the current working tree, not the snapshot. The messages were read from source and were not executed. `docs/diagnostic-codes.tsv` was not extended, so these codes are not in its 189 rows.

Message formats:

- Low verifier (`SUBLANG-L001` to `L005`): `SUBLANG-L00n: function <f> block <b> op <i>: <message>`. The table lists `<message>`. Reporting stops after 16 findings (`SublangLowVerifier.ems:35`).
- Other rows: the message is the text after the code, as shown in the table.

| Code | Meaning | Emitted by (file:line) | Exact message text |
| --- | --- | --- | --- |
| `SUBLANG-L001` | Low IR structure: missing entry block, value defined or used wrongly, missing or misplaced terminator, `stack.alloc` outside the entry block, unknown opcode, branch to a missing block | `src/sublang/low/SublangLowVerifier.ems:40, 96, 97, 104, 109, 110, 224, 464, 468` | `function has no entry block`<br>`defines unknown value <v>`<br>`value <v> is defined twice`<br>`block does not end in a terminator`<br>`terminator before the end of the block`<br>`stack.alloc outside the entry block`<br>`uses undefined value <v>`<br>`unknown opcode <code>`<br>`branch to a missing block` |
| `SUBLANG-L002` | Low IR typing: result, operand or predicate type; operand count; unknown or unsized type; constant range; pointer and field access; conversions; branch argument types | `src/sublang/low/SublangLowVerifier.ems:41, 272, 287, 291, 295, 313, 325, 334, 335, 339, 344, 349, 354, 359, 367, 372, 374, 375, 376, 377, 380, 383, 447, 454, 459, 470, 473` | `unknown return type <t>`<br>`result type <t> differs from <t>`<br>`<op> expects <n> operands`<br>`<op> must produce <t>`<br>`unknown or unsized type <t>`<br>`const.i1 must be 0 or 1`<br>`<op> operand <p> must be <t>`<br>`cmp has unsupported operand type <t>`<br>`cmp operands must be <t>`<br>`cmp predicate <p> does not apply to <t>`<br>`<op> needs a pointer operand`<br>`store value must be <t>`<br>`field.addr names no field of <t>`<br>`<op> index must be i64`<br>`agg.extract does not match its aggregate`<br>`agg.insert does not match its aggregate`<br>`str.len needs a str`<br>`str.ptr needs a str`<br>`sitofp converts an i64`<br>`fptosi converts an f64`<br>`trunc narrows i64 to i8 or i32`<br>`zext widens i8 or i32 to i64`<br>`throw needs an i64 exception code`<br>`ret value must be <t>`<br>`cond_br needs an i1 condition and two targets`<br>`branch passes <n> values to block <b> with <m> parameters`<br>`branch argument <p> must be <t>` |
| `SUBLANG-L003` | Low IR dominance and reachability | `src/sublang/low/SublangLowVerifier.ems:141, 230, 233, 236` | `block is unreachable`<br>`invoke result <v> is only defined on the normal edge`<br>`value <v> is not dominated by its definition`<br>`value <v> is used before its definition` |
| `SUBLANG-L004` | Low IR calls and runtime symbols against the provider | `src/sublang/low/SublangLowVerifier.ems:388, 392, 397, 400, 403` | `runtime symbol <s> is not part of the provider`<br>`call names no function`<br>`call passes <n> arguments, expected <m>`<br>`argument <p> must be <t>`<br>`call result must be <t>` |
| `SUBLANG-L005` | Low IR `invoke` and `eh.catch` shape | `src/sublang/low/SublangLowVerifier.ems:282, 410, 414, 418` | `eh.catch must be the first operation of an unwind block`<br>`invoke needs distinct normal and unwind blocks`<br>`invoke successors take no block parameters`<br>`the unwind block of invoke must start with eh.catch` |
| `SUBLANG-L010` | Lowering target not supported | `src/sublang/lowering/SublangLowering.ems:39` | `target <name> is not supported` (full text, no function prefix) |
| `SUBLANG-L011` | Memory plan made for another snapshot or revision | `src/sublang/lowering/SublangLowering.ems:40` | `the memory plan was made for another snapshot or revision` |
| `SUBLANG-L012` | External function has no Low body | `src/sublang/lowering/SublangLowering.ems:58` | `external function <f> has no Low body` |
| `SUBLANG-L013` | Lowering problem, prefixed to each problem the lowering context recorded | `src/sublang/lowering/SublangLowering.ems:82` (prefix); the problems are recorded at `SublangLowering.ems:148`, `src/sublang/lowering/SublangLowerContext.ems:77` (via `unsupported`, line 51), `src/sublang/lowering/SublangLowerMemory.ems:193` | `opcode <code> is not lowered`<br>`unbound High value <v> in <f>`<br>`class.downcast in <f> has no dispatch group to name the tag field` |
| `SUBLANG-L014` | Module was not lowered to Low IR (CLI; exit 1) | `src/sublang/cli/SublangCommand.ems:86` | `the module was not lowered to Low IR` |
| `SUBLANG-K001` | Linker: the two modules cannot be merged; the linker prints each error and produces no module | `src/sublang/snapshot/SublangModuleLinker.ems:69` (prefix); messages at `:123, 175, 211, 255, 328, 329, 332, 370, 388` | `type <t> depends on a type that cannot be mapped`<br>`type <t> is declared with incompatible structure in the two modules`<br>`field <f> of <t> differs between the modules`<br>`failure action <f> is defined differently in the two modules`<br>`unresolved import <f>`<br>`import <f> is ambiguous: the provider defines it <n> times`<br>`import <f> has a signature that differs from the provider's definition`<br>`class <t> is registered with different tags in the two modules`<br>`both modules define an entry function` |
| `SUBLANG-K002` | Linked module fails verification (CLI) | `src/sublang/cli/SublangCommand.ems:109` | `linked module does not verify: <code> <message>` (first verifier diagnostic of the linked module) |
| `SUBLANG-P010` | Pass input is not a frozen snapshot | `src/sublang/pass/SublangPassManager.ems:70` | `pass input must be a frozen snapshot` |
| `SUBLANG-P011` | Pass input snapshot is superseded | `src/sublang/pass/SublangPassManager.ems:71` | `input snapshot <id> is superseded; fork it or use the head revision` |
| `SUBLANG-P012` | Pass input does not verify | `src/sublang/pass/SublangPassManager.ems:73` | `pass input does not verify` |
| `SUBLANG-P013` | Unknown pass name | `src/sublang/pass/SublangPassManager.ems:80` | `unknown pass <name>` |
| `SUBLANG-P014` | Pass produced an invalid snapshot | `src/sublang/pass/SublangPassManager.ems:104` | `<pass> produced an invalid snapshot: <code> <message>` (code and message of the first diagnostic of the new snapshot) |
| `SUBLANG-P015` | Snapshot lineage rejected the new revision | `src/sublang/pass/SublangPassManager.ems:107` | `snapshot lineage rejected the new revision` |
| `SUBLANG-P017` | Target/provider/ABI or external body has no supported lifetime proof | `src/sublang/pass/SublangPassContext.ems` | Rejected inside P012/P014; no unchecked pass is committed |
| `SUBLANG-P018` | Pass descriptor does not accept the current IR stage | `src/sublang/pass/SublangPassManager.ems` | `pass does not accept this IR stage` |
| `SUBLANG-E008` | Declared effect or `noescape` or `borrow_read` claim contradicted by the derived body effects | `src/sublang/effects/SublangEffectChecks.ems:39, 68, 71` (returned by `contradictions`, consumed at `src/sublang/pass/SublangPassManager.ems:58`) | `function <f> declares <area>=<value> but its body derives <derived>`<br>`parameter <p> of <f> is declared noescape but its body lets it escape`<br>`borrow_read parameter <p> of <f> is written by its body` |
| `SUBLANG-E009` | Effect analysis budget exhausted; the function is widened to unknown. A note, not a diagnostic | `src/sublang/effects/SublangEffectAnalysis.ems:72` (`result.note`) | `effect analysis budget exhausted for function <f>; widened to unknown` |
| `SUBLANG-X001` | Exception terminator contract (`invoke`, `throw`, `resume`); dimension "structure" | `src/sublang/checks/operation/SublangExceptionChecks.ems:16` (reported; messages built in lines 19-53) | `<op> defines no value; invoke results live on the normal edge`<br>`invoke uses an unknown function`<br>`invoke of an external function needs a provider contract`<br>`invoke of <f> passes the wrong number of arguments`<br>`argument <i> of invoke of <f> has the wrong type or passing mode`<br>`invoke results are limited to scalar or Void returns`<br>`invoke needs a normal and an unwind target and no extra arguments`<br>`invoke target block is not defined`<br>`the normal target of invoke must take the call result as its only parameter`<br>`the normal target parameter must have the callee return type`<br>`the unwind target of invoke must take one Int exception code`<br>`invoke normal and unwind targets must differ`<br>`<op> has no successor blocks`<br>`<op> requires one Int exception code` |
| `SUBLANG-O001` | Class hierarchy: base is not a class, class is its own ancestor, class does not begin with its base's fields; dimension "structure" | `src/sublang/checks/SublangDispatchChecks.ems:37, 44, 53` | `class <t> extends a type that is not a class`<br>`class <t> is its own ancestor`<br>`class <t> must begin with the fields of <base>` |
| `SUBLANG-O002` | Dispatch registration and group roots, tag fields and implementations; dimension "structure" | `src/sublang/checks/SublangDispatchChecks.ems:74, 78, 80, 114, 118, 172` | `dispatch registration <i> names a type that is not a class`<br>`class registered twice`<br>`two classes of one hierarchy share a tag`<br>`dispatch group <g> needs a hierarchy root class`<br>`dispatch group <g> needs an Int tag field of its root class`<br>`dispatch group <g> has no implementation for class <t>` |
| `SUBLANG-O003` | Dispatch group prototype and entries; dimension "structure" | `src/sublang/checks/SublangDispatchChecks.ems:121, 134, 137, 142` | `dispatch group <g> has no prototype function`<br>`dispatch group <g> lists an unknown function`<br>`implementation <f> does not match the signature of group <g>`<br>`dispatch group <g> lists a tag twice` |
| `SUBLANG-O004` | `class.upcast`, `class.downcast` and `call.virtual` contracts; dimension "structure" | `src/sublang/checks/operation/SublangObjectChecks.ems:16` (reported; messages built in lines 27-80) | `class.upcast needs one reference operand and a result`<br>`class.upcast converts class references`<br>`class.upcast works on class references`<br>`class.upcast target is not an ancestor of the source class`<br>`a borrowed upcast is a read-only view`<br>`an owned upcast moves ownership into a destination scope`<br>`class.upcast accepts borrow_read or owned operands`<br>`call.virtual names no dispatch group`<br>`dispatch group <g> has no implementation`<br>`call.virtual passes the wrong number of arguments`<br>`argument <i> of call.virtual does not match the group prototype`<br>`call.virtual of a Void group must not produce a value`<br>`call.virtual must produce the group return type`<br>`a reference result of call.virtual needs owned ownership and a scope`<br>`class.downcast takes one reference borrowed for reading`<br>`class.downcast converts class references`<br>`class.downcast target is not a proper descendant of the source class`<br>`class.downcast target class has no registered tag`<br>`a downcast is a read-only view` |
| `SUBLANG-B009` | Extension operations (`ext.bytes.v1`, `ext.numeric.v1`, `ext.eh.v1`) reached the compile path without Low IR | `src/sublang/backend/SublangCompiler.ems:56` | `extension operations are only emitted from Low IR; <route>`, where `<route>` names the lowering status and its first problem |
| `SUBLANG-PGO001` | Profile does not match this program or toolchain (worker; exit 3) | `scripts/sublang-build-worker.sh:68` | `profile does not match this program or toolchain: <field>`, where `<field>` is `ir-sha256`, `clang`, `target` or `llvm-opt` |
| `SUBLANG-PGO002` | `--pgo=use` without the profile files (launcher; exit 2) | `scripts/sublang-build.sh:41` | `--pgo=use needs --profile=DIR containing program.profdata and program.profmeta` |

Notes on the rows above:

- Assertions: the only assertions of these codes in `src/` or `scripts/` are `L001` to `L004` (`src/sublang/harness/pass/SublangLowChecks.ems:67, 71, 82, 98, 129`) and `E008` (`src/sublang/harness/pass/SublangPassChecks.ems:94`). All other rows are emitters only.
- Dimension: `SublangVocabulary.dimensionOf` (`SublangVocabulary.ems:218-222`) maps the `X` and `O` prefixes to "structure", and everything else to "semantics". `L`, `K`, `P` and `PGO` are not classified.
- The `X` family was listed as "Experimental, not part of the stable contract" in the proposed range table above. It is now used by the exception checks, so that row is out of date.
- `B009` tests `usesBytes`, `usesNumeric` and `usesExceptions` only (`SublangCompiler.ems:55`). An `ext.oo.v1` module that is not lowered does not get `B009`. UNVERIFIED: how that module is then emitted; this was not traced.
- `PGO001` is printed only by the worker script. `sublang-build.sh` does not print it.
- UNVERIFIED: the exit status of `sublang link` on `K001` and `K002` was not traced.

## Text IR codes

`sublang text-build` reports these (see `docs/Sublang_Text_IR.md` for the format):

| Code | Meaning | Emitted by |
| --- | --- | --- |
| `SUBLANG-TX001` | syntax error: string, escape, integer, token or record order, with line and column | `src/sublang/text/` |
| `SUBLANG-TX002` | unknown record keyword, attribute or feature name | `src/sublang/text/` |
| `SUBLANG-TX003` | duplicate or non-dense table id, duplicate operation id | `src/sublang/text/` |
| `SUBLANG-TX004` | input, line count or line length limit exceeded | `src/sublang/text/` |
| `SUBLANG-TX005` | record inconsistent with the module (version, schema, stage, revision, entry, convention) | `src/sublang/text/` |
| `SUBLANG-TX006` | the parsed module failed verification; carries the verifier's own code | `src/sublang/text/` |
