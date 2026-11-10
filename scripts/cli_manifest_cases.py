"""Commit 22 file workflows; independent hashlib/json expectations, no timing."""
import hashlib
import json
import os


def exercise(root, case, report, links):
    def run(name, args, expected=0, **kw):
        result = case('manifest/' + name, args, expected, **kw)
        report['cases'][-1]['manifest_added'] = True
        return result

    def digest(data):
        return dict(byte_length=str(len(data)), sha256=hashlib.sha256(data).hexdigest())

    old = root/'verified.old'; sig = root/'verified.sig'; new = root/'verified.new'
    info = root/'basis-info.json'; delta = root/'verified.delta'
    manifest = root/'update.json'; out = root/'verified.out'
    basis = b'ABCDEFGHIJKLMN' * 20 + bytes(range(256))
    target = b'!' + basis[:70] + b'change' + basis[76:] + b'?'
    old.write_bytes(basis); new.write_bytes(target)
    run('signature', ['signature', old, sig, '--block-size', '7', '--sum-size', '16'], watch=[old], output=sig)
    run('basis-info', ['basis-info',old,sig,info], watch=[old,sig], output=info)
    expected_info = dict(schema_version=1, kind='moonlibsync-basis-info', basis=digest(basis), signature=digest(sig.read_bytes()))
    assert json.loads(info.read_bytes()) == expected_info
    # OLD is actually unavailable while both sending commands run.
    old.unlink()
    run('sender-delta-no-old', ['delta',sig,new,delta], watch=[sig,new,info], output=delta)
    run('sender-manifest-no-old', ['make-manifest',info,sig,new,delta,manifest], watch=[info,sig,new,delta,old], output=manifest)
    expected = dict(schema_version=1, kind='librsync-delta', basis=digest(basis), signature=digest(sig.read_bytes()), delta=digest(delta.read_bytes()), result=digest(target))
    assert json.loads(manifest.read_bytes()) == expected
    old.write_bytes(basis)
    protected=[old,sig,new,delta,info,manifest]
    run('receiver', ['patch-verified',old,delta,manifest,out], watch=protected, output=out)
    assert out.read_bytes() == target
    # Reuse after failures must preserve this successful result and all inputs.
    protected.append(out)
    badold=root/'wrong.old'; badold.write_bytes(b'X'+basis[1:])
    baddelta=root/'wrong.delta'; baddelta.write_bytes(bytes([delta.read_bytes()[0]^1])+delta.read_bytes()[1:])
    short=root/'short.old'; short.write_bytes(basis[:-1])
    for name, first, second, needle in [('wrong-basis',badold,delta,'basis_sha256'),('wrong-length',short,delta,'basis_length'),('wrong-delta',old,baddelta,'delta_sha256')]:
        dest=root/(name+'.out')
        run(name,['patch-verified',first,second,manifest,dest],1,watch=protected+[first,second],output=dest,contains=needle)
    for field, value, needle in [('result',dict(byte_length=str(len(target)-1),sha256=expected['result']['sha256']),'result_length'), ('result',dict(byte_length=str(len(target)),sha256='0'*64),'result_sha256'), ('signature',dict(byte_length='11',sha256='0'*64),'signature.byte_length')]:
        bad=root/('bad-'+needle+'.json'); data=dict(expected);data[field]=value;bad.write_text(json.dumps(data))
        dest=root/('bad-'+needle+'.out')
        run(needle,['patch-verified',old,delta,bad,dest],1,watch=protected+[bad],output=dest,contains=needle)
    # A correct hash binding never bypasses strict parsing/COPY range checks.
    for name, data, needle in [('opcode',bytes.fromhex('727302365500'),'InvalidOpcode'), ('copy',bytes.fromhex('727302364600ffff00'),'CopyOutOfBounds'), ('trailing',bytes.fromhex('7273023600ff'),'TrailingData')]:
        dd=root/(name+'.delta');dd.write_bytes(data)
        mm=root/(name+'.json');value=dict(expected);value['delta']=digest(data);mm.write_text(json.dumps(value))
        dest=root/(name+'.out')
        run(name,['patch-verified',old,dd,mm,dest],1,watch=protected+[dd,mm],output=dest,contains=needle)
    # Sender factory cannot prove recovery; actual receiver catches xyz != abc.
    abc=root/'abc.old'; abc.write_bytes(b'abc'); ss=root/'abc.sig'; ii=root/'abc.info'
    nn=root/'abc.new';nn.write_bytes(b'abc');dd=root/'xyz.delta';dd.write_bytes(bytes.fromhex('7273023603')+b'xyz'+b'\0')
    mm=root/'xyz.json'; oo=root/'xyz.out'
    run('abc-sig',['signature',abc,ss],output=ss,watch=[abc])
    run('abc-info',['basis-info',abc,ss,ii],output=ii,watch=[abc,ss])
    run('wrong-literal-manifest',['make-manifest',ii,ss,nn,dd,mm],output=mm,watch=[ii,ss,nn,dd])
    run('wrong-literal-receiver',['patch-verified',abc,dd,mm,oo],1,output=oo,watch=[abc,dd,mm],contains='result_sha256')
    forms=[('basis-info',[old,sig]),('make-manifest',[info,sig,new,delta]),('patch-verified',[old,delta,manifest])]
    for command, inputs in forms:
        for label, args in [('missing',inputs[:-1]),('extra',[*inputs,'one','two']),('json',[*inputs,'unused','--json']),('unknown',[*inputs,'unused','--force'])]:
            run(command+'/'+label,[command,*args],2,watch=protected,contains='usage:')
        for i, source in enumerate(inputs):
            # Every INFO/MANIFEST/SIG/OLD/NEW/DELTA output alias is refused.
            run(command+'/alias'+str(i),[command,*inputs,source],1,watch=protected,output=source,contains='exists')
            dest=root/(command+'-missing'+str(i))
            changed=list(inputs);changed[i]=root/'missing-input'
            run(command+'/missing'+str(i),[command,*changed,dest],1,watch=protected,output=dest,contains=command)
            changed[i]=root
            run(command+'/directory-input'+str(i),[command,*changed,dest],1,watch=protected,output=dest,contains='unsupported input')
        run(command+'/directory-output',[command,*inputs,root],1,watch=protected,contains='exists')
        if links:
            link=root/(command+'-link');link.symlink_to(old)
            run(command+'/link-output',[command,*inputs,link],1,watch=protected+[link],output=link,contains='exists')
            for i in range(len(inputs)):
                changed=list(inputs);changed[i]=link;dest=root/(command+'-link'+str(i))
                run(command+'/link-input'+str(i),[command,*changed,dest],1,watch=protected+[link],output=dest,contains='leaf symlink')
    for command, inputs, index in [('make-manifest',[info,sig,new,delta],0),('patch-verified',[old,delta,manifest],2)]:
        for name, data, needle in [('large',b' '*65537,'ReadLimitExceeded'),('json',b'{','InvalidJson'),('utf8',b'\xff','InvalidUtf8'),('schema',b'{}','InvalidSchema'),('duplicate',b'{"schema_version":1,"schema_version":1}','InvalidJson'),('bom',b'\xef\xbb\xbf{}','InvalidJson')]:
            bad=root/(command+'-'+name+'.json');bad.write_bytes(data);changed=list(inputs);changed[index]=bad;dest=root/(command+'-'+name+'.out')
            run(command+'/'+name,[command,*changed,dest],1,watch=protected+[bad],output=dest,contains=needle)
    # Every content input uses the existing bounded reader, before allocation.
    caps={'basis-info':[67108864,16777216], 'make-manifest':[65536,16777216,67108864,83886080], 'patch-verified':[67108864,83886080,65536]}
    for command, inputs in forms:
        for i, cap in enumerate(caps[command]):
            big=root/('large-'+str(cap))
            if not big.exists():
                with big.open('wb') as f: f.truncate(cap+1)
            changed=list(inputs);changed[i]=big;dest=root/(command+'-large'+str(i))
            run(command+'/limit'+str(i),[command,*changed,dest],1,watch=protected,output=dest,contains='ReadLimitExceeded')
    # Empty basis/new still needs signature, END and the empty SHA-256 binding.
    empty=root/'verified.empty';empty.write_bytes(b'')
    es=root/'manifest-empty.sig';ei=root/'manifest-empty.info';ed=root/'manifest-empty.delta';em=root/'manifest-empty.manifest';eo=root/'manifest-empty.out'
    for name,args,dest in [('signature',['signature',empty,es],es),('basis',['basis-info',empty,es,ei],ei),('delta',['delta',es,empty,ed],ed),('manifest',['make-manifest',ei,es,empty,ed,em],em),('patch',['patch-verified',empty,ed,em,eo],eo)]:
        run('empty/'+name,args,watch=[empty],output=dest)
    assert eo.read_bytes()==b'' and json.loads(em.read_bytes())['result']==digest(b'')
    # A lone '-' and option-looking paths after -- are actual files.
    dash=root/'-';dash.write_bytes(manifest.read_bytes());special=root/'--verified-out'
    run('separator',['patch-verified','--',old,delta,'-',special],watch=protected+[dash],output=special)
    assert special.read_bytes()==target
    # Check the normal entry again after all failures, with fresh output.
    again=root/'verified-again.out'
    run('success-after-failures',['patch-verified',old,delta,manifest,again],watch=protected,output=again)
    assert again.read_bytes()==target and out.read_bytes()==target
    report['verified_workflow']=dict(old_unavailable_at_sender=True, independent_json=True, result_sha256=digest(target)['sha256'], restored=True)
