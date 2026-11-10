"""Actual external stage A consumer entry; candidate workspace replacement only."""
import argparse,json,os,platform,subprocess,sys,re
from pathlib import Path
from release_version import MODULE, VERSION
ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser();p.add_argument('--client',type=Path,required=True);p.add_argument('--package',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--target',choices=['native','js','wasm-gc']);p.add_argument('--registry',action='store_true');a=p.parse_args()
    client=a.client.resolve();package=a.package.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    assert not client.is_relative_to(ROOT) and not package.is_relative_to(ROOT)
    if a.registry:
        for parent in (client,*client.parents):
            assert not (parent/'moon.work').exists() and not (parent/'moon.work.json').exists()
        assert package==(client/'.mooncakes'/MODULE).resolve()
        assert not re.search(r'(?m)^\s*(?:replace|path|git)\b',(client/'moon.mod').read_text(encoding='utf8'))
    else:
        assert client.parent==package.parent
        assert '"./stage-a-consumer"' in (client.parent/'moon.work').read_text(encoding='utf-8')
    targets=[a.target] if a.target else ['native','js','wasm-gc']
    report=dict(status='incomplete',kind='public-registry-no-local-replacement' if a.registry else 'release-candidate-local-workspace',registry_consumption=a.registry,version=VERSION,environment=platform.platform(),client=str(client),resolved_package=str(package),replacement='none' if a.registry else 'moon.work members package and stage-a-consumer',expected=dict(targets=len(targets),encapsulation=len(targets)*3),runs=[],encapsulation=[])
    def run(cmd,label,expected=0,marker=None):
        result=subprocess.run(list(map(str,cmd)),cwd=client,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=180)
        text=result.stdout+result.stderr;(out/(label+'.log')).write_text(text, encoding='utf-8')
        if result.returncode!=expected and not (expected==1 and result.returncode>0):
            print(text);raise RuntimeError('STAGE_A_CONSUMER_ENTRY_FAILURE '+label)
        if marker: assert marker in text,text
        return text
    tree=json.loads(run(['moon','tree','--json'],'resolved-dependencies'))
    module=[m for m in tree['modules'] if m['name']=='YKDshaxing/moonlibsync']
    assert len(module)==1 and module[0]['version']==VERSION,module
    if a.registry:
        assert module[0]['source']['kind']=='registry' and not module[0]['workspace_member'],module
    else:
        assert Path(module[0]['source']['path']).resolve()==package and module[0]['workspace_member'],module
    report['actual_resolution']=module[0]
    original=(client/'main.mbt').read_text(encoding='utf-8')
    try:
        for target in targets:
            text=run(['moon','run',client,'--target',target],target,marker='STAGE_A_CONSUMER_OK')
            assert text.count('STAGE_A_CONSUMER_OK')==1
            rejection_plan=json.loads((ROOT/'tests/stage-a/rejections.json').read_text(encoding='utf-8'))
            observed=re.findall(r'^STAGE_A_REJECTION (.+)$',text,re.M)
            assert observed==rejection_plan['expected_diagnostics'],observed
            report['runs'].append(dict(target=target,status='passed',public_rejections=len(observed),rejections=[dict(id=name,diagnostic=actual,status='passed') for name,actual in zip(rejection_plan['core'],observed)]))
            for name,code in [('index','fn main { let p = @lib.prepare_signature(b"",@lib.Limits::default()) catch { _ => abort("fail") }; ignore(p.index) }'),('bytes','fn main { let p = @lib.prepare_signature(b"",@lib.Limits::default()) catch { _ => abort("fail") }; ignore(p.signature_bytes) }'),('construct','fn main { let p : @lib.PreparedSignature = { signature_bytes: 12L, index: 0 }; ignore(p) }')]:
                (client/'main.mbt').write_text(code+'\n', encoding='utf-8')
                diagnostic=run(['moon','check',client,'--target',target],target+'-'+name,expected=1)
                assert ('4091' if name!='construct' else '4036') in diagnostic,diagnostic
                report['encapsulation'].append(dict(target=target,case=name,rejected=True))
                (client/'main.mbt').write_text(original, encoding='utf-8')
            run(['moon','run',client,'--target',target],target+'-after-errors',marker='STAGE_A_CONSUMER_OK')
        assert len(report['runs'])==report['expected']['targets'] and len(report['encapsulation'])==report['expected']['encapsulation']
        report['status']='passed'
    except BaseException as error:
        report.update(status='failed',error=repr(error));raise
    finally:
        (client/'main.mbt').write_text(original, encoding='utf-8')
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n', encoding='utf-8')
    print('Stage A external consumer passed:',targets,'candidate='+str(package))

if __name__=='__main__':main()
