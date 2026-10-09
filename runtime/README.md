# Experimental source-built free runtime

This developer recipe builds a separate Rosetta Wine candidate from CodeWeavers'
public CrossOver 26.3 FOSS source. It requires no paid CrossOver installation or
proprietary runtime. It reuses the installed, pinned Sikarugir libraries, Mono
and Gecko. The packaged Sikarugir runner remains the installed default until the
candidate passes the game acceptance checks.

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
Normal NotProton installer integration and Steam renderer controls for this
source candidate remain pending. This recipe is not a qualified replacement.

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
and a D3D11 feature-level 11_1 device initialized. Menu/gameplay remain pending.

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
