#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/.dynamic.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
docker run --rm --init --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp -e EMERALD_HOME=/emerald \
  -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 600s sh -c '
    set -eu
    mkdir /tmp/dyn
    timeout 180s /emerald/emerald-stable/emerald-compiler build /project/src/SublangDynamicSmoke.ems -o /tmp/dyn-generator
    timeout 60s /tmp/dyn-generator
    test -s /tmp/dyn/dyn-d1-on.plan
    grep -q "may leave the region" /tmp/dyn/dyn-d1-on.plan
    echo "PASS D1 plan artifact names the blocker"
    # Results: each program returns an Int; the expected value is fixed by construction.
    for spec in dyn-d1:111 dyn-d2:11 dyn-d3:1527 dyn-d5:142; do
      name=${spec%:*}
      expected=${spec#*:}
      for variant in off on; do
        file=/tmp/dyn/$name-$variant
        llvm-as "$file.ll" -o "$file.bc"
        opt -passes=verify -disable-output "$file.bc"
        eh=""
        if grep -q "__gxx_personality_v0" "$file.ll"; then eh="-lstdc++"; fi
        clang -Wno-override-module -O2 "$file.bc" $eh -o "$file.bin"
        actual=$(timeout 10s "$file.bin")
        test "$actual" = "$expected"
        echo "PASS native $name-$variant = $actual"
      done
    done
    # ASan and LeakSanitizer: owned Dyn values must be released exactly once in both variants.
    for spec in dyn-d1:111 dyn-d2:11 dyn-d5:142; do
      name=${spec%:*}
      expected=${spec#*:}
      for variant in off on; do
        file=/tmp/dyn/$name-$variant
        clang -Wno-override-module -O1 -fsanitize=address "$file.bc" -o /tmp/dyn/asan-bin
        set +e
        actual=$(timeout 20s /tmp/dyn/asan-bin 2>/tmp/dyn/asan.stderr)
        status=$?
        set -e
        test "$status" = 0
        test "$actual" = "$expected"
        echo "PASS ASan+LeakSanitizer $name-$variant = $actual"
      done
    done
    # D4: aborting programs terminate with SIGABRT, print nothing, and do not return a value.
    for name in dyn-d4-type dyn-d4-inexact dyn-d4-overflow; do
      for variant in off on; do
        file=/tmp/dyn/$name-$variant
        llvm-as "$file.ll" -o "$file.bc"
        opt -passes=verify -disable-output "$file.bc"
        eh=""
        if grep -q "__gxx_personality_v0" "$file.ll"; then eh="-lstdc++"; fi
        clang -Wno-override-module -O2 "$file.bc" $eh -o "$file.bin"
        set +e
        timeout 10s "$file.bin" >/tmp/dyn/abort.stdout 2>/tmp/dyn/abort.stderr
        status=$?
        set -e
        test "$status" = 134
        test ! -s /tmp/dyn/abort.stdout
        echo "PASS $name-$variant aborts (SIGABRT), prints nothing"
      done
    done
    cp /tmp/dyn/*.ll /tmp/dyn/*.plan /export/
    echo "Sublang dynamic: all checks passed"
  '
test -d "$STAGE" && test ! -L "$STAGE"
mkdir -p "$ROOT/build/dyn"
for artifact in "$STAGE"/*.ll "$STAGE"/*.plan; do
  test -f "$artifact" && test ! -L "$artifact"
  mv -- "$artifact" "$ROOT/build/dyn/$(basename -- "$artifact")"
done
