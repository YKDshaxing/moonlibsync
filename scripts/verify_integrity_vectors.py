"""Independent hashlib/JSON oracle; --export only writes the new integrity data.

SHA inputs: empty, abc, 00 7f 80 ff; (73*i+19)%256 for 55,56,63,64,65,1024.
SIG bytes are frozen rdiff 2.3.4/e3648526 reference output, not this encoder.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'tests/integrity'
SIG_ABC=bytes.fromhex('72730147000008000000002066298923bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319')


def descriptor(data):
    return dict(byte_length=str(len(data)),sha256=hashlib.sha256(data).hexdigest())


def wire(obj):
    return (json.dumps(obj,separators=(',',':'))+'\n').encode()


def expected():
    vectors=[]
    for label,data in [('empty',b''),('abc',b'abc'),('binary',bytes.fromhex('007f80ff'))]+[(str(n),bytes((i*73+19)%256 for i in range(n))) for n in [55,56,63,64,65,1024]]:
        vectors.append(dict(id=label,input_hex=data.hex(),sha256=hashlib.sha256(data).hexdigest()))
    cases=[]
    for label,old,sig,new,delta in [
        ('empty-default',b'',bytes.fromhex('727301470000080000000020'),b'',bytes.fromhex('7273023600')),
        ('abc-default',b'abc',SIG_ABC,b'abc',bytes.fromhex('7273023645000300')),
        ('one-nondefault',b'\x00',bytes.fromhex('7273014700000007000000010810422503'),b'\x00',bytes.fromhex('7273023645000100')),
    ]:
        basis=dict(schema_version=1,kind='moonlibsync-basis-info',basis=descriptor(old),signature=descriptor(sig))
        update=dict(schema_version=1,kind='librsync-delta',basis=descriptor(old),signature=descriptor(sig),delta=descriptor(delta),result=descriptor(new))
        cases.append(dict(id=label,old_hex=old.hex(),signature_hex=sig.hex(),new_hex=new.hex(),delta_hex=delta.hex(),basis_json=wire(basis).decode(),update_json=wire(update).decode()))
    return dict(source='Python hashlib.sha256 + json; rdiff v2.3.4/e364852674780e43d578e4239128ff7014190ed3 fixed SIG bytes',sha256=vectors,manifests=cases)


def byte_literal(data):
    return 'b"'+''.join('\\x%02x'%b for b in data)+'"'


def main():
    data=expected()
    if '--export' in sys.argv:
        FOLDER.mkdir(parents=True,exist_ok=True)
        (FOLDER/'vectors.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8',newline='\n')
        for kind in ['basis','update']:
            (FOLDER/(kind+'.json')).write_text(data['manifests'][1][kind+'_json'],encoding='utf8',newline='\n')
        lines=['// SPDX-License-Identifier: LGPL-2.1-or-later','// Independent oracle transport: scripts/verify_integrity_vectors.py; do not hand edit.','','///|','fn sha256_reference_vectors() -> Array[(Bytes, String)] {','  [']
        for v in data['sha256']:
            if v['id'].isdigit():
                expr=f"Bytes::makei({int(v['id'])}, i => ((i * 73 + 19) % 256).to_byte())"
            else:expr=byte_literal(bytes.fromhex(v['input_hex']))
            lines.append(f'    ({expr}, "{v["sha256"]}"),')
        lines+=['  ]','}','','///|','fn manifest_reference_vectors() -> Array[(Bytes, Bytes, Bytes, Bytes, Bytes, Bytes)] {','  [']
        for case in data['manifests']:
            vals=[bytes.fromhex(case[k]) for k in ['old_hex','signature_hex','new_hex','delta_hex']]+[case[k].encode() for k in ['basis_json','update_json']]
            lines.append('    ('+', '.join(byte_literal(v) for v in vals)+'),')
        lines+=['  ]','}','']
        (ROOT/'manifest_vectors_wbtest.mbt').write_text('\n'.join(lines),encoding='utf8',newline='\n')
    assert json.loads((FOLDER/'vectors.json').read_text())==data
    assert (FOLDER/'basis.json').read_bytes()==data['manifests'][1]['basis_json'].encode()
    assert (FOLDER/'update.json').read_bytes()==data['manifests'][1]['update_json'].encode()
    source=(ROOT/'manifest_vectors_wbtest.mbt').read_text()
    assert all(v['sha256'] in source for v in data['sha256'])
    print('Integrity oracle verified: 9 SHA-256 vectors and 3 independent manifest pairs; original fixtures untouched.')


if __name__=='__main__':main()
