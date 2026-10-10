#!/usr/bin/env bash
# Checks the independent Tiny frontend end to end. The frontend (python3) only writes
# Wire files; compilation and every generated program run in the capped sandbox via
# sublang-build.sh. Requires build/sublang (scripts/sublang-bootstrap.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TINY="$ROOT/examples/frontend/tiny"
OUT="$ROOT/build/tiny"
mkdir -p "$OUT"
fail() { echo "FAIL $*" >&2; exit 1; }

compile() { python3 -I "$TINY/tiny.py" "$TINY/$1.tiny" "$OUT/$1.sublang-wire"; }
build_run() {
  local text
  text="$(bash "$ROOT/scripts/sublang-build.sh" "$OUT/$1.sublang-wire" -o "$OUT/$1" --flow="$2" --optimind="$3" --llvm-opt="$4" --run 2>/dev/null)"
  printf '%s\n' "${text%%$'\n'*}"
}

expect_value() { # name expected
  local name=$1 expected=$2 flow optimind level actual
  compile "$name"
  for config in "on on 2" "off off 0"; do
    read -r flow optimind level <<<"$config"
    actual="$(build_run "$name" "$flow" "$optimind" "$level")"
    [[ "$actual" == "$expected" ]] || fail "$name flow=$flow optimind=$optimind -O$level: expected $expected, got '$actual'"
    echo "PASS tiny $name = $actual (flow=$flow optimind=$optimind -O$level)"
  done
}

expect_value fib 6000
expect_value factorial 2432902008176640000

for trap in overflow divzero; do
  compile "$trap"
  if bash "$ROOT/scripts/sublang-build.sh" "$OUT/$trap.sublang-wire" -o "$OUT/$trap" --flow=on --optimind=on --llvm-opt=2 --run >"$OUT/$trap.out" 2>&1; then
    fail "$trap: program must abort, it completed"
  fi
  grep -qE "^(4000000000|[0-9]+)$" "$OUT/$trap.out" && fail "$trap: printed a value instead of aborting"
  echo "PASS tiny $trap aborts instead of wrapping"
done

if python3 -I "$TINY/tiny.py" "$TINY/undefined.tiny" "$OUT/undefined.sublang-wire" 2>"$OUT/undefined.err"; then
  fail "undefined variable must be rejected by the frontend"
fi
grep -q "undefined variable 'missing'" "$OUT/undefined.err" || fail "missing frontend diagnostic"
echo "PASS tiny frontend rejects undefined variables with a source position"
# A verifier finding must keep its own code and source position through the backend gate.
python3 -I - "$OUT/fib.sublang-wire" "$OUT/bad-opcode.sublang-wire" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
assert b"7:int.add," in data
open(sys.argv[2], "wb").write(data.replace(b"7:int.add,", b"7:int.xyz,", 1))
PY
if bash "$ROOT/scripts/sublang-build.sh" "$OUT/bad-opcode.sublang-wire" -o "$OUT/bad-opcode" >"$OUT/bad-opcode.out" 2>&1; then
  fail "invalid opcode must be rejected"
fi
grep -q "SUBLANG-B002: SUBLANG-S001 unknown opcode int.xyz (line [0-9]*, column [0-9]*)" "$OUT/bad-opcode.out" \
  || fail "verifier finding lost its code or position: $(cat "$OUT/bad-opcode.out")"
echo "PASS backend gate reports the verifier code and source position"
echo "Tiny frontend: all checks passed"
