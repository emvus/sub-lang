#!/usr/bin/env bash
# One bounded acceptance run: language-generated runtime IR, with Flow on/off.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp -e EMERALD_HOME=/emerald \
  -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
  "${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}" \
  timeout --signal=TERM --kill-after=5s 300s sh -c '
    set -eu
    timeout 240s /emerald/emerald-stable/emerald-compiler build /project/src/SublangRuntimeSmoke.ems -o /tmp/runtime-smoke
    timeout 30s /tmp/runtime-smoke
    for mode in off on cli; do
      llvm-as "/tmp/runtime-$mode.ll" -o "/tmp/runtime-$mode.bc"
      opt -passes=verify -disable-output "/tmp/runtime-$mode.bc"
      clang -O2 "/tmp/runtime-$mode.ll" -o "/tmp/runtime-$mode"
      test "$(timeout 5s "/tmp/runtime-$mode")" = 42
    done
    echo "Runtime IR native acceptance passed (Flow off/on: 42)"
  '
