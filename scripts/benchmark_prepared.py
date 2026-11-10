"""Fixed in-process Native comparison and separate pinned-rdiff reuse checks."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'tests/benchmarks/prepared-config.json'
OUT = ROOT / '_build/benchmarks-prepared'
UPSTREAM = 'e364852674780e43d578e4239128ff7014190ed3'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')


def inputs(size, count, config):
    old = bytes(b & 127 for b in hashlib.shake_256((config['domain'] + str(size) + '/old').encode()).digest(size))
    news = []
    pos = size // 2 + 17
    for i in range(count):
        if i % 4 == 0:
            new = old[:pos] + bytes(128 + (i+j) % 128 for j in range(64)) + old[pos+64:]
        elif i % 4 == 1:
            new = bytes(128 + (i+j) % 128 for j in range(32)) + old
        elif i % 4 == 2:
            new = old[:pos] + old[pos+64:]
        else:
            new = old
        news.append(new)
    return old, news


def statistics_for(rows):
    if len(rows) != 9 or [r['round'] for r in rows] != list(range(9)):
        raise ValueError('Incomplete rounds')
    for i, r in enumerate(rows):
        if r.get('status') != 'validated' or r['phase'] != ('warmup' if i < 2 else 'formal'):
            raise ValueError('Invalid or failed sample')
        for key in ('one_total_us', 'prepared_total_us', 'prepare_us'):
            if not math.isfinite(r[key]) or r[key] < 0:
                raise ValueError('Invalid timing')
        for key in ('one_generation_us', 'prepared_generation_us'):
            if len(r[key]) != r['reuse_count'] or any(not math.isfinite(t) or t < 0 for t in r[key]):
                raise ValueError('Invalid individual times')
    formal = rows[2:]
    def stats(values):
        return dict(median=statistics.median(values), minimum=min(values), maximum=max(values))
    return dict(prepare_us=stats([r['prepare_us'] for r in formal]),
                one_total_us=stats([r['one_total_us'] for r in formal]),
                prepared_total_us=stats([r['prepared_total_us'] for r in formal]),
                one_generation_us=[stats([r['one_generation_us'][i] for r in formal]) for i in range(formal[0]['reuse_count'])],
                prepared_generation_us=[stats([r['prepared_generation_us'][i] for r in formal]) for i in range(formal[0]['reuse_count'])])


def self_check(config):
    assert config['sizes'] == [65536,1048576] and config['reuse_counts'] == [1,4,16]
    assert (config['warmups'],config['rounds'],config['block_len'],config['strong_sum_len']) == (2,7,2048,32)
    for size in config['sizes']:
        old, news = inputs(size,16,config)
        assert (old,news) == inputs(size,16,config) and len(set(map(sha,news))) >= 9
        assert len(old)==size and len(news[0])==size and len(news[1])==size+32 and len(news[2])==size-64 and news[3]==old
    rows=[dict(round=i,phase='warmup' if i<2 else 'formal',status='validated',reuse_count=1,
               prepare_us=1,one_total_us=i+10,prepared_total_us=i+2,one_generation_us=[1],prepared_generation_us=[1]) for i in range(9)]
    assert statistics_for(rows)['prepared_total_us']['median']==7
    for bad in [rows[:-1],[dict(r,status='failed') for r in rows],[dict(r,prepared_total_us=float('nan')) for r in rows]]:
        try: statistics_for(bad)
        except ValueError: pass
        else: raise AssertionError('Bad samples entered statistics')
    print('Prepared benchmark self-check: deterministic inputs, exact plan, raw-total statistics and failed/incomplete rejection passed.')


def main():
    global OUT
    parser=argparse.ArgumentParser()
    parser.add_argument('--self-check',action='store_true')
    parser.add_argument('--interop-only',action='store_true')
    args=parser.parse_args()
    if args.interop_only:
        OUT = OUT / 'interop-check'
    config=json.loads(CONFIG.read_text())
    self_check(config)
    if args.self_check:return
    assert sys.platform.startswith('linux'), 'Measured/rdiff reference environment is Linux Native'
    OUT.mkdir(parents=True,exist_ok=True)
    commands=(OUT/'commands.log').open('a',encoding='utf8')
    def run(argv):
        p=subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,text=True,encoding='utf8',timeout=600)
        commands.write(json.dumps(dict(argv=list(map(str,argv)),exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr))+'\n');commands.flush()
        p.check_returncode()
        return p.stdout
    lock=json.loads((ROOT/'toolchain.lock.json').read_text())
    assert run(['moonc','-v']).strip()==lock['moonc']
    help_text=run(['moon','build','--help'])
    assert '--release' in help_text and '--target' in help_text
    run([sys.executable, ROOT/'scripts/verify_dependencies.py'])
    run(['moon','--target-dir',OUT/'build','build','probes/prepared','--target','native','--release'])
    exe=OUT/'build/native/release/build/probes/prepared/prepared.exe'
    assert exe.read_bytes()[:4]==b'\x7fELF'
    rdiff=ROOT/'.toolchain/reference/build/rdiff'
    assert run(['git','-C',ROOT/'.toolchain/reference/source','rev-parse','HEAD']).strip()==UPSTREAM
    run(['git','-C',ROOT/'.toolchain/reference/source','diff','--exit-code'])
    git=['git','-c','safe.directory='+ROOT.as_posix()]
    source=dict(sha=run([*git,'rev-parse','HEAD']).strip(),dirty=bool(run([*git,'status','--porcelain']).strip()))
    runtime=[p for p in ROOT.glob('*.mbt') if not p.name.endswith(('_test.mbt','_wbtest.mbt'))]
    runtime += [ROOT/'probes/prepared/main.mbt',ROOT/'probes/prepared/moon.pkg',ROOT/'moon.mod',ROOT/'moon.pkg',ROOT/'toolchain.lock.json',ROOT/'dependencies.lock.json']
    manifest=dict(config=config,config_sha256=sha(CONFIG.read_bytes()),source=source,
                  runtime_sha256={p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in runtime},
                  executable=str(exe),executable_sha256=sha(exe.read_bytes()),rdiff=str(rdiff),rdiff_sha256=sha(rdiff.read_bytes()),
                  rdiff_version=run([rdiff,'--version']),toolchain=run(['moon','version','--all']),compiler=run(['cc','--version']),
                  cpu=run(['lscpu']),memory=run(['free','-b']),os=platform.platform(),os_release=Path('/etc/os-release').read_text(),
                  build='release',clock='core/bench monotonic clock, microseconds',inputs=[])
    save('manifest.json',manifest)
    report=dict(source=source,status='incomplete',fixed_fixture_restores=0,same_process_multi_target_restores=0,timed_output_restores=0)
    save('interop-report.json',report)
    with tempfile.TemporaryDirectory(prefix='moonlibsync-prepared-') as directory:
        temp=Path(directory)
        manifest['input_output_location']=str(temp)
        manifest['filesystem']=run(['findmnt','-n','-o','FSTYPE','-T',temp]).strip()
        def signature(old, folder):
            path=folder/'old.bin';path.write_bytes(old)
            sig=folder/'old.sig'
            run([rdiff,'-H','blake2','-R','rabinkarp','-b','2048','-S','32','signature',path,sig])
            return path,sig
        def validate(old_path,new,path,restore):
            encoded=path.read_bytes()
            copied=check_contents(inspect_delta(encoded),old_path.read_bytes(),new)
            run([rdiff,'patch',old_path,path,restore])
            assert restore.read_bytes()==new
            return dict(delta_bytes=len(encoded),copy_bytes=copied,delta_sha256=sha(encoded))
        # Original independent upstream signatures, not regenerated by MoonBit.
        # Fixture names come from the independently frozen fixture directory.
        fixture_folders=sorted(p for p in (ROOT/'tests/fixtures').iterdir() if (p/'old.sig').is_file())
        assert len(fixture_folders)==16
        for i,fixture in enumerate(fixture_folders):
            folder=temp/('fixed-'+str(i));folder.mkdir()
            run([exe,'generate',fixture/'old.sig',folder,fixture/'new.bin'])
            validate(fixture/'old.bin',(fixture/'new.bin').read_bytes(),folder/'reused-0.delta',folder/'restored')
            report['fixed_fixture_restores']+=1
        old,news=inputs(65536,16,config)
        folder=temp/'multi';folder.mkdir();old_path,sig=signature(old,folder)
        paths=[]
        for i,new in enumerate(news):
            path=folder/f'new-{i}';path.write_bytes(new);paths.append(path)
        run([exe,'generate',sig,folder,*paths])
        for i,new in enumerate(news):
            stats=validate(old_path,new,folder/f'reused-{i}.delta',folder/f'restored-{i}')
            assert stats['copy_bytes']>=len(old)-4096
            report['same_process_multi_target_restores']+=1
        if not args.interop_only:
            raw=[];summaries=[]
            save('measurements.json',raw)
            for size in config['sizes']:
                for count in config['reuse_counts']:
                    folder=temp/f'bench-{size}-{count}';folder.mkdir()
                    old,news=inputs(size,count,config);old_path,sig=signature(old,folder)
                    paths=[]
                    for i,new in enumerate(news):
                        path=folder/f'new-{i}';path.write_bytes(new);paths.append(path)
                    n=(len(sig.read_bytes())-12)//36
                    metadata=dict(old_bytes=size,signature_bytes=sig.stat().st_size,records=n,reuse_count=count,
                                  old_sha256=sha(old),signature_sha256=sha(sig.read_bytes()),new=[dict(bytes=len(new),sha256=sha(new)) for new in news],
                                  retained_structure=dict(records=n,final_ordinals=n,strong_payload_bytes=n*32,ordinal_payload_bytes=n*4,raw_signature_retained=False,heap_or_rss_measured=False))
                    manifest['inputs'].append(metadata);save('manifest.json',manifest)
                    lines=run([exe,'bench',sig,folder,*paths]).splitlines()
                    rows=[json.loads(line) for line in lines];assert len(rows)==9
                    for row in rows:
                        row.update(size=size,reuse_count=count,status='incomplete',outputs=[])
                        raw.append(row);save('measurements.json',raw)
                        for engine in ['one','prepared']:
                            for i,new in enumerate(news):
                                path=folder/f'{engine}-{row["round"]}-{i}.delta'
                                stats=validate(old_path,new,path,folder/f'restored-{engine}-{row["round"]}-{i}')
                                assert stats['copy_bytes']>=size-4096
                                row['outputs'].append(dict(engine=engine,target=i,**stats))
                                report['timed_output_restores']+=1
                        row['status']='validated';save('measurements.json',raw)
                    summaries.append(dict(size=size,reuse_count=count,**statistics_for(rows)))
                    save('summary.json',summaries)
                    print('Measured and validated',size,count,flush=True)
        save('manifest.json',manifest)
    report['status']='passed';save('interop-report.json',report)
    print('Prepared upstream checks:',report)


if __name__=='__main__':
    main()
