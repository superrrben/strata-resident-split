#!/usr/bin/env bash
# Build Strata v0.1.39 with the two patches in patches/ and tag it strata-resident-split:0.1.39.
#   ./build.sh                      clone upstream, apply the patches, docker build
#   CUDA_ARCHITECTURES=86 ./build.sh   one GPU generation (default 86 = RTX 30; 89 = RTX 40, 120 = RTX 50)
#   CHECK=1 ./build.sh              clone, apply and syntax-check the patches; build nothing
# The upstream tree is cloned into a temp dir and patched there; nothing outside it is touched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# Pinned by tag AND by tree hash. Upstream's history was rewritten after this repo was first built (v0.1.39 was 6f32ec0, now a1641e9); the files
# are identical, so the tree hash is the stable identity and a plain commit hash is not.
PIN_TAG=v0.1.39
PIN_TREE=27b0e86ffc000d325a9fbf0bd753ee5817eddaa7
TAG=${TAG:-strata-resident-split:0.1.39}
CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES:-86}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git clone --quiet https://github.com/Niko1221/Strata.git "$work/src"
git -C "$work/src" checkout --quiet "$PIN_TAG"
[ "$(git -C "$work/src" rev-parse 'HEAD^{tree}')" = "$PIN_TREE" ] || { echo "FAIL: $PIN_TAG is not the tree these patches were made against ($PIN_TREE)"; exit 1; }
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
