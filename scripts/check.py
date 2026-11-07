"""Check foundations and bounded signatures; reject interface auto-write drift."""

import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)


def run(*args):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(args, check=True)


def moon(*args):
    build_dir = os.environ.get("MOONLIBSYNC_BUILD_DIR")
    run("moon", *(["--target-dir", build_dir] if build_dir else []), *args)


def interfaces():
    files = [ROOT / "pkg.generated.mbti", *sorted((ROOT / "probes").glob("*/pkg.generated.mbti"))]
    return {str(p.relative_to(ROOT)): p.read_bytes() for p in files if p.is_file()}


before = interfaces()
if "pkg.generated.mbti" not in before:
    raise SystemExit("Missing committed core interface; review moon info output first")
lock = json.loads((ROOT / "toolchain.lock.json").read_text(encoding="utf-8"))
actual = subprocess.check_output(["moonc", "-v"], text=True).strip()
if actual != lock["moonc"]:
    raise SystemExit(f"Expected {lock['moonc']}; got {actual}")
moon("version", "--all")
moon("fmt", "--check")
run(sys.executable, "scripts/verify_fixtures.py")
if not os.environ.get("MOONLIBSYNC_OFFLINE_INDEX"):
    moon("update")
# Fetch without rewriting local interface files, then verify every dependency.
moon("check", "--target", "wasm-gc", "--no-mbti")
run(sys.executable, "scripts/verify_dependencies.py")
run(sys.executable, "scripts/reference_vectors.py")
for target in ("native", "js", "wasm-gc"):
    for action in ("check", "build", "test"):
        moon(action, "--target", target)
    moon("run", "probes/digest", "--target", target)
run(sys.executable, "scripts/native_probe.py")
moon("info")
after = interfaces()
if before != after:
    changed = sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
    raise SystemExit("Public interfaces changed; review the diff: " + ", ".join(changed))
run("git", "-c", f"safe.directory={ROOT.as_posix()}", "diff", "--check")
print("All foundation and bounded signature checks passed. No rdiff interop or full algorithm delivery claim.")
