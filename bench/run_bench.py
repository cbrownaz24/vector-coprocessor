#!/usr/bin/env python3
"""
run_bench.py - sweeps benchmarks across procs.

reads benchmarks.json + processors.json. writes one csv per result type:
    results/main.csv          - every (proc, bench, mode) at default size
    results/daxpy_scaling.csv  - daxpy at varying N
    results/linpack_scaling.csv - linpack at varying mtx dim

each row: processor, benchmark, mode (scalar|vector), size, cycles,
instructions, ipc, passed, note.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
REPO_DIR = THIS_DIR.parent
DEFAULT_VMH_DIR = REPO_DIR / "tests" / "build" / "vmh"
UBMARK_VMH_DIR = REPO_DIR / "ubmark" / "build" / "vmh"
COURSE_BIN = "/home/ECE475/local/bin"

STAT_RE = re.compile(
    r"num_cycles\s*=\s*(?P<cycles>\d+).*?num_inst\s*=\s*(?P<inst>\d+)",
    re.DOTALL,
)
PASS_RE = re.compile(r"\*\*\* PASSED \*\*\*")
FAIL_RE = re.compile(r"\*\*\* FAILED \*\*\*")


@dataclass
class Result:
    processor: str
    benchmark: str
    mode: str
    size: int
    cycles: int
    instructions: int
    ipc: float
    passed: bool
    note: str


def env_with_course() -> dict:
    env = os.environ.copy()
    if COURSE_BIN not in env.get("PATH", ""):
        env["PATH"] = f"{COURSE_BIN}:{env.get('PATH', '')}"
    return env


def find_vmh(name: str) -> Path | None:
    for d in (DEFAULT_VMH_DIR, UBMARK_VMH_DIR):
        p = d / name
        if p.exists():
            return p
    return None


def build_sim(proc: dict, env: dict, force: bool) -> Path | None:
    build_dir = (THIS_DIR / proc["build_dir"]).resolve()
    sim = build_dir / proc["sim_binary"]
    if force and sim.exists():
        sim.unlink()
    if not sim.exists():
        res = subprocess.run(
            ["make", proc["sim_binary"]],
            cwd=build_dir, env=env, capture_output=True, text=True,
        )
        if res.returncode != 0:
            print(f"  build failed for {proc['name']}: {res.stderr[-1000:]}")
            return None
    return sim


def run_one(sim: Path, vmh: Path, env: dict) -> tuple[int, int, bool, str]:
    res = subprocess.run(
        [str(sim), f"+exe={vmh}", "+stats=1"],
        capture_output=True, text=True, timeout=180, env=env,
    )
    out = res.stdout + res.stderr
    passed = bool(PASS_RE.search(out))
    failed = bool(FAIL_RE.search(out))
    note = "ok" if passed else ("FAILED" if failed else "no_status")
    m = STAT_RE.search(out)
    if not m:
        return -1, -1, passed, f"{note}; no stats"
    return int(m["cycles"]), int(m["inst"]), passed, note


def collect_main(processors: list[dict], benchmarks: list[dict], env: dict) -> list[Result]:
    results = []
    sims = {p["name"]: build_sim(p, env, False) for p in processors}
    for proc in processors:
        sim = sims[proc["name"]]
        if sim is None:
            continue
        print(f"=== {proc['name']} ===")
        for bm in benchmarks:
            for mode, key in (("scalar", "scalar_vmh"), ("vector", "vector_vmh")):
                if bm.get(key) is None:
                    continue
                if mode == "vector" and not proc.get("is_vector_capable", False):
                    continue
                vmh = find_vmh(bm[key])
                if vmh is None:
                    continue
                cycles, inst, passed, note = run_one(sim, vmh, env)
                ipc = inst / cycles if cycles > 0 else 0.0
                status = "PASS" if passed else "FAIL"
                print(f"  {bm['name']:<22} {mode:<6} {status} cycles={cycles:>7} inst={inst:>6} ipc={ipc:.3f}")
                results.append(Result(
                    processor=proc["name"], benchmark=bm["name"], mode=mode,
                    size=bm.get("size", 0), cycles=cycles, instructions=inst,
                    ipc=ipc, passed=passed, note=note,
                ))
    return results


def collect_scaling(
    processors: list[dict],
    sweep: dict,
    sweep_name: str,
    env: dict,
) -> list[Result]:
    results = []
    sims = {p["name"]: build_sim(p, env, False) for p in processors}
    for proc in processors:
        sim = sims[proc["name"]]
        if sim is None:
            continue
        print(f"=== {sweep_name} on {proc['name']} ===")
        for n in sweep["sizes"]:
            for mode, key in (("scalar", "scalar_vmh_template"), ("vector", "vector_vmh_template")):
                if mode == "vector" and not proc.get("is_vector_capable", False):
                    continue
                vmh_name = sweep[key].format(N=n)
                vmh = find_vmh(vmh_name)
                if vmh is None:
                    continue
                cycles, inst, passed, note = run_one(sim, vmh, env)
                ipc = inst / cycles if cycles > 0 else 0.0
                status = "PASS" if passed else "FAIL"
                print(f"  N={n:<4} {mode:<6} {status} cycles={cycles:>7} inst={inst:>6}")
                results.append(Result(
                    processor=proc["name"], benchmark=sweep_name, mode=mode,
                    size=n, cycles=cycles, instructions=inst, ipc=ipc,
                    passed=passed, note=note,
                ))
    return results


def write_csv(results: list[Result], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not results:
        path.write_text("processor,benchmark,mode,size,cycles,instructions,ipc,passed,note\n")
        return
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(asdict(results[0]).keys()))
        w.writeheader()
        for r in results:
            w.writerow(asdict(r))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--processors", nargs="*", help="restrict to these processors")
    ap.add_argument("--skip-main", action="store_true")
    ap.add_argument("--skip-scaling", action="store_true")
    args = ap.parse_args()

    bench_cfg = json.loads((THIS_DIR / "benchmarks.json").read_text())
    proc_cfg = json.loads((THIS_DIR / "processors.json").read_text())

    procs = proc_cfg["processors"]
    if args.processors:
        procs = [p for p in procs if p["name"] in set(args.processors)]
    env = env_with_course()

    results_dir = THIS_DIR / "results"
    results_dir.mkdir(exist_ok=True)

    if not args.skip_main:
        main_results = collect_main(procs, bench_cfg["benchmarks"], env)
        write_csv(main_results, results_dir / "main.csv")
        print(f"\nwrote {results_dir / 'main.csv'} ({len(main_results)} rows)\n")

    if not args.skip_scaling:
        sweeps = bench_cfg["scaling_sweeps"]
        for sweep_name, sweep_cfg in sweeps.items():
            scaling_results = collect_scaling(procs, sweep_cfg, sweep_name, env)
            write_csv(scaling_results, results_dir / f"{sweep_name}.csv")
            print(f"\nwrote {results_dir / sweep_name}.csv ({len(scaling_results)} rows)\n")

        # chain-depth study: same kernel, depths 1..6, vec-only.
        # compares riscvvec (no chain) vs riscvvec-chained.
        chain_cfg = bench_cfg.get("chain_depth_study")
        if chain_cfg:
            sims = {p["name"]: build_sim(p, env, False) for p in procs}
            chain_rows = []
            for proc in procs:
                if not proc.get("is_vector_capable", False):
                    continue
                sim = sims[proc["name"]]
                if sim is None:
                    continue
                print(f"=== chain_depth on {proc['name']} ===")
                for d in chain_cfg["depths"]:
                    vmh = find_vmh(chain_cfg["vmh_template"].format(N=d))
                    if vmh is None:
                        continue
                    cycles, inst, passed, note = run_one(sim, vmh, env)
                    ipc = inst / cycles if cycles > 0 else 0.0
                    status = "PASS" if passed else "FAIL"
                    print(f"  depth={d}  {status} cycles={cycles:>5} inst={inst:>4}")
                    chain_rows.append(Result(
                        processor=proc["name"], benchmark="chain-depth", mode="vector",
                        size=d, cycles=cycles, instructions=inst, ipc=ipc,
                        passed=passed, note=note,
                    ))
            write_csv(chain_rows, results_dir / "chain_depth.csv")
            print(f"\nwrote {results_dir / 'chain_depth.csv'} ({len(chain_rows)} rows)\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
