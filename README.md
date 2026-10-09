# NotProton

NotProton enables the Steam Play experience from Linux Steam in the macOS Steam client.

This is done by forcibly enabling the Steam Play functionality in macOS Steam (which is
present and inert) as well as by porting some components of Valve's Proton to macOS.

This tool is intended to be used with Steam Client 1788652215 or 1790121765.
For a free runner, install NotProton into Steam and choose **Set Up Free Runner**
in the Status page. This downloads **Sikarugir Wine 11.0 revision 1**, with the
matching dependencies and graphics layers from Sikarugir Template 1.0.21. Both
archives are verified against pinned SHA-256 digests before extraction. No
CrossOver installation or activation is required for this runner.

The free runner uses Rosetta on Apple Silicon. Automatic graphics selects
**DXMT** for Direct3D 10/11, with **DXVK** available in each game's Compatibility
settings and **WineD3D** as a fallback. DXVK uses the included MoltenVK library.
The selected DXVK-Sikarugir 1.10.3/D9VK 2.3 build passes the hardware-device
probe on Apple M4 Pro. The template's newer DXVK 3.1.1 requires Vulkan features
that this MoltenVK setup does not expose, so it is not selected.
This path does not install Sikarugir's wrapper UI, its SDK, or D3DMetal/GPTK.
Direct3D 12 support and FEX integration are outside this initial free-runner change.
Published components come from the upstream [engine releases](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0)
and [template releases](https://github.com/Sikarugir-App/Template/releases/tag/v1.0);
renderer license files are retained in the managed runner.

Age of Empires: Definitive Edition (Steam app 1017900) has been tested through
actual gameplay on Apple M4 Pro. Its startup hardware check rejects Apple's
PCI IDs, so the free DXMT and DXVK launchers supply an adapter-ID compatibility
profile for this game. Explicit renderer configuration takes precedence.
Startup-video playback still stutters in the tested Wine media pipeline,
affecting both video and audio; gameplay audio has been confirmed smooth.

The existing paid runner supports **CrossOver Preview
20261006 (27.0.0.41069) or 20260821 (27.0.0.40921)**. These are Preview releases,
not stable CrossOver 26.3. Both the FEX build and the Rosetta build are supported.
The Rosetta build is the recommended version, as the FEX one is in an early state.
Preview releases are available through the [CodeWeavers Preview Centre](https://www.codeweavers.com/preview).

NotProton verifies the Wine loader against known builds before patching the runtime;
a newer or stable CrossOver release is not automatically compatible. An installed
but unsupported CrossOver should be distinguished from a missing installation.

Installing NotProton patches Steam and stages its core components in your macOS
user folder. Setting up the compatibility tool is a separate step that downloads
Sikarugir or copies a supported CrossOver runtime and produces the patched `ntdll.dll` files. Until that
step is complete, Windows games may offer an Install button in Steam, but the
compatibility tool is not ready to launch them.

The macOS app itself is located in the ```app``` folder. The core logic is in ```dylib```.
```lsteamclient``` is a macOS port of Valve's lsteamclient. ```steam-shim```is a port of Valve's
steam-helper from Proton 9. ntdll-patch patches the copy of the Wine runtime that the app
makes/places in the ```~/Library/Application Support/notproton/runners/``` folder so that
lsteamclient is loaded.

This release is coming several days past when I wanted to release it, so the
documentation is quite sparse. Sorry about that, I'll improve it shortly.

Please read NOTICE for license information.

Please open issue reports with any issues. PRs are welcome and encouraged. Contributions policy to come shortly.
