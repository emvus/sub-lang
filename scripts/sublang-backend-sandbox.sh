#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/.verify.XXXXXXXX")"
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
  "$IMAGE" timeout --signal=TERM --kill-after=5s 300s sh -c '
    set -eu
    mkdir /tmp/backend
    timeout 180s /emerald/emerald-stable/emerald-compiler build /project/src/SublangBackendSmoke.ems -o /tmp/backend-generator
    timeout 20s /tmp/backend-generator
    for spec in static-string:200 inline-list:199 owned-list:199 value-list:42 inline-local:42 nested-regions:28 bond-cycle:55 bond-component:4242 arithmetic:4000000000 loop:5072 record:41 floating:1 object:43 object-cfg:89 scoped-runtime:36 borrowed-calls:82 owned-transfers:82 root-graph:43 root-deep:10000 folded-fields:42 shard-mixed:5085 root-churn:5085 pool-borrow:100 integer-parity:47 division:0 constant-calls:49 folded-getter:42 borrowed-graph:42 pool-graph-inner:2100 pool-graph-outer:2100; do
      name=${spec%:*}
      expected=${spec#*:}
      for variant in base opt; do
        file=/tmp/backend/$name-$variant
        llvm-as "$file.ll" -o "$file.bc"
        opt -passes="mem2reg,instcombine,simplifycfg" "$file.bc" -o "$file.checked.bc"
        interpreted=$(timeout 10s lli "$file.bc")
        test "$interpreted" = "$expected"
        clang -Wno-override-module -O2 "$file.checked.bc" -o "$file.bin"
        actual=$(timeout 10s "$file.bin")
        test "$actual" = "$expected"
        echo "PASS native+LLVM $name-$variant = $actual"
      done
    done
    for name in string-bounds overflow mul-overflow div-zero div-overflow call-overflow; do
    for variant in base opt; do
      file=/tmp/backend/$name-$variant
      llvm-as "$file.ll" -o "$file.bc"
      clang -Wno-override-module -O2 "$file.bc" -o "$file.bin"
      set +e
      timeout 10s "$file.bin" >/tmp/overflow.stdout 2>/tmp/overflow.stderr
      status=$?
      set -e
      test "$status" = 134
      test ! -s /tmp/overflow.stdout
      echo "PASS $name-$variant aborts (SIGABRT), even if its result is discarded"
    done
    done
    grep -q "%fold.*alloca i64" /tmp/backend/object-opt.ll
    grep -q "call ptr @sublang.flow.allocate.t.*(ptr %scope" /tmp/backend/object-base.ll
    grep -q "call void @sublang.flow.end(ptr %scope" /tmp/backend/object-base.ll
    grep -q "Folded: primitive fields" /tmp/backend/object-cfg-opt.plan
    grep -q "Heap: Flow disabled" /tmp/backend/object-cfg-base.plan
    test "$(grep -c "call void @sublang.flow.end(ptr %scope" /tmp/backend/object-cfg-base.ll)" = 2
    grep -q "Pool: reusable per-site frame slot" /tmp/backend/pool-borrow-opt.plan
    grep -q "%pool.*alloca %t" /tmp/backend/pool-borrow-opt.ll
    grep -q "Local: entry allocation" /tmp/backend/borrowed-calls-opt.plan
    clang -Wno-override-module -O1 -fsanitize=leak /tmp/backend/scoped-runtime-base.ll -o /tmp/backend/leak-check
    test "$(timeout 10s /tmp/backend/leak-check)" = 36
    grep -q "ScopeOwned: ownership transfer requires stable storage" /tmp/backend/owned-transfers-opt.plan
    for variant in base opt; do
      clang -Wno-override-module -O1 -fsanitize=leak /tmp/backend/owned-transfers-$variant.ll -o /tmp/backend/owned-leak-check
      test "$(timeout 10s /tmp/backend/owned-leak-check)" = 82
    done
    for name in root-graph root-deep; do
      for variant in base opt; do
        clang -Wno-override-module -O1 -fsanitize=leak /tmp/backend/$name-$variant.ll -o /tmp/backend/root-leak-check
        timeout 10s /tmp/backend/root-leak-check >/tmp/root-result
      done
    done
    grep -q "Root: owned reference fields" /tmp/backend/root-graph-opt.plan
    grep -q "Shard: closed ownership graph" /tmp/backend/shard-mixed-opt.plan
    grep -q "call ptr @sublang.shard.allocate(ptr %region" /tmp/backend/shard-mixed-opt.ll
    grep -q "call void @sublang.shard.end(ptr %shard" /tmp/backend/shard-mixed-opt.ll
    for name in inline-list inline-local owned-list nested-regions bond-cycle bond-component; do
      for variant in base opt; do
        clang -Wno-override-module -O1 -fsanitize=address /tmp/backend/$name-$variant.ll -o /tmp/backend/full-flow-asan
        timeout 10s /tmp/backend/full-flow-asan >/tmp/full-flow-result
      done
    done
    grep -q "Root: owned reference fields" /tmp/backend/root-deep-opt.plan
    grep -q "early subtree release" /tmp/backend/root-churn-opt.plan
    ! grep -q "Shard:" /tmp/backend/root-churn-opt.plan
    grep -q "Folded: primitive fields" /tmp/backend/folded-fields-opt.plan
    grep -q "Folded: primitive fields" /tmp/backend/folded-getter-opt.plan
    ! grep -q "call i64 @fn1" /tmp/backend/constant-calls-opt.ll
    clang -Wno-override-module -O1 -fsanitize=address /tmp/backend/borrowed-graph-opt.ll -o /tmp/backend/view-asan
    test "$(timeout 10s /tmp/backend/view-asan)" = 42
    for name in pool-graph-inner pool-graph-outer; do
      grep -q "Pool: reusable graph slot" /tmp/backend/$name-opt.plan
      clang -Wno-override-module -O1 -fsanitize=address /tmp/backend/$name-opt.ll -o /tmp/backend/pool-graph-asan
      test "$(timeout 10s /tmp/backend/pool-graph-asan)" = 2100
    done
    # Compile the standalone CLI once, then process a file without a builder driver.
    timeout 180s /emerald/emerald-stable/emerald-compiler build /project/src/SublangMain.ems -o /tmp/backend/sublang
    /tmp/backend/sublang --version
    timeout 30s /tmp/backend/sublang emit-llvm /tmp/backend/borrowed-graph.sublang-wire /tmp/backend/from-file.ll on on
    llvm-as /tmp/backend/from-file.ll -o /tmp/backend/from-file.bc
    test "$(timeout 10s lli /tmp/backend/from-file.bc)" = 42
    echo "PASS standalone binary consumes versioned IR file with Flow"
    /tmp/backend/sublang capabilities > /tmp/backend/capabilities.txt
    grep -qx "wire.read=1,2" /tmp/backend/capabilities.txt
    grep -qx "feature=core.native64.v2" /tmp/backend/capabilities.txt
    /tmp/backend/sublang capabilities | cmp -s - /tmp/backend/capabilities.txt
    echo "PASS capability discovery is deterministic"
    timeout 30s /tmp/backend/sublang dump /tmp/backend/borrowed-graph.sublang-wire > /tmp/backend/dump1.txt
    timeout 30s /tmp/backend/sublang dump /tmp/backend/borrowed-graph.sublang-wire | cmp -s - /tmp/backend/dump1.txt
    grep -q "^module " /tmp/backend/dump1.txt
    set +e
    /tmp/backend/sublang dump /tmp/backend/does-not-exist > /dev/null
    dump_status=$?
    set -e
    test "$dump_status" = 2
    echo "PASS IR dump command is deterministic and rejects missing input"
    timeout 30s /tmp/backend/sublang emit-llvm /project/examples/wire/arithmetic.sublang-wire /tmp/backend/rep-on.ll on on
    timeout 30s /tmp/backend/sublang emit-llvm /project/examples/wire/arithmetic.sublang-wire /tmp/backend/rep-off.ll on off
    grep -q "^optimind: enabled" /tmp/backend/rep-on.ll.plan
    grep -q "^optimind: fn1 main: [1-9][0-9]* decisions" /tmp/backend/rep-on.ll.plan
    grep -q "^optimind: disabled" /tmp/backend/rep-off.ll.plan
    echo "PASS Optimind decision report is present in the plan and respects --optimind=off"
    for variant in base opt; do
      clang -Wno-override-module -O1 -fsanitize=address /tmp/backend/shard-mixed-$variant.ll -o /tmp/backend/shard-asan
      test "$(timeout 10s /tmp/backend/shard-asan)" = 5085
    done
    echo "PASS Folded scalar fields, Pool borrow placement and mixed Shard/heap ASan+LSan"
    echo "PASS Root trees, iterative deep destruction and LeakSanitizer"
    echo "PASS owned transfer/return cleanup and LeakSanitizer"
    echo "PASS scope-owned allocation/cleanup, mixed placement and LeakSanitizer"
    echo "PASS explainable Local/Heap plan and two terminal cleanup sites"
    echo "PASS Flow Folded eliminates object storage; baseline explicitly frees"
    echo "Sublang backend: all checks passed"
    cp /tmp/backend/sublang /export/sublang
    cp /tmp/backend/*.sublang-wire /export/
  '
test -f "$STAGE/sublang" && test ! -L "$STAGE/sublang"
mkdir -p "$ROOT/build/ir"
for artifact in "$STAGE"/*.sublang-wire; do
  test -f "$artifact" && test ! -L "$artifact"
  mv -- "$artifact" "$ROOT/build/ir/$(basename -- "$artifact")"
done
mv -- "$STAGE/sublang" "$ROOT/build/sublang"
