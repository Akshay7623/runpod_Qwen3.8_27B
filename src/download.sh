#!/usr/bin/env bash
# Downloads files from the FP8/ folder of $MODEL_REPO at $MODEL_REVISION into
# $MODEL_PATH. Arguments are file names or patterns inside FP8/.
#
# The Dockerfile calls this once per weight file so that each file gets its own
# layer: GHCR rejects layers over 10 GB, and the weights total 30.9 GB.
set -euo pipefail

patterns=()
for p in "$@"; do patterns+=("FP8/$p"); done

# The repo is on Hugging Face's Xet storage. HF_XET_HIGH_PERFORMANCE lets the
# download use every core and all the bandwidth, since RunPod stops
# `docker build` after 30 minutes. HF_HOME is a temporary folder, so no
# Hugging Face cache is left in the image.
HF_HOME=/tmp/hf-home HF_XET_HIGH_PERFORMANCE=1 \
    python3 - "$MODEL_REPO" "$MODEL_REVISION" "${patterns[@]}" <<'EOF'
import sys
from huggingface_hub import snapshot_download

snapshot_download(sys.argv[1], revision=sys.argv[2], allow_patterns=sys.argv[3:], local_dir="/tmp/model")
EOF

# Fails here if the patterns matched nothing.
mkdir -p "$MODEL_PATH"
mv /tmp/model/FP8/* "$MODEL_PATH"/
rm -rf /tmp/model /tmp/hf-home
