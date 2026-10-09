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
