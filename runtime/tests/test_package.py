"""Exercise package consumer failures rather than implementation structure."""
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
import struct

spec = importlib.util.spec_from_file_location('runtime_package', Path(__file__).parents[1] / 'package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def archive(self, entries):
        target = self.root / 'input.tar'
        with tarfile.open(target, 'w') as archive:
            for name, body, link in entries:
                entry = tarfile.TarInfo(name)
                if link:
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = link
                    archive.addfile(entry)
                else:
                    entry.size = len(body)
                    archive.addfile(entry, io.BytesIO(body))
        return target

    def test_normal_package_relocates_and_keeps_internal_link(self):
        archive = self.archive([('Wine/bin/loader', b'engine', None), ('Wine/bin/wine', b'', 'loader')])
        destination = self.root / 'path with spaces'
        package.extract(archive, destination)
        self.assertEqual((destination / 'Wine/bin/wine').read_bytes(), b'engine')
        self.assertTrue((destination / 'Wine/bin/wine').is_symlink())

    def test_archive_traversal_leaves_no_external_file(self):
        archive = self.archive([('../escaped', b'bad', None)])
        with self.assertRaises(ValueError):
            package.extract(archive, self.root / 'staging')
        self.assertFalse((self.root / 'escaped').exists())

    def test_archive_link_cannot_escape(self):
        archive = self.archive([('Wine/link', b'', '../../outside'), ('Wine/link/file', b'bad', None)])
        with self.assertRaises(ValueError):
            package.extract(archive, self.root / 'staging')
        self.assertFalse((self.root / 'outside/file').exists())

    def test_inventory_rejects_external_dependency(self):
        wine = self.root / 'Wine'
        wine.mkdir()
        (wine / 'Libraries').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            package.inventory(wine)

    def test_inventory_detects_tampered_payload(self):
        wine = self.root / 'Wine'
        wine.mkdir()
        (wine / 'ntdll').write_bytes(b'qualified')
        manifest = package.inventory(wine)
        (wine / 'ntdll').write_bytes(b'other build')
        with self.assertRaises(ValueError):
            package.verify_inventory(wine, manifest)

    def test_inventory_rejects_unexpected_file(self):
        wine = self.root / 'Wine'
        wine.mkdir()
        (wine / 'loader').write_bytes(b'qualified')
        manifest = package.inventory(wine)
        (wine / 'unreviewed').write_bytes(b'extra')
        with self.assertRaises(ValueError):
            package.verify_inventory(wine, manifest)

    def host_binary(self, cpu=0x1000007, dependency='/usr/lib/libSystem.B.dylib'):
        name = dependency.encode() + b'\0'
        size = (24 + len(name) + 7) & ~7
        command = struct.pack('<6I', 0xc, size, 24, 0, 0, 0) + name
        command += b'\0' * (size - len(command))
        version = struct.pack('<4I', 0x24, 16, 0x1b0000, 0x1b0000)
        header = struct.pack('<8I', 0xfeedfacf, cpu, 3, 2, 2, size + 16, 0, 0)
        path = self.root / 'loader'
        path.write_bytes(header + command + version)
        return path

    def test_binary_contract_rejects_non_intel_host(self):
        self.host_binary(cpu=0x100000c)
        with self.assertRaisesRegex(ValueError, 'architecture'):
            package.validate_binaries(self.root)

    def test_binary_contract_rejects_build_machine_dependency(self):
        self.host_binary(dependency='/opt/homebrew/lib/unbundled.dylib')
        with self.assertRaisesRegex(ValueError, 'absolute library'):
            package.validate_binaries(self.root)

    def test_binary_contract_rejects_missing_relative_library(self):
        self.host_binary(dependency='@rpath/unbundled.dylib')
        with self.assertRaisesRegex(ValueError, 'Unresolved library'):
            package.validate_binaries(self.root)

    def test_binary_contract_reports_actual_minimum_os(self):
        self.host_binary()
        self.assertEqual(package.validate_binaries(self.root), '27.0.0')

    def test_binary_contract_rejects_wrong_windows_architecture(self):
        self.host_binary()
        path = self.root / 'i386-windows/ntdll.dll'
        path.parent.mkdir()
        header = bytearray(128)
        header[:2] = b'MZ'
        struct.pack_into('<I', header, 0x3c, 64)
        header[64:70] = b'PE\0\0' + struct.pack('<H', 0x8664)
        path.write_bytes(header)
        with self.assertRaisesRegex(ValueError, 'PE architecture'):
            package.validate_binaries(self.root)


if __name__ == '__main__':
    unittest.main()
