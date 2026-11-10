"""Focused real product CLI entry for stage A failure propagation (not full matrix)."""
import hashlib,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def main():
    build=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')
    subprocess.run(['moon','--target-dir',str(build),'build','cmd/moonlibsync','--target','native'],cwd=ROOT,check=True)
    exe=build/'native/debug/build/cmd/moonlibsync/moonlibsync.exe'
    with tempfile.TemporaryDirectory(prefix='moonlibsync-stage-a-gate-') as folder:
        work=Path(folder);old=work/'old';old.write_bytes(b'abc')
        delta=work/'delta';delta.write_bytes(bytes.fromhex('7273023645000300'))
        manifest=work/'manifest';manifest.write_bytes((ROOT/'tests/integrity/update.json').read_bytes())
        inputs={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in [old,delta,manifest]}
        out=work/'out'
        p=subprocess.run([str(exe),'patch-verified',str(old),str(delta),str(manifest),str(out)],capture_output=True)
        assert all(hashlib.sha256(path.read_bytes()).hexdigest()==sha for path,sha in inputs.items())
        assert not list(work.glob('.moonlibsync-*.tmp'))
        if p.returncode:
            assert not out.exists()
            print(p.stderr.decode(),flush=True)
            p.check_returncode()
        assert out.read_bytes()==b'abc'
    print('STAGE_A_VERIFIED_GATE_OK')

if __name__=='__main__':main()
