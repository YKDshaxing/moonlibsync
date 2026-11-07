"""Install only the locked toolchain into this project's ignored .toolchain.

Uses official versioned URLs, verifies every archive, never edits user PATH or
the system toolchain. Python 3.12+ is required for safe tar extraction.
"""

import hashlib
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "toolchain.lock.json").read_text(encoding="utf-8"))
SYSTEM = platform.system().lower()
if SYSTEM not in ("windows", "linux") or platform.machine().lower() not in (
    "amd64", "x86_64"
):
    raise SystemExit("Only Windows/Linux x86_64 are locked for Commit 1")
SPEC = LOCK["platforms"][SYSTEM + "-x86_64"]
parser = argparse.ArgumentParser()
parser.add_argument("--name", default="selected", choices=("selected", "linux"))
DEST = ROOT / ".toolchain" / parser.parse_args().name
CACHE = ROOT / ".toolchain" / "downloads"
CACHE.mkdir(parents=True, exist_ok=True)


def fetch(relative, filename, expected):
    path = CACHE / filename
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        url = "https://cli.moonbitlang.com/" + urllib.parse.quote(relative, safe="/")
        print("Downloading", url, flush=True)
        urllib.request.urlretrieve(url, path)
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"SHA256 mismatch for {filename}: {actual}")
    print(f"Verified {filename} sha256={actual}", flush=True)
    return path


def extract(path, dest):
    dest.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                if not (dest / name).resolve().is_relative_to(dest.resolve()):
                    raise SystemExit("Unsafe archive path")
            archive.extractall(dest)
    else:
        with tarfile.open(path) as archive:
            archive.extractall(dest, filter="data")


binary = fetch(
    f"binaries/{LOCK['version']}/{SPEC['archive']}", SPEC["archive"], SPEC["sha256"]
)
core = fetch("cores/" + SPEC["core_archive"], SPEC["core_archive"], SPEC["core_sha256"])
extract(binary, DEST)
extract(core, DEST / "lib")
if SYSTEM != "windows":
    for file in (DEST / "bin").rglob("*"):
        if file.is_file():
            file.chmod(file.stat().st_mode | 0o111)
env = os.environ | {"MOON_HOME": str(DEST)}
env["PATH"] = str(DEST / "bin") + os.pathsep + env["PATH"]
moon = str(DEST / "bin" / ("moon.exe" if SYSTEM == "windows" else "moon"))
moonc = str(DEST / "bin" / ("moonc.exe" if SYSTEM == "windows" else "moonc"))
actual = subprocess.check_output([moonc, "-v"], env=env, text=True).strip()
if actual != LOCK["moonc"]:
    raise SystemExit(f"Unexpected compiler: {actual}")
subprocess.run([moon, "-C", str(DEST / "lib/core"), "bundle", "--all"], env=env, check=True)
subprocess.run([moon, "version", "--all"], env=env, check=True)
print("Installed isolated toolchain. Set MOON_HOME and prepend its bin to PATH.")
