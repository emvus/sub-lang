#!/bin/sh
# Runs only inside the capped build sandbox, not as a host entry point.
set -eu
FRONTEND=$1 FLOW=$2 OPTIMIND=$3 RUN=$4 LLVM_OPT=$5 C_STANDARD=$6 SOURCE_NAME=$7
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
clang -Wno-override-module -O"$LLVM_OPT" /tmp/sublang-build/checked.bc -o /tmp/sublang-build/program
if [ "$RUN" = 1 ]; then timeout 20s /tmp/sublang-build/program; fi
cp /tmp/sublang-build/program /export/program
cp /tmp/sublang-build/program.ll /export/program.ll
cp /tmp/sublang-build/checked.bc /export/program.bc
cp /tmp/sublang-build/program.plan /export/program.plan
