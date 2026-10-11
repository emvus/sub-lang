# Bundled LLVM distribution

The Linux x86-64 development distribution includes a pinned LLVM toolchain and a C sysroot.
The compiler core remains the Emerald-built Sublang binary. A Bash driver orchestrates the
separate LLVM processes without requiring Emerald or Docker on an end user's machine.
The native Emerald process driver remains a separate implementation task.

Development status (October 11, 2026): payload extraction and relocated tool-version checks
have passed. The isolated end-to-end gate found a missing `libgcc_s.so` linker entry in the
sysroot. Construction now supplies that entry, but its corrected payload and the remaining
native-build, LTO, PGO and sanitizer checks still need a successful acceptance run. This
source snapshot is not an accepted binary release.

## Build and use

Release construction:

```sh
bash scripts/sublang-bootstrap.sh
bash scripts/sublang-package.sh --with-llvm
bash scripts/sublang-bundle-smoke.sh dist/sublang-0.1-dev-llvm23.1.3-linux-x86_64
```

The first construction downloads the official archive into the on-disk
`build/toolchain-cache/`, validates its pinned SHA-256 and constructs the bundle inside the
6,000,000,000-byte, networkless sandbox. Subsequent construction uses the verified cache.
Compilation after installation never downloads components.

After unpacking, the package's entry point provides:

```sh
./sublang toolchain info
./sublang build examples/wire/bond-component.sublang-wire -o program --flow=on
./sublang build source.c -o program
./sublang build input.sublang-wire -o program --lto=thin
./sublang build input.sublang-wire -o profiles/program --pgo=train
./sublang build input.sublang-wire -o program --pgo=use --profile=profiles
```

`--emit=exe|obj|bc|ll`, `--llvm-opt=0|1|2|3`, `--optimind=on|off`, `--flow=auto|on|off`
and `--run` are supported. A C input uses C17; High IR Optimind and HyperAlloc Flow do not
apply to that path. `--flow=on` for C is rejected. Emerald builder inputs are development-only.

For this user's development environment, execute these commands only through the sandbox:

```sh
bash scripts/sublang-build.sh examples/wire/bond-component.sublang-wire \
  -o build/bundled-program --toolchain=bundled --flow=on --run
```

`SUBLANG_BUNDLE_ROOT` selects a different complete distribution for that development launcher.
Its legacy `--toolchain=sandbox` path is retained and remains the development launcher's default;
it is not the installed package's default. The installed package always selects its own LLVM.

## Payload and dependency resolution

```text
sublang -> bin/sublang
bin/sublang                            build/process driver
libexec/sublang/sublang-core            Emerald-built compiler
libexec/sublang/llvm/bin/               private tool launchers
libexec/sublang/llvm/real/              upstream LLVM executables
libexec/sublang/llvm/lib/               private shared libraries and matching ELF loader
libexec/sublang/llvm/lib/clang/23/       Clang headers, compiler-rt, PGO and sanitizer resources
libexec/sublang/llvm/sysroot/           C headers, startup objects and runtime/link libraries
libexec/sublang/llvm/manifest.txt       effective target/version/provenance
share/sublang/toolchain.lock           release construction pin
share/sublang/licenses/                upstream and installed-image license texts
share/sublang/sysroot-image-packages.txt
examples/wire/
MANIFEST.txt
SHA256SUMS
```

Every tool is addressed relative to the resolved installation directory. The private ELF loader
starts tools and the compiler against their matching libraries; no global `LD_LIBRARY_PATH`
is installed. Clang receives explicit target, sysroot, GCC runtime directory, resource directory
and LLD path. An installed system Clang cannot silently replace any component.

`--toolchain-root=DIR` explicitly selects another complete LLVM subtree with the same pinned
version, supported target, resources and manifest. Missing or mismatched components fail with
`SUBLANG-TC001`. Arbitrary PATH-based system discovery is not implemented.

Inputs and output paths are passed as argv elements, including spaces and Unicode. Builds use
an isolated temporary directory; the executable is published only after successful compilation,
linking and any requested run. Sidecars contain LLVM IR, checked/optimized bitcode, the memory
plan and effective build options. PGO reuse requires matching IR, toolchain manifest, LLVM level
and LTO mode. PGO training executes the actual input program and can have its normal side effects.

## Platform and release boundary

The current pin is LLVM **23.1.3**, evaluated at the October 11, 2026 freeze. The archive URL,
SHA-256 and pinned sysroot image ID are in `toolchains/llvm-linux-x86_64.lock`. Upgrade the lock,
resource selection and compatibility evidence together for the next stable release; ordinary
builds never resolve a floating `latest` URL. See the [distribution policy](Sublang_Toolchain_Distribution.md).

This is a Linux x86-64 package requiring the ordinary OS shell/coreutils facilities (Bash and
GNU utilities). Other targets and operating systems are not advertised. The current C target
is glibc 2.44 with GCC 16 runtime components, taken from the pinned sandbox image.
Generated executables use the normal OS interpreter path and require a compatible target
libc/runtime when distributed independently. `--run` uses the bundled loader and libraries.
Relocating the compiler bundle does not embed its old install path into an ordinary executable.
This is not an older-glibc portability guarantee or a cross-compilation SDK.

The bundle records installed-image package versions and includes license texts. Before public
redistribution, provide/review corresponding source material and notices for the exact bundled
LGPL/GPL runtime packages, including distribution patches. SHA-256 pins provide integrity, not
a signed Sublang release or upstream signature/attestation verification. No public upload is
performed by these scripts. Signing, source-material publication and CI release automation
remain release work.

## Compatibility check

`scripts/sublang-bundle-smoke.sh` imports a temporary minimal test image containing shell and
coreutils runtimes only. It contains no LLVM, development headers/startup objects, Emerald or
Docker client. The package is mounted readonly at a relocated path containing spaces and Unicode;
all compilation and execution remain inside the 6 GB/no-extra-swap, networkless sandbox.

The single bundle checks existing ownership/region/collection/Bond examples with Flow off/on,
integer overflow, exception linking, C17 with system and local headers, full/Thin LTO, PGO,
incompatible-toolchain rejection and focused Bond cleanup under ASan/LSan. The temporary test
image is removed afterward. This is compatibility evidence, not a speed or memory benchmark.
