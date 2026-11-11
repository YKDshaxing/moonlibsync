"""Commit 26 cases, separate from all original CLI counts; also candidate CLI."""
import hashlib,json


def exercise(root,case,report):
    def run(name,args,expected=0,**kw):
        result=case('transfer/'+name,args,expected,**kw)
        report['cases'][-1]['transfer_added']=True
        return result
    def save(name,data):
        p=root/('transfer-'+name);p.write_bytes(data);return p
    old=save('old',b'abcdefghijklmnop');sig=root/'transfer-sig';info=root/'transfer-info'
    run('signature',['signature',old,sig,'--block-size','8'],watch=[old],output=sig)
    run('info',['basis-info',old,sig,info],watch=[old,sig],output=info)
    evidence=[]
    for label,new_bytes,minimum,kind in [('reuse',old.read_bytes(),0,'librsync-delta'),('tie',b'abcdefgh',0,'full-file'),('exact',old.read_bytes(),8,'librsync-delta'),('below',old.read_bytes(),9,'full-file'),('huge',old.read_bytes(),9223372036854775807,'full-file'),('unrelated',b'xyz',0,'full-file'),('magic',b'rs\x026\xff\x00',0,'full-file'),('empty',b'',0,'full-file')]:
        new=save(label+'.new',new_bytes);delta=root/('transfer-'+label+'.delta');manifest=root/('transfer-'+label+'.json');out=root/('transfer-'+label+'.out')
        original=old.read_bytes();old.unlink()
        run(label+'/delta',['delta',sig,new,delta],watch=[sig,new],output=delta)
        run(label+'/make',['make-transfer-manifest',info,sig,new,delta,manifest,'--min-savings',str(minimum)],watch=[info,sig,new,delta],output=manifest)
        assert not old.exists();old.write_bytes(original)
        m=json.loads(manifest.read_bytes());assert m['schema_version']==2 and m['kind']==kind
        payload=delta if kind=='librsync-delta' else new
        assert m['payload']==dict(byte_length=str(payload.stat().st_size),sha256=hashlib.sha256(payload.read_bytes()).hexdigest())
        assert m['result']==dict(byte_length=str(len(new_bytes)),sha256=hashlib.sha256(new_bytes).hexdigest())
        assert set(m)==({'schema_version','kind','basis','signature','payload','result'} if kind=='librsync-delta' else {'schema_version','kind','payload','result'})
        basis=['--basis',old] if kind=='librsync-delta' else []
        run(label+'/apply',['apply-update',payload,manifest,out,*basis],watch=[old,payload,manifest],output=out)
        assert out.read_bytes()==new_bytes
        evidence.append(dict(id=label,kind=kind,new_bytes=len(new_bytes),delta_bytes=delta.stat().st_size,payload_bytes=payload.stat().st_size,min_savings=minimum,manifest=m,payload_sha256=hashlib.sha256(payload.read_bytes()).hexdigest(),restored=True))
    reuse=root/'transfer-reuse.json';full=root/'transfer-unrelated.json';delta=root/'transfer-reuse.delta';new=root/'transfer-unrelated.new'
    bad=save('bad-payload',b'xxx');wrong_old=save('wrong-old',b'ABCDEFGHIJKLMNOP');bad_json=save('bad-json',b'{}')
    for name,args,code,needle in [
        ('missing-basis',['apply-update',delta,reuse],2,'requires --basis'),
        ('full-extra-basis',['apply-update',new,full],2,'forbids --basis'),
        ('bad-json',['apply-update',new,bad_json],1,'InvalidSchema'),
        ('bad-full-payload',['apply-update',bad,full],1,'payload_sha256'),
        ('wrong-kind-payload',['apply-update',delta,full],1,'payload_length'),
        ('bad-old',['apply-update',delta,reuse],1,'basis_sha256'),
        ('missing-payload',['apply-update',root/'nonexistent',full],1,'read'),
    ]:
        dest=root/('transfer-fail-'+name);suffix=['--basis',root/'nonexistent'] if name=='full-extra-basis' else ['--basis',wrong_old] if name=='bad-old' else []
        run(name,[*args,dest,*suffix],code,watch=[old,new,delta,reuse,full],output=dest,contains=needle)
    broken=save('broken-delta',b'rs\x026\xff')
    run('full-still-rejects-bad-candidate',['make-transfer-manifest',info,sig,new,broken,root/'transfer-failed.json'],1,watch=[new,sig,info],output=root/'transfer-failed.json',contains='InvalidOpcode')
    for name,options in [('negative',['--min-savings','-1']),('overflow',['--min-savings','9223372036854775808']),('empty',['--min-savings','']),('auto',['--min-savings','auto']),('repeat',['--min-savings','0','--min-savings','1'])]:
        dest=root/('transfer-usage-'+name)
        run('usage/'+name,['make-transfer-manifest',info,sig,new,delta,dest,*options],2,output=dest,contains='usage:')
    for label,args in [('apply-min',['apply-update',new,full,'--min-savings','0']),('make-basis',['make-transfer-manifest',info,sig,new,delta,'--basis',old]),('basis-duplicate',['apply-update',delta,reuse,'--basis',old,'--basis',old])]:
        dest=root/('transfer-usage-'+label);run(label,[*args,dest],2,output=dest,contains='usage:')
    for target in [new,old,full,delta]:
        run('existing/'+target.name,['apply-update',new,full,target],1,watch=[old,new,full,delta],output=target,contains='exists')
    dash=save('dash-source',b'xyz');special=root/'--transfer-manifest';special.write_bytes(full.read_bytes());dest=root/'--transfer-out'
    run('separator',['apply-update','--',dash,special,dest],watch=[dash,special],output=dest)
    assert dest.read_bytes()==b'xyz'
    dest=root/'transfer-after-errors';run('after-errors',['apply-update',new,full,dest],watch=[new,full],output=dest)
    assert dest.read_bytes()==b'xyz'
    report['transfer_cases']=evidence
