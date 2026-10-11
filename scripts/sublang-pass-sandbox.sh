#!/usr/bin/env bash
# Builds and runs the snapshot/pass/effect checks inside the capped sandbox.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp -e EMERALD_HOME=/emerald \
  -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 300s sh -c '
    set -eu
    timeout 240s /emerald/emerald-stable/emerald-compiler build /project/src/SublangPassSmoke.ems -o /tmp/pass-smoke
    timeout 60s /tmp/pass-smoke
  '
