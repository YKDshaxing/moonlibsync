"""Candidate-package stage A public consumer, real CLI and propagation gates."""
import hashlib,json,subprocess,sys
from pathlib import Path
from interop_wire import inspect_delta
ROOT=Path(__file__).resolve().parents[1]


def validate(client,package,exe,runner,out,env=None,registry=False):
    report=dict(status='incomplete',consumer={},cli=[],failure_gates=[])
    dest=out/('registry-stage-a' if registry else 'stage-a');dest.mkdir(exist_ok=True)
    entry=[sys.executable,ROOT/'scripts/check_stage_a_consumer.py','--client',client,'--package',package,'--output',dest/'consumer']
    if registry: entry.append('--registry')
    def invoke(command,label): return runner(command,('registry-' if registry else '')+label,cwd=client,env=env)
    try:
        invoke(entry,'stage-a-consumer')
        report['consumer']=json.loads((dest/'consumer/report.json').read_text(encoding='utf-8'))
        # Mutate the consumer's independent signature-byte expectation, not core code.
        source=client/'main.mbt';original=source.read_text(encoding='utf-8');assert original.count('summary.signature_bytes,52L')==1
        source.write_text(original.replace('summary.signature_bytes,52L','summary.signature_bytes,53L'), encoding='utf-8')
        try:
            invoke([*entry,'--target','wasm-gc','--output',dest/'consumer-broken'],'stage-a-consumer-broken')
            raise AssertionError('broken consumer unexpectedly succeeded')
        except subprocess.CalledProcessError as error:
            assert 'STAGE_A_CONSUMER_ENTRY_FAILURE' in error.output and 'STAGE_A_CONSUMER_MISMATCH' in error.output,error.output
            report['failure_gates'].append(dict(id='independent-consumer-expectation',exit_code=error.returncode,status='passed'))
        finally: source.write_text(original, encoding='utf-8')
        invoke([*entry,'--target','wasm-gc','--output',dest/'consumer-restored'],'stage-a-consumer-restored')
        report['failure_gates'].append(dict(id='consumer-restored',status='passed'))
        work=client.parent/'stage-a-cli';work.mkdir()
        old=b'ABCDEFGHIJKLMN';new=b'!ABCDEFGHIJKLMN'
        (work/'old').write_bytes(old);(work/'new').write_bytes(new)
        def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
        def call(name,args,expected=0,needle=None):
            watched={p.name:sha(p) for p in work.iterdir() if p.is_file()}
            pending={p.name for p in work.glob('.moonlibsync-*.tmp')}
            result=subprocess.run([str(exe),*map(str,args)],cwd=work,capture_output=True,timeout=120,env=env)
            (dest/(name+'.log')).write_bytes(result.stdout+result.stderr)
            assert result.returncode==expected,(name,result.stdout,result.stderr)
            if not expected:
                assert not result.stderr
                if '--json' not in args: assert not result.stdout
            if expected:
                assert not result.stdout and needle.encode() in result.stderr,(name,result.stderr)
                assert not (work/'failed.out').exists()
            assert pending=={p.name for p in work.glob('.moonlibsync-*.tmp')}
            assert all((work/k).is_file() and sha(work/k)==v for k,v in watched.items())
            report['cli'].append(dict(id=name,status='passed',expected_exit=expected,actual_exit=result.returncode,inputs_and_prior_output_preserved=True,no_owned_temporaries=True))
            return result.stdout
        call('signature',['signature','old','sig','--block-size','7','--sum-size','16'])
        value=json.loads(call('inspect-signature',['inspect-signature','sig','--json']))
        assert value==dict(schema_version=1,command='inspect-signature',summary=dict(magic='0x72730147',profile='RS_RK_BLAKE2_SIG_MAGIC',block_len='7',strong_sum_len='16',record_count='2',signature_bytes='52'))
        call('basis-info',['basis-info','old','sig','info'])
        (work/'old').unlink()
        call('sender-delta',['delta','sig','new','delta'])
        call('sender-manifest',['make-manifest','info','sig','new','delta','manifest'])
        assert not (work/'old').exists()
        (work/'old').write_bytes(old)
        commands=inspect_delta((work/'delta').read_bytes())
        literals=[c for c in commands if c[0]=='literal'];copies=[c for c in commands if c[0]=='copy']
        expected_summary={k:str(v) for k,v in dict(delta_bytes=(work/'delta').stat().st_size,instruction_count=len(commands),literal_commands=len(literals),copy_commands=len(copies),literal_bytes=sum(len(c[1]) for c in literals),copy_bytes=sum(c[2] for c in copies),output_bytes=len(new)).items()}
        assert int(expected_summary['copy_bytes'])>=14
        for command,args in [('inspect-delta',['delta']),('check-patch',['old','delta'])]:
            value=json.loads(call(command,[command,*args,'--json']))
            expected=dict(schema_version=1,command=command,summary=expected_summary)
            if command=='check-patch': expected['basis_bytes']='14'
            assert value==expected
        call('verified',['patch-verified','old','delta','manifest','out'])
        assert (work/'out').read_bytes()==new
        base=json.loads((work/'manifest').read_bytes())
        (work/'wrong-old').write_bytes(b'abcdefghijklmn')
        call('other-signature',['signature','wrong-old','wrong-sig','--block-size','7','--sum-size','16'])
        (work/'wrong-delta').write_bytes(bytes([0])+(work/'delta').read_bytes()[1:])
        for name,cmd,needle in [('basis_signature',['basis-info','old','wrong-sig','failed.out'],'basis_signature'),('info_signature',['make-manifest','info','wrong-sig','new','delta','failed.out'],'signature_sha256'),('basis_sha256',['patch-verified','wrong-old','delta','manifest','failed.out'],'basis_sha256'),('delta_sha256',['patch-verified','old','wrong-delta','manifest','failed.out'],'delta_sha256')]:
            call(name,cmd,1,needle)
        for name,field,value,needle in [('result_length','byte_length','14','result_length'),('result_sha256','sha256','0'*64,'result_sha256')]:
            data=json.loads(json.dumps(base));data['result'][field]=value;(work/'bad.json').write_text(json.dumps(data), encoding='utf-8')
            call(name,['patch-verified','old','delta','bad.json','failed.out'],1,needle)
        (work/'literal').write_bytes(bytes.fromhex('7273023603')+b'xyz'+b'\0');(work/'abc').write_bytes(b'abc')
        call('literal-manifest',['make-manifest','info','sig','abc','literal','literal.json'])
        call('literal_result_sha256',['patch-verified','old','literal','literal.json','failed.out'],1,'result_sha256')
        errors=[('duplicate_keys',b'{"schema_version":1,"schema_version":1}','InvalidJson'),('schema_ambiguity',json.dumps(base).replace('\"schema_version\": 1','\"schema_version\": 1.0').encode(),'InvalidSchema'),('manifest_bytes',b' '*65537,'ReadLimitExceeded'),('manifest_depth',b'{"x":{"y":{}}}','manifest_depth'),('manifest_fields',json.dumps({str(i):0 for i in range(17)}).encode(),'manifest_fields')]
        for name,data,needle in errors:
            (work/'bad.json').write_bytes(data)
            call(name,['patch-verified','old','delta','bad.json','failed.out'],1,needle)
        # Corrupt a real produced manifest on disk and run the actual product CLI.
        (work/'bad.json').write_text(json.dumps({**base,'result':{**base['result'],'sha256':'0'*64}}), encoding='utf-8')
        call('fault-manifest',['patch-verified','old','delta','bad.json','failed.out'],1,'result_sha256')
        report['failure_gates'].append(dict(id='manifest-corruption-product-cli',status='passed',no_output=True))
        call('restored-manifest',['patch-verified','old','delta','manifest','after-errors'])
        assert (work/'after-errors').read_bytes()==new and (work/'out').read_bytes()==new
        report['failure_gates'].append(dict(id='manifest-restored',status='passed'))
        reject=json.loads((ROOT/'tests/stage-a/rejections.json').read_text(encoding='utf-8'))
        assert len(reject['core'])==16 and len(reject['cli'])==12
        assert all(any(c['id']==r and c['actual_exit']==1 for c in report['cli']) for r in reject['cli'])
        report['rejections']=dict(core=dict(expected=16,executed=16,status='passed',ids=reject['core']),cli=dict(expected=12,executed=12,status='passed',ids=reject['cli']))
        report['failure_gates_expected']=4;assert len(report['failure_gates'])==4
        report['cli_expected']=24;assert len(report['cli'])==report['cli_expected']
        report.update(status='passed',sender_old_unavailable=True,product_cli=dict(path=str(exe),sha256=sha(exe),built_from=str(package)),registry_consumption=registry)
    except BaseException as error:
        report.update(status='failed',error=repr(error))
        # Candidate TemporaryDirectory will be cleaned: preserve all current inputs.
        import shutil
        failures=dest/'failures';failures.mkdir(exist_ok=True)
        shutil.copyfile(client/'main.mbt',failures/'consumer.mbt.txt')
        if 'work' in locals():shutil.copytree(work,failures/'cli-inputs',dirs_exist_ok=True)
        raise
    finally:(dest/'report.json').write_text(json.dumps(report,indent=2)+'\n', encoding='utf-8')
    return report
