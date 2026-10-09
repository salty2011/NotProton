# Free runtime media baseline

Measured on 10 October 2026 using the unchanged CodeWeavers 26.3 public Wine source
candidate with NotProton's matching Steam hook/Unix bridge, official DXMT v0.80,
and the pinned free dependency assembly. Host: Apple M4 Pro, macOS 27.2. This is
qualification of the Media Foundation probe, not confirmation of in-game playback.

`runtime-tests/media.py` generates a 12-second 1280×720/30fps H.264/AAC clip with
synchronized audio pulses and video flashes. It exercises Media Foundation's
D3D11 device-manager path and transfers each delivered video frame into a GPU
texture. The test-only CoreAudio tap captures PCM and callback timestamps into
preallocated memory, then writes after the audio unit stops. It performs no disk
writes or allocations in the render callback. Wine QPC and CoreAudio host times
are aligned using the native timebase and continuous/absolute clock offset.

| Replay | Cold runs (3) | Warm runs (3) |
|---|---|---|
| Synthetic marker | 359/360 transferred frames in each run | 359/360 in each run |
| Synthetic maximum frame gap | 41 ms | 41 ms |
| Synthetic internal silence/callback errors/clock discontinuities | 0 | 0 |
| Synthetic measured A/V drift | −0.93 to +0.35 ms | −1.96 to +0.45 ms |
| Original AoE Microsoft Studios clip | 150 transferred frames in each run | 150 in each run |
| Original clip maximum frame gap | 42–45 ms | 41 ms |
| Original clip captured internal silence/callback errors/clock discontinuities | 0 | 0 |

All six synthetic runs pass the agreed probe gates: ≥99% transferred frames,
no post-buffering frame gap above three frame periods, no captured starvation or
callback errors, and absolute marker drift ≤100 ms. The original game clip is
3840×2160, about 5.056 seconds long, and remains unmodified. Game media is local
input only; neither clips nor PCM captures are committed or redistributed.

The earlier Sikarugir reproduction had captured silent gaps during simultaneous
video/audio playback. These new results justify testing AoE with the newer source
runtime before adding the proposed CoreAudio or video-allocation patches. They
**do not** establish that the complete game startup is smooth: actual swapchain
presentation, every startup clip, user-observed playback and gameplay must still
be checked. A successful texture transfer is not a presented-frame measurement.
No additional media patch has been promoted, and the working installed runtime
has not been replaced by these experiments.

## Presentation and independent patch trials

The follow-up probe transfers into a visible DXGI swapchain and records a frame
only after `Present(1, 0)` returns `S_OK`. Each row below includes three cold and
three warm runs on the same host, using DXMT 0.80 and the same encoded clips.
Audio was captured as stereo float PCM at 48 kHz. These are successful presentation
submissions, not a measurement of physical screen scanout or of AoE's own renderer.

| Engine | Marker frames per run (expected 360) | Maximum gap | Marker drift range | Original AoE clip |
|---|---|---|---|---|
| Unpatched 26.3 baseline | 359 | 36–51 ms | −6.06 to +3.18 ms | 150 frames; 39–42 ms gaps |
| CoreAudio buffer trial | 358–359 | 36–49 ms | −13.45 to +1.26 ms | 150 frames; 37–44 ms gaps |
| Source Reader allocator trial | 358–359 | 36–49 ms | −2.84 to +0.82 ms | 150 frames; 36–41 ms gaps |

Every synthetic run passed the ≥99% frame, ≤100 ms gap/drift and audio-capture
gates. All 36 full-video runs completed with no recorded internal silent regions,
callback errors, clock discontinuities or failed frame transfers/presentations.
Both trial engines also passed the separate 32/64-bit namespace and HTTPS probes.

The audio-only mode removes video from the encoded clip without re-encoding AAC.
Six baseline and six CoreAudio-trial runs completed without captured silent gaps,
callback errors or clock discontinuities. Baseline captured duration was
11.915–11.925 seconds; trial duration was 11.925 seconds. The secondary trial ran
alongside build/allocation work, so it is exploratory evidence rather than an
isolated timing comparison. No system audio-rate setting was changed.

Media Engine uses a media session in this Wine source; it does not exercise the
proposed patch's Source Reader allocation path. The independent `--source-reader`
probe requests a D3D11 device manager, advanced video processing and shared
textures, then obtains and reopens every sample's DXGI shared handle. One cold and
one warm run on each baseline/video candidate decoded all 360 frames with 360
usable shared textures and zero failures. This establishes that the tested
allocation case already works on the baseline; it does not cover every Unity or
Unreal configuration. See Microsoft's [Source Reader attributes](https://learn.microsoft.com/en-us/windows/win32/medfound/source-reader-attributes)
for the separate reader/device-manager interface.

Both proposed patches apply cleanly and build against the pinned source tree.
Their exact inputs and attribution are recorded in `runtime/media-candidates.json`.
Neither trial reproduces or removes a failing case in these probes, so **neither
patch is promoted**. Full AoE startup replays, user-observed smoothness and gameplay
regression remain required. Item 3 is unfinished until those checks resolve the
reported symptom. The newer engine's clean probe behavior alone is not a game fix.

## Reproduction

Reproduce in a new output directory:

```sh
python3 runtime-tests/media.py run \
  --runtime '/absolute/path/to/package/Wine' \
  --output .scratch/media-qualification --runs 3
```

Use `--clip /absolute/path/to/local/clip.mp4` for a local game clip; synthetic
marker drift/gates apply only to the generated clip. The harness stops only its
own disposable prefix's matching wineserver. Failed/incomplete capture is not a
passing measurement. Keep the individual `metrics.json`, `probe.log` and runtime
loader/clip digests for comparisons.

Use `--audio-only` to separate audio from video work, `--source-reader` to test
shared sample allocation, or `--transfer-only` for the historical offscreen
baseline. These modes are mutually exclusive. The default measures the visible
swapchain. Raw game media, PCM and device logs remain private local evidence.
