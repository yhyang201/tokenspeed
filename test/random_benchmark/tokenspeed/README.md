# Random-Dataset Perf Benchmark (Qwen3.5-397B-A17B-NVFP4)

Sweeps four (input, output) length combos at four concurrency levels, against
two TokenSpeed deployments: **TP8** and **TP8EP8**.

## Layout

```
test/random_benchmark/tokenspeed/
├── configs/
│   ├── tp8.sh        # ts serve --world-size 8 ... (no EP)
│   └── tp8ep8.sh     # ts serve ... --moe-tp-size 1 --ep-size 8
├── random_bench.sh   # manual sweep: launches each config in turn
└── collect_outputs.py
```

## Cases

Each case sweeps `--parallel 1 8 32 64` with `--number 5 20 100 200`.

| Case          | Input len | Output len |
| ------------- | --------- | ---------- |
| `in1k_out1k`  | 1024      | 1024       |
| `in1k_out8k`  | 1024      | 8192       |
| `in8k_out1k`  | 8192      | 1024       |
| `in4k_out4k`  | 4096      | 4096       |

## Manual run

```bash
# Default: sweep tp8 then tp8ep8
bash test/random_benchmark/tokenspeed/random_bench.sh

# Override knobs
MODEL_PATH=/data/models/Qwen3.5-397B-A17B-NVFP4 \
PORT=8000 \
CONFIGS="tp8" \
    bash test/random_benchmark/tokenspeed/random_bench.sh
```

Outputs land in `outputs/<timestamp>/<config>/<case>/...`. The script
auto-runs `collect_outputs.py` at the end to print an aggregated table.

## CI integration

Two manual-trigger CI jobs (one per deployment):

* `test/ci/perf/qwen3.5-397b-a17b-nvfp4-evalscope-random-tp8.yaml`
* `test/ci/perf/qwen3.5-397b-a17b-nvfp4-evalscope-random-tp8ep8.yaml`

Both call the same 4-case sweep against an already-launched server
(`server:` block) and post-process via `collect_outputs.py`.
