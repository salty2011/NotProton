# Experimental source-built free runtime

This developer recipe builds a separate Rosetta Wine candidate from CodeWeavers'
public CrossOver 26.3 FOSS source. It requires no paid CrossOver installation or
proprietary runtime. It reuses the installed, pinned Sikarugir libraries, Mono
and Gecko. The packaged Sikarugir runner remains the default. The experimental engine
can be imported as a separate Steam tool for explicit per-game testing.

Sikarugir 11.0 revision 1 cannot open `\\.\GLOBALROOT\??\` paths. Fallout 76 opens
its own executable through that namespace and subsequently crashes. The public
Wine source implements that behavior. Removing only this implementation restores
Fallout's original crash; restoring it lets the game initialize Steam and D3D11.
See [the acceptance matrix](../docs/research/game-compatibility-matrix.md) for
the remaining menu, networking and gameplay checks.

## Inputs and integration

[inputs.json](inputs.json) pins the source archive, official DXMT v0.80 release,
DXMT license and existing DLL-path prepend patch by SHA-256. Released DXMT uses
the surface API supported by this Wine base; Sikarugir's newer development DXMT
binary expects a different macOS driver API.

[prepare-steam-hook.py](prepare-steam-hook.py) adapts NotProton's existing
`ntdll-patch/detour{,32}.c` export forwarding to Wine's actual loader structures.
The hook runs before import resolution, avoiding borrowed hardcoded PE offsets.
Both 32-bit and 64-bit bridge probes have created a real native Steam client pipe.
The Unix `lsteamclient` is compiled against this exact Wine tree; do not mix it
with the packaged runner's Unix bridge.

DXMT is an overlay through `WINEDLLPATH_PREPEND`, preserving Wine's builtin D3D
DLLs. No D3DMetal, `libd3dshared`, FEX or paid compatibility database is included.
NotProton imports the qualified build as a managed, separate Steam tool. It
preserves the engine’s matching Unix bridge during app updates and uses the
selected renderer’s builtin overlay. This is not a fully qualified replacement.

## Build

Requirements: macOS, Rosetta, Command Line Tools, Python 3, GNU make (`gmake`),
MinGW-w64, Bison, pkg-config, and headers for FreeType, GnuTLS, SDL2 and GStreamer.
The current build uses Homebrew headers under `/opt/homebrew` and matching
x86_64 Sikarugir binary libraries. Component archives must have been verified by
the Sikarugir installer. Build the NotProton application payload first so its
pinned PE bridges exist under
`app/Sources/NotProtonApp/Resources/payload/bridge/`.

```sh
python3 runtime/build.py \
  --work .scratch/free-runtime \
  --components "$HOME/Library/Application Support/notproton/runners/sikarugir-11.0_1/Wine"
```

Use a work directory without whitespace. Optional `--headers` selects another
development prefix and `--jobs` controls parallel compilation. `--stage-only`
stages an existing build; it does not validate a fresh build. Keep and inspect
the build logs rather than proceeding with partial output.

Output: `<work>/wine-built`. Its manifest records pinned inputs, recipe hashes,
repository revision, toolchain versions, header/component roots and key binary hashes. Libraries
remain symlinked to installed Sikarugir components. This is a local developer
candidate, not a self-contained release archive. Header/toolchain versions are
not fully pinned; do not claim byte-for-byte reproducibility or redistribute
just this directory.

On 9 October 2026, a clean source tree built successfully through this recipe.
That output passed all six 32/64-bit namespace, HTTPS and native Steam bridge
probes. Fallout's original exception was absent in its 45-second startup replay,
and a D3D11 feature-level 11_1 device initialized. After managed import and prefix
rebuild on 10 October, the user confirmed Steam launch, login and entering
gameplay. Longer sessions and additional game features remain unqualified.

## Import and select

The current review build accepts the exact locally qualified binaries identified
by `SupportedRunners.freeWine` and `FreeWineInstaller.binaryHashes`. A different
compilation needs a new identity and qualification; a self-authored manifest
alone does not authorize arbitrary binaries. The recipe is not byte reproducible.

In NotProton, use **Experimental Free Wine → Import Build…** and select
`<work>/wine-built`. Keep the official renderer at the recipe’s adjacent
`<work>/dxmt-v0.80/v0.80` path. Sikarugir must be ready when importing: its pinned
libraries and renderers are copied into the managed engine, including materializing
library symlinks. Subsequent use does not depend on retaining that Sikarugir copy.

Restart Steam after the tool is registered. For a test game, select
**Free Wine 26.3 revision 1 (Experimental)** in Steam’s Compatibility properties.
Start with Automatic (DXMT), which passed the source replay. DXVK and WineD3D
selection is implemented but has not yet been qualified with this source engine.
Importing does not change existing game mappings or the default compatibility tool.

Before changing an existing prefix’s engine, stop its matching wineserver and
back up the entire compatdata directory. To roll back, stop the source engine,
reselect the previous Steam tool, and restore the prefix backup if required.
Re-selecting a tool alone does not undo Wine’s prefix updates. NotProton’s
**Remove Copy** action removes the managed engine; select another tool for any
mapped games before removing it. A damaged source copy must be removed and
reimported, rather than repaired using generic engine binaries.

The review app and managed engine were installed on 10 October 2026. Steam
selection for Fallout and its prefix rebuild are complete. The user confirmed
login and entry into gameplay. Remaining coverage is recorded in the
[acceptance matrix](../docs/research/game-compatibility-matrix.md).

## Validate

Use this engine's Wine loader and wineserver. Add its `Libraries` and GStreamer
library directory to `DYLD_FALLBACK_LIBRARY_PATH`. For DXMT, prepend
`<work>/dxmt-v0.80/v0.80` through `WINEDLLPATH_PREPEND` and use builtin D3D11/DXGI
overrides. Pass the matching Steam bridge environment for Steam API tests.
Start with [the Windows fixtures](../runtime-tests/README.md).

Use disposable prefixes, cloning existing prefixes for game tests. Wine updates
Windows components and registry state even when a launch fails. Stop the clone's
matching wineserver after each test. Process survival, an HTTPS response and a
D3D device are separate milestones; none prove menu or gameplay compatibility.

## Source and licenses

Wine's base is LGPL-2.1-or-later: retain its `COPYING.LIB` and matching source.
The reused NotProton hook is GPLv3, copied as `LICENSE.NotProton`; do not describe
the combined modified engine as solely LGPL. Official DXMT v0.80 is MIT and its
license is copied as `LICENSE.DXMT`. Retain Sikarugir dependencies' licenses.
Any future release must provide complete corresponding source and patches.

The namespace fix also appears in [Valve's Wine history](https://github.com/ValveSoftware/wine/commit/0b4e6f7f3c909fb9f9a0621ed1e3663e0ce39a34).
The prepend patch is reused from pinned Highball tooling, with its MacPorts
origin recorded in the manifest. Credit this existing work.

## Portable package development

`package.py components` prepares the pinned free dependency selection directly
from the engine/template archives in `component-inputs.json`. No installed
Sikarugir or paid runtime is required. Use a new output directory:

```sh
python3 runtime/package.py components \
  --engine /path/to/WS12WineSikarugir11.0_1.tar.xz \
  --template /path/to/Template-1.0.21.tar.xz \
  --output .scratch/runtime-components
python3 runtime/build.py --work .scratch/runtime-build \
  --components .scratch/runtime-components
```

`package.py build` combines that assembly, the source engine and official DXMT
with provenance into an archive and catalog. It validates the complete file/link
inventory, Intel/Windows architecture, internal non-system library references,
and executable entry points. The macOS minimum comes from actual binaries;
the current local package requires macOS 27.0.0. `package.py verify <archive>`
checks relocation and inventory. Run `python3 -m unittest discover -s runtime/tests -v`
for archive-safety/consumer tests.

The app's **Install Package…** action accepts the exact archive approved by its
bundled catalog, then prepares its matching bridge in isolation before committing
its own versioned Steam tool. Existing engines remain available. Package
revisions can share a loader; identify them by approved archive and build ID,
not by guessing from the loader hash. Runtime capabilities are reviewed per
revision in `runtime/policy.json`; `generate-policy.py` projects those descriptors
into Swift, Steam UI and the launcher, and `--check` detects stale projections.

The release workflow remains quarantined: `release.py` produces separate binary,
modified-source and qualification outputs, but binary publication/catalog promotion
are disabled while dependency corresponding-source/notices review is incomplete.
The generated `distributionReady` field remains false. Do not publish a local
binary merely because its namespace/TLS tests pass. See the new
[measured media baseline](../docs/research/free-runtime-media-baseline.md) for the
separate playback and game acceptance gates.
