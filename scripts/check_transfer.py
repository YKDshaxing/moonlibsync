"""Commit 26 real file decisions, strict payload checks and pinned rdiff recovery.
No timing measurements; Full is never counted as a librsync recovery.
"""
import hashlib,json,os,platform,subprocess,sys,tempfile,shutil
from pathlib import Path
from cli_transfer_cases import exercise
from interop_wire import inspect_delta,check_contents
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'_build/commit26/reference'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    git=['git','-c','safe.directory='+ROOT.as_posix()]
    source=dict(sha=subprocess.check_output([*git,'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),dirty=bool(subprocess.check_output([*git,'status','--porcelain'],cwd=ROOT,text=True).strip()))
    if os.environ.get('GITHUB_SHA'):assert source==dict(sha=os.environ['GITHUB_SHA'],dirty=False)
    report=dict(source=source,status='incomplete',cases=[],delta_selections=0,full_selections=0,delta_upstream_restores=0,full_raw_validations=0,timed=False)
    commands=(OUT/'commands.log').open('w',encoding='utf8')
    def run(args,cwd=ROOT):
        p=subprocess.run(list(map(str,args)),cwd=cwd,capture_output=True,timeout=180)
        commands.write(json.dumps(dict(argv=list(map(str,args)),cwd=str(cwd),exit_code=p.returncode,stdout=p.stdout.decode('utf8','replace'),stderr=p.stderr.decode('utf8','replace')))+'\n');commands.flush()
        return p
    def success(args):
        p=run(args);assert p.returncode==0,(args,p.stdout,p.stderr);return p.stdout
    def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
    try:
        ref=ROOT/'.toolchain/reference';rdiff=ref/'build/rdiff'
        assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ref/'source',text=True).strip()=='e364852674780e43d578e4239128ff7014190ed3'
        assert b'2.3.4' in success([rdiff,'--version'])
        success([sys.executable,'scripts/verify_dependencies.py'])
        report['environment']=dict(os=platform.platform(),python=sys.version,moon=success(['moon','version','--all']).decode('utf8'),storage='fresh system temporary directory')
        build=ROOT/'_build/commit26/build'
        text=success(['moon','--target-dir',build,'build','cmd/moonlibsync','--target','native','--release'])
        exe=build/'native/release/build/cmd/moonlibsync/moonlibsync.exe'
        assert str(exe).encode() in text and exe.is_file()
        report['tools']=dict(executable=str(exe),executable_sha256=digest(exe),rdiff=str(rdiff),rdiff_sha256=digest(rdiff),build='release')
        text=success(['moon','run','examples/transfer','--target','native']).decode()
        assert 'kind=librsync-delta new=16 delta=8 payload=8' in text and 'kind=full-file new=3 delta=9 payload=3' in text
        report['planning_example']='both actual branches passed'
        with tempfile.TemporaryDirectory(prefix='moonlibsync-transfer-') as folder:
            work=Path(folder)
            report['environment']['filesystem']=success(['findmnt','-n','-o','FSTYPE','-T',work]).decode().strip()
            def case(name,args,expected=0,watch=(),output=None,contains=None,text=False):
                before={p:digest(p) for p in work.iterdir() if p.is_file()};pending=set(work.glob('.moonlibsync-*.tmp'))
                p=run([exe,*args],work)
                assert p.returncode==expected,(name,p.stdout,p.stderr)
                assert not p.stdout and (bool(p.stderr) if expected else not p.stderr)
                if contains:assert contains.encode() in p.stderr,(name,p.stderr)
                assert all(k.is_file() and digest(k)==v for k,v in before.items())
                assert pending==set(work.glob('.moonlibsync-*.tmp'))
                if expected and output:assert not output.exists() or output in before
                report['cases'].append(dict(name=name,passed=True,exit_code=p.returncode))
                return p
            try:
                exercise(work,case,report)
                for row in report['transfer_cases']:
                    label=row['id'];new=(work/('transfer-'+label+'.new')).read_bytes()
                    delta=work/('transfer-'+label+'.delta')
                    check_contents(inspect_delta(delta.read_bytes()),b'abcdefghijklmnop',new)
                    if row['kind']=='librsync-delta':
                        report['delta_selections']+=1
                        restored=work/(label+'.rdiff-out')
                        success_args=[rdiff,'patch',work/'transfer-old',delta,restored]
                        p=run(success_args,work);assert p.returncode==0,(p.stdout,p.stderr)
                        assert restored.read_bytes()==new
                        report['delta_upstream_restores']+=1
                    else:
                        report['full_selections']+=1
                        assert row['manifest']['payload']==row['manifest']['result'] and row['payload_bytes']==len(new)
                        assert hashlib.sha256(new).hexdigest()==row['manifest']['payload']['sha256']
                        report['full_raw_validations']+=1
                assert (report['delta_selections'],report['full_selections'],report['delta_upstream_restores'],report['full_raw_validations'])==(2,6,2,6)
                report['status']='passed'
            except BaseException:
                failure=OUT/'failures';failure.mkdir(exist_ok=True);shutil.copytree(work,failure/work.name);raise
    except BaseException as error:
        report.update(status='failed',error=repr(error));raise
    finally:
        commands.close();(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print('Commit 26 passed: 2 Delta selections/upstream restores; 6 Full raw validations; no timing',flush=True)


if __name__=='__main__':main()
