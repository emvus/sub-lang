#!/bin/sh
# Text IR (M10) checks. Without arguments this starts the capped sandbox container and runs the
# script again inside it with --inside. Inside, it builds src/SublangMain.ems and src/SublangTextSmoke.ems,
# then checks the CLI: text-dump and text-build over every example Wire file, byte identity of the
# round trip, determinism, the negative inputs, and the NUL/UTF-8 escape round trip.
set -eu

if [ "${1:-}" != "--inside" ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  EMERALD_ROOT="${SUBLANG_EMERALD_ROOT:-$ROOT/../Emerald LLVM}"
  IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
  exec docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
    --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
    --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$ROOT,dst=/project,readonly" \
    --mount "type=bind,src=$EMERALD_ROOT,dst=/emerald,readonly" \
    --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
    -e HOME=/tmp -e EMERALD_HOME=/emerald \
    -e EMERALD_LLVM_LIB_DIR=/usr/lib -e EMERALD_LLVM_LIBRARY=LLVM \
    "$IMAGE" timeout --signal=TERM --kill-after=5s 1500s sh /project/scripts/sublang-text-sandbox.sh --inside
fi

bin=/tmp/sublang
work=/tmp/text-work
neg=$work/neg

fail() {
  echo "FAIL $*"
  exit 1
}

pass() {
  echo "PASS $*"
}

# expect_reject LABEL INPUT CODE...: text-build must exit 1 and print every CODE.
expect_reject() {
  label="$1"
  input="$2"
  shift 2
  out="$neg/$label.out"
  set +e
  "$bin" text-build "$input" "$neg/$label.wire" > "$out" 2>&1
  rc=$?
  set -e
  if [ "$rc" != 1 ]; then
    cat "$out"
    fail "$label: text-build exited $rc, expected 1"
  fi
  for code in "$@"; do
    if ! grep -F "$code" "$out" > /dev/null; then
      cat "$out"
      fail "$label: diagnostic does not contain $code"
    fi
  done
  pass "reject $label: exit 1 with $* ($(head -n 1 "$out"))"
}

rm -rf "$work"
mkdir -p "$neg"

timeout 900s /emerald/emerald-stable/emerald-compiler build /project/src/SublangMain.ems -o "$bin" \
  || fail "compile src/SublangMain.ems"
pass "compile: src/SublangMain.ems -> $bin"

timeout 600s /emerald/emerald-stable/emerald-compiler build /project/src/SublangTextSmoke.ems -o /tmp/text-smoke \
  || fail "compile src/SublangTextSmoke.ems"
timeout 60s /tmp/text-smoke || fail "in-process text checks (src/SublangTextSmoke.ems)"

# Round trip of every Wire example. Version 2 inputs must come back byte-identical. Version 1 inputs
# cannot: SublangWire.write always emits transport 2, so for them the check is that the text of the
# rebuilt Wire is identical to the text of the original.
examples=0
for f in /project/examples/wire/*.sublang-wire /project/examples/frontend/tiny/*.sublang-wire; do
  if [ ! -f "$f" ]; then
    continue
  fi
  examples=$((examples + 1))
  name=$(basename "$f" .sublang-wire)
  dump="$work/$name.txt"
  built="$work/$name.built.sublang-wire"
  "$bin" text-dump "$f" > "$dump" || fail "text-dump $name"
  "$bin" text-dump "$f" > "$work/$name.again.txt" || fail "text-dump again $name"
  cmp -s "$dump" "$work/$name.again.txt" || fail "text-dump is not deterministic for $name"
  "$bin" text-build "$dump" "$built" > "$work/$name.build.log" 2>&1 \
    || { cat "$work/$name.build.log"; fail "text-build $name"; }
  "$bin" text-dump "$built" > "$work/$name.rebuilt.txt" || fail "text-dump of rebuilt $name"
  cmp -s "$dump" "$work/$name.rebuilt.txt" || fail "$name: text changed after the Wire round trip"
  if [ "$(head -c 19 "$f")" = "12:SUBLANG-WIRE,1:2" ]; then
    cmp -s "$f" "$built" || fail "$name: rebuilt Wire is not byte-identical to the original"
    pass "round trip byte-identical: $name (transport v2)"
  else
    pass "round trip model-identical: $name (transport v1 input; the Wire writer emits v2, bytes differ)"
  fi
done
if [ "$examples" = 0 ]; then
  fail "no example Wire files found under /project/examples"
fi
if ! ls /project/examples/frontend/tiny/*.sublang-wire > /dev/null 2>&1; then
  echo "SKIP examples/frontend/tiny has no .sublang-wire output (only .tiny sources)"
fi
pass "examples: $examples Wire files, text-dump deterministic"

base="$work/arithmetic.txt"
if [ ! -f "$base" ]; then
  fail "arithmetic text is missing"
fi

# Negative inputs. Each must exit 1 with the named diagnostic.
head -n 12 "$base" > "$neg/truncated.txt"
expect_reject truncated "$neg/truncated.txt" SUBLANG-TX001

{ sed '$d' "$base"; echo 'bogus x=1'; echo 'end'; } > "$neg/unknown-record.txt"
expect_reject unknown-record "$neg/unknown-record.txt" SUBLANG-TX002

sed '/^span id=1 /p' "$base" > "$neg/duplicate-span.txt"
cmp -s "$base" "$neg/duplicate-span.txt" && fail "duplicate-span input was not changed"
expect_reject duplicate-span "$neg/duplicate-span.txt" SUBLANG-TX003

printf 'sublang-text 1 schema=1 stage=High revision=1\nmodule "bad\\q" entry=0\nend\n' > "$neg/bad-escape.txt"
expect_reject bad-escape "$neg/bad-escape.txt" "SUBLANG-TX001: line 2 column 12: invalid escape"

printf 'sublang-text 1 schema=1 stage=High revision=1\n# \303\244 not ASCII\nmodule "m" entry=0\nend\n' > "$neg/non-ascii-comment.txt"
expect_reject non-ascii-comment "$neg/non-ascii-comment.txt" "SUBLANG-TX001: line 2 column 3"

{ printf 'sublang-text 1 schema=1 stage=High revision=1\n# '; head -c 70000 /dev/zero | tr '\0' x; printf '\nend\n'; } > "$neg/long-line.txt"
expect_reject long-line "$neg/long-line.txt" "SUBLANG-TX004: line 2 column 1: line exceeds 64 KiB"

sed 's/opcode="int.add"/opcode="int.bogus"/' "$base" > "$neg/unknown-opcode.txt"
cmp -s "$base" "$neg/unknown-opcode.txt" && fail "opcode input was not changed"
expect_reject unknown-opcode "$neg/unknown-opcode.txt" SUBLANG-TX006 SUBLANG-S001

# Escapes: a NUL byte and the UTF-8 bytes of U+00E4 written as \x00 and \xC3\xA4 in a module name.
sed 's/^module "arithmetic"/module "a\\x00b\\xC3\\xA4"/' "$base" > "$work/nul.txt"
cmp -s "$base" "$work/nul.txt" && fail "escape input was not changed"
"$bin" text-build "$work/nul.txt" "$work/nul.sublang-wire" || fail "text-build of the NUL/UTF-8 module name"
"$bin" text-dump "$work/nul.sublang-wire" > "$work/nul.back.txt" || fail "text-dump of the NUL/UTF-8 module"
grep -F 'module "a\x00b\xc3\xa4" entry=' "$work/nul.back.txt" > /dev/null \
  || fail "NUL/UTF-8 module name did not round trip through Wire"
pass "escapes: \\x00 and \\xC3\\xA4 round trip through text, Wire and text"

echo "Sublang text: all checks passed"
