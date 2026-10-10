#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
RUNS=5
shopt -s nullglob
while (($#)); do
  case "$1" in
    --runs=*) RUNS="${1#*=}"; shift ;;
    -h|--help) echo 'Usage: sublang-measure.sh [--runs=N]   (N=1..25, default 5; writes build/measure/<timestamp>.tsv)'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$RUNS" in ''|*[!0-9]*) echo 'Invalid run count' >&2; exit 2 ;; esac
if ((RUNS < 1 || RUNS > 25)); then echo 'Run count must be 1..25' >&2; exit 2; fi
INPUTS=("$ROOT"/examples/wire/*.sublang-wire)
if ((${#INPUTS[@]} == 0)); then echo 'No examples/wire/*.sublang-wire inputs found' >&2; exit 2; fi
if [[ ! -x "$ROOT/build/sublang" ]]; then echo 'Build the standalone compiler once: bash scripts/sublang-bootstrap.sh' >&2; exit 2; fi
mkdir -p "$ROOT/build/measure"
STAGE="$(mktemp -d "$ROOT/build/.measure.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
# One capped container measures every input. Inputs and the compiler are read-only;
# the only writable paths are the tmpfs /tmp scratch and the empty export directory.
# The worker is POSIX sh (no bash required in the image). Timing uses date +%s%N when
# it yields nanoseconds, otherwise every timing cell is n/a. Peak RSS uses GNU time
# (%M, KB) when /usr/bin/time exists, else polls VmHWM in /proc/<pid>/status, else n/a.
read -r -d '' WORKER <<'WORKER_EOF' || true
set -u
RUNS=$1
BIN=/project/build/sublang
SRC_DIR=/project/examples/wire
OUT=/export/measure.tsv
W=/tmp/measure
OPT_LEVEL=3
COMPILE_LIMIT=120
RUN_LIMIT=20
mkdir -p "$W"
printf 'input\tflow\toptimind\tcompile_ms\tllvm_opt_ms\tlink_ms\trun_ms_median\tpeak_rss_kb\toutput\texit\n' > "$OUT"

TIME_BIN=
if [ -x /usr/bin/time ]; then TIME_BIN=/usr/bin/time; fi
PROC_OK=0
if [ -r /proc/self/status ]; then PROC_OK=1; fi
NS_OK=0
t=$(date +%s%N 2>/dev/null) || t=
case $t in ''|*[!0-9]*) ;; *) NS_OK=1 ;; esac
if [ "$NS_OK" = 0 ]; then echo 'measure: date +%s%N unsupported; timings reported as n/a' >&2; fi
if [ -z "$TIME_BIN" ] && [ "$PROC_OK" = 0 ]; then echo 'measure: no /usr/bin/time and no /proc; peak RSS reported as n/a' >&2; fi

now_ns() {
  if [ "$NS_OK" = 1 ]; then date +%s%N; else echo 0; fi
}
elapsed_ms() {
  if [ "$NS_OK" = 1 ]; then echo $(( ($2 - $1) / 1000000 )); else echo n/a; fi
}

# One execution of binary $1 with output prefix $2. Sets RUN_STATUS, RUN_MS, RUN_RSS.
run_once() {
  bin=$1; pfx=$2
  RUN_RSS=n/a
  s=$(now_ns)
  if [ -n "$TIME_BIN" ]; then
    timeout --signal=KILL "${RUN_LIMIT}s" "$TIME_BIN" -f "%M" -o "$pfx.time" "$bin" >"$pfx.out" 2>"$pfx.err"
    RUN_STATUS=$?
    if read -r RUN_RSS 2>/dev/null < "$pfx.time"; then :; else RUN_RSS=n/a; fi
  elif [ "$PROC_OK" = 1 ]; then
    "$bin" >"$pfx.out" 2>"$pfx.err" &
    pid=$!
    ( sleep "$RUN_LIMIT"; kill -KILL "$pid" 2>/dev/null ) &
    wd=$!
    peak=0
    while [ -r "/proc/$pid/status" ]; do
      st=
      while read -r k v _; do
        case $k in
          VmHWM:) if [ "${v:-0}" -gt "$peak" ]; then peak=$v; fi ;;
          State:) st=$v ;;
        esac
      done 2>/dev/null < "/proc/$pid/status"
      if [ "$st" = Z ]; then break; fi
    done
    wait "$pid"
    RUN_STATUS=$?
    kill "$wd" 2>/dev/null || true
    wait "$wd" 2>/dev/null || true
    if [ "$peak" -gt 0 ]; then RUN_RSS=$peak; fi
  else
    timeout --signal=KILL "${RUN_LIMIT}s" "$bin" >"$pfx.out" 2>"$pfx.err"
    RUN_STATUS=$?
  fi
  e=$(now_ns)
  RUN_MS=$(elapsed_ms "$s" "$e")
}

for src in "$SRC_DIR"/*.sublang-wire; do
  [ -f "$src" ] || continue
  name=$(basename "$src" .sublang-wire)
  for flow in off on; do
    d="$W/$name-$flow"
    mkdir -p "$d"
    FAIL=
    C_MS=n/a; O_MS=n/a; L_MS=n/a; R_MED=n/a; R_PEAK=n/a; OUTV=; EXIT_V=n/a

    # Stage 1: Sublang emit-llvm with the requested Flow mode and Optimind on.
    s=$(now_ns)
    timeout --signal=TERM --kill-after=5s "${COMPILE_LIMIT}s" "$BIN" emit-llvm "$src" "$d/program.ll" "$flow" on >"$d/emit.log" 2>&1 || FAIL=emit
    e=$(now_ns); C_MS=$(elapsed_ms "$s" "$e")
    if [ -z "$FAIL" ] && [ ! -s "$d/program.ll" ]; then FAIL=emit; fi

    # Stage 2: llvm-as + opt -O3 with verifier boundaries (timed together).
    if [ -z "$FAIL" ]; then
      s=$(now_ns)
      llvm-as "$d/program.ll" -o "$d/program.bc" && opt -passes="verify,default<O$OPT_LEVEL>,verify" "$d/program.bc" -o "$d/checked.bc" || FAIL=opt
      e=$(now_ns); O_MS=$(elapsed_ms "$s" "$e")
    fi

    # Stage 3: clang -O3 codegen and link (timed separately).
    if [ -z "$FAIL" ]; then
      s=$(now_ns)
      clang -Wno-override-module -O$OPT_LEVEL "$d/checked.bc" -o "$d/program" || FAIL=link
      e=$(now_ns); L_MS=$(elapsed_ms "$s" "$e")
    fi

    # Stage 4: RUNS sequential executions of the same binary.
    if [ -z "$FAIL" ]; then
      : > "$d/times"; : > "$d/rss"; : > "$d/status"
      i=1
      while [ "$i" -le "$RUNS" ]; do
        run_once "$d/program" "$d/run$i"
        echo "$RUN_MS" >> "$d/times"
        echo "$RUN_RSS" >> "$d/rss"
        echo "$RUN_STATUS" >> "$d/status"
        i=$((i + 1))
      done
      if [ "$NS_OK" = 1 ]; then
        R_MED=$(sort -n "$d/times" | sed -n "$(( (RUNS + 1) / 2 ))p")
      fi
      peak=$(grep -E '^[0-9]+$' "$d/rss" | sort -n | tail -n 1)
      if [ -n "$peak" ]; then R_PEAK=$peak; fi
      OUTV=$(tr '\n\t' '  ' < "$d/run1.out" | sed 's/ *$//')
      if [ -z "$OUTV" ]; then OUTV='<none>'; fi
      EXIT_V=$(sed -n 1p "$d/status")
      i=2
      while [ "$i" -le "$RUNS" ]; do
        if ! cmp -s "$d/run1.out" "$d/run$i.out" || [ "$(sed -n "${i}p" "$d/status")" != "$EXIT_V" ]; then
          EXIT_V=varied
          OUTV="$OUTV (runs differ)"
        fi
        i=$((i + 1))
      done
    else
      OUTV="FAIL:$FAIL"
      echo "measure: $name flow=$flow failed at stage $FAIL" >&2
      if [ "$FAIL" = emit ]; then tail -n 5 "$d/emit.log" >&2 || true; fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$flow" on "$C_MS" "$O_MS" "$L_MS" "$R_MED" "$R_PEAK" "$OUTV" "$EXIT_V" >> "$OUT"
  done
done
echo 'measure: complete' >&2
WORKER_EOF

docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 7200s sh -c "$WORKER" sh "$RUNS"
test -f "$STAGE/measure.tsv" && test ! -L "$STAGE/measure.tsv" || { echo 'Invalid measurement export' >&2; exit 1; }
TS="$(date +%Y%m%dT%H%M%S)"
DEST="$ROOT/build/measure/$TS.tsv"
if [[ -e "$DEST" ]]; then DEST="$ROOT/build/measure/$TS-$$.tsv"; fi
mv -- "$STAGE/measure.tsv" "$DEST"
echo "Wrote $DEST (inputs=${#INPUTS[@]}, runs=$RUNS, optimind=on, flow=off,on, LLVM -O3)"
