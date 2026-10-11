# Bundled LLVM toolchain distribution

Status: product policy, October 11, 2026. A Linux x86-64 implementation now exists in
[Bundled LLVM](Sublang_Bundled_LLVM.md): pinned LLVM tools, private loader/libraries, C sysroot,
relocatable Bash orchestration and a minimal-environment compatibility check. Native Emerald
process orchestration, other platforms, signed releases and corresponding-source publication
remain open. This policy describes the full release target, not a claim that every item is done.

## 1. User-facing requirement

An ordinary user installs **one Sublang distribution** and can compile/link supported inputs without separately installing Emerald, LLVM, Clang, LLD, development packages or Docker.

A distribution may contain multiple internal executables/libraries. One download/install is the requirement; pretending that a compiler driver plus its libraries are literally one executable is unnecessary.

The supported OS/architecture and minimum OS runtime remain explicit. Normal OS facilities may be prerequisites. A target needing an unavailable SDK/sysroot is not fully self-contained and must be reported as such.

Development/release verification still uses the capped sandbox. Docker is not intended as a normal end-user prerequisite of the completed distribution.

## 2. Actual starting point

The legacy thin package contains a standalone Wire-to-LLVM compiler and examples and depends
on external LLVM tools. The optional full bundle selects and validates its own pinned tools;
development launchers retain an explicitly separate legacy sandbox-toolchain path.

The Linux full bundle addresses toolchain payload and offline compilation. Its Bash driver is
not the planned native Emerald driver, and broader release/target requirements remain open.

Do not interrupt/rewrite the concurrent IR/pass/Flow work to claim bundling is finished. Integrate this work at the toolchain/build/runtime boundary.

## 3. Product policy

- Ship a coherent, pinned LLVM release toolchain inside each supported Sublang package.
- Use the bundled toolchain by default, resolved relative to the installed distribution rather than the working directory.
- Do not silently select arbitrary tools from PATH or mix bundled libraries with system tools.
- Permit explicit system/custom-toolchain selection for advanced users after validation.
- Ordinary compilation works offline after installation; do not fetch missing components in the build path.
- Package updates replace a complete compiler/toolchain set atomically. Preserve the prior install until the new set validates.
- A system Clang executable is not proof that opt, llvm-as, linkers, libraries, runtimes or matching versions are available.

## 4. LLVM version policy

For each ordinary Sublang release, evaluate and integrate the **latest stable upstream LLVM release available at that release's toolchain freeze**, including current stable patch fixes. Development snapshots/RCs are opt-in preview channels, not the default stable distribution.

Pin the exact version, upstream source revision/artifact digest and packaging configuration. Do not resolve a floating latest URL at user compile time. The next Sublang release should move to the newest stable release and rerun the bounded compatibility gates.

If the newest stable LLVM is incompatible, the ordinary release gate is not satisfied. Fix the adapter or explicitly postpone that release. A separately labeled compatibility/security exception must document the reason and bundled version; do not silently advertise newest-LLVM support on an older package.

Support for a bundled version and support for newer external LLVM are separate claims. Reject unverified external combinations or label experimental support explicitly. Bitcode, pass pipelines, opaque pointers, intrinsics, EH and instrumentation can change across versions.

Record both the stable LLVM version evaluated at freeze and the version actually shipped, including any exception. Do not hard-code the current latest version in this plan; determine it from upstream release information when producing an artifact.

## 5. Minimum payload and proposed layout

Names below are a proposed distribution layout, not existing paths:

```text
sublang/
  bin/sublang
  libexec/sublang/llvm/bin/
    clang
    opt
    llvm-as
    llvm-ar
    lld / ld.lld / platform-specific linker entry
  libexec/sublang/llvm/lib/
    required shared libraries
    clang/<version>/include/ and target runtime resources as applicable
  lib/sublang/
    supported Sublang runtime components
  share/sublang/
    toolchain-manifest.json
    licenses/
    examples/
  sysroots/<target>/       only supported, legally redistributable target material
```

Include only tools used by advertised capabilities. llvm-dis/llvm-link, profiling tools, compiler-rt, unwind libraries, C++ runtime libraries and other components are included when required by enabled debugging, multi-module, PGO, sanitizer or EH paths.

Clang is required for the advertised C frontend and can initially drive native linking. If native builds use Clang, its resource directory, compatible linker/runtime discovery and dynamic library closure must work after relocation.

For the existing host-libc target, inventory startup objects, libc headers/libraries and target system runtime requirements. Bundling opt/clang alone does not remove development-package dependencies. Ship a supported redistributable sysroot or state/restrict the target accordingly.

OS-provided SDKs, such as platform-specific Apple/Windows material, have separate availability and licensing constraints. Do not claim a fully bundled target until its complete supported toolchain is distributable and tested.

## 6. Driver and discovery

Add a native build orchestration command to Sublang, so ordinary users do not need repository shell scripts or manual llvm-as/opt/clang calls. Keep IR-to-LLVM emission available independently.

Suggested CLI, subject to consistency with the current command model:

```text
sublang build input.sublang-wire -o program
sublang toolchain info
sublang build input.sublang-wire --toolchain=bundled
sublang build input.sublang-wire --toolchain=system
sublang build input.sublang-wire --toolchain-root=/explicit/path
```

The full Linux bundle implements `build`, `toolchain info`, bundled selection and an explicit
complete `--toolchain-root`. PATH-based `--toolchain=system` remains proposed and unsupported.

The driver must:
1. Locate its actual install root without depending on the current working directory.
2. Resolve its complete default toolchain by absolute paths.
3. Validate version/capability/target compatibility before invocation.
4. Pass argv as arguments rather than interpolating input paths into shell commands.
5. Capture precise diagnostics/exit status and publish output only after success.
6. Preserve separate compiler, optimizer, linker and optional run phases.
7. Support paths with spaces, Unicode and relocation.
8. Report effective toolchain origin/version/target in capabilities and build artifacts.

Do not require llvm-config merely to validate an end-user package if the driver only needs the shipped executables. If LLVM APIs are later linked in process, validate that distinct library/ABI contract too.

Existing sandbox scripts should use the same selected toolchain logic rather than define a second version policy. Compiler/generated-program runs during development remain under the existing 6 GB, no-swap, networkless cap.

## 7. External toolchains

Explicit system mode discovers the entire required set, validates versions/configuration and runs a small compatibility probe. A matching version string alone does not establish usable codegen/linking.

Check required pass/intrinsic support, target backend, linker, Clang resources, runtime/sysroot and dynamic dependencies. Fail with a diagnostic naming the missing/mismatched component.

Do not silently combine opt from one LLVM major, Clang from another and an arbitrary libLLVM from a third. Supported mixed patch/component configurations require specific evidence; default to a coherent pinned build.

A detected external toolchain can be offered as an option, but must not automatically replace the known bundled default simply because Clang exists.

## 8. Release construction, provenance and redistribution

Use LLVM's distribution-component build/install mechanism to produce a minimal coherent payload. Source builds may be release-infrastructure work; do not compile LLVM unbounded on the user's PC.

The current user sandbox constraint remains in force for local builds. If LLVM cannot be built within it, use a suitable verified prebuilt artifact or separately provisioned release infrastructure rather than exceeding the cap.

Record:
- Sublang commit/version, exact LLVM version/revision and artifact/source hashes.
- Build flags, selected projects/targets/components and runtime ABI.
- Minimum host OS/runtime and supported target triples/sysroots.
- Tool/library dependency inventory, license/notices and source provenance.
- Hashes of packaged files, compiler/runtime resource paths and capability list.
- Profile/bitcode compatibility identifiers relevant to PGO/LTO.

Preserve LLVM Apache-2.0 WITH LLVM-exception notices and all other applicable bundled component notices. Redistributed system runtimes/sysroots have their own licenses. Checksums establish integrity, not publisher identity; signed release manifests/artifacts are a separate distribution hardening task.

Never copy unrelated executables from a developer's machine without provenance and dependency/license inspection.

## 9. Focused acceptance gates

One coherent release bundle should establish:
- Compile/link a representative Wire program with system LLVM/Clang unavailable.
- Compile the advertised C example without undeclared development-package dependencies.
- Verify all required bundled libraries/resources/sysroots are present.
- Move the install directory to a path containing spaces and repeat the build.
- Preserve existing Flow-off/on results, checked failure behavior and Bond cleanup under the candidate LLVM release.
- Reject a deliberately incompatible explicit external toolchain with a useful diagnostic.
- Build/run offline without Emerald or Docker as a product dependency; development verification may still execute inside the prescribed sandbox.
- Verify enabled LTO/PGO/EH components when those capabilities are actually shipped.
- Record compiler/optimization/link/run costs separately; do not claim performance from a version bump.

Keep this focused on distribution/LLVM boundaries. Do not duplicate every frontend test. A compiler artifact without working native linking is not a complete bundled-toolchain release.

## 10. Implementation order and reporting

1. Inventory/pin the current working toolchain and its dependencies.
2. Add the install-relative resolver and explicit external override.
3. Add native build orchestration using argument-safe subprocess invocation.
4. Package the required LLVM tools/libraries/resources and supported target sysroot.
5. Run the clean-environment/relocation/offline compatibility bundle.
6. Integrate the newest-stable LLVM release gate with packaging and capability reporting.

The implementation and its exact acceptance evidence are recorded separately in
[Bundled LLVM](Sublang_Bundled_LLVM.md); the remaining policy items must not be inferred from
the existence of a Linux development archive.

## Upstream references

- [Building LLVM with CMake](https://llvm.org/docs/CMake.html): LLVM_DISTRIBUTION_COMPONENTS and project/runtime configuration.
- [Clang toolchain components](https://clang.llvm.org/docs/Toolchain.html): codegen, linking, runtimes and target dependencies.
- [LLVM release index](https://releases.llvm.org/): stable-release selection at artifact freeze.
- [LLVM developer/license policy](https://llvm.org/docs/DeveloperPolicy.html): redistribution licensing and exceptions.
