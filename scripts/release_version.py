"""One release version source: the root module metadata, never a cached package."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
MODULE='YKDshaxing/moonlibsync'


def metadata(root=ROOT):
    text=(root/'moon.mod').read_text(encoding='utf8')
    name=re.findall(r'^name\s*=\s*"([^"\n]+)"',text,re.M)
    versions=re.findall(r'^version\s*=\s*"([^"\n]+)"',text,re.M)
    assert name==[MODULE] and len(versions)==1,'Release module/version metadata mismatch'
    version=versions[0]
    assert re.fullmatch(r'0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',version),'Expected supported pre-1.0 release version'
    return name[0],version

MODULE,VERSION=metadata()
ARCHIVE=MODULE.replace('/','-')+'-'+VERSION+'.zip'


def consumer_metadata(name='release/consumer'):
    return f'name = "{name}"\nversion = "0.0.0"\nimport {{ "{MODULE}@{VERSION}", }}\n'
