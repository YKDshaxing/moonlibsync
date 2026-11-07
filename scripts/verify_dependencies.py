"""Verify pinned versions, closure, archives and installed dependency sources.

This project maintains dependencies.lock.json; moon does not generate it.
The empty .mooncakes/.moon-lock is a mutex, not a resolution lock.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "dependencies.lock.json").read_text(encoding="utf-8"))["packages"]
MOON_HOME = Path(os.environ.get("MOON_HOME", str(Path.home() / ".moon")))


def imports(text):
    return dict(re.findall(r'"([^"@]+)@([^"\s]+)"', text))


expected = {name: spec["version"] for name, spec in LOCK.items()}
if imports((ROOT / "moon.mod").read_text(encoding="utf-8")) != expected:
    raise SystemExit("Root module pins differ from dependencies.lock.json")
for name, spec in LOCK.items():
    version = spec["version"]
    archive = MOON_HOME / "registry/cache" / name / (version + ".zip")
    if hashlib.sha256(archive.read_bytes()).hexdigest() != spec["sha256"]:
        raise SystemExit(f"Archive checksum mismatch: {name}@{version}")
    installed = ROOT / ".mooncakes" / name
    manifest = (installed / "moon.mod").read_text(encoding="utf-8")
    found = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.M)
    if not found or found[1] != version or imports(manifest) != spec["deps"]:
        raise SystemExit(f"Resolved dependency differs: {name}@{version}")
    for dep, dep_version in spec["deps"].items():
        if expected.get(dep) != dep_version:
            raise SystemExit(f"Unpinned transitive dependency: {dep}@{dep_version}")
    with zipfile.ZipFile(archive) as source:
        for info in source.infolist():
            if not info.is_dir():
                file = (installed / info.filename).resolve()
                if not file.is_relative_to(installed.resolve()):
                    raise SystemExit("Unsafe source path")
                if file.read_bytes() != source.read(info):
                    raise SystemExit(f"Extracted source drift: {name}/{info.filename}")
    print(f"Verified {name}@{version} sha256={spec['sha256']} (archive and source)")
