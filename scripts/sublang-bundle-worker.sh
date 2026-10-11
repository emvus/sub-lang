#!/bin/bash
# Release construction inside the pinned, networkless 6 GB sandbox only.
set -euo pipefail
export LC_ALL=C
source /project/toolchains/llvm-linux-x86_64.lock
LLVM_MAJOR="${LLVM_VERSION%%.*}"
PKG=/export/package
LLVM="$PKG/libexec/sublang/llvm"
mkdir -p "$LLVM" "$PKG/bin" "$PKG/share/sublang/licenses" "$PKG/examples"
echo 'Extracting selected LLVM tools/resources (bounded zstd window)...'
tar -I 'zstd -d --long=30' --strip-components=1 -xf "/artifacts/$LLVM_ARCHIVE" -C "$LLVM" --wildcards \
  "LLVM-$LLVM_VERSION-Linux-X64/bin/clang" "LLVM-$LLVM_VERSION-Linux-X64/bin/clang-$LLVM_MAJOR" \
  "LLVM-$LLVM_VERSION-Linux-X64/bin/opt" "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-as" \
  "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-ar" "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-link" \
  "LLVM-$LLVM_VERSION-Linux-X64/bin/llvm-profdata" "LLVM-$LLVM_VERSION-Linux-X64/bin/ld.lld" \
  "LLVM-$LLVM_VERSION-Linux-X64/bin/lld" "LLVM-$LLVM_VERSION-Linux-X64/lib/*.so*" \
  "LLVM-$LLVM_VERSION-Linux-X64/lib/clang/*"
mv "$LLVM/bin" "$LLVM/real"
mkdir "$LLVM/bin"
cp /project/build/sublang "$PKG/libexec/sublang/sublang-core"
cp /project/scripts/sublang-distribution-driver.sh "$PKG/bin/sublang"
ln -s bin/sublang "$PKG/sublang"
cp -R /project/examples/wire "$PKG/examples/wire"
cp /artifacts/LLVM-LICENSE.TXT "$PKG/share/sublang/licenses/LLVM-LICENSE.TXT"
cp /project/toolchains/llvm-linux-x86_64.lock "$PKG/share/sublang/toolchain.lock"
: > "$PKG/share/sublang/dependency-files.txt"
deps() {
  local file="$1" output library
  output="$(LD_LIBRARY_PATH="$LLVM/lib" ldd "$file")"
  if grep -q 'not found' <<< "$output"; then echo "$output" >&2; exit 1; fi
  while IFS= read -r library; do
    [[ -f "$library" ]] || continue
    if [[ "$library" != "$LLVM/lib/$(basename -- "$library")" ]]; then cp -L -- "$library" "$LLVM/lib/$(basename -- "$library")"; fi
    printf '%s\n' "$library" >> "$PKG/share/sublang/dependency-files.txt"
  done < <(awk '$2=="=>" && substr($3,1,1)=="/" {print $3} substr($1,1,1)=="/" {print $1}' <<< "$output")
}
for tool in clang opt llvm-as llvm-ar llvm-link llvm-profdata ld.lld; do deps "$LLVM/real/$tool"; done
deps "$PKG/libexec/sublang/sublang-core"
cp -L /lib64/ld-linux-x86-64.so.2 "$LLVM/lib/ld-linux-x86-64.so.2"
# Each private executable starts through the matching loader; no global LD_LIBRARY_PATH and
# no host linker/LLVM discovery. The executable basename preserves lld's driver selection.
for tool in clang opt llvm-as llvm-ar llvm-link llvm-profdata ld.lld; do
  cat > "$LLVM/bin/$tool" <<'WRAPPER'
#!/bin/bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$(basename -- "$0")"
# /proc/self/exe is the loader when invoked explicitly. Preserve the wrapper as argv[0]
# and let Clang respawn that wrapper for cc1, so children get the same private libraries.
if [[ "$NAME" = clang && "${1:-}" != -cc1 && "${1:-}" != -cc1as ]]; then set -- -no-canonical-prefixes "$@"; fi
exec "$HERE/lib/ld-linux-x86-64.so.2" --library-path "$HERE/lib" --argv0 "$HERE/bin/$NAME" "$HERE/real/$NAME" "$@"
WRAPPER
done
SYSROOT="$LLVM/sysroot"
mkdir -p "$SYSROOT/usr/lib/gcc/x86_64-pc-linux-gnu/16" "$SYSROOT/lib64"
pacman -Qlq glibc linux-api-headers | sed -n 's|^/usr/include/|usr/include/|p' > /tmp/c-headers.list
tar -C / --no-recursion -T /tmp/c-headers.list -cf - | tar -C "$SYSROOT" -xf -
for pattern in libc.so libc.so.6 libc_nonshared.a libm.so libm.so.6 libmvec.so.1 libgcc_s.so libgcc_s.so.1 libstdc++.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libresolv.so.2 libutil.so.1; do
  if [[ -f "/usr/lib/$pattern" ]]; then cp -L "/usr/lib/$pattern" "$SYSROOT/usr/lib/$pattern"; fi
done
if [[ ! -e "$SYSROOT/usr/lib/libgcc_s.so" ]]; then
  ln -s libgcc_s.so.1 "$SYSROOT/usr/lib/libgcc_s.so"
fi
for object in /usr/lib/{crt1,Scrt1,rcrt1,crti,crtn}.o; do cp "$object" "$SYSROOT/usr/lib/"; done
for object in /usr/lib/gcc/x86_64-pc-linux-gnu/16/crt*.o /usr/lib/gcc/x86_64-pc-linux-gnu/16/libgcc*.a; do
  cp "$object" "$SYSROOT/usr/lib/gcc/x86_64-pc-linux-gnu/16/"
done
cp -L /usr/lib/gcc/x86_64-pc-linux-gnu/16/libstdc++.so "$SYSROOT/usr/lib/libstdc++.so"
cp -L /usr/lib/libgcc_s.so.1 "$LLVM/lib/libgcc_s.so.1"
cp -L /usr/lib/libstdc++.so.6 "$LLVM/lib/libstdc++.so.6"
cp "$LLVM/lib/ld-linux-x86-64.so.2" "$SYSROOT/usr/lib/"
ln -s ../usr/lib/ld-linux-x86-64.so.2 "$SYSROOT/lib64/ld-linux-x86-64.so.2"
ln -s usr/lib "$SYSROOT/lib"
# Keep installed license notices and exact package versions. Source-material release obligations
# are recorded separately; this local development bundle is not published automatically.
while IFS= read -r -d '' license; do
  destination="$PKG/share/sublang/licenses/sysroot-image/${license#/usr/share/licenses/}"
  mkdir -p "$(dirname -- "$destination")"
  cp "$license" "$destination"
done < <(find /usr/share/licenses -type f -print0)
pacman -Q > "$PKG/share/sublang/sysroot-image-packages.txt"
sort -u -o "$PKG/share/sublang/dependency-files.txt" "$PKG/share/sublang/dependency-files.txt"
cat > "$LLVM/manifest.txt" <<META
format=sublang-toolchain-1
version=$LLVM_VERSION
target=x86_64-unknown-linux-gnu
resource=$LLVM_MAJOR
gcc-runtime=16
target-libc=$(getconf GNU_LIBC_VERSION)
llvm-release=$LLVM_RELEASE
llvm-sha256=$LLVM_SHA256
freeze-date=$LLVM_FREEZE_DATE
sysroot-image=$SYSROOT_IMAGE_ID
META
find "$PKG" -type d -exec chmod 0755 {} +
find "$PKG" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG/bin/sublang" "$PKG/libexec/sublang/sublang-core" "$LLVM/bin/"* "$LLVM/real/"* "$LLVM/lib/ld-linux-x86-64.so.2"
"$PKG/bin/sublang" toolchain info
# Minimal test image: ordinary shell/coreutils and their runtime closure, no LLVM, compiler,
# development headers, startup objects, Emerald or Docker client.
CLEAN=/export/clean-root
mkdir -p "$CLEAN/bin" "$CLEAN/usr/lib" "$CLEAN/lib64" "$CLEAN/tmp"
chmod 1777 "$CLEAN/tmp"
for name in bash readlink dirname basename realpath mktemp mkdir rm mv cp grep sed awk head sha256sum cut cat timeout cmp env; do
  path="$(command -v "$name")"
  cp -L "$path" "$CLEAN/bin/$name"
  while IFS= read -r library; do [[ -f "$library" ]] && cp -L "$library" "$CLEAN/usr/lib/"; done < <(ldd "$path" | awk '$2=="=>" && substr($3,1,1)=="/" {print $3} substr($1,1,1)=="/" {print $1}')
done
cp -L /lib64/ld-linux-x86-64.so.2 "$CLEAN/lib64/"
ln -s bash "$CLEAN/bin/sh"
printf 'PATH=/bin\n' > "$CLEAN/environment"
echo 'Bundled LLVM, loader, headers, startup objects and runtimes exported.'
