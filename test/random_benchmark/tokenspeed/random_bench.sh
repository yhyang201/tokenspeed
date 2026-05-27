#!/usr/bin/bash
#
# Random-dataset perf sweep over TP8 / TP8EP8 deployments.
#
# Each deployment is launched in turn (configs/<config>.sh), then evalscope
# perf is run for four input/output combos with concurrency [1, 8, 32, 64].
#
# Layout:
#   outputs/<sweep_ts>/<config>/<case_name>/<model>/benchmark_summary.json
#
# Env knobs:
#   MODEL_PATH   model id / path (default: nvidia/Qwen3.5-397B-A17B-NVFP4)
#   PORT         server port    (default: 8000)
#   CONFIGS      space-separated list (default: "tp8 tp8ep8")
#

set -euo pipefail

MODEL_PATH=${MODEL_PATH:-nvidia/Qwen3.5-397B-A17B-NVFP4}
PORT=${PORT:-8000}
CONFIGS=${CONFIGS:-"tp8 tp8ep8"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PID=
SERVER_LOG=

launch_server() {
    local config=$1
    SERVER_LOG=/tmp/tokenspeed_server_random_${config}.log
    MODEL_PATH="$MODEL_PATH" PORT="$PORT" \
        setsid "${SCRIPT_DIR}/configs/${config}.sh" > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!
}

wait_for_ready() {
    local TIMEOUT=600
    local START=$SECONDS
    until curl -sf -o /dev/null "http://127.0.0.1:${PORT}/readiness"; do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "Server died early. Last log lines:" >&2
            tail -100 "$SERVER_LOG" >&2
            return 1
        fi
        if grep -qE "CUDA out of memory|OutOfMemory|RuntimeError|Killed" "$SERVER_LOG"; then
            echo "Server hit a fatal error:" >&2
            tail -100 "$SERVER_LOG" >&2
            return 1
        fi
        if (( SECONDS - START > TIMEOUT )); then
            echo "Timeout after ${TIMEOUT}s waiting for server" >&2
            return 1
        fi
        sleep 5
    done
    echo "Server ready after $((SECONDS - START))s"
}

stop_server() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Stopping ts serve (pgid $SERVER_PID)..."
        kill -TERM -"$SERVER_PID" 2>/dev/null || true
        for _ in {1..20}; do
            kill -0 "$SERVER_PID" 2>/dev/null || break
            sleep 1
        done
        kill -KILL -"$SERVER_PID" 2>/dev/null || true
    fi
    SERVER_PID=
}

wait_for_port_free() {
    local port=${1:-$PORT}
    local timeout=${2:-90}
    local start=$SECONDS
    while ! python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', $port)); s.close()" 2>/dev/null; do
        if (( SECONDS - start > timeout )); then
            echo "Port ${port} still in use after ${timeout}s" >&2
            return 1
        fi
        sleep 1
    done
}

trap stop_server EXIT

wait_for_port_free "$PORT"

URL="http://127.0.0.1:${PORT}/v1/chat/completions"
SWEEP_TS=$(date +%Y%m%d_%H%M%S)
SWEEP_DIR="${SCRIPT_DIR}/outputs/${SWEEP_TS}"
echo "Sweep outputs: ${SWEEP_DIR}"

# 4 (input_len, output_len) cases. Each case sweeps concurrency 1/8/32/64.
# Format: "<case_name> <min_in> <max_in> <max_out>"
CASES=(
    "in1k_out1k    1024 1024 1024"
    "in1k_out8k    1024 1024 8192"
    "in8k_out1k    8192 8192 1024"
    "in4k_out4k    4096 4096 4096"
)

run_perf() {
    local config=$1
    local case_name=$2
    local in_min=$3
    local in_max=$4
    local out_len=$5

    local out_dir="${SWEEP_DIR}/${config}/${case_name}"
    echo "--- Perf: config=${config} case=${case_name}"
    evalscope perf \
        --parallel 1 8 32 64 \
        --number 5 20 100 200 \
        --model "$MODEL_PATH" \
        --url "$URL" \
        --api openai \
        --dataset random \
        --max-tokens "$out_len" \
        --min-tokens "$out_len" \
        --prefix-length 0 \
        --min-prompt-length "$in_min" \
        --max-prompt-length "$in_max" \
        --tokenizer-path "$MODEL_PATH" \
        --warmup-num 0.1 \
        --extra-args '{"ignore_eos": true}' \
        --name "${config}_${case_name}" \
        --outputs-dir "$out_dir" \
        --no-timestamp
}

for CONFIG in $CONFIGS; do
    echo "============================================="
    echo "=== Running config: ${CONFIG}"
    echo "============================================="
    launch_server "$CONFIG"

    if ! wait_for_ready; then
        stop_server
        wait_for_port_free "$PORT"
        exit 1
    fi

    for CASE_LINE in "${CASES[@]}"; do
        # shellcheck disable=SC2086
        set -- $CASE_LINE
        run_perf "$CONFIG" "$1" "$2" "$3" "$4"
    done

    stop_server
    wait_for_port_free "$PORT"
done

echo
echo "=== Sweep done. Aggregating ==="
python3 "${SCRIPT_DIR}/collect_outputs.py" "${SWEEP_DIR}"
