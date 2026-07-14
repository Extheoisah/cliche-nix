# AGENTS.md

Guidance for coding agents working on this repository.

## Project overview

This repository is a Nix flake for building the `cliche` command-line
application from <https://github.com/nbd-wtf/cliche> as a GraalVM native image.
The resulting binary is intended to be a Nix-built binary, not a fully portable
or fully self-contained Linux binary.

The flake pins upstream projects and tools as inputs:

- `cliche`: upstream application source.
- `immortan`: Lightning/wallet library used by cliche.
- `graal`: Gluon GraalVM Java 11 distribution with native-image support.
- `sbt`: SBT 1.6.2 distribution.
- `nixpkgs`: package set used for build tools and libraries.

Primary build command:

```sh
nix build .
```

Expected result:

```text
result/bin/cliche
```

A dependency-cache package is also exposed as `.#deps`. It is a fixed-output
derivation used to populate and freeze SBT/Ivy/Coursier caches so the final
build can reuse them.

## Repository layout

```text
flake.nix       Main build definition.
flake.lock      Locked upstream inputs.
checkpoints/    Replacement Immortan electrum checkpoint JSON files.
AGENTS.md       Agent guidance.
```

Checkpoint files:

```text
checkpoints/checkpoints_mainnet.json
checkpoints/checkpoints_testnet.json
```

During the build these are copied into Immortan at:

```text
src/main/resources/electrum/checkpoints_mainnet.json
src/main/resources/electrum/checkpoints_testnet.json
```

## Flake structure

The flake currently defines packages for `x86_64-linux` only.

Important helpers in `flake.nix`:

- `setupTools`: unpacks/patchelfs GraalVM and SBT, sets `JAVA_HOME`,
  `GRAALVM_HOME`, `PATH`, `HOME`, `COURSIER_CACHE`, and `SBT_OPTS`.
- `patchCliche`: removes unsupported native-image serialization config and
  ensures required testnet resources are included in cliche's native-image
  resource config.
- `patchImmortanCheckpoints`: installs this repository's checkpoint files into
  the Immortan source tree before publishing Immortan locally.
- `sbtDeps`: fixed-output derivation that warms/captures SBT, Ivy, and
  Coursier caches.
- `default`: final derivation that builds `sbt nativeImage` and installs the
  resulting binary.

Immortan is published locally in both `sbtDeps` and `default`. If you patch
Immortan before `sbt publishLocal`, apply the patch in both places unless there
is a deliberate reason not to.

## Fixed-output SBT dependency cache

`sbtDeps` uses a fixed-output hash:

```nix
outputHashMode = "recursive";
outputHashAlgo = "sha256";
outputHash = "...";
```

If dependency resolution, locally published artifacts, or cache contents change,
Nix may report a hash mismatch.

Typical workflow:

1. Run `nix build .#deps` or `nix build .`.
2. If Nix reports a fixed-output hash mismatch, verify the change is expected.
3. Copy the reported `got:` hash into `sbtDeps.outputHash`.
4. Rebuild.

Do not update the hash blindly.

## Checkpoint files and flakes

The `checkpoints/` files must be tracked by git. Nix flakes copy the tracked git
source into the store; untracked files are omitted.

If a build fails with a missing path like:

```text
/nix/store/...-source/checkpoints/checkpoints_mainnet.json
```

then the checkpoint files are probably untracked. Stage or commit them:

```sh
git add checkpoints/checkpoints_mainnet.json \
        checkpoints/checkpoints_testnet.json \
        flake.nix
```

## Portability policy

This project intentionally builds a Nix-based binary. Do not add static-linking,
JNI-replacement, AppImage, `nix bundle`, or portable tarball logic unless the
user explicitly asks for it.

Known facts:

- The native image may contain `/nix/store/...` dynamic linker and library
  references.
- That is acceptable for this repository's current goal.
- ACINQ secp256k1 is loaded through the JVM/JNI dependency stack used by
  cliche/Immortan.
- Previous attempts to force a fully static binary required invasive JNI and
  linker changes and were intentionally removed.

If asked about running on non-Nix systems, explain that the current artifact is
not designed for that. Suggested alternatives can include installing Nix on the
target, using `nix run`, `nix profile install`, `nix copy`, or designing a
separate portable packaging effort.

## Build and validation commands

On a system with Nix installed:

```sh
nix flake check --no-build
nix build .#deps
nix build .
./result/bin/cliche --help
```

For dependency inspection when needed:

```sh
ldd result/bin/cliche
readelf -d result/bin/cliche
```

In minimal coding-agent environments, `nix`, `ldd`, `file`, or `readelf` may be
unavailable. If validation cannot be performed locally, say so clearly.

## Coding guidelines

- Keep `flake.nix` as the source of truth.
- Preserve reproducibility. Avoid network access in non-fixed-output final
  derivations.
- Keep SBT/Ivy/Coursier state under `$HOME`/`$COURSIER_CACHE` as configured by
  `setupTools`.
- When adding files referenced by the flake, ensure they are tracked by git.
- Prefer small, focused changes. The flake has multiple interacting build
  phases.
- If changing dependency inputs, update `flake.lock` with `nix flake lock` or
  `nix flake lock --update-input ...`.
- Do not reintroduce static Graal/native-image options such as `--static`,
  static secp256k1 builds, or custom JNI loader shims without explicit user
  direction.

## Commit message style

Use concise conventional commit messages:

```text
type: short imperative title

Body wrapped at about 72 columns. Explain what changed and why.
```

Example:

```text
build: patch immortan checkpoints

Add mainnet and testnet checkpoint files to the flake source.

Copy them into Immortan's electrum resources before publishing
Immortan for both dependency caching and the final cliche build.
```

## Common failure modes

### Missing checkpoint files in `/nix/store/...-source`

Cause: checkpoint files are untracked by git.

Fix: `git add checkpoints/ flake.nix` and rebuild.

### Fixed-output hash mismatch for `cliche-sbt-deps`

Cause: SBT dependency/cache contents changed.

Fix: verify the change is expected, then update `sbtDeps.outputHash` to the
hash Nix reports.

### Binary does not run on a non-Nix system

Cause: this project builds a Nix-based native binary and may depend on Nix store
paths.

Fix: run it in a Nix environment or start a separate portable packaging effort.
Do not silently change the flake to pursue full static portability.
