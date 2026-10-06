#!/usr/bin/env bash
# Build Strata v0.1.39 (6f32ec0) with the two patches in patches/ and tag it strata-resident-split:0.1.39.
#   ./build.sh                      clone upstream, apply the patches, docker build
#   CUDA_ARCHITECTURES=86 ./build.sh   one GPU generation (default 86 = RTX 30; 89 = RTX 40, 120 = RTX 50)
#   CHECK=1 ./build.sh              clone, apply and syntax-check the patches; build nothing
# The upstream tree is cloned into a temp dir and patched there; nothing outside it is touched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PIN=6f32ec0
TAG=${TAG:-strata-resident-split:0.1.39}
CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES:-86}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git clone --quiet https://github.com/Niko1221/Strata.git "$work/src"
git -C "$work/src" checkout --quiet "$PIN"
[ "$(git -C "$work/src" rev-parse --short HEAD)" = "$PIN" ] || { echo "FAIL: not at $PIN"; exit 1; }
rm -rf "$work/src/.git"
# -F0: no fuzz. Fuzz once put a hunk into the wrong class of a file and it still compiled.
for p in resident-split-0.1.39 tool-choice-0.1.39; do
  ( cd "$work/src" && patch -p1 -F0 --no-backup-if-mismatch < "$HERE/patches/$p.patch" ) \
    || { echo "FAIL: $p.patch does not apply exactly"; exit 1; }
done
grep -q 'struct SwapHome' "$work/src/src/program/generate.cpp" || { echo "FAIL: resident patch missing"; exit 1; }
python3 -m py_compile "$work/src/serve/server.py" "$work/src/serve/frontend.py"
[ "${CHECK:-0}" = 1 ] && { echo "patches apply and the Python compiles; CHECK=1, nothing built"; exit 0; }
# The compile takes every core for several minutes.
docker build -t "$TAG" --build-arg CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES" --build-arg BUILD_VISION=0 "$work/src"
docker image inspect --format "$TAG {{.Id}}" "$TAG"
