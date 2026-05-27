#!/usr/bin/env python3
"""Aggregate random-dataset perf sweep results into one summary table.

Expected sweep layout (produced by random_bench.sh and the CI yaml):

    <sweep_dir>/<config>/<case>/<run_name>/benchmark_summary.json

Where:
    <config> e.g. tp8, tp8ep8 (or single-config when invoked from CI yaml,
                  in which case it can also be passed directly as <sweep_dir>)
    <case>   e.g. in1k_out1k, in1k_out8k, in8k_out1k, in4k_out4k
    <run_name> per-concurrency subdir created by evalscope (varies by version)

Each benchmark_summary.json is one (concurrency) data point. We compute:
    decode TPS/user      = 1000 / TPOT(ms)
    total throughput tps = "Total Throughput (tok/s)"
    AR (acceptance rate) = "Decoded Tok/Iter"

Usage:
    python3 collect_outputs.py <sweep_dir> [-o out.csv]
"""

import argparse
import csv
import json
import re
import sys
from pathlib import Path

# Parsing helpers ---------------------------------------------------------

CASE_ORDER = ["in1k_out1k", "in1k_out8k", "in8k_out1k", "in4k_out4k"]


def _case_key(case: str) -> int:
    try:
        return CASE_ORDER.index(case)
    except ValueError:
        return len(CASE_ORDER)


def _summaries(root: Path):
    """Yield (config, case, concurrency, summary_dict).

    The directory tree may look like:
        root/<config>/<case>/.../benchmark_summary.json   (sweep mode)
        root/<case>/.../benchmark_summary.json            (single config)
    We auto-detect which level <config> sits at.
    """
    for summary_path in root.rglob("benchmark_summary.json"):
        rel = summary_path.relative_to(root).parts
        # rel = (config, case, ..., benchmark_summary.json)
        # or   = (case,   ..., benchmark_summary.json)
        if not rel:
            continue
        # First non-summary part is either <config> or <case>.
        first = rel[0]
        if any(c in first for c in ("tp", "ep", "dp")):
            config = first
            case = rel[1] if len(rel) >= 3 else "unknown"
        else:
            config = "default"
            case = first
        try:
            data = json.loads(summary_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            print(f"[warn] skip {summary_path}: {e}", file=sys.stderr)
            continue
        conc = data.get("Concurrency") or 0
        yield config, case, int(conc), data, summary_path


def collect(root: Path):
    rows = []
    for config, case, conc, s, _path in _summaries(root):
        tpot_ms = float(s.get("TPOT (ms)") or 0.0)
        tps_user = 1000.0 / tpot_ms if tpot_ms else 0.0
        ar = float(s.get("Decoded Tok/Iter") or 0.0)
        total_tps = float(s.get("Total Throughput (tok/s)") or 0.0)
        ttft_ms = float(s.get("TTFT (ms)") or 0.0)
        rows.append(
            {
                "config": config,
                "case": case,
                "concurrency": conc,
                "tps_per_user": round(tps_user, 2),
                "total_throughput": round(total_tps, 2),
                "acceptance_rate": round(ar, 4),
                "ttft_ms": round(ttft_ms, 2),
                "tpot_ms": round(tpot_ms, 3),
            }
        )
    rows.sort(key=lambda r: (r["config"], _case_key(r["case"]), r["concurrency"]))
    return rows


def print_table(rows):
    if not rows:
        print("[random perf] no benchmark_summary.json found", file=sys.stderr)
        return
    print("\n=== Random perf sweep ===")
    header = (
        f"  {'Config':<10} {'Case':<14} {'Conc.':>6} "
        f"{'TPS/user':>10} {'Total TPS':>12} "
        f"{'AR':>6} {'TTFT(ms)':>10} {'TPOT(ms)':>10}"
    )
    print(header)
    print("  " + "-" * (len(header) - 2))
    for r in rows:
        print(
            f"  {r['config']:<10} {r['case']:<14} {r['concurrency']:>6} "
            f"{r['tps_per_user']:>10.2f} {r['total_throughput']:>12.2f} "
            f"{r['acceptance_rate']:>6.2f} {r['ttft_ms']:>10.2f} "
            f"{r['tpot_ms']:>10.3f}"
        )
    print()


def write_csv(out_path: Path, rows):
    fieldnames = list(rows[0].keys()) if rows else [
        "config", "case", "concurrency", "tps_per_user",
        "total_throughput", "acceptance_rate", "ttft_ms", "tpot_ms",
    ]
    with out_path.open("w", newline="") as fp:
        w = csv.DictWriter(fp, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sweep_dir", type=Path,
                    help="Directory containing per-config / per-case evalscope outputs")
    ap.add_argument("-o", "--output", type=Path, default=None,
                    help="Optional CSV output path")
    args = ap.parse_args()

    if not args.sweep_dir.is_dir():
        sys.exit(f"Not a directory: {args.sweep_dir}")

    rows = collect(args.sweep_dir)
    print_table(rows)
    if args.output:
        write_csv(args.output, rows)
        print(f"[random perf] wrote CSV: {args.output}")

    if not rows:
        sys.exit(1)


if __name__ == "__main__":
    main()
