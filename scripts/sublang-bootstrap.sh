#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/.bootstrap.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp -e EMERALD_HOME=/emerald \
  -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 240s sh -c '
    set -eu
    /emerald/emerald-stable/emerald-compiler build /project/src/SublangMain.ems -o /tmp/sublang
    /tmp/sublang --version
    cp /tmp/sublang /export/sublang
  '
test -f "$STAGE/sublang" && test ! -L "$STAGE/sublang"
mv -- "$STAGE/sublang" "$ROOT/build/sublang"
echo "Built standalone IR compiler: $ROOT/build/sublang"
