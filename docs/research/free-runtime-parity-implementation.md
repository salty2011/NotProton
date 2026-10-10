# Free runtime parity implementation

Implementation of the approved roadmap items 1–4, based on fork commit `e89ebd1`.
This is a local review candidate, not a declaration of CrossOver or universal game
parity. FEX and free D3D12 remain outside this release.

## Reviewable behavior

- **Portable runtime:** `runtime/package.py` assembles pinned free inputs, validates
  architecture/dependency closure, inventories files and derives the minimum OS.
  The app's bundled catalog authorizes exact archives and descriptors. Revision 2
  requires macOS 27.0.0 because of its compiled loader; the app itself targets 26+.
- **Installation lifecycle:** Install Package verifies and caches a local archive
  for offline reuse. The cache/download menu uses only approved hashes; public
  downloads require distribution-ready metadata. Staged installation registers a
  new revision beside existing tools and rolls back failed registration.
- **Migration and recovery:** With Steam and the game stopped, Prefixes → context
  menu → Change Runtime retains the old prefix, identity and game mapping before
  rebuilding. Prefix Backups can restore prefix plus selection or prefix only.
  Inherited selections snapshot the resolved engine; changed legacy aliases require
  prefix-only restoration and explicit selection. Unknown older selection records
  require explicit choice in Steam. Removal
  refuses runtimes still selected by games or the Steam default.
- **Capabilities:** `runtime/policy.json` generates the Swift, C and shell views of
  each exact runtime. Automatic selects DXMT plus the separate D9VK overlay.
  Unsupported requests fail clearly; unqualified controls say Experimental.
- **Profiles:** `runtime/game-profiles.json` generates app/helper/Steam metadata.
  The AoE adapter profile matches Steam ID, executable, actual PE architecture,
  runtime and renderer. Explicit settings win per key; unrelated config survives.
  Profile v2 is limited to the qualified Sikarugir runtime. Source revision 2 still
  fails AoE startup without the profile; a single earlier menu result with profiles
  disabled was not reproducible. Restoring the original Sikarugir prefix and runtime
  passed user-confirmed menu and level gameplay on the installed profile-v2 build.
  Profiles can be disabled/reset per game. Fallout's namespace fix stays in Wine.
- **Dependency preparation:** The stopped-prefix operation checks actual modules,
  retains a backup, runs an approved pinned method, verifies the postcondition and
  records the recipe revision. Stale receipts do not suppress missing-module
  checks. The shipping catalog is empty until a failing game proves a real need;
  fixture recipes validate installation, idempotence, failure and recovery.

## Validation and limits

The latest Swift suite passed 513 tests in 62 suites, including source-runtime
adapter-profile exclusion through the generated launcher. An additional real-archive
qualification passed 83 focused tests, including dependency-loss health detection.
Eleven Python package tests, shell/native panel and launch checks, generated-policy
checks and workflow lint passed. The signed app built successfully.

A clean local CI rehearsal built from fresh source and pinned archives, relocated
the package into a path with spaces and passed both 32/64-bit namespace and HTTPS
probes without an installed dependency application. The GitHub workflow has not
yet run remotely. Toolchain versions are recorded; byte-identical builds are not
promised. CI retains source and reports but does not publish binary candidates.

Media probe and independent patch evidence is in
[`free-runtime-media-baseline.md`](free-runtime-media-baseline.md). Both patches
remain excluded because the tested baseline already passes. Actual AoE smoothness
and Fallout's required longer-session regression still need qualification.

Public binary distribution remains gated on complete corresponding-source and
license review for selected dependency binaries, especially the pinned GStreamer
and library assembly. Current source artifacts cover Wine and NotProton integration
and explicitly record the unresolved dependency inventory. A local package passing
tests does not clear that gate.
