"""Real Native CLI tests. Separate from library99 and Python interop-tool6."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
OUTPUT = ROOT / os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build') / 'cli'
OUTPUT.mkdir(parents=True, exist_ok=True)
report = dict(format=1, status='running', platform=platform.platform(), cases=[],
              native_helper_tests=dict(expected=6, passed=0, status='not_executed'),
              baseline_core_library_tests=99, baseline_python_interop_tool_tests=6,
              cleanup='not_completed', unsupported=[])
log = (OUTPUT/'commands.log').open('w', encoding='utf-8')
root = None


def run(argv, cwd=ROOT, expected=None):
    argv = list(map(str, argv))
    try:
        p = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=120)
    except BaseException as error:
        log.write(json.dumps(dict(argv=argv, cwd=str(cwd), error=repr(error)))+'\n'); log.flush()
        raise
    log.write(json.dumps(dict(argv=argv, cwd=str(cwd), exit_code=p.returncode,
                             stdout=p.stdout.decode('utf-8', errors='replace'), stderr=p.stderr.decode('utf-8', errors='replace')))+'\n')
    log.flush()
    if expected is not None:
        assert p.returncode == expected, (argv, p.returncode, expected, p.stdout, p.stderr)
    return p


def snapshot(path):
    path = Path(path)
    if path.is_symlink(): return ('symlink', os.readlink(path))
    if not path.exists(): return ('absent',)
    if path.is_dir(): return ('directory', sorted(p.name for p in path.iterdir()))
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(65536): h.update(chunk)
    st = path.stat()
    return ('file', st.st_size, h.hexdigest(), st.st_ino, st.st_nlink)


def temps():
    return {str(p.relative_to(root)) for p in root.rglob('.moonlibsync-*.tmp')}


def case(name, args, expected=0, watch=(), output=None, contains=None, text=False, prefix=()):
    protected = list(dict.fromkeys([Path(p) for p in watch] + ([Path(output)] if output else [])))
    before = {str(p): snapshot(p) for p in protected}
    pending = temps()
    p = run([*prefix, exe, *args], cwd=root, expected=expected)
    if expected:
        assert p.stderr and not p.stdout, (name,p.stdout,p.stderr)
        assert b'backtrace' not in p.stderr.lower() and b'panic' not in p.stderr.lower(), name
    elif text:
        assert p.stdout and not p.stderr, name
    else:
        assert not p.stdout and not p.stderr, (name,p.stdout,p.stderr)
    if contains:
        assert contains.encode() in (p.stdout if text else p.stderr), (name,contains,p.stdout,p.stderr)
    # Success writes a new output by design; all failure outputs stay untouched.
    for path, value in before.items():
        if expected == 0 and output and path == str(output): continue
        assert snapshot(path) == value, ('changed protected input/output', name, path)
    assert temps() == pending, ('leaked or deleted temporary', name, temps(), pending)
    report['cases'].append(dict(name=name, expected_exit=expected, actual_exit=p.returncode, passed=True,
                                inputs_preserved=True, owned_temporary_clean=True))
    return p


def sparse(path, size):
    with path.open('xb') as file:
        if os.name == 'nt':
            import msvcrt
            from ctypes import wintypes
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            call = kernel.DeviceIoControl
            call.argtypes = [wintypes.HANDLE,wintypes.DWORD,wintypes.LPVOID,wintypes.DWORD,wintypes.LPVOID,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),wintypes.LPVOID]
            call.restype = wintypes.BOOL
            done = wintypes.DWORD()
            if not call(msvcrt.get_osfhandle(file.fileno()),0x900c4,None,0,None,0,ctypes.byref(done),None):
                raise ctypes.WinError(ctypes.get_last_error())
        file.truncate(size)


try:
    lock = json.loads((ROOT/'toolchain.lock.json').read_text(encoding='utf-8'))
    version = run(['moonc','-v'],expected=0).stdout.decode().strip()
    assert version == lock['moonc']
    report['moonc'] = version
    git = ['git','-c',f'safe.directory={ROOT.as_posix()}']
    report['source_sha'] = run([*git,'rev-parse','HEAD'],expected=0).stdout.decode().strip()
    report['source_dirty'] = bool(run([*git,'status','--porcelain'],expected=0).stdout.strip())
    build = os.environ.get('MOONLIBSYNC_BUILD_DIR','_build')
    run(['moon','--target-dir',build,'build','cmd/moonlibsync','--target','native'],expected=0)
    unit = run(['moon','--target-dir',build,'test','cmd/moonlibsync','--target','native'])
    (OUTPUT/'native-helper-tests.log').write_bytes(unit.stdout+unit.stderr)
    unit_totals = re.search(rb'Total tests: (\d+), passed: (\d+), failed: (\d+)\.',unit.stdout+unit.stderr)
    report['native_helper_tests'].update(status='failed',passed=int(unit_totals[2]) if unit_totals else None,exit_code=unit.returncode)
    assert unit.returncode==0 and unit_totals and tuple(map(int,unit_totals.groups()))==(6,6,0)
    report['native_helper_tests']['status']='passed'
    exe = ROOT/build/'native/debug/build/cmd/moonlibsync/moonlibsync.exe'
    assert exe.is_file()
    report['executable'] = str(exe.resolve())
    with exe.open('rb') as executable_file:
        report['binary_magic'] = executable_file.read(4).hex()
    run_parent = Path(os.environ.get('MOONLIBSYNC_CLI_TMP_PARENT', str(OUTPUT))).resolve()
    root = Path(tempfile.mkdtemp(prefix='run-',dir=run_parent)).resolve()
    assert root.is_relative_to(run_parent) and root.name.startswith('run-')
    report['temporary_parent'] = str(run_parent)
    if os.name == 'nt':
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        fs_name = ctypes.create_unicode_buffer(64)
        volume = kernel.GetVolumeInformationW
        volume.argtypes = [wintypes.LPCWSTR,wintypes.LPWSTR,wintypes.DWORD,wintypes.LPVOID,wintypes.LPVOID,wintypes.LPVOID,wintypes.LPWSTR,wintypes.DWORD]
        volume.restype = wintypes.BOOL
        assert volume(root.drive + chr(92),None,0,None,None,None,fs_name,64)
        report['filesystem'] = fs_name.value
    else:
        report['filesystem'] = run(['findmnt','-n','-o','FSTYPE','-T',root],expected=0).stdout.decode().strip()
    print(f'CLI source: sha={report["source_sha"]} dirty={report["source_dirty"]}; exe={exe}; filesystem={report["filesystem"]}',flush=True)
    foreign = root/'.moonlibsync-foreign.tmp'; foreign.write_bytes(b'FOREIGN')
    module = re.search(r'^version = "([^"]+)"$',(ROOT/'moon.mod').read_text(),re.M)[1]
    case('help',['--help'],text=True,contains='-- ends option parsing')
    case('version',['--version'],text=True,contains='MoonLibSync '+module+'\n')
    # Independent new bytes; each roundtrip calls the actual product executable.
    old = bytes((i*73+19+i//2048*11)%256 for i in range(8197))
    examples = [('default-spaces',old,old[:4096]+b'\x00\x80\xff'+old[4096:],None),
                ('empty-both',b'',b'',None),('empty-old',b'',b'\x00\x80\xff', (2,16)),
                ('empty-new',b'abc',b'',None),('explicit-tail',b'ABCDEFGHIJKLMN\x00\x80\xff',b'ABCDEFG!HIJKLMN\x00\x80\xff',(7,16))]
    for name, old_bytes, new_bytes, options in examples:
        folder = root/name; folder.mkdir()
        oldp,newp,sig,delt,out=[folder/n for n in ['old with spaces.bin','new with spaces.bin','sig with spaces.bin','delta with spaces.bin','out with spaces.bin']]
        oldp.write_bytes(old_bytes); newp.write_bytes(new_bytes)
        arguments = ['signature',oldp,sig] if options is None else ['signature','--sum-size',options[1],oldp,sig,'--block-size',options[0]]
        case(name+'/signature',arguments,watch=[oldp,newp],output=sig)
        # Removing OLD during delta proves the sender does not infer/read it.
        oldp.unlink()
        case(name+'/delta',['delta',sig,newp,delt],watch=[sig,newp],output=delt)
        oldp.write_bytes(old_bytes)
        case(name+'/patch',['patch',oldp,delt,out],watch=[oldp,newp,sig,delt],output=out)
        assert out.read_bytes()==new_bytes, name
        commands=inspect_delta(delt.read_bytes())
        copied=check_contents(commands,old_bytes,new_bytes)
        if name=='default-spaces':
            assert copied>=8192 and delt.stat().st_size<len(new_bytes)
            report['reuse']=dict(new_bytes=len(new_bytes),delta_bytes=delt.stat().st_size,copy_bytes=copied,minimum_copy=8192)
    a=root/'old'; n=root/'new'; sig=root/'sig'; d=root/'delta'
    a.write_bytes(b'abc'); n.write_bytes(b'!abc')
    case('prepare/signature',['signature',a,sig],watch=[a,n],output=sig)
    case('prepare/delta',['delta',sig,n,d],watch=[a,n,sig],output=d)
    for label,block,strong in [('maximum-block','1048576','1'),('leading-zero','0002','01')]:
        boundary=root/('boundary-'+label)
        case('decimal-valid/'+label,['signature',a,boundary,'--block-size',block,'--sum-size',strong],watch=[a],output=boundary)
        import struct
        assert struct.unpack('>III',boundary.read_bytes()[:12])==(0x72730147,int(block),int(strong))
    for name,args in [
        ('unknown-command',['unknown']),('missing-command',[]),('help-extra',['--help','x']),
        ('unknown-option',['signature',a,'x','--wat']),('duplicate-block',['signature',a,'x','--block-size','1','--block-size','2']),
        ('duplicate-sum',['signature',a,'x','--sum-size','1','--sum-size','2']),
        ('missing-path',['patch',a,d]),('missing-option-value',['signature',a,'x','--sum-size']),
        ('extra-path',['delta',sig,n,'x','extra']),('delta-options',['delta',sig,n,'x','--block-size','1']),
    ]: case('usage/'+name,args,2,watch=[a,n,sig,d],output=root/'x')
    for value in ['0','-1','+1','1x','1e2',' 1','1 ','2147483648','99999999999999999999999999999','1048577']:
        case('decimal/block/'+repr(value),['signature',a,'x','--block-size',value],2,watch=[a,n],output=root/'x')
    for value in ['0','-1','33','32x','99999999999999999999999']:
        case('decimal/sum/'+repr(value),['signature',a,'x','--sum-size',value],2,watch=[a,n],output=root/'x')
    # -- permits option-looking paths; a bare '-' denotes a literal file.
    (root/'-').write_bytes(b'A'); (root/'--new').write_bytes(b'BA')
    case('dash/signature',['signature','--','-','--sig'],watch=[root/'-'],output=root/'--sig')
    case('dash/delta',['delta','--','--sig','--new','--delta'],watch=[root/'--sig',root/'--new'],output=root/'--delta')
    case('dash/patch',['patch','--','-','--delta','--out'],watch=[root/'-',root/'--delta'],output=root/'--out')
    assert (root/'--out').read_bytes()==b'BA'
    badsig=root/'bad.sig'; badsig.write_bytes(b'bad')
    baddelta=root/'bad.delta'; baddelta.write_bytes(bytes.fromhex('727302365500'))
    oob=root/'oob.delta'; oob.write_bytes(bytes.fromhex('7273023645030100'))
    folder=root/'input-directory'; folder.mkdir()
    for name,args,needle in [
        ('missing',['signature',root/'missing','x'],'read'),('directory',['signature',folder,'x'],'unsupported input'),
        ('bad-signature',['delta',badsig,n,'x'],'TruncatedInput'),('bad-delta',['patch',a,baddelta,'x'],'InvalidOpcode'),
        ('copy-range',['patch',a,oob,'x'],'CopyOutOfBounds')]:
        case('input/'+name,args,1,watch=[a,n,badsig,baddelta,oob],output=root/'x',contains=needle)
    # Exactly max+1 logical size, sparse allocation rather than huge data writes.
    sizes=[(root/'sparse64',67108865),(root/'sparse16',16777217),(root/'sparse80',83886081)]
    for path,size in sizes: sparse(path,size)
    saved_sparse={str(path):snapshot(path) for path,_ in sizes}
    for name,args in [('signature-old',['signature',sizes[0][0],'x']),('delta-sig',['delta',sizes[1][0],n,'x']),('delta-new',['delta',sig,sizes[0][0],'x']),('patch-old',['patch',sizes[0][0],d,'x']),('patch-delta',['patch',a,sizes[2][0],'x'])]:
        case('read-limit/'+name,args,1,watch=[a,n,sig,d],output=root/'x',contains='ReadLimitExceeded')
    assert all(snapshot(Path(path))==before for path,before in saved_sparse.items())
    # Exact/equivalent existing entries are refused using real OS path semantics.
    (root/'sub').mkdir()
    aliases=[('same',a),('relative','old'),('dot',str(root)+'/./old'),('dotdot',str(root)+'/sub/../old')]
    if os.name=='nt': aliases += [('case',str(a).swapcase()),('slash',str(a).replace('\\','/'))]
    for name,path in aliases:
        case('output-alias/'+name,['signature',a,path],1,watch=[a,n],output=a,contains='output already exists')
    existing=root/'existing'; existing.write_bytes(b'USER CONTENT')
    existingdir=root/'existing-directory'; existingdir.mkdir()
    case('output-existing-file',['signature',a,existing],1,watch=[a],output=existing)
    case('output-existing-directory',['signature',a,existingdir],1,watch=[a],output=existingdir)
    case('output-parent-missing',['signature',a,root/'missing-parent'/'out'],1,watch=[a],output=root/'missing-parent'/'out')
    hard=root/'hard'; os.link(a,hard)
    case('output-hardlink',['signature',a,hard],1,watch=[a],output=hard)
    try:
        link=root/'symbolic'; os.symlink(a,link)
        dangling=root/'dangling'; os.symlink(root/'absent-target',dangling)
    except OSError as error:
        if os.name!='nt' or getattr(error,'winerror',None)!=1314: raise
        report['unsupported'].append(dict(feature='symbolic links',status='not_executed',checks=4,reason=str(error)))
    else:
        case('output-symlink',['signature',a,link],1,watch=[a],output=link)
        case('output-dangling-symlink',['signature',a,dangling],1,watch=[a],output=dangling)
        case('input-symlink',['signature',link,'x'],1,watch=[a,link],output=root/'x',contains='leaf symlink')
        case('input-dangling-symlink',['signature',dangling,'x'],1,watch=[a,dangling],output=root/'x',contains='leaf symlink')
    # Permissions are proven under the same identity that executes this case.
    denied=root/'unwritable'; denied.mkdir()
    acl=root/'saved-acl'
    prefix=[]
    denied_mode=stat.S_IMODE(denied.stat().st_mode)
    root_mode=stat.S_IMODE(root.stat().st_mode)
    permission_shell = shutil.which('pwsh') or 'powershell'
    try:
        if os.name=='nt':
            run([permission_shell,'-NoProfile','-File',ROOT/'scripts/cli-permission.ps1','-Directory',denied,'-Backup',acl,'-Action','Deny'],expected=0)
        else:
            denied.chmod(0o555)
            if os.geteuid()==0:
                root.chmod(0o755)
                prefix=['runuser','-u','nobody','--']
        if prefix:
            run([*prefix,exe,'--version'],expected=0)
        probe=run([*prefix,sys.executable,'-c',"open(__import__('sys').argv[1], 'xb')",denied/'probe'])
        assert probe.returncode!=0 and b'PermissionError' in probe.stderr, ('permission denial not demonstrated',probe.stdout,probe.stderr)
        report['permission_identity']='nobody (controlled root-runner case)' if prefix else 'current process identity'
        case('output-actually-unwritable',['signature',a,denied/'out'],1,watch=[a],output=denied/'out',prefix=prefix)
    finally:
        if os.name=='nt' and acl.exists():
            run([permission_shell,'-NoProfile','-File',ROOT/'scripts/cli-permission.ps1','-Directory',denied,'-Backup',acl,'-Action','Restore'],expected=0)
        elif os.name!='nt':
            denied.chmod(denied_mode)
            root.chmod(root_mode)
    restored_probe=denied/'restored-probe'
    with restored_probe.open('xb') as restored_file: restored_file.write(b'ok')
    restored_probe.unlink()
    report['permission_denial_and_restore_proven']=True
    assert list(denied.iterdir())==[]
    # Three simultaneous pairs, exactly one complete publication per target.
    ra=root/'race-a'; rb=root/'race-b'
    ra.write_bytes(bytes((i*17+31)%256 for i in range(1048576))); rb.write_bytes(b'B'*1048576)
    ea=root/'race-expected-a'; eb=root/'race-expected-b'
    case('race-prepare-a',['signature',ra,ea,'--block-size','64'],watch=[ra],output=ea)
    case('race-prepare-b',['signature',rb,eb,'--block-size','64'],watch=[rb],output=eb)
    race_inputs=[snapshot(ra),snapshot(rb)]
    for i in range(3):
        target=root/f'race-{i}'
        pending=temps()
        argv=[[str(exe),'signature',str(src),str(target),'--block-size','64'] for src in (ra,rb)]
        children=[subprocess.Popen(args,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for args in argv]
        observed=[]
        for args,child in zip(argv,children):
            stdout,stderr=child.communicate(timeout=120)
            log.write(json.dumps(dict(argv=args,cwd=str(root),exit_code=child.returncode,stdout=stdout.decode('utf-8',errors='replace'),stderr=stderr.decode('utf-8',errors='replace')))+'\n');log.flush()
            observed.append((child.returncode,stdout,stderr))
        assert sorted(v[0] for v in observed)==[0,1], observed
        winner=next(j for j,v in enumerate(observed) if v[0]==0)
        assert target.read_bytes()==[ea,eb][winner].read_bytes()
        assert all(not v[1] for v in observed) and observed[1-winner][2]
        assert temps()==pending
        assert [snapshot(ra),snapshot(rb)]==race_inputs
        report['cases'].append(dict(name=f'concurrent-publish-{i}',passed=True,exit_codes=[v[0] for v in observed],complete_winner=True,owned_temporary_clean=True))
    # Inputs may alias each other: empty delta used as both basis and delta.
    empty=root/'empty.delta'; empty.write_bytes(bytes.fromhex('7273023600'))
    case('same-two-readonly-inputs',['patch',empty,empty,root/'same-input-out'],watch=[empty],output=root/'same-input-out')
    assert (root/'same-input-out').read_bytes()==b''
    recovered=root/'after-failures'
    fresh_sig=root/'after-failures.sig'; fresh_delta=root/'after-failures.delta'
    case('normal-after-failures/signature',['signature',a,fresh_sig],watch=[a,n],output=fresh_sig)
    case('normal-after-failures/delta',['delta',fresh_sig,n,fresh_delta],watch=[a,n,fresh_sig],output=fresh_delta)
    case('normal-after-failures/patch',['patch',a,fresh_delta,recovered],watch=[a,n,fresh_sig,fresh_delta],output=recovered)
    assert recovered.read_bytes()==n.read_bytes()
    assert foreign.read_bytes()==b'FOREIGN' and temps()=={foreign.name}
    # Delete only this verified fresh run directory, after restoring permissions.
    assert root.is_relative_to(run_parent) and root.name.startswith('run-')
    shutil.rmtree(root)
    report['cleanup']='owned run directory removed; foreign temporary preserved until run cleanup'
    report['status']='passed'
    print(f'CLI smoke passed: {len(report["cases"])} integration cases; 6 Native helper tests; {len(report["unsupported"])} unsupported optional link feature groups.',flush=True)
    print('CLI reuse:',report['reuse'],flush=True)
    code=0
except BaseException as error:
    report['status']='failed'; report['error']=repr(error)
    report['failure_directory']=str(root)
    print('CLI smoke failed:',repr(error),file=sys.stderr)
    code=1
finally:
    report['integration_cases_passed']=sum(c.get('passed',False) for c in report['cases'])
    (OUTPUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    log.close()
sys.exit(code)
