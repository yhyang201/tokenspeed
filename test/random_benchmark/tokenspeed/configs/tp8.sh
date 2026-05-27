#!/usr/bin/bash

set -euo pipefail

MODEL_PATH=${MODEL_PATH:-nvidia/Qwen3.5-397B-A17B-NVFP4}
PORT=${PORT:-8000}

exec ts serve \
    --model "${MODEL_PATH}" \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --world-size 8 \
    --gpu-memory-utilization 0.8 \
    --moe-backend flashinfer_trtllm \
    --attention-backend trtllm \
    --load-format auto \
    --comm-fusion-max-num-tokens 4096 \
    --max-model-len 262144 \
    --kv-cache-dtype fp8_e4m3 \
    --speculative-algorithm MTP \
    --speculative-draft-model-path "${MODEL_PATH}" \
    --speculative-num-steps 3
