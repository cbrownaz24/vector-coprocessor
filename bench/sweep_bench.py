#!/usr/bin/env python3
"""
sweep_bench.py - sweep VEC_CMD_QUEUE_DEPTH, measure real cycle counts.

rebuilds riscvvec-sim w/ iverilog -DVEC_CMD_QUEUE_DEPTH=N
-DVEC_CMD_QUEUE_PTR_SZ=log2(N) for each N in sweep, runs every bench,
writes results/sweep_queue.csv.

other params (VLMAX, NUM_LANES, NUM_VREGS) arent parameterized in rtl
so not swept. dont fake analytical nums - if you want those plots,
parameterize the rtl first.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
REPO_DIR = THIS_DIR.parent
BUILD_DIR = REPO_DIR / "build"
VMH_DIR = REPO_DIR / "tests" / "build" / "vmh"
COURSE_BIN = "/home/ECE475/local/bin"

QUEUE_DEPTHS = [2, 4, 8, 16]   # PTR_SZ = log2(depth)

# sweep w/ pipelined-linpack since its the only bench that actually
# fills the cmd queue (no per-row vfence).
PIPELINED_BENCH = "riscv-bmark-linpack-pipelined-16x16.vmh"


def ptr_sz_for(depth: int) -> int:
    if depth & (depth - 1):
        raise ValueError(f"queue depth {depth} must be a power of 2")
    n = 0
    while (1 << n) < depth:
        n += 1
    return n


def env_with_course() -> dict:
    env = os.environ.copy()
    if COURSE_BIN not in env.get("PATH", ""):
        env["PATH"] = f"{COURSE_BIN}:{env.get('PATH', '')}"
    return env


def build_with_depth(depth: int, env: dict) -> bool:
    sim = BUILD_DIR / "riscvvec-sim"
    if sim.exists():
        sim.unlink()
    cmd = [
        "iverilog", "-g2005", "-Wall",
        "-Wno-sensitivity-entire-vector", "-Wno-sensitivity-entire-array",
        f"-DVEC_CMD_QUEUE_DEPTH={depth}",
        f"-DVEC_CMD_QUEUE_PTR_SZ={ptr_sz_for(depth)}",
        "-o", str(sim),
        "-I", "../riscvvec", "-I", "../vc", "-I", "../imuldiv",
        "../riscvvec/riscvvec-sim.v",
    ]
    res = subprocess.run(cmd, cwd=BUILD_DIR, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  BUILD FAILED at depth={depth}:\n{res.stderr[-1500:]}")
        return False
    return True


def run_one(vmh: Path, env: dict) -> tuple[int, bool]:
    sim = BUILD_DIR / "riscvvec-sim"
    res = subprocess.run(
        [str(sim), f"+exe={vmh}", "+stats=1"],
        cwd=BUILD_DIR, env=env, capture_output=True, text=True, timeout=120,
    )
    out = res.stdout
    passed = "*** PASSED ***" in out
    cycles = -1
    for line in out.splitlines():
        if "num_cycles" in line and "=" in line:
            try:
                cycles = int(line.split("=")[1].strip())
            except ValueError:
                pass
            break
    return cycles, passed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--depths", type=int, nargs="*", default=QUEUE_DEPTHS,
                    help="queue depths to sweep (default: 2 4 8 16)")
    ap.add_argument("--label", default="queue", help="output label: results/sweep_<label>.csv")
    args = ap.parse_args()

    bench_cfg = json.loads((THIS_DIR / "benchmarks.json").read_text())
    # sweep pipelined-linpack + every regular vec bench so plot shows
    # contrast btwn fenced + pipelined kernels.
    bench_list = [
        {"name": "linpack-pipelined", "vector_vmh": PIPELINED_BENCH},
    ]
    for bm in bench_cfg["benchmarks"]:
        if bm.get("vector_vmh"):
            bench_list.append({"name": bm["name"], "vector_vmh": bm["vector_vmh"]})
    env = env_with_course()

    rows = []
    for depth in args.depths:
        print(f"=== queue_depth={depth} ===")
        if not build_with_depth(depth, env):
            for bm in bench_list:
                rows.append({"queue_depth": depth, "benchmark": bm["name"], "mode": "vector",
                             "cycles": -1, "passed": False, "note": "build_failed"})
            continue
        for bm in bench_list:
            vmh = VMH_DIR / bm["vector_vmh"]
            if not vmh.exists():
                rows.append({"queue_depth": depth, "benchmark": bm["name"], "mode": "vector",
                             "cycles": -1, "passed": False, "note": "vmh_missing"})
                continue
            cycles, passed = run_one(vmh, env)
            status = "PASS" if passed else "FAIL"
            print(f"  {bm['name']:<22} {status} cycles={cycles}")
            rows.append({"queue_depth": depth, "benchmark": bm["name"], "mode": "vector",
                         "cycles": cycles, "passed": passed, "note": "ok" if passed else "FAIL"})

    out = THIS_DIR / "results" / f"sweep_{args.label}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["queue_depth", "benchmark", "mode", "cycles", "passed", "note"])
        w.writeheader()
        w.writerows(rows)
    print(f"\nwrote {out}")

    # restore default-built sim so other tools see std config
    if not build_with_depth(4, env):
        print("WARNING: failed to rebuild sim with default depth=4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
