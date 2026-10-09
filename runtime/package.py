#!/usr/bin/env python3
"""Create and validate relocatable free runtime packages from reviewed inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import tarfile
import tempfile

SCHEMA = 1


def macho(path):
    """Read the Intel slice and its loader contract without executing binaries."""
    with path.open('rb') as stream:
        magic = stream.read(4)
        offset = 0
        if magic in [b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf']:
            count = struct.unpack('>I', stream.read(4))[0]
            wide = magic[-1] == 0xbf
            size = 32 if wide else 20
            slices = [stream.read(size) for _ in range(count)]
            intel = [entry for entry in slices if struct.unpack('>I', entry[:4])[0] == 0x1000007]
            if not intel:
                raise ValueError('Mach-O lacks x86_64: ' + str(path))
            offset = struct.unpack('>Q' if wide else '>I', intel[0][8:16 if wide else 12])[0]
            stream.seek(offset)
            magic = stream.read(4)
        if magic not in [b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe']:
            return None
        header = stream.read(28 if magic[0] == 0xcf else 24)
        cpu, _, _, count, command_size, _ = struct.unpack('<6I', header[:24])
        if cpu != 0x1000007:
            raise ValueError('Unsupported Mach-O architecture: ' + str(path))
        commands = stream.read(command_size)
    result = {'dependencies': [], 'rpaths': [], 'minimum': (0, 0, 0)}
    position = 0
    for _ in range(count):
        command, size = struct.unpack_from('<II', commands, position)
        if size < 8 or position + size > len(commands):
            raise ValueError('Invalid Mach-O load command: ' + str(path))
        body = commands[position:position + size]
        if command in [0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023, 0x8000001c]:
            string_offset = struct.unpack_from('<I', body, 8)[0]
            value = body[string_offset:].split(b'\0', 1)[0].decode('utf-8')
            result['rpaths' if command == 0x8000001c else 'dependencies'].append(value)
        elif command in [0x24, 0x32]:
            version = struct.unpack_from('<I', body, 12 if command == 0x32 else 8)[0]
            result['minimum'] = max(result['minimum'], (version >> 16, (version >> 8) & 255, version & 255))
        position += size
    return result


def validate_binaries(root):
    """Reject external dependencies and PE/host architecture mismatches."""
    root = Path(root).resolve()
    minimum = (0, 0, 0)
    count = 0
    fallback = [root / 'Libraries', root / 'Libraries/GStreamer.framework/Libraries',
                root / 'lib/wine/x86_64-unix']
    for folder, _, files in os.walk(root, followlinks=False):
        for name in files:
            path = Path(folder) / name
            if path.is_symlink():
                continue
            with path.open('rb') as stream:
                magic = stream.read(4)
                if magic[:2] == b'MZ' and ('i386-windows' in path.parts or 'x86_64-windows' in path.parts):
                    stream.seek(0x3c)
                    pe_offset = struct.unpack('<I', stream.read(4))[0]
                    stream.seek(pe_offset)
                    header = stream.read(6)
                    expected = 0x14c if 'i386-windows' in path.parts else 0x8664
                    if len(header) != 6 or header[:4] != b'PE\0\0' or struct.unpack('<H', header[4:])[0] != expected:
                        raise ValueError('Incorrect PE architecture: ' + str(path.relative_to(root)))
            if magic not in [b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf']:
                continue
            contract = macho(path)
            minimum = max(minimum, contract['minimum'])
            count += 1
            expand = lambda value: Path(value.replace('@loader_path', str(path.parent)).replace('@executable_path', str(root / 'lib/wine/x86_64-unix')))
            search = fallback + [expand(value) for value in contract['rpaths'] if not value.startswith('@rpath')]
            for dependency in contract['dependencies']:
                if dependency.startswith(('/usr/lib/', '/System/Library/')):
                    continue
                if dependency.startswith('/'):
                    raise ValueError('Non-system absolute library: ' + dependency)
                candidates = ([base / dependency[7:] for base in search] if dependency.startswith('@rpath/')
                              else [expand(dependency)] if dependency.startswith('@')
                              else [base / dependency for base in search] + [path.parent / dependency])
                internal = []
                for candidate in candidates:
                    try:
                        candidate.resolve().relative_to(root)
                    except (ValueError, RuntimeError):
                        continue
                    internal.append(candidate)
                if not any(candidate.is_file() for candidate in internal):
                    raise ValueError('Unresolved library in ' + str(path.relative_to(root)) + ': ' + dependency)
    if not count:
        raise ValueError('Runtime contains no Mach-O engine')
    return '.'.join(str(part) for part in minimum)


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def relative(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or '\\' in name or '\0' in name:
        raise ValueError('Unsafe package path: ' + name)
    return path


def contained(path, root):
    try:
        path.resolve().relative_to(root.resolve())
    except (ValueError, RuntimeError):
        raise ValueError('Package dependency escapes root: ' + str(path)) from None


def extract(archive, destination):
    """Validate the whole archive before creating files; links are created last."""
    destination = Path(destination)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = set()
        links = set()
        for member in members:
            path = relative(member.name)
            name = str(path)
            if name in names:
                raise ValueError('Repeated archive path: ' + name)
            names.add(name)
            if member.issym():
                if PurePosixPath(member.linkname).is_absolute() or '\\' in member.linkname:
                    raise ValueError('Absolute or invalid archive link: ' + name)
                contained(destination / path.parent / member.linkname, destination)
                links.add(name)
            elif not member.isfile() and not member.isdir():
                raise ValueError('Unsupported archive entry: ' + name)
        for member in members:
            path = relative(member.name)
            if any(str(parent) in links for parent in path.parents):
                raise ValueError('Archive writes through a symlink: ' + member.name)
        destination.mkdir(parents=True, exist_ok=False)
        for member in members:
            target = destination / relative(member.name)
            contained(target.parent, destination)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('xb') as output, source.extractfile(member) as body:
                    shutil.copyfileobj(body, output)
                target.chmod(member.mode & 0o777)
        for member in members:
            if member.issym():
                target = destination / relative(member.name)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(member.linkname)


def inventory(root):
    root = Path(root)
    result = {}
    for folder, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(folder) / name
            key = path.relative_to(root).as_posix()
            if path.is_symlink():
                target = os.readlink(path)
                if Path(target).is_absolute():
                    raise ValueError('External package symlink: ' + key)
                contained(path, root)
                if not path.exists():
                    raise ValueError('Broken package symlink: ' + key)
                result[key] = {'kind': 'link', 'target': target}
            elif path.is_file():
                result[key] = {'kind': 'file', 'sha256': digest(path),
                               'mode': stat.S_IMODE(path.stat().st_mode)}
            elif not path.is_dir():
                raise ValueError('Unsupported package file: ' + key)
    return dict(sorted(result.items()))


def verify_inventory(root, expected):
    actual = inventory(root)
    if actual != expected:
        wrong = sorted(key for key in actual.keys() | expected.keys() if actual.get(key) != expected.get(key))
        raise ValueError('Package payload differs: ' + ', '.join(wrong[:8]))


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def prepare_components(engine_archive, template_archive, destination):
    """Reproduce the free library assembly from verified public archives."""
    inputs = json.loads(Path(__file__).with_name('component-inputs.json').read_text())
    for key, archive in [('engine', engine_archive), ('template', template_archive)]:
        if digest(archive) != inputs[key]['sha256']:
            raise ValueError('Unverified component archive: ' + key)
    if destination.exists():
        raise ValueError('Component destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.components-', dir=destination.parent) as temporary:
        temporary = Path(temporary)
        extract(engine_archive, temporary / 'engine')
        extract(template_archive, temporary / 'template')
        engine = temporary / 'engine/wswine.bundle'
        template = temporary / 'template/Template-1.0.21.app/Contents'
        frameworks = template / 'Frameworks'
        prepared = temporary / 'prepared'
        libs = prepared / 'Libraries'
        libs.mkdir(parents=True)
        # Select the free library layer only: no wrapper SDK or proprietary renderer.
        for path in frameworks.iterdir():
            if path.suffix == '.dylib' or path.name == 'GStreamer.framework':
                if path.is_symlink():
                    (libs / path.name).symlink_to(os.readlink(path))
                else:
                    copy(path, libs / path.name)
        nested = libs / 'GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib'
        nested.unlink()
        nested.symlink_to('../../../../libMoltenVK.dylib')
        copy(frameworks / 'renderer/dxvk', prepared / 'renderers/dxvk')
        for arch in ['x86_64-windows', 'i386-windows']:
            copy(prepared / 'renderers/dxvk/wine' / arch / 'd3d9.dll',
                 prepared / 'renderers/d9vk/wine' / arch / 'd3d9.dll')
        for name in ['LICENSE', 'version']:
            copy(prepared / 'renderers/dxvk' / name, prepared / 'renderers/d9vk' / name)
        icd = json.loads((template / 'Resources/vulkan/icd.d/MoltenVK_icd.json').read_text())
        icd['ICD']['library_path'] = '../Libraries/libMoltenVK.dylib'
        (prepared / 'vulkan').mkdir()
        (prepared / 'vulkan/MoltenVK_icd.json').write_text(json.dumps(icd, indent=2) + '\n')
        for name in ['mono', 'gecko']:
            copy(engine / 'share/wine' / name, prepared / 'share/wine' / name)
        (prepared / 'notproton-provider').write_text('sikarugir\n')
        inventory(prepared)
        prepared.rename(destination)
    print('Prepared pinned free dependencies without an installed runtime', flush=True)


def assemble(engine, components, renderer, target):
    """Keep compiled engine and matching bridge; replace borrowed dependencies."""
    copy(engine, target)
    for name in ['Libraries', 'vulkan', 'renderers']:
        path = target / name
        if path.is_symlink():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
    for name in ['Libraries', 'vulkan', 'renderers/dxvk', 'renderers/d9vk']:
        copy(components / name, target / name)
    copy(renderer, target / 'renderers/dxmt/wine')
    for name in ['mono', 'gecko']:
        path = target / 'share/wine' / name
        if path.is_symlink():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
        copy(components / 'share/wine' / name, path)
    (target / 'notproton-provider').write_text('freewine\n')
    metadata = target / 'notproton-source-manifest.json'
    if metadata.exists():
        value = json.loads(metadata.read_text())
        for private in ['component_root', 'headers']:
            value.pop(private, None)
        metadata.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    return inventory(target)


def validate_descriptor(descriptor):
    if descriptor.get('schemaVersion') != SCHEMA:
        raise ValueError('Unsupported runtime package schema')
    if not re.fullmatch(r'freewine-[A-Za-z0-9._-]+', descriptor.get('id', '')):
        raise ValueError('Invalid runtime package identity')
    if descriptor.get('hostArchitecture') != 'x86_64' or descriptor.get('windowsArchitectures') != ['i386', 'x86_64']:
        raise ValueError('Unsupported runtime package architectures')
    files = descriptor.get('files')
    if not isinstance(files, dict) or not files:
        raise ValueError('Runtime package has no inventory')
    for path, entry in files.items():
        relative(path)
        if entry.get('kind') == 'file':
            if not re.fullmatch('[a-f0-9]{64}', entry.get('sha256', '')):
                raise ValueError('Invalid package digest: ' + path)
            if type(entry.get('mode')) is not int or not 0 <= entry['mode'] <= 0o777:
                raise ValueError('Invalid package mode: ' + path)
        elif entry.get('kind') == 'link':
            target = entry.get('target')
            if not isinstance(target, str) or not target or PurePosixPath(target).is_absolute() or '\\' in target or '\0' in target:
                raise ValueError('Invalid package link: ' + path)
        elif entry.get('kind') != 'link':
            raise ValueError('Invalid inventory entry: ' + path)


def verify(package):
    descriptor = json.loads((package / 'package.json').read_text())
    validate_descriptor(descriptor)
    verify_inventory(package / 'Wine', descriptor['files'])
    return descriptor


def build(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / (args.id + '.tar.xz')).exists():
        raise ValueError('Runtime identity already exists; use a new build id')
    policies = json.loads((Path(__file__).parent / 'policy.json').read_text())['runtimes']
    policy = policies.get(args.id)
    # Unreviewed CI compilations must never inherit a release's qualification.
    capabilities = {name: policy['capabilities'][name] if policy else
                    ('dxmt+d9vk' if name == 'automatic' else
                     'unavailable' if name in ('d3dmetal', 'fex') else 'experimental')
                    for name in ('automatic', 'dxmt', 'dxvk', 'wined3d', 'd3dmetal', 'fex')}
    with tempfile.TemporaryDirectory(prefix='.runtime-', dir=output) as temporary:
        stage = Path(temporary) / 'package'
        stage.mkdir()
        files = assemble(args.engine.resolve(), args.components.resolve(), args.renderer.resolve(), stage / 'Wine')
        required = ['lib/wine/x86_64-unix/wine', 'bin/wineserver',
                    'lib/wine/x86_64-unix/ntdll.so', 'lib/wine/x86_64-unix/lsteamclient.so',
                    'lib/wine/x86_64-windows/ntdll.dll', 'lib/wine/i386-windows/ntdll.dll',
                    'lib/wine/x86_64-windows/lsteamclient.dll', 'lib/wine/i386-windows/lsteamclient.dll',
                    'Libraries/libgnutls.dylib', 'Libraries/libfreetype.dylib', 'Libraries/libMoltenVK.dylib',
                    'Libraries/GStreamer.framework/Libraries/gstreamer-1.0/libgstlibav.dylib',
                    'vulkan/MoltenVK_icd.json', 'renderers/dxmt/wine/x86_64-windows/d3d11.dll',
                    'renderers/dxvk/wine/x86_64-windows/d3d11.dll', 'renderers/d9vk/wine/x86_64-windows/d3d9.dll',
                    'COPYING.LIB', 'LICENSE.NotProton', 'LICENSE.DXMT']
        for name in required:
            if not (stage / 'Wine' / name).exists():
                raise ValueError('Missing required package file: ' + name)
        for name in ['lib/wine/x86_64-unix/wine', 'bin/wineserver']:
            if not os.access(stage / 'Wine' / name, os.X_OK):
                raise ValueError('Entry point is not executable: ' + name)
        minimum_os = validate_binaries(stage / 'Wine')
        descriptor = {'schemaVersion': SCHEMA, 'id': args.id, 'displayVersion': args.version,
                      'hostArchitecture': 'x86_64', 'windowsArchitectures': ['i386', 'x86_64'],
                      'minimumAppVersion': '1.1.3', 'minimumMacOSVersion': minimum_os,
                      'bridgeABI': args.id, 'files': files,
                      'criticalFiles': {name: digest(stage / 'Wine' / name) for name in required if not name.startswith('Libraries/')},
                      'capabilities': capabilities,
                      'provenance': json.loads(args.provenance.read_text()),
                      'distributionReady': False}
        validate_descriptor(descriptor)
        serialized = json.dumps(descriptor, indent=2, sort_keys=True) + '\n'
        (stage / 'package.json').write_text(serialized)
        verify(stage)
        archive = output / (args.id + '.tar.xz')
        temporary_archive = Path(temporary) / archive.name
        with tarfile.open(temporary_archive, 'w:xz') as bundle:
            for name in ['package.json', 'Wine']:
                bundle.add(stage / name, arcname=name)
        temporary_archive.replace(archive)
        # The catalog is generated from these final bytes, never a guessed build hash.
        catalog = {'schemaVersion': SCHEMA, 'packages': [{'id': args.id, 'file': archive.name,
                   'sha256': digest(archive), 'size': archive.stat().st_size,
                   'descriptorSHA256': digest(stage / 'package.json'), 'descriptor': descriptor}]}
        (output / (args.id + '.catalog.json')).write_text(json.dumps(catalog, indent=2, sort_keys=True) + '\n')
        print('Packaged', args.id, 'with', len(files), 'inventory entries; distribution review pending', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    package = commands.add_parser('build')
    for name in ['engine', 'components', 'renderer', 'provenance', 'output']:
        package.add_argument('--' + name, type=Path, required=True)
    package.add_argument('--id', required=True)
    package.add_argument('--version', required=True)
    components = commands.add_parser('components')
    components.add_argument('--engine', type=Path, required=True)
    components.add_argument('--template', type=Path, required=True)
    components.add_argument('--output', type=Path, required=True)
    check = commands.add_parser('verify')
    check.add_argument('archive', type=Path)
    args = parser.parse_args()
    if args.command == 'build':
        build(args)
    elif args.command == 'components':
        prepare_components(args.engine, args.template, args.output)
    else:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'package'
            extract(args.archive, root)
            descriptor = verify(root)
            print('Verified', descriptor['id'], 'with', len(descriptor['files']), 'inventory entries')


if __name__ == '__main__':
    main()
