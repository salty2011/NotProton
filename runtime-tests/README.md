# Runtime acceptance probes

These probes exercise Windows behavior in the actual Wine engine. Application and
installer unit tests cannot establish that behavior, and launching a process is
not evidence that a game reaches its menu or plays correctly.

Use a disposable prefix. Never point an experimental engine at a valuable game
prefix: Wine may update its registry and Windows components automatically.

## Windows path namespaces

`path-namespace.c` creates a temporary file, verifies its normal DOS path, and
reads the same contents through `\\.\GLOBALROOT\??\` with two capitalizations.
The process returns 0 only when all reads succeed, 1 for a compatibility failure,
and 2 for fixture setup failure. It deletes its temporary file.

Build both Windows architectures:

```sh
mkdir -p .scratch/runtime-tests
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror runtime-tests/path-namespace.c -o .scratch/runtime-tests/path64.exe
i686-w64-mingw32-gcc -Wall -Wextra -Werror runtime-tests/path-namespace.c -o .scratch/runtime-tests/path32.exe
```

Run with the selected engine's library environment and its matching wineserver:

```sh
NP_WINE="$HOME/Library/Application Support/notproton/runners/sikarugir-11.0_1/Wine"
export WINEPREFIX="$PWD/.scratch/runtime-tests/pfx"
export WINESERVER="$NP_WINE/bin/wineserver"
export DYLD_FALLBACK_LIBRARY_PATH="$NP_WINE/Libraries:$NP_WINE/Libraries/GStreamer.framework/Libraries:/usr/lib"
export SikarugirAppWine11=1
"$NP_WINE/lib/wine/x86_64-unix/wine" "$PWD/.scratch/runtime-tests/path64.exe"
"$NP_WINE/lib/wine/x86_64-unix/wine" "$PWD/.scratch/runtime-tests/path32.exe"
"$WINESERVER" -k
```

On 9 October 2026, both Sikarugir 11.0 revision 1 runs passed `DOS_PATH` and failed
both `GLOBALROOT` reads. Fallout 76 attempted this same namespace when opening its
own executable before its startup exception. The source candidate passes both
architectures. Removing only its `GLOBALROOT` handling reproduces the same
Fallout exception; restoring the handling removes that exception. The user subsequently confirmed Fallout 76 login and gameplay after rebuilding
its prefix on the source engine. Longer sessions and a new package remain separate
qualification milestones.

CodeWeavers' published LGPL Wine source implements `GLOBALROOT` handling in
`dlls/ntdll/unix/file.c`. Valve's Wine history also includes this change. Reuse
source fixes with their licenses and attribution; do not alter the game's code.

## Secure networking

`https.c` sends a credential-free WinHTTP request to Steam's public HTTPS
`robots.txt`, keeping normal certificate validation. It disables cookies and
does not read response content. Exit 0 requires HTTP 200; exit 1 indicates a
network/HTTP failure and 2 a setup failure. Network availability and server
policy affect the result, so keep the diagnostic error/status before blaming TLS.

```sh
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror runtime-tests/https.c -lwinhttp -o .scratch/runtime-tests/https64.exe
i686-w64-mingw32-gcc -Wall -Wextra -Werror runtime-tests/https.c -lwinhttp -o .scratch/runtime-tests/https32.exe
```

Run in the same disposable engine environment as the namespace probes. Both
architectures passed with status 200 in the source candidate on 9 October 2026.
This verifies the actual WinHTTP/GnuTLS path; it does not verify Fallout login,
server connectivity, launcher web views or Kerberos (disabled in this build).

## Native Steam bridge

`steam-client.c` loads the prepared prefix's native Windows Steam client DLL,
obtains `SteamClient021`, then creates and releases a Steam pipe. This tests the
export forwarding and Unix bridge against the real running macOS Steam client.
It does not sign in or request a game. Exit 0 requires a nonzero pipe; the other
exit values distinguish DLL loading, missing export/interface and pipe failure.

```sh
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror -Wno-cast-function-type runtime-tests/steam-client.c -o .scratch/runtime-tests/steam64.exe
i686-w64-mingw32-gcc -Wall -Wextra -Werror -Wno-cast-function-type runtime-tests/steam-client.c -o .scratch/runtime-tests/steam32.exe
```

Use a cloned prefix already prepared by NotProton with Windows Steam DLLs under
`C:\Program Files (x86)\Steam`. Set builtin `lsteamclient` and native
`steamclient,steamclient64` overrides, `STEAM_COMPAT_CLIENT_INSTALL_PATH` to the
running native Steam executable directory, and `WINEDLLPATH` to the prefix's
Steam directory plus this candidate's Wine libraries. Install both matching
source-hook `ntdll.dll` files and the candidate's own `lsteamclient.so`; stale
packaged copies in the clone can silently defeat this test. The source candidate
passed both architectures with `CLIENT_PIPE 1` on 9 October 2026. This is not an
overlay, Steam Input, authentication or gameplay test.

## Game acceptance records

Record engine/source revision, component versions, OS/hardware, prefix origin,
renderer and applied profile. Distinguish these milestones:

1. Prerequisites complete and the main executable starts.
2. Startup reaches the menu without an unhandled exception.
3. A real gameplay session works, including input and audio.
4. Videos, save/reload, networking and overlays work where applicable.
5. A longer session completes without hangs or growing resource use.

Use `pending` for untested milestones and retain failures. Neither exit status 0
nor a successfully created graphics device proves menu or gameplay compatibility.
See [the current matrix](../docs/research/game-compatibility-matrix.md).

## Packaged-runtime and media qualification

`qualify.py --runtime /absolute/path/to/Wine --output .scratch/new-qualification`
builds and runs both architectures' namespace and HTTPS probes in a disposable
prefix and writes `qualification.json`. Native Steam/gameplay checks are explicitly
reported as skipped; it never uses a Steam account or a live game prefix.

`media.py run --runtime /absolute/path/to/Wine --output .scratch/new-media --runs 3`
builds the Windows Media Foundation/D3D11 probe and test-only native audio tap,
generates its own marker clip, and records three cold/warm runs. Requires the
MinGW C++ compiler, clang, ffmpeg and Rosetta. `--clip /path/to/local/video.mp4`
selects private media; `--renderer dxvk` selects a separate renderer trial.
Captured zero-filled buffers, callback errors, successful swapchain presentations
and marker A/V drift remain separate metrics. The visible probe transfers frames
into a swapchain and calls Present; --transfer-only reproduces the earlier
offscreen baseline. Present success measures submitted frames, not physical display
scanout or a complete game's videos and gameplay. Closing the probe window fails
the run. Any failed synthetic gate makes qualification exit unsuccessfully.
