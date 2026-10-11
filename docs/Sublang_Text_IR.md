# Sublang Text IR (M10)

The text IR is a canonical, deterministic, lossless textual form of a High IR module. It is the
human-readable counterpart of the Wire transport (`docs/Sublang_Wire_Spec.md`). The printer is
`sublang::text::SublangTextPrinter`, the parser is `sublang::text::SublangTextParser`, and the
CLI is `sublang text-dump` and `sublang text-build`. The grammar is also written in the header
comment of `src/sublang/text/SublangTextPrinter.ems`.

## Guarantee

- **Lossless round trip with Wire.** For a transport-2 Wire input, `text-dump`, then `text-build`,
  reproduces the input bytes exactly. Verified for the eight transport-2 examples in `examples/wire/`. Transport-1 inputs (`arithmetic`, `borrowed-graph`, `pool-graph`) come back
  as transport 2 with an identical module: the Wire writer never emits transport 1 (see
  `docs/Sublang_Wire_Spec.md`, section 5), so the bytes differ in the header and in the
  per-operation const-text token, but `text-dump` of the rebuilt Wire is identical to the text of
  the original.
- **Verification always runs.** A module that comes from text is frozen and passed through
  `SublangVerifier` before any Wire is written. A module that does not verify is never returned
  by the parser and never written by `text-build`.
- **Deterministic output.** `text-dump` of the same module always gives the same bytes; the
  output contains no addresses, timestamps or file names.

## Lexical form

- The text is ASCII only. One record per line; the first token of a record is its keyword.
- Spaces and tabs separate tokens. A `#` starts a comment that runs to the end of the line; comment
  bytes must be printable ASCII or tabs. Blank lines are ignored. Indentation is cosmetic.
- Line endings are LF. A CR byte outside a string is an error.
- Token kinds:

| Kind | Form | Notes |
| --- | --- | --- |
| word | letters, digits, `_`, `-`, `.`; starts with a letter or `_` | keywords, attribute keys, `true`, `false`, `High` |
| integer | optional `-`, then decimal digits | signed 64-bit; no range beyond Int64 |
| string | `"..."` | see Escapes |
| list | `[` items separated by `,` `]` | integers or strings, `[]` is empty |
| `=` | | between an attribute key and its value |

- Float constants are stored as their raw IEEE-754 64-bit pattern, printed as a signed decimal
  integer (`bits=`), so `-0.0` and NaN payloads survive.

## Escapes

Inside a string, printable ASCII (0x20 to 0x7E) is written raw, except `\` and `"`. Every other
byte is an escape:

| Escape | Byte |
| --- | --- |
| `\\` | `\` |
| `\"` | `"` |
| `\n` `\r` `\t` | LF, CR, TAB |
| `\xNN` | any byte 0x00 to 0xFF, two hex digits (the printer writes lower case, the parser accepts both cases) |

Any other backslash sequence is `TX001`. Strings may therefore hold arbitrary bytes: NUL is
`\x00`, the UTF-8 encoding of U+00E4 is `\xC3\xA4`. The printer always writes the canonical escape
form, so `\xc3\xa4` and `\n` are what text-dump produces.

## Records

Every record has the form `keyword attr=value ...`. Attributes appear in exactly the order shown;
a missing, misplaced or unknown attribute is an error. Records must appear in the order below.

| Order | Record | Attributes |
| --- | --- | --- |
| 0 | `sublang-text 1 schema=1 stage=High revision=1` | must be the first record |
| 1 | `feature "ext.bytes.v1"` (zero or more) | one per extension the module needs; must equal the set the module needs |
| 2 | `module "name" entry=N` | module name and entry function id |
| 3 | `source id=N name="..."` | source file names |
| 4 | `span id=N source=N line=N column=N origin="..."` | |
| 5 | `type id=N kind="..." name="..." width=N signed=B target=N nullable=B span=N` | ids 1 to 4 are the implicit primitives and are never printed |
| 6 | `field id=N owner=N name="..." type=N mutable=B span=N` | field order within an owner is the id order |
| 7 | `profile id=N name="..." version=N integer-rules="..." float-rules="..." failure-model="..." unwinding-model="..."` | |
| 8 | `failure id=N name="..." behavior="..." binding="..." signature="..." continues=B unwinding="..." span=N` | |
| 9 | `location id=N kind="..." name="..." span=N` | |
| 10 | `alias id=N left=N right=N answer="..." origin="..." label="..." revision=N span=N proof-analysis="..." proof-revision=N proof-deps=[...]` | revision must equal the module revision |
| 11 | `effect id=N name="..." span=N`, then its facts | |
| 11 | `fact area="..." value="..." provenance="..." detail="..." label="..." proof-analysis="..." proof-revision=N proof-deps=[...] locations=[...]` | directly after its effect or another fact |
| 12 | `class type=N tag=N` | dispatch table, only when non-empty |
| 13 | `group id=N name="..." root=N field=N prototype=N` | dispatch table, only when non-empty |
| 14 | `entry group=N tag=N function=N` | dispatch table; `group` must name an existing group |
| 15 | `func id=N name="..." returnType=N methodOf=N span=N profile=N effect=N linkage="..." convention="sublang" definition="..."` | convention must be `sublang` |
| 16 | `value id=N type=N` | value ids 1..n, in order, directly after their func |
| 17 | `param id=N name="..." type=N passing="..." noescape=B` | after the values, before the blocks |
| 18 | `block id=N params=[...]` | block ids 1..n; block 1 is the entry block |
| 19 | `op id=N opcode="..." span=N result=N type=N ownership="..." ref=N scope=N overflow="..." predicate="..." fpmode="..." effect=N int=N bool=B bits=N text="..." operands=[...] modes=["..."] targets=[...] trueargs=N` | after its block or another op; every operation attribute is written |
| end | `end` | the last record; nothing may follow it |

Records that are not in the table are `TX002`. `value`, `param`, `block` and `op` belong to the
most recent `func`, `block` and `effect`, which is why their order is part of the grammar.

## Ids

Span, source, type, field, profile, failure, location, alias, effect, group, function, value and
block ids are table ordinals: 1, 2, 3, ... with no gap and no repeat. The parser checks each id
against the next ordinal and reports `TX003`. Operation ids must be unique in the module; gaps are
allowed, as after linking. Every id is preserved exactly.

The scope counter of a function is not part of Wire and is not printed.

## Limits

| Limit | Value | Reported as |
| --- | --- | --- |
| input | 4 MiB (4,194,304 bytes) | `TX004` |
| lines | 200,000 | `TX004` |
| one line | 64 KiB (65,536 bytes) | `TX004` |

The limits are checked before any line is parsed. `text-dump` checks the same limits on its output,
so it refuses to print text that `text-build` could not read. The per-line limit is the one that
can be reached in practice: a string constant of tens of kilobytes with many escapes can produce a
record longer than 64 KiB. Such a module is refused by `text-dump` (`TX004`); it is not truncated.

## Diagnostics

Every failure is one line: `SUBLANG-TXnnn: line L column C: reason`, where L is 1-based and C is the
1-based byte column of the token where the problem was detected. Module-level checks (feature set,
missing end, verification) have no position.

| Code | Meaning |
| --- | --- |
| `SUBLANG-TX001` | syntax: bad or unterminated string, bad escape, raw byte outside a string or in a comment, malformed or out-of-range integer, missing or extra token, record out of order, record before the module, duplicate module, record after `end`, missing `end` (truncated input) |
| `SUBLANG-TX002` | unknown record keyword, unknown or misplaced attribute, unknown feature name |
| `SUBLANG-TX003` | duplicate or non-dense table id, duplicate operation id |
| `SUBLANG-TX004` | input or line limit exceeded (see Limits) |
| `SUBLANG-TX005` | record is inconsistent with the module: unsupported version, schema, stage or revision; calling convention other than `sublang`; alias revision different from the module revision; `entry` naming an unknown group; feature records that do not match the features the module needs |
| `SUBLANG-TX006` | verification failed: `SUBLANG-TX006: verification failed: <code> <message>`, where `<code>` is the first diagnostic of `SublangVerifier`, for example `SUBLANG-S001 unknown opcode int.bogus` |

Errors are reported at the first failure. The verifier diagnostic code is printed as is, so a
module that fails verification can be looked up in `docs/Sublang_Diagnostics.md`.

## CLI

```sh
sublang text-dump INPUT.sublang-wire            # canonical text on stdout
sublang text-build INPUT.sublang-text OUTPUT.sublang-wire
```

- `text-dump` reads Wire the way `dump` does and prints the canonical text. It does not verify
  the module. Exit 1 for malformed Wire (the Wire diagnostic is printed) or for text beyond the
  limits.
- `text-build` parses, verifies and freezes the text, then writes Wire. Exit 0 on success. On any
  error the diagnostic is printed on stdout and the exit status is 1; nothing is written.
- Usage errors and non-regular files exit 2 (`SUBLANG-CLI002`). Existing commands are unchanged.

## Checks

`bash scripts/sublang-text-sandbox.sh` builds `src/SublangMain.ems` and `src/SublangTextSmoke.ems`
inside the capped sandbox and runs:

1. The in-process checks of `src/SublangTextSmoke.ems`: every byte 0 to 255 round-trips through the
   codec and the lexer, the NUL and UTF-8 escapes, the Int64 range, the lexer and parser diagnostics,
   and the limits.
2. For every `examples/wire/*.sublang-wire` (and `examples/frontend/tiny/*.sublang-wire` if present):
   `text-dump` twice (must be identical), `text-build`, and a byte comparison of the rebuilt Wire with
   the original for transport 2; for transport 1 a comparison of the text of the rebuilt Wire.
3. Negative inputs made with `head`, `sed` and `printf`: truncated file (`TX001`), unknown record
   (`TX002`), duplicate span id (`TX003`), bad escape (`TX001`), non-ASCII comment (`TX001`),
   over-long line (`TX004`), and an unknown opcode in an otherwise valid module (`TX006` with
   `SUBLANG-S001`). Each must exit 1 with the named diagnostic.
4. A module name with `\x00` and `\xC3\xA4` built by `text-build` and read back by `text-dump`
   through Wire.

The script prints one `PASS` line per check and ends with `Sublang text: all checks passed`; any
failure exits non-zero.

## Implementation notes

The package `src/sublang/text/` has eight files: `SublangTextCodec` (escapes, integers, lists),
`SublangTextLexer` and `SublangTextCursor` (tokens and typed readers), `SublangTextResult` (the
result and the parser state), `SublangTextParser` and `SublangTextBodyParser` (the records; the
module is rebuilt only through the public builder APIs), and `SublangTextPrinter` and
`SublangTextBodyPrinter` (the output).
