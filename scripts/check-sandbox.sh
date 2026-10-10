#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
kind="${1:-all}"
case "$kind" in harness|examples|all) ;; *) echo "Usage: $0 [harness|examples|all]" >&2; exit 2 ;; esac
if [[ ! -x "$EMERALD_ROOT/emerald-stable/emerald-compiler" || ! -d "$EMERALD_ROOT/stdlib" ]]; then
    echo "Set SUBLANG_EMERALD_ROOT to an Emerald toolchain checkout with emerald-stable/emerald-compiler and stdlib." >&2
    exit 2
fi
docker run --rm --init --network=none --read-only --cap-drop=ALL \
    --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
    --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$ROOT,dst=/project,readonly" \
    --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
    --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
    -e HOME=/tmp -e EMERALD_HOME=/emerald \
    -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
    "$IMAGE" timeout --signal=TERM --kill-after=5s 420s sh -c '
      set -e
      if [ "$1" = harness ] || [ "$1" = all ]; then
        timeout 180s /emerald/emerald-stable/emerald-compiler build /project/src/SublangHarness.ems -o /tmp/sublang-harness
        timeout 20s /tmp/sublang-harness
      fi
      if [ "$1" = examples ] || [ "$1" = all ]; then
        timeout 180s /emerald/emerald-stable/emerald-compiler build /project/src/SublangExamples.ems -o /tmp/sublang-examples
        timeout 20s /tmp/sublang-examples
      fi
    ' sh "$kind"
