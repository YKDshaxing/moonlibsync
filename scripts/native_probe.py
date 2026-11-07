"""External-process Native probe shared by Windows and Linux."""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
build_dir = os.environ.get("MOONLIBSYNC_BUILD_DIR", "_build")
subprocess.run(["moon", "--target-dir", build_dir, "build", "probes/native", "--target", "native"], cwd=ROOT, check=True)
EXE = ROOT / build_dir / "native/debug/build/probes/native/native.exe"
BASE = (ROOT / "_build/probe-runs").resolve()
BASE.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="native-", dir=BASE) as directory:
    scratch = Path(directory).resolve()
    assert scratch.is_relative_to(BASE) and scratch != BASE
    sample = scratch / "binary sample with spaces.bin"
    for mode, path, expected_code, marker in (
        ("roundtrip", sample, 0, "roundtrip-ok bytes=00,7f,80,ff empty=ok"),
        ("fail", sample, 23, "intentional-failure"),
        ("read-missing", scratch / "does not exist.bin", 24, "io-error:"),
        ("write-missing", scratch / "absent parent/output.bin", 24, "io-error:"),
    ):
        result = subprocess.run([str(EXE), mode, str(path)], capture_output=True, text=True)
        print(f"mode={mode} exit={result.returncode} stdout={result.stdout.strip()} stderr={result.stderr.strip()}", flush=True)
        assert result.returncode == expected_code, result
        if expected_code == 0:
            assert marker in result.stdout and not result.stderr, result
            assert sample.read_bytes() == bytes([0, 0x7F, 0x80, 0xFF])
            assert Path(str(sample) + ".empty").read_bytes() == b""
        else:
            assert marker in result.stderr and not result.stdout, result
    print("Native file/args/stderr/exit probe passed.")
