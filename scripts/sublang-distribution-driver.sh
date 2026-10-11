#!/bin/bash
# Installed as bin/sublang. Orchestration only; the compiler core remains Emerald.
set -euo pipefail
export LC_ALL=C
SCRIPT="$(readlink -f -- "${BASH_SOURCE[0]}")"
ROOT="$(cd -- "$(dirname -- "$SCRIPT")/.." && pwd)"
TOOLS="$ROOT/libexec/sublang/llvm"
CORE="$ROOT/libexec/sublang/sublang-core"
PINNED_VERSION="$(awk -F= '$1=="LLVM_VERSION" {print $2}' "$ROOT/share/sublang/toolchain.lock")"
[[ "$PINNED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'SUBLANG-TC001: invalid release lock' >&2; exit 2; }
ORIGIN=bundled
fail() { echo "SUBLANG-TC001: $*" >&2; exit 2; }
core() { "$ROOT/libexec/sublang/llvm/lib/ld-linux-x86-64.so.2" --library-path "$ROOT/libexec/sublang/llvm/lib" "$CORE" "$@"; }
field() { awk -F= -v key="$1" '$1==key {n++; value=substr($0,length(key)+2)} END {if(n!=1) exit 1; print value}' "$TOOLS/manifest.txt"; }
validate() {
  [[ -f "$TOOLS/manifest.txt" ]] || fail 'missing toolchain manifest; reinstall the complete bundle'
  [[ "$(field format)" = sublang-toolchain-1 && "$(field version)" = "$PINNED_VERSION" ]] || fail "unsupported toolchain format/version; expected $PINNED_VERSION"
  [[ "$(field target)" = x86_64-unknown-linux-gnu ]] || fail 'unsupported toolchain target'
  for name in clang opt llvm-as llvm-ar llvm-link llvm-profdata ld.lld; do
    [[ -x "$TOOLS/bin/$name" ]] || fail "missing tool: $name"
    version="$("$TOOLS/bin/$name" --version)" || fail "cannot execute $name"
    observed="$(sed -nE 's/.*(LLVM version|clang version|LLD) ([0-9]+[.][0-9]+[.][0-9]+).*/\2/p' <<< "$version" | head -n 1)"
    [[ "$observed" = "$PINNED_VERSION" ]] || fail "incompatible $name; expected $PINNED_VERSION"
  done
  RESOURCE="$(field resource)"; GCC="$(field gcc-runtime)"
  [[ "$RESOURCE" = "${PINNED_VERSION%%.*}" && "$GCC" =~ ^[0-9]+$ ]] || fail 'invalid resource/runtime selection'
  [[ -f "$TOOLS/lib/clang/$RESOURCE/include/stddef.h" && -f "$TOOLS/sysroot/usr/include/stdio.h" ]] || fail 'missing Clang resources or C headers'
  [[ -f "$TOOLS/sysroot/usr/lib/Scrt1.o" && -f "$TOOLS/sysroot/usr/lib/libc.so" ]] || fail 'missing target startup objects or libc'
}
if (($# == 2)) && [[ "$1" = toolchain && "$2" = info ]]; then
  validate
  cat "$TOOLS/manifest.txt"
  printf 'root=%s\norigin=bundled\n' "$TOOLS"
  exit 0
fi
if (($# == 1)) && [[ "$1" = capabilities ]]; then
  core "$@"
  printf 'driver.commands=build,toolchain\ntoolchain.origin=bundled\ntoolchain.version=%s\n' "$PINNED_VERSION"
  exit 0
fi
if (($# == 0)) || [[ "$1" != build ]]; then core "$@"; exit $?; fi
shift
INPUT= OUTPUT= FLOW=auto OPTIMIND=on LEVEL=2 EMIT=exe LTO=off PGO=off PROFILE= RUN=0
while (($#)); do
  case "$1" in
    -o|--output) (($# >= 2)) || fail 'missing output'; OUTPUT="$2"; shift 2 ;;
    --flow=*) FLOW="${1#*=}"; shift ;;
    --optimind=*) OPTIMIND="${1#*=}"; shift ;;
    --llvm-opt=*) LEVEL="${1#*=}"; shift ;;
    --emit=*) EMIT="${1#*=}"; shift ;;
    --lto=*) LTO="${1#*=}"; shift ;;
    --pgo=*) PGO="${1#*=}"; shift ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --toolchain=bundled) shift ;;
    --toolchain-root=*) TOOLS="$(realpath -- "${1#*=}")"; ORIGIN=explicit; shift ;;
    --run) RUN=1; shift ;;
    --help|-h) echo 'Usage: sublang build input.sublang-wire|input.c -o program [--flow=auto|on|off] [--optimind=on|off] [--llvm-opt=0|1|2|3] [--emit=exe|obj|bc|ll] [--lto=off|full|thin] [--pgo=off|train|use --profile=DIR] [--toolchain-root=DIR] [--run]'; exit 0 ;;
    -*) fail "unknown build option: $1" ;;
    *) [[ -z "$INPUT" ]] || fail 'only one input is supported'; INPUT="$1"; shift ;;
  esac
done
[[ -n "$INPUT" && -f "$INPUT" && -n "$OUTPUT" ]] || fail 'supply an input file and -o output'
case "$FLOW" in auto|on|off) ;; *) fail 'invalid Flow mode' ;; esac
case "$OPTIMIND" in on|off) ;; *) fail 'invalid Optimind mode' ;; esac
case "$LEVEL" in 0|1|2|3) ;; *) fail 'invalid LLVM optimization level' ;; esac
case "$EMIT" in exe|obj|bc|ll) ;; *) fail 'invalid output mode' ;; esac
case "$LTO" in off|full|thin) ;; *) fail 'invalid LTO mode' ;; esac
case "$PGO" in off|train|use) ;; *) fail 'invalid PGO mode' ;; esac
[[ "$RUN" = 0 || "$EMIT" = exe ]] || fail '--run requires --emit=exe'
validate
INPUT="$(realpath -- "$INPUT")"; OUTPUT="$(realpath -m -- "$OUTPUT")"
[[ ! -d "$OUTPUT" ]] || fail 'output is a directory'
mkdir -p -- "$(dirname -- "$OUTPUT")"
WORK="$(mktemp -d "$(dirname -- "$OUTPUT")/.sublang-native.XXXXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
SYSROOT="$TOOLS/sysroot"
CLANG=("$TOOLS/bin/clang" "--target=x86_64-unknown-linux-gnu" "--sysroot=$SYSROOT" "--gcc-install-dir=$SYSROOT/usr/lib/gcc/x86_64-pc-linux-gnu/$GCC" "-resource-dir=$TOOLS/lib/clang/$RESOURCE" "--ld-path=$TOOLS/bin/ld.lld" -Wno-override-module "-O$LEVEL")
case "$INPUT" in
  *.sublang-wire)
    core emit-llvm "$INPUT" "$WORK/program.ll" "$FLOW" "$OPTIMIND"
    mv -- "$WORK/program.ll.plan" "$WORK/program.plan"
    ;;
  *.c)
    [[ "$FLOW" != on ]] || { echo 'SUBLANG-C001: C ownership import is not implemented; --flow=on is unsupported' >&2; exit 2; }
    "${CLANG[@]}" -std=c17 -S -emit-llvm "$INPUT" -o "$WORK/program.ll"
    printf 'frontend: C17\nflow: inactive; C malloc/free semantics retained\noptimind: unavailable for C; LLVM optimization only\n' > "$WORK/program.plan"
    ;;
  *) fail 'expected .sublang-wire or .c input' ;;
esac
"$TOOLS/bin/llvm-as" "$WORK/program.ll" -o "$WORK/input.bc"
PASSES=verify
if [[ "$LEVEL" != 0 ]]; then PASSES="verify,default<O$LEVEL>,verify"; fi
"$TOOLS/bin/opt" "-passes=$PASSES" "$WORK/input.bc" -o "$WORK/program.bc"
FLAGS=() EH=()
case "$LTO" in full) FLAGS+=(-flto=full) ;; thin) FLAGS+=(-flto=thin) ;; esac
if grep -q __gxx_personality_v0 "$WORK/program.ll"; then EH+=(-lstdc++); fi
IR_HASH="$(sha256sum "$WORK/program.ll" | cut -d ' ' -f1)"
TC_HASH="$(sha256sum "$TOOLS/manifest.txt" | cut -d ' ' -f1)"
printf -v META 'ir-sha256=%s\ntoolchain-sha256=%s\nllvm-opt=%s\nlto=%s' "$IR_HASH" "$TC_HASH" "$LEVEL" "$LTO"
if [[ "$PGO" = train ]]; then
  "${CLANG[@]}" "${FLAGS[@]}" -fprofile-generate "$WORK/program.bc" "${EH[@]}" -o "$WORK/train"
  LLVM_PROFILE_FILE="$WORK/train.profraw" "$TOOLS/lib/ld-linux-x86-64.so.2" --library-path "$TOOLS/lib:$SYSROOT/usr/lib" "$WORK/train" >/dev/null
  "$TOOLS/bin/llvm-profdata" merge "$WORK/train.profraw" -o "$WORK/program.profdata"
  printf '%s\n' "$META" > "$WORK/program.profmeta"
elif [[ "$PGO" = use ]]; then
  [[ -f "$PROFILE/program.profdata" && -f "$PROFILE/program.profmeta" ]] || fail 'missing profile data/metadata'
  [[ "$(cat "$PROFILE/program.profmeta")" = "$META" ]] || { echo 'SUBLANG-PGO001: profile does not match the IR/toolchain/options' >&2; exit 2; }
  FLAGS+=("-fprofile-use=$(realpath -- "$PROFILE/program.profdata")")
fi
SUFFIX=
case "$EMIT" in
  exe) "${CLANG[@]}" "${FLAGS[@]}" "$WORK/program.bc" "${EH[@]}" -o "$WORK/program" ;;
  obj) "${CLANG[@]}" "${FLAGS[@]}" -c "$WORK/program.bc" -o "$WORK/program.o"; SUFFIX=.o ;;
esac
if [[ "$RUN" = 1 ]]; then "$TOOLS/lib/ld-linux-x86-64.so.2" --library-path "$TOOLS/lib:$SYSROOT/usr/lib" "$WORK/program"; fi
printf 'toolchain.origin=%s\ntoolchain.version=%s\ntoolchain.sha256=%s\ntarget=x86_64-unknown-linux-gnu\nllvm-opt=%s\nflow=%s\noptimind=%s\nlto=%s\npgo=%s\nemit=%s\n' "$ORIGIN" "$PINNED_VERSION" "$TC_HASH" "$LEVEL" "$FLOW" "$OPTIMIND" "$LTO" "$PGO" "$EMIT" > "$WORK/program.config"
ARTIFACTS=(.ll .bc .plan .config)
if [[ "$PGO" = train ]]; then ARTIFACTS+=(.profdata .profmeta); fi
if [[ "$EMIT" = exe || "$EMIT" = obj ]]; then ARTIFACTS+=("$SUFFIX"); fi
for suffix in "${ARTIFACTS[@]}"; do [[ -f "$WORK/program$suffix" ]] || fail "missing artifact: $suffix"; done
for suffix in "${ARTIFACTS[@]}"; do mv -f -- "$WORK/program$suffix" "$OUTPUT$suffix"; done
