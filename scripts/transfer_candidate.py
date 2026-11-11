"""External candidate-only transfer consumer and both-kind product CLI flows."""
import json,hashlib,subprocess
from cli_transfer_cases import exercise


def validate(client,package,exe,runner,out,env=None):
    report=dict(status='incomplete',kind='candidate-package-local-workspace-consumption',targets=[],cases=[])
    dest=out/'transfer';dest.mkdir(exist_ok=True)
    try:
        for target in ('native','js','wasm-gc'):
            text=runner(['moon','run',str(client),'--target',target],'transfer-consumer-'+target,cwd=client,env=env)
            assert text.count('TRANSFER_EXAMPLE_OK kind=librsync-delta')==1 and text.count('TRANSFER_EXAMPLE_OK kind=full-file')==1
            report['targets'].append(dict(target=target,status='passed',kinds=['librsync-delta','full-file']))
        work=client.parent/'transfer-cli';work.mkdir()
        def case(name,args,expected=0,watch=(),output=None,contains=None,text=False):
            before={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in work.iterdir() if p.is_file()}
            pending=set(work.glob('.moonlibsync-*.tmp'))
            p=subprocess.run([str(exe),*map(str,args)],cwd=work,capture_output=True,timeout=120,env=env)
            assert p.returncode==expected,(name,p.stdout,p.stderr)
            assert not p.stdout and (bool(p.stderr) if expected else not p.stderr),(name,p.stdout,p.stderr)
            if contains:assert contains.encode() in p.stderr,(name,p.stderr)
            assert all(k.is_file() and hashlib.sha256(k.read_bytes()).hexdigest()==v for k,v in before.items())
            assert pending==set(work.glob('.moonlibsync-*.tmp'))
            if expected and output:assert not output.exists() or output in before
            report['cases'].append(dict(name=name,status='passed',expected_exit=expected,actual_exit=p.returncode,argv=list(map(str,args)),stdout=p.stdout.decode('utf8','replace'),stderr=p.stderr.decode('utf8','replace'),stdout_empty=True,prior_files_unchanged=True))
            return p
        exercise(work,case,report)
        report['status']='passed'
    finally:
        (dest/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    return report
