#!/usr/bin/bash

set -euo pipefail

MODEL_PATH=${MODEL_PATH:-nvidia/Qwen3.5-397B-A17B-NVFP4}
PORT=${PORT:-8000}

exec ts serve \
    --model "${MODEL_PATH}" \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --world-size 8 \
    --dist-init-addr 127.0.0.1:4000 \
    --gpu-memory-utilization 0.8 \
    --attention-backend trtllm \
    --moe-backend flashinfer_trtllm \
    --kv-cache-dtype fp8_e4m3 \
    --load-format auto \
    --comm-fusion-max-num-tokens 4096 \
    --moe-tp-size 1 \
    --dense-tp-size 8 \
    --ep-size 8 \
    --max-model-len 262144 \
    --speculative-algorithm MTP \
    --speculative-draft-model-path "${MODEL_PATH}" \
    --speculative-num-steps 3
