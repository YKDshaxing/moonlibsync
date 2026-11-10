"""Version wiring regressions, separate from the four original ZIP-safety tests."""
import sys,tempfile,unittest,subprocess,os
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
import release_check as release
from release_version import metadata,consumer_metadata,MODULE,VERSION,ARCHIVE

class VersionWiring(unittest.TestCase):
    def test_dynamic_metadata_not_previous_release(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'moon.mod').write_text('name = "YKDshaxing/moonlibsync"\nversion = "0.7.3"\n',encoding='utf8')
            self.assertEqual(metadata(p),(MODULE,'0.7.3'))
    def test_wrong_namespace_and_ambiguous_version_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)
            for text in ['name = "other/project"\nversion = "0.2.0"','name = "YKDshaxing/moonlibsync"\nversion = "0.2.0"\nversion = "0.1.0"']:
                (p/'moon.mod').write_text(text,encoding='utf8')
                with self.assertRaises(AssertionError):metadata(p)
    def test_actual_consumer_dependency_tracks_module(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'consumer';release.make_consumer(p)
            self.assertIn('"'+MODULE+'@'+VERSION+'"',(p/'moon.mod').read_text(encoding='utf8'))
            self.assertNotIn('@0.1.0',(p/'moon.mod').read_text(encoding='utf8'))
    def test_historical_output_directory_is_rejected_before_writing(self):
        root=Path(__file__).resolve().parents[2]
        for relative in ['_build/release-0.1.0','_build/release-0.1.0/nested']:
            env=dict(os.environ,MOONLIBSYNC_RELEASE_DIR=relative)
            result=subprocess.run([sys.executable,'-c',"import sys;sys.path.insert(0,'scripts');import release_check"],cwd=root,env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Historical 0.1.0 evidence is read-only',result.stderr)

    def test_archive_and_cli_assertions_track_module(self):
        root=Path(__file__).resolve().parents[2]
        self.assertEqual(ARCHIVE,'YKDshaxing-moonlibsync-'+VERSION+'.zip')
        self.assertIn('MoonLibSync '+VERSION,(root/'cmd/moonlibsync/args.mbt').read_text(encoding='utf8'))
        self.assertIn('MoonLibSync '+VERSION,(root/'cmd/moonlibsync/main.mbt').read_text(encoding='utf8'))

if __name__=='__main__':unittest.main()
