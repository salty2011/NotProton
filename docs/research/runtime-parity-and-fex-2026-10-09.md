# Free runtime parity and FEX feasibility

Research date: 9 October 2026. Initial audit and proposal, followed by the
implementation results recorded at the end of this document.

## Conclusion

Our Sikarugir runner already uses the same NotProton Steam integration as the CrossOver runner. The remaining work is primarily runtime quality, renderer coverage, application profiles, and validation across games. Matching CrossOver requires a maintained stack of compatible components and targeted patches; adding another Wine binary alone is insufficient.

Keep the working Sikarugir/Rosetta runner as the baseline. Evaluate existing media and synchronization fixes, make settings reflect the selected runner's capabilities, and build a small, documented compatibility-profile system. Develop FEX as a separate experimental ARM runner, with separate prefixes and an explicit signing/provisioning path. Reuse available native Wine/FEX work rather than porting the standalone Linux FEX application.

## Scope and evidence

- Audited fork: `salty2011/NotProton`, branch `codex/free-sikarugir-runner`, commit `57f19beb481c82f5880418e7a8cd42cde211292d`.
- Installed application remains our **1.1.2** review build. This research did not replace it or modify game prefixes.
- Latest upstream checked: **1.1.3**, commit `859359449fbc2f8b544b363518dd9ae9f52d0908`. Its changes since our 1.1.2 base concern recognizing the Chinese CrossOver 26.3 rebuild, with its alternate hashes, and related tests. Our branch has **not** been rebased to 1.1.3 during this audit. [Upstream release](https://github.com/NotProtonNot/NotProton/releases/tag/v1.1.3), [exact upstream comparison](https://github.com/NotProtonNot/NotProton/compare/caeb7ff...859359449fbc2f8b544b363518dd9ae9f52d0908).
- Inspected the installed Sikarugir runtime and the installed x86 CrossOver runtime. The CrossOver ARM preview was assessed through NotProton's implementation and primary project sources, not a local gameplay comparison.
- Age of Empires: Definitive Edition is playable with normal gameplay audio. Startup video **and** audio stutter remain unresolved. Existing observations establish neither general game compatibility nor performance parity with CrossOver. [Our recorded scope](../../README.md).

External project reports below are identified as such. Their benchmarks and fixes have not been reproduced in our runner.

## What NotProton itself adds

These features are principally shared integration, rather than benefits exclusive to paid Wine:

| Feature | What the author implements | Free runner status |
| --- | --- | --- |
| Native macOS Steam Play | Steam hooks enable compatibility-tool discovery, Windows installation and launch paths, and the compatibility UI. | Shared. |
| Windows-to-native Steam bridge | Valve-derived `lsteamclient`, Windows client DLLs and a `steam.exe` shim connect Windows software to native Steam. | Shared; our x86 and x64 client-pipe probes passed in prior validation. |
| Wine loader integration | Build-specific `ntdll` detours redirect Steam-client loading into the bridge; loader signing enables necessary injection. | Implemented for the pinned Sikarugir build. |
| Dependency and legacy Steam support | Stages bridge payloads and older Steam components rather than requiring an entire Windows Steam installation. | Shared. Steam's install scripts can still install game dependencies. |
| Launcher discovery | The Steam shim populates Windows Steam registry paths, including the Ubisoft Connect fix. | Shared. |
| Prefix performance and lifecycle | APFS template cloning, locks, update checks, save/profile layout, rebuilds and backups. | Shared. |
| Controllers | Steam Input bridge plus hiding physical devices from Wine's hidraw path when appropriate; raw-controller opt-out. | Shared implementation; broad controller validation still needed. |
| macOS presentation | Per-game application bundles, icons, focus behavior and Game Mode eligibility; overlay shim handles Metal/HDR presentation differences. | Shared infrastructure; renderer-specific overlay behavior needs validation. |
| Settings and launch options | Shell-style `%command%`, renderer variables, MSync, Retina, AVX advertisement and upscaling controls. | Shared UI, but capabilities are not yet accurately filtered for the free runner. |

Implementation evidence: [Steam hooks](https://github.com/salty2011/NotProton/tree/57f19beb481c82f5880418e7a8cd42cde211292d/dylib/hooks), [runner patcher](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/app/Sources/NotProtonApp/Model/RunnerPatcher.swift), [Steam shim](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/steam-shim/steam.cpp), [prefix rebuild](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/app/Sources/NotProtonApp/Model/PrefixRebuild.swift), [controller bridge](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/lsteamclient/unix_steam_input_manual.cpp), [overlay shim](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/overlay-shim/overlay_shim.m), [settings panel](https://github.com/salty2011/NotProton/blob/57f19beb481c82f5880418e7a8cd42cde211292d/dylib/feats/webpatch.c).

The `ntdll` patches provide Steam integration. They do not import every Proton Wine patch, media enhancement or game fix. Likewise, exposing a settings toggle does not establish that the selected runner implements it. [Detour implementation](https://github.com/salty2011/NotProton/tree/57f19beb481c82f5880418e7a8cd42cde211292d/ntdll-patch).

## What CrossOver adds beyond Wine, and how we compare

### Patched Wine and host integration

CrossOver maintains fixes to Windows APIs, Mac window/input behavior, synchronization and application compatibility, alongside its release testing. Its changelog documents launcher and game fixes as well as component updates. Sharing Wine 11 as a base does not prove two engines have the same patch set. [CrossOver changelog](https://www.codeweavers.com/crossover/changelog).

Our installed engine reports `wine sikarugir 11.0 (revision 1)`. Binary inspection confirms Sikarugir-specific startup/renderer handling and `WINEMSYNC` support. It is already a customized macOS runtime, not bare Wine. However, I did not establish a complete source-revision/patch manifest corresponding to `WS12WineSikarugir11.0_1.tar.xz`; the public Wine mirror alone does not establish that correspondence. Therefore, **an exact CrossOver-versus-Sikarugir patch delta remains unverified**. [Engine releases](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0), [Wine mirror](https://github.com/Sikarugir-App/wine), [our pinned installer](../../app/Sources/NotProtonApp/Model/SikarugirInstaller.swift).

Where an important missing patch cannot be obtained in the packaged engine, a reproducible source build is possible. CodeWeavers publishes CrossOver 26.3's FOSS source, and Highball provides an existing LGPL Wine build recipe based on that source. This is an option to reuse and assess, not a reason to replace our working engine immediately. It also does not make the complete CrossOver product freely redistributable. [CodeWeavers source release](https://www.codeweavers.com/crossover/source), [Highball engine recipe](https://github.com/gauthierpiarrette/highball-engine).

### Graphics and performance

| Layer | CrossOver path | Our installed free path | Remaining requirement |
| --- | --- | --- | --- |
| Direct3D 10/11 to Metal | DXMT, alongside other choices. | DXMT `v0.80-244-g7c8dee1`. | Test graphics correctness, video surfaces, frame pacing and settings; newer does not guarantee better in every title. |
| Direct3D 9/10/11 to Vulkan | DXVK and Vulkan-on-Metal libraries. | DXVK-Sikarugir async 1.10.3, D9VK 2.3, MoltenVK 1.4.1; D3D9 DLLs isolated from DXMT. | Evaluate a newer complete driver/renderer pairing rather than updating DLLs independently. |
| Older graphics fallback | WineD3D and Wine's legacy graphics support. | WineD3D; no separate CNC-DDRAW/D8VK installation in our assembler. | Add those only for demonstrated older-game needs. |
| Direct3D 12 | D3DMetal on the relevant Rosetta path; ARM preview support has separate limitations. | No supported D3D12 backend installed. | A separate graphics project or optional Apple component. |
| Upscaling/NVIDIA API adaptation | Renderer-specific MetalFX/NVAPI integration. | DXMT's `nvapi64.dll` is present and upstream controls are exposed. | Verify functionality and show only supported controls. |
| Fast synchronization | MSync on macOS. | Present; NotProton defaults it off unless selected/persisted for a game. | Validate correctness and long-session stability, then enable through tested profiles. |

Installed versions were read from the runner's `version` and renderer `version` files, and its component inventory. Assembly and health checks are in [SikarugirInstaller](../../app/Sources/NotProtonApp/Model/SikarugirInstaller.swift); launch choices and MSync defaults are in [compat_run.sh](../../dylib/feats/compat_run.sh). DXMT's supported API scope is documented by [DXMT upstream](https://github.com/3Shain/dxmt).

Our earlier hardware probe rejected the template's DXVK 3.1.1/MoltenVK pairing because required Vulkan features were missing. DXVK has requirements beyond a driver advertising a Vulkan version. [DXVK driver requirements](https://github.com/doitsujin/dxvk/wiki/Driver-support).

**KosmicKrisp is worth evaluating** as another free Vulkan-to-Metal driver: Mesa documents it as conformant and based on Metal 4/macOS 26+, and Sikarugir publishes build tooling. A modern DXVK + KosmicKrisp pairing, and eventually vkd3d-proton for D3D12, are candidates. We have not verified the required feature set, presentation, correctness or performance of these combinations. Vulkan conformance alone does not establish D3D12 game support. [Mesa driver documentation](https://docs.mesa3d.org/drivers/kosmickrisp.html), [Sikarugir build tooling](https://github.com/Sikarugir-App/mesa-kosmickrisp), [vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton).

GPTK is **not required for our DXMT/DXVK path**. Apple's D3DMetal is a distinct, closed-source component with its own terms. An optional user-installed D3DMetal route would be a different decision from a fully open graphics stack; it must not be treated as another freely replaceable DLL. [Sikarugir's component/renderer description](https://github.com/Sikarugir-App/Sikarugir), [Apple Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/).

One specific upstream CrossOver fix sets `CX_APPLEGPTK_LIBD3DSHARED_PATH` when its bundled library exists, for Rosetta Windows thread-state initialization even when D3DMetal is not selected. We inherit the conditional code, but our free engine has no such library. Its presence is not evidence that all Wine games need GPTK; equivalent functionality must be established against the free engine and an actual failing case. [Exact upstream fix](https://github.com/NotProtonNot/NotProton/commit/5f2562012238ff1300acabb4c8fffae194298a01), [our conditional setup](../../dylib/feats/compat_run.sh).

### Audio, video and additional Windows libraries

Both installed runtimes include Wine Mono **10.4.1** and Wine Gecko **2.47.4**. Our free stack also includes GStreamer and its codec plugins; it does not simply lack a media framework. Earlier Media Foundation probes decoded the startup media, and audio-only playback was continuous. With the full video path, playback stuttered and the captured audio contained gaps. The current diagnosis remains a delivery/timing problem to investigate, not proven codec corruption. [Recorded validation scope](../../README.md), [media dependency setup](../../app/Sources/NotProtonApp/Model/SikarugirInstaller.swift).

Three existing source-level candidates merit controlled evaluation:

- **CoreAudio I/O buffer sizing:** Highball reports eliminating dropouts in one title by limiting the output callback's buffer relative to the client period. This could address an audio starvation symptom; it does not establish the cause of our simultaneous video stutter. [Published patch and reproduction](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/patches/0015-winecoreaudio-io-buffer-under-half-a-period.patch).
- **Media Foundation sample allocation:** an existing Proton-derived patch lets the video processor allocate suitable samples/textures for a DXGI device manager. A candidate for video-surface compatibility, rather than a proven AoE fix. [Published patch](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/patches/0010-mfreadwrite-video-processor-sample-allocator.patch).
- **MSync registration cleanup:** a published fix addresses growing server registrations and memory use after an early-return race. Establish whether our exact engine contains the problem before enabling MSync more widely. [Published patch](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/patches/0014-msync-unregister-early-return.patch).

Mono is not a universal substitute for native .NET. Games may also require particular Microsoft runtime, font or media installations. Use Steam's existing install scripts first and narrowly scoped recipes where they are insufficient; do not install every Winetricks verb into every prefix. CrossOver's installer profiles also select dependencies for particular applications. [CrossOver install-profile documentation](https://codeweavers.helpjuice.com/en_US/user-guides/crossover-mac-user-guide).

### Application profiles

CrossOver's installer recipes and runtime compatibility database are separate mechanisms. NotProton invokes the cloned Wine loader directly; it does not run CrossOver's installer assistant for every Steam game. The paid runtime can still load its `cxcompatdb.so`; NotProton sets `CX_HOME` to the user's CrossOver directory, and this machine has `compatdb-26.dat` there. Our free runtime has no `cxcompatdb.so`. Merely passing the same environment variable does not provide the same database. [NotProton launcher](../../dylib/feats/compat_run.sh), [CrossOver application setup](https://codeweavers.helpjuice.com/en_US/user-guides/crossover-mac-user-guide).

We should implement the useful behavior through documented, reusable profiles, without assuming CrossOver's database can be copied. Suggested fields: Steam ID, executable, runner/version constraints, renderer, environment variables, DLL overrides, registry changes, dependency recipe, reason, source and verification results. User settings should override defaults, and every applied profile should be visible in the log.

Our AoE adapter-ID workaround belongs in such a profile. It is intentionally scoped to app **1017900**, whereas the GStreamer path restoration, shared MoltenVK fix and bridge work apply more broadly. [Current AoE handling](../../dylib/feats/compat_run.sh).

## FEX: feasible architecture and available work

The intended free path is:

**x86/x64 Windows game → FEX WoW64/ARM64EC modules → native ARM Wine → native macOS graphics/media libraries.**

FEX handles CPU instructions. Wine provides Windows behavior, and DXMT/DXVK provide graphics translation. FEX's Wine modules avoid a Linux x86 root filesystem and can call native host libraries. This differs from running the standalone FEX Linux application. [FEX ARM64EC design/build documentation](https://wiki.fex-emu.com/index.php/Development:ARM64EC).

FEX is not inherently unable to emulate AVX on Apple hardware: its project documents a 128-bit implementation rather than an absolute dependency on 256-bit SVE2. The recent Wine integration also includes paired native Unix libraries, so copying Windows translator DLLs alone is insufficient. [FEX 2607 development notes](https://fex-emu.com/FEX-2607/). Latest release checked: **FEX-2610**, 7 October 2026; use a mutually compatible pinned component set, not the newest DLL mixed with an older adapter. [FEX-2610 release](https://github.com/FEX-Emu/FEX/releases/tag/FEX-2610).

NotProton already has ARM-side infrastructure: FEX tool variants, ARM prefix identification, an ARM Unix `lsteamclient`, and ARM/x86/x64 detour definitions. Sikarugir's current installed engine contains only `x86_64-unix`, so none of that turns it into native ARM Wine automatically. [Supported runners](../../app/Sources/NotProtonApp/Model/SupportedRunner.swift), [ntdll patches](../../app/Sources/NotProtonApp/Model/NtdllPatcher.swift), [bridge build](../../lsteamclient/build.sh).

### Reuse candidates

| Project | Useful work | Limitation |
| --- | --- | --- |
| Highball engine | Public ARM Wine build workflow, pinned Wine 11.18/toolchain inputs, Hangover-distributed FEX 2608 modules and a Darwin UnixLib adapter. | Its ARM line does not yet package DXMT graphics or media; depends on a properly entitled loader. Reported compute tests are not game performance evidence. |
| `gzimbric/wine-arm64-macos` | Experimental Wine 11.17-based Darwin loader, x18/memory/surface work and Steam-related changes; developer reports FEX/DXMT gameplay. | Source only. External FEX/DXMT integration is not fully published/reproducible; JIT and synchronization correctness need further work. |
| DXMT upstream | ARM64EC/ARM64X cross-build configuration already exists. | Still needs native host pieces and a compatible Wine Mac driver surface interface. Our x86 renderer package is not the native ARM solution. |
| CrossOver ARM preview | Demonstrates the architecture and informs compatibility requirements. | Paid runtime; copying its loader or proprietary components is not our free distribution plan. |

Sources: [Highball ARM workflow](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/.github/workflows/build-arm64.yml), [its input manifest](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/inputs-arm64.json), [Darwin FEX adapter](https://github.com/gauthierpiarrette/highball-engine/blob/ac5cc83bb7d90b8fcca8e60a4a37fce2b9ee1d81/fex/fexunixlib_darwin.cpp), [experimental Wine status](https://github.com/gzimbric/wine-arm64-macos/blob/21c45a2c3bb32e5b2a1ed92d72be6f2e6e3e72f6/docs/macos-arm64/README.md), [external integration requirements](https://github.com/gzimbric/wine-arm64-macos/blob/21c45a2c3bb32e5b2a1ed92d72be6f2e6e3e72f6/docs/macos-arm64/BUILD.md), [DXMT ARM configuration](https://github.com/3Shain/dxmt/blob/7c8dee1c2d73415301ceb7d1fa810861cef4cd67/build-arm64ec.txt), [CodeWeavers ARM preview description](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac).

### Apple support and signing are the first gate

Native ARM Wine needs Windows-compatible low-address mapping, page behavior, the Windows x18 thread-register convention, and correct memory ordering. CodeWeavers' Wine developer describes Apple's newer support and the restricted cross-architecture entitlement. He identifies paid and free-account variants, but a reply reports difficulty obtaining the free-account capability. A free-account route is therefore **not verified for us**. Ordinary ad-hoc/JIT signing is insufficient. [Wine developer's technical explanation and account-access discussion](https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/).

Local SDK inspection confirms `os_cross_arch_is_supported()` is available from macOS 26.6, with a warning that a positive result establishes kernel facilities, not a functioning installed translator. This machine reports macOS **27.2**, SDK **27.0**; the OS is not obviously below the native-preview requirement, but entitlement/provisioning still needs proof. Local sources: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/os/arch/arm64.h`, `spawn.h`, and `mach/mach_traps.h`.

Our existing patcher preserves CrossOver loaders with the managed restricted entitlement instead of re-signing them. A free provisioned loader must also retain its required signature/profile throughout cloning, launch and repair. The patcher currently recognizes only the managed entitlement string; supporting an unmanaged variant would require an explicit audit. [RunnerPatcher](../../app/Sources/NotProtonApp/Model/RunnerPatcher.swift).

The controlled prototype should keep SIP enabled and use an independently provisioned loader. If that cannot be obtained, report that gate instead of presenting FEX as ready or making disabling OS protections the normal setup.

### Recommended prototype sequence

1. Prove our own signed ARM loader can launch, use the required memory layout, and enable hardware TSO on **every** emulation thread. Test from a relocated bundle too.
2. Reuse a pinned ARM Wine/FEX/Darwin-adapter recipe in a separate managed runner. Run native ARM, x64 and 32-bit Windows fixtures, exceptions/APCs, child processes, memory-protection changes, self-modifying code and threading tests.
3. Rebuild/validate the ARM Unix Steam bridge against this exact runtime. Prefer a narrowly scoped source-level Wine bridge hook when building from source, or otherwise add verified detours for the exact binaries. Do not transplant CrossOver offsets.
4. Add native ARM/ARM64EC DXMT and its Mac driver surface integration, then controller/overlay tests. Build or package ARM media dependencies too. A Rosetta library cannot be loaded into the ARM host process.
5. Register a separate **Free ARM/FEX** tool alongside Sikarugir/Rosetta. Use separate prefixes/templates and the existing backup/rebuild mechanisms for migration; do not run the current valuable prefix through both architectures.
6. Compare matched workloads: startup video, frame-time distribution, gameplay, long-session memory use and power. Retain Rosetta fallback. FEX may reduce translated Wine overhead but does not guarantee higher FPS or solve GPU/media bottlenecks.

These are proposed acceptance steps, not work completed in this research. Supporting evidence: [native integration requirements](https://github.com/gzimbric/wine-arm64-macos/blob/21c45a2c3bb32e5b2a1ed92d72be6f2e6e3e72f6/docs/macos-arm64/BUILD.md), [architecture-specific prefix guard](../../dylib/feats/compat_run.sh), [bridge ABI/build coupling](../../bridge/setup-wine-tree.sh).

## Proposed order for our fork

1. **Bring the branch to upstream 1.1.3 before implementation resumes.** Preserve the fork-only push policy and run the focused checks affected by the small rebase.
2. **Make runner capabilities explicit.** Filter D3DMetal, upscaling and CPU-translation controls; free Automatic must describe the actual DXMT/D9VK selection. Confirm every exposed setting reaches and works in the selected engine.
3. **Finish media reliability.** Evaluate the published CoreAudio and video-allocation fixes in disposable builds, with original clips and measured video/audio timing. Keep gameplay regressions out of the installed baseline.
4. **Add visible application profiles and dependency recipes.** Move the AoE fix into data and accumulate only verified settings. Keep explicit user overrides authoritative.
5. **Establish a runtime release process.** Source/patch provenance, pinned component versions, upgrade/rollback checks, API-level probes and a small representative game matrix, including 32-bit, launchers, video, controllers and long sessions.
6. **Run the FEX feasibility prototype.** Start with entitlement and CPU correctness gates; reuse public work, then integrate graphics/Steam/media. Investigate modern Vulkan/D3D12 separately rather than assuming FEX provides it.

For a prospective upstream PR, the author's position matters: in issue #37 they say supporting a free runner requires real integration changes and express concern about sustaining CodeWeavers. Our implementation should credit reused work and stand on demonstrable behavior; acceptance upstream is not assured. [Maintainer's response](https://github.com/NotProtonNot/NotProton/issues/37).

No runtime parity claim is justified yet. The achievable next outcome is a maintained, well-tested free runner with known capabilities, documented game profiles and a separately validated ARM/FEX path.


## Follow-up: Fallout 76 changes the immediate priority

The user subsequently reported Fallout 76 (Steam app 1151340) crashing at launch. Read-only inspection of the actual captured game log found:

```text
wine: Unhandled illegal instruction at address 00000001420B3880 (thread 011c), starting debugger...
```

Evidence: `~/Library/Application Support/notproton/launchers/1151340/notproton-wine.log`, line 227. The Steam wrapper log records bundle/game status 0 despite this failure, showing that wrapper completion is not a reliable gameplay-success signal. Wine startup also emits memory-mapping and service errors; these are not established as fatal causes. This investigation did not relaunch the game, capture the popup text or disassemble the faulting instruction. The exception may be an unsupported instruction, an intentional trap or incorrect execution state; a specific diagnosis is still pending.

CodeWeavers explicitly lists Fallout 76 fixes in CrossOver 25.0.0. Their presence in our exact Sikarugir build is not verified. [Primary changelog](https://www.codeweavers.com/crossover/changelog/).

Revised execution order after bringing the fork to upstream 1.1.3:

1. Capture and reproduce Fallout's exact exception; improve launch failure reporting and establish a multi-game acceptance matrix. Separate process launch, menu, gameplay, media and long-session results.
2. Establish the reproducible Wine/Rosetta runtime baseline and audit relevant CrossOver/Proton fixes, including CPU feature reporting, exception handling and loader/thread state. Use matched fixtures and targeted patches, not blind imports.
3. Validate graphics/backend selection across games, make controls capability-aware and support explicit tested fallback. Do not infer a graphics cause from this exception alone.
4. Implement data-driven compatibility profiles with transparent applied settings and authoritative user overrides.
5. Validate Steam dependency installers and add narrowly scoped missing dependency recipes, with usable failure reports.
6. Address media timing, CoreAudio and video-surface correctness.
7. Validate synchronization, controllers, overlay, launchers and long-session stability before performance defaults are widened.
8. Add and qualify a free D3D12 backend as a separate coverage project.
9. Introduce FEX as an independently gated native ARM runner; keep Rosetta as the baseline.

Runtime execution is the leading area to investigate from the observed failure. Graphics, application profiles and dependencies are additional compatibility areas, not confirmed Fallout fixes. Media improvements primarily address the existing AoE symptoms. No number of proposed patches can currently be represented as known fixes for Fallout's crash, and FEX is not an immediate cure.

## Implementation results after authorization

The branch is rebased onto upstream **1.1.3**. Changes remain fork-only. The
application was rebuilt and strictly code-signature verified; the installed
review application and Steam components are now installed as 1.1.3. A managed
experimental source engine is imported and selected for Fallout, whose prefix
was rebuilt successfully. The user subsequently confirmed Steam launch, login
and entering gameplay on 10 October 2026. Media, longer sessions and broader
feature checks remain pending.

The original Fallout crash is now diagnosed. The packaged Sikarugir engine fails
to open its executable through `\\.\GLOBALROOT\??\S:\...`, returning
`STATUS_BAD_DEVICE_TYPE`. DOS-path reads work, but equivalent namespace reads
fail in both 32-bit and 64-bit Windows fixtures. The invalid bytes at the crash
are not evidence of an AVX instruction failure. Overlay removal and switching
DXMT to DXVK preserve the original exception, ruling those changes out as fixes
for this specific startup failure.

A separate free runtime candidate built from the public CrossOver 26.3 Wine
source implements the missing API behavior. A controlled comparison removes
only that `GLOBALROOT` handling and reproduces the exact original exception;
restoring it removes the exception. This is a general Windows path behavior,
not an AoE or Fallout executable modification. The game initializes Steam and
D3D11 and survives a 45-second probe. After managed import and prefix rebuild,
the user confirmed successful login and entry into gameplay. Longer sessions,
media and full feature coverage remain unqualified.

The source candidate includes fonts, GnuTLS, GStreamer and SDL. Both Windows
architectures pass namespace access, normal-certificate WinHTTP HTTPS and native
Steam client pipe probes; a fresh prefix initializes successfully. NotProton's
existing Steam export forwarding is adapted at source level, and the Unix bridge
is rebuilt against this exact Wine tree. Official DXMT v0.80 is used as a pinned
overlay because the development DXMT in the packaged template expects a newer
macOS surface API. No paid CrossOver binaries, D3DMetal or FEX are required.
The [developer build recipe](../../runtime/README.md) records inputs and licensing
and keeps this candidate separate from the installed Sikarugir runner. Normal
installer integration now preserves the engine’s matching Unix bridge, copies
its dependencies, and registers a separate opt-in Steam tool. A self-contained
release package remains unfinished.

Two broadly applicable NotProton fixes are implemented: Wine's process status
and explicit unhandled exceptions now produce a launch failure instead of a
false zero-status result; the Steam graphics panel recognizes named, legacy and
inherited free tools, hides unavailable D3DMetal, and sends Automatic DLSS options
to DXMT. Paid-tool behavior is retained. The complete Swift suite passes
**488 tests across 58 suites**, including pinned-archive installation checks;
affected native compatibility and panel fixture/behavior checks also pass.
Actual Steam UI rendering still needs a visible check.

Remaining priority order: package and maintain the managed source runtime;
retest AoE on this engine and broaden Fallout session/feature coverage; add reusable profiles and dependency
recipes where evidence requires them; investigate video/audio timing; broaden
controller/overlay/long-session coverage. Free D3D12 and native ARM/FEX remain
separate later projects. The source baseline does not establish parity with
CrossOver's full product or universal game compatibility.
