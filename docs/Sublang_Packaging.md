# Sublang packaging and reproducibility

This document covers the release artifact produced from an existing standalone
`build/sublang` binary, its manifest, the runtime assumptions it records, and the
package smoke check. It is the first slice of roadmap section 1 ("Binary packaging
and reproducibility"). It does not provide a multi-platform release or a package
manager.

## Three distinct phases

Each phase has its own script, sandbox run and failure domain. Do not merge them.

| Phase | Command | What runs where | Output |
| --- | --- | --- | --- |
| 1. Compiler bootstrap | `bash scripts/sublang-bootstrap.sh` | Emerald toolchain mounted readonly, one capped sandbox run | `build/sublang` |
| 2. IR compilation | `bash scripts/sublang-build.sh input.sublang-wire -o build/program --flow=on` | Capped sandbox; runs the Sublang binary, then LLVM tools and clang | `build/program.ll`, `.bc`, `.plan` |
| 3. Generated-program execution | `--run` on the build, or the package smoke check | Capped sandbox; runs only the native program | stdout of the program |

Packaging (`scripts/sublang-package.sh`) consumes phase 1 output only. It never
bootstraps and never mounts Emerald. The package smoke check
(`scripts/sublang-package-smoke.sh`) exercises phases 2 and 3 against the packaged
binary. The Emerald toolchain is not needed by any packaged artifact.

## Build a package

```sh
bash scripts/sublang-bootstrap.sh          # phase 1, once
bash scripts/sublang-package.sh            # creates dist/sublang-<version>/ and .tar.gz
bash scripts/sublang-package-smoke.sh dist/sublang-<version>
```

`<version>` is taken from the output of `sublang --version` (currently `0.1-dev`).
The packaging script refuses to overwrite an existing `dist/sublang-<version>/` or
archive; remove it first.

Environment:

- `SUBLANG_SANDBOX_IMAGE`: sandbox image reference (default `emerald-selfhost-sandbox`).
  Its immutable ID is recorded, and that ID is what the sandbox runs.
- `SOURCE_DATE_EPOCH`: integer timestamp for every file mtime and the archive. Defaults
  to the committer time of `HEAD`.

## Package layout

```text
dist/sublang-<version>/
  sublang                 packaged binary (mode 0755)
  examples/wire/          Wire inputs copied from the repository
  MANIFEST.txt            provenance, toolchain probes, assumptions, sorted file list
  SHA256SUMS              SHA-256 of every file above, including MANIFEST.txt
dist/sublang-<version>.tar.gz
dist/sublang-<version>.tar.gz.sha256
```

The archive is created with:

```sh
tar --sort=name --mtime=@$SOURCE_DATE_EPOCH --owner=0 --group=0 --numeric-owner ... | gzip -n
```

Modes are normalized (directories 0755, files 0644, `sublang` 0755), and all mtimes
are set to `SOURCE_DATE_EPOCH`. Given the same binary, inputs and epoch, the archive
bytes should not change between runs. This has not yet been proven on two hosts.

## Manifest contents

- `sublang-version`: output of `sublang --version`, probed inside the sandbox.
- `sublang-sha256`: SHA-256 of the binary as probed in the sandbox. The packaging
  script refuses to continue if the copied binary differs.
- `sublang-linkage`: `ldd` output for the binary, probed inside the sandbox.
- `clang`, `llvm-as`, `opt`: first version lines, probed inside the sandbox.
- `glibc`: `getconf GNU_LIBC_VERSION` inside the sandbox image.
- `arch`: `uname -m` inside the sandbox image.
- `sandbox-image-ref` and `sandbox-image-id`: the image reference and its ID.
- `sandbox-limits`: the hardening flags used for every sandbox run.
- `git-commit`: `git rev-parse HEAD`.
- `git-dirty`: `true` when `git status --porcelain` is nonempty. A dirty package is
  still produced, but the flag must be read as "this archive does not match a clean
  commit".
- `source-date-epoch`: the timestamp used for mtimes.
- `files`: the sorted payload list (MANIFEST.txt itself is listed in SHA256SUMS only).

Versions are recorded, not enforced. Nothing in the packaging step rejects a
different LLVM or clang; comparing the manifest with the release pin is a reviewer
step until a pin file is defined.

## Runtime assumptions

- `sublang` is expected to link dynamically against the host C library. The
  `sublang-linkage` line records what was actually observed.
- The `sublang` binary emits LLVM IR text (`sublang emit-llvm`). It does not launch
  clang or LLVM tools. Native programs need `llvm-as`, `opt` and `clang` on the
  consumer's system, at versions compatible with the recorded ones.
- The link step is a plain `clang` link with the default C library. The emitted `.ll`
  is self-contained: the backend smoke test and the package smoke check link it
  without a Sublang runtime library.
- The consumer's glibc must be at least the recorded build glibc for dynamic linking
  to succeed.
- No Emerald toolchain or Emerald runtime is needed to run a packaged binary.

## Package smoke check

`scripts/sublang-package-smoke.sh dist/sublang-<version>` does the following:

1. Verifies `SHA256SUMS` on the host. Nothing runs before this succeeds.
2. In the capped sandbox, with the package mounted readonly, compiles
   `examples/wire/bond-component.sublang-wire` with `flow=on` and Optimind on.
3. Compiles the same input a second time and checks that the two `.ll` files are
   byte-identical.
4. Runs `llvm-as`, `opt -passes="verify,default<O2>,verify"` and
   `clang -Wno-override-module -O2`, the same steps as `sublang-build-worker.sh`,
   then runs the native program with a 20-second limit.
5. Asserts that stdout is `4242`.

The check uses the same docker hardening flags as the build sandbox: no network,
readonly root and package, `--cap-drop=ALL`, `no-new-privileges`, a 6,000,000,000-byte
memory and swap cap, two CPUs, 128 pids, no core dumps, and a tmpfs `/tmp`.

## Limits

- Single platform: the target is the Linux host and sandbox image that produced the
  build. The recorded `arch` is informational; no other architecture or OS is built
  or tested.
- No package manager: there is no install step, dependency resolution, update channel
  or uninstall. Users unpack the archive and run `sublang` from it.
- Integrity only: `SHA256SUMS` detects corruption and mismatched copies. It is not a
  signature, and it does not prove who produced the archive.
- The binary is not proven reproducible. The archive is deterministic for a given
  binary; whether the Emerald-built binary is bit-identical across builds is a
  separate question for the bootstrap phase.
- The sandbox image is pinned by its local image ID only. The packaging step does not
  check the image's contents or provenance.
- `dist/` is not listed in `.gitignore`. Add it before committing a package tree.
- The smoke check covers one representative program (`bond-component`, expected `4242`).
  It does not cover the rest of `examples/wire` or the backend suite in
  `sublang-backend-sandbox.sh`.
- Phase 1 (bootstrap) remains the only step that uses Emerald; releases are built from
  an already bootstrapped tree.
