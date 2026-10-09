#!/usr/bin/env python3
"""Qualify packaged Wine namespace and TLS behavior without a Steam account."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    fixtures = Path(__file__).resolve().parent
    env = dict(os.environ, WINEPREFIX=str(output / 'prefix'), WINELOADER=str(runtime / 'bin/wine'),
               WINESERVER=str(runtime / 'bin/wineserver'), WINEDEBUG='err+all,fixme-all',
               DYLD_FALLBACK_LIBRARY_PATH=f'{runtime}/Libraries:{runtime}/Libraries/GStreamer.framework/Libraries:{runtime}/lib/wine/x86_64-unix:/usr/lib',
               GST_PLUGIN_PATH=str(runtime / 'Libraries/GStreamer.framework/Libraries/gstreamer-1.0'),
               MVK_CONFIG_LOG_LEVEL='0')
    results = []
    try:
        for name in ['path-namespace', 'https']:
            for arch, compiler in [('x86_64', 'x86_64-w64-mingw32-gcc'), ('i386', 'i686-w64-mingw32-gcc')]:
                executable = output / f'{name}-{arch}.exe'
                command = [compiler, '-Wall', '-Wextra', '-Werror', str(fixtures / (name + '.c')), '-o', str(executable)]
                if name == 'https':
                    command.append('-lwinhttp')
                subprocess.run(command, check=True)
                log = output / f'{name}-{arch}.log'
                with log.open('wb') as stream:
                    process = subprocess.run([str(runtime / 'bin/wine'), str(executable)], env=env,
                                             stdout=stream, stderr=subprocess.STDOUT, timeout=120)
                signals = [line for line in log.read_text(errors='replace').splitlines() if 'PASS' in line or 'FAIL' in line]
                results.append({'probe': name, 'architecture': arch, 'exit': process.returncode, 'signals': signals})
                print(json.dumps(results[-1]), flush=True)
                if process.returncode:
                    raise RuntimeError(f'{name}/{arch} failed; retain the report')
    finally:
        subprocess.run([env['WINESERVER'], '-k'], env=env, timeout=10, check=True)
        results.append({'probe': 'steam-integration', 'status': 'skipped',
                        'reason': 'Requires a running user-owned Steam client and separately qualified gameplay; CI has no account.'})
        (output / 'qualification.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
