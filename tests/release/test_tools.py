"""Release-tool checks, counted separately from the six interop tool tests."""
import importlib.util
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))

spec = importlib.util.spec_from_file_location('release_check', Path(__file__).resolve().parents[2] / 'scripts/release_check.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ArchiveSafety(unittest.TestCase):
    def archive(self, records):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'package.zip'
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(path, 'w') as z:
                for name, data in records:
                    if isinstance(name, str):
                        info = zipfile.ZipInfo('entry')
                        info.filename = info.orig_filename = name
                        name = info
                    z.writestr(name, data)
        return path

    def test_exact_bytes(self):
        self.assertEqual(release.members(self.archive([('source.mbt', b'line\n'), ('fixture.bin', b'\x00\xff')])),
                         {'source.mbt': b'line\n', 'fixture.bin': b'\x00\xff'})

    def test_duplicate_alias(self):
        for names in [('a', 'a'), ('A', 'a')]:
            with self.assertRaises(AssertionError):
                release.members(self.archive([(name, b'x') for name in names]))

    def test_path_escape(self):
        for name in ('../escape', '/absolute', 'C:/escape', 'a\\b'):
            with self.assertRaises(AssertionError):
                release.members(self.archive([(name, b'x')]))

    def test_link(self):
        info = zipfile.ZipInfo('link')
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(AssertionError):
            release.members(self.archive([(info, b'target')]))


if __name__ == '__main__':
    unittest.main()
