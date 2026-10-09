# NotProton

NotProton enables the Steam Play experience from Linux Steam in the macOS Steam client.

This is done by forcibly enabling the Steam Play functionality in macOS Steam (which is
present and inert) as well as by porting some components of Valve's Proton to macOS.

This tool is intended to be used with Steam Client 1788652215 or 1790121765.
For a free runner, install NotProton into Steam and choose **Set Up Free Runner**
in the Status page. This downloads **Sikarugir Wine 11.0 revision 1**, with the
matching dependencies and graphics layers from Sikarugir Template 1.0.21. Both
archives are verified against pinned SHA-256 digests before extraction. No
CrossOver installation or activation is required for this runner. After setup,
select **Sikarugir** in the game’s Steam Compatibility settings.

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

Fallout 76 exposes a missing `GLOBALROOT` Windows path behavior in the packaged
Sikarugir engine. A separate [source-built free runtime candidate](runtime/README.md)
fixes that startup exception and passes 32/64-bit namespace, Steam bridge and
HTTPS probes. Menu, networking and gameplay validation remain pending; the
candidate is not installed by **Set Up Free Runner**. Track qualification in
the [game acceptance matrix](docs/research/game-compatibility-matrix.md).

The existing paid runner supports **CrossOver 26.3** and **CrossOver Preview
20261006 (27.0.0.41069) or 20260821 (27.0.0.40921)**. The Preview FEX and Rosetta
builds remain supported; Sikarugir currently uses Rosetta.
Preview releases are available through the [CodeWeavers Preview Centre](https://www.codeweavers.com/preview).

NotProton verifies the Wine loader against known builds before patching the runtime;
an unrecognized CrossOver release is not automatically compatible. An installed
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
documentation is quite sparse. Sorry about that, I'll improve it shortly. For real this time.

Please read NOTICE for license information.

Please open issue reports with any issues. PRs are welcome and encouraged. Contributions policy to come shortly.

There are many people who worked on similar ideas, similar projects. I did not base NotProton on their work, but I still want to 
give thanks to the people who came before me:

[Nat Brown](https://github.com/natbro) made [Kaon](https://github.com/natbro/kaon), which is similar in goals to NotProton.

mont127's [Neutron](https://github.com/mont127/Neutron) is also a similar idea, but implemented differently. 

[Gio](https://github.com/giodotblue) was working enabling Steam Play inside of Steam on macOS prior to the release of NotProton itself. 
I would have done things differently had I been aware of that. 

Thanks to everyone who has positively contributed to macOS gaming. 
