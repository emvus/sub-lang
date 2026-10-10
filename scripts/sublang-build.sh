#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
INPUT=""
OUTPUT="$ROOT/build/program"
FLOW=auto
OPTIMIND=on
RUN=0
LLVM_OPT=2
C_STANDARD=c17
while (($#)); do
  case "$1" in
    -o|--output) OUTPUT="${2:?missing output path}"; shift 2 ;;
    --flow=*) FLOW="${1#*=}"; shift ;;
    --optimind=*) OPTIMIND="${1#*=}"; shift ;;
    --run) RUN=1; shift ;;
    --llvm-opt=*) LLVM_OPT="${1#*=}"; shift ;;
    --c-standard=*) C_STANDARD="${1#*=}"; shift ;;
    -h|--help) echo 'Usage: sublang-build.sh input.sublang-wire|source.c|builder.ems [-o binary] [--flow=auto|on|off] [--optimind=on|off] [--llvm-opt=0|1|2|3] [--c-standard=c17] [--run]'; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) if [[ -n "$INPUT" ]]; then echo 'Only one source translation unit is accepted' >&2; exit 2; fi; INPUT="$1"; shift ;;
  esac
done
case "$FLOW" in auto|on|off) ;; *) echo 'Invalid Flow mode' >&2; exit 2 ;; esac
case "$OPTIMIND" in on) BOOL=true ;; off) BOOL=false ;; *) echo 'Invalid Optimind mode' >&2; exit 2 ;; esac
if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then echo 'Supply IR (.sublang-wire), a C source or builder.ems' >&2; exit 2; fi
case "$LLVM_OPT" in 0|1|2|3) ;; *) echo 'Invalid LLVM optimization level' >&2; exit 2 ;; esac
case "$C_STANDARD" in c89|c99|c11|c17) ;; *) echo 'Unsupported C standard (c89, c99, c11, c17)' >&2; exit 2 ;; esac
INPUT="$(realpath -- "$INPUT")"
case "$INPUT" in
  *.ems) FRONTEND=builder ;;
  *.c) FRONTEND=c ;;
  *.sublang-wire) FRONTEND=wire ;;
  *) echo 'Unsupported source extension: expected .sublang-wire, .c or .ems' >&2; exit 2 ;;
esac
if [[ "$FRONTEND" = c && "$FLOW" = on ]]; then
  echo 'SUBLANG-C001: C ownership import is not implemented; --flow=on cannot be satisfied. Use --flow=auto or off to preserve C malloc/free semantics.' >&2
  exit 2
fi
MOUNTS=(--mount "type=bind,src=$INPUT,dst=/input/SublangProgram.ems,readonly")
if [[ "$FRONTEND" = c ]]; then
  MOUNTS=(--mount "type=bind,src=$(dirname -- "$INPUT"),dst=/input,readonly")
  echo 'C frontend: LLVM optimization enabled according to --llvm-opt; Sublang High-IR Optimind passes and HyperAlloc Flow are unavailable for C and skipped.' >&2
elif [[ "$FRONTEND" = builder ]]; then
  MOUNTS+=(--mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly")
elif [[ ! -x "$ROOT/build/sublang" ]]; then
  echo 'Build the standalone compiler once: bash scripts/sublang-bootstrap.sh' >&2
  exit 2
fi
OUTPUT="$(realpath -m -- "$OUTPUT")"
OUTDIR="$(dirname -- "$OUTPUT")"
mkdir -p -- "$OUTDIR"
STAGE="$(mktemp -d "$OUTDIR/.sublang-build.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
# Only this empty staging directory is writable from the container. Input and both
# repositories are read-only; no Docker socket or host runtime access is exposed.
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  "${MOUNTS[@]}" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp -e EMERALD_HOME=/emerald \
  -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 300s sh /project/scripts/sublang-build-worker.sh \
    "$FRONTEND" "$FLOW" "$BOOL" "$RUN" "$LLVM_OPT" "$C_STANDARD" "$(basename -- "$INPUT")"
for suffix in '' .ll .bc .plan; do
  if [[ ! -f "$STAGE/program$suffix" || -L "$STAGE/program$suffix" ]]; then echo 'Invalid exported artifact' >&2; exit 1; fi
done
for suffix in '' .ll .bc .plan; do mv -- "$STAGE/program$suffix" "$OUTPUT$suffix"; done
echo "Built $OUTPUT (frontend=$FRONTEND, requested Flow=$FLOW, requested Optimind=$OPTIMIND, LLVM=-O$LLVM_OPT); effective pipeline: $OUTPUT.plan"
