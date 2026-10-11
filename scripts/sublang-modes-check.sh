#!/usr/bin/env bash
# Output modes, LTO and PGO of the build launcher. Everything runs in the capped sandbox via
# sublang-build.sh. Requires build/sublang (scripts/sublang-bootstrap.sh) and python3 for Tiny.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/modes"
mkdir -p "$OUT/profile"
fail() { echo "FAIL $*" >&2; exit 1; }
build() { bash "$ROOT/scripts/sublang-build.sh" "$@" 2>&1; }
first_line() { local text; text="$("$@" 2>/dev/null)"; printf '%s\n' "${text%%$'\n'*}"; }

python3 -I "$ROOT/examples/frontend/tiny/tiny.py" "$ROOT/examples/frontend/tiny/fib.tiny" "$OUT/fib.sublang-wire"
python3 -I "$ROOT/examples/frontend/tiny/tiny.py" "$ROOT/examples/frontend/tiny/factorial.tiny" "$OUT/fact.sublang-wire"

for lto in off full thin; do
  result="$(first_line bash "$ROOT/scripts/sublang-build.sh" "$OUT/fib.sublang-wire" -o "$OUT/fib-$lto" --lto=$lto --llvm-opt=2 --run)"
  [[ "$result" == 6000 ]] || fail "lto=$lto produced '$result'"
  grep -qx "lto=$lto" "$OUT/fib-$lto.config" || fail "configuration for lto=$lto was not recorded"
  echo "PASS lto=$lto preserves the result and records its configuration"
done

build "$OUT/fib.sublang-wire" -o "$OUT/fib-obj" --emit=obj >/dev/null
[[ -s "$OUT/fib-obj.o" && ! -e "$OUT/fib-obj" ]] || fail "emit=obj must export an object and no executable"
build "$OUT/fib.sublang-wire" -o "$OUT/fib-bc" --emit=bc >/dev/null
[[ -s "$OUT/fib-bc.bc" && ! -e "$OUT/fib-bc" ]] || fail "emit=bc must export bitcode and no executable"
echo "PASS emit=obj and emit=bc export the requested artifact only"

build "$OUT/fib.sublang-wire" -o "$OUT/fib-train" --pgo=train --llvm-opt=2 >/dev/null
cp "$OUT/fib-train.profdata" "$OUT/profile/program.profdata"
cp "$OUT/fib-train.profmeta" "$OUT/profile/program.profmeta"
result="$(first_line bash "$ROOT/scripts/sublang-build.sh" "$OUT/fib.sublang-wire" -o "$OUT/fib-use" --pgo=use --profile="$OUT/profile" --llvm-opt=2 --run)"
[[ "$result" == 6000 ]] || fail "pgo=use produced '$result'"
echo "PASS PGO train then use applies a matching profile"

set +e
build "$OUT/fact.sublang-wire" -o "$OUT/fact-use" --pgo=use --profile="$OUT/profile" --llvm-opt=2 >"$OUT/stale.out"
status=$?
set -e
[[ "$status" != 0 ]] && grep -q "SUBLANG-PGO001" "$OUT/stale.out" || fail "a profile of another program was accepted"
echo "PASS a stale profile is rejected with SUBLANG-PGO001"
echo "Build modes: all checks passed"
