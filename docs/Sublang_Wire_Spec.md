# Sublang Wire v2 record-level specification

Status: experimental development transport (Wire transport 2, reader also accepts
transport 1). Not a permanent public ABI. This document describes what the Emerald
codec in `src/sublang/wire/` reads and writes, so that a writer or reader can be
implemented in another language without reading that source.

Sources checked: `src/sublang/wire/` (SublangWire, SublangWireStream,
SublangWireTables, SublangWireEffects, SublangWireBody, SublangWireSelection,
SublangWireResult), `src/sublang/vocabulary/SublangVocabulary.ems`,
`src/sublang/ir/` (table ID assignment), `src/sublang/checks/` (accepted tags),
`src/sublang/cli/SublangCommand.ems`, and `examples/wire/*.sublang-wire`.

Verification policy: every record layout and limit below is copied from the codec
source. The 11 example files under `examples/wire/` were decoded with an independent
Python mirror of the reader (not the Emerald binary); all 11 parse exactly to EOF.
Anything not confirmed by that evidence or by direct source reading is marked
`UNVERIFIED:`.

## 0. Key facts that differ from a naive reading

- Transport v2 has no numeric enum encoding. Every kind, opcode, passing mode,
  ownership, failure action, effect area and similar tag is written as a netstring
  text token holding the name (for example `10:i64-signed`). `SublangVocabulary`
  defines these as string constants, not ordinals. A writer must emit the names.
- The only transport diagnostic code is `SUBLANG-W001`, always followed by a byte
  offset and a reason text. The CLI adds `SUBLANG-CLI001..003` (section 9).
- Transport validation checks framing, counts, versions, feature names and
  integer syntax. It does not check opcode names, operand/mode parity, id ranges
  or ownership. Those belong to the verifier and native gate (section 7).
- A reader rejects trailing bytes. Input is at most 16 MiB (16,777,216 bytes).

## 1. Framing: netstring grammar

Every scalar is one netstring token:

```text
token  = length ":" payload ","
length = 1*5DIGIT          ; ASCII 0-9, at most 5 digits, leading zeros allowed
payload = <length bytes>   ; raw bytes, no escaping, no terminator inside
```

Rules, all from `SublangWireStream.readToken` / `payload`:

- `length` counts bytes of the payload, not characters. Verified: in
  `static-string.sublang-wire` token 167 is `5:` followed by the bytes
  `C3 A4 22 5C 0A` (`ä`, quote, backslash, newline), i.e. 5 UTF-8 bytes.
- `length` must be at most 65536 (64 KiB per token). A zero-length token `0:,` is
  valid and is the empty string.
- A payload with no digits (`:` alone) is invalid.
- Payload must end with `,` at offset `start + length`. Length must be strictly less
  than the bytes remaining after `:`, so the comma always exists.
- No whitespace, newlines or separators are allowed between tokens. Files written
  by Emerald have no trailing newline; the byte total equals the last `,`.
- The file is text bytes with no BOM. Non-ASCII bytes are legal only inside payloads.

Scalar interpretation (applied to a token's payload bytes):

| Kind | Payload rule | Notes |
| --- | --- | --- |
| text | any bytes, valid as read | Names/messages keep UTF-8, quotes and newlines as raw bytes. |
| Int | optional `-`, then one or more ASCII digits | `+5` invalid, `-` alone and empty invalid. Leading zeros accepted. Signed Int64 range. `-9223372036854775808` accepted; `9223372036854775808` rejected. Writer emits decimal of the value. |
| flag (Bool) | exactly `0` or `1` | Any other payload is `invalid boolean`. |

## 2. Limits (codec-enforced, reader and writer)

| Scope | Limit |
| --- | --- |
| input file | 16,777,216 bytes (reader rejects at byte 0) |
| one token payload | 65,536 bytes |
| writer output | 16,777,216 bytes |
| total counted entries | 262,144 (sum of every counted section and every id list) |
| required features (count) | 1 to 32 entries counted; a count of 0 passes counting and then fails with `missing core.native64 feature` |
| sources | 4,096 |
| spans | 32,768 |
| types (non-primitive) | 508 |
| fields | 512 |
| profiles | 512 |
| failure actions | 512 |
| locations | 4,096 |
| alias facts | 4,096 |
| effect summaries | 4,096 |
| effect facts per summary | 512 |
| proof dependency ids (per proof) | 4,096 |
| effect location ids (per fact) | 4,096 |
| functions | 32 |
| values per function | 4,096 |
| params per function | 4,096 |
| blocks per function | 64 |
| block parameter ids per block | 4,096 |
| operations per block | 4,096 |
| operands per operation | 4,096 |
| passing modes per operation | 4,096 |
| targets per operation | 2 |

Count rule: a count token is an Int. It must be `0..limit`. Each accepted count is
added to the running total. Id lists (operands, targets, proof dependencies, effect
locations, block parameters) are counted sections too: a count token followed by
that many Int tokens.

Writer-only rejections: `token exceeds 64 KiB`, `output exceeds 16 MiB`.

Native gate limits (function, type, field, block, value and operation budgets
beyond the transport numbers) are separate and not specified here.
UNVERIFIED: the exact native limit values.

## 3. Header

Tokens in this exact order, none optional:

| # | Token | Type | Constraint |
| --- | --- | --- | --- |
| 0 | `SUBLANG-WIRE` | text | must match exactly |
| 1 | transport version | Int | 1 or 2. Writers emit 2 |
| 2 | IR schema | Int | must be 1 |
| 3 | stage | text | must be `High` |
| 4 | revision | Int | must be 1 |
| 5 | required-feature count | Int | 0..32 counted; must produce at least one feature |
| 6..5+n | required features | text | see below |
| 6+n | module name | text | any |
| 7+n | entry FunctionId | Int | not range-checked by transport |

Feature rule: every feature must equal `core.native64.v1` (transport 1) or
`core.native64.v2` (transport 2). A duplicate, an unknown name, or a feature of the
other version is rejected. If no core feature appears, the reader rejects with
`missing core.native64 feature`. Writers emit one feature, `core.native64.v2`.

Example header (`arithmetic.sublang-wire`, transport 1):
`12:SUBLANG-WIRE,1:1,1:1,4:High,1:1,1:1,16:core.native64.v1,10:arithmetic,1:1,`

## 4. Sections, in order

Each section starts with an expect token (its name), then a count (except `end`).
Dense IDs are assigned by the reader in insertion order, so ID = position in the
section (1-based unless noted).

| Order | Section tag | Count limit | Records |
| --- | --- | --- | --- |
| 1 | `sources` | 4096 | source names |
| 1 | `spans` | 32768 | spans |
| 2 | `types` | 508 | type descriptors |
| 2 | `fields` | 512 | field descriptors |
| 3 | `profiles` | 512 | semantic profiles |
| 3 | `failures` | 512 | failure actions |
| 4 | `locations` | 4096 | alias locations |
| 4 | `aliases` | 4096 | alias facts |
| 4 | `effects` | 4096 | effect summaries (each with a fact count) |
| 5 | `functions` | 32 | functions with bodies |
| 6 | `end` | - | then end of file |

The section tags are text tokens and are checked with `expect`. The order is fixed.

### 4.1 Sources and spans

`sources` count, then per source: `name` (text). Source ID = 1-based position.

`spans` count, then per span, in this order:

| Field | Type |
| --- | --- |
| source | Int (0 is the synthetic source in examples) |
| line | Int (0 for synthetic) |
| column | Int (0 for synthetic) |
| origin | text (empty for real source positions) |

Span ID = 1-based position. Example: `1:0,1:0,1:0,18:backend:arithmetic,` is a synthetic span.

### 4.2 Types and fields

Primitive types 1..4 are implicit and never serialized:

| ID | Kind | Name | Width | Signed |
| --- | --- | --- | --- | --- |
| 1 | Void | Void | 0 | no |
| 2 | Bool | Bool | 1 | no |
| 3 | Int | Int | 64 | yes |
| 4 | Float | Float | 64 | no |

`types` count (`types` section, limit 508), then per non-primitive type, starting at
ID 5:

| Field | Type |
| --- | --- |
| kind | text (section 6.1) |
| name | text |
| width | Int |
| signed | flag |
| target | Int (target type ID, e.g. for Ref) |
| span | Int |
| nullable | flag |

`fields` count (limit 512), then per field, ID = 1-based position:

| Field | Type |
| --- | --- |
| owner | Int (type ID) |
| name | text |
| type | Int (type ID) |
| mutable | flag |
| span | Int |

Writers must not emit the primitive descriptors. Writers must emit fields in the
nominal order the owning type lists. The writer checks this (section 8).

### 4.3 Profiles and failure actions

`profiles` count, then per profile, ID = 1-based position:

| Field | Type |
| --- | --- |
| name | text |
| version | Int |
| integer rules | text |
| float rules | text |
| failure model | text |
| unwinding model | text |

`failures` count, then per failure action, ID = 1-based position:

| Field | Type |
| --- | --- |
| name | text |
| behavior | text |
| binding | text |
| signature | text |
| continues | flag |
| unwinding | text |
| span | Int |

### 4.4 Locations, alias facts and effect summaries

`locations` count, then per location, ID = 1-based position:

| Field | Type |
| --- | --- |
| kind | text (section 6.5) |
| name | text |
| span | Int |

`aliases` count, then per alias fact (the fact has no ID; it refers to locations by
Int):

| Field | Type | Notes |
| --- | --- | --- |
| left | Int | location ID |
| right | Int | location ID |
| answer | text | section 6.6 |
| origin | text | |
| label | text (proof label) | |
| revision | Int | must equal module revision 1, else `alias revision mismatch` |
| span | Int | |
| proof analysis | text | proof reference (below) |
| proof revision | Int | |
| proof dependency count + ids | count + Int list | limit 4096 |

`effects` count, then per summary, ID = 1-based position:

| Field | Type |
| --- | --- |
| name | text |
| span | Int |
| fact count | Int (limit 512) |
| facts | per fact below, in order |

Per effect fact (0-based order within its summary):

| Field | Type | Notes |
| --- | --- | --- |
| area | text | section 6.7 |
| value | text | section 6.7 |
| provenance | text | section 6.7 |
| detail | text | free text |
| label | text | proof label |
| proof analysis | text | |
| proof revision | Int | |
| proof dependency count + ids | count + Int list | |
| location count + ids | count + Int list | location IDs |

### 4.5 Functions

`functions` count (limit 32). Per function, ID = 1-based position:

| Field | Type |
| --- | --- |
| name | text |
| return type | Int (type ID) |
| methodOf | Int (0 in examples) |
| span | Int |
| profile | Int (profile ID) |
| effect summary | Int (summary ID) |
| linkage | text (section 6.8) |
| convention | text, must be `sublang` |
| definition | text (section 6.8) |
| value count + value types | count (limit 4096) + one Int type ID per value |
| param count + params | count (limit 4096) + per param below |
| block count + blocks | count (limit 64) + per block below |

Value IDs are dense 1..N in list order (reader calls `newValue` in order), so the
value list is the SSA value table.

Per param (0-based order): value ID (Int), name (text), type ID (Int), passing mode
(text, section 6.2), noEscape (flag). Params are not range-checked for a value
match.

Per block (1-based position): block-parameter value-ID count + Int list (limit 4096),
then operation count (limit 4096) + operations.

Per operation (0-based order within the block):

| Field | Type | Notes |
| --- | --- | --- |
| id | Int | explicit operation id, preserved |
| opcode | text (section 6.3) | |
| span | Int | |
| result value | Int | 0 when no result (examples) |
| result type | Int | type ID |
| result ownership | text | section 6.4; empty when none |
| ref | Int | meaning depends on opcode (section 6.9) |
| scope | Int | |
| overflow | text | section 6.10; empty when not applicable |
| predicate | text | section 6.11; empty when not applicable |
| fp mode | text | `rne` or empty (section 6.12) |
| effect summary | Int | 0 in examples |
| const int | Int | |
| const bool | flag | |
| const float bits | Int | raw IEEE-754 f64 bits, signed Int64 |
| const text | text | **v2 only**, see section 5 |
| operand count + operand IDs | count (limit 4096) + Int list | |
| mode count + passing modes | count (limit 4096) + text list | section 6.2 |
| target count + target IDs | count (limit 2) + Int list | |
| true args | Int | |

Serialization preserves IDs and does not remap CFG references. Operand and mode
counts are independent: the codec does not check that they match.

## 5. v1 versus v2 differences

| Aspect | Transport 1 | Transport 2 |
| --- | --- | --- |
| Accepted by reader | yes (`core.native64.v1`) | yes (`core.native64.v2`) |
| Emitted by Emerald writer | never | always |
| Type kinds `String`, `List`, `Bond` | rejected: `type requires transport v2` | allowed |
| Opcode `const.string` | rejected: `const.string requires transport v2` | allowed |
| Per-operation `const text` token | absent | present, immediately after const float bits |

The v2 const text token is the only operation-record difference. Verified: in
`static-string.sublang-wire`, operation 1 of `const.string` has const float bits
`1:0` at token 166, const text `5:ä"\`+LF at token 167, then operand count `1:0`.
The v1 files in the example set (`arithmetic`, `borrowed-graph`, `pool-graph`)
decode without a const text token.

## 6. Tag vocabularies

No numeric code is written for any tag. The tables give the textual tags.
"Codec" means the tag is checked by the wire layer. "Verifier" means it is checked
by the semantic layer (`SublangVocabulary`, `checks/`), not by the transport.

### 6.1 Type kinds (codec: any text; verifier: list below)

`Void`, `Bool`, `Int`, `Float`, `Record`, `Class`, `Ref`, `String`, `List`, `Bond`.
The codec rejects `String`, `List` and `Bond` only in transport 1.

### 6.2 Passing modes (for params and operations)

`value`, `owned`, `borrow_read`, `borrow_write`, `init`.
Verifier: `SublangVocabulary.isKnownPassing`.

### 6.3 Opcodes (verifier: `isKnownOpcode`)

`const.bool`, `const.int`, `const.float`, `const.string`, `compare`, `record.make`,
`record.get`, `record.with`, `class.new`, `field.init`, `field.clear`, `field.has`,
`field.take`, `field.read`, `field.write`, `field.borrow`, `call.direct`,
`scope.begin`, `scope.end`, `int.add`, `int.sub`, `int.mul`, `int.div`, `int.rem`,
`int.neg`, `float.add`, `float.sub`, `float.mul`, `float.div`, `return`, `branch`,
`cond_branch`, `fail`, `bond.own`, `bond.new`, `bond.retain`, `bond.borrow`,
`bond.get`, `bond.link`, `bond.clear`, `bond.write`, `list.new`, `list.push`,
`list.length`, `list.get`, `list.borrow`, `list.clear`, `string.length`,
`string.byte`, `string.equal`.

Notes from `SublangVocabulary`: `const.string`, `string.*`, `list.*` and `bond.*`
require transport 2 (codec checks `const.string` only). `call.direct` does not
produce a value by itself.

### 6.4 Result ownership (observed and checked, full set UNVERIFIED)

Observed in examples and checks: empty text (no ownership), `owned`, `borrow_read`,
and Bond result ownership uses a mode text. UNVERIFIED: the complete accepted set
for result ownership beyond these values.

### 6.5 Location kinds (verifier: `isLocationKind`)

`global`, `allocation`, `field-path`, `container`, `argument-region`, `runtime`,
`unknown`.

### 6.6 Alias answers (verifier: `isAliasAnswer`)

`NoAlias`, `MayAlias`, `MustAlias`.

### 6.7 Effect areas, values and provenance

Areas (verifier: `effectAreas`), in this order in the startup summary:
`allocation`, `escape`, `failure`, `exceptions`, `memory-read`, `memory-write`,
`synchronization`, `observable`, `control`.

Values: `none`, `may`, `unknown` for every area except `control`, which accepts
`returns`, `may-diverge`, `unknown`.

Provenance (verifier: `isEffectProvenance`): `declared`, `assumed-conservative`,
`proven`.

### 6.8 Linkage and definition (verifier)

Linkage: `internal`, `external`. Definition: `body`, `contract`.
Calling convention: codec requires exactly `sublang`.

### 6.9 Ref field meaning (verifier: `refMeaning`)

Per opcode: `field` (field.*, record.get/with, bond.get/link/clear/write, bond.own,
field.borrow), `type` (record.make, class.new, bond.new, list.new), `function`
(call.direct), `scope` (scope.begin/end), `failure` (fail and int arithmetic
opcodes), `none` otherwise. The example `int.add` has ref `1`, which is failure
action 1 (`test.abort`).

### 6.10 Overflow modes (verifier: `allowsOverflow`)

`trap`, `wrap` for int arithmetic; `int.rem` also allows `zero`. Empty text when
not applicable.

### 6.11 Predicates (verifier)

Integer compare: `eq`, `ne`, `lt`, `le`, `gt`, `ge`.
Float compare: `oeq`, `one`, `olt`, `ole`, `ogt`, `oge`, `ueq`, `une`, `ult`,
`ule`, `ugt`, `uge`, `ord`, `uno`.

### 6.12 Float rounding mode

Only `rne` is accepted (checks `SUBLANG-A003` for other modes). Empty for
non-float operations.

### 6.13 Failure actions (verifier: `checkFailureAction`)

| Field | Accepted now |
| --- | --- |
| behavior | `abort` only (`SUBLANG-U004` otherwise) |
| continues | `0` only (`SUBLANG-F003` otherwise) |
| unwinding | `none` only (`SUBLANG-U005` otherwise) |
| signature | `noreturn void()` (`SUBLANG-F002` otherwise) |
| binding | `unbound` or `libc.abort` (backend gate) |

Startup profile (`SublangVocabulary`): name `sublang.startup`, version `1`, integer
rules `i64-signed`, float rules `f64-ieee-rne`, failure model `abort`, unwinding
model `none`, float rounding `rne`.

## 7. What the transport does not check

- Opcode names, operand/mode parity, operand and value ID ranges, CFG references
  and ownership. Verifier and native gate check these.
- Entry FunctionId range.
- Effect facts for completeness. Imported `proven` labels grant no NoAlias and no
  call elimination (`Sublang_Wire.md`).
- Id-valued Int fields are not range-checked against tables.

## 8. Writer-only checks

The writer runs the same count and limit logic and additionally:

- Requires a frozen module: `writer requires a frozen snapshot` (reported at byte 0).
- Rejects tokens above 64 KiB and output above 16 MiB.
- Rejects non-canonical primitive descriptors: `modified implicit primitive
  descriptor`.
- Rejects nominal field order mismatches: `incomplete nominal field order`,
  `noncanonical nominal field order`, `inconsistent nominal field table`.

The writer always emits transport `2` and feature `core.native64.v2`.

## 9. Diagnostics

All transport failures use the form:

```text
SUBLANG-W001 at byte N: reason
```

`N` is the byte offset at the moment of the first rejection. The reader keeps only
the first failure. The offset is the reader cursor at the moment of rejection: the cursor advances past
each character it reads, so it points just after the failing character (for a
bad length byte) or after the colon (for a payload error).

Reason strings from the codec:

| Reason | Trigger |
| --- | --- |
| `input exceeds 16 MiB` | input larger than 16,777,216 bytes (offset 0) |
| `expected <tag>` | section or header tag mismatch |
| `invalid token length` | non-digit or more than 5 digits before `:` |
| `truncated length` | input ends before `:` |
| `invalid or truncated payload` | empty length, length above 65536, or fewer bytes left than length plus comma |
| `missing token delimiter` | byte after payload is not `,` |
| `empty integer` | Int with no digits |
| `invalid or overflowing integer` | non-digit, or outside Int64 |
| `invalid boolean` | flag payload not `0` or `1` |
| `count budget exceeded` | count below 0 or above its limit |
| `total table budget exceeded` | running total above 262,144 |
| `unsupported transport version` | transport not 1 or 2 |
| `unsupported IR schema, stage or revision` | schema not 1, stage not `High`, revision not 1 |
| `unknown or duplicate required feature` | feature not the version's core name, or repeated |
| `missing core.native64 feature` | no feature accepted |
| `type requires transport v2` | transport 1 with String/List/Bond kind |
| `const.string requires transport v2` | transport 1 with `const.string` |
| `alias revision mismatch` | alias revision not 1 |
| `unsupported calling convention` | convention not `sublang` |
| `trailing data` | bytes remain after `end` |

CLI (`sublang emit-llvm`): prints the W001 text and exits 1 for a decode failure.
`SUBLANG-CLI001` (invalid Optimind mode, exit 2), `SUBLANG-CLI002` (input not a regular
file or larger than 16 MiB, exit 2) and `SUBLANG-CLI003` (cannot write output, exit 1)
are printed by `SublangCommand.ems`.

## 10. Conformance examples

### 10.1 Positive: `examples/wire/arithmetic.sublang-wire` (1,494 bytes, transport 1)

Program: `main() -> Int`: `2000000000 + 2000000000` with `trap` overflow, returned.
Token offsets are byte offsets of the length digits. Token index is the sequence
position. Decoded with the Python mirror; the trace is exact.

| Tok | Offset | Raw token | Meaning |
| --- | --- | --- | --- |
| 0 | 0 | `12:SUBLANG-WIRE,` | magic |
| 1 | 16 | `1:1,` | transport 1 |
| 2 | 20 | `1:1,` | schema 1 |
| 3 | 24 | `4:High,` | stage |
| 4 | 31 | `1:1,` | revision 1 |
| 5 | 35 | `1:1,` | feature count 1 |
| 6 | 39 | `16:core.native64.v1,` | feature (v1) |
| 7 | 59 | `10:arithmetic,` | module name |
| 8 | 73 | `1:1,` | entry FunctionId 1 |
| 9 | 77 | `7:sources,` | section tag |
| 10 | 87 | `1:0,` | 0 sources |
| 11 | 91 | `5:spans,` | section tag |
| 12 | 99 | `1:1,` | 1 span |
| 13 | 103 | `1:0,` | span source 0 |
| 14 | 107 | `1:0,` | line 0 |
| 15 | 111 | `1:0,` | column 0 |
| 16 | 115 | `18:backend:arithmetic,` | span origin |
| 17 | 137 | `5:types,` | section tag |
| 18 | 145 | `1:0,` | 0 non-primitive types |
| 19 | 149 | `6:fields,` | section tag |
| 20 | 158 | `1:0,` | 0 fields |
| 21 | 162 | `8:profiles,` | section tag |
| 22 | 173 | `1:1,` | 1 profile |
| 23 | 177 | `15:sublang.startup,` | profile name |
| 24 | 196 | `1:1,` | profile version 1 |
| 25 | 200 | `10:i64-signed,` | integer rules |
| 26 | 214 | `12:f64-ieee-rne,` | float rules |
| 27 | 230 | `5:abort,` | failure model |
| 28 | 238 | `4:none,` | unwinding model |
| 29 | 245 | `8:failures,` | section tag |
| 30 | 256 | `1:1,` | 1 failure action |
| 31 | 260 | `10:test.abort,` | failure name |
| 32 | 274 | `5:abort,` | behavior |
| 33 | 282 | `7:unbound,` | binding |
| 34 | 292 | `15:noreturn void(),` | signature |
| 35 | 311 | `1:0,` | continues 0 |
| 36 | 315 | `4:none,` | unwinding |
| 37 | 322 | `1:0,` | span 0 |
| 38 | 326 | `9:locations,` | section tag |
| 39 | 338 | `1:0,` | 0 locations |
| 40 | 342 | `7:aliases,` | section tag |
| 41 | 352 | `1:0,` | 0 alias facts |
| 42 | 356 | `7:effects,` | section tag |
| 43 | 366 | `1:1,` | 1 effect summary |
| 44 | 370 | `12:conservative,` | summary name |
| 45 | 386 | `1:0,` | summary span 0 |
| 46 | 390 | `1:9,` | 9 facts |
| 47-55 | 394-461 | 9 tokens | fact `allocation`: `10:allocation,` `7:unknown,` `20:assumed-conservative,` `0:,` (detail) `0:,` (label) `0:,` (analysis) `1:0,` (revision 0) `1:0,` (0 dependencies) `1:0,` (0 locations) |
| 56-127 | 463-1009 | 8 x 9 tokens | the other eight facts in the order `escape`, `failure`, `exceptions`, `memory-read`, `memory-write`, `synchronization`, `observable`, `control`; each is the same 9-token group with the area changed and value `unknown` |
| 128 | 1010 | `9:functions,` | section tag |
| 129 | 1022 | `1:1,` | 1 function |
| 130 | 1026 | `4:main,` | function name |
| 131 | 1033 | `1:3,` | return type 3 (Int) |
| 132 | 1037 | `1:0,` | methodOf 0 |
| 133 | 1041 | `1:1,` | span 1 |
| 134 | 1045 | `1:1,` | profile 1 |
| 135 | 1049 | `1:1,` | effect summary 1 |
| 136 | 1053 | `8:internal,` | linkage |
| 137 | 1064 | `7:sublang,` | convention |
| 138 | 1074 | `4:body,` | definition |
| 139 | 1081 | `1:3,` | 3 values |
| 140-142 | 1085-1096 | `1:3,` x3 | value types for values 1, 2, 3 |
| 143 | 1097 | `1:0,` | 0 params |
| 144 | 1101 | `1:1,` | 1 block |
| 145 | 1105 | `1:0,` | block 1 has 0 block params |
| 146 | 1109 | `1:4,` | 4 operations |
| 147 | 1113 | `1:1,` | op 1 id 1 |
| 148 | 1117 | `9:const.int,` | opcode |
| 149 | 1129 | `1:1,` | span 1 |
| 150 | 1133 | `1:1,` | result value 1 |
| 151 | 1137 | `1:3,` | result type Int |
| 152 | 1141 | `0:,` | ownership none |
| 153 | 1144 | `1:0,` | ref 0 |
| 154 | 1148 | `1:0,` | scope 0 |
| 155 | 1152 | `0:,` | overflow none |
| 156 | 1155 | `0:,` | predicate none |
| 157 | 1158 | `0:,` | fp mode none |
| 158 | 1161 | `1:0,` | effect summary 0 |
| 159 | 1165 | `10:2000000000,` | const int |
| 160 | 1179 | `1:0,` | const bool 0 |
| 161 | 1183 | `1:0,` | const float bits 0 |
| 162 | 1187 | `1:0,` | 0 operands |
| 163 | 1191 | `1:0,` | 0 modes |
| 164 | 1195 | `1:0,` | 0 targets |
| 165 | 1199 | `1:0,` | true args 0 |
| 166 | 1203 | `1:2,` | op 2 id 2 |
| 167-184 | 1207-1292 | | op 2 `const.int` 2000000000, result value 2, same layout as op 1 |
| 185 | 1293 | `1:3,` | op 3 id 3 |
| 186 | 1297 | `7:int.add,` | opcode |
| 187 | 1307 | `1:1,` | span 1 |
| 188 | 1311 | `1:3,` | result value 3 |
| 189 | 1315 | `1:3,` | result type Int |
| 190 | 1319 | `0:,` | ownership none |
| 191 | 1322 | `1:1,` | ref 1 (failure action 1, `test.abort`) |
| 192 | 1326 | `1:0,` | scope 0 |
| 193 | 1330 | `4:trap,` | overflow trap |
| 194-195 | 1337-1342 | `0:,` `0:,` | predicate none, fp mode none |
| 196 | 1343 | `1:0,` | effect summary 0 |
| 197-199 | 1347-1358 | `1:0,` x3 | const int 0, const bool 0, const float bits 0 |
| 200 | 1359 | `1:2,` | 2 operands |
| 201 | 1363 | `1:1,` | operand value 1 |
| 202 | 1367 | `1:2,` | operand value 2 |
| 203 | 1371 | `1:2,` | 2 modes |
| 204-205 | 1375-1390 | `5:value,` x2 | passing modes |
| 206 | 1391 | `1:0,` | 0 targets |
| 207 | 1395 | `1:0,` | true args 0 |
| 208 | 1399 | `1:4,` | op 4 id 4 |
| 209 | 1403 | `6:return,` | opcode |
| 210 | 1412 | `1:1,` | span 1 |
| 211-212 | 1416-1423 | `1:0,` x2 | result value 0, result type 0 |
| 213 | 1424 | `0:,` | ownership none |
| 214-215 | 1427-1434 | `1:0,` x2 | ref 0, scope 0 |
| 216-218 | 1435-1443 | `0:,` x3 | overflow, predicate, fp mode none |
| 219-222 | 1444-1459 | `1:0,` x4 | effect 0, const int 0, const bool 0, const float bits 0 |
| 223 | 1460 | `1:1,` | 1 operand |
| 224 | 1464 | `1:3,` | operand value 3 |
| 225 | 1468 | `1:1,` | 1 mode |
| 226 | 1472 | `5:value,` | mode value |
| 227 | 1480 | `1:0,` | 0 targets |
| 228 | 1484 | `1:0,` | true args 0 |
| 229 | 1488 | `3:end,` | end marker |
| - | 1494 | EOF | no trailing bytes |

Decoded totals (mirror): transport 1, module `arithmetic`, entry 1, 29 counted
entries.

### 10.2 Positive excerpt: `examples/wire/static-string.sublang-wire` (transport 2, const.string)

The const.string operation's attribute tokens, with the v2 const text token:

```text
1:1,   op id 1
12:const.string,
1:1,   span 1
1:1,   result value 1
1:5,   result type 5 (String)
0:,    ownership none
1:0,   ref 0
1:0,   scope 0
0:,    overflow
0:,    predicate
0:,    fp mode
1:0,   effect summary 0
1:0,   const int 0
1:0,   const bool 0
1:0,   const float bits 0
5:<C3 A4 22 5C 0A>,   const text (v2 only): ä, quote, backslash, newline
1:0,   0 operands
1:0,   0 modes
1:0,   0 targets
1:0,   true args 0
```

The byte count 5 confirms UTF-8 byte semantics for the writer.

### 10.3 Negative cases (expected diagnostics)

Each case is a mutation of the arithmetic file. Offsets come from the Python
mirror. Verified on 2026-10-11 against the compiled `sublang` binary (`sublang dump`
inside the sandbox): all seven strings and byte offsets below match exactly.

| Case | Input change | Expected diagnostic |
| --- | --- | --- |
| Truncated (mid-file) | first 100 bytes | `SUBLANG-W001 at byte 100: truncated length` |
| Truncated (end) | last `,` removed | `SUBLANG-W001 at byte 1490: invalid or truncated payload` |
| Wrong version | transport `1:1` -> `1:3` | `SUBLANG-W001 at byte 20: unsupported transport version` |
| Unknown required feature | `core.native64.v1` -> `core.native64.v9` | `SUBLANG-W001 at byte 59: unknown or duplicate required feature` |
| Duplicate required feature | feature count 1 -> 2, feature repeated | `SUBLANG-W001 at byte 79: unknown or duplicate required feature` |
| Trailing data | one extra `x` after `end` | `SUBLANG-W001 at byte 1494: trailing data` |
| v2 feature under transport 1 | static-string with transport 2 -> 1 | `SUBLANG-W001 at byte 59: unknown or duplicate required feature` |

### 10.4 Native backend rules that the transport does not check

Operation ids must be unique across the whole module, not merely per function or
block. The native backend rejects a repeated id with `SUBLANG-B008: duplicate
operation id` and requires every id to be in `1..32768`. A writer should therefore
number operations with one module-wide counter (the Tiny frontend in
`examples/frontend/tiny` does).

## 11. Versioning and compatibility

- Transport 2 is the only writer format. Transport 1 input is read-only compatibility.
- Feature names pin the transport: a reader must reject a feature that does not
  match the transport.
- Header schema, stage and revision are fixed in this version.

## 12. UNVERIFIED list

- Verified: the diagnostic strings and byte offsets of section 10.3 as produced by the
  compiled binary (the Python mirror was also checked against all 11 example files).
- UNVERIFIED: complete set of result-ownership values (section 6.4).
- UNVERIFIED: meaning of the Int `methodOf` field and of effect-summary ID 0 (used as
  "none" in examples).
- UNVERIFIED: native gate budget numbers (function, type, field, block, value and
  operation limits).
- UNVERIFIED: how `SublangTypeTable.addField` handles an owner ID that is not yet a
  type (the code path was not traced).
- UNVERIFIED: whether Emerald `String.length()` is byte-based in every code path. The
  examples show byte counts for the emitted files, but the codec was not executed.
