"""Additional auto CLI checks; preserve every original case and count separately."""
import json,struct


def exercise(root,case,report):
    def run(name,args,expected=0,**kw):
        result=case('auto/'+name,args,expected,**kw)
        report['cases'][-1]['auto_added']=True
        return result
    old=root/'auto.old';old.write_bytes(bytes(range(256))*128+b'!')
    for label,opts,block,strong in [('default',[],2048,32),('numeric',['--block-size','17'],17,32),('auto',['--block-size','auto'],128,32),('auto16',['--sum-size','16','--block-size','auto'],128,16)]:
        dest=root/('auto-'+label+'.sig')
        run(label,['signature',old,dest,*opts],watch=[old],output=dest)
        data=dest.read_bytes();assert struct.unpack('>III',data[:12])==(0x72730147,block,strong)
        assert len(data)==12+((old.stat().st_size+block-1)//block)*(4+strong)
        if label=='auto':
            explicit=root/'auto-explicit.sig'
            run('explicit-equality',['signature',old,explicit,'--block-size','128'],watch=[old],output=explicit)
            assert explicit.read_bytes()==data
            p=run('inspect',['inspect-signature',dest,'--json'],watch=[dest],text=True)
            # case() returns CompletedProcess in the shared harness.
            assert json.loads(p.stdout)['summary']['block_len']=='128'
    empty=root/'auto-empty';empty.write_bytes(b'');sig=root/'auto-empty.sig'
    run('empty',['signature',empty,sig,'--block-size','auto'],watch=[empty],output=sig)
    assert struct.unpack('>III',sig.read_bytes())==(0x72730147,2048,32)
    for label,opts in [('zero',['--block-size','0']),('negative',['--block-size','-1']),('upper',['--block-size','AUTO']),('mixed',['--block-size','Auto']),('empty',['--block-size','']),('space',['--block-size','auto ']),('sum-auto',['--sum-size','auto']),('repeat-auto',['--block-size','auto','--block-size','auto']),('repeat-mixed',['--block-size','17','--block-size','auto']),('repeat-reverse',['--block-size','auto','--block-size','17'])]:
        out=root/(label+'-failed.sig')
        run('usage/'+label,['signature',old,out,*opts],2,watch=[old],output=out,contains='usage:')
    for command,paths in [('delta',[old,old]),('patch',[old,old]),('basis-info',[old,old]),('make-manifest',[old,old,old,old]),('patch-verified',[old,old,old])]:
        dest=root/('auto-'+command+'.out')
        run('other/'+command,[command,*paths,dest,'--block-size','auto'],2,watch=[old],output=dest,contains='signature-only')
    for name,input_path,out_path,needle in [('missing',root/'missing',root/'auto-failed.sig','read'),('directory',root,root/'auto-failed.sig','unsupported input'),('existing',old,old,'exists')]:
        run('file/'+name,['signature',input_path,out_path,'--block-size','auto'],1,watch=[old],output=out_path,contains=needle)
    option_path=root/'--auto-old';option_path.write_bytes(b'abc');dash=root/'--auto-new'
    run('separator',['signature','--block-size','auto','--','--auto-old','--auto-new'],watch=[option_path],output=dash)
    assert struct.unpack('>III',dash.read_bytes()[:12])==(0x72730147,64,32)
    literal=root/'-';literal_out=root/'auto-literal.sig'
    assert literal.is_file() and 0<literal.stat().st_size<=32768
    run('literal-dash',['signature','--block-size','auto','--','-',literal_out],watch=[literal],output=literal_out)
    assert struct.unpack('>III',literal_out.read_bytes()[:12])==(0x72730147,64,32)
    huge=root/'auto-huge.old'
    with huge.open('wb') as f:f.truncate(67108865)
    failed=root/'auto-huge.sig'
    run('oversize',['signature',huge,failed,'--block-size','auto'],1,watch=[old],output=failed,contains='ReadLimitExceeded')
    again=root/'auto-after.sig'
    run('after-errors',['signature',old,again,'--block-size','auto'],watch=[old],output=again)
    assert again.read_bytes()==(root/'auto-auto.sig').read_bytes()
    report['auto_policy']=dict(policy_version=1,nonempty_bytes=32769,selected_block=128,empty_block=2048,combined_strong=16)
