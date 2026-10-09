#!/usr/bin/env python3
"""Build and measure real Wine Media Foundation playback in disposable prefixes."""
import argparse
import array
import bisect
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time

SOURCE = Path(__file__).resolve().parent


def run(command, **options):
    return subprocess.run([str(value) for value in command], check=True, **options)


def prepare(output):
    output.mkdir(parents=True, exist_ok=True)
    run(['x86_64-w64-mingw32-g++', '-Wall', '-Wextra', '-Werror', '-municode', '-static',
         SOURCE / 'media-playback.cpp', '-o', output / 'media-playback.exe',
         '-lmfplat', '-lmfreadwrite', '-lmfuuid', '-luuid', '-lole32', '-loleaut32', '-ld3d11', '-ldxgi'])
    run(['clang', '-arch', 'x86_64', '-Wall', '-Wextra', '-Werror', '-dynamiclib',
         SOURCE / 'audio-capture.c', '-framework', 'AudioToolbox', '-o', output / 'audio-capture.dylib'])
    run(['codesign', '-f', '-s', '-', output / 'audio-capture.dylib'])
    # The generated clip has a 30ms audio pulse and video flash every second.
    # There is no intentional silence, making zero-filled buffers unambiguous.
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error',
         '-f', 'lavfi', '-i', "testsrc2=size=1280x720:rate=30:duration=12,drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='lt(mod(t,1),0.033)'",
         '-f', 'lavfi', '-i', "aevalsrc='sin(2*PI*997*t)*if(lt(mod(t,1),0.03),0.65,0.1)':s=48000:d=12",
         '-c:v', 'libx264', '-preset', 'fast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k',
         '-shortest', '-y', output / 'marker.mp4'])


def analyze(directory, marker=False):
    lines = (directory / 'probe.log').read_text(errors='replace').splitlines()
    frames = []
    completion = None
    frequency = None
    for line in lines:
        if line.startswith('MEDIA_ALLOCATION_RESULT '):
            values = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', line)}
            result = dict(values, path='source-reader', passesAllocationGate=bool(values['ended']
                and values['frames'] > 0 and values['shared'] == values['frames'] and values['failures'] == 0
                and (not marker or values['frames'] >= math.ceil(360 * .99))))
            (directory / 'metrics.json').write_text(json.dumps(result, indent=2) + '\n')
            return result
        if line.startswith('MEDIA_'):
            values = dict(re.findall(r'(\w+)=([-\d.]+)', line))
            if line.startswith('MEDIA_FRAME'):
                frames.append({key: float(value) for key, value in values.items()})
            elif line.startswith('MEDIA_RESULT'):
                completion = values
            elif line.startswith('MEDIA_TIMING'):
                frequency = float(values['qpc_frequency'])
    surface = next((line.split()[1] for line in lines if line.startswith('MEDIA_SURFACE ')), None)
    result = {'completed': bool(completion and completion['ended'] == '1' and completion['error'] == '0'),
              'surface': surface, 'framesPresented': int(completion['frames']) if completion and surface == 'swapchain' else None,
              'framesTransferred': len(frames), 'transferFailures': int(completion['failures']) if completion else None,
              'maxFrameGapMS': max((b['wall_ms'] - a['wall_ms'] for a, b in zip(frames, frames[1:])), default=None),
              'audio': [], 'marker': marker}
    for file in directory.glob('render-*.json'):
        info = json.loads(file.read_text())
        samples = array.array('f')
        samples.frombytes(file.with_suffix('.f32').read_bytes())
        channels = info['channels']
        if info['overflow'] or info['unsupported'] or not channels or len(samples) % channels:
            result['audio'].append({'valid': False, 'metadata': info})
            continue
        ticks = list(struct.iter_unpack('<dQII', file.with_suffix('.timing').read_bytes()))
        amplitude = [max(abs(value) for value in samples[i:i + channels]) for i in range(0, len(samples), channels)]
        active = [i for i, value in enumerate(amplitude) if value != 0]
        gaps = []
        start = None
        if active:
            for i in range(active[0], active[-1] + 1):
                if amplitude[i] == 0 and start is None:
                    start = i
                elif amplitude[i] != 0 and start is not None:
                    if i - start >= 128:
                        gaps.append({'startFrame': start, 'frames': i - start, 'ms': (i - start) * 1000 / info['rate']})
                    start = None
        audio = {'valid': bool(active and ticks), 'seconds': len(amplitude) / info['rate'],
                 'internalSilentRegions': gaps,
                 'clockDiscontinuities': sum(abs(b[0] - a[0] - a[2]) > .5 for a, b in zip(ticks, ticks[1:])),
                 'callbackErrors': sum(tick[3] != 0 for tick in ticks), 'markerOffsetsMS': []}
        if marker and active and ticks and frequency and frames:
            # Capture hostTime is mach_absolute_time; Wine QPC is continuous time.
            # The native tap records the sleep offset and timebase at startup.
            positions = [0]
            for tick in ticks:
                positions.append(positions[-1] + tick[2])
            pulses = []
            previous = -info['rate']
            for position, value in enumerate(amplitude):
                if value > .35 and position - previous > info['rate'] * .5:
                    pulses.append(position)
                    previous = position
            for second, position in enumerate(pulses):
                if second >= 12:
                    break
                tick_index = min(len(ticks) - 1, bisect.bisect_right(positions, position) - 1)
                tick = ticks[tick_index]
                audio_ns = (tick[1] + info['continuousOffset']) * info['timebaseNumer'] / info['timebaseDenom']
                audio_ns += (position - positions[tick_index]) * 1e9 / info['rate']
                video = min(frames, key=lambda frame: abs(frame['pts_100ns'] / 1e7 - second))
                if abs(video['pts_100ns'] / 1e7 - second) < .05:
                    audio['markerOffsetsMS'].append((audio_ns - video['qpc'] * 1e9 / frequency) / 1e6)
            offsets = audio['markerOffsetsMS']
            audio['avDriftMS'] = offsets[-1] - offsets[0] if len(offsets) >= 10 else None
        result['audio'].append(audio)
    if marker:
        audio = [value for value in result['audio'] if value['valid']]
        result['passesSyntheticGate'] = bool(result['completed'] and result['transferFailures'] == 0
            and result['framesTransferred'] >= math.ceil(360 * .99)
            and result['maxFrameGapMS'] is not None and result['maxFrameGapMS'] <= 100
            and len(audio) == 1 and not audio[0]['internalSilentRegions']
            and not audio[0]['clockDiscontinuities'] and not audio[0]['callbackErrors']
            and audio[0].get('avDriftMS') is not None and abs(audio[0]['avDriftMS']) <= 100)
        if surface == 'audio-only':
            result['passesSyntheticGate'] = bool(result['completed'] and len(audio) == 1
                and not audio[0]['internalSilentRegions'] and not audio[0]['clockDiscontinuities']
                and not audio[0]['callbackErrors'] and abs(audio[0]['seconds'] - 12) <= .25)
    (directory / 'metrics.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def replay(args):
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Use a new output directory; measurements are immutable')
    prepare(output / 'fixtures')
    runtime = args.runtime.resolve()
    clip = args.clip.resolve() if args.clip else output / 'fixtures/marker.mp4'
    original_clip = clip
    if args.audio_only:
        clip = output / 'fixtures/audio.m4a'
        # Preserve the encoded AAC stream; remove video without re-encoding audio.
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', original_clip,
             '-vn', '-c:a', 'copy', clip])
    metadata = {'runtimeLoaderSHA256': hashlib.sha256((runtime / 'lib/wine/x86_64-unix/wine').read_bytes()).hexdigest(),
                'renderer': args.renderer, 'clipSHA256': hashlib.sha256(clip.read_bytes()).hexdigest(),
                'synthetic': not bool(args.clip), 'os': subprocess.check_output(['sw_vers'], text=True),
                'path': 'source-reader' if args.source_reader else 'media-engine',
                'originalClipSHA256': hashlib.sha256(original_clip.read_bytes()).hexdigest(),
                'surface': 'audio-only' if args.audio_only else 'transfer-only' if args.transfer_only else 'swapchain',
                'hardware': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True)}
    (output / 'run.json').write_text(json.dumps(metadata, indent=2) + '\n')
    warm = output / 'warm-prefix'
    reports = []
    for mode in ['cold', 'warm']:
        for number in range(1, args.runs + 1):
            directory = output / f'{mode}-{number}'
            directory.mkdir()
            prefix = directory / 'prefix' if mode == 'cold' else warm
            overlay = runtime / f'renderers/{args.renderer}/wine'
            env = dict(os.environ, WINEPREFIX=str(prefix), WINELOADER=str(runtime / 'bin/wine'),
                       WINESERVER=str(runtime / 'bin/wineserver'), WINEDEBUG='err+all,fixme-all',
                       DYLD_FALLBACK_LIBRARY_PATH=f'{runtime}/Libraries:{runtime}/Libraries/GStreamer.framework/Libraries:{runtime}/lib/wine/x86_64-unix:/usr/lib',
                       GST_PLUGIN_PATH=str(runtime / 'Libraries/GStreamer.framework/Libraries/gstreamer-1.0'),
                       GST_REGISTRY=str(output / 'gst-registry.bin'), MVK_CONFIG_LOG_LEVEL='0',
                       WINEDLLPATH_PREPEND=str(overlay), WINEDLLOVERRIDES='dxgi,d3d11,d3d10core,lsteamclient=b',
                       NP_AUDIO_CAPTURE_DIR=str(directory), DYLD_INSERT_LIBRARIES=str(output / 'fixtures/audio-capture.dylib'))
            try:
                with (directory / 'probe.log').open('wb') as log:
                    command = [str(runtime / 'bin/wine'), str(output / 'fixtures/media-playback.exe'), 'Z:' + str(clip).replace('/', '\\')]
                    if args.transfer_only:
                        command.append('--transfer-only')
                    elif args.audio_only:
                        command.append('--audio-only')
                    elif args.source_reader:
                        command.append('--source-reader')
                    outcome = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
                metrics = analyze(directory, marker=not bool(args.clip))
                reports.append({'mode': mode, 'run': number, 'exit': outcome.returncode, 'metrics': metrics})
                print(mode, number, 'exit', outcome.returncode, json.dumps(metrics), flush=True)
            finally:
                # Only this disposable prefix's server; never the user's game server.
                subprocess.run([env['WINESERVER'], '-k'], env=env, timeout=10, check=True)
    (output / 'qualification.json').write_text(json.dumps(reports, indent=2) + '\n')
    gate = 'passesAllocationGate' if args.source_reader else 'passesSyntheticGate'
    if any(report['exit'] or (not args.clip and not report['metrics'].get(gate)) for report in reports):
        raise RuntimeError('Media qualification failed; retain the individual measurements')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    test = commands.add_parser('run')
    test.add_argument('--runtime', type=Path, required=True)
    test.add_argument('--output', type=Path, required=True)
    test.add_argument('--clip', type=Path)
    test.add_argument('--renderer', choices=['dxmt', 'dxvk'], default='dxmt')
    test.add_argument('--runs', type=int, default=3, choices=range(1, 4))
    surface = test.add_mutually_exclusive_group()
    surface.add_argument('--transfer-only', action='store_true', help='Replay the earlier offscreen-transfer baseline without a swapchain')
    surface.add_argument('--audio-only', action='store_true', help='Replay the same encoded audio without video decoding or presentation')
    surface.add_argument('--source-reader', action='store_true', help='Check Source Reader DXGI texture sharing separately from playback timing')
    inspect = commands.add_parser('analyze')
    inspect.add_argument('directory', type=Path)
    inspect.add_argument('--marker', action='store_true')
    args = parser.parse_args()
    if args.command == 'run':
        replay(args)
    else:
        print(json.dumps(analyze(args.directory, args.marker), indent=2))


if __name__ == '__main__':
    main()
