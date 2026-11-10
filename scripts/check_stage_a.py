"""Execute the frozen 18-path stage A plan, preserving the old interop plan."""
import hashlib,json,os,shutil,subprocess,sys,tempfile
from pathlib import Path
from stage_a_data import groups
from interop_wire import inspect_delta,check_contents
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')/'stage-a'
PLAN=ROOT/'tests/stage-a/plan.json'
SHA='e364852674780e43d578e4239128ff7014190ed3'


def digest(data): return dict(byte_length=str(len(data)),sha256=hashlib.sha256(data).hexdigest())


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    plan=json.loads(PLAN.read_text(encoding='utf-8')); generated=groups(plan)
    actual=[dict(id=g['id'],block=g['block'],strong=g['strong'],old_length=len(g['old']),old_sha256=hashlib.sha256(g['old']).hexdigest(),targets=[dict(id=t['id'],new_length=len(t['new']),new_sha256=hashlib.sha256(t['new']).hexdigest(),min_copy=t['min_copy']) for t in g['targets']]) for g in generated]
    assert actual==plan['input_manifest'],'STAGE_A_INPUT_PLAN_MISMATCH'
    assert all(hashlib.sha256((ROOT/name).read_bytes().replace(b'\r\n',b'\n')).hexdigest()==sha for name,sha in plan['generator_sha256'].items())
    source=dict(sha=subprocess.check_output(['git','-c',f'safe.directory={ROOT.as_posix()}','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),dirty=bool(subprocess.check_output(['git','-c',f'safe.directory={ROOT.as_posix()}','status','--porcelain'],cwd=ROOT,text=True).strip()))
    if os.environ.get('GITHUB_SHA'): assert source['sha']==os.environ['GITHUB_SHA'] and not source['dirty']
    report=dict(status='incomplete',source=source,plan_sha256=hashlib.sha256(PLAN.read_bytes()).hexdigest(),expected=plan['expected'],executed={k:0 for k in plan['expected']},cases=[],groups=[],failures=[])
    (OUT/'plan.json').write_bytes(PLAN.read_bytes())
    log=(OUT/'commands.log').open('w', encoding='utf-8')
    def run(cmd,cwd=ROOT,expect=0):
        p=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=120)
        log.write(json.dumps(dict(argv=list(map(str,cmd)),cwd=str(cwd),exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr))+'\n');log.flush()
        assert p.returncode==expect,(cmd,p.returncode,p.stdout,p.stderr)
        return p.stdout
    work=None
    try:
        ref=ROOT/'.toolchain/reference';rdiff=ref/'build/rdiff'
        assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ref/'source',text=True).strip()==SHA
        assert '2.3.4' in run([rdiff,'--version'])
        run([sys.executable,'scripts/verify_dependencies.py'])
        build=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')
        for pkg in ['probes/signature','probes/stage_a']:
            run(['moon','--target-dir',build,'build',pkg,'--target','native'])
        adapter=build/'native/debug/build/probes/stage_a/stage_a.exe'; original=build/'native/debug/build/probes/signature/signature.exe'
        assert adapter.is_file() and original.is_file()
        report['tools']=dict(adapter=str(adapter),adapter_sha256=hashlib.sha256(adapter.read_bytes()).hexdigest(),rdiff=str(rdiff),rdiff_sha256=hashlib.sha256(rdiff.read_bytes()).hexdigest())
        with tempfile.TemporaryDirectory(prefix='moonlibsync-stage-a-',dir=os.environ.get('MOONLIBSYNC_CLI_TMP_PARENT')) as folder:
            work=Path(folder)
            try:
                for g in generated:
                    base=work/g['id'];base.mkdir();old=base/'old';old.write_bytes(g['old'])
                    news=[]
                    for t in g['targets']:
                        path=base/(t['id']+'.new');path.write_bytes(t['new']);news.append(path)
                    sigs={s:base/(s+'.sig') for s in plan['signature_sources']}
                    run([rdiff,'-H','blake2','-R','rabinkarp','-b',g['block'],'-S',g['strong'],'signature',old,sigs['rdiff']])
                    run([original,old,sigs['moon'],g['block'],g['strong']])
                    assert sigs['rdiff'].read_bytes()==sigs['moon'].read_bytes()
                    report['executed']['signature_comparisons']+=1
                    for origin,sig in sigs.items():
                        lane=base/origin;lane.mkdir();info=lane/'basis.json'
                        run([adapter,'basis',old,sig,info]);expected_info=dict(schema_version=1,kind='moonlibsync-basis-info',basis=digest(g['old']),signature=digest(sig.read_bytes()))
                        assert json.loads(info.read_bytes())==expected_info
                        report['executed']['basis_infos']+=1
                        # No OLD file exists for this complete sending phase.
                        old.unlink()
                        text=run([adapter,'group',sig,lane,*news])
                        assert text.strip()==f"prepared=1 targets={len(news)} calls={2*len(news)}"
                        report['executed']['preparations']+=1
                        report['executed']['multi_target_preparations']+=int(len(news)>1)
                        report['executed']['multi_target_calls']+=2*len(news) if len(news)>1 else 0
                        report['executed']['prepared_calls']+=2*len(news)
                        report['executed']['deterministic_rechecks']+=len(news)
                        for i,t in enumerate(g['targets']):
                            upstream=lane/f'rdiff-{i}.delta';run([rdiff,'delta',sig,news[i],upstream])
                            for generator in plan['delta_generators']:
                                dd=upstream if generator=='rdiff' else lane/f'{generator}-{i}.delta'
                                commands=inspect_delta(dd.read_bytes());copied=check_contents(commands,g['old'],t['new'])
                                assert copied>=t['min_copy'],(g['id'],t['id'],generator,copied,t['min_copy'])
                                if g['id']=='bytes' and t['id']=='different': assert copied==0
                                manifest=lane/f'{generator}-{i}.json'
                                run([adapter,'manifest',info,sig,news[i],dd,manifest])
                                expected=dict(schema_version=1,kind='librsync-delta',basis=digest(g['old']),signature=digest(sig.read_bytes()),delta=digest(dd.read_bytes()),result=digest(t['new']))
                                assert json.loads(manifest.read_bytes())==expected
                                report['executed']['manifests']+=1
                        old.write_bytes(g['old'])
                        for i,t in enumerate(g['targets']):
                            for generator in plan['delta_generators']:
                                dd=lane/f'{generator}-{i}.delta';manifest=lane/f'{generator}-{i}.json'
                                commands=inspect_delta(dd.read_bytes());copied=check_contents(commands,g['old'],t['new'])
                                literals=[c for c in commands if c[0]=='literal'];copies=[c for c in commands if c[0]=='copy']
                                stats=list(map(int,run([adapter,'inspect',sig,dd,len(g['old'])]).split()))
                                assert stats==[g['block'],g['strong'],(len(g['old'])+g['block']-1)//g['block'],len(sig.read_bytes()),len(dd.read_bytes()),len(commands),len(literals),len(copies),sum(len(c[1]) for c in literals),copied,len(t['new'])]
                                report['executed']['signature_checks']+=1;report['executed']['delta_checks']+=1;report['executed']['patch_checks']+=1
                                for restore in plan['restorers']:
                                    dest=lane/f'{generator}-{i}-{restore}.out'
                                    cmd=[rdiff,'patch',old,dd,dest] if restore=='rdiff' else [original,'patch',old,dd,dest] if restore=='patch' else [adapter,'verified',old,dd,manifest,dest]
                                    run(cmd)
                                    assert dest.read_bytes()==t['new']
                                    report['cases'].append(dict(group=g['id'],target=t['id'],signature=origin,generator=generator,restore=restore,copy_bytes=copied,equal=True))
                                    report['executed']['restores_each']+=int(restore=='verified')
                                    report['executed']['restores_total']+=1
                                report['executed']['generation_each']+=int(generator=='prepared')
                                report['executed']['delta_files']+=1
                        report['executed']['signature_files']+=1
                    report['executed']['groups']+=1
                    report['executed']['input_pairs']+=len(g['targets']);report['executed']['parameter_cases']+=len(g['targets'])
                    report['groups'].append(dict(id=g['id'],block=g['block'],strong=g['strong'],old=digest(g['old']),targets=[dict(id=t['id'],new=digest(t['new']),min_copy=t['min_copy']) for t in g['targets']]))
                assert report['executed']==report['expected'],report['executed']
                for kind in plan['restorers']: assert sum(c['restore']==kind for c in report['cases'])==168
                for kind in plan['delta_generators']: assert sum(c['generator']==kind for c in report['cases'])//3==56
                report['coverage']={k:dict(expected=v,executed=report['executed'][k],status='passed') for k,v in report['expected'].items()}
                report['generation_counts']={k:sum(c['generator']==k for c in report['cases'])//3 for k in plan['delta_generators']}
                report['restore_counts']={k:sum(c['restore']==k for c in report['cases']) for k in plan['restorers']}
                report['status']='passed'
            except BaseException:
                failures=OUT/'failures';failures.mkdir(exist_ok=True)
                shutil.copytree(work,failures/work.name)
                raise
    except BaseException as e:
        report['status']='failed';report['failures'].append(repr(e));raise
    finally:
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n', encoding='utf-8');log.close()
    print('Stage A passed:',report['executed'],'plan_sha256='+report['plan_sha256'])

if __name__=='__main__':main()
