"""Compile external positive/negative consumers against all three real .mi files."""
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'_build/prepared-encapsulation'
OUT.mkdir(parents=True,exist_ok=True)
build=ROOT/os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')
sources={
    'call':'pub fn run(p : @lib.PreparedSignature, data : Bytes) -> Bytes raise @lib.SyncError { p.delta(data, @lib.Limits::default()) }',
    'index':'pub fn leak(p : @lib.PreparedSignature) -> Unit { ignore(p.index) }',
    'bytes':'pub fn leak(p : @lib.PreparedSignature) -> Int64 { p.signature_bytes }',
    'construct':'pub fn forge() -> @lib.PreparedSignature { { signature_bytes: 12L, index: 0 } }',
}
report=[]
for target in ('native','js','wasm-gc'):
    for name,source in sources.items():
        path=OUT/(name+'.mbt');path.write_text(source+'\n',encoding='utf8')
        command=['moonc','check',str(path),'-i',str(build/target/'debug/check/moonlibsync.mi')+':lib',
                 '-pkg','audit/encapsulation','-std-path',str(Path(os.environ['MOON_HOME'])/'lib/core/_build'/target/'release/bundle'),
                 '-target',target,'-no-mi']
        p=subprocess.run(command,cwd=OUT,capture_output=True,text=True,encoding='utf8')
        diagnostic=p.stdout+p.stderr
        (OUT/(target+'-'+name+'.log')).write_text(diagnostic,encoding='utf8')
        if name=='call':assert p.returncode==0,diagnostic
        else:assert p.returncode!=0 and ('[E4036]' if name=='construct' else '[E4091]') in diagnostic,diagnostic
        report.append(dict(target=target,case=name,exit_code=p.returncode,expected_rejection=name!='call'))
(OUT/'report.json').write_text(json.dumps(dict(status='passed',checks=report),indent=2)+'\n',encoding='utf8')
print('Prepared external interface: method accepted and fields/construction rejected on native/js/wasm-gc (12 compiler checks, separate from library tests).')
