# Sublang measurement: compile cost, runtime and RSS

This note describes the baseline measurement launcher for Roadmap section 8
("Measurement and focused validation"). It records compile cost, program runtime
and peak resident memory for the Wire examples with Flow off and on. It is a
measurement harness, not a performance claim: read the [not comparable](#not-comparable)
section before quoting any number.

## Method

Input set: every `examples/wire/*.sublang-wire` file (the executable Wire inputs
described in `examples/wire/readme.md`).

For each input, two rows are produced: `flow=off` and `flow=on`, both with
`optimind=on`. The stages are:

1. **Compile (`compile_ms`)**: `build/sublang emit-llvm <input> program.ll <flow> on`.
   Covers reading the Wire file, decoding, verification, the Sublang High-IR passes
   and LLVM IR emission. It does not include Emerald, because the standalone binary
   consumes Wire input directly.
2. **LLVM optimization (`llvm_opt_ms`)**: `llvm-as` followed by
   `opt -passes="verify,default<O3>,verify"`. The `llvm-as` step is included here
   because it is part of the same stage.
3. **Link (`link_ms`)**: `clang -Wno-override-module -O3 checked.bc -o program`.
   This includes clang's code generation from bitcode and the link.
4. **Runtime (`run_ms_median`, `peak_rss_kb`, `output`, `exit`)**: the program is
   executed `N` times (default `N=5`, `--runs=` accepts 1 to 25). The median wall
   time is reported; peak RSS is the maximum across the runs. `output` is the first
   run's stdout, and `exit` is its exit status (`varied` if runs disagree; the
   output then carries the suffix `(runs differ)`).

All stages of all inputs run inside **one** capped Docker container, using the same
hardening as `scripts/sublang-build.sh`: `--network=none`, `--read-only`,
`--cap-drop=ALL`, `--security-opt=no-new-privileges`, 6,000,000,000 bytes memory and
memory-swap (no swap), `--cpus=2`, `--pids-limit=128`, `--ulimit core=0`, the host
user's UID/GID, `--init`, and an outer `timeout`. Inputs and the compiler are
read-only mounts; the only writable paths are a tmpfs `/tmp` and the empty staging
export directory. Each compile, optimization, link and run stage also has its own
timeout (120 s for compile, 20 s per program run).

Measurement mechanics:

- Wall time uses `date +%s%N` inside the container. If the image's `date` does not
  produce nanoseconds, every timing cell is reported as `n/a` rather than guessed.
- Peak RSS uses GNU time (`/usr/bin/time -f %M`, kilobytes, the child's `ru_maxrss`)
  when that binary exists in the image. Otherwise it polls `VmHWM` in
  `/proc/<pid>/status` while the program runs. If neither works, it reports `n/a`.
- Each run is preceded by no warm-up. The median of five runs damps first-run page
  cache and scheduling effects, but does not remove them.
- A run that exceeds 20 s is killed and recorded with a non-zero exit status.
- A failing compile, optimization or link stage writes a row with
  `output=FAIL:<stage>`, `exit=n/a`, and `n/a` for the remaining timing cells.

## How to run

```sh
bash scripts/sublang-bootstrap.sh          # builds build/sublang once
bash scripts/sublang-measure.sh            # N=5 runs per input and Flow mode
bash scripts/sublang-measure.sh --runs=9   # optional: more runs for a steadier median
```

Requirements: Docker with the image `emerald-selfhost-sandbox` (override with
`SUBLANG_SANDBOX_IMAGE`), and the bootstrap build. The launcher writes
`build/measure/<YYYYmmddTHHMMSS>.tsv` (`build/` is git-ignored). Repeat runs
get a separate file; nothing is overwritten.

Run it on an otherwise idle machine, and record the hardware, Docker version and
CPU governor next to the TSV, because these numbers are only comparable under the
same conditions (see below).

## Output format

Tab-separated, one header line, one row per input and Flow mode:

| Column | Meaning |
| --- | --- |
| `input` | Input name without `.sublang-wire` |
| `flow` | `off` or `on` (passed to `emit-llvm`) |
| `optimind` | Always `on` in this launcher |
| `compile_ms` | `emit-llvm` wall time, milliseconds |
| `llvm_opt_ms` | `llvm-as` + `opt -O3` (verifier boundaries included) |
| `link_ms` | `clang -O3` codegen and link from bitcode |
| `run_ms_median` | Median wall time of the `N` runs |
| `peak_rss_kb` | Maximum peak RSS over the runs, kilobytes (or `n/a`) |
| `output` | First run's stdout, trailing whitespace trimmed |
| `exit` | First run's exit status, or `varied` |

Expected correctness outputs for the examples are listed in `examples/wire/readme.md`.
A row whose `output` does not match them is a correctness failure, not a timing result.

## How to read

- Compare `flow=off` and `flow=on` rows of the same input from the same TSV. Do not
  compare across TSV files unless the hardware, Docker setup, runs and load are the same.
- `compile_ms` answers "what does Sublang cost at compile time". `run_ms_median` and
  `peak_rss_kb` answer "what does the produced program cost". Keep the two apart in
  any summary; a Flow-on row can be slower to compile and faster to run, or the reverse.
- Check `llvm_opt_ms` and `link_ms` only as a sanity check that the LLVM stages did
  not dominate or fail; they do not depend on Flow in any way the launcher controls
  beyond the IR they receive.
- Treat differences of a few milliseconds, or a few tens of kilobytes of RSS, as
  noise until repeated runs show otherwise. Re-run with `--runs=9` and compare medians.
- To know whether Flow changed anything for an input, compare the effective plans
  instead of the timings. The launcher does not export plans, so build the two
  variants with the normal builder and diff them:

  ```sh
  bash scripts/sublang-build.sh examples/wire/bond-cycle.sublang-wire -o build/bc-off --flow=off
  bash scripts/sublang-build.sh examples/wire/bond-cycle.sublang-wire -o build/bc-on  --flow=on
  diff build/bc-off.plan build/bc-on.plan
  ```

## Not comparable

Do not put these cases into a speed table, a comparison, or a claim about Flow:

- **Tiny programs where startup dominates.** `arithmetic`, `static-string`,
  `value-list`, `inline-local` and similar inputs finish in a few milliseconds of
  user code. Their `run_ms_median` mostly measures `exec`, dynamic loading and the
  timing wrapper, and the `date` resolution limits how small a number can be. Only
  the larger inputs (for example `bond-component` and `nested-regions`) are more
  likely to carry runtime signal, and even those should be read with the noise rule
  above. Check the actual `run_ms_median` against the run's own duration before
  treating a row as a runtime measurement.
- **Flow-off and Flow-on producing the same plan.** If the effective `.plan` is
  identical in both modes (no Folded, Pool, Shard or Root decisions change), the
  generated code is expected to be identical or nearly so. Any timing difference
  between those two rows is noise or environment, not an effect of Flow. Check with
  the `diff` above before interpreting a row.
- **Correctness tests are not speed claims.** `scripts/sublang-backend-sandbox.sh`
  verifies outputs, placement (`.plan` text, `alloca`/`call` patterns), ASan/LSan
  cleanliness and expected exit codes. Passing those checks shows the behavior is
  right and the placement is what the plan says; it does not show that anything is
  faster or smaller. The same holds for every `PASS` line in the repository.
- **Mixed or changed inputs across TSV files.** Rows from different timestamps,
  different `--runs` values, different Docker versions, or a machine under load are
  not comparable with each other.
- **Compile cost of the Emerald builder path.** `compile_ms` only covers the
  standalone `emit-llvm` path on `.sublang-wire` inputs. Builder `.ems` inputs and
  the Emerald frontend are not measured and must not be compared with these numbers.
- **C frontend.** C inputs use Clang's own optimization, have no Sublang High-IR
  passes and no Flow (the build script rejects `--flow=on` for C). They are outside
  this launcher and not comparable to Flow rows.
- **Peak RSS under the fallback.** The `/proc` polling path samples `VmHWM` while the
  process runs and can miss a short peak. Use the GNU time path (`/usr/bin/time`) for
  RSS; rows with `n/a` RSS are not evidence of low memory use.
- **Compile RSS.** The launcher does not record peak memory of `emit-llvm`, `opt` or
  `clang`. Only the program's RSS is measured.
- **Original-runtime compatibility.** A number from a Sublang-produced program says
  nothing about the original Emerald runtime. Establishing that needs explicit mapped
  cases, which are separate work under section 8.
- **Sanitizer builds.** ASan/LSan builds used for correctness are slower and use more
  memory by design; do not mix them into these rows. This launcher builds without
  sanitizers.
- **Single machine, single container.** Results describe this host with `--cpus=2`
  and a 6 GB cap. They are not a general claim about other hardware, cgroup limits
  or Flow-on behavior at larger heaps.

## Larger workloads: `--dir`

`scripts/sublang-measure.sh --dir=REPO_RELATIVE_DIR` measures the `*.sublang-wire`
files of another repository directory instead of `examples/wire` (the directory is
mounted read-only like the rest of the repository; `..` and absolute paths are
rejected). The bundled wire inputs are correctness-sized, so a heavier input can be
produced with the independent Tiny frontend:

```bash
mkdir -p build/bench
python3 examples/frontend/tiny/tiny.py examples/frontend/tiny/bench-numeric.tiny build/bench/bench-numeric.sublang-wire
bash scripts/sublang-measure.sh --runs=3 --dir=build/bench
```

`bench-numeric.tiny` is a 200,000,000-iteration checked-arithmetic loop whose result
is `1799999982`. One run on the development machine (`--runs=3`, LLVM `-O3`, Flow off
and on) gave about 150 ms of program time for both Flow settings and a peak RSS near
1.5 MB. Treat this as a smoke-level numeric data point only: one machine, three runs,
LLVM may restructure the loop, and the program has no heap values, so Flow on and off
are equivalent by construction. It is not an allocation, string or graph baseline, and
it supports no cross-implementation speed claim.
