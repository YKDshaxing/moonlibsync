"""External candidate/registry transfer consumer and both-kind product CLI flows."""
import json,hashlib,subprocess
from cli_transfer_cases import exercise


def validate(client,package,exe,runner,out,env=None,registry=False):
    report=dict(status='incomplete',kind='public-registry-no-local-replacement' if registry else 'candidate-package-local-workspace-consumption',targets=[],cases=[])
    dest=out/('registry-transfer' if registry else 'transfer');dest.mkdir(exist_ok=True)
    try:
        for target in ('native','js','wasm-gc'):
            text=runner(['moon','run',str(client),'--target',target],'transfer-consumer-'+target,cwd=client,env=env)
            assert text.count('STAGE_B_KIND_OK kind=librsync-delta')==1 and text.count('STAGE_B_KIND_OK kind=full-file')==1 and 'STAGE_B_CONSUMER_OK auto=128 records=257 signature=5152' in text
            report['targets'].append(dict(target=target,status='passed',kinds=['librsync-delta','full-file']))
        # Same entry must propagate an actual bad public-API consumer, then recover.
        source=client/'main.mbt';original=source.read_bytes()
        broken=original.replace(b'assert_eq(block, 128L)',b'assert_eq(block, 129L)')
        assert broken!=original
        source.write_bytes(broken)
        try:
            try:
                runner(['moon','run',str(client),'--target','wasm-gc'],'transfer-consumer-broken',cwd=client,env=env)
                raise AssertionError('Broken stage B consumer unexpectedly passed')
            except subprocess.CalledProcessError as error:
                assert 'STAGE_B_CONSUMER_FAILED' in error.output,error.output
                report['failure_gate']=dict(status='passed',observed_exit=error.returncode)
        finally:source.write_bytes(original)
        recovered=runner(['moon','run',str(client),'--target','wasm-gc'],'transfer-consumer-restored',cwd=client,env=env)
        assert 'STAGE_B_CONSUMER_OK' in recovered
        report['restored_consumer']='passed'
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
        # Additional auto file checks, separate from the retained 48 transfer cases.
        n=work/'auto-source';n.write_bytes(bytes(range(256))*128+b'!')
        auto=work/'auto.sig';explicit=work/'explicit.sig'
        case('stage-b/auto',['signature',n,auto,'--block-size','auto'],output=auto)
        case('stage-b/explicit',['signature',n,explicit,'--block-size','128'],output=explicit)
        assert auto.read_bytes()==explicit.read_bytes()
        import struct
        assert struct.unpack('>III',auto.read_bytes()[:12])==(0x72730147,128,32)
        report['auto_cli']=dict(status='passed',actual_block=128,source_bytes=32769,signature_bytes=auto.stat().st_size,byte_equal_explicit=True,cases=2)
        report['status']='passed'
    finally:
        (dest/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    return report
