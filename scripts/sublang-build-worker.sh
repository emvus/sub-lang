#!/bin/sh
# Runs only inside the capped build sandbox, not as a host entry point.
set -eu
FRONTEND=$1 FLOW=$2 OPTIMIND=$3 RUN=$4 LLVM_OPT=$5 C_STANDARD=$6 SOURCE_NAME=$7
if [ "${SUBLANG_TOOLCHAIN:-sandbox}" = bundled ]; then
  WIRE_OPTIMIND=off
  if [ "$OPTIMIND" = true ]; then WIRE_OPTIMIND=on; fi
  if [ "$FRONTEND" = c ] && [ "$C_STANDARD" != c17 ]; then echo 'The bundled C frontend currently accepts C17' >&2; exit 2; fi
  set -- build "/input/$SOURCE_NAME" -o /export/program "--flow=$FLOW" "--optimind=$WIRE_OPTIMIND" "--llvm-opt=$LLVM_OPT" "--emit=${SUBLANG_EMIT:-exe}" "--lto=${SUBLANG_LTO:-off}" "--pgo=${SUBLANG_PGO:-off}"
  if [ "${SUBLANG_PGO:-off}" = use ]; then set -- "$@" --profile=/profile; fi
  if [ "$RUN" = 1 ]; then set -- "$@" --run; fi
  exec /distribution/bin/sublang "$@"
fi
mkdir /tmp/work /tmp/sublang-build
if [ "$FRONTEND" = c ]; then
  # Mount the source directory read-only so relative #include paths keep working.
  cd /input
  timeout 120s clang -std="$C_STANDARD" -O"$LLVM_OPT" -S -emit-llvm \
    "/input/$SOURCE_NAME" -o /tmp/sublang-build/program.ll
  {
    printf 'frontend: Clang C (%s)\n' "$C_STANDARD"
    clang --version | head -n 1
    printf 'pipeline: C -> Clang LLVM IR -> LLVM verifier/optimizer -> native\n'
    printf 'llvm: -O%s; C arithmetic, ABI and malloc/free semantics preserved\n' "$LLVM_OPT"
    printf 'optimind: unavailable for LLVM-imported C; requested=%s; no Sublang High-IR pass executed\n' "$OPTIMIND"
    printf 'flow: inactive; requested=%s; C memory management retained\n' "$FLOW"
    printf 'integration: no Sublang C effect/alias/escape summary importer yet; no Flow ownership proof\n'
  } > /tmp/sublang-build/program.plan
elif [ "$FRONTEND" = wire ]; then
  # This path has no Emerald toolchain mount and never builds a frontend driver.
  WIRE_OPTIMIND=off
  if [ "$OPTIMIND" = true ]; then WIRE_OPTIMIND=on; fi
  timeout 120s /project/build/sublang emit-llvm /input/SublangProgram.ems /tmp/sublang-build/program.ll "$FLOW" "$WIRE_OPTIMIND"
  mv /tmp/sublang-build/program.ll.plan /tmp/sublang-build/program.plan
elif [ "$FRONTEND" = builder ]; then
  cp /input/SublangProgram.ems /tmp/work/SublangProgram.ems
  ln -s /project/src/sublang /tmp/work/sublang
  printf '%s\n' 'use sublang::backend::SublangBuild;' 'use SublangProgram;' \
    "main() { SublangBuild.emit(SublangProgram.build(), $OPTIMIND, \"$FLOW\"); }" > /tmp/work/SublangRunner.ems
  timeout 180s /emerald/emerald-stable/emerald-compiler build /tmp/work/SublangRunner.ems -o /tmp/sublang-build/driver
  timeout 30s /tmp/sublang-build/driver
else
  echo 'Invalid internal frontend' >&2; exit 2
fi
test -s /tmp/sublang-build/program.ll
llvm-as /tmp/sublang-build/program.ll -o /tmp/sublang-build/program.bc
# verify is explicit at both boundaries; LLVM passes are separate from Optimind.
if [ "$LLVM_OPT" = 0 ]; then
  opt -passes=verify /tmp/sublang-build/program.bc -o /tmp/sublang-build/checked.bc
else
  opt -passes="verify,default<O$LLVM_OPT>,verify" /tmp/sublang-build/program.bc -o /tmp/sublang-build/checked.bc
fi
B=/tmp/sublang-build
EMIT=${SUBLANG_EMIT:-exe}; LTO=${SUBLANG_LTO:-off}; PGO=${SUBLANG_PGO:-off}
# Exceptions need the Itanium unwinder/personality runtime that ships with libstdc++.
EH=""
if grep -q "__gxx_personality_v0" $B/program.ll; then EH="-lstdc++"; fi
LTOFLAG=""
case "$LTO" in full) LTOFLAG=-flto ;; thin) LTOFLAG=-flto=thin ;; off) ;; *) echo 'Invalid LTO mode' >&2; exit 2 ;; esac
cp $B/program.ll /export/program.ll
cp $B/checked.bc /export/program.bc
cp $B/program.plan /export/program.plan
# Identity a profile is bound to: the exact IR text plus the toolchain and options that consume it.
IR_HASH=$(sha256sum $B/program.ll | cut -d" " -f1)
CLANG_ID=$(clang --version | head -n 1)
TARGET_ID=$(clang -dumpmachine)
case "$PGO" in
  off) ;;
  train)
    clang -Wno-override-module -O"$LLVM_OPT" -fprofile-generate $B/checked.bc $EH -o $B/instrumented
    LLVM_PROFILE_FILE=$B/train.profraw timeout 20s $B/instrumented > /dev/null
    llvm-profdata merge -o /export/program.profdata $B/train.profraw
    printf 'ir-sha256=%s\nclang=%s\ntarget=%s\nllvm-opt=%s\n' "$IR_HASH" "$CLANG_ID" "$TARGET_ID" "$LLVM_OPT" > /export/program.profmeta
    ;;
  use)
    for field in ir-sha256="$IR_HASH" clang="$CLANG_ID" target="$TARGET_ID" llvm-opt="$LLVM_OPT"; do
      grep -qxF -- "$field" /profile/program.profmeta || { echo "SUBLANG-PGO001: profile does not match this program or toolchain: ${field%%=*}" >&2; exit 3; }
    done
    LTOFLAG="$LTOFLAG -fprofile-use=/profile/program.profdata"
    ;;
  *) echo 'Invalid PGO mode' >&2; exit 2 ;;
esac
case "$EMIT" in
  ll) ;;
  bc) ;;
  obj)
    clang -Wno-override-module -O"$LLVM_OPT" $LTOFLAG -c $B/checked.bc -o $B/program.o
    cp $B/program.o /export/program.o
    ;;
  exe)
    clang -Wno-override-module -O"$LLVM_OPT" $LTOFLAG $B/checked.bc $EH -o $B/program
    if [ "$RUN" = 1 ]; then timeout 20s $B/program; fi
    cp $B/program /export/program
    ;;
  *) echo 'Invalid emit mode' >&2; exit 2 ;;
esac
{
  printf 'emit=%s\nlto=%s\npgo=%s\nllvm-opt=%s\n' "$EMIT" "$LTO" "$PGO" "$LLVM_OPT"
  printf 'ir-sha256=%s\nclang=%s\ntarget=%s\neh-runtime=%s\n' "$IR_HASH" "$CLANG_ID" "$TARGET_ID" "${EH:-none}"
} > /export/program.config
