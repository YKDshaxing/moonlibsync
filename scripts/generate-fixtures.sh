#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RDIFF="$ROOT/.toolchain/reference/build/rdiff"
test -x "$RDIFF"
test "$(git -c safe.directory="$ROOT/.toolchain/reference/source" -C "$ROOT/.toolchain/reference/source" rev-parse HEAD)" = e364852674780e43d578e4239128ff7014190ed3
python3 "$ROOT/scripts/fixture_data.py" "$RDIFF" "$@"
