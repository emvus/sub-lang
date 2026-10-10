#!/usr/bin/env bash
# Packages an already built build/sublang into dist/sublang-<version>/ and a
# deterministic dist/sublang-<version>.tar.gz. This script never bootstraps: run
# scripts/sublang-bootstrap.sh first. The binary is executed only inside the capped
# sandbox; the host copies, hashes and archives files, and never runs sublang itself.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SUBLANG_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
BINARY="$ROOT/build/sublang"
WIRE_DIR="$ROOT/examples/wire"
if [[ ! -f "$BINARY" || -L "$BINARY" || ! -x "$BINARY" ]]; then
  echo 'Missing build/sublang: run bash scripts/sublang-bootstrap.sh first (this script never bootstraps)' >&2
  exit 2
fi
test -d "$WIRE_DIR" || { echo 'Missing examples/wire' >&2; exit 2; }
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 2; }
git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null || { echo 'Packaging requires a git commit' >&2; exit 2; }
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}"
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || { echo 'SOURCE_DATE_EPOCH must be a non-negative integer' >&2; exit 2; }
export SOURCE_DATE_EPOCH
# Pin the exact image that is inspected by running its immutable ID.
IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE")"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/dist/.package.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT

# Toolchain and binary probes run inside the capped sandbox. Only /export is writable.
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
  -e HOME=/tmp \
  "$IMAGE_ID" timeout --signal=TERM --kill-after=5s 120s sh -c '
    set -eu
    test -x /project/build/sublang
    {
      printf "sublang-version=%s\n" "$(timeout 10s /project/build/sublang --version)"
      printf "sublang-sha256=%s\n" "$(sha256sum /project/build/sublang | cut -d " " -f 1)"
      printf "sublang-linkage=%s\n" "$(ldd /project/build/sublang 2>&1 | tr "\n" " ")"
      printf "clang=%s\n" "$(clang --version | head -n 1)"
      printf "llvm-as=%s\n" "$(llvm-as --version | grep -m 1 "LLVM version")"
      printf "opt=%s\n" "$(opt --version | grep -m 1 "LLVM version")"
      printf "glibc=%s\n" "$(getconf GNU_LIBC_VERSION)"
      printf "arch=%s\n" "$(uname -m)"
    } > /export/toolchain.txt
  '
test -f "$STAGE/toolchain.txt" && test ! -L "$STAGE/toolchain.txt"
field() { grep -m 1 "^$1=" "$STAGE/toolchain.txt" | cut -d= -f2- || true; }
SUBLANG_VERSION_LINE="$(field sublang-version)"
SUBLANG_VERSION="$(printf '%s\n' "$SUBLANG_VERSION_LINE" | sed -n 's/^Sublang \([^;]*\);.*/\1/p')"
if [[ ! "$SUBLANG_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Cannot derive a safe package version from: $SUBLANG_VERSION_LINE" >&2
  exit 1
fi
SANDBOX_SHA="$(field sublang-sha256)"
PKG_NAME="sublang-$SUBLANG_VERSION"
DIST_DIR="$ROOT/dist/$PKG_NAME"
if [[ -e "$DIST_DIR" || -e "$ROOT/dist/$PKG_NAME.tar.gz" ]]; then
  echo "$PKG_NAME already exists in dist/; remove it first" >&2
  exit 2
fi

PKG="$STAGE/$PKG_NAME"
mkdir -p "$PKG/examples"
cp -- "$BINARY" "$PKG/sublang"
cp -R -- "$WIRE_DIR" "$PKG/examples/wire"
test "$(sha256sum "$PKG/sublang" | cut -d ' ' -f 1)" = "$SANDBOX_SHA" || {
  echo 'Packaged binary differs from the binary probed in the sandbox' >&2
  exit 1
}

# Normalize modes so the archive does not depend on the host umask.
find "$PKG" -type d -exec chmod 0755 {} +
find "$PKG" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG/sublang"

GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then GIT_DIRTY=true; else GIT_DIRTY=false; fi

# MANIFEST.txt lists payload files; SHA256SUMS covers the payload and MANIFEST.txt.
{
  echo 'format=sublang-package-manifest-1'
  echo "package=$PKG_NAME"
  echo "git-commit=$GIT_COMMIT"
  echo "git-dirty=$GIT_DIRTY"
  echo "source-date-epoch=$SOURCE_DATE_EPOCH"
  echo "sandbox-image-ref=$IMAGE"
  echo "sandbox-image-id=$IMAGE_ID"
  echo 'sandbox-limits=--network=none --read-only --cap-drop=ALL --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 --cpus=2 --pids-limit=128 --ulimit core=0'
  echo '# probed inside the sandbox (never on the host):'
  cat "$STAGE/toolchain.txt"
  echo '# runtime assumptions:'
  echo '  - sublang is expected to link dynamically against the host C library (see sublang-linkage)'
  echo '  - sublang emits LLVM IR text only; no Emerald toolchain or Emerald runtime is needed to run it'
  echo '  - native programs are made by the consumer with llvm-as, opt and clang (versions above); the link step uses clang default libc linkage'
  echo '  - generated .ll is self-contained; no Sublang runtime library is shipped'
  echo 'files:'
  (cd "$PKG" && find . -type f ! -name MANIFEST.txt -printf '%P\n' | sort | sed 's/^/  /')
} > "$PKG/MANIFEST.txt"
(cd "$PKG" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs -r -d '\n' sha256sum) > "$PKG/SHA256SUMS"

# Deterministic timestamps and ordering for every entry, then a fixed-order archive.
find "$PKG" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -cf - "$PKG_NAME" | gzip -n > "$STAGE/$PKG_NAME.tar.gz"
(cd "$STAGE" && sha256sum "$PKG_NAME.tar.gz" > "$PKG_NAME.tar.gz.sha256")

mv -- "$PKG" "$DIST_DIR"
mv -- "$STAGE/$PKG_NAME.tar.gz" "$ROOT/dist/$PKG_NAME.tar.gz"
mv -- "$STAGE/$PKG_NAME.tar.gz.sha256" "$ROOT/dist/$PKG_NAME.tar.gz.sha256"
(cd "$DIST_DIR" && sha256sum -c --quiet SHA256SUMS)
(cd "$ROOT/dist" && sha256sum -c --quiet "$PKG_NAME.tar.gz.sha256")
echo "Packaged $DIST_DIR (archive: dist/$PKG_NAME.tar.gz, sha256: dist/$PKG_NAME.tar.gz.sha256)"
