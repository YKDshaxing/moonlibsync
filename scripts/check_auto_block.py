"""Finite data-volume and fixed-rdiff verification. Never measures elapsed time."""
import json,hashlib,os,shutil,subprocess,sys,tempfile,struct
from pathlib import Path
from benchmark import inputs
from interop_wire import inspect_delta,check_contents
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')/'auto-block'
PLAN=ROOT/'tests/auto-block/plan.json'
REF_SHA='e364852674780e43d578e4239128ff7014190ed3'


def main():
    OUT.mkdir(parents=True,exist_ok=True);plan=json.loads(PLAN.read_text(encoding='utf8'))
    git=['git','-c','safe.directory='+ROOT.as_posix()]
    source=dict(sha=subprocess.check_output([*git,'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),dirty=bool(subprocess.check_output([*git,'status','--porcelain'],cwd=ROOT,text=True).strip()))
    if os.environ.get('GITHUB_SHA'):assert source['sha']==os.environ['GITHUB_SHA'] and not source['dirty']
    report=dict(status='incomplete',source=source,policy_version=1,plan_sha256=hashlib.sha256(PLAN.read_bytes()).hexdigest(),expected=plan['expected'],executed={k:0 for k in plan['expected']},thresholds=[],comparison=[],timed=False)
    (OUT/'plan.json').write_bytes(PLAN.read_bytes());log=(OUT/'commands.log').open('w',encoding='utf8')
    def run(cmd,cwd=ROOT):
        p=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=180)
        log.write(json.dumps(dict(argv=list(map(str,cmd)),cwd=str(cwd),exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr))+'\n');log.flush()
        assert p.returncode==0,(cmd,p.returncode,p.stdout,p.stderr)
        return p.stdout
    def sha(b):return hashlib.sha256(b).hexdigest()
    try:
        ref=ROOT/'.toolchain/reference';rdiff=ref/'build/rdiff'
        assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ref/'source',text=True).strip()==REF_SHA
        assert '2.3.4' in run([rdiff,'--version'])
        run([sys.executable,'scripts/verify_dependencies.py'])
        build=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')
        text=run(['moon','--target-dir',build,'build','cmd/moonlibsync','--target','native','--release'])
        # Existing standalone project scope, separate from debug CLI smoke.
        exe=build/'native/release/build/cmd/moonlibsync/moonlibsync.exe'
        assert exe.is_file() and str(exe) in text
        report['tools']=dict(executable=str(exe),executable_sha256=sha(exe.read_bytes()),mode='release',rdiff=str(rdiff),rdiff_sha256=sha(rdiff.read_bytes()))
        config=json.loads((ROOT/'tests/benchmarks/config.json').read_text(encoding='utf8'))
        with tempfile.TemporaryDirectory(prefix='moonlibsync-auto-') as folder:
            work=Path(folder)
            def case(label,old,new,block,strong,automatic):
                lane=work/label;lane.mkdir();a=lane/'old';n=lane/'new';a.write_bytes(old);n.write_bytes(new)
                sig=lane/'sig';explicit=lane/'explicit.sig';up=lane/'upstream.sig';delta=lane/'delta';updelta=lane/'upstream.delta'
                run([exe,'signature',a,sig,'--block-size','auto' if automatic else block,'--sum-size',strong])
                count=len(old)//block+int(len(old)%block!=0);expected_size=12+count*(4+strong)
                wire=sig.read_bytes();assert struct.unpack('>III',wire[:12])==(0x72730147,block,strong) and len(wire)==expected_size
                summary=json.loads(run([exe,'inspect-signature',sig,'--json']))['summary']
                assert summary==dict(magic='0x72730147',profile='RS_RK_BLAKE2_SIG_MAGIC',block_len=str(block),strong_sum_len=str(strong),record_count=str(count),signature_bytes=str(expected_size))
                run([exe,'signature',a,explicit,'--block-size',block,'--sum-size',strong]);assert explicit.read_bytes()==wire
                run([rdiff,'-H','blake2','-R','rabinkarp','-b',block,'-S',strong,'signature',a,up]);assert up.read_bytes()==wire
                report['executed']['signature_comparisons']+=1
                # Generation has no basis argument and OLD is physically absent.
                a.unlink();run([exe,'delta',sig,n,delta]);run([rdiff,'delta',up,n,updelta]);a.write_bytes(old)
                copied=check_contents(inspect_delta(delta.read_bytes()),old,new)
                upstream_copy=check_contents(inspect_delta(updelta.read_bytes()),old,new)
                mo=lane/'moon-restored';ro=lane/'rdiff-restored'
                run([exe,'patch',a,updelta,mo]);run([rdiff,'patch',a,delta,ro])
                assert mo.read_bytes()==ro.read_bytes()==new;report['executed']['restores']+=2
                return dict(label=label,mode='auto' if automatic else 'fixed',old_bytes=len(old),new_bytes=len(new),old_sha256=sha(old),new_sha256=sha(new),block_len=block,strong_sum_len=strong,records=count,signature_bytes=len(wire),signature_sha256=sha(wire),delta_bytes=delta.stat().st_size,copy_bytes=copied,upstream_delta_bytes=updelta.stat().st_size,upstream_copy_bytes=upstream_copy,signature_equal_rdiff=True,signature_equal_explicit=True,restored=True)
            try:
                for i,v in enumerate(plan['thresholds']):
                    old=bytes((j*73+19)%256 for j in range(v['length']));new=b'!'+old+b'\x80'
                    r=case('threshold-'+str(i),old,new,v['block'],v['strong'],True)
                    assert r['records']==v['records'] and r['signature_bytes']==v['signature_bytes']
                    report['thresholds'].append(r);report['executed']['threshold_cases']+=1
                for size in plan['sizes']:
                    for scenario in plan['scenarios']:
                        old,new=inputs(size,scenario,config)
                        pair=[]
                        for mode in plan['modes']:
                            block=2048 if mode=='fixed' else (128 if size==65536 else 2048)
                            r=case(str(size)+'-'+scenario+'-'+mode,old,new,block,32,mode=='auto')
                            if scenario=='all-different':assert not set(old)&set(new) and r['copy_bytes']==r['upstream_copy_bytes']==0
                            if scenario=='identical':assert r['copy_bytes']==len(new)
                            r.update(scenario=scenario,size=size);pair.append(r)
                        report['comparison'].append(dict(size=size,scenario=scenario,results=pair));report['executed']['comparison_pairs']+=1
                assert report['executed']==report['expected'],report['executed']
                report['status']='passed'
            except BaseException:
                failure=OUT/'failures';failure.mkdir(exist_ok=True);shutil.copytree(work,failure/work.name);raise
    except BaseException as error:
        report.update(status='failed',error=repr(error));raise
    finally:
        log.close();(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print('Auto block upstream/data checks passed:',report['executed'],'no timing performed',flush=True)

if __name__=='__main__':main()
