# Free runner acceptance matrix

Updated 10 October 2026. Hardware: Apple M4 Pro. Installed baseline: Sikarugir Wine
11.0 revision 1, Rosetta; DXMT 0.80 development build, DXVK-Sikarugir async 1.10.3,
D9VK 2.3 and shared MoltenVK 1.4.1. NotProton application/Steam installation is
now the 1.1.3 review build, rebased onto upstream 1.1.3. The experimental
source engine is imported as a separate managed Steam tool; Fallout is selected for this tool and its prefix has been rebuilt successfully.
The user confirmed Fallout launches, logs in and enters gameplay with the rebuilt
prefix. Its DXMT overlay uses released v0.80. Media and longer-session checks
remain pending.

| Game | Prerequisites / launch | Menu | Gameplay | Media | Longer session / remaining coverage |
| --- | --- | --- | --- | --- | --- |
| Age of Empires: Definitive Edition, 1017900 | Previously passed | Previously passed after scoped adapter profile | User confirmed playable with normal audio | Startup video and audio stutter; unresolved | Long sessions, network, controllers and overlay not comprehensively qualified; retest after engine changes |
| Age of Empires — packaged source runtime revision 2 | Steam dependency preparation completed; backed-up prefix migration succeeded | One DXVK/profile-disabled replay reached the menu; subsequent installed-fix replays stayed black both with and without the disable marker | Pending on this revision | Pending; no media patch promoted | Reliable startup unresolved; original Sikarugir prefix and selection restored for a baseline comparison, revision 2 prefix retained |
| Fallout 76, 1151340 — installed Sikarugir | Dependency helper ran; completion is not fully qualified. Main executable reproducibly crashes at startup | Failed before menu in the controlled replay | Pending | Pending | Pending |
| Fallout 76 — managed experimental source runtime | User confirmed successful Steam launch after prefix rebuild; original crash removed by verified namespace fix | User confirmed reaching gameplay | User confirmed login and entering gameplay | Pending | Basic login/network path passed in user testing; longer sessions, save/reload, controllers and overlay remain pending |
| Quake II, 2320 | User reports launch reaches a level; exact runtime, renderer and edition/executable for this replay are not confirmed | Not separately assessed | Blocked: HUD is visible, but the game world is black | Not assessed | Rendering defect unresolved; reaching a level does not establish playable gameplay |

## AoE adapter profile regression

On 10 October 2026, two revision 2/DXMT replays stayed completely black. Changing
only the renderer to DXVK left the same symptom. Keeping DXVK, the same runtime
and rebuilt prefix, then disabling only the adapter profile reached the menu in
user review. That initially implicated profile application, but the installed
profile-v2 replay subsequently stayed completely black without a warning even
though the source runtime received no automatic adapter profile. The earlier
menu result therefore does not establish a reliable fix or a causal explanation.

The profile had extended adapter IDs tested on Sikarugir to both source runtimes
without game qualification. Profile v2 restricts those defaults to
`sikarugir-11.0_1`. Source runtimes retain the player's explicit renderer settings
and receive no automatic adapter spoofing. Generated-launcher regression tests
cover both source-runtime revisions and both graphics paths; Steam panel tests
cover explicit and inherited runtime selection. The installed helper also
returns no profile defaults for the actual AoE executable on revision 2/DXVK.
A fresh comparison with the local profile-disable marker restored also stayed
black in human review. The reported dialog is NotProton's generic launch-failure
alert with exit status 1; no Wine exception trace was captured, and stopping a
stuck replay can also trigger that alert. Both successful and failed runs contain
unsupported swapchain buffer diagnostics; their presence alone does not identify
the cause. The original Sikarugir prefix and selection have been restored for a
baseline comparison, retaining revision 2 as another backup. Reaching the menu
does not establish gameplay, smooth startup media or session stability.

## Quake II rendering report

On 10 October 2026 the user reported that Quake II launches into a level, but only
the HUD is visible and the game world is black. Record this as a gameplay-blocking
rendering issue, separate from AoE's startup media stutter. No cause or workaround
has been established, and no controlled reproduction has been run for this report.

Before selecting a fix, identify the actual edition/executable, selected runtime,
renderer and effective settings, then capture a failing replay and compare graphics
paths using a disposable or backed-up prefix. Acceptance requires a visible game
world and playable level with the HUD intact, followed by repeat-launch checks.
The local follow-up ticket is
`.scratch/quake2-rendering/issues/01-black-world-visible-hud.md`.

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
and survives a 45-second probe. Those probes alone did not establish menu or gameplay compatibility. After
managed import, Steam selection and prefix rebuild, the user confirmed successful
launch, login and entry into gameplay on 10 October 2026. This does not establish
long-session stability or complete feature coverage.

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
