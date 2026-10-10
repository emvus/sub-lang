#!/usr/bin/env bash
# Smoke check for a dist/sublang-<version> directory made by scripts/sublang-package.sh.
# The packaged binary and the generated program run only inside the capped sandbox.
# The host only verifies checksums and reads the expected output constant.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
EXPECTED_OUTPUT=4242
if (($# != 1)); then
  echo 'Usage: bash scripts/sublang-package-smoke.sh dist/sublang-<version>' >&2
  exit 2
fi
if [[ ! -d "$1" ]]; then echo "Not a directory: $1" >&2; exit 2; fi
DIST="$(realpath -- "$1")"
if [[ ! -f "$DIST/sublang" || -L "$DIST/sublang" || ! -x "$DIST/sublang" ]]; then
  echo 'Missing packaged sublang binary' >&2
  exit 2
fi
test -f "$DIST/examples/wire/bond-component.sublang-wire" || { echo 'Missing examples/wire/bond-component.sublang-wire' >&2; exit 2; }
test -f "$DIST/MANIFEST.txt" || { echo 'Missing MANIFEST.txt' >&2; exit 2; }
test -f "$DIST/SHA256SUMS" || { echo 'Missing SHA256SUMS' >&2; exit 2; }
# Verify the package contents on the host before anything executes from it.
(cd "$DIST" && sha256sum -c --quiet SHA256SUMS)
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 2; }
IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE")"

# Same capped sandbox as sublang-build.sh. The package is mounted readonly and the
# sandbox has no export mount; all scratch files live in the tmpfs /tmp.
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$DIST,dst=/pkg,readonly" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp \
  "$IMAGE_ID" timeout --signal=TERM --kill-after=5s 300s sh -c '
    set -eu
    expected=$1
    mkdir /tmp/smoke
    wire=/pkg/examples/wire/bond-component.sublang-wire
    # Frontend stage: flow=on and Optimind=on, as the default wire build.
    timeout 120s /pkg/sublang emit-llvm "$wire" /tmp/smoke/program.ll on on
    test -s /tmp/smoke/program.ll
    mv /tmp/smoke/program.ll.plan /tmp/smoke/program.plan
    # Reproducibility: a second compilation of the same input must be byte-identical.
    timeout 120s /pkg/sublang emit-llvm "$wire" /tmp/smoke/second.ll on on
    cmp /tmp/smoke/program.ll /tmp/smoke/second.ll
    echo "PASS byte-identical .ll across two compilations"
    # Native steps mirror sublang-build-worker.sh for the wire frontend at -O2.
    llvm-as /tmp/smoke/program.ll -o /tmp/smoke/program.bc
    opt -passes="verify,default<O2>,verify" /tmp/smoke/program.bc -o /tmp/smoke/checked.bc
    clang -Wno-override-module -O2 /tmp/smoke/checked.bc -o /tmp/smoke/program
    actual=$(timeout 20s /tmp/smoke/program)
    test "$actual" = "$expected"
    echo "PASS packaged sublang -> LLVM -> native program = $actual"
  ' sh "$EXPECTED_OUTPUT"
echo "Package smoke passed: $DIST (output $EXPECTED_OUTPUT, .ll reproducible)"
