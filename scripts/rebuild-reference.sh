#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
bash scripts/build-reference.sh
TEMP=$(mktemp -d "$ROOT/.toolchain/reference/rebuild.XXXXXX")
trap 'rm -rf -- "$TEMP"' EXIT
bash scripts/generate-fixtures.sh "$TEMP/fixtures"
cp -a tests/fixtures/opcodes "$TEMP/fixtures/opcodes"
python3 scripts/verify_fixtures.py "$TEMP/fixtures" --export "$TEMP/bytes.mbt"
diff -ru tests/fixtures "$TEMP/fixtures"
cmp reference_bytes_wbtest.mbt "$TEMP/bytes.mbt"
cp -a "$TEMP/fixtures" "$TEMP/corrupt"
printf '\xff' >> "$TEMP/corrupt/empty/old.bin"
if python3 scripts/verify_fixtures.py "$TEMP/corrupt"; then
  echo 'ERROR: corrupted fixture accepted' >&2
  exit 1
fi
echo 'Reference rebuild identical; corrupted copy rejected.'
cp -a "$TEMP/fixtures" "$TEMP/corrupt-opcodes"
printf ' ' >> "$TEMP/corrupt-opcodes/opcodes/vectors.json"
if python3 scripts/verify_fixtures.py "$TEMP/corrupt-opcodes"; then
  echo 'ERROR: corrupted opcode data accepted' >&2
  exit 1
fi
echo 'Corrupted handwritten opcode copy rejected.'
