"""Finite representative inputs, reusing the fixed Commit 25/26 rules."""
import json,hashlib
from pathlib import Path
from benchmark import inputs
ROOT=Path(__file__).resolve().parents[1]


def inputs_for(spec):
    mode=spec['input']
    if mode=='empty':return b'',b''
    if mode=='tiny':return b'abc',b'xyz'
    if mode=='tie':return b'abcdefghijklmnop',b'abcdefgh'
    if mode=='block':return b'abcdefghijklmnop',b'abcdefghijklmnop'
    if mode=='tail':return b'abcdefghijklmnop!',b'abcdefghijklmnop!'
    config=json.loads((ROOT/'tests/benchmarks/config.json').read_text())
    return inputs(65536,mode,config)


def digest(data):return dict(byte_length=str(len(data)),sha256=hashlib.sha256(data).hexdigest())
