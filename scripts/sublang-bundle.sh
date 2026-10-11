#!/bin/bash
# Construct a full development distribution without running compiler tools on the host.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/toolchains/llvm-linux-x86_64.lock"
CACHE="$ROOT/build/toolchain-cache"
NAME="sublang-0.1-dev-llvm$LLVM_VERSION-linux-x86_64"
if [[ -e "$ROOT/dist/$NAME" || -e "$ROOT/dist/$NAME.tar.gz" ]]; then echo "Refusing to overwrite $NAME" >&2; exit 2; fi
mkdir -p "$CACHE" "$ROOT/dist"
[[ -x "$ROOT/build/sublang" ]] || { echo 'Bootstrap Sublang first.' >&2; exit 2; }
fetch() {
  local url="$1" digest="$2" file="$3" limit="$4"
  if [[ ! -f "$file" ]]; then
    curl --fail --location --retry 2 --connect-timeout 20 --max-time 900 --max-filesize "$limit" --output "$file.partial" "$url"
    printf '%s  %s\n' "$digest" "$file.partial" | sha256sum -c -
    mv -- "$file.partial" "$file"
  fi
  printf '%s  %s\n' "$digest" "$file" | sha256sum -c -
}
fetch "$LLVM_URL" "$LLVM_SHA256" "$CACHE/$LLVM_ARCHIVE" "$LLVM_BYTES"
fetch "$LLVM_LICENSE_URL" "$LLVM_LICENSE_SHA256" "$CACHE/LLVM-LICENSE.TXT" 100000
docker image inspect "$SYSROOT_IMAGE_ID" >/dev/null
STAGE="$(mktemp -d "$ROOT/dist/.llvm-bundle.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
docker run --rm --init --pull=never --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT,dst=/project,readonly" \
  --mount "type=bind,src=$CACHE,dst=/artifacts,readonly" \
  --mount "type=bind,src=$STAGE,dst=/export" \
  --tmpfs /tmp:rw,exec,nosuid,size=1073741824 -e HOME=/tmp \
  "$SYSROOT_IMAGE_ID" timeout --signal=TERM --kill-after=5s 420s bash /project/scripts/sublang-bundle-worker.sh
PKG="$STAGE/package"
{
  echo 'format=sublang-bundled-package-1'
  echo "package=$NAME"
  echo "git-commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "source-dirty=$(test -z "$(git -C "$ROOT" status --porcelain)" && echo false || echo true)"
  echo "compiler-sha256=$(sha256sum "$PKG/libexec/sublang/sublang-core" | cut -d ' ' -f1)"
  echo 'driver=bash-orchestration; compiler=Emerald'
  cat "$PKG/libexec/sublang/llvm/manifest.txt"
} > "$PKG/MANIFEST.txt"
(cd "$PKG" && find . -type l -printf '%P -> %l\n' | sort > SYMLINKS.txt)
(cd "$PKG" && find . -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 sha256sum > SHA256SUMS)
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}"
[[ "$EPOCH" =~ ^[0-9]+$ ]] || { echo 'Invalid SOURCE_DATE_EPOCH' >&2; exit 2; }
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner -C "$STAGE/clean-root" -cf "$STAGE/clean-root.tar" .
# Preserve the minimal verification rootfs separately from the distributable compiler.
mv "$STAGE/clean-root.tar" "$ROOT/build/toolchain-cache/clean-root.tar"
# Publish only after the relocated, minimal-environment compatibility bundle succeeds.
bash "$ROOT/scripts/sublang-bundle-smoke.sh" "$PKG"
mv "$PKG" "$ROOT/dist/$NAME"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner -C "$ROOT/dist" -cf - "$NAME" | gzip -n -1 > "$STAGE/$NAME.tar.gz"
mv "$STAGE/$NAME.tar.gz" "$ROOT/dist/$NAME.tar.gz"
(cd "$ROOT/dist" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "Bundled distribution: $ROOT/dist/$NAME"
