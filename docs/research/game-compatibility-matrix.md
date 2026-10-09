# Free runner acceptance matrix

Updated 10 October 2026. Hardware: Apple M4 Pro. Installed baseline: Sikarugir Wine
11.0 revision 1, Rosetta; DXMT 0.80 development build, DXVK-Sikarugir async 1.10.3,
D9VK 2.3 and shared MoltenVK 1.4.1. NotProton application/Steam installation is
now the 1.1.3 review build, rebased onto upstream 1.1.3. The experimental
source engine is imported as a separate managed Steam tool; selection and visible
game verification remain pending. Its DXMT overlay uses released v0.80.

| Game | Prerequisites / launch | Menu | Gameplay | Media | Longer session / remaining coverage |
| --- | --- | --- | --- | --- | --- |
| Age of Empires: Definitive Edition, 1017900 | Previously passed | Previously passed after scoped adapter profile | User confirmed playable with normal audio | Startup video and audio stutter; unresolved | Long sessions, network, controllers and overlay not comprehensively qualified; retest after engine changes |
| Fallout 76, 1151340 — installed Sikarugir | Dependency helper ran; completion is not fully qualified. Main executable reproducibly crashes at startup | Failed before menu in the controlled replay | Pending | Pending | Pending |
| Fallout 76 — experimental source candidate | Original crash removed by verified namespace fix; native Steam client and D3D11 initialize | Pending visible verification; process survives 45-second probe | Pending | Pending | Networking and longer sessions pending; managed source tool is imported; per-game selection is pending |

## Fallout 76 evidence

The original launch and disposable-prefix replays report an unhandled illegal
instruction at `Fallout76.exe+0x20B3880`. Removing the Steam overlay, removing the
Steam launch helper, and replacing DXMT with DXVK individually leave the same
exception. Debugger inspection reads invalid bytes at the faulting entry point;
this is not evidence of an AVX instruction failure.

Targeted file tracing identifies failed opens through
`\\.\GLOBALROOT\??\S:\steamapps\common\Fallout76\Fallout76.exe` with NT status
`0xc00000cb`. The independent Windows namespace fixture also fails in both 32-bit
and 64-bit Sikarugir. The source-built free candidate passes both architectures.

A controlled comparison establishes causality for the original startup crash:
removing only the `GLOBALROOT` implementation from the candidate's Unix `ntdll`
restores the same exception at `0x1420B3880`; restoring it removes that exception.
The completed candidate initializes native Steam and D3D11 (feature level 11_1)
and survives a 45-second probe. This is not menu or gameplay proof. The Mac was
locked during these probes, so visible verification remains pending.

The candidate uses public CrossOver 26.3 Wine source, source-level NotProton
Steam hooks, the matching Unix bridge, official DXMT v0.80, and the existing
Sikarugir font, TLS and media libraries. It requires no paid CrossOver binary.
Both 32-bit and 64-bit probes pass Windows namespace access, create a native
Steam client pipe, and receive HTTP 200 over certificate-verified WinHTTP HTTPS.
Fresh prefix initialization also passes. See [the build recipe](../../runtime/README.md)
for pinned inputs, licenses, managed import and rollback. A redistributable
release package remains unfinished.

The launcher previously recorded bundle/game status 0 despite the Windows
exception. The source now captures Wine's own exit result and treats an explicit
unhandled-exception report as a failure when Wine returns zero. This is failure
reporting, not a fix for the runtime exception.

Captured local evidence and controlled replays are in `.scratch/fallout76/` and
are intentionally excluded from commits. Do not publish complete logs without
reviewing account identifiers and other private fields.

## Coverage to add

Use additional installed/available games to cover a 32-bit D3D9 title, a second
D3D11 engine, a launcher-dependent title, and eventually a D3D12 title. Fixtures
cover API behavior between manual gameplay runs; they do not replace gameplay
qualification. Mark unavailable titles as pending instead of inferring support.
