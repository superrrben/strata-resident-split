#!/usr/bin/env bash
# One-time data prep for UD-Q4_K_XL, run inside the image you built (it carries tools/ and gguf-py).
#   MODELS=/path/to/models DATA=/path/to/strata-data ./prep.sh
# MODELS must contain Qwen3.8-Flash-Next-UD-Q4_K_XL/UD-Q4_K_XL/*.gguf (4 shards, 111 GB; download from
# https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF, revision 38bb39e, and check the SHA-256s in upstream's docs/UNSLOTH_Q4.md).
# DATA receives packs/ud-q4_k_xl (1.4 GiB, ~10 s), mtp/rt (the draft layer; ~5 GiB download) and config/.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=${IMAGE:-strata-resident-split:0.1.39}
: "${MODELS:?set MODELS}"; : "${DATA:?set DATA}"
GGUF=/models/Qwen3.8-Flash-Next-UD-Q4_K_XL/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf
[ -f "$MODELS${GGUF#/models}" ] || { echo "FAIL: shard 1 not found under $MODELS"; exit 1; }
mkdir -p "$DATA/packs" "$DATA/mtp" "$DATA/config" "$DATA/logs"
# --user: the files in $DATA stay yours instead of root's (the pack step was re-run this way; the MTP steps were not)
U="--user $(id -u):$(id -g) -e HOME=/tmp"
R="docker run --rm $U -v $DATA:/data -v $MODELS:/models:ro --entrypoint .venv/bin/python $IMAGE"
# 1. the pack: dense weights + tokenizer; the experts stay in the GGUF shards and are read in place.
#    --compat-bf16 converts the small Q8_0/F32 tensors the engine wants as BF16 (max abs error 0.0144).
docker run --rm $U -v "$DATA:/data" -v "$MODELS:/models:ro" -e STRATA_GGUF_PY=/opt/strata/third_party/llama.cpp/gguf-py \
  --entrypoint .venv/bin/python "$IMAGE" tools/iq_pack.py --gguf "$GGUF" --out /data/packs/ud-q4_k_xl --compat-bf16
# 2. the MTP draft layer (docs/ORCA.md "Preparation" upstream)
$R tools/mtp_fetch.py fetch --out /data/mtp
$R tools/mtp_fetch.py verify --out /data/mtp
$R tools/mtp_pack.py --src /data/mtp --experts q2_0 --out /data/mtp/mtp-q2_0.gguf
$R tools/mtp_rt.py --gguf /data/mtp/mtp-q2_0.gguf --out /data/mtp/rt
docker run --rm $U -v "$DATA:/data" --entrypoint cp "$IMAGE" data/draft_vocab.bin /data/mtp/rt/draft_vocab.bin
# 3. the server config
cp "$HERE/config/strata-ud-q4_k_xl-resident-park.json" "$DATA/config/"
echo "done. Next: MODELS=$MODELS DATA=$DATA docker compose up -d"
