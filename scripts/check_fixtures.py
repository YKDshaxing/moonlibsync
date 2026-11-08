"""Mandatory CI fixture entry; child failure must reach the caller."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / 'scripts/verify_fixtures.py')], cwd=ROOT, check=True)
