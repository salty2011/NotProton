#!/usr/bin/env python3
"""Build an isolated free Wine candidate; never install over a user's runner."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

repo = Path(__file__).resolve().parent.parent
inputs = json.loads((repo / 'runtime/inputs.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--components', type=Path, required=True, help='Verified dependency assembly from package.py components')
parser.add_argument('--headers', type=Path, default=Path('/opt/homebrew'))
parser.add_argument('--jobs', type=int, default=8)
parser.add_argument('--stage-only', action='store_true', help='Stage an already built candidate')
args = parser.parse_args()
work = args.work.resolve()
components = args.components.resolve()
headers = args.headers.resolve()
if any(c.isspace() for c in str(work)) or args.jobs < 1:
    parser.error('Use a work path without whitespace and a positive job count')
if not (components / 'notproton-provider').is_file() or not (components / 'Libraries').is_dir():
    parser.error('--components must name the verified free dependency assembly')
work.mkdir(parents=True, exist_ok=True)
source = work / 'source/sources/wine'
build = work / 'wine-build'
engine = work / 'wine-built'
deps = work / 'deps'
if not deps.exists():
    deps.symlink_to(components / 'Libraries', target_is_directory=True)

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def obtain(key, name):
    item = inputs[key]
    path = work / name
    if not path.exists() or digest(path) != item['sha256']:
        temporary = path.with_suffix(path.suffix + '.part')
        urllib.request.urlretrieve(item['url'], temporary)
        if digest(temporary) != item['sha256']:
            raise RuntimeError('Checksum mismatch: ' + key)
        temporary.replace(path)
    return path

def run(command, cwd=None, env=None, log=None):
    print('Running:', command[0], flush=True)
    if log:
        with (work / log).open('wb') as output:
            subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run(command, cwd=cwd, env=env, check=True)

wine_archive = obtain('wine', 'crossover-sources-26.3.0.tar.gz')
renderer_archive = obtain('dxmt', 'dxmt-v0.80-builtin.tar.gz')
patch = obtain('dll_path_prepend_patch', 'winedllpath-prepend.patch')
dxmt_license = obtain('dxmt_license', 'dxmt-v0.80-LICENSE')
if not source.exists():
    (work / 'source').mkdir(exist_ok=True)
    run(['tar', '-xzf', str(wine_archive), '-C', str(work / 'source'), 'sources/wine'])
if not (source / 'dlls/ntdll/notproton_steam.h').exists():
    run([sys.executable, str(repo / 'runtime/prepare-steam-hook.py'), str(source)])
if 'WINEDLLPATH_PREPEND' not in (source / 'dlls/ntdll/unix/loader.c').read_text():
    run(['patch', '-d', str(source), '-p1', '-i', str(patch)])

media_lib = deps / 'GStreamer.framework/Versions/1.0/lib'
env = dict(os.environ, PATH=str(headers / 'opt/bison/bin') + ':' + str(headers / 'bin') + ':' + os.environ['PATH'],
           DYLD_FALLBACK_LIBRARY_PATH=f'{deps}:{media_lib}:/usr/lib',
           GNUTLS_CFLAGS=f'-I{headers}/include', GNUTLS_LIBS=f'-L{deps} -lgnutls',
           FREETYPE_CFLAGS=f'-I{headers}/include/freetype2', FREETYPE_LIBS=f'-L{deps} -lfreetype',
           SDL2_CFLAGS=f'-I{headers}/include/SDL2', SDL2_LIBS=f'-L{deps} -lSDL2',
           GSTREAMER_LIBS=f'-L{media_lib} -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0',
           ac_cv_lib_soname_vulkan='libMoltenVK.dylib', ac_cv_lib_soname_SDL2='libSDL2.dylib',
           ac_cv_lib_soname_freetype='libfreetype.dylib', ac_cv_lib_soname_gnutls='libgnutls.dylib')
# Libraries are the matching x86_64 Sikarugir dependencies; headers come from the
# local development toolchain. Record both instead of claiming byte reproducibility.
if not args.stage_only:
    env['GSTREAMER_CFLAGS'] = subprocess.check_output(['pkg-config', '--cflags', 'gstreamer-1.0', 'gstreamer-video-1.0', 'gstreamer-audio-1.0', 'gstreamer-tag-1.0'], env=env, text=True).strip()
    build.mkdir(exist_ok=True)
    configure = [str(source / 'configure'), '--host=x86_64-apple-darwin', '--enable-archs=i386,x86_64', '--with-mingw',
                 '--without-x', '--with-freetype', '--with-gnutls', '--with-gstreamer', '--with-sdl', '--without-usb',
                 '--without-krb5', '--without-netapi', '--without-cups', '--without-fontconfig', '--disable-tests',
                 '--prefix=' + str(engine), 'CC=clang -arch x86_64', 'CXX=clang++ -arch x86_64', 'CFLAGS=-O2 -mmacosx-version-min=14.0']
    run(configure, build, env, 'configure-complete.log')
    # GNU make preserves the library environment for Wine's font-generation tool.
    run(['gmake', '-j' + str(args.jobs)], build, env, 'wine-complete-build.log')
    run(['gmake', 'install-lib'], build, env, 'wine-complete-install.log')
    (build / 'dlls/lsteamclient').mkdir(parents=True, exist_ok=True)
    (source / 'dlls/lsteamclient').mkdir(exist_ok=True)
    env.update(WINE_BUILD=str(build), WINE_SRC_REL='../source/sources/wine', CX_ROOT=str(engine))
    run(['bash', str(repo / 'lsteamclient/build.sh'), '--unix'], env=env, log='bridge-source-build.log')

renderer = work / 'dxmt-v0.80'
if not (renderer / 'v0.80').exists():
    renderer.mkdir(exist_ok=True)
    run(['tar', '-xzf', str(renderer_archive), '-C', str(renderer)])
for arch in ['x86_64', 'i386']:
    target = engine / 'lib/wine' / (arch + '-windows')
    shutil.copy2(build / 'dlls/ntdll' / (arch + '-windows') / 'ntdll.dll', target / 'ntdll.dll')
    shutil.copy2(repo / 'app/Sources/NotProtonApp/Resources/payload/bridge' / (arch + '-windows-lsteamclient.dll'), target / 'lsteamclient.dll')
    shutil.copy2(renderer / 'v0.80' / (arch + '-windows') / 'winemetal.dll', target / 'winemetal.dll')
for file in ['ntdll/ntdll.so', 'lsteamclient/lsteamclient.so']:
    shutil.copy2(build / 'dlls' / file, engine / 'lib/wine/x86_64-unix' / Path(file).name)
shutil.copy2(renderer / 'v0.80/x86_64-unix/winemetal.so', engine / 'lib/wine/x86_64-unix/winemetal.so')
for item in ['Libraries', 'vulkan']:
    if not (engine / item).exists():
        (engine / item).symlink_to(components / item, target_is_directory=True)
for item in ['mono', 'gecko']:
    destination = engine / 'share/wine' / item
    if not destination.exists():
        run(['cp', '-cR', str(components / 'share/wine' / item), str(destination)])
shutil.copy2(source / 'COPYING.LIB', engine / 'COPYING.LIB')
shutil.copy2(repo / 'LICENSE', engine / 'LICENSE.NotProton')
shutil.copy2(dxmt_license, engine / 'LICENSE.DXMT')

def tool_version(command):
    try:
        return subprocess.check_output(command, env=env, text=True, stderr=subprocess.STDOUT).splitlines()[0]
    except (OSError, subprocess.CalledProcessError, IndexError):
        return 'unavailable'

manifest = {'experimental': True, 'inputs': inputs, 'component_root': str(components),
            'headers': str(headers), 'toolchain': {key: tool_version(command) for key, command in {
                'clang': ['clang', '--version'], 'gmake': ['gmake', '--version'],
                'macos_sdk': ['xcrun', '--show-sdk-version'],
                'gstreamer_headers': ['pkg-config', '--modversion', 'gstreamer-1.0']}.items()},
            'recipe_sha256': {str(f.relative_to(repo)): digest(f) for f in [repo / 'runtime/build.py', repo / 'runtime/prepare-steam-hook.py', repo / 'ntdll-patch/detour.c', repo / 'ntdll-patch/detour32.c', repo / 'lsteamclient/build.sh', repo / 'lsteamclient/fetch.sh']}, 'notproton_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'files': {str(file.relative_to(engine)): digest(file) for file in [engine / 'bin/wine', engine / 'bin/wineserver',
                      engine / 'lib/wine/x86_64-windows/ntdll.dll', engine / 'lib/wine/i386-windows/ntdll.dll',
                      engine / 'lib/wine/x86_64-windows/lsteamclient.dll', engine / 'lib/wine/i386-windows/lsteamclient.dll',
                      engine / 'lib/wine/x86_64-unix/winemetal.so',
                      engine / 'lib/wine/x86_64-unix/ntdll.so', engine / 'lib/wine/x86_64-unix/lsteamclient.so']}}
(engine / 'notproton-source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Experimental candidate:', engine)
print('Keep the source tree and licenses. This does not install or select a Steam tool.')
