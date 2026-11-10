"""Frozen stage A generation rules. Independent expected NEW, no binary corpus."""
import hashlib
from fixture_data import cases


def groups(plan):
    result=[]
    gates={'multi':14,'repeat':48,'exact-block':16,'default-edit':2048}
    for name,purpose,old,new,block,strong in cases():
        result.append(dict(id='ref-'+name,old=old,block=block,strong=strong,targets=[dict(id=name,new=new,min_copy=gates.get(name,0))]))
    for spec in plan['synthetic_groups']:
        name=spec['id']
        if name=='bytes': old=b'\0\x80\xffABCDEF'*9+b'z'
        elif name=='pairs': old=bytes(range(256))*2+b'\xfa'
        else:
            seq=b''.join(hashlib.sha256(i.to_bytes(4,'big')).digest() for i in range(32))
            old=seq[:128]+seq[:64]+seq[192:]+b'\0\x80\xff'
        block=spec['block'];tail=len(old)%block
        targets=[]
        for mode in spec['targets']:
            if mode=='same': new=old
            elif mode=='different':
                new=b'\x7f'*len(old)
                assert not set(new)&set(old)
            elif mode=='local': new=old[:17]+b'!'+old[18:]
            elif mode=='head': new=b'!'+old
            elif mode=='move': new=old[block:2*block]+old[:block]+old[2*block:]
            elif mode=='repeat': new=old[:block]*3+old
            elif mode=='tail-middle':
                assert tail
                new=old[:block]+old[-tail:]+old[block:-tail]
            else: raise AssertionError(mode)
            minimum=0 if mode in ('different','local') else (len(old) if mode=='same' else block)
            targets.append(dict(id=mode,new=new,min_copy=minimum))
        result.append(dict(id=name,old=old,block=block,strong=spec['strong'],targets=targets))
    assert len(result)==plan['expected']['groups']
    pairs=[(g['old'],t['new']) for g in result for t in g['targets']]
    assert len(pairs)==len(set(pairs))==plan['expected']['input_pairs']
    assert {g['block'] for g in result}=={1,2,7,16,64,2048}
    assert {g['strong'] for g in result}=={1,16,32}
    return result
