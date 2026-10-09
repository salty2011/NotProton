#!/usr/bin/env python3
"""Build a quarantined free runtime, matching source bundle and qualification report."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request

import package

REPO = Path(__file__).resolve().parent.parent


def obtain(item, cache):
    target = cache / item['file']
    if target.exists() and package.digest(target) == item['sha256']:
        return target
    cache.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + '.part')
    try:
        urllib.request.urlretrieve(item['url'], partial)
        if package.digest(partial) != item['sha256']:
            raise ValueError('Unverified dependency input: ' + item['file'])
        partial.replace(target)
    finally:
        partial.unlink(missing_ok=True)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--headers', type=Path, default=Path('/opt/homebrew'))
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--id', required=True, help='Fresh immutable identity, e.g. freewine-26.3_ci-<commit>-<run>')
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists():
        parser.error('--work must be a new directory; do not reuse an engine identity')
    work.mkdir(parents=True)
    pins = json.loads((REPO / 'runtime/component-inputs.json').read_text())
    archives = {key: obtain(value, args.cache.resolve()) for key, value in pins.items()}
    components = work / 'components'
    package.prepare_components(archives['engine'], archives['template'], components)
    subprocess.run([sys.executable, str(REPO / 'runtime/build.py'), '--work', str(work / 'build'),
                    '--components', str(components), '--headers', str(args.headers), '--jobs', str(args.jobs)], check=True)
    engine = work / 'build/wine-built'
    provenance = json.loads((engine / 'notproton-source-manifest.json').read_text())
    for name in ['component_root', 'headers', 'files']:
        provenance.pop(name, None)
    provenance['dependencyInputs'] = pins
    provenance['headerInventorySHA256'] = hashlib.sha256(json.dumps({
        str(path.relative_to(args.headers)): package.digest(path)
        for path in args.headers.rglob('*.h') if path.is_file()
    }, sort_keys=True).encode()).hexdigest()
    provenance['dependencySourceReview'] = 'pending: match every dependency binary to corresponding source and notices before publication'
    manifest = work / 'provenance.json'
    manifest.write_text(json.dumps(provenance, indent=2) + '\n')
    artifacts = work / 'artifacts'
    build_args = argparse.Namespace(engine=engine, components=components,
        renderer=work / 'build/dxmt-v0.80/v0.80', provenance=manifest, output=artifacts,
        id=args.id, version=args.id.removeprefix('freewine-'))
    package.build(build_args)
    # Modified Wine source includes the generated Steam hook and prepend patch.
    # Keep the original source and exact integration sources separately too.
    sources = work / 'sources'
    sources.mkdir()
    shutil.copy2(work / 'build/crossover-sources-26.3.0.tar.gz', sources)
    with tarfile.open(sources / 'modified-wine.tar.xz', 'w:xz', preset=1) as archive:
        archive.add(work / 'build/source/sources/wine', arcname='wine')
    with (sources / 'notproton-integration.tar').open('wb') as output:
        subprocess.run(['git', 'archive', 'HEAD', 'runtime', 'runtime-tests', 'ntdll-patch',
                        'lsteamclient', 'steam-shim', 'bridge', 'LICENSE'], cwd=REPO, stdout=output, check=True)
    shutil.copy2(manifest, sources / 'provenance.json')
    (sources / 'DEPENDENCIES-PENDING.md').write_text(
        '# Publication gate\n\nWine, NotProton and DXMT sources/licenses are pinned. '
        'Dependency archives also have pinned binary digests. Their full corresponding source and notices '
        'must be matched and reviewed before any binary package is marked distribution-ready. '
        'This build does not publish its binary or promote its catalog into an app.\n')
    relocated = work / 'relocated runtime'
    package.extract(artifacts / (args.id + '.tar.xz'), relocated)
    package.verify(relocated)
    subprocess.run([sys.executable, str(REPO / 'runtime-tests/qualify.py'),
                    '--runtime', str(relocated / 'Wine'), '--output', str(work / 'qualification')], check=True)


if __name__ == '__main__':
    main()
