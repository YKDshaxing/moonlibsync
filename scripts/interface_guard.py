"""Explicit package scope, including absent executable interfaces; no cache glob."""
from pathlib import Path
import subprocess

PACKAGES = ('', 'probes/digest', 'probes/native', 'probes/signature', 'probes/prepared', 'probes/stage_a', 'cmd/moonlibsync', 'examples/basic', 'examples/prepared', 'examples/verified', 'examples/auto')


def snapshot(root):
    paths = [str(Path(package) / 'pkg.generated.mbti').replace('\\', '/') for package in PACKAGES]
    git = ['git', '-c', f'safe.directory={root.as_posix()}']
    tracked = subprocess.check_output([*git, 'ls-tree', '-r', '--name-only', 'HEAD', '--', *paths], cwd=root, text=True).splitlines()
    current = {name: (root / name).read_bytes() if (root / name).is_file() else None for name in paths}
    for name in tracked:
        expected = subprocess.check_output([*git, 'show', 'HEAD:' + name], cwd=root)
        if current[name] != expected:
            raise SystemExit('INTERFACE_BASELINE_MISMATCH: ' + name)
    if current['pkg.generated.mbti'] is None:
        raise SystemExit('INTERFACE_BASELINE_MISSING: pkg.generated.mbti')
    return current


def unchanged(root, before):
    after = snapshot(root)
    changed = [name for name in before if before[name] != after[name]]
    if changed:
        raise SystemExit('INTERFACE_GENERATION_CHANGED: ' + ', '.join(changed))
    return {name: 'absent' if value is None else 'unchanged' for name, value in after.items()}
