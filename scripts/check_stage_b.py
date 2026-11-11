"""Finite stage B combinations; no timing and no cross-generator delta equality."""
import hashlib,json,os,shutil,struct,subprocess,sys,tempfile
from pathlib import Path
from stage_b_data import inputs_for,digest
from interop_wire import inspect_delta,check_contents
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'_build/stage-b'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    plan_file=ROOT/'tests/stage-b/plan.json';plan=json.loads(plan_file.read_text())
    assert all(hashlib.sha256((ROOT/n).read_bytes().replace(b'\r\n',b'\n')).hexdigest()==h for n,h in plan['generator_sha256'].items())
    git=['git','-c','safe.directory='+ROOT.as_posix()]
    source=dict(sha=subprocess.check_output([*git,'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),dirty=bool(subprocess.check_output([*git,'status','--porcelain'],cwd=ROOT,text=True).strip()))
    if os.environ.get('GITHUB_SHA'):assert source==dict(sha=os.environ['GITHUB_SHA'],dirty=False)
    report=dict(status='incomplete',source=source,plan_sha256=hashlib.sha256(plan_file.read_bytes()).hexdigest(),expected=plan['expected'],executed={k:0 for k in plan['expected']},delta_upstream_restores=0,full_raw_checks=0,cases=[],rejects=[],timed=False)
    (OUT/'plan.json').write_bytes(plan_file.read_bytes());log=(OUT/'commands.log').open('w',encoding='utf8')
    def run(args,expected=0,needle=None):
        p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,timeout=180)
        log.write(json.dumps(dict(argv=list(map(str,args)),exit_code=p.returncode,stdout=p.stdout.decode('utf8','replace'),stderr=p.stderr.decode('utf8','replace')))+'\n');log.flush()
        assert (p.returncode==0 if expected==0 else p.returncode!=0),(args,p.stdout,p.stderr)
        if needle:assert needle.encode() in p.stdout+p.stderr,(args,p.stdout,p.stderr)
        return p
    def reject(name,args,output,needle):
        run(args,1,needle);assert not output.exists()
        assert not list(output.parent.glob('.moonlibsync-*.tmp'))
        report['rejects'].append(dict(id=name,status='passed',no_output=True))
    try:
        ref=ROOT/'.toolchain/reference';rdiff=ref/'build/rdiff'
        assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ref/'source',text=True).strip()=='e364852674780e43d578e4239128ff7014190ed3'
        run([sys.executable,'scripts/verify_dependencies.py'])
        build=OUT/'build'
        for package in ['cmd/moonlibsync','probes/stage_b']:run(['moon','--target-dir',build,'build',package,'--target','native','--release'])
        exe=build/'native/release/build/cmd/moonlibsync/moonlibsync.exe';probe=build/'native/release/build/probes/stage_b/stage_b.exe'
        report['tools']=dict(cli_sha256=digest(exe.read_bytes())['sha256'],probe_sha256=digest(probe.read_bytes())['sha256'],rdiff_sha256=digest(rdiff.read_bytes())['sha256'],mode='release')
        with tempfile.TemporaryDirectory(prefix='mls-stage-b-') as folder:
            work=Path(folder)
            try:
                for spec in plan['cases']:
                    old,new=inputs_for(spec);assert digest(old)==spec['old'] and digest(new)==spec['new']
                    lane=work/spec['id'];lane.mkdir();a=lane/'old';n=lane/'new';sig=lane/'sig';info=lane/'info';up_sig=lane/'rdiff.sig'
                    a.write_bytes(old);n.write_bytes(new)
                    run([exe,'signature',a,sig,'--block-size',spec['block_choice']])
                    block=spec['block_len'];wire=sig.read_bytes();count=(len(old)+block-1)//block
                    assert struct.unpack('>III',wire[:12])==(0x72730147,block,32) and len(wire)==12+36*count
                    run([rdiff,'-H','blake2','-R','rabinkarp','-b',block,'-S',32,'signature',a,up_sig]);assert wire==up_sig.read_bytes()
                    report['executed']['signature_comparisons']+=1
                    run([exe,'basis-info',a,sig,info]);a.unlink()
                    primary=lane/'primary';primary.mkdir()
                    run([probe,spec['generator'],sig,n,info,primary,spec['min_savings']])
                    upstream=lane/'upstream';upstream.mkdir();run([rdiff,'delta',sig,n,upstream/'candidate'])
                    run([exe,'make-transfer-manifest',info,sig,n,upstream/'candidate',upstream/'manifest','--min-savings',spec['min_savings']])
                    row=dict(id=spec['id'],old=spec['old'],new=spec['new'],block_len=block,record_count=count,signature=digest(wire),generators=[])
                    for label,where in [(spec['generator'],primary),('rdiff',upstream)]:
                        candidate=(where/'candidate').read_bytes();check_contents(inspect_delta(candidate),old,new)
                        choose=len(candidate)<len(new) and len(new)-len(candidate)>=spec['min_savings']
                        kind='librsync-delta' if choose else 'full-file';payload=candidate if choose else new
                        manifest=json.loads((where/'manifest').read_bytes())
                        assert manifest['kind']==kind and manifest['schema_version']==2
                        assert manifest['payload']==digest(payload) and manifest['result']==digest(new)
                        if choose:assert manifest['basis']==digest(old) and manifest['signature']==digest(wire)
                        else:assert set(manifest)=={'schema_version','kind','payload','result'}
                        if where==primary:assert (where/'payload').read_bytes()==payload
                        else:(where/'payload').write_bytes(payload)
                        out=where/'out'
                        if choose:
                            a.write_bytes(old);run([exe,'apply-update',where/'payload',where/'manifest',out,'--basis',a])
                            run([rdiff,'patch',a,where/'payload',where/'rdiff-out']);assert (where/'rdiff-out').read_bytes()==new
                            a.unlink();report['delta_upstream_restores']+=1
                        else:
                            assert not a.exists();run([exe,'apply-update',where/'payload',where/'manifest',out]);report['full_raw_checks']+=1
                        assert out.read_bytes()==new
                        row['generators'].append(dict(generator=label,candidate=digest(candidate),payload=digest(payload),result=digest(out.read_bytes()),kind=kind,min_savings=spec['min_savings'],status='passed'))
                        report['executed']['candidates']+=1;report['executed']['applications']+=1
                    a.write_bytes(old)
                    if spec['id']=='block':
                        legacy=lane/'schema1';run([exe,'make-manifest',info,sig,n,primary/'candidate',legacy])
                        failed=lane/'failed';good=primary/'manifest'
                        reject('schema1-as-schema2',[exe,'apply-update',primary/'payload',legacy,failed,'--basis',a],failed,'InvalidSchema')
                        reject('schema2-as-schema1',[exe,'patch-verified',a,primary/'candidate',good,failed],failed,'InvalidSchema')
                        bad=lane/'bad';bad.write_text(good.read_text().replace('librsync-delta','unknown'))
                        reject('unknown-kind',[exe,'apply-update',primary/'payload',bad,failed,'--basis',a],failed,'InvalidSchema')
                        wrong=lane/'wrong';wrong.write_bytes(b'ABCDEFGHIJKLMNOP')
                        reject('wrong-basis',[exe,'apply-update',primary/'payload',good,failed,'--basis',wrong],failed,'basis_sha256')
                        wrong.write_bytes(b'bad')
                        reject('wrong-payload',[exe,'apply-update',wrong,good,failed,'--basis',a],failed,'delta_length')
                        m=json.loads(good.read_bytes());m['result']['sha256']='0'*64;bad.write_text(json.dumps(m))
                        reject('wrong-result',[exe,'apply-update',primary/'payload',bad,failed,'--basis',a],failed,'result_sha256')
                        bad.write_bytes(b'');reject('bad-signature',[exe,'delta',bad,n,failed],failed,'TruncatedInput')
                        reject('work-limit',[probe,'work-error',sig,n],failed,'LimitExceeded')
                        restored=lane/'after-errors';run([exe,'apply-update',primary/'payload',good,restored,'--basis',a]);assert restored.read_bytes()==new
                    if spec['id']=='tiny':
                        failed=lane/'failed';reject('payload-type-mismatch',[exe,'apply-update',primary/'candidate',primary/'manifest',failed],failed,'payload_length')
                    report['cases'].append(row);report['executed']['input_cases']+=1
                assert report['executed']==report['expected'] and len(report['rejects'])==9
                assert report['delta_upstream_restores']>0 and report['full_raw_checks']>0
                report['status']='passed'
            except BaseException:
                dest=OUT/'failures';dest.mkdir(exist_ok=True);shutil.copytree(work,dest/work.name);raise
    except BaseException as error:report.update(status='failed',error=repr(error));raise
    finally:log.close();(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print('Stage B combinations passed:',report['executed'],'Delta upstream:',report['delta_upstream_restores'],'Full:',report['full_raw_checks'],flush=True)


if __name__=='__main__':main()
