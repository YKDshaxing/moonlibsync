"""Check foundations and bounded signatures; reject interface auto-write drift."""

import json
import os
import re
from pathlib import Path
import subprocess
import sys
from interface_guard import snapshot, unchanged

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)


def run(*args):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(args, check=True)


def moon(*args):
    build_dir = os.environ.get("MOONLIBSYNC_BUILD_DIR")
    run("moon", *(["--target-dir", build_dir] if build_dir else []), *args)


# Resource evidence is derived from the same unfiltered suite executions below,
# never an extra matrix. Keep library counts distinct from interop/Python tools.
resource_dir = ROOT / "_build/resources"
resource_dir.mkdir(parents=True, exist_ok=True)
resource_names = re.findall(r'^test "(resources[^"\n]*)"', (ROOT / "resources_wbtest.mbt").read_text(encoding="utf-8"), re.M)
inspection_names = [name for path in (ROOT / "inspect_test.mbt", ROOT / "inspect_wbtest.mbt")
                    for name in re.findall(r'^test "([^"\n]*)"', path.read_text(encoding="utf-8"), re.M)]
prepared_names = [name for path in (ROOT / "prepared_test.mbt", ROOT / "prepared_wbtest.mbt")
                  for name in re.findall(r'^test "([^"\n]*)"', path.read_text(encoding="utf-8"), re.M)]
resource_report = {
    "format": 1, "status": "not_executed", "baseline_library_tests": 80,
    "resource_tests": len(resource_names), "resource_test_names": resource_names,
    "inspection_tests": len(inspection_names), "inspection_test_names": inspection_names,
    "prepared_tests": len(prepared_names), "prepared_test_names": prepared_names,
    "boundary_checks": {"signature": 4, "delta": 8, "patch": 4},
    "boundary_policy": "need-1 rejects; need and need+1 succeed; invalid configurations tested separately",
    "source_sha": subprocess.check_output(["git", "-c", f"safe.directory={ROOT.as_posix()}", "rev-parse", "HEAD"], text=True).strip(),
    "source_dirty": bool(subprocess.check_output(["git", "-c", f"safe.directory={ROOT.as_posix()}", "status", "--porcelain"], text=True).strip()),
    "targets": {},
}

(resource_dir / "report.json").write_text(json.dumps(resource_report, indent=2) + "\n", encoding="utf-8")

def test_target(target):
    build_dir = os.environ.get("MOONLIBSYNC_BUILD_DIR")
    command = ["moon", *(["--target-dir", build_dir] if build_dir else []), "test", "--target", target, "--package", "YKDshaxing/moonlibsync"]
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    print(result.stdout, end="", flush=True)
    (resource_dir / (target + ".log")).write_text(result.stdout, encoding="utf-8")
    totals = re.search(r"Total tests: (\d+), passed: (\d+), failed: (\d+)\.", result.stdout)
    expected = resource_report["baseline_library_tests"] + len(resource_names) + len(inspection_names) + len(prepared_names)
    complete = bool(totals and tuple(map(int, totals.groups())) == (expected, expected, 0) and result.returncode == 0)
    resource_report["targets"][target] = {
        "command": command, "exit_code": result.returncode,
        "expected_library_tests": expected,
        "observed_summary": list(map(int, totals.groups())) if totals else None,
        "resource_tests_passed": len(resource_names) if complete else None,
        "complete": complete,
    }
    resource_report["status"] = "passed" if len(resource_report["targets"]) == 3 and all(v["complete"] for v in resource_report["targets"].values()) else "incomplete"
    (resource_dir / "report.json").write_text(json.dumps(resource_report, indent=2) + "\n", encoding="utf-8")
    result.check_returncode()
    if not complete:
        raise SystemExit("Unfiltered suite count mismatch; update the reviewed resource ledger: " + target)


before = snapshot(ROOT)
lock = json.loads((ROOT / "toolchain.lock.json").read_text(encoding="utf-8"))
actual = subprocess.check_output(["moonc", "-v"], text=True).strip()
if actual != lock["moonc"]:
    raise SystemExit(f"Expected {lock['moonc']}; got {actual}")
moon("version", "--all")
moon("fmt", "--check")
run(sys.executable, "scripts/check_fixtures.py")
if not os.environ.get("MOONLIBSYNC_OFFLINE_INDEX"):
    moon("update")
# Fetch without rewriting local interface files, then verify every dependency.
moon("check", "--target", "wasm-gc", "--no-mbti")
run(sys.executable, "scripts/verify_dependencies.py")
run(sys.executable, "scripts/reference_vectors.py")
for target in ("native", "js", "wasm-gc"):
    for action in ("check", "build"):
        moon(action, "--target", target)
    test_target(target)
    moon("run", "probes/digest", "--target", target)
    run(sys.executable, "scripts/check_example.py", "--target", target)
run(sys.executable, "scripts/native_probe.py")
moon("info")
interface_report = unchanged(ROOT, before)
interface_dir = ROOT / os.environ.get("MOONLIBSYNC_BUILD_DIR", "_build") / "interfaces"
interface_dir.mkdir(parents=True, exist_ok=True)
(interface_dir / "report.json").write_text(json.dumps(interface_report, indent=2) + "\n", encoding="utf-8")
run("git", "-c", f"safe.directory={ROOT.as_posix()}", "diff", "--check")
print("Foundation checks and three public examples passed; Linux rdiff interoperability runs in the reference job.")
