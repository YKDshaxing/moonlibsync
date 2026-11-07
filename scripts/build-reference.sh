#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.toolchain/reference"
SHA=e364852674780e43d578e4239128ff7014190ed3
mkdir -p "$BASE"
exec > >(tee "$BASE/build.log") 2>&1
if [[ ! -d "$BASE/source/.git" ]]; then
  git clone --no-checkout https://github.com/librsync/librsync.git "$BASE/source"
  git -C "$BASE/source" checkout --detach "$SHA"
fi
test "$(git -c safe.directory="$BASE/source" -C "$BASE/source" rev-parse HEAD)" = "$SHA"
git -c safe.directory="$BASE/source" -C "$BASE/source" diff --exit-code HEAD --
test -z "$(git -c safe.directory="$BASE/source" -C "$BASE/source" ls-files --others --exclude-standard)"
cc --version
cmake --version
dpkg-query -W gcc libpopt-dev
cmake -S "$BASE/source" -B "$BASE/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_RDIFF=ON -DUSE_LIBB2=OFF -DENABLE_COMPRESSION=OFF -DENABLE_TRACE=OFF
cmake --build "$BASE/build" --target rdiff -j 2
RDIFF="$BASE/build/rdiff"
"$RDIFF" --version | tee "$BASE/version.txt"
grep -q '2.3.4' "$BASE/version.txt"
grep -q 'src/blake2/blake2b-ref.c' "$BASE/build/compile_commands.json"
echo "Verified source=$SHA blake2=src/blake2/blake2b-ref.c rdiff=$RDIFF"
