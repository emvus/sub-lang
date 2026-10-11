#!/bin/bash
# One compatibility bundle in a minimal image containing only OS shell/coreutils runtimes.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# = 1 ]] || { echo 'Usage: sublang-bundle-smoke.sh PACKAGE' >&2; exit 2; }
PKG="$(realpath -- "$1")"
(cd "$PKG" && sha256sum -c --quiet SHA256SUMS)
(cd "$PKG" && cmp -s SYMLINKS.txt <(find . -type l -printf '%P -> %l\n' | LC_ALL=C sort))
[[ -f "$ROOT/build/toolchain-cache/clean-root.tar" ]] || { echo 'Build the bundle first' >&2; exit 2; }
CLEAN_IMAGE="$(docker import "$ROOT/build/toolchain-cache/clean-root.tar")"
trap 'docker image rm "$CLEAN_IMAGE" >/dev/null' EXIT
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$PKG,dst=/opt/Sublang bundle ä,readonly" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 -e HOME=/tmp -e PATH=/bin \
  --entrypoint /bin/bash "$CLEAN_IMAGE" -c '
    set -euo pipefail
    ! command -v clang; ! command -v opt; ! command -v emerald-compiler; ! command -v docker
    [[ ! -d /usr/include && ! -f /usr/lib/Scrt1.o ]]
    P="/opt/Sublang bundle ä"
    S="$P/bin/sublang"
    mkdir -p "/tmp/output path ä"
    O="/tmp/output path ä"
    "$S" toolchain info
    check() {
      local name="$1" expected="$2" flow="$3" actual
      actual="$("$S" build "$P/examples/wire/$name.sublang-wire" -o "$O/program" "--flow=$flow" --run)"
      [[ "$actual" = "$expected" ]] || { echo "FAIL $name/$flow: $actual"; exit 1; }
      echo "PASS $name Flow=$flow -> $actual"
    }
    for flow in off on; do
      check arithmetic 4000000000 "$flow"
      check inline-local 42 "$flow"
      check owned-list 199 "$flow"
      check nested-regions 28 "$flow"
      check pool-graph 2100 "$flow"
      check bond-cycle 55 "$flow"
      check bond-component 4242 "$flow"
      check static-string 200 "$flow"
      check exceptions 311 "$flow"
    done
    for lto in full thin; do
      actual="$("$S" build "$P/examples/wire/arithmetic.sublang-wire" -o "$O/program" "--lto=$lto" --run)"
      [[ "$actual" = 4000000000 ]]
      echo "PASS LTO=$lto"
    done
    "$S" build "$P/examples/wire/arithmetic.sublang-wire" -o "$O/program" --pgo=train
    actual="$("$S" build "$P/examples/wire/arithmetic.sublang-wire" -o "$O/program" --pgo=use "--profile=$O" --run)"
    [[ "$actual" = 4000000000 ]]
    echo "PASS PGO training/use"
    printf "#define ANSWER 42\n" > "$O/local.h"
    printf "#include <stdio.h>\n#include <stdlib.h>\n#include <stdint.h>\n#include \"local.h\"\nint main(void) { int64_t *p=malloc(sizeof(*p)); if(!p) return 1; *p=ANSWER; printf(\"%%lld\\n\", (long long)*p); free(p); return 0; }\n" > "$O/source.c"
    actual="$("$S" build "$O/source.c" -o "$O/c program" --run)"
    [[ "$actual" = 42 ]]
    echo "PASS C17 with sysroot/local include/malloc/free"
    set +e
    "$S" build "$P/examples/wire/overflow.sublang-wire" -o "$O/overflow" --run > "$O/overflow.out" 2>&1
    status=$?
    set -e
    [[ "$status" = 134 && ! -f "$O/overflow" ]]
    echo "PASS checked overflow; failed run did not publish executable"
    mkdir "$O/incompatible"
    printf "format=sublang-toolchain-1\nversion=0.0.0\ntarget=x86_64-unknown-linux-gnu\n" > "$O/incompatible/manifest.txt"
    if "$S" build "$P/examples/wire/arithmetic.sublang-wire" -o "$O/bad" "--toolchain-root=$O/incompatible" > "$O/rejected" 2>&1; then exit 1; fi
    grep -q SUBLANG-TC001 "$O/rejected"
    [[ ! -f "$O/bad" ]]
    echo "PASS incompatible explicit toolchain rejected"
    "$S" build "$P/examples/wire/bond-cycle.sublang-wire" -o "$O/bond" --flow=on
    T="$P/libexec/sublang/llvm"
    R="$(sed -n "s/^resource=//p" "$T/manifest.txt")"
    "$T/bin/clang" --target=x86_64-unknown-linux-gnu "--sysroot=$T/sysroot" "--gcc-install-dir=$T/sysroot/usr/lib/gcc/x86_64-pc-linux-gnu/16" "-resource-dir=$T/lib/clang/$R" "--ld-path=$T/bin/ld.lld" -Wno-override-module -O1 -fsanitize=address "$O/bond.bc" -o "$O/bond-asan"
    ASAN_OPTIONS=detect_leaks=1 "$T/lib/ld-linux-x86-64.so.2" --library-path "$T/lib:$T/sysroot/usr/lib" "$O/bond-asan" > "$O/asan.out"
    [[ "$(cat "$O/asan.out")" = 55 ]]
    echo "PASS Bond cleanup under ASan/LSan"
    echo "Sublang bundled toolchain: all checks passed"
  '
